import 'app_role.dart';

/// Parametres injectes au build.
///
/// Rien n'est secrete dans le depot : URL et anon key Supabase sont publiques
/// par construction (la securite vient des policies RLS), mais elles restent
/// passees en `--dart-define` pour permettre un staging sans reecrire le code.
class AppEnv {
  const AppEnv._();

  static const String supabaseUrl = String.fromEnvironment('SUPABASE_URL');
  static const String supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');
  static const String _roleSlug = String.fromEnvironment('MBOA_ROLE');

  /// Vrai quand un projet Supabase est reellement configure.
  ///
  /// Faux = l'app bascule en mode demonstration sur la base SQLite locale.
  /// C'est ce qui permet de faire tourner les trois flows sur un Tecno hors
  /// connexion, sans creer de faux identifiants silencieusement.
  static bool get supabaseConfigure =>
      supabaseUrl.startsWith('http') && supabaseAnonKey.length > 20;

  static AppRole get role => AppRole.resolve(_roleSlug);

  /// Duree maximale du message vocal au champ, en secondes.
  static const int dureeMessageVocal = 5;

  /// Nombre de chiffres de l'OTP vocal : 4 chiffres, un par ecran.
  static const int otpChiffres = 4;

  /// Message d'avertissement a afficher gros quand la config manque.
  static String? get problemeConfig {
    if (supabaseConfigure) return null;
    return 'Aucun projet Supabase dans ce build. '
        'Les donnees restent sur le telephone.';
  }
}
