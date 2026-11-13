import 'dart:convert';

import 'unite.dart';

/// Un element d'un plat prepare : « 3 bottes de ndole », « 1 litre de
/// crevettes ».
///
/// Gele dans le JSONB `produits.pack_composants` au moment ou le comptoir
/// compose le plat, puis reporte dans la ligne du devis. Le gel n'est pas un
/// detail : si la recette change le lendemain, les parts deja vendues doivent
/// rester ce que la cliente a cru acheter, et le debit du stock doit suivre la
/// meme liste qu'elle a vue a la porte.
///
/// Le [nom] est transporte a cote du [slug], et pas seulement le slug. Une
/// ligne de devis relue six mois plus tard doit s'afficher meme si la
/// reference a ete retiree du catalogue depuis : sans le nom gele, il ne
/// resterait qu'un identifiant technique sur un papier qui doit rester
/// lisibles par une personne qui ne lit pas.
class PackComposant {
  const PackComposant({
    required this.slug,
    required this.quantite,
    required this.unite,
    this.nom,
  });

  /// La reference du stock que cet ingredient vient piocher.
  final String slug;

  /// Le nom affiche et prononce. Null quand le composeur n'a rien gele : on
  /// retombe alors sur le slug, qui reste lisible (« poisson_fume ») et vaut
  /// mieux qu'un vide.
  final String? nom;

  /// Par part, pas pour le lot : deux parts de ce plat retirent 6 bottes.
  final double quantite;

  /// L'unite de l'ingredient, pas celle du plat. Un pack se vend en parts et
  /// se compose en bottes, litres et morceaux meles.
  final Unite unite;

  String get libelle {
    final gele = nom?.trim();
    return gele == null || gele.isEmpty ? slug.replaceAll('_', ' ') : gele;
  }

  /// Ce que la voix enonce : « 3 bottes de ndolè ».
  String get annonce => '${unite.avec(quantite)} de $libelle';

  /// Le texte court de la tuile : « 3 bottes ».
  String get libelleCourt => unite.avec(quantite);

  factory PackComposant.fromJson(Map<String, dynamic> json) => PackComposant(
        slug: (json['slug'] ?? '') as String,
        nom: json['nom'] as String?,
        quantite: (json['quantite'] as num?)?.toDouble() ?? 0,
        unite: Unite.resolve(json['unite'] as String?),
      );

  Map<String, dynamic> toJson() => {
        'slug': slug,
        'nom': libelle,
        'quantite': quantite,
        'unite': unite.slug,
      };

  PackComposant copieAvec({double? quantite, Unite? unite}) => PackComposant(
        slug: slug,
        nom: nom,
        quantite: quantite ?? this.quantite,
        unite: unite ?? this.unite,
      );
}

/// La liste des composants, dans l'ordre ou le comptoir les a poses.
///
/// Tolere le JSONB brut (une chaine, cas du cache SQLite) comme le tableau
/// deja decode (cas de la reponse HTTP). Un composant illisible est ignore
/// plutot que de faire tomber la tuile : mieux vaut un plat dont un element
/// manque qu'une vitrine entiere vide.
List<PackComposant> composantsDepuisJson(dynamic brut) {
  final List<dynamic> tableau = switch (brut) {
    final List<dynamic> l => l,
    final String s when s.trim().isNotEmpty => _decoder(s),
    _ => const <dynamic>[],
  };

  return tableau
      .whereType<Map<String, dynamic>>()
      .map(PackComposant.fromJson)
      .toList(growable: false);
}

List<dynamic> _decoder(String texte) {
  try {
    final decode = jsonDecode(texte);
    return decode is List ? decode : const [];
  } catch (_) {
    return const [];
  }
}
