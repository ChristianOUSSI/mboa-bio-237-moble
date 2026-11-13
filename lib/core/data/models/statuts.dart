/// Etats partages entre les trois apps et la base.
///
/// Les valeurs de [slug] sont celles des enums Postgres. Un renommage ici
/// sans migration SQL cachee provoque une erreur `invalid input value for
/// enum` seulement a l'ecriture : les lectures, elles, renverraient
/// silencieusement une valeur de repli. C'est pour ca que
/// `tool/verifier_sql.mjs` compare les deux vocabulaires a chaque execution.
library;

/// Colonne `public.commandes.statut_enum` : la timeline a 4 icones.
///
/// Le cinquieme etat, `recue`, n'ajoute pas une icone a la timeline. Il
/// ferme la quatrieme : la main qui donne devient pleine et verte. Cinq
/// jalons sur un ecran de cinq pouces ne se lisent plus, et la confirmation
/// n'est pas une etape du parcours, c'est sa fin.
///
/// `annulee` est le sixieme, et il ne se dessine pas sur la timeline : un
/// devis annule n'est pas une etape franchie, c'est un papier qui n'existe
/// plus. Il porte neanmoins une donnee qu'aucun autre etat ne porte, la
/// raison du retour de marchandise au stock.
enum StatutCommande {
  nouvelle('nouvelle', 'Nouvelle'),
  valideeAdmin('validee_admin', 'Validée'),
  enLivraison('en_livraison', 'En route'),
  livree('livree', 'Livrée'),
  recue('recue', 'Reçue'),
  annulee('annulee', 'Annulée');

  const StatutCommande(this.slug, this.libelle);

  final String slug;
  final String libelle;

  /// Position absolue dans le parcours, 0 a 5.
  int get rang => index;

  /// Position sur la timeline a quatre icones. `recue` allume la meme case
  /// que `livree`, mais la ferme ; `annulee` n'en allume aucune.
  int get jalon => index.clamp(0, 3);

  bool get attendConfirmation => this == StatutCommande.livree;

  bool get estTerminee => this == StatutCommande.recue;

  /// Le devis ne peut plus avancer : soit il est solde, soit il est mort.
  bool get estFermee => this == StatutCommande.recue || this == StatutCommande.annulee;

  /// Ce qui reste a faire, dans l'ordre des priorites de la journee.
  String get actionRestante => switch (this) {
        StatutCommande.nouvelle => 'Mboa doit valider',
        StatutCommande.valideeAdmin => 'La moto doit partir',
        StatutCommande.enLivraison => 'La moto est en route',
        StatutCommande.livree => 'Dis si tout est bon',
        StatutCommande.recue => 'C’est fini',
        StatutCommande.annulee => 'La marchandise est revenue',
      };

  /// Phrase prononcee quand l'etat change, cote cliente.
  ///
  /// Celle de `livree` est la plus importante de toute l'app : c'est le
  /// message court qui declenche la confirmation. Une phrase, un point
  /// d'interrogation, deux boutons apres.
  String get annonce => switch (this) {
        StatutCommande.nouvelle => 'Devis enregistré',
        StatutCommande.valideeAdmin => 'Mboa a validé votre devis, la marchandise est réservée',
        StatutCommande.enLivraison => 'La moto est en route',
        StatutCommande.livree => 'Ta commande est arrivée. Tout est bon ?',
        StatutCommande.recue => 'Merci, c’est noté',
        StatutCommande.annulee => 'Votre devis a été annulé',
      };

  static StatutCommande resolve(String? slug) => values.firstWhere(
        (s) => s.slug == slug,
        orElse: () => StatutCommande.nouvelle,
      );
}

/// Colonne `public.commandes.paiement`.
///
/// `especes` est premier et par defaut : on ne paie plus dans l'app, on paie
/// a la porte, devant la marchandise. Les deux modes mobiles restent declares
/// pour le jour ou un contrat d'agregation sera signe, mais ils ne sont
/// proposes nulle part dans le parcours.
enum ModePaiement {
  especes('especes', 'Espèces à la livraison', null),
  momo('mtn_momo', 'MTN MoMo', 'assets/pictos/momo.svg'),
  orangeMoney('orange_money', 'Orange Money', 'assets/pictos/orange-money.svg');

  const ModePaiement(this.slug, this.libelle, this.marque);

  final String slug;
  final String libelle;

  /// Marque de remplacement, pas le logo officiel de l'operateur. Null pour
  /// les especes : il n'y a rien a marquer.
  final String? marque;

  /// Seuls les modes a proposer a l'ecran. Aujourd'hui : un seul.
  bool get estPropose => this == ModePaiement.especes;

  static ModePaiement resolve(String? slug) => values.firstWhere(
        (p) => p.slug == slug,
        orElse: () => ModePaiement.especes,
      );
}

/// Reponse unique de la cliente apres la livraison.
///
/// Binaire par decision, pas par paresse : une echelle a cinq niveaux est
/// illegible pour qui ne lit pas, et le choix du milieu devient le defaut de
/// quelqu'un qui ne veut pas deranger. La donnee utile est donc « accepté »
/// ou « probleme », et le probleme s'explique ailleurs.
///
/// Les pictogrammes qui les representent sont declares dans
/// `core/design_system/picto.dart` : un modele de donnees ne doit rien a la
/// bibliotheque de widgets.
enum Satisfaction {
  bon('bon', 'Tout est bon'),
  probleme('probleme', 'Il y a un problème');

  const Satisfaction(this.slug, this.libelle);

  final String slug;
  final String libelle;

  bool get estBon => this == Satisfaction.bon;

  /// Ce que la voix dit au comptoir quand la cliente a repondu.
  String get annonceAuComptoir => switch (this) {
        Satisfaction.bon => 'La cliente a accepté sa marchandise',
        Satisfaction.probleme => 'La cliente signale un problème',
      };

  static Satisfaction? parse(String? slug) {
    for (final s in values) {
      if (s.slug == slug) return s;
    }
    return null;
  }
}

/// Les trois motifs de refus proposes a la cliente.
///
/// Pas de champ libre : trois choix dessinés, puis la possibilité de le dire
/// a voix haute si les trois ne suffisent pas.
enum MotifReception {
  rienRecu('rien_recu', 'Rien n’est arrivé'),
  quantite('quantite', 'Ce n’est pas la bonne quantité'),
  abime('abime', 'Le produit est abîmé');

  const MotifReception(this.slug, this.libelle);

  final String slug;
  final String libelle;
}
