import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/data/models/categorie.dart';
import '../../core/data/models/produit.dart';
import '../../core/design_system/boutons.dart';
import '../../core/design_system/carte.dart';
import '../../core/design_system/picto.dart';
import '../../core/design_system/photo.dart';
import '../../core/design_system/tactile.dart';
import '../../core/etat/providers.dart';
import '../../core/theme/mboa_colors.dart';
import '../../core/theme/mboa_typography.dart';
import '../../core/utils/format_monnaie.dart';
import '../../core/voice/tts_service.dart';
import 'liste_screen.dart';
import 'panier_screen.dart';

/// L'ecran d'achat. Un tap = une ligne au panier.
///
/// Pas de nom de produit sur la tuile, et c'est voulu : la cliente reconnait
/// la papaye a sa photo. Le nom, lui, est dit par la voix quand on appuie sur
/// le haut-parleur. Ce qu'on lit est le prix, parce que c'est la seule chose
/// que l'on compare.
///
/// Acheter prend trois gestes : toucher la tuile, valider le panier, payer.
/// Le filtre par categorie est en haut, sous forme de pastilles, parce qu'une
/// maman qui cherche du manioc ne veut pas faire defiler quarante papayes.
class MarcheScreen extends ConsumerStatefulWidget {
  const MarcheScreen({super.key});

  static const String nom = '/marche';

  @override
  ConsumerState<MarcheScreen> createState() => _MarcheScreenState();
}

class _MarcheScreenState extends ConsumerState<MarcheScreen> {
  Categorie? _filtre;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      TtsService.instance.dire('Le marché. Touchez un produit pour le mettre dans votre panier.');
    });
  }

  void _ajouter(Produit produit) {
    // La premiere quantité : un kilo pour un produit au poids, une part pour
    // un plat. Plus de paliers calibrés par référence, le pas vient de
    // l'unité, et le réglage fin se fait au panier.
    final kg = produit.estPack ? 1.0 : 1.0;
    ref.read(panierProvider.notifier).poser(produit, kg);

    TtsService.instance.dire('${produit.nom}, ajouté. ${formaterFcfa(produit.montantPour(kg))}');
    Navigator.of(context).push(
      MaterialPageRoute(builder: (context) => const PanierScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final vitrine = ref.watch(vitrineProvider(_filtre));
    final panier = ref.watch(panierProvider);
    final liste = ref.watch(listeProvider);

    return Scaffold(
      backgroundColor: MboaColors.background,
      appBar: AppBar(
        title: const Text('Mboa Bio 237'),
        actions: [
          // L'entree de la liste de marche : le papier se prepare avant
          // l'achat, il ne se merite pas en plein milieu d'un panier.
          IconButton(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (context) => const ListeScreen()),
            ),
            tooltip: 'Ma liste',
            iconSize: 34,
            icon: Badge(
              label: Text('${liste.count}', style: MboaTypo.aide(couleur: MboaColors.primary)),
              backgroundColor: MboaColors.secondary,
              isLabelVisible: liste.count > 0,
              child: const PictoIcon(Picto.liste, size: 34, couleur: MboaColors.surface),
            ),
          ),
          IconButton(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (context) => const PanierScreen()),
            ),
            tooltip: 'Mon panier',
            iconSize: 34,
            icon: Badge(
              label: Text('${panier.count}', style: MboaTypo.aide(couleur: MboaColors.primary)),
              backgroundColor: MboaColors.secondary,
              isLabelVisible: panier.count > 0,
              child: const PictoIcon(Picto.basket, size: 34, couleur: MboaColors.surface),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _Filtres(
              choisi: _filtre,
              onChoisi: (cat) => setState(() => _filtre = cat),
            ),
            Expanded(
              child: vitrine.maybeWhen(
                data: (liste) {
                  if (liste.isEmpty) {
                    return Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const PictoIcon(Picto.leaf, size: 96),
                          const SizedBox(height: 18),
                          Text('Le marché se remplit', style: MboaTypo.titre()),
                          const SizedBox(height: 10),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 40),
                            child: Text(
                              'Les produits du comptoir apparaissent ici dès qu\'ils sont en stock',
                              style: MboaTypo.aide(couleur: MboaColors.text),
                              textAlign: TextAlign.center,
                            ),
                          ),
                        ],
                      ),
                    );
                  }
                  return GridView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 2,
                      mainAxisSpacing: 14,
                      crossAxisSpacing: 14,
                      childAspectRatio: 0.72,
                    ),
                    itemCount: liste.length,
                    itemBuilder: (context, index) => _TuileMarche(
                      produit: liste[index],
                      onAchat: () => _ajouter(liste[index]),
                    ),
                  );
                },
                orElse: () => const Center(
                  child: CircularProgressIndicator(color: MboaColors.primary),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Les huit pastilles de filtre, plus « tout ».
///
/// La premiere est « tout », et elle est plus large que les autres : c'est le
/// choix par defaut, celui qu'on ne doit jamais avoir a chercher.
class _Filtres extends StatelessWidget {
  const _Filtres({required this.choisi, required this.onChoisi});

  final Categorie? choisi;
  final ValueChanged<Categorie?> onChoisi;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 84,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        children: [
          Padding(
            padding: const EdgeInsets.only(right: 10),
            child: SizedBox(
              width: 108,
              child: BoutonCarre(
                picto: Picto.basket,
                taille: 64,
                couleurFond: choisi == null ? MboaColors.primary : MboaColors.surface,
                couleurTrait: MboaColors.primary,
                onTap: () => onChoisi(null),
                annonce: 'Tous les produits',
              ),
            ),
          ),
          for (final cat in Categorie.values)
            Padding(
              padding: const EdgeInsets.only(right: 10),
              child: GestureDetector(
                onTap: () {
                  mboaTactile(annonce: cat.libelle);
                  onChoisi(cat);
                },
                child: SizedBox(
                  width: 72,
                  child: PhotoProduit(
                    chemin: '',
                    categorie: cat,
                    cote: 64,
                    cadre: choisi == cat,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _TuileMarche extends StatelessWidget {
  const _TuileMarche({required this.produit, required this.onAchat});

  final Produit produit;
  final VoidCallback onAchat;

  @override
  Widget build(BuildContext context) {
    return CarteBio(
      onTap: onAchat,
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Stack(
              alignment: Alignment.bottomRight,
              children: [
                Center(
                  child: PhotoProduit(
                    chemin: produit.photo,
                    categorie: produit.categorie,
                    slug: produit.slug,
                    cote: 128,
                    cadre: false,
                    libelle: produit.nom,
                  ),
                ),
                Positioned(
                  right: 0,
                  top: 0,
                  child: BoutonVoix(texte: produit.annonceVocale),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          // L'exception du pack : la regle « pas de nom, la photo suffit »
          // tient pour une papaye, pas pour un plat. Deux packs se
          // ressemblent en photo ; seule la lettre les distingue.
          if (produit.estPack) ...[
            Text(
              produit.nom,
              style: MboaTypo.titre(),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            Text(
              '${produit.composants.length} ingrédients',
              style: MboaTypo.aide(),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Text(
                  formaterFcfaCourt(produit.prix),
                  style: MboaTypo.chiffreGeant(),
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                // « le kilo », « la boule », « la part » : l'unite vient du
                // produit, jamais de l'ecran.
                child: Text(
                  produit.uniteReelle.avecArticle,
                  style: MboaTypo.aide(),
                ),
              ),
            ],
          ),
          Text(
            produit.disponibilite,
            style: MboaTypo.aide(couleur: MboaColors.text),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}
