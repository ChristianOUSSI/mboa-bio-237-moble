import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../utils/identifiants.dart';
import 'base_locale.dart';
import 'mboa_reseau.dart';
import 'models/achat.dart';
import 'models/categorie.dart';
import 'models/unite.dart';

/// Les achats du comptoir chez les agriculteurs.
///
/// Deux mondes se croisent ici, et le depot est le seul endroit ou ils se
/// parlent : le fournisseur propose ce qu'il a, l'admin signe. La marchandise
/// n'entre au stock qu'a la signature (`mboa.valider_achat`), et l'argent
/// sort dans un second temps (`payer_achat`). Un achat valide et un achat
/// paye ne veulent donc pas dire la meme chose, et l'ecran doit pouvoir le
/// dire sans mentir.
///
/// Hors connexion, la photo est d'abord ecrite sur le telephone : une photo
/// de recolte perdue au champ ne se reprend pas. La proposition part ensuite
/// avec la file, photo comprise.
class DepotAchats {
  DepotAchats(this._base);

  final BaseLocale _base;

  /// La file d'attente du comptoir : ce qui attend une signature.
  Future<List<Achat>> fileAttente() async {
    final client = MboaReseau.client;
    if (client != null) {
      try {
        final lignes = await client
            .from('achats')
            .select()
            .eq('statut', 'propose')
            .order('propose_le', ascending: true);
        for (final ligne in lignes) {
          await _base.stocker(Entites.achat, ligne);
        }
        return lignes.map(Achat.fromMap).toList(growable: false);
      } catch (e) {
        debugPrint('file d achats distante indisponible: $e');
      }
    }

    final cache = await _base.lignesCachees(Entites.achat);
    return cache
        .map(Achat.fromMap)
        .where((a) => a.statut.estAttente)
        .toList(growable: false)
      ..sort((a, b) => (a.proposeLe ?? DateTime(0)).compareTo(b.proposeLe ?? DateTime(0)));
  }

  /// Les achats signes qui attendent encore leur argent.
  Future<List<Achat>> aPayer() async {
    final client = MboaReseau.client;
    if (client != null) {
      try {
        final lignes = await client
            .from('achats')
            .select()
            .eq('statut', 'valide')
            .order('valide_le', ascending: true);
        for (final ligne in lignes) {
          await _base.stocker(Entites.achat, ligne);
        }
        return lignes.map(Achat.fromMap).toList(growable: false);
      } catch (e) {
        debugPrint('achats a payer indisponibles: $e');
      }
    }

    final cache = await _base.lignesCachees(Entites.achat);
    return cache.map(Achat.fromMap).where((a) => a.statut.estDu).toList(growable: false);
  }

  /// Ce que le fournisseur connecte a vendu, du plus recent au plus ancien.
  Future<List<Achat>> mesAchats() async {
    final client = MboaReseau.client;
    if (client != null) {
      try {
        final lignes = await client.rpc<List<dynamic>>('mes_achats');
        final achats = lignes
            .whereType<Map<String, dynamic>>()
            .map(Achat.fromMap)
            .toList(growable: false);
        for (final achat in achats) {
          await _base.stocker(Entites.achat, achat.toMap());
        }
        // La fiche peut avoir un identifiant different de celui du profil :
        // c'est le cas d'un fournisseur ouvert au comptoir puis rattache a son
        // compte. On memorise cet identifiant pour que le cache hors ligne
        // retrouve ses achats au prochain demarrage.
        if (achats.isNotEmpty) {
          await _base.ecrireEtat('fournisseur', achats.first.fournisseurId);
        }
        return achats;
      } catch (e) {
        debugPrint('mes achats distants indisponibles: $e');
      }
    }

    final moi = await _base.lireEtat('fournisseur') ?? await _base.lireEtat('session');
    final cache = await _base.lignesCachees(Entites.achat);
    return cache
        .map(Achat.fromMap)
        .where((a) => moi == null || a.fournisseurId == moi)
        .toList(growable: false)
      ..sort((a, b) => (b.proposeLe ?? DateTime(0)).compareTo(a.proposeLe ?? DateTime(0)));
  }

  /// Ce que le comptoir doit encore, et ce qu'il a deja paye.
  Future<Map<String, int>> mesGains() async {
    final client = MboaReseau.client;
    if (client != null) {
      try {
        final lignes = await client.rpc<List<dynamic>>('mes_gains');
        final ligne = lignes.whereType<Map<String, dynamic>>().firstOrNull;
        if (ligne != null) {
          return {
            'paye': (ligne['paye'] as num?)?.round() ?? 0,
            'en_attente': (ligne['en_attente'] as num?)?.round() ?? 0,
          };
        }
      } catch (e) {
        debugPrint('gains distants indisponibles: $e');
      }
    }

    final moi = await _base.lireEtat('fournisseur') ?? await _base.lireEtat('session');
    final cache = await _base.lignesCachees(Entites.achat);
    var paye = 0;
    var attente = 0;
    for (final ligne in cache) {
      final achat = Achat.fromMap(ligne);
      if (moi != null && achat.fournisseurId != moi) continue;
      if (achat.statut.estPayee) paye += achat.montant;
      if (achat.statut.estDu || achat.statut.estAttente) attente += achat.montant;
    }
    return {'paye': paye, 'en_attente': attente};
  }

  /// Le fournisseur declare ce qu'il a. La photo est obligatoire : le
  /// comptoir achete sur image, pas sur une phrase.
  Future<Achat?> proposer({
    required String nom,
    required Categorie categorie,
    required double quantite,
    required Unite unite,
    required int prixDemande,
    required Uint8List photoOctets,
    Uint8List? audioOctets,
  }) async {
    final nomPropre = nom.trim();
    if (nomPropre.length < 2) {
      throw ArgumentError('La marchandise doit avoir un nom');
    }
    if (quantite <= 0) throw ArgumentError('Quantité invalide');
    if (prixDemande < 1) throw ArgumentError('Prix invalide');

    final reference = Identifiants.uuidV4();
    final photo = await MboaReseau.televerser(
      bucket: 'produits',
      dossier: 'achats',
      nom: '$reference.jpg',
      octets: photoOctets,
      mime: 'image/jpeg',
    );
    final audio = audioOctets == null
        ? null
        : await MboaReseau.televerser(
            bucket: 'audios',
            dossier: 'achats',
            nom: '$reference.m4a',
            octets: audioOctets,
            mime: 'audio/mp4',
          );

    final client = MboaReseau.client;
    if (client != null && photo != null) {
      try {
        final cree = await client.rpc<Map<String, dynamic>>(
          'proposer_achat',
          params: {
            'p_nom': nomPropre,
            'p_categorie': categorie.slug,
            'p_quantite': quantite,
            'p_unite': unite.slug,
            'p_prix_demande': prixDemande,
            'p_photo_url': photo,
            'p_audio_url': audio,
          },
        );
        if (cree != null) {
          await _base.stocker(Entites.achat, cree);
          return Achat.fromMap(cree);
        }
      } catch (e) {
        debugPrint('proposition refusee par le serveur: $e');
        return null;
      }
    }

    // Hors connexion, la photo dort sur le telephone jusqu'au prochain
    // envoi. Sans elle, la proposition n'a pas de sens : on ne cree rien.
    final locale = await _garderPhoto(photoOctets);
    final achat = Achat(
      id: reference,
      fournisseurId: (await _base.lireEtat('session')) ?? '',
      slug: Identifiants.slugDe(nomPropre),
      nom: nomPropre,
      categorie: categorie,
      unite: unite,
      quantite: quantite,
      prixDemande: prixDemande,
      photoUrl: locale,
      audioUrl: audio,
      proposeLe: DateTime.now(),
    );

    await _base.stocker(Entites.achat, achat.toMap());
    await _base.enfiler(
      entite: Entites.achat,
      id: reference,
      operation: 'rpc:proposer_achat',
      payload: {
        'achat_id': reference,
        'nom': nomPropre,
        'categorie': categorie.slug,
        'quantite': quantite,
        'unite': unite.slug,
        'prix_demande': prixDemande,
        'photo_locale': locale,
        'audio_url': audio,
      },
    );
    return achat;
  }

  /// Le comptoir saisit l'achat d'une fiche qui n'a pas de compte.
  ///
  /// La marchandise est devant lui : il la photographie, il note ce que le
  /// producteur a apporte et son prix. Pas de file hors ligne ici, parce que
  /// la photo n'aurait nulle part ou attendre sans un compte pour la
  /// reprendre : l'ecran demande alors de reessayer avec le reseau.
  Future<Achat?> proposerPour({
    required String fournisseurId,
    required String nom,
    required Categorie categorie,
    required double quantite,
    required Unite unite,
    required int prixDemande,
    required Uint8List photoOctets,
    Uint8List? audioOctets,
  }) async {
    final nomPropre = nom.trim();
    if (nomPropre.length < 2) {
      throw ArgumentError('La marchandise doit avoir un nom');
    }
    if (quantite <= 0) throw ArgumentError('Quantité invalide');
    if (prixDemande < 1) throw ArgumentError('Prix invalide');

    final client = MboaReseau.client;
    if (client == null) return null;

    final reference = Identifiants.uuidV4();
    final photo = await MboaReseau.televerser(
      bucket: 'produits',
      dossier: 'achats',
      nom: '$reference.jpg',
      octets: photoOctets,
      mime: 'image/jpeg',
    );
    if (photo == null) return null;

    final audio = audioOctets == null
        ? null
        : await MboaReseau.televerser(
            bucket: 'audios',
            dossier: 'achats',
            nom: '$reference.m4a',
            octets: audioOctets,
            mime: 'audio/mp4',
          );

    try {
      final cree = await client.rpc<Map<String, dynamic>>(
        'proposer_achat_pour',
        params: {
          'p_fournisseur_id': fournisseurId,
          'p_nom': nomPropre,
          'p_categorie': categorie.slug,
          'p_quantite': quantite,
          'p_unite': unite.slug,
          'p_prix_demande': prixDemande,
          'p_photo_url': photo,
          'p_audio_url': audio,
        },
      );
      if (cree != null) {
        await _base.stocker(Entites.achat, cree);
        return Achat.fromMap(cree);
      }
    } catch (e) {
      debugPrint('achat pour fournisseur refuse: $e');
    }
    return null;
  }

  /// Le comptoir signe. Le prix signe peut differer du prix demande : c'est
  /// la tout l'interet du marchandage, et ce prix-la fait entrer la
  /// marchandise au stock.
  Future<Achat?> valider({
    required Achat achat,
    required int prixAchat,
    int? prixRevente,
  }) async {
    if (prixAchat < 1) throw ArgumentError('Prix d’achat invalide');

    final client = MboaReseau.client;
    if (client != null) {
      try {
        final valide = await client.rpc<Map<String, dynamic>>(
          'valider_achat',
          params: {
            'p_achat_id': achat.id,
            'p_prix_achat': prixAchat,
            'p_prix_revente': prixRevente,
          },
        );
        if (valide != null) {
          await _base.stocker(Entites.achat, valide);
          await _base.vider(Entites.produit);
          return Achat.fromMap(valide);
        }
      } catch (e) {
        debugPrint('signature refusee: $e');
        return null;
      }
    }

    final local = achat
        .copieAvec(statut: StatutAchat.valide, prixMarchand: prixAchat)
        .toMap()
      ..['valide_le'] = DateTime.now().toIso8601String();
    await _base.stocker(Entites.achat, local);
    await _base.enfiler(
      entite: Entites.achat,
      id: achat.id,
      operation: 'rpc:valider_achat',
      payload: {
        'achat_id': achat.id,
        'prix_achat': prixAchat,
        'prix_revente': prixRevente,
      },
    );
    return Achat.fromMap(local);
  }

  Future<Achat?> payer(Achat achat) async {
    final client = MboaReseau.client;
    if (client != null) {
      try {
        final paye = await client.rpc<Map<String, dynamic>>(
          'payer_achat',
          params: {'p_achat_id': achat.id},
        );
        if (paye != null) {
          await _base.stocker(Entites.achat, paye);
          return Achat.fromMap(paye);
        }
      } catch (e) {
        debugPrint('paiement refuse: $e');
        return null;
      }
    }

    final local = achat.copieAvec(statut: StatutAchat.paye).toMap()
      ..['paye_le'] = DateTime.now().toIso8601String();
    await _base.stocker(Entites.achat, local);
    await _base.enfiler(
      entite: Entites.achat,
      id: achat.id,
      operation: 'rpc:payer_achat',
      payload: {'achat_id': achat.id},
    );
    return Achat.fromMap(local);
  }

  Future<Achat?> refuser({
    required Achat achat,
    String? motif,
    Uint8List? audioOctets,
    bool litige = false,
  }) async {
    final texte = motif?.trim();
    if ((texte == null || texte.isEmpty) && audioOctets == null) {
      throw ArgumentError('Un refus sans raison ne dit rien au producteur');
    }

    String? audio;
    if (audioOctets != null) {
      audio = await MboaReseau.televerser(
        bucket: 'audios',
        dossier: 'achats',
        nom: '${achat.id}-motif.m4a',
        octets: audioOctets,
        mime: 'audio/mp4',
      );
    }

    final client = MboaReseau.client;
    if (client != null) {
      try {
        final refuse = await client.rpc<Map<String, dynamic>>(
          'refuser_achat',
          params: {
            'p_achat_id': achat.id,
            'p_motif': texte,
            'p_motif_audio_url': audio,
            'p_litige': litige,
          },
        );
        if (refuse != null) {
          await _base.stocker(Entites.achat, refuse);
          return Achat.fromMap(refuse);
        }
      } catch (e) {
        debugPrint('refus refuse par le serveur: $e');
        return null;
      }
    }

    final local = achat
        .copieAvec(statut: litige ? StatutAchat.litige : StatutAchat.annule)
        .toMap()
      ..['motif'] = texte;
    await _base.stocker(Entites.achat, local);
    await _base.enfiler(
      entite: Entites.achat,
      id: achat.id,
      operation: 'rpc:refuser_achat',
      payload: {
        'achat_id': achat.id,
        'motif': texte,
        'audio_url': audio,
        'litige': litige,
      },
    );
    return Achat.fromMap(local);
  }

  Future<String> _garderPhoto(Uint8List octets) async {
    final dossier = await getApplicationDocumentsDirectory();
    final repertoire = Directory('${dossier.path}/mboa_achats');
    if (!await repertoire.exists()) {
      await repertoire.create(recursive: true);
    }
    final fichier = File('${repertoire.path}/${Identifiants.uuidV4()}.jpg');
    await fichier.writeAsBytes(octets, flush: true);
    return fichier.path;
  }
}
