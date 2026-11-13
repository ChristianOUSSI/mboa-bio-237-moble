import 'categorie.dart';
import 'unite.dart';

/// Une ligne de `public.catalogue` : une reference du marche camerounais.
///
/// Le catalogue n'est pas le stock. Il dit qu'une marchandise existe, comment
/// le marche la compte et ce qu'elle coute d'habitude ; il ne dit nulle part
/// qu'il y en a au comptoir. Cette separation est ce qui permet a l'admin
/// d'ajouter une reference sans mentir a la cliente sur une disponibilite.
///
/// Le Dart ne porte qu'une partie de la verite : les paliers et la mesure
/// habituelle du produit du logo, pour que la grille reste utilisable hors
/// connexion. La base garde la main, et `slug` est la cle commune.
class EntreeCatalogue {
  const EntreeCatalogue({
    required this.slug,
    required this.nom,
    required this.categorie,
    required this.prixTendance,
    required this.paliers,
    required this.perissable,
    required this.ordre,
    this.unite,
    this.uniteLibelle,
  });

  /// La cle commune avec `catalogue.slug` et avec `produits.slug`.
  final String slug;
  final String nom;
  final Categorie categorie;

  /// Prix d'observation au marche, en FCFA par unite. Un conseil pour
  /// l'admin, jamais un prix applique tout seul.
  final int prixTendance;

  /// Positions du curseur de quantite, dans l'ordre croissant : des paliers
  /// ronds, jamais un continu qui demande de lire des decimales.
  final List<int> paliers;

  final bool perissable;

  /// Position dans la grille de la categorie, identique a `catalogue.ordre`.
  final int ordre;

  /// `catalogue.unite_defaut` : ce que le marche compte. Null = le kilo, qui
  /// reste la mesure la plus frequente mais pas la seule.
  final Unite? unite;

  /// Le mot pluriel tel que le village l'emploie (« pièces », « régimes »).
  final String? uniteLibelle;

  Unite get uniteReelle => unite ?? Unite.kg;

  /// Le premier palier, celui qu'une tuile pose quand on la touche une fois.
  double get premierPalier => (paliers.isEmpty ? 1 : paliers.first).toDouble();

  /// Le pas d'un pouce sur le curseur : l'ecart entre les deux premiers
  /// paliers, pour que trois appuis ne vident pas un stock.
  double get pasPaliers => paliers.length > 1 ? (paliers[1] - paliers[0]).toDouble() : 1;

  factory EntreeCatalogue.fromMap(Map<String, dynamic> map) {
    final brut = map['paliers'];
    final brutUnite = map['unite_defaut'] as String?;
    return EntreeCatalogue(
      slug: (map['slug'] ?? '') as String,
      nom: (map['nom'] ?? '') as String,
      categorie: Categorie.resolve(map['categorie'] as String?),
      prixTendance: (map['prix_tendance'] as num?)?.round() ?? 0,
      paliers: brut is List ? brut.map((p) => (p as num).round()).toList() : const <int>[],
      perissable: (map['perissable'] as bool?) ?? true,
      ordre: (map['ordre'] as num?)?.round() ?? 0,
      unite: brutUnite == null ? null : Unite.resolve(brutUnite),
      uniteLibelle: map['unite_libelle'] as String?,
    );
  }

  Map<String, dynamic> toMap() => {
        'slug': slug,
        'nom': nom,
        'categorie': categorie.slug,
        'prix_tendance': prixTendance,
        'paliers': paliers,
        'perissable': perissable,
        'ordre': ordre,
        'unite_defaut': uniteReelle.slug,
        'unite_libelle': uniteLibelle ?? uniteReelle.pluriel,
      };
}
