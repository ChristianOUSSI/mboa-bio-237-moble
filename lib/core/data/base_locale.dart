import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as chemin;

/// Le telephone d'abord, le serveur ensuite.
///
/// Un Tecno au champ n'a parfois pas de credit data de la journee. Plutot que
/// de synchroniser colonne par colonne (et de casser a chaque migration SQL),
/// cette base stocke des lignes entieres en JSON, avec les seules colonnes
/// dont l'app a besoin pour filtrer hors connexion. C'est le meme modele que
/// le « document cache » des SDK Firebase ou Supabase.
///
/// Trois tables, pas une de plus :
///   * `cache`  : la derniere version connue d'une ligne distante ou locale ;
///   * `file`   : les ecritures pas encore acceptees par le serveur ;
///   * `etat`   : session, derniere synchro, langue choisie.
class BaseLocale {
  BaseLocale._(this._db);

  static const int _version = 1;
  static const String _nomFichier = 'mboa_bio.sqlite';

  final Database _db;

  static Future<BaseLocale> ouvrir({String? pourTest}) async {
    final repertoire = await getDatabasesPath();
    final fichier = chemin.join(repertoire, pourTest ?? _nomFichier);
    final db = await openDatabase(
      fichier,
      version: _version,
      onConfigure: (d) async => d.execute('PRAGMA foreign_keys = ON'),
      onCreate: (d, v) => _creer(d),
    );
    return BaseLocale._(db);
  }

  static Future<void> _creer(Database db) async {
    await db.execute('''
      create table cache (
        entite       text not null,
        id           text not null,
        payload      text not null,
        fournisseur  text,
        consommateur text,
        etat         text,
        ecrit_le     integer not null,
        primary key (entite, id)
      )
    ''');
    await db.execute('create index cache_fournisseur on cache (entite, fournisseur)');
    await db.execute('create index cache_consommateur on cache (entite, consommateur)');
    await db.execute('create index cache_etat on cache (entite, etat)');

    await db.execute('''
      create table file (
        cle       text primary key,
        entite    text not null,
        id        text not null,
        operation text not null,
        payload   text not null,
        cree_le   integer not null
      )
    ''');

    await db.execute('''
      create table etat (
        cle    text primary key,
        valeur text not null
      )
    ''');
  }

  // --------------------------------------------------------------------------
  // Cache
  // --------------------------------------------------------------------------

  /// Remplace ou ajoute une ligne. Le payload est la copie fidele de la ligne
  /// distante, colonnes comprises : les modeles Dart font la conversion.
  Future<void> stocker(String entite, Map<String, dynamic> ligne) async {
    // L'identifiant arrive en texte des tables uuid, mais en entier des
    // colonnes bigint comme `mboa.notifications` : on normalise en chaine.
    final brut = ligne['id'] ?? ligne['slug'];
    if (brut == null) {
      debugPrint('ligne sans id ignoree dans $entite');
      return;
    }

    await _db.insert(
      'cache',
      {
        'entite': entite,
        'id': brut.toString(),
        'payload': jsonEncode(ligne),
        'fournisseur': ligne['fournisseur_id'] as String?,
        'consommateur': ligne['consommateur_id'] as String?,
        'etat': (ligne['statut'] ?? ligne['statut_enum'] ?? ligne['role']) as String?,
        'ecrit_le': DateTime.now().millisecondsSinceEpoch,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<List<Map<String, dynamic>>> lignesCachees(
    String entite, {
    String? fournisseur,
    String? consommateur,
    String? etat,
    int? limite,
  }) async {
    final clauses = <String>['entite = ?'];
    final valeurs = <Object?>[entite];

    if (fournisseur != null) {
      clauses.add('fournisseur = ?');
      valeurs.add(fournisseur);
    }
    if (consommateur != null) {
      clauses.add('consommateur = ?');
      valeurs.add(consommateur);
    }
    if (etat != null) {
      clauses.add('etat = ?');
      valeurs.add(etat);
    }

    final lignes = await _db.query(
      'cache',
      where: clauses.join(' and '),
      whereArgs: valeurs,
      orderBy: 'ecrit_le desc',
      limit: limite,
    );

    return lignes.map((l) => jsonDecode(l['payload'] as String) as Map<String, dynamic>).toList();
  }

  Future<void> supprimerDuCache(String entite, String id) =>
      _db.delete('cache', where: 'entite = ? and id = ?', whereArgs: [entite, id]);

  Future<void> vider(String entite) =>
      _db.delete('cache', where: 'entite = ?', whereArgs: [entite]);

  // --------------------------------------------------------------------------
  // File d'envoi
  // --------------------------------------------------------------------------

  /// Une ecriture part toujours par la file : `depots.dart` l'execute en
  /// direct si le reseau repond, et la relit ici sinon.
  Future<void> enfiler({
    required String entite,
    required String id,
    required String operation,
    required Map<String, dynamic> payload,
  }) =>
      _db.insert(
        'file',
        {
          'cle': '$entite:$id:$operation',
          'entite': entite,
          'id': id,
          'operation': operation,
          'payload': jsonEncode(payload),
          'cree_le': DateTime.now().millisecondsSinceEpoch,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );

  Future<List<Map<String, dynamic>>> file() =>
      _db.query('file', orderBy: 'cree_le asc');

  Future<void> desenfiler(String cle) =>
      _db.delete('file', where: 'cle = ?', whereArgs: [cle]);

  Future<int> tailleFile() async {
    final lignes = await _db.query('file');
    return lignes.length;
  }

  // --------------------------------------------------------------------------
  // Etat applicatif
  // --------------------------------------------------------------------------

  Future<void> ecrireEtat(String cle, String valeur) => _db.insert(
        'etat',
        {'cle': cle, 'valeur': valeur},
        conflictAlgorithm: ConflictAlgorithm.replace,
      );

  Future<void> supprimerEtat(String cle) =>
      _db.delete('etat', where: 'cle = ?', whereArgs: [cle]);

  Future<String?> lireEtat(String cle) async {
    final lignes = await _db.query('etat', where: 'cle = ?', whereArgs: [cle], limit: 1);
    return lignes.isEmpty ? null : lignes.first['valeur'] as String;
  }

  Future<void> fermer() => _db.close();
}

/// Noms d'entites du cache. Une seule source, pour qu'un `entite:` tape a la
/// main dans un depot ne cree pas deux copies de la meme ligne.
class Entites {
  const Entites._();

  static const String profil = 'profil';
  static const String produit = 'produit';
  static const String commande = 'commande';
  static const String catalogue = 'catalogue';

  /// La projection publique lue par la cliente, sans les colonnes d'achat.
  /// Separee du stock admin pour qu'un cache admin ne fuite jamais ses prix
  /// d'achat vers l'ecran de la cliente.
  static const String vitrine = 'vitrine';

  /// Les achats du comptoir chez les agriculteurs.
  static const String achat = 'achat';

  /// Le journal de bord des colis, une ligne par jalon pose.
  static const String suivi = 'suivi';

  /// Les listes de marche preparees par les clientes.
  static const String liste = 'liste';

  /// Le tableau des moto qui portent les paniers.
  static const String livreur = 'livreur';

  /// Le fichier des producteurs du comptoir, avec ou sans compte.
  static const String fournisseur = 'fournisseur';

  /// Les notifications n'ont pas de `role` ni de `id` uuid : les melanger aux
  /// profils ferait echouer la lecture de session.
  static const String notification = 'notification';
}
