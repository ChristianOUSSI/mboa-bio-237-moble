import 'dart:typed_data';

import 'package:flutter/foundation.dart';

import '../utils/identifiants.dart';
import 'base_locale.dart';
import 'depot_auth.dart' show normaliserTelephone;
import 'mboa_reseau.dart';
import 'models/categorie.dart';
import 'models/fournisseur.dart';
import 'models/unite.dart';

/// Le fichier des producteurs du comptoir.
///
/// Une fiche peut naitre au comptoir, sans compte : c'est le cas d'un
/// producteur qui vend une fois par saison et n'a pas de smartphone. Le jour
/// ou il installe l'application avec le meme numero, le serveur la rattache a
/// son profil. L'ecran admin n'a donc jamais a gerer ce lien a la main.
///
/// L'ecriture est reservee a l'admin par la RLS. Les methodes renvoient null
/// quand le serveur refuse, pour que l'ecran puisse le dire sans afficher une
/// exception.
class DepotFournisseurs {
  DepotFournisseurs(this._base);

  final BaseLocale _base;

  Future<List<Fournisseur>> tous({bool seulementActifs = false}) async {
    final client = MboaReseau.client;
    if (client != null) {
      try {
        final requete = client.from('fournisseurs').select();
        final lignes = seulementActifs
            ? await requete.eq('actif', true).order('nom')
            : await requete.order('nom');
        for (final ligne in lignes) {
          await _base.stocker(Entites.fournisseur, ligne);
        }
        return lignes.map(Fournisseur.fromMap).toList();
      } catch (e) {
        debugPrint('fournisseurs distants indisponibles: $e');
      }
    }

    final lignes = await _base.lignesCachees(Entites.fournisseur);
    final fiches = lignes.map(Fournisseur.fromMap).toList()
      ..sort((a, b) => a.nom.toLowerCase().compareTo(b.nom.toLowerCase()));
    return seulementActifs ? fiches.where((f) => f.actif).toList() : fiches;
  }

  /// Enregistre une fiche. Le numero est la cle qui permettra de la rattacher
  /// au compte plus tard : il est donc normalise ici, comme a l'inscription.
  Future<Fournisseur?> creer({
    required String nom,
    required String telephone,
    required String village,
    required Categorie productionCategorie,
    String productionLibre = '',
    Unite unite = Unite.kg,
    Uint8List? photoOctets,
  }) async {
    final numero = normaliserTelephone(telephone);
    if (numero == null) throw ArgumentError('Numero de fournisseur invalide');

    final id = Identifiants.uuidV4();

    final cheminPhoto = photoOctets == null
        ? null
        : await MboaReseau.televerser(
            bucket: 'visages',
            dossier: id,
            nom: 'fournisseur.jpg',
            octets: photoOctets,
            mime: 'image/jpeg',
          );

    final fiche = Fournisseur(
      id: id,
      nom: nom.trim(),
      telephone: numero,
      village: village.trim(),
      photo: cheminPhoto,
      productionCategorie: productionCategorie,
      productionLibre: productionLibre.trim(),
      unite: unite,
    );

    await _base.stocker(Entites.fournisseur, fiche.toMap());

    final client = MboaReseau.client;
    if (client == null) return fiche;

    try {
      final cree = await client.from('fournisseurs').insert(fiche.toMap()).select();
      if (cree.isEmpty) return null;
      final recu = Fournisseur.fromMap(cree.first);
      await _base.stocker(Entites.fournisseur, recu.toMap());
      return recu;
    } catch (e) {
      debugPrint('fournisseur refuse par le serveur: $e');
      return null;
    }
  }

  Future<Fournisseur?> modifier(Fournisseur fiche, {Uint8List? photoOctets}) async {
    String? cheminPhoto;
    if (photoOctets != null) {
      cheminPhoto = await MboaReseau.televerser(
        bucket: 'visages',
        dossier: fiche.id,
        nom: 'fournisseur.jpg',
        octets: photoOctets,
        mime: 'image/jpeg',
      );
    }

    final maj = fiche.copieAvec(photo: cheminPhoto ?? fiche.photo);
    await _base.stocker(Entites.fournisseur, maj.toMap());

    final client = MboaReseau.client;
    if (client == null) return maj;

    try {
      // `profil_id` ne part pas dans la mise a jour : le lien appartient au
      // trigger d'inscription, et une liste lue avant le rattachement
      // l'effacerait en renvoyant un null perime.
      final lignes = await client
          .from('fournisseurs')
          .update(maj.toMap()
            ..remove('id')
            ..remove('profil_id'))
          .eq('id', maj.id)
          .select();
      if (lignes.isEmpty) return null;
      final recu = Fournisseur.fromMap({...maj.toMap(), ...lignes.first});
      await _base.stocker(Entites.fournisseur, recu.toMap());
      return recu;
    } catch (e) {
      debugPrint('modification de fournisseur refusee: $e');
      return null;
    }
  }

  /// Retirer une fiche la gele, jamais ne la supprime : des achats et de
  /// l'argent y sont rattaches.
  Future<bool> desactiver(String id) async {
    final lignes = await _base.lignesCachees(Entites.fournisseur);
    final existante = lignes.where((l) => l['id'] == id);
    if (existante.isNotEmpty) {
      await _base.stocker(Entites.fournisseur, {...existante.first, 'actif': false});
    }

    final client = MboaReseau.client;
    if (client == null) return true;
    try {
      await client.from('fournisseurs').update({'actif': false}).eq('id', id);
      return true;
    } catch (e) {
      debugPrint('desactivation de fournisseur refusee: $e');
      return false;
    }
  }
}
