import 'categorie.dart';
import 'unite.dart';

/// Une fiche de producteur au fichier du comptoir.
///
/// Table `public.fournisseurs`. La fiche existe avant le compte, et lui
/// survit : le comptoir achete chez des gens qui n'ont pas de smartphone.
/// Quand la personne installe l'application avec le meme numero, le serveur
/// rattache la fiche au profil, sans creer un deuxieme fournisseur.
///
/// La cliente ne voit jamais cette fiche. Elle achete un produit au stock,
/// pas l'histoire de celui qui l'a produit.
class Fournisseur {
  const Fournisseur({
    required this.id,
    required this.nom,
    required this.telephone,
    required this.village,
    this.profilId,
    this.photo,
    this.productionCategorie,
    this.productionLibre = '',
    this.unite = Unite.kg,
    this.actif = true,
  });

  final String id;

  /// Le compte rattache, quand il existe. Null pour une fiche tenue au
  /// comptoir, ce qui est le cas courant d'un producteur du village.
  final String? profilId;

  final String nom;
  final String telephone;
  final String village;
  final String? photo;

  /// La case de production. Null sur une fiche creee par l'inscription, tant
  /// que l'admin ne l'a pas ouverte : l'ecran le dit au lieu de deviner.
  final Categorie? productionCategorie;

  /// Le mot du marche, plus precis que la case : « igname de Mbouda ».
  final String productionLibre;

  /// L'unite habituelle du producteur, proposee d'abord a la saisie d'achat.
  final Unite unite;

  final bool actif;

  bool get lie => profilId != null && profilId!.isNotEmpty;

  /// Ce que l'ecran affiche pour la production, sans jamais inventer une
  /// categorie qui n'a pas ete choisie.
  String get production {
    final libre = productionLibre.trim();
    if (libre.isNotEmpty) return libre;
    final categorie = productionCategorie;
    return categorie == null ? 'Production à préciser' : categorie.libelle;
  }

  /// Ce que la voix dit quand l'admin touche le haut-parleur de la fiche.
  String get annonce {
    final compte = lie ? 'Compte rattaché.' : 'Pas encore de compte.';
    return '$nom, à $village. $production. Mesure habituelle : ${unite.pluriel}. $compte';
  }

  factory Fournisseur.fromMap(Map<String, dynamic> map) => Fournisseur(
        id: map['id'] as String,
        nom: (map['nom'] as String?) ?? 'Fournisseur',
        telephone: (map['telephone_237'] as String?) ?? '',
        village: (map['village'] as String?) ?? 'Inconnu',
        profilId: map['profil_id'] as String?,
        photo: map['photo'] as String?,
        productionCategorie: _categorie(map['production_categorie'] as String?),
        productionLibre: (map['production_libre'] as String?) ?? '',
        unite: Unite.resolve(map['unite'] as String?),
        actif: (map['actif'] as bool?) ?? true,
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'profil_id': profilId,
        'nom': nom,
        'telephone_237': telephone,
        'village': village,
        'photo': photo,
        'production_categorie': productionCategorie?.slug,
        'production_libre': productionLibre,
        'unite': unite.slug,
        'actif': actif,
      };

  Fournisseur copieAvec({
    String? nom,
    String? telephone,
    String? village,
    String? photo,
    Categorie? productionCategorie,
    String? productionLibre,
    Unite? unite,
    bool? actif,
  }) =>
      Fournisseur(
        id: id,
        profilId: profilId,
        nom: nom ?? this.nom,
        telephone: telephone ?? this.telephone,
        village: village ?? this.village,
        photo: photo ?? this.photo,
        productionCategorie: productionCategorie ?? this.productionCategorie,
        productionLibre: productionLibre ?? this.productionLibre,
        unite: unite ?? this.unite,
        actif: actif ?? this.actif,
      );

  static Categorie? _categorie(String? slug) {
    if (slug == null || slug.isEmpty) return null;
    for (final categorie in Categorie.values) {
      if (categorie.slug == slug) return categorie;
    }
    return null;
  }
}
