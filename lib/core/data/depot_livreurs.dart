import 'dart:typed_data';

import 'package:flutter/foundation.dart';

import '../utils/identifiants.dart';
import 'base_locale.dart';
import 'depot_auth.dart' show normaliserTelephone;
import 'mboa_reseau.dart';
import 'models/livreur.dart';

/// Le tableau des livreurs.
///
/// Lecture ouverte a tous, ecriture reservee a l'admin : la policy
/// `livreurs_ecriture_admin` la garde cote serveur, et les methodes d'ecriture
/// ici ne font que renvoyer null quand elle refuse, pour que l'ecran puisse le
/// dire plutot que d'afficher une exception.
///
/// Le telephone ne passe jamais par [tous] en mode distant : la vue
/// `vitrine_livreurs` ne l'expose pas. Il vient de la table complete, que la
/// RLS rend seulement a l'admin, et du cache local en demonstration.
class DepotLivreurs {
  DepotLivreurs(this._base);

  final BaseLocale _base;

  static const String _colonnesVitrine =
      'id, nom, zone, photo, moto, plaque, tarif_course, actif';

  Future<List<Livreur>> tous({bool seulementActifs = true}) async {
    final client = MboaReseau.client;
    if (client != null) {
      try {
        final requete = client.from('livreurs').select(_colonnesVitrine);
        final lignes = seulementActifs
            ? await requete.eq('actif', true).order('zone')
            : await requete.order('zone');
        for (final ligne in lignes) {
          await _base.stocker(Entites.livreur, ligne);
        }
        return lignes.map(Livreur.fromMap).toList();
      } catch (e) {
        debugPrint('livreur distant indisponible: $e');
      }
    }

    final lignes = await _base.lignesCachees(Entites.livreur);
    final livreurs = lignes.map(Livreur.fromMap).toList()
      ..sort((a, b) => a.zone.compareTo(b.zone));
    return seulementActifs ? livreurs.where((l) => l.actif).toList() : livreurs;
  }

  /// La fiche rattachée au compte connecté, s'il y en a une.
  ///
  /// Un compte `livreur` sans fiche ne peut pas travailler : c'est le
  /// comptoir qui crée la fiche et y rattache le profil. L'identifiant de la
  /// fiche est mémorisé localement pour que [DepotCommandes.mesCourses]
  /// retrouve les courses au cache quand la 3G tombe.
  Future<Livreur?> maFiche() async {
    final client = MboaReseau.client;
    final profilId = client?.auth.currentUser?.id;
    if (client != null && profilId != null) {
      try {
        final lignes = await client
            .from('livreurs')
            .select(_colonnesVitrine)
            .eq('profil_id', profilId)
            .eq('actif', true)
            .limit(1);
        if (lignes.isNotEmpty) {
          final fiche = Livreur.fromMap(lignes.first);
          await _base.stocker(Entites.livreur, lignes.first);
          await _base.ecrireEtat('livreur', fiche.id);
          return fiche;
        }
        await _base.supprimerEtat('livreur');
        return null;
      } catch (e) {
        debugPrint('fiche livreur indisponible: $e');
      }
    }

    final id = await _base.lireEtat('livreur');
    if (id == null || id.isEmpty) return null;
    for (final l in await _base.lignesCachees(Entites.livreur)) {
      if (l['id'] == id) return Livreur.fromMap(l);
    }
    return null;
  }

  /// Enregistre un livreur. Renvoie null si le serveur refuse.
  Future<Livreur?> creer({
    required String nom,
    required String telephone,
    required String zone,
    String? moto,
    String? plaque,
    int tarifCourse = 0,
    Uint8List? photoOctets,
  }) async {
    final numero = normaliserTelephone(telephone);
    if (numero == null) throw ArgumentError('Numero de livreur invalide');

    final id = Identifiants.uuidV4();

    final cheminPhoto = photoOctets == null
        ? null
        : await MboaReseau.televerser(
            bucket: 'visages',
            dossier: id,
            nom: 'livreur.jpg',
            octets: photoOctets,
            mime: 'image/jpeg',
          );

    final livreur = Livreur(
      id: id,
      nom: nom.trim(),
      telephone: numero,
      zone: zone.trim(),
      moto: moto?.trim(),
      plaque: plaque?.trim(),
      photo: cheminPhoto,
      tarifCourse: tarifCourse,
    );

    await _base.stocker(Entites.livreur, livreur.toMap());

    final client = MboaReseau.client;
    if (client == null) return livreur;

    try {
      // Le numero n'est pas lisible en retour : la 0012 a retire le privilege
      // de colonne pour qu'aucun select ne le rende. On relit les colonnes de
      // service, et on garde le numero deja saisi par l'admin.
      final cree = await client
          .from('livreurs')
          .insert(livreur.toMap())
          .select(_colonnesVitrine);
      final recu = Livreur.fromMap({...livreur.toMap(), ...cree.first});
      await _base.stocker(Entites.livreur, recu.toMap());
      return recu;
    } catch (e) {
      debugPrint('livreur refuse par le serveur: $e');
      return null;
    }
  }

  Future<Livreur?> modifier(Livreur livreur, {Uint8List? photoOctets}) async {
    String? cheminPhoto;
    if (photoOctets != null) {
      cheminPhoto = await MboaReseau.televerser(
        bucket: 'visages',
        dossier: livreur.id,
        nom: 'livreur.jpg',
        octets: photoOctets,
        mime: 'image/jpeg',
      );
    }

    final maj = livreur.copieAvec(photo: cheminPhoto ?? livreur.photo);
    await _base.stocker(Entites.livreur, maj.toMap());

    final client = MboaReseau.client;
    if (client == null) return maj;

    try {
      final lignes = await client
          .from('livreurs')
          .update(maj.toMap()..remove('id'))
          .eq('id', maj.id)
          .select(_colonnesVitrine);
      final recu = Livreur.fromMap({...maj.toMap(), ...lignes.first});
      await _base.stocker(Entites.livreur, recu.toMap());
      return recu;
    } catch (e) {
      debugPrint('modification de livreur refusee: $e');
      return null;
    }
  }

  /// Le numero du livreur, pour le comptoir.
  ///
  /// La 0012 a retire le privilege de colonne pour que le numero ne sorte
  /// plus par un select. L'admin le lit par `telephone_livreur`, une porte
  /// nommee que la RLS du serveur garde.
  Future<String?> telephone(String id) async {
    final client = MboaReseau.client;
    if (client != null) {
      try {
        final numero = await client.rpc(
          'telephone_livreur',
          params: {'p_livreur_id': id},
        );
        if (numero is String && numero.isNotEmpty) {
          final lignes = await _base.lignesCachees(Entites.livreur);
          final existante = lignes.where((l) => l['id'] == id);
          if (existante.isNotEmpty) {
            await _base.stocker(Entites.livreur, {...existante.first, 'telephone_237': numero});
          }
          return numero;
        }
      } catch (e) {
        debugPrint('numero de livreur indisponible: $e');
      }
    }

    for (final l in await _base.lignesCachees(Entites.livreur)) {
      if (l['id'] == id) return l['telephone_237'] as String?;
    }
    return null;
  }

  /// Desactiver, jamais supprimer.
  ///
  /// Une course payee sans livreur identifiable est une course contestee :
  /// la ligne reste, elle cesse juste d'etre proposee a l'affectation.
  Future<bool> desactiver(String id) async {
    final lignes = await _base.lignesCachees(Entites.livreur);
    final existante = lignes.where((l) => l['id'] == id);
    if (existante.isNotEmpty) {
      await _base.stocker(Entites.livreur, {...existante.first, 'actif': false});
    }

    final client = MboaReseau.client;
    if (client == null) return true;
    try {
      await client.from('livreurs').update({'actif': false}).eq('id', id);
      return true;
    } catch (e) {
      debugPrint('desactivation de livreur refusee: $e');
      return false;
    }
  }

  /// Affecte un livreur a une commande.
  ///
  /// L'RPC fait trois choses d'un coup cote serveur : la colonne, le passage
  /// en `en_livraison` si la commande etait validee, et la notification. Le
  /// client n'a rien a orchestrer.
  Future<bool> affecter({
    required String commandeId,
    required String livreurId,
  }) async {
    final client = MboaReseau.client;
    if (client == null) {
      await _majCacheCommande(commandeId, {'livreur_id': livreurId});
      return true;
    }

    try {
      final maj = await client.rpc<Map<String, dynamic>>(
        'affecter_livreur',
        params: {'p_commande_id': commandeId, 'p_livreur_id': livreurId},
      );
      if (maj != null) await _base.stocker(Entites.commande, maj);
      return true;
    } catch (e) {
      debugPrint('affectation refusee: $e');
      await _majCacheCommande(commandeId, {'livreur_id': livreurId});
      return false;
    }
  }

  /// Le numero du livreur, pour l'appel.
  Future<String?> contact(String commandeId) async {
    final client = MboaReseau.client;
    if (client != null) {
      try {
        final numero = await client.rpc('contact_livreur', params: {'p_commande_id': commandeId});
        return numero as String?;
      } catch (e) {
        debugPrint('contact livreur refuse: $e');
        return null;
      }
    }

    final commandes = await _base.lignesCachees(Entites.commande);
    final livreurId = commandes
        .where((c) => c['id'] == commandeId)
        .map((c) => c['livreur_id'] as String?)
        .firstOrNull;
    if (livreurId == null) return null;

    for (final l in await _base.lignesCachees(Entites.livreur)) {
      if (l['id'] == livreurId) return l['telephone_237'] as String?;
    }
    return null;
  }

  Future<void> _majCacheCommande(String id, Map<String, dynamic> modifications) async {
    final lignes = await _base.lignesCachees(Entites.commande);
    final existante = lignes.where((l) => l['id'] == id);
    if (existante.isEmpty) return;
    await _base.stocker(Entites.commande, {...existante.first, ...modifications});
  }
}
