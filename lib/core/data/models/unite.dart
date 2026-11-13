/// Ce que compte une quantite.
///
/// Miroir exact de `public.unite_enum`. Le marche ne vend pas tout au kilo :
/// le macabo en boules, l'huile rouge en bouteilles, la feuille de ndole en
/// bottes, un pack prepare en parts. Une colonne de quantite sans unite
/// associee affiche un prix que la cliente ne retrouvera pas a la porte.
///
/// Ce fichier ne depend de rien d'autre : `categorie.dart` l'importe, et
/// les deux se rejoignent plus haut dans `pack_composant.dart`.
enum Unite {
  kg('kg', 'kilo', 'kilos', 'le'),
  boule('boule', 'boule', 'boules', 'la'),
  bouteille('bouteille', 'bouteille', 'bouteilles', 'la'),
  botte('botte', 'botte', 'bottes', 'la'),
  morceau('morceau', 'morceau', 'morceaux', 'le'),
  part('part', 'part', 'parts', 'la'),
  // Les cinq unités qui manquaient pour écrire un vrai devis de marché :
  // l'arachide, la tomate et le maïs se vendent au litre, le miondo au
  // paquet, l'œuf au plateau, le plantain au régime, le sel au sachet.
  litre('litre', 'litre', 'litres', 'le'),
  paquet('paquet', 'paquet', 'paquets', 'le'),
  plateau('plateau', 'plateau', 'plateaux', 'le'),
  regime('regime', 'régime', 'régimes', 'le'),
  sachet('sachet', 'sachet', 'sachets', 'le');

  const Unite(this.slug, this.un, this.pluriel, this.article);

  final String slug;

  /// Pour dire « 1 boule ».
  final String un;

  /// Pour ecrire et dire « 3 boules ».
  final String pluriel;

  /// L'article du mot. Il appartient au nom, pas a une regle sur une seule
  /// unite : « le kilo » et « le morceau » sont masculins, les quatre autres
  /// feminins. Ecrire cet accord dans chaque ecran en produisait un autre.
  final String article;

  /// Vrai quand la valeur se lit comme un poids : le seul cas ou le mot
  /// « kilos » a le droit d'apparaitre a l'ecran.
  bool get estPoids => this == Unite.kg;

  /// 1 -> « boule », 3 -> « boules ».
  String pour(double valeur) => valeur == 1 ? un : pluriel;

  /// « le kilo », « la boule ».
  String get avecArticle => '$article $un';

  /// « 3 boules », « 1 kilo », « 5 parts ». Le texte de la tuile et de la
  /// liste imprimee, dans cet ordre la.
  String avec(double valeur) => '${_nombre(valeur)} ${pour(valeur)}';

  static String _nombre(double valeur) {
    final arrondi = valeur.roundToDouble();
    return (valeur - arrondi).abs() < 0.01
        ? arrondi.toStringAsFixed(0)
        : valeur.toStringAsFixed(1).replaceAll('.', ',');
  }

  static Unite resolve(String? slug) => values.firstWhere(
        (u) => u.slug == slug,
        orElse: () => Unite.kg,
      );
}
