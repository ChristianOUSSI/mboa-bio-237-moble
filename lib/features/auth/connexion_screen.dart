import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/config/app_env.dart';
import '../../core/config/app_role.dart';
import '../../core/data/depot_auth.dart';
import '../../core/design_system/boutons.dart';
import '../../core/design_system/carte.dart';
import '../../core/design_system/picto.dart';
import '../../core/design_system/photo.dart';
import '../../core/etat/providers.dart';
import '../../core/theme/mboa_colors.dart';
import '../../core/theme/mboa_typography.dart';
import '../../core/voice/tts_service.dart';
import 'otp_vocal_screen.dart';
import 'pave_numerique.dart';

/// Connexion en trois etapes, sans mot de passe et sans savoir lire.
///
///   1. le numero, tape sur le pave numerique geant ;
///   2. la photo du visage, qui sert de reconnaissance visuelle et non de
///      biometrie (voir la doc de DepotAuth) ;
///   3. le code a 4 chiffres, annonce par la voix puis recompose.
///
/// Le role n'est jamais demande ici : c'est le flavor du build qui l'impose,
/// et la base qui le confirme. Un producteur qui ouvrirait par erreur l'app
/// cliente est renvoye vers la sienne par l'ecran de garde.
class ConnexionScreen extends ConsumerStatefulWidget {
  const ConnexionScreen({super.key});

  static const String nom = '/connexion';

  @override
  ConsumerState<ConnexionScreen> createState() => _ConnexionScreenState();
}

class _ConnexionScreenState extends ConsumerState<ConnexionScreen> {
  /// Les deux seules etapes tenues par cet ecran : le code est un ecran a
  /// part entiere, il merite son propre rythme vocal.
  static const int _etapeNumero = 0;
  static const int _etapeVisage = 1;

  int _etape = _etapeNumero;
  String _numero = '';
  Uint8List? _visageOctets;
  String? _visageChemin;
  OtpDemande? _demande;
  String? _erreur;
  bool _occupee = false;

  AppRole get _role => AppEnv.role;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      TtsService.instance
          .dire('Bienvenue dans ${_role.appName}. Tapez votre numéro de téléphone.');
    });
  }

  void _touche(String chiffre) {
    if (_numero.length >= 9) return;
    setState(() {
      _numero += chiffre;
      _erreur = null;
    });
  }

  void _effacer() {
    if (_numero.isEmpty) return;
    setState(() => _numero = _numero.substring(0, _numero.length - 1));
  }

  Future<void> _numeroValide() async {
    setState(() => _occupee = true);
    try {
      final demande = await ref.read(depotAuthProvider).demanderCode(_numero, role: _role);
      if (!mounted) return;
      setState(() {
        _demande = demande;
        _etape = _etapeVisage;
      });
      await TtsService.instance.dire('Très bien. Prenez maintenant votre photo de visage.');
    } on AuthException catch (e) {
      if (!mounted) return;
      setState(() => _erreur = e.message);
      await TtsService.instance.dire(e.message ?? 'Numéro incorrect');
    } finally {
      if (mounted) setState(() => _occupee = false);
    }
  }

  Future<void> _prendreVisage() async {
    try {
      final prise = await ImagePicker().pickImage(
        source: ImageSource.camera,
        preferredCameraDevice: CameraDevice.front,
        maxWidth: 720,
        imageQuality: 70,
      );
      if (prise == null) return;

      final octets = await File(prise.path).readAsBytes();
      if (!mounted) return;
      setState(() {
        _visageOctets = octets;
        _visageChemin = prise.path;
        _erreur = null;
      });
      await TtsService.instance.dire('C’est vous. Appuyez sur suivant.');
    } catch (e) {
      if (!mounted) return;
      setState(() => _erreur = 'La caméra est indisponible');
      await TtsService.instance.dire('La caméra est indisponible');
    }
  }

  void _verserCode() {
    final demande = _demande;
    if (demande == null) return;

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => OtpVocalScreen(
          demande: demande,
          visageOctets: _visageOctets,
          role: _role,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: MboaColors.background,
      appBar: AppBar(
        title: Text(_role.appName),
        leading: _etape == _etapeNumero
            ? null
            : IconButton(
                onPressed: () => setState(() => _etape = _etapeNumero),
                tooltip: 'Retour',
                iconSize: 36,
                icon: const PictoIcon(Picto.back, size: 36, couleur: MboaColors.surface),
              ),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _PisteEtapes(index: _etape),
              const SizedBox(height: 22),
              Expanded(child: _corps()),
              if (_erreur != null) ...[
                const SizedBox(height: 14),
                BandeauEtat(
                  texte: _erreur!,
                  couleur: MboaColors.error,
                  icone: const PictoIcon(Picto.alert, size: 30, couleur: MboaColors.error),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _corps() {
    if (_occupee) {
      return const Center(child: CircularProgressIndicator(color: MboaColors.primary));
    }

    if (_etape == _etapeNumero) {
      return Column(
        children: [
          _AfficheNumero(numero: _numero),
          const SizedBox(height: 18),
          Expanded(
            child: PaveNumerique(
              onTouche: _touche,
              effacer: _numero.isEmpty ? null : _effacer,
              valider: _numero.length < 9 ? null : _numeroValide,
              titre: 'Votre numéro',
            ),
          ),
        ],
      );
    }

    return Column(
      children: [
        const _PisteEtapes(index: 1),
        const SizedBox(height: 22),
        Center(
          child: PhotoRonde(
            chemin: _visageChemin ?? '',
            cote: 168,
            couleurLiseret: _visageOctets == null ? MboaColors.trait : MboaColors.primary,
          ),
        ),
        const SizedBox(height: 20),
        GrosBouton(
          titre: 'Prendre ma photo',
          picto: Picto.camera,
          sousTitre: _visageOctets == null ? 'Face à la caméra' : 'Photo prise',
          sombre: _visageOctets == null,
          onTap: _prendreVisage,
        ),
        const Spacer(),
        GrosBouton(
          titre: 'Suivant',
          picto: Picto.check,
          sombre: _visageOctets != null,
          onTap: _visageOctets == null ? null : _verserCode,
        ),
      ],
    );
  }
}

/// Les trois pistes de progression : numero, visage, code.
///
/// Les longueurs sont volontairement inegales. Le numero est la partie la
/// plus longue a saisir, le visage se prend en trois secondes : une progression
/// reguliere ferait croire que les deux coutent le meme effort.
class _PisteEtapes extends StatelessWidget {
  const _PisteEtapes({required this.index});

  final int index;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (var i = 0; i < 3; i++)
          Expanded(
            flex: i == 0 ? 5 : (i == 1 ? 3 : 4),
            child: Padding(
              padding: EdgeInsets.only(right: i == 2 ? 0 : 8),
              child: Container(
                height: 14,
                decoration: BoxDecoration(
                  color: i < index
                      ? MboaColors.primary
                      : (i == index ? MboaColors.secondary : MboaColors.primaryDoux),
                  borderRadius: BorderRadius.circular(7),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// Le numero en cours, en chiffres geants groupe par trois.
class _AfficheNumero extends StatelessWidget {
  const _AfficheNumero({required this.numero});

  final String numero;

  @override
  Widget build(BuildContext context) {
    final groupes = <String>[];
    for (var i = 0; i < numero.length; i += 3) {
      groupes.add(numero.substring(i, (i + 3).clamp(0, numero.length)));
    }

    return CarteBio(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 20),
      child: Column(
        children: [
          Text(
            '+237 ${groupes.isEmpty ? '' : groupes.join(' ')}',
            style: MboaTypo.chiffreGeant(
              couleur: numero.isEmpty ? MboaColors.textDoux : MboaColors.primary,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            numero.isEmpty ? 'Neuf chiffres, en commençant par 6' : '${numero.length} sur 9',
            style: MboaTypo.aide(),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
