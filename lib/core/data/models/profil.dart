import 'langue.dart';

/// Un humain inscrit : producteur, admin ou cliente.
///
/// Table `public.profiles`. Le role n'est jamais demande au client : il vient
/// de la ligne en base, donc un flavor falsifie au build ne donne aucun droit.
class Profil {
  const Profil({
    required this.id,
    required this.role,
    required this.nom,
    required this.village,
    required this.telephone,
    required this.langue,
    this.photoVisage,
    this.latitude,
    this.longitude,
    this.actif = true,
  });

  final String id;

  /// `fournisseur`, `admin` ou `consommateur`.
  final String role;

  final String nom;
  final String village;

  /// Format `+2376XXXXXXXX`, garantie par la contrainte CHECK cote serveur.
  final String telephone;

  final Langue langue;
  final String? photoVisage;

  /// Position du champ, utilisee par les points verts de la carte admin.
  final double? latitude;
  final double? longitude;

  final bool actif;

  /// Prenom tel que l'app l'annonce : « Mama Elise », sans majuscule parasite.
  String get prenom {
    final parties = nom.trim().split(RegExp(r'\s+'));
    if (parties.isEmpty) return 'Producteur';
    if (parties.length == 1) return _capitalise(parties.first);
    return '${_capitalise(parties.first)} ${parties.sublist(1).join(' ').toUpperCase()}';
  }

  static String _capitalise(String chaine) {
    if (chaine.isEmpty) return chaine;
    return chaine[0].toUpperCase() + chaine.substring(1).toLowerCase();
  }

  /// « Papa Jean à Bafoussam », la formule que le TTS enonce dans la vitrine.
  String get vitrine => '$prenom à $village';

  bool get estFournisseur => role == 'fournisseur';
  bool get estAdmin => role == 'admin';

  factory Profil.fromMap(Map<String, dynamic> map) => Profil(
        id: map['id'] as String,
        role: (map['role'] as String?) ?? 'consommateur',
        nom: (map['nom'] as String?) ?? 'Nouveau',
        village: (map['village'] as String?) ?? 'Inconnu',
        telephone: (map['telephone_237'] as String?) ?? '',
        langue: Langue.resolve(map['langue'] as String?),
        photoVisage: map['photo_visage'] as String?,
        latitude: (map['latitude'] as num?)?.toDouble(),
        longitude: (map['longitude'] as num?)?.toDouble(),
        actif: (map['actif'] as bool?) ?? true,
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'role': role,
        'nom': nom,
        'village': village,
        'telephone_237': telephone,
        'langue': langue.slug,
        'photo_visage': photoVisage,
        'latitude': latitude,
        'longitude': longitude,
        'actif': actif,
      };

  Profil copieAvec({
    String? nom,
    String? village,
    String? telephone,
    Langue? langue,
    String? photoVisage,
    bool? actif,
  }) =>
      Profil(
        id: id,
        role: role,
        nom: nom ?? this.nom,
        village: village ?? this.village,
        telephone: telephone ?? this.telephone,
        langue: langue ?? this.langue,
        photoVisage: photoVisage ?? this.photoVisage,
        latitude: latitude,
        longitude: longitude,
        actif: actif ?? this.actif,
      );
}
