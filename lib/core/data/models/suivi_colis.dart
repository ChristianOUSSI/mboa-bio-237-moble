
/// Les cinq etapes du suivi de colis, dans l'ordre du voyage.
///
/// Le suivi se lit comme un journal de bord, pas comme un flux GPS. Chaque
/// jalon porte un horodatage et un auteur, et c'est tout ce que la cliente,
/// l'admin et le livreur ont besoin de voir.
///
/// Trois jalons sont poses automatiquement par le trigger SQL quand le statut
/// de la commande change : [panierPrepare], [motoPartie] et [arrive]. Les
/// deux autres, [enApproche] et [remis], sont poses par l'admin (pour le
/// premier) et par la cliente (pour le second, via sa confirmation).
///
/// L'ordre est ferme : on ne peut pas pointer [enApproche] avant que la moto
/// soit partie, et l'RPC serveur le refuse.
enum JalonSuivi {
  panierPrepare('panier_prepare', 'Panier prepare', 'Le comptoir a sorti et empaquete la marchandise'),
  motoPartie('moto_partie', 'La moto est partie', 'Le livreur a charge et quitte le depot'),
  enApproche('en_approche', 'Le livreur approche', 'Il est proche, vous pouvez vous preparer'),
  arrive('arrive', 'Arrive chez vous', 'La moto est devant votre porte'),
  remis('remis', 'Remis en main propre', 'Vous avez confirme la reception');

  const JalonSuivi(this.slug, this.libelle, this.description);

  final String slug;
  final String libelle;
  final String description;

  /// La position dans le voyage, de 0 a 4.
  int get rang => index;

  /// La phrase prononcee par le TTS quand ce jalon est pose.
  String get annonce => libelle;

  /// Vrai si ce jalon est pose automatiquement par le trigger SQL.
  bool get estAutomatique =>
      this == JalonSuivi.panierPrepare ||
      this == JalonSuivi.motoPartie ||
      this == JalonSuivi.arrive ||
      this == JalonSuivi.remis;

  static JalonSuivi resolve(String? slug) => values.firstWhere(
        (j) => j.slug == slug,
        orElse: () => JalonSuivi.panierPrepare,
      );
}

/// Une ligne du journal de bord : un jalon, son horodatage, et qui l'a pose.
///
/// La table `suivi_colis` porte une ligne par couple commande + jalon. Cette
/// classe est sa contrepartie Dart, lue via l'RPC `mboa.suivi_commande`.
class EtapeSuivi {
  const EtapeSuivi({
    required this.jalon,
    required this.horodatage,
    required this.auteur,
  });

  final JalonSuivi jalon;
  final DateTime horodatage;
  final String auteur;

  factory EtapeSuivi.fromMap(Map<String, dynamic> map) => EtapeSuivi(
        jalon: JalonSuivi.resolve(map['jalon'] as String?),
        horodatage: DateTime.tryParse(map['horodatage'] as String? ?? '') ?? DateTime.now(),
        auteur: (map['auteur'] ?? 'auto') as String,
      );
}

/// La timeline complete d'une commande : les jalons poses, dans l'ordre.
///
/// Cette classe reconstruit la timeline cote Dart : elle complete les jalons
/// manquants (pas encore poses) avec un horodatage null, pour que l'ecran de
/// suivi puisse dessiner les cinq etapes d'un coup, allumees ou eteintes.
class SuiviColis {
  const SuiviColis({required this.commandeId, required this.etapes});

  final String commandeId;
  final List<EtapeSuivi> etapes;

  /// Vrai si au moins une etape a ete posee.
  bool get nonVide => etapes.isNotEmpty;

  /// Le dernier jalon pose, ou null si rien n'a encore ete enregistre.
  EtapeSuivi? get derniereEtape =>
      etapes.isEmpty ? null : etapes.last;

  /// Le rang du dernier jalon pose, pour allumer la timeline.
  int get dernierRang => derniereEtape?.jalon.rang ?? -1;

  /// L'etape [enApproche] a-t-elle ete posee ?
  bool get enApproche =>
      etapes.any((e) => e.jalon == JalonSuivi.enApproche);

  /// L'etape [arrive] a-t-elle ete posee ?
  bool get arrive =>
      etapes.any((e) => e.jalon == JalonSuivi.arrive);

  /// L'etape [remis] a-t-elle ete posee ?
  bool get remis =>
      etapes.any((e) => e.jalon == JalonSuivi.remis);

  /// Construit la timeline complete, avec les jalons manquants inseres.
  ///
  /// Renvoie une liste de cinq elements, un par [JalonSuivi], dans l'ordre.
  /// Chaque element porte l'horodatage s'il a ete pose, ou null sinon.
  List<EtapeTimeline> get timeline {
    final parJalon = {for (final e in etapes) e.jalon: e};
    return [
      for (final jalon in JalonSuivi.values)
        EtapeTimeline(
          jalon: jalon,
          etape: parJalon[jalon],
        ),
    ];
  }

  factory SuiviColis.vide(String commandeId) =>
      SuiviColis(commandeId: commandeId, etapes: const []);

  factory SuiviColis.fromMaps(String commandeId, List<Map<String, dynamic>> maps) =>
      SuiviColis(
        commandeId: commandeId,
        etapes: maps.map(EtapeSuivi.fromMap).toList()
          ..sort((a, b) => a.horodatage.compareTo(b.horodatage)),
      );
}

/// Une etape de la timeline, posee ou non.
///
/// Si [etape] est non null, le jalon a ete pointe et porte un horodatage.
/// Sinon, il est encore en attente : la timeline le dessine eteint.
class EtapeTimeline {
  const EtapeTimeline({required this.jalon, this.etape});

  final JalonSuivi jalon;
  final EtapeSuivi? etape;

  bool get estPose => etape != null;
  DateTime? get horodatage => etape?.horodatage;
  String? get auteur => etape?.auteur;
}
