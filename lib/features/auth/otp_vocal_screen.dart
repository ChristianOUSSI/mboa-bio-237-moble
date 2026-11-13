import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/config/app_env.dart';
import '../../core/config/app_role.dart';
import '../../core/data/depot_auth.dart';
import '../../core/data/models/profil.dart';
import '../../core/design_system/boutons.dart';
import '../../core/design_system/carte.dart';
import '../../core/design_system/picto.dart';
import '../../core/design_system/photo.dart';
import '../../core/etat/providers.dart';
import '../../core/theme/mboa_colors.dart';
import '../../core/theme/mboa_typography.dart';
import '../../core/voice/tts_service.dart';
import '../admin/tableau_admin_screen.dart';
import '../consommateur/marche_screen.dart';
import '../fournisseur/accueil_fournisseur_screen.dart';
import '../livreur/accueil_livreur_screen.dart';
import 'pave_numerique.dart';
import 'profil_screen.dart';

/// L'etape du code a quatre chiffres, dit a voix haute.
///
/// Le code n'est pas une formalite : c'est le seul moment ou l'app prouve que
/// la personne tient le telephone qui a recu le message. En canal SMS, le code
/// arrive par SMS et l'app ne l'a jamais. En canal voix, l'app le genere, le
/// lit chiffre par chiffre, et le redemande : celui qui a entendu « un, deux,
/// trois, quatre » et sait les recomposer a demonstre qu'il est la.
///
/// Les quatre tuiles de rappel ne sont pas une decoration. Elles restent
/// allumees pendant la saisie, pour qu'on puisse reecouter sans se presser.
class OtpVocalScreen extends ConsumerStatefulWidget {
  const OtpVocalScreen({
    required this.demande,
    required this.role,
    this.visageOctets,
    super.key,
  });

  final OtpDemande demande;
  final AppRole role;
  final Uint8List? visageOctets;

  @override
  ConsumerState<OtpVocalScreen> createState() => _OtpVocalScreenState();
}

class _OtpVocalScreenState extends ConsumerState<OtpVocalScreen> {
  final List<String> _saisie = [];
  String? _erreur;
  bool _occupee = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _lireCode());
  }

  Future<void> _lireCode() async {
    final demande = widget.demande;
    if (demande.codeConnu) {
      await TtsService.instance.dire('Votre code est ${demande.code!.split('').join(', ')}');
      return;
    }
    await TtsService.instance
        .dire('Un message arrive sur votre téléphone. Tapez les quatre chiffres du message.');
  }

  void _touche(String chiffre) {
    if (_saisie.length >= AppEnv.otpChiffres) return;
    setState(() {
      _saisie.add(chiffre);
      _erreur = null;
    });
    if (_saisie.length == AppEnv.otpChiffres) _valider();
  }

  void _effacer() {
    if (_saisie.isEmpty) return;
    setState(() => _saisie.removeLast());
  }

  Future<void> _valider() async {
    setState(() => _occupee = true);
    try {
      final profil = await ref.read(depotAuthProvider).validerCode(
            telephone: widget.demande.telephone,
            code: _saisie.join(),
            role: widget.role,
            photoVisageOctets: widget.visageOctets,
          );

      if (!mounted) return;
      await ref.read(sessionProvider.notifier).basculer(profil);
      await _suite(profil);
    } on AuthException catch (e) {
      if (!mounted) return;
      setState(() {
        _erreur = e.message;
        _saisie.clear();
      });
      await TtsService.instance.dire('Ce code ne convient pas. Réécoutez.');
      await _lireCode();
    } catch (e) {
      if (!mounted) return;
      setState(() => _erreur = 'Le serveur ne répond pas');
      await TtsService.instance.dire('Le serveur ne répond pas. Réessayez.');
    } finally {
      if (mounted) setState(() => _occupee = false);
    }
  }

  /// Un compte deja complete part directement a son accueil ; un compte
  /// fraichement cree doit d'abord se doter d'un nom, d'un village et d'une
  /// langue.
  Future<void> _suite(Profil profil) async {
    final aComplete = profil.nom.trim().isNotEmpty &&
        profil.nom.trim().toUpperCase() != 'NOUVEAU' &&
        profil.village.trim().toUpperCase() != 'INCONNU';

    if (!aComplete) {
      await Navigator.of(context).push(MaterialPageRoute(
        builder: (context) => const ProfilScreen(),
      ));
      if (!mounted) return;
    }

    Navigator.of(context).pushNamedAndRemoveUntil(_racine(widget.role), (route) => false);
  }

  static String _racine(AppRole role) => switch (role) {
        AppRole.fournisseur => AccueilFournisseurScreen.nom,
        AppRole.admin => TableauAdminScreen.nom,
        AppRole.consommateur => MarcheScreen.nom,
        AppRole.livreur => AccueilLivreurScreen.nom,
      };

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: MboaColors.background,
      appBar: AppBar(
        title: const Text('Votre code'),
        leading: IconButton(
          onPressed: () => Navigator.of(context).pop(),
          tooltip: 'Retour',
          iconSize: 36,
          icon: const PictoIcon(Picto.back, size: 36, couleur: MboaColors.surface),
        ),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 24),
          child: _occupee
              ? const Center(child: CircularProgressIndicator(color: MboaColors.primary))
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    CarteBio(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              for (var i = 0; i < AppEnv.otpChiffres; i++)
                                Padding(
                                  padding: EdgeInsets.only(right: i == AppEnv.otpChiffres - 1 ? 0 : 14),
                                  child: _Tuile(
                                    valeur: i < _saisie.length ? _saisie[i] : '',
                                    attendu: code != null && i < code.length ? code[i] : '',
                                  ),
                                ),
                            ],
                          ),
                          const SizedBox(height: 14),
                          GrosBouton(
                            titre: 'Réécouter',
                            picto: Picto.speaker,
                            secondaire: true,
                            onTap: _lireCode,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    Expanded(
                      child: PaveNumerique(
                        onTouche: _touche,
                        effacer: _saisie.isEmpty ? null : _effacer,
                        valider: _saisie.length < AppEnv.otpChiffres ? null : _valider,
                      ),
                    ),
                    if (_erreur != null) ...[
                      const SizedBox(height: 12),
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
}

/// Une case du code.
///
/// Aucune case n'affiche le chiffre attendu : la voix seule le donne. Afficher
/// la reponse transformerait la saisie en copiage, et le code ne prouverait
/// plus rien du tout.
class _Tuile extends StatelessWidget {
  const _Tuile({required this.valeur});

  final String valeur;

  @override
  Widget build(BuildContext context) {
    final remplie = valeur.isNotEmpty;

    return Container(
      width: 72,
      height: 84,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: remplie ? MboaColors.primary : MboaColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: MboaColors.primary, width: 3),
      ),
      child: Text(
        valeur,
        style: MboaTypo.chiffre(couleur: remplie ? MboaColors.surface : MboaColors.textDoux),
      ),
    );
  }
}
