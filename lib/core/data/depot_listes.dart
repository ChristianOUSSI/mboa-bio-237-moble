import 'dart:typed_data';

import 'package:flutter/foundation.dart';

import '../utils/identifiants.dart';
import 'base_locale.dart';
import 'mboa_reseau.dart';
import 'models/commande.dart';
import 'models/liste.dart';

/// Listes de marche : preparer, montrer, transformer.
///
/// Une liste n'est pas un panier qui attend. C'est un papier que la mama
/// compose quand elle veut, qu'elle envoie a sa fille, montre au livreur ou
/// dicte au telephone grace a son code court, et qu'elle transforme en
/// commande le jour ou elle a decide.
///
/// Le code est genere cote client et verifie par une contrainte unique cote
/// serveur : si deux listes se heurtent sur le meme code, la deuxieme
/// echoue et l'app en regenere un. Rien n'est perdu, et aucune mama ne
/// partage le code d'une autre.
class DepotListes {
  DepotListes(this._base);

  final BaseLocale _base;


  Future<List<ListeMarche>> mesListes(String consommateurId) async {
    final client = MboaReseau.client;
    if (client != null) {
      try {
        final lignes = await client
            .from('listes')
            .select()
            .eq('consommateur_id', consommateurId)
            .order('created_at', ascending: false)
            .limit(40);
        for (final ligne in lignes) {
          await _base.stocker(Entites.liste, ligne);
        }
        return lignes.map(ListeMarche.fromMap).toList();
      } catch (e) {
        debugPrint('listes distantes indisponibles: $e');
      }
    }

    final lignes = await _base.lignesCachees(Entites.liste, consommateur: consommateurId);
    return lignes.map(ListeMarche.fromMap).toList()
      ..sort((a, b) => b.createdLe.compareTo(a.createdLe));
  }

  /// Retrouver une liste par son code, pour l'agent qui recoit l'appel.
  ///
  /// L'RPC `mboa.liste_par_code` ne rend ni le numero ni l'identite de la
  /// cliente : juste ce qu'il faut pour confirmer qu'on a la bonne liste.
  Future<Map<String, dynamic>?> parCode(String code) async {
    final client = MboaReseau.client;
    if (client == null) {
      for (final ligne in await _base.lignesCachees(Entites.liste)) {
        if ((ligne['code'] ?? '').toString().toLowerCase() == code.toLowerCase()) {
          return ligne;
        }
      }
      return null;
    }

    try {
      final json = await client.rpc('liste_par_code', params: {'p_code': code});
      return json as Map<String, dynamic>?;
    } catch (e) {
      debugPrint('code $code inconnu: $e');
      return null;
    }
  }

  /// Cree la liste, avec un code garanti unique sur l'appareil.
  Future<ListeMarche> creer({
    required String consommateurId,
    required List<LigneCommande> lignes,
    required String titre,
    String? consommateurNom,
    String? consommateurTelephone,
  }) async {
    if (lignes.isEmpty) throw StateError('Liste vide');

    var code = CodeListe.generer();
    for (var tentative = 0;
         tentative < 5 && await _codePris(code);
         tentative++) {
      code = CodeListe.generer();
    }

    final liste = ListeMarche(
      id: Identifiants.uuidV4(),
      consommateurId: consommateurId,
      lignes: lignes,
      code: code,
      titre: titre.trim().isEmpty ? 'Ma liste' : titre.trim(),
      createdLe: DateTime.now(),
      consommateurNom: consommateurNom,
      consommateurTelephone: consommateurTelephone,
    );

    await _base.stocker(Entites.liste, liste.toMap());

    final client = MboaReseau.client;
    if (client == null) {
      await _base.enfiler(
        entite: Entites.liste,
        id: liste.id,
        operation: 'insert',
        payload: liste.toMap(),
      );
      return liste;
    }

    try {
      final creees = await client.from('listes').insert(liste.toMap()).select();
      final recreee = ListeMarche.fromMap(creees.first);
      await _base.stocker(Entites.liste, recreee.toMap());
      return recreee;
    } catch (e) {
      debugPrint('liste distante en attente: $e');
      await _base.enfiler(
        entite: Entites.liste,
        id: liste.id,
        operation: 'insert',
        payload: liste.toMap(),
      );
      return liste;
    }
  }

  Future<void> modifierLignes({
    required String id,
    required List<LigneCommande> lignes,
    String? titre,
  }) async {
    final lignesCachees = await _base.lignesCachees(Entites.liste);
    final existante = lignesCachees.where((l) => l['id'] == id);
    if (existante.isEmpty) return;

    final modifications = <String, dynamic>{
      'produits': lignes.map((l) => l.toJson()).toList(),
      'montant_estime': lignes.fold(0, (somme, l) => somme + l.sousTotal),
      if (titre != null) 'titre': titre,
    };
    await _base.stocker(Entites.liste, {...existante.first, ...modifications});

    final client = MboaReseau.client;
    if (client == null) {
      await _base.enfiler(
        entite: Entites.liste,
        id: id,
        operation: 'update',
        payload: {'id': id, ...modifications},
      );
      return;
    }
    try {
      await client.from('listes').update(modifications).eq('id', id);
    } catch (e) {
      debugPrint('liste locale, envoi en attente: $e');
      await _base.enfiler(
        entite: Entites.liste,
        id: id,
        operation: 'update',
        payload: {'id': id, ...modifications},
      );
    }
  }

  /// Enregistre l'image filigranee une fois generee sur le telephone.
  ///
  /// L'image est produite cote cliente : elle part en PNG dans le bucket
  /// public `listes`, et son URL devient celle que la mama partage sur
  /// WhatsApp. Si le televersement echoue, la liste reste valide sur
  /// l'appareil et l'image se represente a la prochaine connexion.
  Future<String?> enregistrerImage({
    required String id,
    required String consommateurId,
    required Uint8List png,
  }) async {
    final chemin = await MboaReseau.televerser(
      bucket: 'listes',
      dossier: consommateurId,
      nom: '$id.png',
      octets: png,
      mime: 'image/png',
    );
    if (chemin == null) return null;

    final lignes = await _base.lignesCachees(Entites.liste);
    final existante = lignes.where((l) => l['id'] == id);
    if (existante.isNotEmpty) {
      await _base.stocker(Entites.liste, {...existante.first, 'image_url': chemin});
    }

    final client = MboaReseau.client;
    if (client != null) {
      try {
        await client.from('listes').update({'image_url': chemin}).eq('id', id);
      } catch (e) {
        debugPrint('image de liste en attente: $e');
      }
    }
    return chemin;
  }

  Future<void> marquerEnvoyee(String id) async {
    final maintenant = DateTime.now().toIso8601String();
    final lignes = await _base.lignesCachees(Entites.liste);
    final existante = lignes.where((l) => l['id'] == id);
    if (existante.isNotEmpty) {
      await _base.stocker(Entites.liste, {...existante.first, 'envoyee_le': maintenant});
    }

    final client = MboaReseau.client;
    if (client != null) {
      try {
        await client.from('listes').update({'envoyee_le': maintenant}).eq('id', id);
      } catch (e) {
        debugPrint('envoi non transmis: $e');
      }
    }
  }

  /// Attache la commande nee de la liste, sans effacer la liste.
  Future<void> marquerTransformee(String id, String commandeId) async {
    final maintenant = DateTime.now().toIso8601String();
    final lignes = await _base.lignesCachees(Entites.liste);
    final existante = lignes.where((l) => l['id'] == id);
    if (existante.isNotEmpty) {
      await _base.stocker(Entites.liste, {
        ...existante.first,
        'transformee_en': commandeId,
        'transformee_le': maintenant,
      });
    }

    final client = MboaReseau.client;
    if (client != null) {
      try {
        await client
            .from('listes')
            .update({'transformee_en': commandeId, 'transformee_le': maintenant})
            .eq('id', id);
      } catch (e) {
        debugPrint('transformation non transmise: $e');
      }
    }
  }

  /// La liste en cours de la cliente : la plus recente non transformee.
  ///
  /// Une seule liste active, volontairement. Plusieurs listes, c'est un
  /// choix a faire avant de savoir ce qu'on cherche, et une mama de 60 ans
  /// n'a pas a arbitrer entre « liste du mardi » et « liste de la semaine ».
  Future<ListeMarche?> listeActive(String consommateurId) async {
    final toutes = await mesListes(consommateurId);
    for (final liste in toutes) {
      if (!liste.estTransformee) return liste;
    }
    return null;
  }

  Future<void> supprimer(String id) async {
    await _base.supprimerDuCache(Entites.liste, id);
    final client = MboaReseau.client;
    if (client == null) return;
    try {
      await client.from('listes').delete().eq('id', id);
    } catch (e) {
      debugPrint('suppression de liste echouee: $e');
    }
  }

  /// Rattache le moto qui a porte la commande nee de cette liste.
  ///
  /// Une liste n'a pas de livreur dans sa propre table : le livreur est
  /// affecte a la commande. Cette methode fait le pont pour que le papier
  /// partage porte « qui vient », et elle echoue en silence : une image sans
  /// bloc livreur reste une image utile, et une liste dont la commande n'est
  /// pas relisible n'est pas une erreur.
  Future<ListeMarche> avecLivreur(ListeMarche liste) async {
    final commandeId = liste.transformeeEn;
    if (commandeId == null || commandeId.isEmpty) return liste;

    final client = MboaReseau.client;
    Map<String, dynamic>? ligne;

    if (client != null) {
      try {
        ligne = await client
            .from('commandes')
            .select('livreur_id, livreur:livreurs!livreur_id(nom, plaque, tarif_course)')
            .eq('id', commandeId)
            .maybeSingle();
      } catch (e) {
        debugPrint('livreur de liste illisible: $e');
        return liste;
      }
    } else {
      for (final c in await _base.lignesCachees(Entites.commande)) {
        if (c['id'] == commandeId) ligne = c;
      }
    }

    if (ligne == null) return liste;

    final livreur = ligne['livreur'];
    final carte = livreur is Map<String, dynamic> ? livreur : const <String, dynamic>{};
    final nom = (carte['nom'] ?? ligne['nom_livreur']) as String?;
    if (nom == null || nom.isEmpty) return liste;

    final contact = await _contactLivreur(commandeId);

    return liste.copieAvec(
      livreurNom: nom,
      livreurPlaque: (carte['plaque'] ?? ligne['plaque']) as String?,
      livreurTelephone: contact,
      // La jointure rend `tarif_course`, le cache local rend `tarif_livreur` :
      // les deux formes se recoupent comme pour le reste du livreur.
      livreurTarif:
          (carte['tarif_course'] ?? ligne['tarif_livreur']) is num
              ? ((carte['tarif_course'] ?? ligne['tarif_livreur']) as num).round()
              : null,
    );
  }

  Future<String?> _contactLivreur(String commandeId) async {
    final client = MboaReseau.client;
    if (client == null) return null;
    try {
      final numero = await client.rpc('contact_livreur', params: {'p_commande_id': commandeId});
      return numero as String?;
    } catch (_) {
      // Pas partie a la course, pas de numero : la RLS a raison de refuser.
      return null;
    }
  }

  Future<bool> _codePris(String code) async {
    for (final ligne in await _base.lignesCachees(Entites.liste)) {
      if ((ligne['code'] ?? '').toString() == code) return true;
    }

    final client = MboaReseau.client;
    if (client == null) return false;
    try {
      final trouve = await client.from('listes').select('id').eq('code', code).maybeSingle();
      return trouve != null;
    } catch (_) {
      // Un code deja pris dans le monde mais invisible ici sera rejete par
      // la contrainte unique du serveur, et la liste repartira en file.
      return false;
    }
  }
}
