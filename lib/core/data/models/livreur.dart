import 'dart:convert';

import 'commande.dart';
import 'statuts.dart';

/// Un moto qui porte les paniers.
///
/// Table `public.livreurs`. La fiche est enregistree par le comptoir, qui y
/// rattache ensuite un compte (`profil_id`, role `livreur`) quand le moto veut
/// suivre ses courses lui-meme. Le rattachement reste facultatif : un livreur
/// sans application continue de travailler, le comptoir pointe pour lui.
///
/// Trois champs existent pour une seule raison : la securite d'une femme agee
/// qui ouvre sa porte. Qui vient, sur quelle moto, a quel numero.
class Livreur {
  const Livreur({
    required this.id,
    required this.nom,
    required this.telephone,
    required this.zone,
    this.profilId,
    this.photo,
    this.moto,
    this.plaque,
    this.tarifCourse = 0,
    this.actif = true,
  });

  final String id;

  /// Le nom tel que la mama l'a entendu au telephone, en toutes lettres.
  final String nom;

  /// `+2376XXXXXXXX`. Il ne sort de la base que par `mboa.contact_livreur`,
  /// pour les parties a la course.
  final String telephone;

  /// Le village ou le quartier d'ou il part.
  final String zone;

  /// Lie au compte quand le livreur a aussi une app, jamais obligatoire.
  final String? profilId;

  final String? photo;

  /// Marque et modele de la moto.
  final String? moto;

  /// L'immatriculation, telle qu'elle est peinte sur la garde-boue.
  final String? plaque;

  /// Prix de la course en FCFA. Affiche sur la liste : la mama doit savoir
  /// ce qu'elle doit au moto en plus de sa marchandise.
  final int tarifCourse;

  /// On ne supprime pas un livreur : ses courses passees doivent rester
  /// rattachables a quelqu'un.
  final bool actif;

  /// Le repere que la cliente verifie avant d'ouvrir.
  String get repere {
    final p = plaque;
    if (p != null && p.trim().isNotEmpty) return p.trim();
    final m = moto;
    if (m != null && m.trim().isNotEmpty) return m.trim();
    return nom;
  }

  /// Ce que la voix dit quand on touche le haut-parleur de la carte.
  String get annonce {
    final p = plaque;
    return 'C’est $nom, de $zone'
        '${p != null && p.isNotEmpty ? ', plaque $p' : ''}'
        '${tarifCourse > 0 ? ', la course coûte $tarifCourse francs' : ''}.';
  }

  factory Livreur.fromMap(Map<String, dynamic> map) => Livreur(
        id: map['id'] as String,
        nom: (map['nom'] as String?) ?? 'Livreur',
        telephone: (map['telephone_237'] as String?) ?? '',
        zone: (map['zone'] as String?) ?? '',
        profilId: map['profil_id'] as String?,
        photo: map['photo'] as String?,
        moto: map['moto'] as String?,
        plaque: map['plaque'] as String?,
        tarifCourse: (map['tarif_course'] as num?)?.round() ?? 0,
        actif: (map['actif'] as bool?) ?? true,
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'nom': nom,
        'telephone_237': telephone,
        'zone': zone,
        'profil_id': profilId,
        'photo': photo,
        'moto': moto,
        'plaque': plaque,
        'tarif_course': tarifCourse,
        'actif': actif,
      };

  Livreur copieAvec({
    String? nom,
    String? telephone,
    String? zone,
    String? photo,
    String? moto,
    String? plaque,
    int? tarifCourse,
    bool? actif,
  }) =>
      Livreur(
        id: id,
        nom: nom ?? this.nom,
        telephone: telephone ?? this.telephone,
        zone: zone ?? this.zone,
        profilId: profilId,
        photo: photo ?? this.photo,
        moto: moto ?? this.moto,
        plaque: plaque ?? this.plaque,
        tarifCourse: tarifCourse ?? this.tarifCourse,
        actif: actif ?? this.actif,
      );
}

/// Une course telle que le livreur la voit.
///
/// Ligne de `mboa.mes_courses()` : la commande, son contenu et ce qu'il faut
/// encaisser. Jamais le cout d'achat du comptoir, jamais le telephone de la
/// cliente en clair : le moto a besoin de savoir quoi porter, ou aller et
/// combien demander a la porte, rien de plus.
class CourseLivreur {
  const CourseLivreur({
    required this.id,
    required this.statut,
    required this.montantTotal,
    required this.createdLe,
    this.livreeLe,
    this.clienteNom = '',
    this.clienteVillage = '',
    this.clienteTelephone,
    this.lignes = const [],
  });

  final String id;
  final StatutCommande statut;

  /// Marchandise seule. La course se paie a part, directement au moto.
  final int montantTotal;

  final DateTime createdLe;
  final DateTime? livreeLe;
  final String clienteNom;
  final String clienteVillage;

  /// Sort de `mboa.mes_courses`, seulement pour une course affectee a ce
  /// livreur : un moto ne trouve pas une concession au fond d'un quartier
  /// avec un nom de village.
  final String? clienteTelephone;

  final List<LigneCommande> lignes;

  /// La course est en route : c'est le moment de poser `en_approche`.
  bool get enRoute => statut == StatutCommande.enLivraison;

  /// Le panier est pret au comptoir, la moto peut charger.
  bool get aCharger => statut == StatutCommande.valideeAdmin;

  String get clienteLabel {
    final nom = clienteNom.trim();
    final base = nom.isEmpty ? 'La cliente' : nom;
    final village = clienteVillage.trim();
    return village.isEmpty ? base : '$base, $village';
  }

  String get resumeProduits =>
      lignes.isEmpty ? 'Rien à porter' : lignes.map((l) => l.nom).join(', ');

  String get resumeQuantites => resumerQuantites(lignes);

  /// Ce que la voix dit quand le livreur ouvre la course.
  String get annonce =>
      '${clienteLabel}. ${resumeQuantites}. À encaisser ${montantTotal} francs.';

  /// Reconstruction depuis le cache local, qui ne connaît pas le nom de la
  /// cliente : la carte montre alors « La cliente ».
  factory CourseLivreur.depuisCommande(Commande commande) => CourseLivreur(
        id: commande.id,
        statut: commande.statut,
        montantTotal: commande.montantTotal,
        createdLe: commande.createdLe,
        livreeLe: commande.livreeLe,
        lignes: commande.lignes,
      );

  factory CourseLivreur.fromMap(Map<String, dynamic> map) {
    final brut = map['produits'];
    final List<dynamic> tableau = switch (brut) {
      final List<dynamic> l => l,
      final String s when s.trim().isNotEmpty =>
        (jsonDecode(s) as List<dynamic>),
      _ => const <dynamic>[],
    };

    return CourseLivreur(
      id: map['id'] as String,
      statut: StatutCommande.resolve(map['statut_enum'] as String?),
      montantTotal: (map['montant_total'] as num?)?.round() ?? 0,
      createdLe:
          DateTime.tryParse(map['created_at'] as String? ?? '') ??
              DateTime.fromMillisecondsSinceEpoch(0),
      livreeLe: DateTime.tryParse(map['livree_le'] as String? ?? ''),
      clienteNom: (map['cliente_nom'] as String?) ?? '',
      clienteVillage: (map['cliente_village'] as String?) ?? '',
      clienteTelephone: map['cliente_tel'] as String?,
      lignes: tableau
          .whereType<Map<String, dynamic>>()
          .map(LigneCommande.fromJson)
          .toList(growable: false),
    );
  }
}
