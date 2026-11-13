import 'categorie.dart';
import 'pack_composant.dart';
import 'unite.dart';

/// Une fiche du stock du comptoir.
///
/// Table `public.produits`. Ce n'est plus une recolte declaree par un
/// producteur : c'est une marchandise que MBOA BIO a achetee, qu'elle a en
/// quantite, et qu'elle revend. Deux prix vivent donc sur la meme ligne, et
/// c'est le coeur du modele economique :
///
///   * [prix], ce que la cliente paie a la porte. C'est le seul que son app
///     lit, parce que la vue `vitrine` ne selectionne pas l'autre.
///   * [prixAchat], ce que la marchandise a couté au comptoir, en moyenne
///     glissante sur les entrées. La marge en découle, et elle se lit ici,
///     pas dans un pourcentage prélevé sur la vente de quelqu'un d'autre.
///
/// Un plat prepare (pack) est la meme chose : une ligne de stock, dont la
/// recette est [composants]. La contrainte SQL
/// `produits_soit_produit_soit_pack` garantit qu'une ligne est soit un
/// produit simple, soit un pack nommé et chiffré en parts, jamais les deux,
/// jamais aucun des deux.
class Produit {
  const Produit({
    required this.id,
    required this.slug,
    required this.nom,
    required this.categorie,
    required this.photoReelle,
    required this.quantite,
    required this.prix,
    this.unite,
    this.prixAchat,
    this.photoFiligranee,
    this.audioDescription,
    this.perissable = true,
    this.actif = true,
    this.composants = const [],
    this.createdLe,
  });

  final String id;

  /// La cle stable, sans accent, en minuscules : `boeuf`, `poisson_fume`.
  /// C'est elle qui empeche « Bœuf », « bœuf » et « BOEUF » de devenir trois
  /// stocks differents, et elle est la porte d'entrée de chaque achat signé.
  final String slug;

  /// Le nom tel qu'il s'affiche et se prononce : « Bœuf », « Ndolè ».
  final String nom;

  /// Une des huit cases de la grille. Le catalogue est ouvert, la navigation
  /// ne l'est pas : c'est ce qui la garde lisible sans savoir lire.
  final Categorie categorie;

  final String photoReelle;

  /// Apposée par le comptoir. C'est elle que voit la cliente.
  final String? photoFiligranee;

  /// Nombre d'unités disponibles. [uniteReelle] dit dans quel sens la lire.
  final double quantite;

  /// Prix de revente à l'unité, en FCFA entier : pas de centime au marché.
  final int prix;

  /// Ce que l'unité a coûté au comptoir. Null tant que rien n'a été acheté
  /// une fiche créée à la main par l'admin avant son premier dépôt.
  final int? prixAchat;

  /// Null quand la fiche suit l'habitude du catalogue : le macabo en boules,
  /// l'arachide en litres.
  final Unite? unite;

  final String? audioDescription;

  /// Ce qui tourne et se jette si le comptoir dort dessus deux jours.
  final bool perissable;

  /// Retirée de la vitrine sans être effacée : l'historique des ventes et la
  /// carte du prix doivent survivre à l'arrêt d'une référence.
  final bool actif;

  /// La recette du plat, vide pour un produit simple.
  final List<PackComposant> composants;

  final DateTime? createdLe;

  bool get estPack => composants.isNotEmpty;

  /// L'unité effective du stock. Un plat se compte toujours en parts, quoi
  /// que l'admin ait saisi : c'est la contrainte SQL qui le dit, et le modèle
  /// ne doit pas en donner une deuxième version.
  Unite get uniteReelle => estPack ? Unite.part : (unite ?? Unite.kg);

  /// La photo qui s'affiche : filigranée dès qu'elle existe.
  String get photo => photoFiligranee ?? photoReelle;

  bool get estVitrine => actif && quantite > 0;
  bool get estPlein => quantite > 0;
  bool get estRupture => quantite <= 0;

  /// La jauge verte, de 0.0 à 1.0.
  ///
  /// Le plafond suit l'unité, et le caractère périssable ne fait que moduler
  /// le kilo : 20 kilos de tomate ne se lisent pas comme 20 kilos de riz, et
  /// un plat de six parts n'a rien à faire sur une échelle de 120.
  ///
  /// Le `default` est volontaire : énumérer les unités une à une faisait
  /// planter la compilation à chaque unité ajoutée au catalogue.
  double get jauge {
    final plafond = switch (uniteReelle) {
      Unite.part => 20.0,
      Unite.kg => perissable ? 20.0 : 120.0,
      _ => 60.0,
    };
    return (quantite / plafond).clamp(0.0, 1.0);
  }

  /// Ce que dit le haut-parleur de la tuile : « Bœuf, 14 kilos disponibles,
  /// 4 000 francs le kilo ». Ni producteur, ni village : la cliente achète au
  /// comptoir, et un nom d'agriculteur sur une tuile ne prouve rien sur la
  /// marchandise.
  String get annonceVocale =>
      '$nom, ${uniteReelle.avec(quantite)} disponibles, $prix francs ${uniteReelle.avecArticle}';

  /// La ligne courte de la tuile : « 18 kilos disponibles », « plus rien ».
  String get disponibilite =>
      estRupture ? 'plus rien au comptoir' : '${uniteReelle.avec(quantite)} disponibles';

  /// Le prix tel qu'il s'écrit sur une tuile : « 350 F la boule ». L'article
  /// vient de l'unité, jamais de l'écran.
  String get prixLabel => '$prix F ${uniteReelle.avecArticle}';

  int montantPour(double nombre) => (nombre * prix).round();

  // --- Ce que le comptoir seul regarde --------------------------------------

  /// La marge unitaire, ou null tant que le coût n'est pas connu. Afficher
  /// « 0 F » sur une fiche non encore achetée ferait croire à une vente à
  /// perte quand ce n'est qu'une fiche sans passé.
  int? get margeUnitaire => prixAchat == null ? null : prix - prixAchat!;

  /// Pourcentage de marge sur le prix d'achat. Null sans coût d'achat, ou sur
  /// un coût nul.
  int? get margePct {
    final achat = prixAchat;
    if (achat == null || achat <= 0) return null;
    return (((prix - achat) / achat) * 100).round();
  }

  /// Vrai quand la fiche se vend moins que son coût. Ce n'est pas une
  /// hypothèse : ça arrive à chaque entrée plus chère que la précédente, et
  /// l'admin doit le voir avant la cliente.
  bool get estAPerte {
    final marge = margeUnitaire;
    return marge != null && marge < 0;
  }

  factory Produit.fromMap(Map<String, dynamic> map) {
    final brutUnite = map['unite'] as String?;
    return Produit(
      id: map['id'] as String,
      slug: (map['slug'] ?? '') as String,
      nom: (map['nom'] ?? '') as String,
      categorie: Categorie.resolve(map['categorie'] as String?),
      // La vitrine expose deja la bonne photo sous `photo` : c'est le seul
      // chemin par lequel la cliente recoit une image, et lire `photo_reelle`
      // seule lui rendait un chemin vide sur chaque tuile.
      photoReelle: (map['photo_reelle'] ?? map['photo']) as String? ?? '',
      photoFiligranee: map['photo_filigranee'] as String?,
      quantite: (map['quantite'] as num?)?.toDouble() ?? 0,
      prix: (map['prix'] as num?)?.round() ?? 0,
      unite: brutUnite == null ? null : Unite.resolve(brutUnite),
      prixAchat: (map['prix_achat'] as num?)?.round(),
      audioDescription: map['audio_description_url'] as String?,
      perissable: (map['perissable'] as bool?) ?? true,
      actif: (map['actif'] as bool?) ?? true,
      composants: composantsDepuisJson(map['pack_composants']),
      createdLe: DateTime.tryParse(map['created_at'] as String? ?? ''),
    );
  }

  /// Ecriture du comptoir. Les colonnes de stock (`quantite`, `prix_achat`)
  /// ne passent pas par ici : elles appartiennent aux RPC d'achat et de
  /// devis. Une fiche dont l'écran écrirait la quantité directement
  /// fausserait l'inventaire sans laisser de trace.
  Map<String, dynamic> toMap() => {
        'id': id,
        'slug': slug,
        'nom': nom,
        'categorie': categorie.slug,
        'unite': uniteReelle.slug,
        'photo_reelle': photoReelle,
        'photo_filigranee': photoFiligranee,
        'audio_description_url': audioDescription,
        'prix': prix,
        'perissable': perissable,
        'actif': actif,
        'pack_composants': estPack
            ? [for (final c in composants) c.toJson()]
            : null,
        'created_at': createdLe?.toIso8601String(),
      };

  Produit copieAvec({
    double? quantite,
    int? prix,
    int? prixAchat,
    String? photoFiligranee,
    String? audioDescription,
    bool? actif,
    bool? perissable,
    Unite? unite,
    List<PackComposant>? composants,
  }) =>
      Produit(
        id: id,
        slug: slug,
        nom: nom,
        categorie: categorie,
        photoReelle: photoReelle,
        photoFiligranee: photoFiligranee ?? this.photoFiligranee,
        quantite: quantite ?? this.quantite,
        prix: prix ?? this.prix,
        unite: unite ?? this.unite,
        prixAchat: prixAchat ?? this.prixAchat,
        audioDescription: audioDescription ?? this.audioDescription,
        perissable: perissable ?? this.perissable,
        actif: actif ?? this.actif,
        composants: composants ?? this.composants,
        createdLe: createdLe,
      );
}
