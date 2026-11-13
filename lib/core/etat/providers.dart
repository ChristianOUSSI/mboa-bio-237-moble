import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/app_role.dart';
import '../data/base_locale.dart';
import '../data/depot_achats.dart';
import '../data/depot_auth.dart';
import '../data/depot_commandes.dart';
import '../data/depot_fournisseurs.dart';
import '../data/depot_listes.dart';
import '../data/depot_livreurs.dart';
import '../data/depot_produits.dart';
import '../data/models/catalogue.dart';
import '../data/models/achat.dart';
import '../data/models/categorie.dart';
import '../data/models/commande.dart';
import '../data/models/fournisseur.dart';
import '../data/models/liste.dart';
import '../data/models/livreur.dart';
import '../data/models/produit.dart';
import '../data/models/profil.dart';
import '../data/models/repere.dart';
import '../data/models/statuts.dart';
import '../data/models/suivi_colis.dart';
import '../data/models/unite.dart';
import '../data/mboa_reseau.dart';
import '../data/service_sync.dart';
import '../utils/format_monnaie.dart';
import '../temps_reel/hub_realtime.dart';
import '../voice/note_vocale.dart';
import '../voice/stt_service.dart';
import '../voice/tts_service.dart';

// =============================================================================
// Racine : les objets metier, construits une seule fois et injectes.
// =============================================================================

/// Surcharge dans `main()` apres l'ouverture de SQLite. Tous les depots en
/// dependent, donc c'est le seul point d'entre du monde local.
final baseLocaleProvider = Provider<BaseLocale>(
  (ref) => throw StateError('baseLocaleProvider doit etre surcharge dans main()'),
);

final depotAuthProvider = Provider<DepotAuth>((ref) => DepotAuth(ref.watch(baseLocaleProvider)));

final depotProduitsProvider =
    Provider<DepotProduits>((ref) => DepotProduits(ref.watch(baseLocaleProvider)));

final depotCommandesProvider =
    Provider<DepotCommandes>((ref) => DepotCommandes(ref.watch(baseLocaleProvider)));

final depotListesProvider =
    Provider<DepotListes>((ref) => DepotListes(ref.watch(baseLocaleProvider)));

final depotLivreursProvider =
    Provider<DepotLivreurs>((ref) => DepotLivreurs(ref.watch(baseLocaleProvider)));

final depotFournisseursProvider =
    Provider<DepotFournisseurs>((ref) => DepotFournisseurs(ref.watch(baseLocaleProvider)));

final depotAchatsProvider =
    Provider<DepotAchats>((ref) => DepotAchats(ref.watch(baseLocaleProvider)));

final serviceSyncProvider =
    Provider<ServiceSync>((ref) => ServiceSync(ref.watch(baseLocaleProvider)));

final hubProvider = Provider<HubRealtime>((ref) {
  final hub = HubRealtime(ref.watch(baseLocaleProvider));
  ref.onDispose(hub.fermer);
  return hub;
});

/// Les trois services vocaux sont des singleton `ChangeNotifier`. Ils sont
/// exposes tels quels pour que les ecrans s'y accrochent avec
/// `ListenableBuilder` : les envelopper dans Riverpod dupliquerait un etat
/// qui appartient au systeme, pas a l'app.
final voixProvider = Provider<TtsService>((ref) => TtsService.instance);
final dicteeProvider = Provider<SttService>((ref) => SttService.instance);
final noteProvider = Provider<NoteVocaleService>((ref) => NoteVocaleService.instance);

// =============================================================================
// Session
// =============================================================================

class Session {
  const Session({required this.profil, required this.role});

  final Profil profil;

  /// Le role vient de la base. Le flavor du build ne decide que de l'ecran
  /// d'entree : si les deux divergent, la base gagne, et l'app redirige.
  final AppRole role;

  String get identifiant => profil.id;
  String get village => profil.village;
  String get nom => profil.nom;
}

class SessionEtats extends StateNotifier<Session?> {
  SessionEtats(this._depot, this._base, this._hub) : super(null);

  final DepotAuth _depot;
  final BaseLocale _base;
  final HubRealtime _hub;

  /// Reprise de session a froid, puis ecoute du temps reel.
  Future<void> demarrer() async {
    final profil = await _depot.profilActuel();
    if (profil == null) {
      state = null;
      return;
    }
    await basculer(profil);
  }

  Future<void> basculer(Profil profil) async {
    state = Session(profil: profil, role: AppRole.resolve(profil.role));
    await TtsService.instance.definirLangue(profil.langue);
    await _hub.demarrer();
  }

  Future<void> deconnexion() async {
    await _hub.arreter();
    await _depot.deconnexion();
    state = null;
  }

  /// Nom, village, langue : les trois champs que l'utilisateur corrige apres
  /// son inscription. L'ecriture est locale d'abord, le serveur suivra.
  Future<void> majProfil(Profil profil) async {
    await _base.stocker(Entites.profil, profil.toMap());
    await _base.ecrireEtat('session', profil.id);
    await TtsService.instance.definirLangue(profil.langue);

    final client = MboaReseau.client;
    if (client != null) {
      try {
        await client
            .from('profiles')
            .update({
              'nom': profil.nom,
              'village': profil.village,
              'langue': profil.langue.slug,
              'photo_visage': profil.photoVisage,
            })
            .eq('id', profil.id);
      } catch (e) {
        debugPrint('profil distant en attente: $e');
      }
    }

    state = Session(profil: profil, role: AppRole.resolve(profil.role));
  }
}

final sessionProvider = StateNotifierProvider<SessionEtats, Session?>((ref) {
  final etats = SessionEtats(
    ref.watch(depotAuthProvider),
    ref.watch(baseLocaleProvider),
    ref.watch(hubProvider),
  );
  // Le redemarrage est declenche par l'ecran de garde : un `demarrer()` ici
  // transformerait la construction d'un provider en effet de bord invisible.
  return etats;
});

// =============================================================================
// Reseau et file d'attente
// =============================================================================

/// Vrai quand au moins une interface est up. connectivity_plus 6 renvoie une
/// liste de resultats par evenement, pas un resultat simple.
final reseauProvider = StreamProvider<bool>((ref) async* {
  final initial = await Connectivity().checkConnectivity();
  yield _estJoignable(initial);
  yield* Connectivity()
      .onConnectivityChanged
      .map(_estJoignable)
      .handleError((Object e) => debugPrint('ecoute reseau perdue: $e'));
});

bool _estJoignable(List<ConnectivityResult> etats) =>
    etats.isNotEmpty && !etats.every((e) => e == ConnectivityResult.none);

/// Nombre d'envois que le telephone n'a pas encore pu faire passer.
///
/// Se recalcule a chaque bascule du reseau : le bandeau « 3 envois en attente »
/// du fournisseur doit disparaitre tout seul quand la 3G revient, sinon il ne
/// sert pas a grand-chose.
final fileAttenteProvider = FutureProvider<int>((ref) async {
  final connecte = ref.watch(reseauProvider).value ?? false;
  if (connecte) return ref.watch(serviceSyncProvider).viderFile();
  return ref.watch(baseLocaleProvider).tailleFile();
});

// =============================================================================
// Catalogue et stock
// =============================================================================

final catalogueProvider = FutureProvider<List<EntreeCatalogue>>(
  (ref) => ref.watch(depotProduitsProvider).catalogue(),
);

/// Les 8 cases du catalogue, dans l'ordre de la grille.
final grilleProvider = FutureProvider<List<EntreeCatalogue>>((ref) async {
  final entrees = await ref.watch(catalogueProvider.future);
  return [...entrees]..sort((a, b) => a.ordre.compareTo(b.ordre));
});

/// La vitrine de la cliente, filtree par categorie ou dans sa totalite.
final vitrineProvider = FutureProvider.family<List<Produit>, Categorie?>(
  (ref, filtre) => ref.watch(depotProduitsProvider).vitrine(filtre: filtre),
);

/// Tout le stock du comptoir, pour l'admin.
final stockProvider = FutureProvider<List<Produit>>(
  (ref) => ref.watch(depotProduitsProvider).stock(),
);

/// Les points verts de la carte admin : un point par village producteur.
///
/// Agrege cote client et non cote serveur, parce que la liste des villages
/// tient en quelques dizaines de lignes et que l'admin doit pouvoir l'afficher
/// hors connexion.
final repereProvider = FutureProvider<List<RepereVillage>>((ref) async {
  final client = MboaReseau.client;
  if (client == null) return RepereVillage.horsLigne();

  try {
    final lignes = await client
        .from('profiles')
        .select('village, latitude, longitude, actif')
        .eq('role', 'fournisseur')
        .eq('actif', true)
        .not('latitude', 'is', null);

    final parVillage = <String, (double, double, int)>{};
    for (final ligne in lignes) {
      final village = (ligne['village'] as String?) ?? 'Inconnu';
      final lat = (ligne['latitude'] as num).toDouble();
      final lng = (ligne['longitude'] as num).toDouble();
      final courant = parVillage[village];
      parVillage[village] = (lat, lng, (courant?.$3 ?? 0) + 1);
    }

    final repere = parVillage.entries
        .map((e) => RepereVillage(
              village: e.key,
              latitude: e.value.$1,
              longitude: e.value.$2,
              fournisseurs: e.value.$3,
              recoltes: 0,
            ))
        .toList()
      ..sort((a, b) => b.fournisseurs.compareTo(a.fournisseurs));
    return repere;
  } catch (e) {
    debugPrint('carte indisponible, repli sur les villages connus: $e');
    return RepereVillage.horsLigne();
  }
});

// =============================================================================
// Commandes
// =============================================================================

final commandesClienteProvider = FutureProvider<List<Commande>>((ref) {
  final session = ref.watch(sessionProvider);
  if (session == null) return const [];
  return ref.watch(depotCommandesProvider).pourConsommateur(session.identifiant);
});

final commandesAdminProvider = FutureProvider<List<Commande>>(
  (ref) => ref.watch(depotCommandesProvider).toutes(),
);

/// Les livraisons que l'admin doit pointer aujourd'hui.
final livraisonsAPointerProvider = FutureProvider<List<Commande>>(
  (ref) => ref.watch(depotCommandesProvider).aPointer(),
);

/// Le profil d'un compte, relu a l'unite.
///
/// Utilise par l'ecran de livraison pour nommer la cliente : la commande ne
/// porte que son identifiant, et c'est l'admin qui a le droit de savoir a qui
/// la moto va apporter le panier.
final profilParIdProvider = FutureProvider.family<Profil?, String>(
  (ref, identifiant) => ref.watch(depotAuthProvider).profilParId(identifiant),
);

/// Livrées depuis 12 h sans que la cliente ait répondu.
final relancesProvider = FutureProvider<List<Commande>>(
  (ref) => ref.watch(depotCommandesProvider).sansConfirmation(),
);

/// Les commandes de la cliente qui attendent son pouce.
final aConfirmerProvider = FutureProvider<List<Commande>>((ref) async {
  final toutes = await ref.watch(commandesClienteProvider.future);
  return toutes.where((c) => c.attendConfirmation).toList();
});

/// Le nombre de confirmations en attente : la pastille de l'app cliente.
final confirmationsAttenteProvider = FutureProvider<int>(
  (ref) async => (await ref.watch(aConfirmerProvider.future)).length,
);

/// Le suivi de colis d'une commande, rafraichi par le temps reel.
///
/// Ce provider est parametre par l'identifiant de la commande : chaque
/// commande a sa propre timeline, et l'ecran de suivi la relit a chaque
/// evenement temps reel.
final suiviColisProvider = FutureProvider.family<SuiviColis, String>(
  (ref, commandeId) => ref.watch(depotCommandesProvider).suivi(commandeId),
);

final listesProvider = FutureProvider<List<ListeMarche>>((ref) {
  final session = ref.watch(sessionProvider);
  if (session == null) return const [];
  return ref.watch(depotListesProvider).mesListes(session.identifiant);
});

/// Le tableau des livreurs, dans l'ordre des zones.
final livreursProvider = FutureProvider<List<Livreur>>(
  (ref) => ref.watch(depotLivreursProvider).tous(),
);

/// La fiche du compte livreur connecté, null si le comptoir ne l'a pas
/// encore rattachée.
final maFicheLivreurProvider = FutureProvider<Livreur?>(
  (ref) => ref.watch(depotLivreursProvider).maFiche(),
);

/// Les courses affectées au livreur connecté.
final mesCoursesProvider = FutureProvider<List<CourseLivreur>>(
  (ref) => ref.watch(depotCommandesProvider).mesCourses(),
);

/// Tous les livreurs, meme inactifs : l'admin doit pouvoir relancer l'un
/// d'entre eux sans appeler le depot une deuxieme fois.
final livreursCompletsProvider = FutureProvider<List<Livreur>>(
  (ref) => ref.watch(depotLivreursProvider).tous(seulementActifs: false),
);

/// Le fichier des producteurs du comptoir, actifs et retires.
final fournisseursProvider = FutureProvider<List<Fournisseur>>(
  (ref) => ref.watch(depotFournisseursProvider).tous(),
);

/// Les packs composes par l'admin, epuises compris.
final packsProvider = FutureProvider<List<Produit>>(
  (ref) => ref.watch(depotProduitsProvider).packs(),
);

/// La file des marchandises proposees par les agriculteurs.
///
/// C'est le haut de la journee du comptoir : rien n'entre au stock sans une
/// signature ici, et un achat signe mais non paye reste visible jusqu'au
/// dernier franc.
final achatsEnAttenteProvider = FutureProvider<List<Achat>>(
  (ref) => ref.watch(depotAchatsProvider).fileAttente(),
);

final achatsAPayerProvider = FutureProvider<List<Achat>>(
  (ref) => ref.watch(depotAchatsProvider).aPayer(),
);

/// Ce que le fournisseur connecte a vendu au comptoir.
final mesAchatsProvider = FutureProvider<List<Achat>>(
  (ref) => ref.watch(depotAchatsProvider).mesAchats(),
);

/// Deux chiffres seulement, ceux qu'un producteur vient chercher : ce qui
/// est deja paye, ce qui attend encore.
final mesGainsProvider = FutureProvider<Map<String, int>>(
  (ref) => ref.watch(depotAchatsProvider).mesGains(),
);

/// Fige une annonce du stock en ligne de panier ou de liste.
///
/// Le nom, le slug, l'unite, le prix de revente et le coût d'achat sont
/// transportés ici et nulle part ailleurs. Les recopier champ par champ dans
/// chaque notifier en oublierait trois : la ligne survit, elle s'affiche, et
/// elle s'appelle « Bœuf » parce que le nom est gelé.
LigneCommande _figerLigne(Produit produit, double quantite) => LigneCommande(
      produitId: produit.id,
      slug: produit.slug,
      nom: produit.nom,
      categorie: produit.categorie,
      quantite: quantite,
      prix: produit.prix,
      coutAchat: produit.prixAchat ?? 0,
      photo: produit.photo,
      unite: produit.unite,
      composants: produit.composants,
    );

/// L'etat de la liste de marche en cours.
///
/// Une liste n'est pas un panier qui attend sagement : c'est un papier qui
/// survit a la session, se montre au livreur et se transforme en commande.
/// Le notifier porte donc les deux temps, l'edition locale et l'ecriture en
/// base, et il ne ecrit en base que quand la mama le demande.
class ListeEtats extends StateNotifier<ListeState> {
  ListeEtats(this._depot) : super(const ListeState());

  final DepotListes _depot;

  Future<void> charger(String consommateurId) async {
    final active = await _depot.listeActive(consommateurId);
    if (active == null) {
      state = const ListeState();
      return;
    }
    state = ListeState(
      sauvee: active,
      lignes: {for (final l in active.lignes) l.produitId: l},
    );
  }

  /// Ajoute ou remplace la quantite.
  void poser(Produit produit, double kg) {
    if (kg <= 0) {
      retirer(produit.id);
      return;
    }

    final lignes = Map<String, LigneCommande>.from(state.lignes)
      ..[produit.id] = _figerLigne(produit, kg);

    state = ListeState(
      sauvee: state.sauvee,
      lignes: lignes,
      modifiee: true,
    );
  }

  /// Pose un article que le catalogue ne connait pas : « miondo, 5 paquets,
  /// 700 F », dicte a la voix.
  void poserLibre({
    required String nom,
    required double quantite,
    required Unite unite,
    required int prix,
  }) {
    // Un seul identifiant, la meme valeur pour la cle de la carte et pour la
    // ligne : deux `uuidV4()` consecutifs donneraient une ligne que le
    // bouton moins ne saurait pas retirer.
    final cle = '${nom.hashCode}_${DateTime.now().millisecondsSinceEpoch}';

    final lignes = Map<String, LigneCommande>.from(state.lignes)
      ..[cle] = LigneCommande(
        produitId: cle,
        nom: nom.trim(),
        categorie: Categorie.legume,
        quantite: quantite,
        prix: prix,
        photo: '',
        unite: unite,
      );

    state = ListeState(
      sauvee: state.sauvee,
      lignes: lignes,
      modifiee: true,
    );
  }

  void retirer(String produitId) {
    final lignes = Map<String, LigneCommande>.from(state.lignes)..remove(produitId);
    state = ListeState(
      sauvee: state.sauvee,
      lignes: lignes,
      modifiee: lignes.isNotEmpty,
    );
  }

  double quantiteDe(String produitId) => state.lignes[produitId]?.quantite ?? 0;

  List<LigneCommande> get articles => state.lignes.values.toList(growable: false);

  /// Repose une ligne deja en liste, avec une quantite differente.
  void ajusterQuantite(LigneCommande ligne, double kg) {
    if (kg <= 0) {
      retirer(ligne.produitId);
      return;
    }

    final lignes = Map<String, LigneCommande>.from(state.lignes)
      ..[ligne.produitId] = ligne.copieAvec(quantite: kg);

    state = ListeState(
      sauvee: state.sauvee,
      lignes: lignes,
      modifiee: true,
    );
  }

  /// Enregistre la liste, ou la met a jour si elle existe deja.
  Future<ListeMarche?> sauvegarder({
    required String consommateurId,
    required String consommateurNom,
    required String consommateurTelephone,
    required String titre,
  }) async {
    final courant = state;
    if (courant.lignes.isEmpty) return null;

    final existante = courant.sauvee;
    if (existante != null) {
      await _depot.modifierLignes(
        id: existante.id,
        lignes: articles,
        titre: titre,
      );
      state = ListeState(
        sauvee: existante.copieAvec(lignes: articles, titre: titre),
        lignes: courant.lignes,
      );
      return existante.copieAvec(lignes: articles, titre: titre);
    }

    final creee = await _depot.creer(
      consommateurId: consommateurId,
      lignes: articles,
      titre: titre,
      consommateurNom: consommateurNom,
      consommateurTelephone: consommateurTelephone,
    );

    state = ListeState(
      sauvee: creee,
      lignes: courant.lignes,
    );
    return creee;
  }

  /// Attache l'image filigranee generee sur le telephone.
  Future<void> attacherImage(String pngUrl) async {
    final sauvee = state.sauvee;
    if (sauvee == null) return;
    state = ListeState(
      sauvee: sauvee.copieAvec(imageUrl: pngUrl),
      lignes: state.lignes,
    );
  }

  Future<void> marquerEnvoyee() async {
    final sauvee = state.sauvee;
    if (sauvee == null) return;
    await _depot.marquerEnvoyee(sauvee.id);
  }

  Future<void> marquerTransformee(String commandeId) async {
    final sauvee = state.sauvee;
    if (sauvee == null) return;
    await _depot.marquerTransformee(sauvee.id, commandeId);
    state = const ListeState();
  }

  void vider() => state = const ListeState();
}

/// L'etat visible de la liste.
class ListeState {
  const ListeState({
    this.sauvee,
    this.lignes = const {},
    this.modifiee = false,
  });

  /// La liste telle qu'elle est en base, null si rien n'est enregistre.
  final ListeMarche? sauvee;
  final Map<String, LigneCommande> lignes;

  /// Vrai quand l'ecran a change depuis la derniere ecriture : le bouton
  /// « Enregistrer » reste actif, sinon il devient une promesse vide.
  final bool modifiee;

  bool get vide => lignes.isEmpty;
  int get count => lignes.length;
  List<LigneCommande> get articles => lignes.values.toList(growable: false);

  int get montantEstime => lignes.values.fold(0, (somme, l) => somme + l.sousTotal);

  String get resumeQuantites => resumerQuantites(lignes.values);

  String get code => sauvee?.code ?? '';

  /// La phrase lue quand la mama appuie sur le haut-parleur de sa liste.
  String get resumePourVoix {
    if (vide) return 'Votre liste est vide. Touchez un produit pour l’ajouter.';
    final detail = lignes.values
        .map((l) => '${l.quantiteAffichee} de ${l.nom}')
        .join(', ');
    return '$detail. Environ ${formaterFcfa(montantEstime)} francs.';
  }
}

final listeProvider = StateNotifierProvider<ListeEtats, ListeState>(
  (ref) => ListeEtats(ref.watch(depotListesProvider)),
);

// =============================================================================
// Panier de la cliente
// =============================================================================

/// Le panier n'est plus limite a un village : la cliente achete au comptoir,
/// et un devis peut melanger le manioc et la chevre.
class Panier {
  const Panier({required this.lignes});

  final Map<String, LigneCommande> lignes;

  bool get vide => lignes.isEmpty;
  int get count => lignes.length;
  List<LigneCommande> get articles => lignes.values.toList(growable: false);

  int get montantTotal => lignes.values.fold(0, (somme, l) => somme + l.sousTotal);

  String get resumeQuantites => resumerQuantites(lignes.values);

  /// La phrase que la voix lit sur le resume du panier.
  ///
  /// Elle enonce les produits puis le total a presenter a la porte, dans cet
  /// ordre : une mama qui entend d'abord le montant retient un chiffre, une
  /// mama qui entend les produits retient ce qu'elle doit preparer.
  String get resumePourVoix {
    if (vide) return 'Votre panier est vide';
    final detail = lignes.values
        .map((l) => '${l.quantiteAffichee} de ${l.nom}')
        .join(', ');
    return '$detail. Total ${formaterFcfa(montantTotal)}, à payer à la livraison.';
  }

  static const Panier vide = Panier(lignes: {});
}

class PanierEtats extends StateNotifier<Panier> {
  PanierEtats() : super(Panier.vide);

  /// Pose la quantite [kg] pour [produit].
  void poser(Produit produit, double kg) {
    if (kg <= 0) {
      retirer(produit.id);
      return;
    }

    final lignes = Map<String, LigneCommande>.from(state.lignes)
      ..[produit.id] = _figerLigne(produit, kg);

    state = Panier(lignes: lignes);
  }

  bool retirer(String produitId) {
    final lignes = Map<String, LigneCommande>.from(state.lignes)..remove(produitId);
    state = lignes.isEmpty ? Panier.vide : Panier(lignes: lignes);
    return true;
  }

  double quantiteDe(String produitId) => state.lignes[produitId]?.quantite ?? 0;

  /// Repose une ligne deja figuree, sans repasser par un Produit.
  ///
  /// C'est le chemin de la liste vers le panier : la ligne porte deja son
  /// prix, sa photo tels qu'ils etaient au moment ou la mama les a choisis.
  void poserLigne(LigneCommande ligne) {
    final lignes = Map<String, LigneCommande>.from(state.lignes)..[ligne.produitId] = ligne;
    state = Panier(lignes: lignes);
  }

  void vider() => state = Panier.vide;
}

final panierProvider = StateNotifierProvider<PanierEtats, Panier>((ref) => PanierEtats());

// =============================================================================
// Sons et annonces
// =============================================================================

/// L'evenement de la derniere minute : declenche le son villageois et
/// l'appel automatisse. Le hub diffuse en broadcast, donc les trois apps
/// peuvent ecouter en meme temps.
final evenementProvider = StreamProvider<EvenementMboa>((ref) => ref.watch(hubProvider).flux);

/// Annonce chaque evenement une seule fois.
///
/// La memoire est volontairement une simple `Set` en RAM : un redemarrage
/// d'app doit pouvoir rejouer la derniere commande, c'est justement ce qui
/// remplace l'appel vocal rate pendant la nuit.
class EmetteurSon extends ChangeNotifier {
  EmetteurSon(this._voix);

  final TtsService _voix;
  final Set<String> _dejaDits = {};

  int get annoncees => _dejaDits.length;

  void traiter(EvenementMboa evenement) {
    final cle = '${evenement.type.name}:${evenement.id}';
    if (_dejaDits.contains(cle)) return;
    _dejaDits.add(cle);
    unawaited(_voix.dire(_phrase(evenement)));
    notifyListeners();
  }

  /// La phrase depend du statut reellement recu, pas seulement du type
  /// d'evenement : une `commandeChangee` vaut aussi bien « la moto est en
  /// route » que « ta commande est arrivee, tout est bon ? », et seule la
  /// deuxieme doit declencher une action de la cliente.
  static String _phrase(EvenementMboa evenement) {
    if (evenement.type == TypeEvenement.commandeChangee) {
      return StatutCommande.resolve(evenement.apres['statut_enum'] as String?).annonce;
    }

    if (evenement.type == TypeEvenement.suiviColis) {
      final jalon = evenement.apres['jalon'] as String?;
      return JalonSuivi.resolve(jalon).annonce;
    }

    return switch (evenement.type) {
      TypeEvenement.nouvelleRecolte => 'Nouvelle récolte à valider',
      TypeEvenement.recolteModeree => 'Récolte mise à jour dans le marché',
      TypeEvenement.commandeRecue => 'Vous avez une nouvelle commande',
      TypeEvenement.commandeChangee => 'Votre commande avance',
      TypeEvenement.suiviColis => 'Votre colis avance',
      TypeEvenement.notification => 'Message de Mboa',
    };
  }
}

final emetteurSonProvider = ChangeNotifierProvider<EmetteurSon>(
  (ref) => EmetteurSon(ref.watch(voixProvider)),
);
