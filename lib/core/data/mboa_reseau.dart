import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/app_env.dart';

/// Le seul endroit qui touche Supabase.
///
/// `client` renvoie null quand aucun projet n'est configure, et les depots
/// basculent alors sur [BaseLocale]. C'est ce qui permet de faire tourner les
/// trois apps sur un telephone hors connexion sans dualite de code : un seul
/// chemin metier, deux supports.
class MboaReseau {
  const MboaReseau._();

  static SupabaseClient? _client;

  static SupabaseClient? get client => _client;

  static bool get enLigne => _client != null;

  static Future<void> initialiser() async {
    if (!AppEnv.supabaseConfigure) {
      debugPrint('MBOA: mode hors-ligne, aucun SUPABASE_URL dans le build');
      return;
    }
    try {
      await Supabase.initialize(
        url: AppEnv.supabaseUrl,
        anonKey: AppEnv.supabaseAnonKey,
        authOptions: const FlutterAuthClientOptions(
          // Flux PKCE : le seul flux fiable, puisque l'app ne possede aucun
          // secret client.
          authFlowType: AuthFlowType.pkce,
        ),
      );
      _client = Supabase.instance.client;
    } catch (e) {
      // Une URL invalide ne doit pas empecher l'app de s'ouvrir : le producteur
      // a deja son stock en local, il peut continuer a travailler.
      debugPrint('MBOA: Supabase indisponible ($e), repli sur la base locale');
      _client = null;
    }
  }

  /// URL publique d'un objet du bucket. Les buckets `produits` et `audios`
  /// sont publics (cf. 0007_storage.sql), donc aucune signature requise.
  static String? urlPublique(String chemin) {
    if (chemin.isEmpty) return null;
    if (chemin.startsWith('http')) return chemin;
    if (chemin.startsWith('assets/')) return null;
    final url = AppEnv.supabaseUrl;
    if (url.isEmpty) return null;
    return '$url/storage/v1/object/public/$chemin';
  }

  /// Televerse des octets et renvoie le chemin stocke, ou null si le serveur
  /// n'est pas joignable. Dans ce cas l'appelant garde l'objet en local et
  /// l'enverra plus tard : une photo perdue au champ est irremplacable.
  static Future<String?> televerser({
    required String bucket,
    required String dossier,
    required String nom,
    required Uint8List octets,
    required String mime,
  }) async {
    final client = _client;
    if (client == null) return null;
    final chemin = '$dossier/$nom';
    try {
      await client.storage.from(bucket).uploadBinary(
            chemin,
            octets,
            fileOptions: FileOptions(contentType: mime, upsert: true),
          );
      return '$bucket/$chemin';
    } catch (e) {
      debugPrint('televersement $bucket/$chemin echoue: $e');
      return null;
    }
  }

  static Future<void> supprimer(String bucketChemin) async {
    final client = _client;
    if (client == null || bucketChemin.isEmpty) return;
    final eclates = bucketChemin.split('/');
    final bucket = eclates.removeAt(0);
    try {
      await client.storage.from(bucket).remove([eclates.join('/')]);
    } catch (e) {
      debugPrint('suppression $bucketChemin echouee: $e');
    }
  }
}
