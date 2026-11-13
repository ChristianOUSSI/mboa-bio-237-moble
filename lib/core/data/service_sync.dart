import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'base_locale.dart';
import 'mboa_reseau.dart';

class ServiceSync {
  ServiceSync(this._base);

  final BaseLocale _base;
  static final _enCours = Expando<Future<int>>();

  static const champsListe = {
    'produits', 'titre', 'image_url', 'montant_estime',
    'transformee_en', 'transformee_le', 'envoyee_le',
  };
  static const champsFiche = {'prix', 'actif', 'photo_filigranee'};

  Future<void> enfiler({
    required String entite,
    required String id,
    required String operation,
    required Map<String, dynamic> payload,
  }) async {
    final precedent = (await _base.file()).where((e) =>
        e['entite'] == entite && e['id'] == id && e['operation'] == operation);
    final fusion = <String, dynamic>{
      if (precedent.isNotEmpty)
        ...Map<String, dynamic>.from(jsonDecode(precedent.first['payload'] as String) as Map),
      ...payload,
    };
    await _base.enfiler(entite: entite, id: id, operation: operation, payload: fusion);
  }

  Future<int> viderFile() {
    final active = _enCours[_base];
    if (active != null) return active;
    final future = _vider().whenComplete(() => _enCours[_base] = null);
    _enCours[_base] = future;
    return future;
  }

  Future<int> _vider() async {
    final client = MboaReseau.client;
    if (client == null) return _base.tailleFile();
    if (client.auth.currentUser == null) {
      throw StateError('Une connexion au compte est nécessaire pour synchroniser');
    }

    for (final envoi in await _base.file()) {
      final entite = envoi['entite'] as String;
      final operation = envoi['operation'] as String;
      final payload = Map<String, dynamic>.from(jsonDecode(envoi['payload'] as String) as Map);
      final id = envoi['id'] as String;
      Map<String, dynamic> recue;
      switch ('$entite/$operation') {
        case 'liste/insert':
          _verifierChamps(payload, {...champsListe, 'id', 'consommateur_id', 'code', 'created_at'});
          _verifierProprietaire(client, payload);
          if (payload['id'] != id) throw StateError('Identifiant de liste incohérent');
          await client.from('listes').upsert(payload, onConflict: 'id', ignoreDuplicates: true);
          recue = await client.from('listes').select().eq('id', id).single();
        case 'liste/update':
          _verifierChamps(payload, {...champsListe, 'id', 'consommateur_id'});
          _verifierProprietaire(client, payload);
          if (payload['id'] != id) throw StateError('Identifiant de liste incohérent');
          final modifications = Map<String, dynamic>.from(payload)
            ..remove('id')
            ..remove('consommateur_id');
          if (modifications.isEmpty) throw StateError('Modification de liste vide');
          recue = await client.from('listes').update(modifications)
              .eq('id', id).eq('consommateur_id', payload['consommateur_id'] as String)
              .select().single();
        case 'produit/fiche:update':
          _verifierChamps(payload, {...champsFiche, 'slug'});
          if (payload['slug'] != id || (payload['prix'] as num?) == null ||
              (payload['prix'] as num) <= 0) {
            throw StateError('Modification de fiche invalide');
          }
          recue = await client.from('produits')
              .update(Map<String, dynamic>.from(payload)..remove('slug'))
              .eq('slug', id).select().single();
        case 'commande/update':
          final modifications = Map<String, dynamic>.from(payload)
            ..remove('id')
            ..remove('commande_id');
          _verifierChamps(modifications, {
            'statut_enum', 'appel_vocal_fait',
            'photo_livraison_url', 'signature_url',
          });
          if (modifications.isEmpty) {
            throw StateError('Modification de commande vide');
          }
          recue = await client
              .from('commandes')
              .update(modifications)
              .eq('id', id)
              .select()
              .single();
        case 'commande/rpc:creer_devis':
          recue = await client.rpc<Map<String, dynamic>>(
            'creer_devis',
            params: {
              'p_produits': payload['produits'],
              'p_moto': payload['moto'] ?? true,
            },
          );
          // Le serveur a son propre identifiant : le devis local n'est plus
          // qu'une esquisse, et deux devis pour un seul panier seraient pires
          // qu'un devis perdu.
          if (recue['id'] != id) {
            await _base.supprimerDuCache(Entites.commande, id);
          }
        case 'commande/rpc:valider_devis':
          recue = await client.rpc<Map<String, dynamic>>(
            'valider_devis',
            params: {'p_commande_id': payload['commande_id']},
          );
        case 'commande/rpc:annuler_devis':
          recue = await client.rpc<Map<String, dynamic>>(
            'annuler_devis',
            params: {
              'p_commande_id': payload['commande_id'],
              'p_motif': payload['motif'],
              'p_audio_url': payload['audio_url'],
            },
          );
        case 'commande/rpc:pointer_livraison':
          recue = await client.rpc<Map<String, dynamic>>(
            'pointer_livraison',
            params: {
              'p_commande_id': payload['commande_id'],
              'p_montant_livre': payload['montant_livre'],
            },
          );
        case 'commande/rpc:confirmer_reception':
          recue = await client.rpc<Map<String, dynamic>>(
            'confirmer_reception',
            params: {
              'p_commande_id': payload['commande_id'],
              'p_bon': payload['bon'] ?? true,
              'p_motif': payload['motif'],
              'p_audio_url': payload['audio_url'],
            },
          );
        case 'commande/rpc:fermer_sur_delai':
          recue = await client.rpc<Map<String, dynamic>>(
            'fermer_sur_delai',
            params: {'p_commande_id': payload['commande_id']},
          );
        case 'commande/rpc:pointer_suivi':
          final jalon = await client.rpc<Map<String, dynamic>>(
            'pointer_suivi',
            params: {
              'p_commande_id': payload['commande_id'],
              'p_jalon': payload['jalon'],
              'p_auteur': payload['auteur'] ?? 'admin',
            },
          );
          await _base.stocker(Entites.suivi, jalon);
          recue = const <String, dynamic>{};
        case 'achat/rpc:proposer_achat':
          // La photo a peut-etre attendu des jours sur le telephone : elle
          // monte maintenant, et c'est elle qui rend la proposition recevable.
          var photo = (payload['photo_url'] as String?) ?? '';
          final locale = (payload['photo_locale'] as String?) ?? '';
          if (photo.isEmpty && locale.isNotEmpty) {
            final fichier = File(locale);
            if (!await fichier.exists()) {
              throw StateError('Photo locale introuvable, proposition conservée');
            }
            photo = await MboaReseau.televerser(
                  bucket: 'produits',
                  dossier: 'achats',
                  nom: '$id.jpg',
                  octets: await fichier.readAsBytes(),
                  mime: 'image/jpeg',
                ) ??
                '';
          }
          if (photo.isEmpty) {
            throw StateError('Une proposition sans photo ne part pas');
          }
          final cree = await client.rpc<Map<String, dynamic>>(
            'proposer_achat',
            params: {
              'p_nom': payload['nom'],
              'p_categorie': payload['categorie'],
              'p_quantite': payload['quantite'],
              'p_unite': payload['unite'],
              'p_prix_demande': payload['prix_demande'],
              'p_photo_url': photo,
              'p_audio_url': payload['audio_url'],
            },
          );
          if (cree['id'] != id) {
            await _base.supprimerDuCache(Entites.achat, id);
          }
          recue = cree;
          if (locale.isNotEmpty) {
            try {
              await File(locale).delete();
            } catch (e) {
              debugPrint('photo locale non supprimee: $e');
            }
          }
        case 'achat/rpc:valider_achat':
          recue = await client.rpc<Map<String, dynamic>>(
            'valider_achat',
            params: {
              'p_achat_id': payload['achat_id'],
              'p_prix_achat': payload['prix_achat'],
              'p_prix_revente': payload['prix_revente'],
            },
          );
          await _base.vider(Entites.produit);
        case 'achat/rpc:payer_achat':
          recue = await client.rpc<Map<String, dynamic>>(
            'payer_achat',
            params: {'p_achat_id': payload['achat_id']},
          );
        case 'achat/rpc:refuser_achat':
          recue = await client.rpc<Map<String, dynamic>>(
            'refuser_achat',
            params: {
              'p_achat_id': payload['achat_id'],
              'p_motif': payload['motif'],
              'p_motif_audio_url': payload['audio_url'],
              'p_litige': payload['litige'] ?? false,
            },
          );
        default:
          throw UnsupportedError('Opération conservée en file, non prise en charge : $entite/$operation');
      }

      // Une intention modifiée pendant l'envoi doit rester en file.
      final actuelle = (await _base.file()).where((e) => e['cle'] == envoi['cle']);
      if (actuelle.isNotEmpty && actuelle.first['payload'] == envoi['payload']) {
        final cache = await _base.lignesCachees(entite);
        final precedente = cache.where((l) => entite == Entites.produit
            ? l['slug'] == id : l['id'] == id);
        await _base.stocker(entite, {
          if (precedente.isNotEmpty) ...precedente.first,
          ...recue,
        });
        await _base.desenfiler(envoi['cle'] as String);
      }
      if (entite == Entites.produit) await _base.vider(Entites.vitrine);
    }
    return _base.tailleFile();
  }

  static void _verifierChamps(Map<String, dynamic> payload, Set<String> permis) {
    final inconnus = payload.keys.where((c) => !permis.contains(c));
    if (inconnus.isNotEmpty) {
      throw UnsupportedError('Champs non pris en charge, envoi conservé : ${inconnus.join(', ')}');
    }
  }

  static void _verifierProprietaire(SupabaseClient client, Map<String, dynamic> payload) {
    if (payload['consommateur_id'] != client.auth.currentUser!.id) {
      throw StateError('Cette liste appartient à un autre compte');
    }
  }
}
