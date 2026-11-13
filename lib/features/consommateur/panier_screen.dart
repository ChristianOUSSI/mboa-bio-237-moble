import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/data/models/commande.dart';
import '../../core/data/models/produit.dart';
import '../../core/design_system/boutons.dart';
import '../../core/design_system/carte.dart';
import '../../core/design_system/picto.dart';
import '../../core/design_system/photo.dart';
import '../../core/etat/providers.dart';
import '../../core/theme/mboa_colors.dart';
import '../../core/theme/mboa_typography.dart';
import '../../core/utils/format_monnaie.dart';
import '../../core/voice/tts_service.dart';
import 'commander_screen.dart';

/// Le panier, dessine comme un etal.
///
/// Les lignes sont empilees dans l'ordre d'ajout, la plus recente en haut,
/// exactement comme une mama pose ses sacs sur l'etal. Chaque ligne porte la
/// photo du tas : on ne valide pas une commande que l'on ne reconnait pas.
///
/// Les touches plus et moins font 96 px, soit le double de la cible
/// reglementaire. C'est le seul endroit de l'app ou l'on appuie beaucoup de
/// fois, donc le seul endroit ou la precision coute plus qu'elle ne rapporte.
class PanierScreen extends ConsumerWidget {
  const PanierScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final panier = ref.watch(panierProvider);
    final vitrine = ref.watch(vitrineProvider(null)).valueOrNull ?? const <Produit>[];

    if (panier.vide) {
      return Scaffold(
        backgroundColor: MboaColors.background,
        appBar: AppBar(title: const Text('Mon panier')),
        body: SafeArea(
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const PictoIcon(Picto.basket, size: 104),
                const SizedBox(height: 20),
                Text('Panier vide', style: MboaTypo.titre()),
                const SizedBox(height: 12),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 44),
                  child: Text(
                    'Touchez un fruit au marché pour le déposer ici',
                    style: MboaTypo.aide(couleur: MboaColors.text),
                    textAlign: TextAlign.center,
                  ),
                ),
                const SizedBox(height: 26),
                GrosBouton(
                  titre: 'Voir le marché',
                  picto: Picto.leaf,
                  sombre: true,
                  onTap: () => Navigator.of(context).pop(),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: MboaColors.background,
      appBar: AppBar(
        title: const Text('Mon panier'),
        leading: IconButton(
          onPressed: () => Navigator.of(context).pop(),
          tooltip: 'Retour',
          iconSize: 36,
          icon: const PictoIcon(Picto.back, size: 36, couleur: MboaColors.surface),
        ),
        actions: [
          IconButton(
            onPressed: () {
              ref.read(panierProvider.notifier).vider();
              TtsService.instance.dire('Panier vidé');
            },
            tooltip: 'Vider le panier',
            iconSize: 34,
            icon: const PictoIcon(Picto.trash, size: 34, couleur: MboaColors.surface),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: ListView.separated(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
                itemCount: panier.articles.length,
                separatorBuilder: (context, index) => const SizedBox(height: 12),
                itemBuilder: (context, index) {
                  final ligne = panier.articles[index];
                  final produit = vitrine.where((p) => p.id == ligne.produitId).toList();
                  return _LigneEtal(
                    ligne: ligne,
                    // Le stock reel vient de la vitrine : sans lui, on ne peut
                    // pas dire a la cliente qu'il ne reste que 3 kilos.
                    disponible: produit.isEmpty ? null : produit.first.quantite,
                    onPlus: () => _changer(ref, ligne, +1),
                    onMoins: () => _changer(ref, ligne, -1),
                  );
                },
              ),
            ),
            _Total(panier: panier),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 6, 16, 18),
              child: GrosBouton(
                titre: 'Commander',
                picto: Picto.money,
                sombre: true,
                minHeight: 104,
                chiffre: formaterFcfaCourt(panier.montantTotal),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (context) => const CommanderScreen()),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Un pas = le premier palier du produit. Vider completement une ligne se
  /// fait par la corbeille de la ligne, pas en tapant moins dix fois.
  static void _changer(WidgetRef ref, LigneCommande ligne, int sens) {
    final pas = ligne.pas;
    final nouveau = (ligne.quantite + sens * pas);

    final notifieur = ref.read(panierProvider.notifier);
    if (nouveau <= 0) {
      notifieur.retirer(ligne.produitId);
      TtsService.instance.dire('${ligne.nom} retiré');
      return;
    }

    // Reconstitue la ligne : le panier ne connait que des produits de la
    // vitrine, et le prix comme le stock y ont leur source.
    final vitrine = ref.read(vitrineProvider(null)).valueOrNull ?? const <Produit>[];
    final produit = vitrine.where((p) => p.id == ligne.produitId).toList();
    if (produit.isEmpty) return;

    notifieur.poser(produit.first, nouveau);
    TtsService.instance.dire('${ligne.uniteReelle.avec(nouveau)} de ${ligne.nom}');
  }
}

class _LigneEtal extends StatelessWidget {
  const _LigneEtal({
    required this.ligne,
    required this.disponible,
    required this.onPlus,
    required this.onMoins,
  });

  final LigneCommande ligne;
  final double? disponible;
  final VoidCallback onPlus;
  final VoidCallback onMoins;

  @override
  Widget build(BuildContext context) {
    final manque = disponible != null && ligne.quantite > disponible!;

    return CarteBio(
      couleurTrait: manque ? MboaColors.error : MboaColors.trait,
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              PhotoProduit(
                chemin: ligne.photo,
                categorie: ligne.categorie,
                slug: ligne.slug,
                libelle: ligne.nom,
                cote: 88,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Le nom revient ici, et particulierement pour un pack :
                    // dans le panier, la mama compare ce qu'elle a pose. Deux
                    // parts de plat different par leur photo, rarement
                    // assez pour qu'une personne agee les distingue du coup
                    // d'oeil sur une ligne de recu.
                    Text(ligne.nom, style: MboaTypo.titre()),
                    ChiffreUnite(
                      valeur: ligne.quantiteAffichee,
                      geant: true,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${formaterFcfaCourt(ligne.prix)} ${ligne.uniteReelle.avecArticle}',
                      style: MboaTypo.aide(couleur: MboaColors.text),
                    ),
                    if (ligne.estPack)
                      Text(
                        [for (final c in ligne.composants) c.libelleCourt].join(' · '),
                        style: MboaTypo.aide(),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                  ],
                ),
              ),
              Text(
                formaterFcfaCourt(ligne.sousTotal),
                style: MboaTypo.chiffre(),
              ),
            ],
          ),
          if (manque) ...[
            const SizedBox(height: 10),
            BandeauEtat(
              texte: 'Il ne reste que ${ligne.uniteReelle.avec(disponible!)} au comptoir',
              couleur: MboaColors.error,
              icone: const PictoIcon(Picto.alert, size: 28, couleur: MboaColors.error),
            ),
          ],
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: BoutonCarre(
                  picto: Picto.minus,
                  taille: 96,
                  onTap: onMoins,
                  annonce: `Retirer ${ligne.annoncePas}`,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: BoutonCarre(
                  picto: Picto.plus,
                  taille: 96,
                  couleurFond: MboaColors.primary,
                  couleurTrait: MboaColors.primary,
                  onTap: onPlus,
                  annonce: `Ajouter ${ligne.annoncePas}`,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Le total du panier.
///
/// Pas de commission cachée : le prix affiché est le prix à payer, et la
/// marge du comptoir se calcule sur le coût d'achat, pas sur un prélèvement
/// visible à la cliente.
class _Total extends ConsumerWidget {
  const _Total({required this.panier});

  final Panier panier;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      decoration: BoxDecoration(
        color: MboaColors.surface,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: MboaColors.primary, width: 3),
      ),
      child: Column(
        children: [
          Row(
            children: [
              const PictoIcon(Picto.leaf, size: 34),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  '${panier.count} produits · ${panier.resumeQuantites}',
                  style: MboaTypo.corps(),
                ),
              ),
              BoutonVoix(
                texte: 'Total ${formaterFcfa(panier.montantTotal)} pour ${panier.count} produits',
                resume: formaterFcfa(panier.montantTotal),
              ),
            ],
          ),
          const Divider(height: 20),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(child: Text('À payer à la porte', style: MboaTypo.titre())),
              Text(
                formaterFcfa(panier.montantTotal),
                style: MboaTypo.chiffreGeant(),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
