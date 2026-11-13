import 'dart:async';
import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as chemin;
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

/// Message vocal de 5 secondes enregistre au champ.
///
/// C'est la piece maitresse de l'accessibilite : le producteur ne tape
/// jamais, il parle, et la cliente entend sa voix avec l'accent du village.
///
/// Les trois dependances audio (`record`, `audioplayers`, `speech_to_text`)
/// sont concentrees dans ce fichier et dans stt_service.dart. Si une version
/// casse une signature, c'est ici et uniquement ici qu'il faut corriger.
class NoteVocaleService extends ChangeNotifier {
  NoteVocaleService._();

  static final NoteVocaleService instance = NoteVocaleService._();

  final AudioRecorder _micro = AudioRecorder();
  final AudioPlayer _lecteur = AudioPlayer();

  String? _chemin;
  bool _enCours = false;
  int _secondesRestantes = 0;
  String? _erreur;
  Timer? _compteur;

  bool get enCours => _enCours;
  bool get pret => _chemin != null;
  int get secondesRestantes => _secondesRestantes;
  String? get erreur => _erreur;
  String? get cheminFichier => _chemin;

  Future<bool> permission() async {
    try {
      return await _micro.hasPermission();
    } catch (e) {
      _erreur = 'Micro refuse';
      debugPrint('permission micro: $e');
      return false;
    }
  }

  /// Lance l'enregistrement et s'arrete seul au bout de [dureeSecondes].
  ///
  /// L'arret automatique n'est pas du confort : un producteur qui oublie le
  /// telephone ouvert sur son tas remplit la base de silence de dix minutes.
  Future<void> enregistrer({int dureeSecondes = 5}) async {
    _erreur = null;
    if (!await permission()) {
      notifyListeners();
      return;
    }

    final repertoire = await getTemporaryDirectory();
    final fichier = chemin.join(
      repertoire.path,
      'note_${DateTime.now().millisecondsSinceEpoch}.m4a',
    );

    try {
      await _micro.start(path: fichier, encoder: AudioEncoder.aacLc, bitRate: 64000);
      _chemin = fichier;
      _enCours = true;
      _secondesRestantes = dureeSecondes;
      notifyListeners();

      _compteur = Timer.periodic(const Duration(seconds: 1), (t) async {
        _secondesRestantes -= 1;
        if (_secondesRestantes <= 0) {
          t.cancel();
          await couper();
          return;
        }
        notifyListeners();
      });
    } catch (e) {
      _enCours = false;
      _erreur = 'Enregistrement impossible';
      debugPrint('start note vocale: $e');
      notifyListeners();
    }
  }

  /// Arrete et renvoie le fichier local, ou null si rien n'a ete dit.
  Future<String?> couper() async {
    _compteur?.cancel();
    _compteur = null;
    if (!_enCours) return _chemin;
    _enCours = false;
    try {
      final arrete = await _micro.stop();
      _chemin = arrete ?? _chemin;
    } catch (e) {
      _erreur = 'Arrêt impossible';
      debugPrint('stop note vocale: $e');
    }
    _secondesRestantes = 0;
    notifyListeners();
    return _chemin;
  }

  /// Ecoute locale, puis ecoute distante : l'appelant ne sait pas toujours
  /// si l'audio est deja sur le telephone ou non.
  Future<void> lire(String urlOuChemin) async {
    if (urlOuChemin.isEmpty) return;
    try {
      await _lecteur.stop();
      if (urlOuChemin.startsWith('http')) {
        await _lecteur.play(UrlSource(urlOuChemin));
      } else if (await File(urlOuChemin).exists()) {
        await _lecteur.play(DeviceFileSource(urlOuChemin));
      } else {
        _erreur = 'Audio non reçu';
        notifyListeners();
      }
    } catch (e) {
      _erreur = 'Lecture impossible';
      debugPrint('lecture audio: $e');
      notifyListeners();
    }
  }

  Future<void> arreterLecture() async {
    try {
      await _lecteur.stop();
    } catch (_) {
      // deja arrete
    }
  }

  void jeter() {
    _chemin = null;
    notifyListeners();
  }

  /// Copie la note dans le repertoire persistant : le dossier temporaire
  /// d'Android est vide par le systeme, et une note non envoyee doit survivre
  /// a une nuit sans reseau.
  Future<String?> persister(String identifiant) async {
    final source = _chemin;
    if (source == null) return null;
    final fichier = File(source);
    if (!await fichier.exists()) return null;

    final appui = await getApplicationDocumentsDirectory();
    final repertoire = Directory(chemin.join(appui.path, 'notes'));
    if (!await repertoire.exists()) await repertoire.create(recursive: true);

    final destination = File(chemin.join(repertoire.path, '$identifiant.m4a'));
    await fichier.copy(destination.path);
    return destination.path;
  }

  @override
  void dispose() {
    _compteur?.cancel();
    _micro.dispose().catchError((_) {});
    _lecteur.dispose().catchError((_) {});
    super.dispose();
  }
}
