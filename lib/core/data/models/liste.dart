import 'dart:convert';
import 'dart:math';

import 'commande.dart';

/// Un brouillon de devis prepare par une cliente.
///
/// Table `public.listes`. Ce n'est pas un panier technique : c'est un papier.
/// Elle a un code court que la mama peut dicter au telephone, une image
/// filigranee qu'elle montre au livreur ou envoie a sa fille sur WhatsApp, et
/// elle survit a la session.
///
/// Le lien avec le devis est dans l'autre sens qu'on attendrait : la liste ne
/// se transforme pas en panier, elle est la preparation du panier. Une liste
/// convertie garde sa trace de ce qui avait ete prepare a cote de ce qui a
/// ete garde.
///
/// Elle n'a plus de `fournisseur_id` : la cliente prepare ce qu'elle veut au
/// comptoir, pas chez un village. C'est la consequence directe du modele
/// economique, et c'est aussi ce qui rend le papier plus simple, une seule
/// chose a choisir, les articles.
class ListeMarche {
  const ListeMarche({
    required this.id,
    required this.consommateurId,
    required this.lignes,
    required this.code,
    required this.titre,
    required this.createdLe,
    this.imageUrl,
    this.transformeeEn,
    this.transformeeLe,
    this.envoyeeLe,
    this.consommateurNom,
    this.consommateurTelephone,
    this.livreurNom,
    this.livreurPlaque,
    this.livreurTelephone,
    this.livreurTarif,
  });

  final String id;
  final String consommateurId;

  /// Meme forme que `commandes.produits` : une liste est un devis en
  /// attente, et ca evite deux serialisations differentes pour un meme objet.
  final List<LigneCommande> lignes;

  /// 7 caracteres, dictables : « h, k, m, p, q, 2, 3 ».
  final String code;

  final String titre;
  final DateTime createdLe;

  /// L'image filigranee, une fois generee cote cliente puis televersee.
  final String? imageUrl;

  final String? transformeeEn;
  final DateTime? transformeeLe;
  final DateTime? envoyeeLe;

  final String? consommateurNom;
  final String? consommateurTelephone;

  // --- Le moto qui a porte le devis ne de cette liste -----------------------
  //
  // Une liste n'a pas de livreur : le livreur est affecte au devis. Ces
  // champs ne sont donc jamais remplis par la table `listes`, mais par
  // `DepotListes.avecLivreur`, qui relit le devis ne de la liste.
  //
  // Ils existent parce que la mama qui renvoie son papier le surlendemain
  // veut savoir qui vient, et que l'image partagee est le seul endroit ou
  // cette information survit a la fermeture de l'app.

  final String? livreurNom;
  final String? livreurPlaque;
  final String? livreurTelephone;

  /// Le prix de la course, porte sur le papier. Une mama qui lit son devis
  /// doit savoir ce qu'elle doit a la moto en plus de la marchandise : c'est
  /// le seul montant qui se regle a part, a la porte.
  final int? livreurTarif;

  bool get aUnLivreur => livreurNom != null && livreurNom!.isNotEmpty;

  bool get estVide => lignes.isEmpty;
  bool get estTransformee => transformeeEn != null;

  /// Marchandise seulement. Le papier, lui, ajoute la course.
  int get montantEstime => lignes.fold(0, (somme, l) => somme + l.sousTotal);

  /// Ce qui sort du portefeuille a la porte.
  int get montantAPayer => montantEstime + (livreurTarif ?? 0);

  String get resumeQuantites => resumerQuantites(lignes);

  String get resumeProduits => lignes.map((l) => l.nom).join(', ');

  /// Ce que la voix lit quand la mama appuie sur le haut-parleur de sa liste.
  String get annonceVocale =>
      '$titre. ${lignes.length} articles, ${resumeQuantites}, '
      'environ $montantEstime francs. Code $code';

  /// Le code, lu caractere par caractere : une mama qui telephone ne doit
  /// pas epeler, elle doit dicter.
  String get codeDicte => code.split('').join(', ');

  factory ListeMarche.fromMap(Map<String, dynamic> map) {
    final brut = map['produits'];
    final List<dynamic> tableau = switch (brut) {
      final List<dynamic> l => l,
      final String s when s.trim().isNotEmpty => (jsonDecode(s) as List<dynamic>),
      _ => const <dynamic>[],
    };

    return ListeMarche(
      id: map['id'] as String,
      consommateurId: (map['consommateur_id'] ?? '') as String,
      lignes: tableau
          .whereType<Map<String, dynamic>>()
          .map(LigneCommande.fromJson)
          .toList(growable: false),
      code: (map['code'] ?? '') as String,
      titre: (map['titre'] as String?) ?? 'Ma liste',
      createdLe: DateTime.tryParse(map['created_at'] as String? ?? '') ?? DateTime.now(),
      imageUrl: map['image_url'] as String?,
      transformeeEn: map['transformee_en'] as String?,
      transformeeLe: DateTime.tryParse(map['transformee_le'] as String? ?? ''),
      envoyeeLe: DateTime.tryParse(map['envoyee_le'] as String? ?? ''),
      consommateurNom: map['nom_consommateur'] as String?,
      consommateurTelephone: map['telephone'] as String?,
      livreurNom: map['nom_livreur'] as String?,
      livreurPlaque: map['plaque'] as String?,
      livreurTelephone: map['telephone_livreur'] as String?,
      livreurTarif: (map['tarif_livreur'] as num?)?.round(),
    );
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'consommateur_id': consommateurId,
        'produits': lignes.map((l) => l.toJson()).toList(),
        'code': code,
        'titre': titre,
        'image_url': imageUrl,
        'montant_estime': montantEstime,
        'transformee_en': transformeeEn,
        'transformee_le': transformeeLe?.toIso8601String(),
        'envoyee_le': envoyeeLe?.toIso8601String(),
        'created_at': createdLe.toIso8601String(),
      };

  ListeMarche copieAvec({
    List<LigneCommande>? lignes,
    String? titre,
    String? imageUrl,
    String? transformeeEn,
    DateTime? envoyeeLe,
    String? livreurNom,
    String? livreurPlaque,
    String? livreurTelephone,
    int? livreurTarif,
  }) =>
      ListeMarche(
        id: id,
        consommateurId: consommateurId,
        lignes: lignes ?? this.lignes,
        code: code,
        titre: titre ?? this.titre,
        createdLe: createdLe,
        imageUrl: imageUrl ?? this.imageUrl,
        transformeeEn: transformeeEn ?? this.transformeeEn,
        transformeeLe: transformeeLe,
        envoyeeLe: envoyeeLe ?? this.envoyeeLe,
        consommateurNom: consommateurNom,
        consommateurTelephone: consommateurTelephone,
        // Reports explicites : le partage passe par une copie, et une copie
        // qui oublie ces champs produit un papier sans moto.
        livreurNom: livreurNom ?? this.livreurNom,
        livreurPlaque: livreurPlaque ?? this.livreurPlaque,
        livreurTelephone: livreurTelephone ?? this.livreurTelephone,
        livreurTarif: livreurTarif ?? this.livreurTarif,
      );
}

/// Le code court d'une liste, dictable au telephone.
///
/// Alphabet sans voyelles ambigues et sans chiffres qui se ressemblent a
/// l'oral : `0` et `o`, `1` et `i`, `5` et `f`, `u` et `v`. Une mama qui
/// dicte son code a l'agent ne doit pas repeter trois fois.
class CodeListe {
  const CodeListe._();

  /// Alphabet dictable : 16 signes, aucun ne se confond au telephone.
  static const String alphabet = 'hjkmpqrtwx234678';
  static const int longueur = 7;

  static final Random _hasard = Random.secure();

  /// Un code de sept caracteres, tire au hasard sur un alphabet qui ne se
  /// prete pas a la repetition. `Random.secure()` et pas `Random()` : un code
  /// qui sert a retrouver un papier ne doit pas se deviner en deux essais.
  static String generer() {
    final tampon = StringBuffer();
    for (var i = 0; i < longueur; i++) {
      tampon.write(alphabet[_hasard.nextInt(alphabet.length)]);
    }
    return tampon.toString();
  }

  static bool estValide(String code) =>
      code.length == longueur &&
      code.split('').every((c) => alphabet.contains(c));
}
