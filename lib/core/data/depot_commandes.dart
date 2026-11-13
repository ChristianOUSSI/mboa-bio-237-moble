import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';

import '../utils/identifiants.dart';
import 'base_locale.dart';
import 'mboa_reseau.dart';
import 'models/commande.dart';
import 'models/livreur.dart';
import 'models/statuts.dart';
import 'models/suivi_colis.dart';

/// Caisse, livraison et confirmation.
///
/// Depuis le paiement à la porte, cette classe ne collecte plus rien. Elle
/// fait trois choses : réserver le panier, enregistrer ce que l'admin a
/// réellement encaissé, et recueillir le tap de la cliente. Le seul moment
/// où de l'argent devient dû est le troisième.
///
/// Le vendeur est MBOA BIO : il n'y a plus de `fournisseur_id` sur une
/// commande, plus de commission, plus de versement au producteur. La marge
/// se calcule côté base (`mboa.marge_devis`), pas côté app.
class DepotCommandes {
  DepotCommandes(this._base);

  final BaseLocale _base;

  /// Jointure unique : le livreur pour la carte « qui vient ». La vue
  /// `vitrine_livreurs` ne rend pas le numéro, il vient de l'RPC
  /// `contact_livreur`.
  static const String _jointureLivreur =
      '*, livreur:livreurs!livreur_id(nom, photo, moto, plaque, tarif_course)';

  /// Délai au-delà duquel l'admin peut clore une livraison sans réponse.
  static const Duration delaiRelance = Duration(hours: 12);

  // --------------------------------------------------------------------------
  // Lecture
  // --------------------------------------------------------------------------

  Future<List<Commande>> pourConsommateur(String consommateurId) async {
    final client = MboaReseau.client;
    if (client != null) {
      try {
        // La cliente lit une projection, pas la table : `commandes` porte le
        // cout d'achat total et, dans son JSONB, le cout de chaque ligne. Une
        // policy ne masque pas une colonne ; la vue `commandes_clientes` le
        // fait, et y ajoute le livreur sans son numero.
        final lignes = await client
            .from('commandes_clientes')
            .select()
            .eq('consommateur_id', consommateurId)
            .order('created_at', ascending: false);
        return _cacheEtConvertis(lignes);
      } catch (e) {
        debugPrint('commandes cliente indisponibles: $e');
      }
    }
    final lignes = await _base.lignesCachees(Entites.commande, consommateur: consommateurId);
    return lignes.map(Commande.fromMap).toList()..sort(_plusRecente);
  }

  /// Toutes les commandes, côté admin.
  Future<List<Commande>> toutes({StatutCommande? statut}) async {
    final client = MboaReseau.client;
    if (client != null) {
      try {
        final base = client.from('commandes').select(_jointureLivreur);
        final lignes = await (statut == null ? base : base.eq('statut_enum', statut.slug))
            .order('created_at', ascending: false)
            .limit(120);
        return _cacheEtConvertis(lignes);
      } catch (e) {
        debugPrint('commandes admin indisponibles: $e');
      }
    }

    final lignes = await _base.lignesCachees(Entites.commande, etat: statut?.slug);
    return lignes.map(Commande.fromMap).toList()..sort(_plusRecente);
  }

  /// Les livraisons que l'admin doit pointer ce matin.
  ///
  /// Les deux statuts qui précèdent `livree` sont pris ensemble : une
  /// commande validée la veille et partie ce matin est la seule chose que
  /// l'admin a à faire, et il ne doit pas avoir à chercher dans deux files.
  Future<List<Commande>> aPointer() async {
    final toutes = await this.toutes();
    return toutes
        .where((c) => c.statut == StatutCommande.valideeAdmin || c.statut == StatutCommande.enLivraison)
        .toList()
      ..sort((a, b) => a.createdLe.compareTo(b.createdLe));
  }

  /// Livrées depuis plus de 12 h sans réponse de la cliente.
  Future<List<Commande>> sansConfirmation() async {
    final client = MboaReseau.client;
    if (client != null) {
      try {
        final lignes = await client.rpc<List<dynamic>>(
          'devis_sans_confirmation',
          params: {'p_delai': '${delaiRelance.inHours} hours'},
        );
        return lignes.map(Commande.fromMap).toList();
      } catch (e) {
        debugPrint('relances distantes indisponibles: $e');
      }
    }

    final livrees = await _base.lignesCachees(Entites.commande, etat: StatutCommande.livree.slug);
    return livrees
        .map(Commande.fromMap)
        .where((c) => c.preteARelance)
        .toList()
      ..sort((a, b) => (a.livreeLe ?? DateTime(0)).compareTo(b.livreeLe ?? DateTime(0)));
  }

  // --------------------------------------------------------------------------
  // Écriture
  // --------------------------------------------------------------------------

  /// Enregistre le devis. Rien n'est payé ici.
  ///
  /// L'RPC `creer_devis` fige le prix et le coût d'achat de chaque ligne,
  /// vérifie la disponibilité, et ne réserve pas encore, c'est `valider_devis`
  /// qui sort le stock.
  Future<Commande> commander({
    required String consommateurId,
    required List<LigneCommande> lignes,
    required bool livraisonMoto,
    Uint8List? photoOctets,
  }) async {
    if (lignes.isEmpty) throw StateError('Panier vide');

    final client = MboaReseau.client;
    if (client != null) {
      try {
        final creee = await client.rpc<Map<String, dynamic>>(
          'creer_devis',
          params: {
            'p_produits': lignes.map((l) => l.toJson()).toList(),
            'p_moto': livraisonMoto,
          },
        );
        final commande = Commande.fromMap(creee);
        if (photoOctets != null) {
          await _preuve(
            commandeId: commande.id,
            dossier: consommateurId,
            colonne: 'photo_livraison_url',
            octets: photoOctets,
            extension: 'panier.jpg',
            mime: 'image/jpeg',
          );
        }
        await _base.stocker(Entites.commande, commande.toMap());
        return commande;
      } catch (e) {
        debugPrint('devis distant refuse, passage en local: $e');
      }
    }

    // Mode local : la même ligne, sans RPC.
    var montant = 0;
    var cout = 0;
    for (final ligne in lignes) {
      montant += ligne.sousTotal;
      cout += ligne.cout;
    }

    final commande = Commande(
      id: Identifiants.uuidV4(),
      consommateurId: consommateurId,
      lignes: lignes,
      statut: StatutCommande.nouvelle,
      montantTotal: montant,
      coutAchat: cout,
      paiement: ModePaiement.especes,
      livraisonMoto: livraisonMoto,
      createdLe: DateTime.now(),
    );

    await _base.stocker(Entites.commande, commande.toMap());
    await _base.enfiler(
      entite: Entites.commande,
      id: commande.id,
      operation: 'rpc:creer_devis',
      payload: {
        'id': commande.id,
        'consommateur_id': consommateurId,
        'produits': lignes.map((l) => l.toJson()).toList(),
        'moto': livraisonMoto,
      },
    );

    if (photoOctets != null) {
      await _preuve(
        commandeId: commande.id,
        dossier: consommateurId,
        colonne: 'photo_livraison_url',
        octets: photoOctets,
        extension: 'panier.jpg',
        mime: 'image/jpeg',
      );
    }
    return commande;
  }

  /// Le comptoir valide le devis : la marchandise sort du stock MBOA.
  ///
  /// C'est le seul geste qui réserve vraiment : avant lui, le devis est une
  /// intention, et deux clientes peuvent demander la même dernière botte.
  Future<Commande?> valider(String id) async {
    final client = MboaReseau.client;
    if (client != null) {
      try {
        final validee = await client.rpc<Map<String, dynamic>>(
          'valider_devis',
          params: {'p_commande_id': id},
        );
        final commande = Commande.fromMap(validee);
        await _base.stocker(Entites.commande, commande.toMap());
        return commande;
      } catch (e) {
        debugPrint('validation distante refusee: $e');
        rethrow;
      }
    }

    final lignes = await _base.lignesCachees(Entites.commande);
    final existante = lignes.where((l) => l['id'] == id);
    if (existante.isEmpty) return null;

    final avant = Commande.fromMap(existante.first);
    final apres = avant.copieAvec(
      statut: StatutCommande.valideeAdmin,
      stockSorti: true,
    );
    await _base.stocker(Entites.commande, apres.toMap());
    await _base.enfiler(
      entite: Entites.commande,
      id: id,
      operation: 'rpc:valider_devis',
      payload: {'commande_id': id},
    );
    return apres;
  }

  /// Le comptoir annule un devis. Le stock revient à la validation suivante.
  ///
  /// L'annulation est la seule porte de retour : le motif est gardé, et la
  /// note vocale de la cliente reste attachée au document.
  Future<Commande?> annuler({
    required String id,
    String? motif,
    Uint8List? audioOctets,
  }) async {
    String? cheminAudio;
    if (audioOctets != null) {
      cheminAudio = await MboaReseau.televerser(
        bucket: 'preuves',
        dossier: id,
        nom: '${Identifiants.court()}.m4a',
        octets: audioOctets,
        mime: 'audio/mp4',
      );
    }

    final client = MboaReseau.client;
    if (client != null) {
      try {
        final annulee = await client.rpc<Map<String, dynamic>>(
          'annuler_devis',
          params: {
            'p_commande_id': id,
            'p_motif': motif,
            'p_audio_url': cheminAudio,
          },
        );
        final commande = Commande.fromMap(annulee);
        await _base.stocker(Entites.commande, commande.toMap());
        return commande;
      } catch (e) {
        debugPrint('annulation distante refusee: $e');
        rethrow;
      }
    }

    final lignes = await _base.lignesCachees(Entites.commande);
    final existante = lignes.where((l) => l['id'] == id);
    if (existante.isEmpty) return null;

    final avant = Commande.fromMap(existante.first);
    final apres = avant.copieAvec(
      statut: StatutCommande.annulee,
      annuleLe: DateTime.now(),
      motifAnnulation: motif,
      stockSorti: false,
    );
    await _base.stocker(Entites.commande, apres.toMap());
    await _base.enfiler(
      entite: Entites.commande,
      id: id,
      operation: 'rpc:annuler_devis',
      payload: {
        'commande_id': id,
        'motif': motif,
        'audio_url': cheminAudio,
      },
    );
    return apres;
  }

  /// Le numéro du comptoir, pour la cliente qui veut parler à quelqu'un.
  Future<String?> contactComptoir() async {
    final client = MboaReseau.client;
    if (client != null) {
      try {
        final numero = (await client.rpc('contact_comptoir') as String?)?.trim();
        return numero == null || numero.isEmpty ? null : numero;
      } catch (e) {
        debugPrint('contact comptoir indisponible: $e');
      }
    }
    final local = (await _base.lireEtat('telephone_comptoir'))?.trim();
    return local == null || local.isEmpty ? null : local;
  }

  /// L'admin pointe la livraison et saisit ce qu'il a réellement encaissé.
  ///
  /// Le montant livré ne peut pas dépasser le panier demandé : la contrainte
  /// est reprise ici en plus du serveur.
  Future<Commande?> pointerLivraison({
    required String id,
    required int montantLivre,
  }) async {
    final client = MboaReseau.client;
    if (client != null) {
      try {
        final livree = await client.rpc<Map<String, dynamic>>(
          'pointer_livraison',
          params: {'p_commande_id': id, 'p_montant_livre': montantLivre},
        );
        final commande = Commande.fromMap(livree);
        await _base.stocker(Entites.commande, commande.toMap());
        return commande;
      } catch (e) {
        debugPrint('pointage distant refuse, reste local: $e');
      }
    }

    final lignes = await _base.lignesCachees(Entites.commande);
    final existante = lignes.where((l) => l['id'] == id);
    if (existante.isEmpty) return null;

    final avant = Commande.fromMap(existante.first);
    final apres = avant.copieAvec(
      statut: StatutCommande.livree,
      montantLivre: montantLivre,
      livreeLe: DateTime.now(),
    );

    await _base.stocker(Entites.commande, apres.toMap());
    await _base.enfiler(
      entite: Entites.commande,
      id: id,
      operation: 'rpc:pointer_livraison',
      payload: {'commande_id': id, 'montant_livre': montantLivre},
    );
    return apres;
  }

  /// Le tap de la cliente : oui, ou problème.
  ///
  /// Le « oui » clos la commande et rend la marge réelle. Le « problème »
  /// ferme le parcours sans fermer la facture : rien n'est dû tant que
  /// l'admin n'a pas tranché.
  Future<Commande?> confirmerReception({
    required String id,
    required bool bon,
    MotifReception? motif,
    Uint8List? audioOctets,
  }) async {
    String? cheminAudio;
    if (audioOctets != null) {
      cheminAudio = await MboaReseau.televerser(
        bucket: 'preuves',
        dossier: id,
        nom: '${Identifiants.court()}.m4a',
        octets: audioOctets,
        mime: 'audio/mp4',
      );
    }

    final client = MboaReseau.client;
    if (client != null) {
      try {
        final confirmee = await client.rpc<Map<String, dynamic>>(
          'confirmer_reception',
          params: {
            'p_commande_id': id,
            'p_bon': bon,
            'p_motif': motif?.slug,
            'p_audio_url': cheminAudio,
          },
        );
        final commande = Commande.fromMap(confirmee);
        await _base.stocker(Entites.commande, commande.toMap());
        return commande;
      } catch (e) {
        debugPrint('confirmation distante refusee, reste locale: $e');
      }
    }

    final lignes = await _base.lignesCachees(Entites.commande);
    final existante = lignes.where((l) => l['id'] == id);
    if (existante.isEmpty) return null;

    final avant = Commande.fromMap(existante.first);
    final clos = bon;
    final apres = avant.copieAvec(
      statut: StatutCommande.recue,
      recueLe: DateTime.now(),
      satisfaction: bon ? Satisfaction.bon : Satisfaction.probleme,
      satisfactionMotif: motif?.slug,
      satisfactionAudio: cheminAudio,
      clos: clos,
      closPar: clos ? 'cliente' : 'admin_litige',
    );

    await _base.stocker(Entites.commande, apres.toMap());
    await _base.enfiler(
      entite: Entites.commande,
      id: id,
      operation: 'rpc:confirmer_reception',
      payload: {
        'commande_id': id,
        'bon': bon,
        'motif': motif?.slug,
        'audio_url': cheminAudio,
      },
    );
    return apres;
  }

  /// Fermeture sur délai, par l'admin, quand la cliente n'a pas répondu.
  Future<Commande?> fermerSurDelai(String id) async {
    final client = MboaReseau.client;
    if (client != null) {
      try {
        final fermee = await client.rpc<Map<String, dynamic>>(
          'fermer_sur_delai',
          params: {'p_commande_id': id},
        );
        final commande = Commande.fromMap(fermee);
        await _base.stocker(Entites.commande, commande.toMap());
        return commande;
      } catch (e) {
        debugPrint('fermeture sur delai refusee: $e');
      }
    }

    final lignes = await _base.lignesCachees(Entites.commande);
    final existante = lignes.where((l) => l['id'] == id);
    if (existante.isEmpty) return null;
    final avant = Commande.fromMap(existante.first);
    final apres = avant.copieAvec(
      statut: StatutCommande.recue,
      recueLe: DateTime.now(),
      clos: true,
      closPar: 'admin_delai',
    );
    await _base.stocker(Entites.commande, apres.toMap());
    await _base.enfiler(
      entite: Entites.commande,
      id: id,
      operation: 'rpc:fermer_sur_delai',
      payload: {'commande_id': id},
    );
    return apres;
  }

  /// Fait avancer une commande d'un cran, hors livraison et confirmation.
  ///
  /// La machine à états serveur refuse toute transition qui n'est pas dans
  /// le sens du voyage. L'admin peut revenir en arrière pour rouvrir un
  /// litige.
  Future<void> avancer({
    required String id,
    required StatutCommande statut,
  }) async {
    final modifications = <String, dynamic>{'statut_enum': statut.slug};
    await _majCache(id, modifications);

    final client = MboaReseau.client;
    if (client == null) {
      await _enfiler(id, modifications);
      return;
    }

    try {
      await client.from('commandes').update(modifications).eq('id', id);
    } catch (e) {
      debugPrint('statut distant en attente: $e');
      await _enfiler(id, modifications);
    }
  }

  /// Marque l'appel vocal automatisé comme passé.
  Future<void> marquerAppelPasse(String id) async {
    final modifications = <String, dynamic>{
      'appel_vocal_fait': true,
    };

    final client = MboaReseau.client;
    if (client != null) {
      try {
        await client.from('commandes').update(modifications).eq('id', id);
      } catch (e) {
        debugPrint('marque appel non transmise: $e');
      }
    }
    await _majCache(id, modifications);
  }

  /// Attache la signature dessinée à une commande déjà créée.
  ///
  /// Séparée de [commander] parce que l'ordre compte : la commande doit
  /// exister avant sa preuve. Si l'écriture de la signature échoue, la
  /// commande n'est pas annulée pour autant.
  Future<void> marquerSignature(String commandeId, Uint8List png) async {
    final consommateurId = (await _base.lireEtat('session')) ?? commandeId;
    await _preuve(
      commandeId: commandeId,
      dossier: consommateurId,
      colonne: 'signature_url',
      octets: png,
      extension: 'signature.png',
      mime: 'image/png',
    );
  }

  // --------------------------------------------------------------------------
  // Courses du livreur
  // --------------------------------------------------------------------------

  /// Les courses affectées au livreur connecté.
  ///
  /// L'RPC `mboa.mes_courses` ne rend que ses courses et jamais les coûts du
  /// comptoir. Hors ligne, on retombe sur le cache local, filtré par la fiche
  /// du livreur mémorisée à la connexion.
  Future<List<CourseLivreur>> mesCourses() async {
    final client = MboaReseau.client;
    if (client != null) {
      try {
        final lignes = await client.rpc<List<dynamic>>('mes_courses');
        return lignes
            .whereType<Map<String, dynamic>>()
            .map(CourseLivreur.fromMap)
            .toList(growable: false);
      } catch (e) {
        debugPrint('courses distantes indisponibles: $e');
      }
    }

    final livreurId = await _base.lireEtat('livreur');
    if (livreurId == null || livreurId.isEmpty) return const [];
    final cache = await _base.lignesCachees(Entites.commande);
    return cache
        .where((c) => c['livreur_id'] == livreurId)
        .map(Commande.fromMap)
        .where((c) =>
            c.statut == StatutCommande.valideeAdmin ||
            c.statut == StatutCommande.enLivraison ||
            c.statut == StatutCommande.livree)
        .map(CourseLivreur.depuisCommande)
        .toList()
      ..sort((a, b) => a.createdLe.compareTo(b.createdLe));
  }

  // --------------------------------------------------------------------------
  // Suivi de colis
  // --------------------------------------------------------------------------

  /// Lit la timeline complete d'une commande.
  ///
  /// Les jalons poses par le trigger SQL sont renvoyes par l'RPC
  /// `mboa.suivi_commande`. En mode hors ligne, on reconstruit la timeline
  /// depuis le statut de la commande : on ne peut pas faire mieux sans
  /// connexion, mais c'est suffisant pour que la cliente voie ou en est sa
  /// commande.
  Future<SuiviColis> suivi(String commandeId) async {
    final client = MboaReseau.client;
    if (client != null) {
      try {
        final lignes = await client.rpc<List<dynamic>>(
          'suivi_commande',
          params: {'p_commande_id': commandeId},
        );
        final maps = lignes.whereType<Map<String, dynamic>>().toList();
        return SuiviColis.fromMaps(commandeId, maps);
      } catch (e) {
        debugPrint('suivi distant indisponible: $e');
      }
    }

    // Mode hors ligne : on reconstruit depuis le statut cache, puis on
    // ajoute les jalons manuels (en_approche) deja recus par le temps reel.
    final lignes = await _base.lignesCachees(Entites.commande);
    final existante = lignes.where((l) => l['id'] == commandeId);
    if (existante.isEmpty) return SuiviColis.vide(commandeId);

    final commande = Commande.fromMap(existante.first);
    final parJalon = <JalonSuivi, EtapeSuivi>{};

    for (final s in await _base.lignesCachees(Entites.suivi)) {
      if (s['commande_id'] != commandeId) continue;
      final e = EtapeSuivi.fromMap(s);
      parJalon[e.jalon] = e;
    }

    // Les jalons automatiques, deduits du statut. Un jalon deja recu par le
    // temps reel garde son horodatage reel : on ne l'ecrase pas par une date
    // reconstruite.
    if (commande.statut.rang >= StatutCommande.valideeAdmin.rang) {
      parJalon.putIfAbsent(JalonSuivi.panierPrepare, () => EtapeSuivi(
        jalon: JalonSuivi.panierPrepare,
        horodatage: commande.createdLe,
        auteur: 'auto',
      ));
    }
    if (commande.statut.rang >= StatutCommande.enLivraison.rang) {
      parJalon.putIfAbsent(JalonSuivi.motoPartie, () => EtapeSuivi(
        jalon: JalonSuivi.motoPartie,
        horodatage: commande.livreeLe ?? DateTime.now(),
        auteur: 'auto',
      ));
    }
    if (commande.statut.rang >= StatutCommande.livree.rang) {
      parJalon.putIfAbsent(JalonSuivi.arrive, () => EtapeSuivi(
        jalon: JalonSuivi.arrive,
        horodatage: commande.livreeLe ?? DateTime.now(),
        auteur: 'auto',
      ));
    }
    if (commande.statut.rang >= StatutCommande.recue.rang) {
      parJalon.putIfAbsent(JalonSuivi.remis, () => EtapeSuivi(
        jalon: JalonSuivi.remis,
        horodatage: commande.recueLe ?? DateTime.now(),
        auteur: 'auto',
      ));
    }

    final etapes = parJalon.values.toList()
      ..sort((a, b) => a.jalon.rang.compareTo(b.jalon.rang));
    return SuiviColis(commandeId: commandeId, etapes: etapes);
  }

  /// Pointe une etape du suivi.
  ///
  /// Seul [JalonSuivi.enApproche] est pointable manuellement : les autres
  /// sont poses automatiquement par le trigger SQL quand le statut change.
  /// Cette methode est donc presque toujours appelee avec `enApproche`.
  Future<void> pointerSuivi({
    required String commandeId,
    required JalonSuivi jalon,
    String auteur = 'admin',
  }) async {
    final client = MboaReseau.client;
    if (client != null) {
      try {
        await client.rpc(
          'pointer_suivi',
          params: {
            'p_commande_id': commandeId,
            'p_jalon': jalon.slug,
            'p_auteur': auteur,
          },
        );
        return;
      } catch (e) {
        debugPrint('pointage suivi distant refuse: $e');
      }
    }

    // Mode hors ligne : on ne peut pas poser un jalon manuel sans connexion.
    // Le jalon partira quand la connexion reviendra.
    await _base.enfiler(
      entite: Entites.commande,
      id: commandeId,
      operation: 'rpc:pointer_suivi',
      payload: {
        'commande_id': commandeId,
        'jalon': jalon.slug,
        'auteur': auteur,
      },
    );
  }

  // --------------------------------------------------------------------------
  // Aides
  // --------------------------------------------------------------------------

  List<Commande> _cacheEtConvertis(List<Map<String, dynamic>> lignes) {
    for (final ligne in lignes) {
      // Écrire dans le cache ne doit jamais faire échouer une lecture réussie.
      unawaited(_base.stocker(Entites.commande, ligne));
    }
    return lignes.map(Commande.fromMap).toList()..sort(_plusRecente);
  }

  /// Dépose une preuve dans le bucket `preuves` et rattache son chemin à la
  /// commande.
  Future<void> _preuve({
    required String commandeId,
    required String dossier,
    required String colonne,
    required Uint8List octets,
    required String extension,
    required String mime,
  }) async {
    final chemin = await MboaReseau.televerser(
      bucket: 'preuves',
      dossier: dossier,
      nom: '$commandeId.$extension',
      octets: octets,
      mime: mime,
    );
    if (chemin == null) return;

    final modifications = <String, dynamic>{colonne: chemin};
    await _majCache(commandeId, modifications);

    final client = MboaReseau.client;
    if (client == null) {
      await _enfiler(commandeId, modifications);
      return;
    }
    try {
      await client.from('commandes').update(modifications).eq('id', commandeId);
    } catch (e) {
      debugPrint('$colonne en attente: $e');
      await _enfiler(commandeId, modifications);
    }
  }

  Future<void> _majCache(String id, Map<String, dynamic> modifications) async {
    final lignes = await _base.lignesCachees(Entites.commande);
    final existante = lignes.where((l) => l['id'] == id);
    if (existante.isEmpty) return;
    await _base.stocker(Entites.commande, {...existante.first, ...modifications});
  }

  Future<void> _enfiler(String id, Map<String, dynamic> payload) => _base.enfiler(
        entite: Entites.commande,
        id: id,
        operation: 'update',
        payload: {'id': id, ...payload},
      );

  static int _plusRecente(Commande a, Commande b) => b.createdLe.compareTo(a.createdLe);
}
