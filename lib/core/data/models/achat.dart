import 'categorie.dart';
import 'unite.dart';

/// Les cinq etats d'une marchandise proposee au comptoir.
///
/// Miroir exact de `public.statut_achat_enum`. Ce cycle est l'autre moitie du
/// commerce : le comptoir achete ferme chez l'agriculteur, il ne prend pas en
/// consignation. D'ou deux temps distincts que l'on confond souvent
/// `valide` veut dire « la marchandise est au stock », `paye` veut dire
/// « l'argent est sorti ». Les garder separés, c'est pouvoir dire a un
/// producteur exactement ou en est son argent sans mentir sur le stock.
enum StatutAchat {
  propose('propose', 'En attente du comptoir', 'Le comptoir regarde encore'),
  valide('valide', 'Achetée', 'Le comptoir a acheté, la marchandise est au stock'),
  paye('paye', 'Payée', 'Le comptoir a payé'),
  litige('litige', 'Refusée', 'Un problème a été signalé à la réception'),
  annule('annule', 'Non retenue', 'Le comptoir n’a pas retenu la marchandise');

  const StatutAchat(this.slug, this.libelle, this.annonce);

  final String slug;
  final String libelle;

  /// Ce que la voix dit a l'agriculteur. Une ligne de status que personne ne
  /// lit n'est pas une information, c'est un decor.
  final String annonce;

  bool get estAttente => this == StatutAchat.propose;

  /// Le stock est entre, l'argent n'est pas forcement sorti.
  bool get estPrise => this == StatutAchat.valide || this == StatutAchat.paye;

  bool get estPayee => this == StatutAchat.paye;

  /// Ce qui reste du a l'agriculteur.
  bool get estDu => this == StatutAchat.valide;

  static StatutAchat resolve(String? slug) => values.firstWhere(
        (s) => s.slug == slug,
        orElse: () => StatutAchat.propose,
      );
}

/// Une proposition d'achat, puis un achat du comptoir.
///
/// Table `public.achats`. L'agriculteur y dicte ce qu'il a, combien, comment
/// ça se compte et à quel prix ; le comptoir signe, et la signature fait
/// entrer la marchandise au stock (`mboa.valider_achat`).
///
/// Ce que la cliente finale ne voit pas tient dans ce fichier : le prix
/// d'achat, le nom de celui qui a fourni, et la file d'attente du comptoir.
/// Rien ici ne remonte a son ecran, et ce n'est pas un filtre d'affichage :
/// la vue `vitrine` ne selectionne simplement pas ces colonnes.
class Achat {
  const Achat({
    required this.id,
    required this.fournisseurId,
    required this.slug,
    required this.nom,
    required this.categorie,
    required this.unite,
    required this.quantite,
    required this.prixDemande,
    required this.photoUrl,
    this.produitId,
    this.prixMarchand,
    this.statut = StatutAchat.propose,
    this.audioUrl,
    this.motif,
    this.motifAudioUrl,
    this.proposeLe,
    this.valideLe,
    this.payeLe,
  });

  final String id;

  /// L'agriculteur qui vend au comptoir. Jamais la cliente.
  final String fournisseurId;

  /// La cle du stock, calculee a partir du nom dicte. C'est elle qui empeche
  /// « Bœuf », « boeuf » et « BOEUF » de devenir trois tas differents.
  final String slug;
  final String nom;
  final Categorie categorie;
  final Unite unite;
  final double quantite;

  /// Le prix demande par l'agriculteur, par unite.
  final int prixDemande;

  /// Le prix signe par le comptoir. Null tant que la proposition attend :
  /// marchander ne consiste pas a effacer ce qui a ete dit.
  final int? prixMarchand;

  final String photoUrl;
  final String? audioUrl;

  /// La fiche de stock que cet achat a alimentee, renseignee a la validation.
  final String? produitId;

  final StatutAchat statut;
  final String? motif;
  final String? motifAudioUrl;
  final DateTime? proposeLe;
  final DateTime? valideLe;
  final DateTime? payeLe;

  /// Ce que la marchandise a coute au comptoir. La base calcule cette colonne
  /// (`achats.montant`), jamais elle ne se saisit.
  int get montant => (quantite * (prixMarchand ?? prixDemande)).round();

  /// Le nom tel que la voix le prononce, avec sa mesure : « 40 kilos de
  /// manioc, à cent soixante francs le kilo ».
  String get annonce {
    final prix = prixMarchand ?? prixDemande;
    return '${unite.avec(quantite)} de $nom, à $prix francs ${unite.avecArticle}';
  }

  /// La ligne de la file du comptoir : ce qui est demande, et ce qui reste a
  /// decider. Un nom sans prix n'existe pas dans ce metier. Le nombre reste
  /// brut ici : le modele ne doit rien a la bibliotheque de widgets, et le
  /// groupement des milliers se fait a l'affichage.
  String get resume => '$nom · ${unite.avec(quantite)} · $prixDemande F ${unite.avecArticle}';

  factory Achat.fromMap(Map<String, dynamic> map) {
    return Achat(
      id: map['id'] as String,
      fournisseurId: (map['fournisseur_id'] ?? '') as String,
      slug: (map['slug'] ?? '') as String,
      nom: (map['nom'] ?? '') as String,
      categorie: Categorie.resolve(map['categorie'] as String?),
      unite: Unite.resolve(map['unite'] as String?),
      quantite: (map['quantite'] as num?)?.toDouble() ?? 0,
      prixDemande: (map['prix_demande'] as num?)?.round() ?? 0,
      prixMarchand: (map['prix_achat'] as num?)?.round(),
      photoUrl: (map['photo_url'] ?? '') as String,
      audioUrl: map['audio_url'] as String?,
      produitId: map['produit_id'] as String?,
      statut: StatutAchat.resolve(map['statut'] as String?),
      motif: map['motif'] as String?,
      motifAudioUrl: map['motif_audio_url'] as String?,
      proposeLe: DateTime.tryParse(map['propose_le'] as String? ?? ''),
      valideLe: DateTime.tryParse(map['valide_le'] as String? ?? ''),
      payeLe: DateTime.tryParse(map['paye_le'] as String? ?? ''),
    );
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'fournisseur_id': fournisseurId,
        'slug': slug,
        'nom': nom,
        'categorie': categorie.slug,
        'unite': unite.slug,
        'quantite': quantite,
        'prix_demande': prixDemande,
        'prix_achat': prixMarchand,
        'photo_url': photoUrl,
        'audio_url': audioUrl,
        'produit_id': produitId,
        'statut': statut.slug,
        'motif': motif,
        'motif_audio_url': motifAudioUrl,
        'propose_le': proposeLe?.toIso8601String(),
        'valide_le': valideLe?.toIso8601String(),
        'paye_le': payeLe?.toIso8601String(),
      };

  Achat copieAvec({StatutAchat? statut, int? prixMarchand, String? motif, String? produitId}) => Achat(
        id: id,
        fournisseurId: fournisseurId,
        slug: slug,
        nom: nom,
        categorie: categorie,
        unite: unite,
        quantite: quantite,
        prixDemande: prixDemande,
        prixMarchand: prixMarchand ?? this.prixMarchand,
        photoUrl: photoUrl,
        audioUrl: audioUrl,
        produitId: produitId ?? this.produitId,
        statut: statut ?? this.statut,
        motif: motif ?? this.motif,
        motifAudioUrl: motifAudioUrl,
        proposeLe: proposeLe,
        valideLe: valideLe,
        payeLe: payeLe,
      );
}
