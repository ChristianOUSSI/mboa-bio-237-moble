import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/data/models/catalogue.dart';
import '../../core/design_system/boutons.dart';
import '../../core/design_system/carte.dart';
import '../../core/design_system/picto.dart';
import '../../core/design_system/photo.dart';
import '../../core/etat/providers.dart';
import '../../core/theme/mboa_colors.dart';
import '../../core/theme/mboa_typography.dart';
import '../../core/utils/format_monnaie.dart';
import '../../core/voice/tts_service.dart';

/// Les prix du marche.
///
/// Les prix de marche se reglent produit par produit. Ce sont les seules
/// donnees que l'admin ajuste chaque semaine, et elles ne touchent jamais
/// une commande deja figee. La marge du comptoir se lit par difference entre
/// ce prix de revente et le cout d'achat moyen glissant, elle ne se regle
/// pas ici, elle se constate.
class PrixScreen extends ConsumerWidget {
  const PrixScreen({super.key});

  /// Le pas de reglage : 50 francs. Assez fin pour suivre le marche, assez
  /// grossier pour que dix appuis suffisent a rattraper une saison.
  static const int _pas = 50;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final catalogue = ref.watch(catalogueProvider);

    return Scaffold(
      backgroundColor: MboaColors.background,
      appBar: AppBar(
        title: const Text('Prix de marché'),
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
            Text('Prix de marché par unité', style: MboaTypo.titre()),
            const SizedBox(height: 12),
            ...catalogue.maybeWhen(
              data: (entrees) => [for (final e in entrees) _LignePrix(entree: e)],
              orElse: () => [
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 32),
                  child: Center(child: CircularProgressIndicator(color: MboaColors.primary)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _LignePrix extends ConsumerWidget {
  const _LignePrix({required this.entree});

  final EntreeCatalogue entree;

  Future<void> _regler(WidgetRef ref, int delta) async {
    final nouveau = (entree.prixTendance + delta).clamp(50, 100000);
    await ref.read(depotProduitsProvider).majPrixMarche(slug: entree.slug, prix: nouveau);
    ref.invalidate(catalogueProvider);
    ref.invalidate(grilleProvider);
    await TtsService.instance
        .dire('${entree.nom} : ${formaterFcfa(nouveau)} ${entree.uniteReelle.avecArticle}');
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: CarteBio(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        child: Row(
          children: [
            PhotoProduit(chemin: '', categorie: entree.categorie, slug: entree.slug, cote: 72, libelle: entree.nom),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(entree.nom, style: MboaTypo.titre()),
                  Text(
                    '${entree.paliers.join(' · ')} ${entree.uniteReelle.pluriel}',
                    style: MboaTypo.aide(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            BoutonCarre(
              picto: Picto.minus,
              taille: 64,
              onTap: () => _regler(ref, -PrixScreen._pas),
              annonce: 'Moins cinquante francs',
            ),
            const SizedBox(width: 8),
            SizedBox(
              width: 108,
              child: Text(
                formaterFcfaCourt(entree.prixTendance),
                style: MboaTypo.chiffre(),
                textAlign: TextAlign.center,
              ),
            ),
            const SizedBox(width: 8),
            BoutonCarre(
              picto: Picto.plus,
              taille: 64,
              couleurFond: MboaColors.primary,
              couleurTrait: MboaColors.primary,
              onTap: () => _regler(ref, +PrixScreen._pas),
              annonce: 'Plus cinquante francs',
            ),
          ],
        ),
      ),
    );
  }
}
