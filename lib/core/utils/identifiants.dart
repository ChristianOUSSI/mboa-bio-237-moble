import 'dart:math';

/// Identifiants uniques faits main.
///
/// Le projet n'embarque pas le package `uuid` pour une seule fonction : la
/// base distante genere ses propres uuid (default `gen_random_uuid()`), et
/// ceux-ci ne servent que de cle de cache local et de nom d'objet Storage
/// avant l'envoi. La forme reste un UUID v4, donc les deux mondes se
/// parlent.
class Identifiants {
  const Identifiants._();

  static final Random _hasard = Random.secure();

  static String uuidV4() {
    final octets = List<int>.generate(16, (_) => _hasard.nextInt(256));

    // Version 4 : les 4 bits de poids fort du 7e octet.
    octets[6] = (octets[6] & 0x0f) | 0x40;
    // Variant RFC 4122 : les 2 bits de poids fort du 9e octet.
    octets[8] = (octets[8] & 0x3f) | 0x80;

    final hex = octets.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}'
        '-${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
  }

  /// Cle courte, lisible, pour une note vocale ou une piece de preuve :
  /// `1r7rt9k`, pas un uuid de 36 caracteres.
  static String court() {
    const alphabet = 'abcdefghijklmnopqrstuvwxyz0123456789';
    return List.generate(7, (_) => alphabet[_hasard.nextInt(alphabet.length)]).join();
  }

  /// Le slug d'un nom : minuscules, sans accent, espaces en underscores.
  ///
  /// Miroir de `mboa.slugifier` côté SQL. C'est lui qui empêche « Bœuf »,
  /// « bœuf » et « BOEUF » de devenir trois stocks différents.
  static String slugDe(String nom) {
    final sansAccent = nom
        .toLowerCase()
        .replaceAll('ç', 'c')
        .replaceAll('œ', 'oe')
        .replaceAll(RegExp(r'[àâä]'), 'a')
        .replaceAll(RegExp(r'[éèêë]'), 'e')
        .replaceAll(RegExp(r'[îï]'), 'i')
        .replaceAll(RegExp(r'[ôö]'), 'o')
        .replaceAll(RegExp(r'[ûùü]'), 'u')
        .replaceAll(RegExp(r'[^a-z0-9 ]'), '')
        .trim()
        .replaceAll(RegExp(r'\s+'), '_');
    return sansAccent.isEmpty ? 'produit' : sansAccent.substring(0, sansAccent.length.clamp(0, 40));
  }
}
