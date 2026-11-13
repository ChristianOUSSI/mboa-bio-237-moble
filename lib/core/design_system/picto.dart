import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../data/models/categorie.dart';
import '../data/models/statuts.dart';
import '../theme/mboa_colors.dart';

/// Les pictogrammes au trait de l'app.
///
/// Aucun emoji, aucun glyphe Material utilise comme icone metier : tout ce
/// qu'un utilisateur doit reconnaitre est dessine dans assets/pictos et
/// genere par tool/gen_pictos.mjs, avec un style strictement identique.
///
/// [fichier] est le nom exact du SVG, et il sert aussi de valeur a
/// `public.categorie_enum` pour les huit cases : un seul vocabulaire de part
/// en part.
enum Picto {
  camera('camera'),
  basket('basket'),
  money('money'),
  speaker('speaker'),
  mic('mic'),
  trash('trash'),
  moto('moto'),
  check('check'),
  handGive('hand-give'),
  plus('plus'),
  minus('minus'),
  phone('phone'),
  face('face'),
  map('map'),
  priceTag('price-tag'),
  leaf('leaf'),
  sync('sync'),
  alert('alert'),
  person('person'),
  back('back'),
  close('close'),
  clock('clock'),
  pouceLeve('pouce-leve'),
  pouceBaisse('pouce-baisse'),
  liste('liste'),
  partage('partage'),
  especes('especes'),
  banane('banane'),
  plantain('plantain'),
  papaye('papaye'),
  pasteque('pasteque'),
  patateDouce('patate_douce'),
  mandarine('mandarine'),
  pommeDeTerre('pomme_de_terre'),
  manioc('manioc'),
  macabo('macabo'),
  // Les huit cases du catalogue ouvert. Une case n'est pas un fruit : c'est
  // une porte, et elle doit se reconnaitre a sa silhouette avant de se
  // reconnaitre a son mot.
  fruit('fruit'),
  tubercule('tubercule'),
  legume('legume'),
  cereale('cereale'),
  viande('viande'),
  poisson('poisson'),
  huile('huile'),
  boisson('boisson'),
  momo('momo'),
  orangeMoney('orange-money');

  const Picto(this.fichier);

  final String fichier;

  String get asset => 'assets/pictos/$fichier.svg';

  /// Vrai pour les deux marques de paiement : elles gardent leur couleur,
  /// les teinter detruirait l'identification de l'operateur.
  bool get estMarque => this == Picto.momo || this == Picto.orangeMoney;

  /// Le dessin d'une des huit cases du catalogue. Le nom du fichier est le
  /// slug de la categorie, en base comme ici : une seule table de
  /// correspondance, et elle ne peut pas diverger.
  static Picto pourCategorie(Categorie categorie) => values.firstWhere(
        (p) => p.fichier == categorie.slug,
        orElse: () => Picto.basket,
      );

  /// Le dessin d'une marchandise, en deux temps.
  ///
  /// Le catalogue est ouvert, cent references et plus, mais les dessins,
  /// non. Un produit qui a son pictogramme (les neuf fruits du logo, et les
  /// rares autres ajoutes) le prend ; tout le reste prend celui de sa case.
  /// C'est ce qui evite deux pieges a la fois : une banane qui apparait la
  /// ou la mama a dicte un « poisson fume », et un catalogue qui ne pourrait
  /// plus s'etendre sans une nouvelle APK.
  static Picto pourSlug(String slug, Categorie categorie) {
    for (final picto in values) {
      if (picto.fichier == slug) return picto;
    }
    return pourCategorie(categorie);
  }

  /// Libelle prononce par le TTS quand aucun semanticLabel n'est passe.
  String get annonce => switch (this) {
        Picto.camera => 'Ajouter ma récolte',
        Picto.basket => 'Mon panier',
        Picto.money => 'Mon argent',
        Picto.speaker => 'Écouter',
        Picto.mic => 'Parler',
        Picto.trash => 'Refuser',
        Picto.moto => 'Livraison à moto',
        Picto.check => 'Validé',
        Picto.handGive => 'Remis en main propre',
        Picto.plus => 'Ajouter',
        Picto.minus => 'Retirer',
        Picto.phone => 'Appeler',
        Picto.face => 'Photo du visage',
        Picto.map => 'La carte des villages',
        Picto.priceTag => 'Le prix',
        Picto.leaf => 'Bio du village',
        Picto.sync => 'Envoyer au serveur',
        Picto.alert => 'Litige',
        Picto.person => 'Le producteur',
        Picto.back => 'Retour',
        Picto.close => 'Fermer',
        Picto.clock => 'Le délai',
        Picto.pouceLeve => 'Oui, tout est bon',
        Picto.pouceBaisse => 'Non, il y a un problème',
        Picto.liste => 'Ma liste de marché',
        Picto.partage => 'Partager',
        Picto.especes => 'Je paie à la livraison',
        Picto.momo => 'MTN Mobile Money',
        Picto.orangeMoney => 'Orange Money',
        _ => 'Produit',
      };
}

/// Le pictogramme qui represente une reponse de la cliente.
///
/// Le modele de donnees ne connait pas les icones. C'est ici, et seulement
/// ici, que `Satisfaction` et `MotifReception` rencontrent leur dessin.
extension PictoSatisfaction on Satisfaction {
  Picto get picto => switch (this) {
        Satisfaction.bon => Picto.pouceLeve,
        Satisfaction.probleme => Picto.pouceBaisse,
      };
}

extension PictoMotifReception on MotifReception {
  Picto get picto => switch (this) {
        MotifReception.rienRecu => Picto.moto,
        MotifReception.quantite => Picto.priceTag,
        MotifReception.abime => Picto.alert,
      };
}

/// Le jalon de la timeline qui correspond a un statut.
///
/// Quatre icones pour six etats : `recue` ne dessine pas une cinquieme case,
/// elle ferme la quatrieme, et `annulee` n'en dessine aucune. Un devis
/// annule n'est pas une etape franchie, c'est un papier qui n'existe plus.
/// C'est la decision de charte, pas un oubli.
extension PictoStatut on StatutCommande {
  Picto get jalonPicto => switch (this) {
        StatutCommande.nouvelle => Picto.basket,
        StatutCommande.valideeAdmin => Picto.check,
        StatutCommande.enLivraison => Picto.moto,
        StatutCommande.livree || StatutCommande.recue => Picto.handGive,
        StatutCommande.annulee => Picto.close,
      };
}

/// Un pictogramme, colore a la volée par `BlendMode.srcIn`.
///
/// Le `Semantics` n'est pas decoratif : un lecteur d'ecran et le TTS interne
/// de l'app lisent la meme chaine, donc un picto sans [label] est une faute
/// d'accessibilite, pas une economie de code.
class PictoIcon extends StatelessWidget {
  const PictoIcon(
    this.picto, {
    this.size = 40,
    this.couleur = MboaColors.primary,
    this.label,
    super.key,
  });

  final Picto picto;
  final double size;
  final Color couleur;
  final String? label;

  @override
  Widget build(BuildContext context) {
    final image = SvgPicture.asset(
      picto.asset,
      width: size,
      height: size,
      excludeFromSemantics: true,
    );

    return Semantics(
      label: label ?? picto.annonce,
      child: picto.estMarque
          ? image
          : ColorFiltered(
              colorFilter: ColorFilter.mode(couleur, BlendMode.srcIn),
              child: image,
            ),
    );
  }
}

/// Pictogramme pose sur une pastille ronde : l'etat « allume » des timelines
/// et des trois gros boutons du fournisseur.
class PictoPastille extends StatelessWidget {
  const PictoPastille({
    required this.picto,
    this.diametre = 72,
    this.allume = true,
    this.couleurFond,
    this.couleurTrait,
    this.couleurIcone,
    this.label,
    super.key,
  });

  final Picto picto;
  final double diametre;
  final bool allume;
  final Color? couleurFond;
  final Color? couleurTrait;

  /// L'icone doit contraster avec le fond de la pastille, pas avec la charte.
  /// Une pastille pleine vert fonce prend donc une icone blanche : sans ce
  /// parametre, le signe de fermeture devenait invisible sur son propre fond.
  final Color? couleurIcone;
  final String? label;

  @override
  Widget build(BuildContext context) {
    final teinteIcone = couleurIcone ?? (allume ? MboaColors.primary : MboaColors.textDoux);

    return Container(
      width: diametre,
      height: diametre,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: couleurFond ?? (allume ? MboaColors.secondaryDoux : MboaColors.primaryDoux),
        border: Border.all(
          color: couleurTrait ?? (allume ? MboaColors.primary : MboaColors.trait),
          width: 3,
        ),
      ),
      child: Center(
        child: PictoIcon(
          picto,
          size: diametre * 0.52,
          couleur: teinteIcone,
          label: label,
        ),
      ),
    );
  }
}
