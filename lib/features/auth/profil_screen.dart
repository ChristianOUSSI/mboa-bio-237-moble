import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/data/depot_auth.dart';
import '../../core/data/models/langue.dart';
import '../../core/design_system/boutons.dart';
import '../../core/design_system/carte.dart';
import '../../core/design_system/picto.dart';
import '../../core/etat/providers.dart';
import '../../core/theme/mboa_colors.dart';
import '../../core/theme/mboa_typography.dart';
import '../../core/voice/tts_service.dart';

/// Les trois informations qui manquent apres le code.
///
/// Le village est une liste, pas une saisie : une personne qui ne sait pas
/// lire ne peut pas deviner comment elle doit epeler son propre village. Le
/// nom reste le seul champ clavier de toute l'app, et il n'est demande qu'une
/// fois dans la vie du compte.
///
/// La langue choisie ici ne change pas seulement les menus : elle regle le
/// debit et la langue du TTS, et elle dit a l'app quelles annonces producteur
/// elle doit savoir lire.
class ProfilScreen extends ConsumerStatefulWidget {
  const ProfilScreen({super.key});

  static const String nom = '/profil';

  @override
  ConsumerState<ProfilScreen> createState() => _ProfilScreenState();
}

class _ProfilScreenState extends ConsumerState<ProfilScreen> {
  /// Les villages d'ou part l'offre au lancement : les bassins de production
  /// reels du Ndé, des Monts de l'Ouest, du Nord et de l'Est. Un producteur
  /// d'ailleurs passe par le clavier.
  static const List<String> _villages = [
    'Mbouda',
    'Bafoussam',
    'Dschang',
    'Bamenda',
    'Foumban',
    'Batchanga',
    'Nkongsamba',
    'Bertoua',
    'Abong Mbang',
    'Yokadouma',
    'Garoua',
    'Maroua',
    'Douala',
    'Yaoundé',
  ];

  final TextEditingController _nom = TextEditingController();
  String? _village;
  Langue _langue = Langue.fr;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      TtsService.instance.dire('Comment vous appelez-vous ?');
    });
  }

  @override
  void dispose() {
    _nom.dispose();
    super.dispose();
  }

  Future<void> _enregistrer() async {
    final session = ref.read(sessionProvider);
    if (session == null) return;

    final saisi = _nom.text.trim();
    final profil = session.profil.copieAvec(
      nom: saisi.isEmpty ? session.profil.nom : saisi,
      village: _village ?? session.profil.village,
      langue: _langue,
    );

    await ref.read(sessionProvider.notifier).majProfil(profil);
    await ref.read(depotAuthProvider).memoriserLangue(_langue);

    if (!mounted) return;
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: MboaColors.background,
      appBar: AppBar(title: const Text('Qui êtes-vous ?')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
          children: [
            const _SectionLibelle('Mon nom', Picto.person),
            const SizedBox(height: 10),
            CarteBio(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: TextField(
                controller: _nom,
                style: MboaTypo.titre(),
                textCapitalization: TextCapitalization.words,
                textAlign: TextAlign.center,
                minLines: 1,
                maxLines: 2,
                decoration: const InputDecoration(
                  border: InputBorder.none,
                  hintText: 'Exemple : Mama Elise',
                  hintStyle: TextStyle(
                    color: MboaColors.textDoux,
                    fontFamily: MboaTypo.famille,
                    fontSize: 20,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 24),
            const _SectionLibelle('Mon village', Picto.map),
            const SizedBox(height: 10),
            GridView.count(
              crossAxisCount: 2,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 10,
              crossAxisSpacing: 10,
              childAspectRatio: 2.1,
              children: [
                for (final village in _villages)
                  GrosBouton(
                    titre: village,
                    picto: Picto.leaf,
                    sombre: _village == village,
                    minHeight: 72,
                    annonce: 'Village : $village',
                    onTap: () {
                      setState(() => _village = village);
                      TtsService.instance.dire('Village choisi : $village');
                    },
                  ),
              ],
            ),
            const SizedBox(height: 26),
            const _SectionLibelle('Ma langue', Picto.speaker),
            const SizedBox(height: 10),
            for (final langue in Langue.values) ...[
              GrosBouton(
                titre: langue.libelle,
                picto: Picto.speaker,
                sousTitre: langue.ttsNative ? 'Lue par l’application' : 'Voix des producteurs',
                sombre: _langue == langue,
                minHeight: 72,
                onTap: () {
                  setState(() => _langue = langue);
                  ref.read(voixProvider).definirLangue(langue);
                },
              ),
              const SizedBox(height: 10),
            ],
            if (!_langue.ttsNative) ...[
              BandeauEtat(
                texte: 'Les menus restent en français. La voix de ${_langue.libelle} '
                    'vient des producteurs eux-mêmes.',
                couleur: MboaColors.primary,
                icone: const PictoIcon(Picto.speaker, size: 30),
              ),
              const SizedBox(height: 18),
            ],
            GrosBouton(
              titre: 'Enregistrer',
              picto: Picto.check,
              sombre: _village != null,
              onTap: _village == null ? null : _enregistrer,
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionLibelle extends StatelessWidget {
  const _SectionLibelle(this.texte, this.picto);

  final String texte;
  final Picto picto;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        PictoIcon(picto, size: 30),
        const SizedBox(width: 12),
        Text(texte, style: MboaTypo.titre()),
      ],
    );
  }
}
