/// Langue de lecture choisie au profil.
///
/// Basse et bamoun ne sont installees sur aucun telephone Android grand
/// public : le TTS systeme ne sait pas les prononcer. La strategie retenue
/// est donc la suivante, et elle est deliberee :
///
///   * fr     -> TTS francais ;
///   * pidgin -> TTS anglais, c'est la langue que le moteur Android sait
///               approximativement prononcer pour un locuteur camerounais ;
///   * bassa / bamoun -> lecture francaise des libelles, mais le vrai canal
///               reste l'audio enregistre par le producteur lui-meme
///               (`produits.audio_description_url`) et la voix de l'operatrice.
///
/// Autrement dit : les libelles systemes sont traduits, les descriptions de
/// marchandise sont chantees par les villageois. C'est ce qui rend l'app
/// utilisable sans savoir lire.
enum Langue {
  fr('fr', 'Français', 'fr-FR'),
  bassa('bassa', 'Bassa', 'fr-FR'),
  bamoun('bamoun', 'Bamoun', 'fr-FR'),
  pidgin('pidgin', 'Pidgin', 'en-US');

  const Langue(this.slug, this.libelle, this.codeTts);

  /// Valeur stockee dans `public.profiles.langue`.
  final String slug;

  /// Nom affiche dans l'ecran de choix, en toutes lettres.
  final String libelle;

  /// Code passe a `FlutterTts.setLanguage`.
  final String codeTts;

  /// Vrai quand le moteur sait reellement lire les libelles dans cette langue.
  bool get ttsNative => this == Langue.fr || this == Langue.pidgin;

  static Langue resolve(String? slug) => values.firstWhere(
        (l) => l.slug == slug,
        orElse: () => Langue.fr,
      );
}
