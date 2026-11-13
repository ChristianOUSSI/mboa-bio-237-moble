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
import '../../core/voice/tts_service.dart';

/// Le stock du comptoir vu par celui qui l'achete et le revend.
///
/// Deux prix par fiche, et une marge entre les deux. C'est le seul ecran ou
/// la marge a le droit d'apparaitre : la cliente ne la voit jamais, le
/// producteur non plus. Une fiche qui se vend moins qu'elle n'a coute passe
/// en rouge, avant la premiere vente a perte.
///
/// La quantite ne se touche pas ici. Elle entre par la signature d'un achat
/// et sort par la validation d'un devis, jamais par un champ.
class StockAdminScreen extends ConsumerWidget {
  const StockAdminScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stock = ref.watch(stockProvider);

    return Scaffold(
      backgroundColor: MboaColors.background,
      appBar: AppBar(
        title: const Text('Stock et marges'),
        leading: IconButton(
          onPressed: () => Navigator.of(context).pop(),
          tooltip: 'Retour',
          iconSize: 36,
          icon: const PictoIcon(Picto.back, size: 36, couleur: MboaColors.surface),
        ),
        actions: [
          IconButton(
            onPressed: () => ref.invalidate(stockProvider),
            tooltip: 'Rafraîchir',
            iconSize: 34,
            icon: const PictoIcon(Picto.sync, size: 34, couleur: MboaColors.surface),
          ),
        ],
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
                    Text('Stock vide', style: MboaTypo.titre()),
                    const SizedBox(height: 10),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 40),
                      child: Text(
                        'Signe un achat de récolte : la marchandise entrera ici',
                        style: MboaTypo.aide(couleur: MboaColors.text),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ],
                ),
              );
            }

            return ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 28),
              itemCount: liste.length,
              separatorBuilder: (context, index) => const SizedBox(height: 14),
              itemBuilder: (context, index) => _FicheStock(
                key: ValueKey(liste[index].id),
                produit: liste[index],
              ),
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

class _FicheStock extends ConsumerWidget {
  const _FicheStock({required this.produit, super.key});

  final Produit produit;

  Future<void> _prix(WidgetRef ref, int delta) async {
    final nouveau = (produit.prix + delta).clamp(50, 1000000);
    await ref.read(depotProduitsProvider).ajusterPrix(id: produit.id, prix: nouveau);
    ref.invalidate(stockProvider);
    ref.invalidate(vitrineProvider(null));
    await TtsService.instance.dire(
      '${produit.nom} à ${formaterFcfa(nouveau)} ${produit.uniteReelle.avecArticle}',
    );
  }

  Future<void> _basculer(WidgetRef ref) async {
    final actif = !produit.actif;
    await ref.read(depotProduitsProvider).basculerActif(id: produit.id, actif: actif);
    ref.invalidate(stockProvider);
    ref.invalidate(vitrineProvider(null));
    await TtsService.instance.dire(
      actif ? '${produit.nom} remis en vente' : '${produit.nom} retiré de la vitrine',
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final vide = produit.quantite <= 0;
    final marge = produit.margeUnitaire;
    final aPerte = marge != null && marge < 0;

    return CarteBio(
      couleurTrait: aPerte ? MboaColors.error : MboaColors.trait,
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
                    _Pastille(
                      texte: produit.actif ? (vide ? 'Épuisé' : 'En vente') : 'Retiré',
                      picto: produit.actif ? (vide ? Picto.alert : Picto.check) : Picto.close,
                      fond: produit.actif
                          ? (vide ? MboaColors.errorDoux : MboaColors.secondaryDoux)
                          : MboaColors.primaryDoux,
                    ),
                  ],
                ),
              ),
              BoutonVoix(texte: produit.annonceVocale),
            ],
          ),
          const SizedBox(height: 12),
          JaugeStock(ratio: produit.jauge, quasiVide: vide),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: Center(
                  child: ChiffreUnite(
                    valeur: formaterKg(produit.quantite),
                    unite: produit.uniteReelle.pour(produit.quantite),
                    geant: true,
                    couleur: vide ? MboaColors.error : MboaColors.primary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (marge != null)
            CarteBio(
              couleurFond: aPerte ? MboaColors.errorDoux : MboaColors.secondaryDoux,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              child: Row(
                children: [
                  PictoIcon(
                    aPerte ? Picto.alert : Picto.money,
                    size: 32,
                    couleur: aPerte ? MboaColors.error : MboaColors.primary,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Acheté ${formaterFcfaCourt(produit.prixAchat ?? 0)} · '
                          'vendu ${formaterFcfaCourt(produit.prix)}',
                          style: MboaTypo.aide(couleur: MboaColors.text),
                        ),
                        Text(
                          'Marge ${formaterFcfaCourt(marge)} ${produit.uniteReelle.avecArticle}'
                          '${produit.margePct == null ? '' : ' (${produit.margePct} %)'}',
                          style: MboaTypo.corps(
                            couleur: aPerte ? MboaColors.error : MboaColors.primary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            )
          else
            Text(
              'Aucun achat signé pour cette fiche : le coût reste inconnu.',
              style: MboaTypo.aide(couleur: MboaColors.textDoux),
            ),
          const SizedBox(height: 12),
          Row(
            children: [
              const PictoIcon(Picto.priceTag, size: 32),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  produit.prixLabel,
                  style: MboaTypo.chiffre(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              BoutonCarre(
                picto: Picto.minus,
                taille: 68,
                onTap: () => _prix(ref, -50),
                annonce: 'Moins cinquante francs',
              ),
              const SizedBox(width: 8),
              BoutonCarre(
                picto: Picto.plus,
                taille: 68,
                couleurFond: MboaColors.primary,
                couleurTrait: MboaColors.primary,
                onTap: () => _prix(ref, 50),
                annonce: 'Plus cinquante francs',
              ),
            ],
          ),
          const SizedBox(height: 12),
          GrosBouton(
            titre: produit.actif ? 'Retirer de la vitrine' : 'Remettre en vente',
            picto: produit.actif ? Picto.close : Picto.check,
            secondaire: true,
            minHeight: 80,
            onTap: () => _basculer(ref),
          ),
        ],
      ),
    );
  }
}

class _Pastille extends StatelessWidget {
  const _Pastille({
    required this.texte,
    required this.picto,
    required this.fond,
  });

  final String texte;
  final Picto picto;
  final Color fond;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: fond,
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
