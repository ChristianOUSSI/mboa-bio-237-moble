import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/data/models/produit.dart';
import '../../core/design_system/boutons.dart';
import '../../core/design_system/carte.dart';
import '../../core/design_system/jauge.dart';
import '../../core/design_system/picto.dart';
import '../../core/design_system/photo.dart';
import '../../core/etat/providers.dart';
import '../../core/theme/mboa_colors.dart';
import '../../core/theme/mboa_typography.dart';
import '../../core/utils/format_monnaie.dart';

/// Le stock du comptoir, en lecture seule pour le producteur.
///
/// Il lit la vitrine publique, la meme que la cliente, et pas la table
/// `produits` : celle-ci est reservee au comptoir, parce qu'elle porte le
/// prix d'achat. Un producteur qui interrogerait la table n'obtiendrait rien
/// et l'ecran resterait vide sans qu'on sache pourquoi.
///
/// Il voit donc ce qui reste au comptoir et le prix de revente, qui est
/// public. Il ne voit ni le cout d'achat moyen, ni la marge, et il ne touche
/// a aucun prix : la marchandise ne lui appartient plus.
class StockScreen extends ConsumerWidget {
  const StockScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stock = ref.watch(vitrineProvider(null));

    return Scaffold(
      backgroundColor: MboaColors.background,
      appBar: AppBar(
        title: const Text('Stock du comptoir'),
        leading: IconButton(
          onPressed: () => Navigator.of(context).pop(),
          tooltip: 'Retour',
          iconSize: 36,
          icon: const PictoIcon(Picto.back, size: 36, couleur: MboaColors.surface),
        ),
      ),
      body: SafeArea(
        child: stock.maybeWhen(
          data: (liste) {
            if (liste.isEmpty) {
              return Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const PictoIcon(Picto.basket, size: 96),
                    const SizedBox(height: 18),
                    Text('Rien au comptoir', style: MboaTypo.titre()),
                    const SizedBox(height: 10),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 40),
                      child: Text(
                        'Les produits apparaissent ici dès qu\'un achat est validé',
                        style: MboaTypo.aide(couleur: MboaColors.text),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ],
                ),
              );
            }

            return ListView.separated(
              padding: const EdgeInsets.fromLTRB(18, 16, 18, 28),
              itemCount: liste.length,
              separatorBuilder: (context, index) => const SizedBox(height: 14),
              itemBuilder: (context, index) => _TuileStock(produit: liste[index]),
            );
          },
          orElse: () => const Center(
            child: CircularProgressIndicator(color: MboaColors.primary),
          ),
        ),
      ),
    );
  }
}

class _TuileStock extends StatelessWidget {
  const _TuileStock({required this.produit});

  final Produit produit;

  @override
  Widget build(BuildContext context) {
    final vide = produit.quantite <= 0;

    return CarteBio(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              PhotoProduit(
                chemin: produit.photo,
                categorie: produit.categorie,
                slug: produit.slug,
                libelle: produit.nom,
                cote: 92,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(produit.nom, style: MboaTypo.titre()),
                    const SizedBox(height: 4),
                    _EtatVente(rupture: vide),
                  ],
                ),
              ),
              BoutonVoix(texte: produit.annonceVocale),
            ],
          ),
          const SizedBox(height: 14),
          JaugeStock(ratio: produit.jauge, quasiVide: vide),
          const SizedBox(height: 10),
          Center(
            child: ChiffreUnite(
              valeur: formaterKg(produit.quantite),
              unite: produit.uniteReelle.pour(produit.quantite),
              geant: true,
              couleur: vide ? MboaColors.error : MboaColors.primary,
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              const PictoIcon(Picto.priceTag, size: 32),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  produit.prixLabel,
                  style: MboaTypo.corps(couleur: MboaColors.text),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// La pastille d'etat : disponible ou en rupture.
class _EtatVente extends StatelessWidget {
  const _EtatVente({required this.rupture});

  final bool rupture;

  @override
  Widget build(BuildContext context) {
    final (couleur, picto, texte) = rupture
        ? (MboaColors.errorDoux, Picto.alert, 'Rupture')
        : (MboaColors.secondaryDoux, Picto.check, 'Disponible');

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: couleur,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          PictoIcon(picto, size: 22, couleur: MboaColors.text),
          const SizedBox(width: 8),
          Text(texte, style: MboaTypo.aide(couleur: MboaColors.text)),
        ],
      ),
    );
  }
}
