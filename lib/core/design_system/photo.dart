import 'dart:io';

import 'package:flutter/material.dart';

import '../config/app_env.dart';
import '../data/models/categorie.dart';
import '../theme/mboa_colors.dart';
import 'picto.dart';

/// Resout un chemin de media en `ImageProvider`, ou null si rien n'est jouable.
///
/// Trois formes se croisent dans la colonne `photo_reelle` :
///   * `assets/produits/boeuf.png` : la reference du catalogue, embarquee ;
///   * `produits/boeuf.jpg` : un objet du bucket, servi en URL publique ;
///   * `https://...` : une URL deja absolue (CDN d'un staging, par exemple).
///
/// Null n'est pas une erreur : c'est l'etat normal d'un telephone hors
/// connexion qui n'a pas encore telecharge la photo. L'appelant bascule alors
/// sur le pictogramme.
ImageProvider? sourceImage(String chemin) {
  if (chemin.isEmpty) return null;
  if (chemin.startsWith('assets/')) return AssetImage(chemin);
  if (chemin.startsWith('http')) return NetworkImage(chemin);
  // Une photo prise au champ dort en fichier local jusqu'a l'envoi. Sans ce
  // cas, la proposition hors connexion afficherait un pictogramme alors que
  // l'image est bien sur le telephone.
  if (chemin.startsWith('file:')) return FileImage(File(chemin.substring(7)));
  if (RegExp(r'^(/|[A-Za-z]:[\\/])').hasMatch(chemin)) return FileImage(File(chemin));
  if (!AppEnv.supabaseConfigure) return null;
  return NetworkImage('${AppEnv.supabaseUrl}/storage/v1/object/public/$chemin');
}

/// La photo reelle de la marchandise, avec son filet vert et son pictogramme
/// de secours.
///
/// Le secours n'est pas un detail visuel : c'est lui qui garde la grille de
/// categorie et la vitrine utilisables quand le reseau est coupe, ce qui
/// arrive a peu pres tout le temps au village.
///
/// Le secours se choisit en deux temps, et c'est ce qui rend le catalogue
/// ouvert possible sans 100 dessins : le pictogramme du produit s'il existe
/// (les neuf fruits du logo, plus les cases), sinon celui de sa categorie. Un
/// « poisson fumé » sans photo montre donc le poisson, pas une banane.
class PhotoProduit extends StatelessWidget {
  const PhotoProduit({
    required this.chemin,
    required this.categorie,
    this.slug,
    this.cote = 96,
    this.rayon = 18,
    this.cadre = true,
    this.libelle,
    super.key,
  });

  final String chemin;
  final Categorie categorie;

  /// La cle du produit, pour tenter son pictogramme avant celui de la case.
  final String? slug;

  final double cote;
  final double rayon;

  /// Le filet vert marque « photo validee par MBOA ». Retirer le cadre se
  /// reserve aux visuels deja encadres par leur conteneur.
  final bool cadre;

  /// Le nom que la voix et le lecteur d'ecran doivent prononcer.
  final String? libelle;

  @override
  Widget build(BuildContext context) {
    final source = sourceImage(chemin);
    final nom = libelle == null || libelle!.isEmpty
        ? categorie.libelle
        : libelle!;
    final secours = PictoIcon(
      Picto.pourSlug(slug ?? '', categorie),
      size: cote * 0.62,
      label: nom,
    );

    return Container(
      width: cote,
      height: cote,
      decoration: BoxDecoration(
        color: MboaColors.background,
        borderRadius: BorderRadius.circular(rayon),
        border: cadre ? Border.all(color: MboaColors.primary, width: 3) : null,
      ),
      clipBehavior: Clip.antiAlias,
      child: source == null
          ? Center(child: secours)
          : Image(
              image: source,
              fit: BoxFit.cover,
              width: cote,
              height: cote,
              gaplessPlayback: true,
              semanticLabel: 'Photo réelle de $nom',
              errorBuilder: (context, erreur, trace) => Center(child: secours),
              loadingBuilder: (context, enfant, etat) =>
                  etat == null ? enfant : Center(child: secours),
            ),
    );
  }
}

/// Le visage d'un humain, en rond.
///
/// Le rond n'est pas une fantaisie : c'est la forme que l'app du producteur
/// et celle de la cliente reconnaissent comme « une personne », et un visage
/// carre se lit comme une photo de produit.
class PhotoRonde extends StatelessWidget {
  const PhotoRonde({
    required this.chemin,
    this.cote = 72,
    this.label,
    this.quandAbsente = Picto.person,
    this.couleurLiseret,
    super.key,
  });

  final String chemin;
  final double cote;
  final String? label;

  /// Le dessin qui prend la place d'une photo absente. Le visage par defaut,
  /// la moto pour un livreur, la camera pour une piece a joindre.
  final Picto quandAbsente;

  /// Le liseret gris tant qu'aucune photo n'est posee, vert des qu'elle
  /// existe : la bordure dit a elle seule si l'etape est faite.
  final Color? couleurLiseret;

  @override
  Widget build(BuildContext context) {
    final source = sourceImage(chemin);

    return Container(
      width: cote,
      height: cote,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: MboaColors.secondaryDoux,
        border: Border.all(
          color: couleurLiseret ?? MboaColors.primary,
          width: 3,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: source == null
          ? Center(
              child: PictoIcon(quandAbsente, size: cote * 0.5, label: label),
            )
          : Image(
              image: source,
              fit: BoxFit.cover,
              width: cote,
              height: cote,
              semanticLabel: label == null ? 'Photo du visage' : 'Visage : $label',
              errorBuilder: (context, erreur, trace) =>
                  Center(child: PictoIcon(quandAbsente, size: cote * 0.5)),
            ),
    );
  }
}
