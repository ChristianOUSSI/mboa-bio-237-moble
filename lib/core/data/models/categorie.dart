/// Les huit cases du catalogue ouvert.
///
/// Miroir exact de `public.categorie_enum`. Ce n'est PAS la liste des
/// produits : le logo MBOA BIO montre neuf fruits, la plateforme vend tout
/// ce que le Cameroun produit, viandes et poissons compris. Un enum ferme de
/// produits aurait recree la limite que le catalogue ouvert supprime, alors
/// un enum ferme de *cases* garde la navigation simple sans borner
/// l'offre : une chevre entre dans `viande`, un bissap dans `boisson`, et
/// aucun des deux n'a besoin d'une nouvelle valeur en base.
///
/// Une case n'est pas un mot : elle est un dessin d'abord, un mot ensuite.
/// C'est pour cela que [picto] fait partie du modele et non de l'ecran qui
/// l'affiche -- sinon chaque ecran choisirait son glyche, et la grille
/// cesserait de ressembler a une seule grille.
enum Categorie {
  fruit('fruit', 'Fruits', 'Les fruits', 1),
  tubercule('tubercule', 'Tubercules', 'Les tubercules', 2),
  legume('legume', 'Légumes et feuilles', 'Les légumes et les feuilles', 3),
  cereale('cereale', 'Céréales et graines', 'Les céréales et les graines', 4),
  viande('viande', 'Viandes et œufs', 'Les viandes et les œufs', 5),
  poisson('poisson', 'Poissons et fruits de mer', 'Les poissons', 6),
  huile('huile', 'Huiles et condiments', 'Les huiles et les condiments', 7),
  boisson('boisson', 'Boissons et laitages', 'Les boissons', 8);

  const Categorie(this.slug, this.libelle, this.libelleVoice, this.ordre);

  /// La valeur exacte de `public.categorie_enum`.
  final String slug;

  /// Le mot court, affiche sous le dessin.
  final String libelle;

  /// Ce que la voix prononce : « Les viandes et les œufs », pas « viande ».
  final String libelleVoice;

  /// Ordre dans la grille, identique a `categories.ordre` : la viande et le
  /// poisson ne descendent pas en bas de page parce qu'ils ne sont pas sur
  /// l'affiche.
  final int ordre;

  /// Le nom du fichier dans assets/pictos, aussi `categories.picto` en base.
  String get picto => slug;
  String get asset => 'assets/pictos/$slug.svg';

  /// Perissable par nature : ce qui tourne et se jette si le comptoir dort
  /// dessus deux jours. Sert aux alertes de stock, pas a l'affichage.
  bool get perissable =>
      this == Categorie.viande ||
      this == Categorie.poisson ||
      this == Categorie.fruit ||
      this == Categorie.legume;

  static Categorie resolve(String? slug) {
    for (final c in values) {
      if (c.slug == slug) return c;
    }
    // Une categorie inconnue ne doit jamais vider la grille : on retombe sur
    // la premiere case, la plus large.
    return Categorie.fruit;
  }
}
