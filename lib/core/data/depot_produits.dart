import 'dart:typed_data';

import 'package:flutter/foundation.dart';

import '../utils/identifiants.dart';
import 'base_locale.dart';
import 'catalogue_hors_ligne.dart';
import 'mboa_reseau.dart';
import 'models/catalogue.dart';
import 'models/categorie.dart';
import 'models/pack_composant.dart';
import 'models/produit.dart';
import 'models/unite.dart';

/// Le stock du comptoir : lecture, catalogue, packs.
///
/// Chemin unique pour les trois apps. Chaque méthode suit la même discipline :
///   1. écrire le cache local en premier, jamais l'inverse ;
///   2. tenter le serveur ;
///   3. s'il ne répond pas, encoder l'intention dans la file.
///
/// Le comptoir achète ferme chez l'agriculteur et revend : il n'y a plus de
/// `fournisseur_id` sur un produit, plus de `moderation`, plus de `nom_enum`.
/// La vitrine est une vue qui ne sélectionne pas `prix_achat`, et c'est elle
/// que la cliente lit.
class DepotProduits {
  DepotProduits(this._base);

  final BaseLocale _base;

  // --------------------------------------------------------------------------
  // Lecture
  // --------------------------------------------------------------------------

  /// Ce que voit la cliente : la vue `vitrine`, sans le prix d'achat.
  Future<List<Produit>> vitrine({Categorie? filtre}) async {
    final client = MboaReseau.client;
    if (client != null) {
      try {
        final filtreBase = client
            .from('vitrine')
            .select();

        final lignes = await (filtre == null
                ? filtreBase
                : filtreBase.eq('categorie', filtre.slug))
            .order('nom', ascending: true)
            .limit(60);

        for (final ligne in lignes) {
          await _base.stocker(Entites.produit, ligne);
        }
        return lignes.map(Produit.fromMap).toList();
      } catch (e) {
        debugPrint('vitrine distante indisponible: $e');
      }
    }

    final lignes = await _base.lignesCachees(Entites.produit);
    final produits = lignes.map(Produit.fromMap).where((p) => p.estVitrine).toList()
      ..sort((a, b) => a.nom.compareTo(b.nom));
    return filtre == null ? produits : produits.where((p) => p.categorie == filtre).toList();
  }

  /// Tout le stock du comptoir, y compris épuisé et inactif : pour l'admin.
  Future<List<Produit>> stock() async {
    final client = MboaReseau.client;
    if (client != null) {
      try {
        final lignes = await client
            .from('produits')
            .select()
            .order('categorie', ascending: true)
            .order('nom', ascending: true);
        for (final ligne in lignes) {
          await _base.stocker(Entites.produit, ligne);
        }
        return lignes.map(Produit.fromMap).toList();
      } catch (e) {
        debugPrint('stock distant indisponible: $e');
      }
    }

    final lignes = await _base.lignesCachees(Entites.produit);
    return lignes.map(Produit.fromMap).toList()
      ..sort((a, b) {
        final cat = a.categorie.ordre.compareTo(b.categorie.ordre);
        return cat != 0 ? cat : a.nom.compareTo(b.nom);
      });
  }

  /// Les 8 cases du catalogue, dans l'ordre de la grille.
  Future<List<EntreeCatalogue>> catalogue() async {
    final client = MboaReseau.client;
    if (client != null) {
      try {
        final lignes = await client.from('catalogue').select().order('ordre');
        for (final ligne in lignes) {
          await _base.stocker(Entites.catalogue, ligne);
        }
        return lignes.map(EntreeCatalogue.fromMap).toList();
      } catch (e) {
        debugPrint('catalogue distant indisponible: $e');
      }
    }

    final lignes = await _base.lignesCachees(Entites.catalogue);
    if (lignes.isEmpty) return catalogueHorsLigne();
    return lignes.map(EntreeCatalogue.fromMap).toList()
      ..sort((a, b) => a.ordre.compareTo(b.ordre));
  }

  /// Les packs composés par l'admin, même épuisés.
  ///
  /// La vitrine les filtre à quantite > 0, ce qui est juste pour la cliente
  /// et faux pour l'admin : un pack à zéro part est une recette à
  /// réapprovisionner, pas une recette à oublier.
  Future<List<Produit>> packs() async {
    final client = MboaReseau.client;
    if (client != null) {
      try {
        final lignes = await client
            .from('produits')
            .select()
            .not('pack_composants', 'is', null)
            .order('nom', ascending: false)
            .limit(80);
        for (final ligne in lignes) {
          await _base.stocker(Entites.produit, ligne);
        }
        return lignes.map(Produit.fromMap).toList();
      } catch (e) {
        debugPrint('packs distants indisponibles: $e');
      }
    }

    final lignes = await _base.lignesCachees(Entites.produit);
    return lignes.map(Produit.fromMap).where((p) => p.estPack).toList();
  }

  // --------------------------------------------------------------------------
  // Écriture
  // --------------------------------------------------------------------------

  /// Ajuste le prix d'une fiche, côté comptoir.
  ///
  /// La quantité ne se modifie pas ici : elle appartient aux RPC d'achat
  /// (entrée) et de devis (sortie). Une fiche dont l'écran écrirait la
  /// quantité directement fausserait l'inventaire sans laisser de trace.
  Future<void> ajusterPrix({
    required String id,
    required int prix,
  }) async {
    final modifications = <String, dynamic>{'prix': prix};
    await _majCache(id, modifications);

    final client = MboaReseau.client;
    if (client == null) {
      await _enfile('update', {'id': id, ...modifications});
      return;
    }
    try {
      await client.from('produits').update(modifications).eq('id', id);
    } catch (e) {
      debugPrint('ajustement distant en attente: $e');
      await _enfile('update', {'id': id, ...modifications});
    }
  }

  /// Active ou désactive une référence : la retire de la vitrine sans
  /// l'effacer, pour que l'historique des ventes survive.
  Future<void> basculerActif({
    required String id,
    required bool actif,
  }) async {
    final modifications = <String, dynamic>{'actif': actif};
    await _majCache(id, modifications);

    final client = MboaReseau.client;
    if (client == null) {
      await _enfile('update', {'id': id, ...modifications});
      return;
    }
    try {
      await client.from('produits').update(modifications).eq('id', id);
    } catch (e) {
      debugPrint('bascule distante en attente: $e');
      await _enfile('update', {'id': id, ...modifications});
    }
  }

  /// Met à jour le prix de tendance d'un produit du catalogue.
  ///
  /// Seuls les admins y ont droit (policy `catalogue_ecriture_admin`). Ce
  /// prix ne change aucune vente déjà figée : il ne vaut que pour les
  /// propositions d'achat suivantes et pour le conseil à l'admin.
  Future<void> majPrixMarche({
    required String slug,
    required int prix,
    List<int>? paliers,
  }) async {
    final modifications = <String, dynamic>{
      'prix_tendance': prix,
      if (paliers != null) 'paliers': paliers,
    };

    final lignes = await _base.lignesCachees(Entites.catalogue);
    final existante = lignes.where((l) => l['slug'] == slug);
    if (existante.isNotEmpty) {
      await _base.stocker(Entites.catalogue, {...existante.first, ...modifications});
    }

    final client = MboaReseau.client;
    if (client == null) return;
    try {
      await client.from('catalogue').update(modifications).eq('slug', slug);
    } catch (e) {
      debugPrint('prix de marché non transmis: $e');
    }
  }

  /// Compose un pack. L'admin en est l'auteur.
  ///
  /// Côté serveur, `mboa.creer_pack` refuse à tout autre rôle, et le trigger
  /// `controle_pack` exige que chaque composant existe au catalogue.
  Future<Produit?> creerPack({
    required String nom,
    required Categorie categorie,
    required List<PackComposant> composants,
    required int prixParPart,
    required Uint8List photoOctets,
    Uint8List? audioOctets,
  }) async {
    if (composants.length < 2) {
      throw StateError("Un pack se compose d'au moins deux éléments");
    }

    final photo = await MboaReseau.televerser(
      bucket: 'produits',
      dossier: 'packs',
      nom: '${Identifiants.uuidV4()}.jpg',
      octets: photoOctets,
      mime: 'image/jpeg',
    );
    final audio = audioOctets == null
        ? null
        : await MboaReseau.televerser(
            bucket: 'audios',
            dossier: 'packs',
            nom: '${Identifiants.uuidV4()}.m4a',
            octets: audioOctets,
            mime: 'audio/mp4',
          );

    final client = MboaReseau.client;
    if (client != null) {
      try {
        final cree = await client.rpc<Map<String, dynamic>>(
          'creer_pack',
          params: {
            'p_nom': nom,
            'p_categorie': categorie.slug,
            'p_composants': [for (final c in composants) c.toJson()],
            'p_prix': prixParPart,
            'p_photo_url': photo,
            'p_audio_url': audio,
          },
        );
        if (cree != null) {
          final pack = Produit.fromMap(cree);
          await _base.stocker(Entites.produit, cree);
          return pack;
        }
      } catch (e) {
        debugPrint('pack refuse par le serveur: $e');
        return null;
      }
    }

    // Mode local : la même ligne, sans RPC.
    final slug = Identifiants.slugDe(nom);
    final pack = Produit(
      id: Identifiants.uuidV4(),
      slug: slug,
      nom: nom.trim(),
      categorie: categorie,
      unite: Unite.part,
      composants: composants,
      photoReelle: photo ?? 'local/produits/pack.jpg',
      quantite: 0,
      prix: prixParPart,
      audioDescription: audio,
      perissable: true,
      actif: true,
      createdLe: DateTime.now(),
    );

    await _base.stocker(Entites.produit, pack.toMap());
    return pack;
  }

  /// Modifie la recette, le prix d'un pack.
  Future<bool> modifierPack({
    required String slug,
    List<PackComposant>? composants,
    int? prixParPart,
  }) async {
    if (composants == null && prixParPart == null) return true;

    final client = MboaReseau.client;
    if (client == null) {
      // Mode local : on met à jour le cache directement.
      final lignes = await _base.lignesCachees(Entites.produit);
      final existant = lignes.where((l) => l['slug'] == slug);
      if (existant.isEmpty) return false;

      final modifications = <String, dynamic>{
        if (composants != null)
          'pack_composants': [for (final c in composants) c.toJson()],
        if (prixParPart != null) 'prix': prixParPart,
      };
      await _base.stocker(Entites.produit, {...existant.first, ...modifications});
      return true;
    }

    try {
      await client.rpc(
        'modifier_pack',
        params: {
          'p_slug': slug,
          if (composants != null)
            'p_composants': [for (final c in composants) c.toJson()],
          if (prixParPart != null) 'p_prix': prixParPart,
        },
      );
      return true;
    } catch (e) {
      debugPrint('modification de pack refusee: $e');
      return false;
    }
  }

  /// Le nombre de parts réellement cuisinables, plafonné par le composant le
  /// plus rare.
  Future<int> partsLivrables(String slug) async {
    final client = MboaReseau.client;
    if (client != null) {
      try {
        final n = await client.rpc('parts_livrables', params: {'p_slug': slug});
        return (n as num?)?.round() ?? 0;
      } catch (e) {
        debugPrint('parts livrables indisponibles: $e');
      }
    }

    final lignes = await _base.lignesCachees(Entites.produit);
    final pack = lignes.where((l) => l['slug'] == slug).firstOrNull;
    if (pack == null) return 0;

    final composants = composantsDepuisJson(pack['pack_composants']);
    var plafond = (pack['quantite'] as num?)?.toInt() ?? 0;

    for (final c in composants) {
      final dispo = lignes
          .where((l) => l['slug'] == c.slug && l['pack_composants'] == null)
          .fold<double>(0, (somme, l) => somme + ((l['quantite'] as num?)?.toDouble() ?? 0));

      final parPart = c.quantite <= 0 ? 1 : c.quantite;
      final possible = (dispo / parPart).floor();
      if (possible < plafond) plafond = possible;
    }

    return plafond < 0 ? 0 : plafond;
  }

  // --------------------------------------------------------------------------
  // Aides
  // --------------------------------------------------------------------------

  Future<void> _majCache(String id, Map<String, dynamic> modifications) async {
    final lignes = await _base.lignesCachees(Entites.produit);
    final existante = lignes.where((l) => l['id'] == id);
    final fusion = <String, dynamic>{
      if (existante.isNotEmpty) ...existante.first,
      'id': id,
      ...modifications,
    };
    await _base.stocker(Entites.produit, fusion);
  }

  Future<void> _enfile(String operation, Map<String, dynamic> payload) => _base.enfiler(
        entite: Entites.produit,
        id: payload['id'] as String,
        operation: operation,
        payload: payload,
      );
}
