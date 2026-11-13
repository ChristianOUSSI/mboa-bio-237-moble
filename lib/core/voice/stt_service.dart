import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:speech_to_text/speech_recognition_error.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_to_text.dart';

import '../data/models/langue.dart';

/// Dictée vocale : « Je veux cinq kilos de manioc ».
///
/// L'app ne pretend pas comprendre cette phrase. Elle transcrit, puis le
/// moteur de recherche local retrouve un produit du catalogue et un palier de
/// poids. C'est volontairement plus bête qu'un assistant : sur un marche a
/// 9 produits, retrouver le mot le plus proche suffit, et ça marche hors
/// connexion avec le moteur clavier du telephone.
class SttService extends ChangeNotifier {
  SttService._();

  static final SttService instance = SttService._();

  final SpeechToText _moteur = SpeechToText();

  bool _pret = false;
  bool _ecoute = false;
  String _transcription = '';
  String? _erreur;

  bool get estPret => _pret;
  bool get ecoute => _ecoute;
  String get transcription => _transcription;
  String? get erreur => _erreur;

  /// A appeler une fois, apres le premier appui sur le micro.
  ///
  /// L'initialisation declenche la demande de permission micro : la faire au
  /// demarrage de l'app afficherait une popup avant meme que l'utilisateur
  /// ait compris ce qu'il regardait.
  Future<bool> demarrer() async {
    if (_pret) return true;
    try {
      _pret = await _moteur.init(
        onError: (SpeechRecognitionError e) => _erreur = e.errorMsg,
        onStatus: (status) {
          if (status == 'done' || status == 'notListening') _ecoute = false;
          notifyListeners();
        },
        debug: false,
      );
    } catch (e) {
      _pret = false;
      _erreur = 'Micro indisponible';
      debugPrint('STT indisponible: $e');
    }
    notifyListeners();
    return _pret;
  }

  /// Une seule enonce, pas de dictee continue : on ecoute, on coupe, on
  /// cherche. [maximumSecondes] sert de garde-fou si le moteur ne rend pas la
  /// main sur un telephone d'entree de gamme.
  Future<String> ecouter({Langue langue = Langue.fr, int maximumSecondes = 6}) async {
    if (!await demarrer()) return '';
    _transcription = '';
    _erreur = null;
    _ecoute = true;
    notifyListeners();

    final fini = Completer<void>();
    await _moteur.listen(
      onResult: (SpeechRecognitionResult result) {
        _transcription = result.recognitionResult;
        notifyListeners();
        if (result.finalResult && !fini.isCompleted) fini.complete();
      },
      localeId: langue.slug == 'pidgin' ? 'en_US' : 'fr_FR',
      listenFor: Duration(seconds: maximumSecondes),
      pauseFor: const Duration(seconds: 2),
    );

    // Certains moteurs d'entree de gamme n'emettent jamais de resultat final :
    // on sort quand meme, sinon l'ecran reste bloque sur le micro ouvert.
    await fini.future.timeout(
      Duration(seconds: maximumSecondes + 2),
      onTimeout: () {},
    );
    await arreter();
    return _transcription.trim();
  }

  Future<void> arreter() async {
    if (_ecoute) {
      try {
        await _moteur.stop();
      } catch (_) {
        // stop sur un moteur deja arrete : sans consequence.
      }
    }
    _ecoute = false;
    notifyListeners();
  }

  void reinitialiser() {
    _transcription = '';
    _erreur = null;
    notifyListeners();
  }
}
