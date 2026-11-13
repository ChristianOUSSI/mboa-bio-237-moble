/// Role actif de l'application.
///
/// Une seule codebase sert les trois apps : le role est decide au build par le
/// flavor Android (`--flavor fournisseur`) et transmis au Dart par
/// `--dart-define=MBOA_ROLE=fournisseur`. Le serveur ne fait jamais confiance
/// a cette valeur : elle n'est qu'un index de presentation, la vraie autorite
/// est `public.profiles.role` verifiee par les policies RLS.
enum AppRole {
  fournisseur('fournisseur', 'MBOA FOURNISSEUR', 'Papa et mama au champ'),
  admin('admin', 'MBOA ADMIN', 'Le controle qualite'),
  consommateur('consommateur', 'MBOA BIO 237', 'La cliente du marche'),
  livreur('livreur', 'MBOA LIVREUR', 'La moto qui porte le panier');

  const AppRole(this.slug, this.appName, this.description);

  /// Valeur de `--dart-define` et du trigger SQL `raw_user_meta_data->>'role'`.
  final String slug;

  /// Nom affiche dans la barre de statut Android et l'ecran de confirmation.
  final String appName;

  /// Phrase courte prononcee au premier lancement de l'app.
  final String description;

  static AppRole resolve(String? slug) {
    for (final role in values) {
      if (role.slug == slug) return role;
    }
    // Un build sans --dart-define tombe sur l'app cliente : c'est la seule
    // variante qui ne peut rien casser chez les producteurs.
    return AppRole.consommateur;
  }
}
