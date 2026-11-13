import 'dart:convert';

import 'categorie.dart';
import 'pack_composant.dart';
import 'statuts.dart';
import 'unite.dart';

/// Resume lisible d'un panier, regroupe par unite.
///
/// « 8 kilos · 2 parts », jamais « 10 ». Additionner des kilos et des boules
/// en un seul nombre est l'erreur la plus facile des qu'un plat entre dans le
/// panier, et c'est une erreur que la cliente paie a la porte.
///
/// Une seule implementation, partagee par le devis, le panier, la liste de
/// marche et l'etat de liste : quatre copies de cette phrase auraient fini
/// par diverger.
String resumerQuantites(Iterable<LigneCommande> lignes) {
  final parUnite = <Unite, double>{};
  for (final l in lignes) {
    parUnite[l.uniteReelle] = (parUnite[l.uniteReelle] ?? 0) + l.quantite;
  }

  if (parUnite.isEmpty) return 'rien';

  return [
    for (final e in parUnite.entries) e.key.avec(e.value),
  ].join(' · ');
}

/// Une ligne du devis, telle qu'elle est gelee dans `commandes.produits`.
///
/// La ligne se suffit a elle-meme : elle porte le nom affiche, l'unite, le
/// prix de revente et le cout d'achat tels qu'ils etaient a la seconde de la
/// caisse. Recharger la fiche de stock a chaque affichage ferait glisser le
/// prix si l'admin l'avait ajuste entre-temps, et le papier cesserait d'etre
/// la preuve de quoi que ce soit.
///
/// Deux formes coexistent, et c'est voulu :
///   * une reference du stock, avec son `slug` ;
///   * une ligne dictee a la voix (« miondo, 5 paquets, 700 F »), sans slug,
///     dont le prix est une declaration que le comptoir valide.
class LigneCommande {
  const LigneCommande({
    required this.produitId,
    required this.nom,
    required this.categorie,
    required this.quantite,
    required this.prix,
    required this.photo,
    this.slug,
    this.unite,
    this.coutAchat = 0,
    this.composants = const [],
  });

  /// L'identifiant de la fiche de stock. Vide pour une ligne dictee.
  final String produitId;

  /// La cle du stock, null pour une ligne libre. C'est elle qui fait la
  /// difference entre « le comptoir n'a plus de bœuf » et « le comptoir ne
  /// vend pas de bœuf ».
  final String? slug;

  /// Le nom affiche et prononce, gele a la caisse.
  final String nom;
  final Categorie categorie;
  final double quantite;

  /// Prix de revente de l'unite au moment de la caisse. Modifier le prix de
  /// la fiche apres le devis ne change jamais le papier.
  final int prix;

  /// Ce que l'unite avait coute au comptoir, gelee en meme temps que [prix].
  /// C'est la moitie de la marge, et sans elle la marge d'un devis relit six
  /// mois plus tard dependrait du stock du jour.
  final int coutAchat;

  final String photo;

  /// Null sur une ligne du stock : on retombe sur l'unite de la fiche.
  final Unite? unite;

  /// La recette du plat. Non vide = la ligne est une part de pack.
  final List<PackComposant> composants;

  bool get estPack => composants.isNotEmpty;

  /// Une ligne que le stock ne connait pas : dictee a la voix.
  bool get estLibre => !estPack && (slug == null || slug!.isEmpty);

  Unite get uniteReelle =>
      unite ?? (estPack ? Unite.part : (estLibre ? Unite.morceau : Unite.kg));

  /// « 3 boules », « 5 kilos ».
  String get quantiteAffichee => uniteReelle.avec(quantite);

  /// « 3 boules de macabo ».
  String get annonce => '$quantiteAffichee de $nom';

  int get sousTotal => (quantite * prix).round();

  /// Ce que la ligne a coûte au comptoir.
  int get cout => (quantite * coutAchat).round();

  /// Le pas des boutons plus et moins : une unite a la fois.
  ///
  /// Une part de plat se regle a la part pres, et une ligne dictee n'a pas de
  /// paliers puisqu'elle n'est au catalogue de personne. Le premier montant,
  /// lui, vient des paliers de la reference quand la cliente touche une tuile
  /// de la grille : c'est la que l'echelle du marche s'exprime, pas dans le
  /// réglage fin.
  double get pas => 1;

  /// La phrase du bouton moins : « retirer 1 kilo ».
  String get annoncePas => '${uniteReelle.avec(pas)} de $nom';

  factory LigneCommande.fromJson(Map<String, dynamic> json) => LigneCommande(
        produitId: (json['produit_id'] ?? '') as String,
        slug: (json['slug'] as String?)?.trim().isEmpty ?? true
            ? null
            : (json['slug'] as String),
        nom: (json['nom'] ?? '') as String,
        categorie: Categorie.resolve(json['categorie'] as String?),
        quantite: (json['quantite'] as num?)?.toDouble() ?? 0,
        prix: (json['prix'] as num?)?.round() ?? 0,
        coutAchat: (json['cout_achat'] as num?)?.round() ?? 0,
        photo: (json['photo'] ?? '') as String,
        unite: json['unite'] == null ? null : Unite.resolve(json['unite'] as String?),
        composants: composantsDepuisJson(json['composants']),
      );

  Map<String, dynamic> toJson() => {
        'produit_id': produitId,
        'slug': slug ?? '',
        'nom': nom,
        'categorie': categorie.slug,
        'quantite': quantite,
        'unite': uniteReelle.slug,
        'prix': prix,
        'cout_achat': coutAchat,
        'photo': photo,
        if (estPack) 'composants': [for (final c in composants) c.toJson()],
      };

  /// Copie en changeant la quantite, et rien d'autre.
  ///
  /// Les + et les - du panier partagent ce chemin avec les lignes de plat et
  /// les lignes dictees : une copie qui oublierait `composants` ou
  /// `cout_achat` transformerait silencieusement un plat en produit simple, ou
  /// une marge en rien du tout.
  LigneCommande copieAvec({double? quantite, int? prix}) => LigneCommande(
        produitId: produitId,
        slug: slug,
        nom: nom,
        categorie: categorie,
        quantite: quantite ?? this.quantite,
        prix: prix ?? this.prix,
        coutAchat: coutAchat,
        photo: photo,
        unite: unite,
        composants: composants,
      );
}

/// Un devis de la cliente. Table `public.commandes`.
///
/// Le vendeur est MBOA BIO : il n'y a plus de `fournisseur_id` ici, et donc
/// plus de regle du « un panier = un village ». Un meme devis peut melanger
/// le manioc entrepose a Mbouda et la chevre venue de Fee, puisque c'est un
/// seul stock qui part et une seule moto qui le porte.
///
/// Trois argent cohabitent, et c'est ce qui rend le papier honnete :
///   * `montantTotal`, ce que la cliente a demande ;
///   * `montantLivre`, ce qu'elle a garde et paye a sa porte ;
///   * `coutAchat`, ce que la marchandise a coute au comptoir.
/// La marge ne se declenche que sur le pouce de la cliente, et se proroge sur
/// la part reellement gardee.
class Commande {
  const Commande({
    required this.id,
    required this.consommateurId,
    required this.lignes,
    required this.statut,
    required this.montantTotal,
    required this.createdLe,
    this.coutAchat = 0,
    this.montantLivre,
    this.paiement,
    this.paiementRef,
    this.livraisonMoto = true,
    this.stockSorti = false,
    this.photoLivraison,
    this.signature,
    this.appelVocalFait = false,
    this.livreeLe,
    this.recueLe,
    this.satisfaction,
    this.satisfactionMotif,
    this.satisfactionAudio,
    this.clos = false,
    this.closPar,
    this.annuleLe,
    this.motifAnnulation,
    this.livreurId,
    this.livreurNom,
    this.livreurPhoto,
    this.livreurMoto,
    this.livreurPlaque,
    this.livreurTelephone,
    this.livreurTarif,
  });

  final String id;
  final String consommateurId;
  final List<LigneCommande> lignes;
  final StatutCommande statut;
  final int montantTotal;

  /// Somme des couts d'achat des lignes, figee a la caisse.
  final int coutAchat;
  final DateTime createdLe;

  /// Encaisse a la porte, saisi par le comptoir en pointant la livraison.
  final int? montantLivre;
  final DateTime? livreeLe;

  /// Le tap de la cliente. Null tant qu'elle n'a pas repondu.
  final DateTime? recueLe;
  final Satisfaction? satisfaction;
  final String? satisfactionMotif;
  final String? satisfactionAudio;

  /// Vrai quand le devis est financierement solde. C'est le seul etat qui
  /// fait exister une marge.
  final bool clos;
  final String? closPar;

  /// Vrai quand les quantites ont ete retirees du stock. La garde unique du
  /// retour : sans elle, deux annulations rendraient la meme marchandise.
  final bool stockSorti;

  final ModePaiement? paiement;
  final String? paiementRef;
  final bool livraisonMoto;
  final String? photoLivraison;
  final String? signature;
  final bool appelVocalFait;

  final DateTime? annuleLe;
  final String? motifAnnulation;

  // --- Le moto qui porte le panier -----------------------------------------
  //
  // Nom, plaque et numero arrives par la jointure `livreurs(...)`. La plaque
  // est la, parce que c'est le repere qu'une personne agee verifie avant
  // d'ouvrir sa porte : elle reconnait la moto avant le visage.

  final String? livreurId;
  final String? livreurNom;
  final String? livreurPhoto;
  final String? livreurMoto;
  final String? livreurPlaque;

  /// Renvoye par l'RPC `mboa.contact_livreur`, jamais lu depuis la table.
  final String? livreurTelephone;

  /// Prix de la course. La cliente doit savoir ce qu'elle doit au moto en
  /// plus de la marchandise : ce n'est pas la meme poche.
  final int? livreurTarif;

  bool get aUnLivreur => livreurId != null;

  /// Ce qui est reellement du, ou rien du tout.
  int get montantDue => clos ? (montantLivre ?? 0) : 0;

  /// L'ecart entre ce qui a ete demande et ce qui a ete garde. Positif quand
  /// la cliente a reduit son panier a la porte : c'est la donnee qui dit au
  /// comptoir qu'une reference est survaluee ou mal photographiée.
  int get ecart => montantLivre == null ? 0 : montantTotal - montantLivre!;

  bool get ecartSignificatif => ecart > 0;

  /// La marge du devis, calculee comme la base la calcule
  /// (`mboa.marge_devis`) : zero tant que la cliente n'a pas solde, et cout
  /// d'achat proroge sur la part reellement gardee.
  ///
  /// Sans la prorata, un panier a moitie refuse afficherait une marge
  /// negative sur une vente normale.
  int get marge {
    if (!clos) return 0;
    final encaisse = montantLivre ?? 0;
    if (montantTotal <= 0) return encaisse;
    final coutGarde = (coutAchat * encaisse / montantTotal).round();
    return encaisse - coutGarde;
  }

  /// Ce que la marchandise a coute, ramene a ce qui a ete garde.
  int get coutGarde {
    final encaisse = montantLivre ?? 0;
    if (montantTotal <= 0) return 0;
    return (coutAchat * encaisse / montantTotal).round();
  }

  /// Marchandise plus course : ce qui sort du portefeuille a la porte.
  int get montantAPayer => montantTotal + (livreurTarif ?? 0);

  bool get attendConfirmation => statut == StatutCommande.livree;

  bool get estAnnule => statut == StatutCommande.annulee;

  /// Combien de temps la cliente a laisse passer depuis la livraison.
  ///
  /// Au-dela du delai de relance, le comptoir peut clore la ligne sans
  /// satisfaction : le silence d'une personne agee ne doit pas devenir une
  /// punition pour tout le monde.
  Duration? get depuisLivraison =>
      livreeLe == null ? null : DateTime.now().difference(livreeLe!);

  bool get preteARelance =>
      attendConfirmation && (depuisLivraison?.inHours ?? 0) >= 12;

  /// La confirmation attendue : un seul ecran, une seule phrase, deux pouces.
  String get messageConfirmation => 'Ta commande est arrivée. Tout est bon ?';

  /// Rang allume sur la timeline a 4 icones.
  int get etapeAllumee => statut.jalon;

  double get quantiteTotale => lignes.fold(0, (somme, l) => somme + l.quantite);

  String get resumeProduits => lignes.map((l) => l.nom).join(', ');

  /// Les quantites regroupees par unite : « 8 kilos · 2 parts ».
  String get resumeQuantites => resumerQuantites(lignes);

  /// Ce que la voix dit au comptoir quand un devis arrive.
  String get annonceVocale {
    final detail = lignes.map((l) => l.annonce).join(', ');
    return 'Un devis arrive pour $detail';
  }

  /// La ligne « qui vient » du suivi.
  String get livreurResume {
    if (!aUnLivreur) return 'Aucun livreur affecté pour le moment';
    final plaque = livreurPlaque;
    return '$livreurNom'
        '${plaque != null && plaque.isNotEmpty ? ' · plaque $plaque' : ''}'
        '${livreurMoto != null && livreurMoto!.isNotEmpty ? ' · $livreurMoto' : ''}';
  }

  String get livreurAnnonce {
    if (!aUnLivreur) return 'Aucun livreur n’est encore affecté';
    final plaque = livreurPlaque;
    final tarif = livreurTarif ?? 0;
    return 'C’est $livreurNom qui apporte votre panier'
        '${plaque != null && plaque.isNotEmpty ? ', plaque $plaque' : ''}'
        '${tarif > 0 ? ', la course coûte $tarif francs à lui payer en espèces' : ''}.';
  }

  factory Commande.fromMap(Map<String, dynamic> map) {
    final brut = map['produits'];
    // Le driver peut renvoyer soit un tableau deja decode, soit la chaine
    // JSON brute (c'est le cas de la copie SQLite locale).
    final List<dynamic> tableau = switch (brut) {
      final List<dynamic> l => l,
      final String s when s.trim().isNotEmpty => (jsonDecode(s) as List<dynamic>),
      _ => const <dynamic>[],
    };

    // La jointure Supabase rend un objet imbrique ; le cache local, lui, a
    // deja ete aplati a l'ecriture. Les deux formes se lisent ici.
    final livreurBrut = map['livreur'] ?? map['livreurs'];
    final livreur = livreurBrut is Map<String, dynamic>
        ? livreurBrut
        : const <String, dynamic>{};

    return Commande(
      id: map['id'] as String,
      consommateurId: (map['consommateur_id'] ?? '') as String,
      lignes: tableau
          .whereType<Map<String, dynamic>>()
          .map(LigneCommande.fromJson)
          .toList(growable: false),
      statut: StatutCommande.resolve(map['statut_enum'] as String?),
      montantTotal: (map['montant_total'] as num?)?.round() ?? 0,
      coutAchat: (map['cout_achat'] as num?)?.round() ?? 0,
      montantLivre: (map['montant_livre'] as num?)?.round(),
      paiement: map['paiement'] == null ? null : ModePaiement.resolve(map['paiement'] as String?),
      paiementRef: map['paiement_ref'] as String?,
      livraisonMoto: (map['livraison_moto'] as bool?) ?? true,
      stockSorti: (map['stock_sorti'] as bool?) ?? false,
      photoLivraison: map['photo_livraison_url'] as String?,
      signature: map['signature_url'] as String?,
      appelVocalFait: (map['appel_vocal_fait'] as bool?) ?? false,
      livreeLe: DateTime.tryParse(map['livree_le'] as String? ?? ''),
      recueLe: DateTime.tryParse(map['recue_le'] as String? ?? ''),
      satisfaction: Satisfaction.parse(map['satisfaction'] as String?),
      satisfactionMotif: map['satisfaction_motif'] as String?,
      satisfactionAudio: map['satisfaction_audio'] as String?,
      clos: (map['clos'] as bool?) ?? false,
      closPar: map['clos_par'] as String?,
      annuleLe: DateTime.tryParse(map['annule_le'] as String? ?? ''),
      motifAnnulation: map['motif_annulation'] as String?,
      createdLe: DateTime.tryParse(map['created_at'] as String? ?? '') ?? DateTime.now(),
      livreurId: map['livreur_id'] as String?,
      livreurNom: (livreur['nom'] ?? map['nom_livreur']) as String?,
      livreurPhoto: (livreur['photo'] ?? map['photo_livreur']) as String?,
      livreurMoto: (livreur['moto'] ?? map['moto']) as String?,
      livreurPlaque: (livreur['plaque'] ?? map['plaque']) as String?,
      livreurTarif: (livreur['tarif_course'] ?? map['tarif_livreur']) is num
          ? ((livreur['tarif_course'] ?? map['tarif_livreur']) as num).round()
          : null,
    );
  }

  /// Copie avec les champs de suivi reinjectes.
  ///
  /// L'RPC de caisse renvoie la ligne toute fraiche mais sans la jointure du
  /// livreur : c'est ici qu'on la remet, pour que la timeline affiche un nom
  /// des la premiere seconde. Tous les champs sont reports explicitement :
  /// une copie qui en oublie un le fait disparaitre sans erreur, et c'est le
  /// genre de perte qui ne se voit que chez la cliente.
  Commande copieAvec({
    String? livreurId,
    String? livreurNom,
    String? livreurPlaque,
    String? livreurMoto,
    String? livreurTelephone,
    int? livreurTarif,
    StatutCommande? statut,
    int? montantLivre,
    int? montantTotal,
    DateTime? livreeLe,
    DateTime? recueLe,
    DateTime? annuleLe,
    Satisfaction? satisfaction,
    String? satisfactionMotif,
    bool? clos,
    String? closPar,
    bool? stockSorti,
    String? motifAnnulation,
    List<LigneCommande>? lignes,
  }) =>
      Commande(
        id: id,
        consommateurId: consommateurId,
        lignes: lignes ?? this.lignes,
        statut: statut ?? this.statut,
        montantTotal: montantTotal ?? this.montantTotal,
        coutAchat: coutAchat,
        montantLivre: montantLivre ?? this.montantLivre,
        paiement: paiement,
        paiementRef: paiementRef,
        livraisonMoto: livraisonMoto,
        stockSorti: stockSorti ?? this.stockSorti,
        photoLivraison: photoLivraison,
        signature: signature,
        appelVocalFait: appelVocalFait,
        createdLe: createdLe,
        livreeLe: livreeLe ?? this.livreeLe,
        recueLe: recueLe ?? this.recueLe,
        satisfaction: satisfaction ?? this.satisfaction,
        satisfactionMotif: satisfactionMotif ?? this.satisfactionMotif,
        satisfactionAudio: satisfactionAudio,
        clos: clos ?? this.clos,
        closPar: closPar ?? this.closPar,
        annuleLe: annuleLe ?? this.annuleLe,
        motifAnnulation: motifAnnulation ?? this.motifAnnulation,
        livreurId: livreurId ?? this.livreurId,
        livreurNom: livreurNom ?? this.livreurNom,
        livreurPhoto: livreurPhoto,
        livreurMoto: livreurMoto ?? this.livreurMoto,
        livreurPlaque: livreurPlaque ?? this.livreurPlaque,
        livreurTelephone: livreurTelephone ?? this.livreurTelephone,
        livreurTarif: livreurTarif ?? this.livreurTarif,
      );

  /// Copie locale, pour le cache SQLite et la file d'envoi.
  Map<String, dynamic> toMap() => {
        'id': id,
        'consommateur_id': consommateurId,
        'produits': lignes.map((l) => l.toJson()).toList(),
        'statut_enum': statut.slug,
        'montant_total': montantTotal,
        'cout_achat': coutAchat,
        'montant_livre': montantLivre,
        'paiement': paiement?.slug,
        'paiement_ref': paiementRef,
        'livraison_moto': livraisonMoto,
        'stock_sorti': stockSorti,
        'photo_livraison_url': photoLivraison,
        'signature_url': signature,
        'appel_vocal_fait': appelVocalFait,
        'created_at': createdLe.toIso8601String(),
        'livree_le': livreeLe?.toIso8601String(),
        'recue_le': recueLe?.toIso8601String(),
        'satisfaction': satisfaction?.slug,
        'satisfaction_motif': satisfactionMotif,
        'satisfaction_audio': satisfactionAudio,
        'clos': clos,
        'clos_par': closPar,
        'annule_le': annuleLe?.toIso8601String(),
        'motif_annulation': motifAnnulation,
        'livreur_id': livreurId,
        'nom_livreur': livreurNom,
        'photo_livreur': livreurPhoto,
        'moto': livreurMoto,
        'plaque': livreurPlaque,
        'tarif_livreur': livreurTarif,
      };
}
