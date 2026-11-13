import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../data/base_locale.dart';
import '../data/mboa_reseau.dart';

/// Ce qui vient de se passer quelque part sur la plateforme.
enum TypeEvenement {
  /// Un producteur a propose une marchandise au comptoir.
  nouvelleRecolte,

  /// L'admin a statue sur un achat : le stock grandit ou la proposition est refusee.
  recolteModeree,

  /// Une cliente a commande : l'admin doit valider le devis.
  commandeRecue,

  /// Un statut a change : les icones de la timeline s'allument.
  commandeChangee,

  /// Un jalon de suivi de colis a ete pose : la timeline se rafraichit.
  suiviColis,

  /// Un message pour une seule personne.
  notification,
}

class EvenementMboa {
  const EvenementMboa({required this.type, required this.apres, this.avant});

  final TypeEvenement type;
  final Map<String, dynamic> apres;
  final Map<String, dynamic>? avant;

  String get id => (apres['id'] ?? '') as String;
}

/// Le canal commun des trois apps.
///
/// Les evenements ne font que prevenir : chaque app relit ensuite son depot,
/// qui remet le cache a jour. C'est volontaire. Pousser la ligne entiere dans
/// l'evenement aurait impose de maintenir deux formats de serialisation, et
/// `replica identity full` diffuse deja l'avant/apres dans le payload.
///
/// Avec [BaseLocale] et [MboaReseau], c'est le troisieme endroit ou une
/// montee de version `supabase_flutter` peut demander une retouche.
class HubRealtime {
  HubRealtime(this._base);

  final BaseLocale _base;
  final StreamController<EvenementMboa> _flux = StreamController<EvenementMboa>.broadcast();

  final List<RealtimeChannel> _canaux = [];

  Stream<EvenementMboa> get flux => _flux.stream;

  bool get actif => _canaux.isNotEmpty;

  Future<void> demarrer() async {
    final client = MboaReseau.client;
    if (client == null || _canaux.isNotEmpty) return;

    try {
      _canaux.add(
        client.channel('mboa-produits')
          ..onRealtime(SupabaseEvent.insert, (payload) => _recu(TypeEvenement.nouvelleRecolte, payload))
          ..onRealtime(SupabaseEvent.update, (payload) => _recu(TypeEvenement.recolteModeree, payload)),
      );

      _canaux.add(
        client.channel('mboa-commandes')
          ..onRealtime(SupabaseEvent.insert, (payload) => _recu(TypeEvenement.commandeRecue, payload))
          ..onRealtime(SupabaseEvent.update, (payload) => _recu(TypeEvenement.commandeChangee, payload)),
      );

      _canaux.add(
        client.channel('mboa-notifications')
          ..onRealtime(SupabaseEvent.insert, (payload) => _recu(TypeEvenement.notification, payload)),
      );

      _canaux.add(
        client.channel('mboa-suivi')
          ..onRealtime(SupabaseEvent.insert, (payload) => _recu(TypeEvenement.suiviColis, payload)),
      );

      for (final canal in _canaux) {
        await canal.subscribe();
      }
    } catch (e) {
      debugPrint('temps reel indisponible: $e');
      await arreter();
    }
  }

  void _recu(TypeEvenement type, SupabaseRealtimePayload payload) {
    final apres = payload.newRecord;
    if (apres.isEmpty) return;

    // Le cache local absorbe l'evenement : la prochaine lecture, meme hors
    // connexion, verra la meme ligne.
    unawaited(_base.stocker(_entiteDe(type), apres));
    _flux.add(EvenementMboa(type: type, apres: apres, avant: payload.oldRecord));
  }

  static String _entiteDe(TypeEvenement type) => switch (type) {
        TypeEvenement.nouvelleRecolte || TypeEvenement.recolteModeree => Entites.produit,
        TypeEvenement.commandeRecue || TypeEvenement.commandeChangee => Entites.commande,
        TypeEvenement.suiviColis => Entites.suivi,
        TypeEvenement.notification => Entites.notification,
      };

  Future<void> arreter() async {
    final client = MboaReseau.client;
    for (final canal in _canaux) {
      if (client != null) {
        try {
          await client.removeChannel(canal);
        } catch (_) {
          // canal deja parti : sans effet.
        }
      }
    }
    _canaux.clear();
  }

  Future<void> fermer() async {
    await arreter();
    await _flux.close();
  }
}
