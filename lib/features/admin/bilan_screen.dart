import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/data/models/statuts.dart';
import '../../core/design_system/boutons.dart';
import '../../core/design_system/carte.dart';
import '../../core/design_system/picto.dart';
import '../../core/etat/providers.dart';
import '../../core/theme/mboa_colors.dart';
import '../../core/theme/mboa_typography.dart';
import '../../core/utils/format_monnaie.dart';
import '../../core/voice/tts_service.dart';

/// Le bilan d'une journee de comptoir.
///
/// Quatre chiffres, dans l'ordre ou l'admin les regarde le matin : ce qui
/// attend, ce qui est en stock, ce qui est en litige, ce qui s'est vendu.
///
/// Cet ecran est le seul de l'app admin ou le texte est permis : un
/// gestionnaire de 28 ans a Douala sait lire un tableau. Les regles
/// d'accessibilite strictes s'appliquent aux deux apps villageoises, pas a
/// l'outil de travail interne.
class BilanScreen extends ConsumerWidget {
  const BilanScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      backgroundColor: MboaColors.background,
      appBar: AppBar(
        title: const Text('Bilan du jour'),
        leading: IconButton(
          onPressed: () => Navigator.of(context).pop(),
          tooltip: 'Retour',
          iconSize: 36,
          icon: const PictoIcon(Picto.back, size: 36, couleur: MboaColors.surface),
        ),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(18, 16, 18, 26),
          children: [
            const _Chiffres(),
            const SizedBox(height: 20),
            GrosBouton(
              titre: 'Écouter le bilan',
              picto: Picto.speaker,
              sombre: true,
              onTap: () => TtsService.instance.dire(
                'Bilan. Les chiffres du jour sont affichés à l écran.',
              ),
            ),
            const SizedBox(height: 18),
            const BandeauEtat(
              texte:
                  'Le detail par village reste sur la carte : '
                  'un tableau ne dit pas ou est le probleme.',
              couleur: MboaColors.primary,
              icone: PictoIcon(Picto.map, size: 30),
            ),
          ],
        ),
      ),
    );
  }
}

class _Chiffres extends ConsumerWidget {
  const _Chiffres();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final commandes = ref.watch(commandesAdminProvider).valueOrNull ?? const [];
    final aValider = commandes.where((c) => c.statut == StatutCommande.nouvelle).length;
    final litiges = ref.watch(relancesProvider).valueOrNull?.length ?? 0;
    final ventes = commandes;

    // Le chiffre d'affaires est l'argent reellement passe a la porte, pas la
    // somme des paniers demandes. Compter montantTotal gonflerait le bilan de
    // tout ce que les clientes ont refuse a la livraison.
    final soldees = ventes.where((c) => c.clos).toList();
    final chiffreAffaires =
        soldees.fold(0, (somme, c) => somme + (c.montantLivre ?? 0));

    // La marge du comptoir : ce qu'il a vraiment gagne, apres cout d'achat.
    final marge = soldees.fold(0, (somme, c) => somme + c.marge);

    // Les paniers refuses font partie du bilan, pas des stats cachees : c'est
    // le seul indicateur qui dit a Mboa si les prix sont bien calibres.
    final repondues = ventes.where((c) => c.satisfaction != null).toList();
    final accepts = repondues.where((c) => c.satisfaction?.estBon ?? false).length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Ligne(
          picto: Picto.clock,
          libelle: 'Devis à valider',
          valeur: '$aValider',
          accentuer: aValider > 0,
        ),
        _Ligne(
          picto: Picto.alert,
          libelle: 'Livraisons sans réponse',
          valeur: '$litiges',
          couleur: litiges > 0 ? MboaColors.error : null,
        ),
        CarteBio(
          couleurFond: MboaColors.primary,
          couleurTrait: MboaColors.primary,
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
          child: Row(
            children: [
              const PictoIcon(Picto.money, size: 40, couleur: MboaColors.surface),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  'Ventes confirmées',
                  style: MboaTypo.titre(couleur: MboaColors.surface),
                ),
              ),
              Text(
                formaterFcfaCourt(chiffreAffaires),
                style: MboaTypo.chiffreGeant(couleur: MboaColors.surface),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        CarteBio(
          couleurFond: MboaColors.secondaryDoux,
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
          child: Row(
            children: [
              const PictoIcon(Picto.leaf, size: 34, couleur: MboaColors.primary),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  'Marge du comptoir',
                  style: MboaTypo.corps(couleur: MboaColors.primary),
                ),
              ),
              Text(
                formaterFcfaCourt(marge),
                style: MboaTypo.chiffre(couleur: MboaColors.primary),
              ),
            ],
          ),
        ),
        if (repondues.isNotEmpty) ...[
          const SizedBox(height: 8),
          CarteBio(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
            child: Row(
              children: [
                const PictoIcon(Picto.pouceLeve, size: 30, couleur: MboaColors.primary),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Paniers acceptés : $accepts sur ${repondues.length}',
                    style: MboaTypo.corps(),
                  ),
                ),
                Text(
                  '${(accepts * 100 / repondues.length).round()} %',
                  style: MboaTypo.chiffre(couleur: MboaColors.secondary),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class _Ligne extends StatelessWidget {
  const _Ligne({
    required this.picto,
    required this.libelle,
    required this.valeur,
    this.couleur,
    this.accentuer = false,
  });

  final Picto picto;
  final String libelle;
  final String valeur;
  final Color? couleur;
  final bool accentuer;

  @override
  Widget build(BuildContext context) {
    final teinte = couleur ?? MboaColors.primary;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: CarteBio(
        couleurFond: accentuer ? MboaColors.secondaryDoux : MboaColors.surface,
        child: Row(
          children: [
            PictoIcon(picto, size: 34, couleur: teinte),
            const SizedBox(width: 14),
            Expanded(child: Text(libelle, style: MboaTypo.corps())),
            Text(valeur, style: MboaTypo.chiffre(couleur: teinte)),
          ],
        ),
      ),
    );
  }
}
