import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';

/// Telecharge des octets bruts depuis une URL publique, sans dependance.
///
/// Le SDK Storage de Supabase expose des methodes de telechargement dont la
/// signature change a chaque version majeure. Pour une seule operation, lire
/// une photo avant de la filigraner, `dart:io` suffit et ne bouge pas.
///
/// La lecture est faite chunk par chunk : une photo de telephone fait
/// quelques centaines de kilo-octets, mais un reseau 3G camerounais les
/// deliver par morceaux de quelques milliers d'octets.
Future<Uint8List?> telechargerBinaire(String url) async {
  if (!url.startsWith('http')) return null;

  final client = HttpClient()..connectionTimeout = const Duration(seconds: 12);

  try {
    final requete = await client.getUrl(Uri.parse(url));
    final reponse = await requete.close();
    if (reponse.statusCode != HttpStatus.ok) {
      debugPrint('telechargement $url : HTTP ${reponse.statusCode}');
      return null;
    }

    final tampons = <List<int>>[];
    var total = 0;
    await for (final morceau in reponse) {
      tampons.add(morceau);
      total += morceau.length;
    }

    final octets = Uint8List(total);
    var decalage = 0;
    for (final tampon in tampons) {
      octets.setRange(decalage, decalage + tampon.length, tampon);
      decalage += tampon.length;
    }
    return octets;
  } catch (e) {
    debugPrint('telechargement $url impossible: $e');
    return null;
  } finally {
    client.close(force: true);
  }
}
