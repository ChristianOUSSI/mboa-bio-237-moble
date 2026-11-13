/// Un point de producteur sur la carte admin.
///
/// Vit dans le modele et non dans le widget : la liste des villages est
/// produite par un provider, consommee par la carte, et doit rester testable
/// sans rendre un pixel.
class RepereVillage {
  const RepereVillage({
    required this.village,
    required this.latitude,
    required this.longitude,
    required this.fournisseurs,
    required this.recoltes,
  });

  final String village;
  final double latitude;
  final double longitude;

  /// Nombre de producteurs actifs declares dans le village.
  final int fournisseurs;

  /// Recoltes validees. C'est ce que la carte represente reellement : de
  /// l'offre disponible, pas des comptes inscrits.
  final int recoltes;

  /// Le poids visuel du point, en pixels.
  ///
  /// Plafonne a 40 : un village qui aurait 300 producteurs ne doit pas devenir
  /// une tache qui mange la carte.
  double get diametre => (18 + fournisseurs * 3).clamp(18.0, 40.0).toDouble();

  String get annonce =>
      '$village, $fournisseurs producteurs';

  /// Les localites reelles du bassin d'offre, utilisees quand la base ne
  /// repond pas. Coordonnees observees, pas devinees.
  static const List<RepereVillage> villagesConnus = [
    RepereVillage(village: 'Mbouda', latitude: 4.8167, longitude: 10.2667, fournisseurs: 1, recoltes: 2),
    RepereVillage(village: 'Bafoussam', latitude: 5.4785, longitude: 10.4179, fournisseurs: 1, recoltes: 2),
    RepereVillage(village: 'Dschang', latitude: 5.1667, longitude: 10.0667, fournisseurs: 1, recoltes: 2),
    RepereVillage(village: 'Bamenda', latitude: 5.9575, longitude: 10.1546, fournisseurs: 0, recoltes: 0),
    RepereVillage(village: 'Foumban', latitude: 5.7333, longitude: 10.9000, fournisseurs: 0, recoltes: 0),
    RepereVillage(village: 'Nkongsamba', latitude: 4.9500, longitude: 9.9333, fournisseurs: 0, recoltes: 0),
    RepereVillage(village: 'Bertoua', latitude: 4.5833, longitude: 13.6833, fournisseurs: 0, recoltes: 0),
    RepereVillage(village: 'Yokadouma', latitude: 3.5167, longitude: 15.0500, fournisseurs: 0, recoltes: 0),
    RepereVillage(village: 'Garoua', latitude: 9.3000, longitude: 13.4000, fournisseurs: 0, recoltes: 0),
    RepereVillage(village: 'Maroua', latitude: 10.5927, longitude: 14.3214, fournisseurs: 0, recoltes: 0),
    RepereVillage(village: 'Ngaoundéré', latitude: 7.3333, longitude: 13.5833, fournisseurs: 0, recoltes: 0),
    RepereVillage(village: 'Kribi', latitude: 2.9333, longitude: 9.9167, fournisseurs: 0, recoltes: 0),
    RepereVillage(village: 'Yaoundé', latitude: 3.8480, longitude: 11.5021, fournisseurs: 0, recoltes: 0),
    RepereVillage(village: 'Douala', latitude: 4.0483, longitude: 9.7044, fournisseurs: 0, recoltes: 0),
  ];

  static List<RepereVillage> horsLigne() => villagesConnus;
}
