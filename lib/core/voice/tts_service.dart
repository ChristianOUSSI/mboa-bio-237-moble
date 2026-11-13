import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';

import '../data/models/langue.dart';

/// Lecture a haute voix de tous les libelles de l'app.
///
/// Singleton assume : le moteur TTS est une ressource systeme unique, le
/// noyer dans Riverpod n'apporte rien. Seule l'etat visible (langue, mode
/// muet) passe par un ChangeNotifier, pour que l'ecran reglages se rafraichisse.
///
/// Sur un Tecno sans Google TTS installe, `flutter_tts` leve une exception des
/// le premier appel : l'app ne doit jamais en mourir, l'utilisateur entendra
/// simplement le silence et lira les gros caracteres. C'est le `echoue`
/// ci-dessous, et c'est la raison pour laquelle chaque ecran reste autonome
/// sans la voix.
class TtsService extends ChangeNotifier {
  TtsService._();

  static final TtsService instance = TtsService._();

  final FlutterTts _tts = FlutterTts();

  Langue _langue = Langue.fr;
  bool _pret = false;
  bool _muet = false;

  /// Vitesse ralentie : 0.42 pour environ 130 mots/minute, le debit conseille
  /// pour une personne agee qui decouvre l'ecran.
  static const double _debit = 0.42;

  Langue get langue => _langue;
  bool get estPret => _pret;
  bool get estMuet => _muet;

  Future<void> demarrer() async {
    try {
      await _tts.awaitSpeakCompletion(true);
      await _tts.setVolume(1.0);
      await _tts.setPitch(0.95);
      await _tts.setSpeechRate(_debit);
      await _tts.setLanguage(_langue.codeTts);
      _pret = true;
    } catch (e) {
      _pret = false;
      debugPrint('TTS indisponible: $e');
    }
    notifyListeners();
  }

  Future<void> definirLangue(Langue nouvelle) async {
    _langue = nouvelle;
    if (_pret) {
      try {
        await _tts.setLanguage(nouvelle.codeTts);
      } catch (_) {
        // Le code langue peut etre refuse sur certains moteurs : on garde la
        // langue precedente sans prevenir l'utilisateur, le texte suffit.
      }
    }
    notifyListeners();
  }

  Future<void> couperVoix() async {
    _muet = !_muet;
    if (_muet) await arreter();
    notifyListeners();
  }

  /// Interrompt ce qui est en cours puis lit [texte].
  ///
  /// `interrupt` est vrai par defaut : deux phrases qui se chevauchent
  /// rendent l'app incomprehensible, et l'utilisateur age ne sait pas
  /// annuler un audio.
  Future<void> dire(String texte, {bool interrupt = true}) async {
    if (_muet || texte.trim().isEmpty || !_pret) return;
    try {
      if (interrupt) await _tts.stop();
      await _tts.speak(texte);
    } catch (_) {
      _pret = false;
      notifyListeners();
    }
  }

  /// « Un, deux, trois, quatre » : l'OTP est enonce chiffre par chiffre avec
  /// une virgule, que le moteur marque par une vraie pause.
  Future<void> direCode(String code) => dire(code.split('').join(', '));

  Future<void> direChiffre(int nombre) => dire(nombre.toString());

  Future<void> arreter() async {
    if (!_pret) return;
    try {
      await _tts.stop();
    } catch (_) {
      // Un stop sur un moteur deja arrete leve parfois une erreur : sans effet.
    }
  }

  @override
  void dispose() {
    if (_pret) {
      _tts.stop().catchError((_) {});
    }
    super.dispose();
  }
}
