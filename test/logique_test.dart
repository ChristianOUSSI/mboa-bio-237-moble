import 'package:flutter_test/flutter_test.dart';

import 'package:mboa_bio/core/config/app_role.dart';
import 'package:mboa_bio/core/data/depot_auth.dart' show normaliserTelephone;
import 'package:mboa_bio/core/data/models/categorie.dart';
import 'package:mboa_bio/core/data/models/commande.dart';
import 'package:mboa_bio/core/data/models/langue.dart';
import 'package:mboa_bio/core/data/models/livreur.dart';
import 'package:mboa_bio/core/data/models/liste.dart';
import 'package:mboa_bio/core/data/models/pack_composant.dart';
import 'package:mboa_bio/core/data/models/produit.dart';
import 'package:mboa_bio/core/data/models/statuts.dart';
import 'package:mboa_bio/core/data/models/unite.dart';
import 'package:mboa_bio/core/utils/format_monnaie.dart';
import 'package:mboa_bio/core/utils/identifiants.dart';

/// Les regles qui n'ont besoin ni d'ecran ni de serveur.
///
/// Ces tests sont les seuls du projet a tourner sans emulator : ils couvrent
/// la monnaie, les numeros camerounais, les unites du marche, la marge du
/// comptoir et la machine a etats du devis. Ce sont exactement les endroits
/// ou une erreur se voit le plus tard, chez la cliente.
void main() {
  group('normaliserTelephone', () {
    test('accepte les formes saisies sur un clavier de telephone', () {
      expect(normaliserTelephone('699123456'), '+237699123456');
      expect(normaliserTelephone('6 99 12 34 56'), '+237699123456');
      expect(normaliserTelephone('+237 699 123 456'), '+237699123456');
      expect(normaliserTelephone('237699123456'), '+237699123456');
      expect(normaliserTelephone('0233112233'), '+237233112233');
      expect(normaliserTelephone('694556677'), '+237694556677');
    });

    test('refuse ce qui ne peut pas etre un numero du Cameroun', () {
      expect(normaliserTelephone(''), isNull);
      expect(normaliserTelephone('12345'), isNull);
      expect(normaliserTelephone('799123456'), isNull);
      expect(normaliserTelephone('399123456'), isNull);
      expect(normaliserTelephone('6991234567890'), isNull);
    });
  });

  group('formaterFcfa', () {
    test('groupe les milliers par trois avec une espace insecable', () {
      expect(formaterFcfa(0), '0 FCFA');
      expect(formaterFcfa(999), '999 FCFA');
      expect(formaterFcfa(1000), '1${String.fromCharCode(0x00A0)}000 FCFA');
      expect(formaterFcfa(1250), '1${String.fromCharCode(0x00A0)}250 FCFA');
      expect(formaterFcfa(1000000),
          '1${String.fromCharCode(0x00A0)}000${String.fromCharCode(0x00A0)}000 FCFA');
    });

    test('rend le signe moins, pour une ligne de marge', () {
      expect(formaterFcfa(-120), '-120 FCFA');
    });

    test('la forme courte tient dans une tuile', () {
      expect(formaterFcfaCourt(350), '350 F');
    });
  });

  group('formaterKg', () {
    test('dit 2 et pas 2,0', () {
      expect(formaterKg(2.0), '2');
      expect(formaterKg(2.5), '2,5');
      expect(formaterKg(0.5), '0,5');
    });

    test('la voix d un nombre isole reste un nombre', () {
      expect(formaterKg(120), '120');
    });
  });

  group('Unite', () {
    test('le marche ne compte pas tout au kilo', () {
      expect(Unite.boule.avec(3), '3 boules');
      expect(Unite.boule.avec(1), '1 boule');
      expect(Unite.part.pour(12), 'parts');
      expect(Unite.morceau.avecArticle, 'le morceau');
      expect(Unite.kg.avecArticle, 'le kilo');
    });

    test('les onze mesures du catalogue sont celles du SQL', () {
      // Miroir de `public.unite_enum` : un ajout d'un cote sans l'autre
      // produit une erreur d'ecriture seulement, jamais une erreur de lecture.
      expect(Unite.values.map((u) => u.slug).toList(), [
        'kg', 'boule', 'bouteille', 'botte', 'morceau', 'part',
        'litre', 'paquet', 'plateau', 'regime', 'sachet',
      ]);
    });

    test('les mesures du devis papier existent', () {
      expect(Unite.litre.avec(5), '5 litres');
      expect(Unite.litre.avecArticle, 'le litre');
      expect(Unite.paquet.pour(1), 'paquet');
      expect(Unite.plateau.pour(2), 'plateaux');
      expect(Unite.regime.avec(2), '2 régimes');
      expect(Unite.sachet.avecArticle, 'le sachet');
      expect(Unite.litre.estPoids, false);
    });

    test('un slug inconnu retombe sur le kilo, jamais sur du vide', () {
      expect(Unite.resolve('petrole'), Unite.kg);
      expect(Unite.resolve(null), Unite.kg);
    });
  });

  group('Pack', () {
    LigneCommande partDePack() => const LigneCommande(
          produitId: 'pack1',
          slug: 'pack_ndole',
          nom: 'Pack Ndolè',
          categorie: Categorie.legume,
          quantite: 2,
          prix: 2500,
          photo: 'pack.jpg',
          composants: [
            PackComposant(slug: 'ndole', nom: 'Ndolè', quantite: 3, unite: Unite.botte),
            PackComposant(slug: 'crevette', nom: 'Crevettes', quantite: 1, unite: Unite.litre),
          ],
        );

    test('une part se nomme, se compte et se regle a la part', () {
      final ligne = partDePack();
      expect(ligne.estPack, true);
      expect(ligne.estLibre, false);
      expect(ligne.libelle, 'Pack Ndolè');
      expect(ligne.quantiteAffichee, '2 parts');
      expect(ligne.pas, 1);
      expect(ligne.sousTotal, 5000);
    });

    test('le gel de la recette survit a la relecture du JSON', () {
      final relu = LigneCommande.fromJson(partDePack().toJson());
      expect(relu.composants.length, 2);
      expect(relu.composants.first.unite, Unite.botte);

      // Un ingredient rebaptise dans le catalogue ne doit pas changer ce que
      // dit une vieille commande : le nom gele fait foi.
      final gele = PackComposant.fromJson({
        'slug': 'ndole',
        'nom': 'Ndolè du village',
        'quantite': 3,
        'unite': 'botte',
      });
      expect(gele.libelle, 'Ndolè du village');
      expect(gele.annonce, '3 bottes de Ndolè du village');
    });

    test('un panier mele ne somme jamais deux unites', () {
      const papaye = LigneCommande(
        produitId: 'p1',
        slug: 'papaye',
        nom: 'Papaye',
        categorie: Categorie.fruit,
        quantite: 5,
        prix: 300,
        photo: 'p.jpg',
      );
      expect(resumerQuantites([papaye, partDePack()]), '5 kilos · 2 parts');
    });
  });

  group('Ligne libre', () {
    // Le miondo n'est pas une reference du stock. Un devis de marche sans ces
    // lignes n'est pas un devis de marche.
    LigneCommande miondo({double quantite = 5, Unite? unite}) => LigneCommande(
          produitId: 'libre-1',
          nom: 'Miondo',
          categorie: Categorie.cereale,
          unite: unite,
          quantite: quantite,
          prix: 700,
          photo: '',
        );

    test('elle se nomme elle-meme, jamais la valeur de repli du catalogue', () {
      final ligne = miondo(unite: Unite.paquet);
      expect(ligne.estLibre, true);
      expect(ligne.estPack, false);
      expect(ligne.libelle, 'Miondo');
      expect(ligne.quantiteAffichee, '5 paquets');
      expect(ligne.annonce, '5 paquets de Miondo');
    });

    test('sans unite posee, elle se compte en pieces et non en kilos', () {
      // Une ligne dictee n'a pas de fiche dont heriter l'unite : vendre le
      // miondo au kilo serait une erreur que la cliente paie a la porte.
      expect(miondo(unite: null).uniteReelle, Unite.morceau);
      expect(miondo(unite: Unite.paquet).uniteReelle, Unite.paquet);
    });

    test('son pas est la piece', () {
      expect(miondo().pas, 1);
    });

    test('le nom dicte survit au JSON', () {
      final relu = LigneCommande.fromJson(miondo(unite: Unite.paquet).toJson());
      expect(relu.nom, 'Miondo');
      expect(relu.estLibre, true);
      expect(relu.sousTotal, 3500);
    });

    test('un panier mele ligne libre et produit du stock', () {
      const papaye = LigneCommande(
        produitId: 'p1',
        slug: 'papaye',
        nom: 'Papaye',
        categorie: Categorie.fruit,
        quantite: 2,
        prix: 300,
        photo: 'p.jpg',
      );
      final commande = Commande(
        id: 'c1',
        consommateurId: 'u1',
        lignes: [papaye, miondo(unite: Unite.paquet)],
        statut: StatutCommande.nouvelle,
        montantTotal: 600 + 3500,
        createdLe: DateTime(2026, 11, 6),
      );
      expect(commande.resumeQuantites, '2 kilos · 5 paquets');
      expect(commande.resumeProduits, 'Papaye, Miondo');
    });
  });

  group('Le devis', () {
    ListeMarche devis({int tarif = 500}) => ListeMarche(
          id: 'l1',
          consommateurId: 'c1',
          lignes: const [
            LigneCommande(
              produitId: 'p1',
              slug: 'papaye',
              nom: 'Papaye',
              categorie: Categorie.fruit,
              quantite: 2,
              prix: 300,
              photo: 'p.jpg',
            ),
            LigneCommande(
              produitId: 'libre-1',
              nom: 'Miondo',
              categorie: Categorie.cereale,
              unite: Unite.paquet,
              quantite: 5,
              prix: 700,
              photo: '',
            ),
          ],
          code: 'hkmpq23',
          titre: 'Ma liste',
          createdLe: DateTime(2026, 11, 6),
          livreurNom: tarif == 0 ? null : 'Ibrahim',
          livreurTarif: tarif == 0 ? null : tarif,
        );

    test('la marchandise et la course ne sortent pas de la meme poche', () {
      final liste = devis();
      expect(liste.montantEstime, 4100);
      expect(liste.montantAPayer, 4600);
    });

    test('sans moto affectee, le devis n invente pas de frais', () {
      final liste = devis(tarif: 0);
      expect(liste.aUnLivreur, false);
      expect(liste.montantAPayer, liste.montantEstime);
    });

    test('le total du papier est la somme des lignes du tableau', () {
      // Le devis est le papier qui fait foi : si le bandeau du bas ne tombe
      // pas sur la somme des totaux de ligne, la mama paie mal a la porte.
      final liste = devis();
      final somme = liste.lignes.fold<int>(0, (t, l) => t + l.sousTotal);
      expect(liste.montantAPayer, somme + (liste.livreurTarif ?? 0));
    });
  });

  group('Livreur', () {
    Livreur un({String? plaque, String? moto}) => Livreur(
          id: 'l1',
          nom: 'Ibrahim',
          telephone: '+237677555112',
          zone: 'Bafoussam',
          plaque: plaque,
          moto: moto,
          tarifCourse: 500,
        );

    test('la plaque est le premier repere, la moto le second', () {
      expect(un(plaque: 'AB 2145 CM', moto: 'Sanble bleue').repere, 'AB 2145 CM');
      expect(un(moto: 'Sanble bleue').repere, 'Sanble bleue');
      expect(un().repere, 'Ibrahim');
    });

    test('la voix dit qui vient, sur quoi, et ce que coute la course', () {
      final texte = un(plaque: 'AB 2145 CM').annonce;
      expect(texte, contains('Ibrahim'));
      expect(texte, contains('Bafoussam'));
      expect(texte, contains('plaque AB 2145 CM'));
      expect(texte, contains('500 francs'));
    });

    test('une fiche inactive garde son nom pour les courses passees', () {
      final retire = un(plaque: 'AB 2145 CM').copieAvec(actif: false);
      expect(retire.actif, false);
      expect(retire.repere, 'AB 2145 CM');
    });
  });

  group('Categorie', () {
    test('huit cases, dans l ordre de la grille', () {
      expect(Categorie.values.map((c) => c.slug).toList(), [
        'fruit', 'tubercule', 'legume', 'cereale',
        'viande', 'poisson', 'huile', 'boisson',
      ]);
      expect(Categorie.values.map((c) => c.ordre).toList(), [1, 2, 3, 4, 5, 6, 7, 8]);
    });

    test('chaque case a son dessin, et le dessin porte son nom', () {
      for (final categorie in Categorie.values) {
        expect(categorie.picto, categorie.slug);
        expect(categorie.asset, 'assets/pictos/${categorie.slug}.svg');
        expect(categorie.libelle, isNotEmpty);
        expect(categorie.libelleVoice, isNotEmpty);
      }
    });

    test('le perissable est une nature, pas une humeur du jour', () {
      expect(Categorie.viande.perissable, isTrue);
      expect(Categorie.poisson.perissable, isTrue);
      expect(Categorie.huile.perissable, isFalse);
      expect(Categorie.cereale.perissable, isFalse);
    });

    test('un slug inconnu ne vide jamais la grille', () {
      expect(Categorie.resolve('epices'), Categorie.fruit);
      expect(Categorie.resolve(null), Categorie.fruit);
    });
  });

  group('Produit du stock', () {
    Produit construire({
      double quantite = 20,
      int prix = 150,
      int? prixAchat,
      bool perissable = true,
      bool actif = true,
      List<PackComposant> composants = const [],
    }) =>
        Produit(
          id: 'p1',
          slug: 'manioc',
          nom: 'Manioc',
          categorie: Categorie.tubercule,
          photoReelle: 'produits/manioc.jpg',
          quantite: quantite,
          prix: prix,
          prixAchat: prixAchat,
          perissable: perissable,
          actif: actif,
          composants: composants,
        );

    test('la jauge ne depasse jamais 1 et suit l unite', () {
      expect(construire(quantite: 120).jauge, 1.0);
      expect(construire(quantite: 10).jauge, 0.5);
      expect(construire(quantite: 0).jauge, 0.0);
      // Le riz se garde : son echelle est plus large que celle de la tomate.
      expect(construire(quantite: 60, perissable: false).jauge, 0.5);
    });

    test('un produit vide ou retire sort de la vitrine', () {
      expect(construire(quantite: 0).estVitrine, isFalse);
      expect(construire(quantite: 5).estVitrine, isTrue);
      expect(construire(actif: false).estVitrine, isFalse);
    });

    test('le montant est arrondi au franc', () {
      expect(construire().montantPour(2.5), 375);
    });

    test('l annonce vocale ne nomme jamais un producteur', () {
      final texte = construire(quantite: 12).annonceVocale;
      expect(texte, contains('Manioc'));
      expect(texte, contains('12 kilos'));
      expect(texte, contains('150 francs'));
      expect(texte, isNot(contains('Papa')));
    });

    test('la marge ne se lit que sur un produit deja achete', () {
      expect(construire(prixAchat: null).margeUnitaire, isNull);
      expect(construire(prixAchat: 100).margeUnitaire, 50);
      expect(construire(prixAchat: 100).margePct, 50);
      expect(construire(prixAchat: 200).estAPerte, isTrue);
    });

    test('la photo filigranee passe avant l originale', () {
      final produit = construire().copieAvec(photoFiligranee: 'x_marque.jpg');
      expect(produit.photo, 'x_marque.jpg');
    });

    test('un pack se compte en parts, quoi qu on saisisse', () {
      final pack = construire(
        composants: const [
          PackComposant(slug: 'ndole', quantite: 3, unite: Unite.botte),
        ],
      );
      expect(pack.estPack, isTrue);
      expect(pack.uniteReelle, Unite.part);
      expect(pack.jauge, 1.0);
    });
  });

  group('Commande', () {
    LigneCommande ligne(String id, double quantite, int prix) => LigneCommande(
          produitId: id,
          slug: 'papaye',
          nom: 'Papaye',
          categorie: Categorie.fruit,
          quantite: quantite,
          prix: prix,
          photo: 'p.jpg',
        );

    test('le panier se lit depuis un JSONB decode ou brut', () {
      final map = {
        'id': 'c1',
        'consommateur_id': 'u1',
        'statut_enum': 'nouvelle',
        'montant_total': 600,
        'created_at': '2026-11-05T10:00:00Z',
        'produits': [ligne('p1', 2, 300).toJson()],
      };

      final depuisTableau = Commande.fromMap(map);
      expect(depuisTableau.lignes.length, 1);
      expect(depuisTableau.resumeQuantites, '2 kilos');

      final depuisChaine = Commande.fromMap({
        ...map,
        'produits': '[{"produit_id":"p1","quantite":2,"prix":300}]',
      });
      expect(depuisChaine.lignes.length, 1);
    });

    test('une ligne sans fournisseur ne casse pas la lecture', () {
      final commande = Commande.fromMap({
        'id': 'c2',
        'produits': '[]',
        'statut_enum': 'inconnu_dans_enum',
      });
      expect(commande.statut, StatutCommande.nouvelle);
      expect(commande.lignes, isEmpty);
    });

    test('l annonce de commande est une phrase complete', () {
      final commande = Commande(
        id: 'c3',
        consommateurId: 'u1',
        lignes: [ligne('p1', 5, 150)],
        statut: StatutCommande.nouvelle,
        montantTotal: 750,
        createdLe: DateTime(2026, 11, 5),
      );
      expect(commande.annonceVocale, contains('5 kilos'));
      expect(commande.annonceVocale, contains('Papaye'));
    });
  });

  group('Statuts', () {
    test('six etats, quatre jalons', () {
      expect(
        StatutCommande.values.map((s) => s.slug).toList(),
        ['nouvelle', 'validee_admin', 'en_livraison', 'livree', 'recue', 'annulee'],
      );
      expect(StatutCommande.values.map((s) => s.rang).toList(), [0, 1, 2, 3, 4, 5]);

      // La confirmation ne dessine pas une cinquieme icone : elle ferme la
      // quatrieme. Sans ce clamp, la timeline deborderait de l'ecran.
      expect(StatutCommande.values.map((s) => s.jalon).toList(), [0, 1, 2, 3, 3, 3]);
    });

    test('seule la livraison pointee attend un pouce', () {
      expect(StatutCommande.livree.attendConfirmation, isTrue);
      expect(StatutCommande.enLivraison.attendConfirmation, isFalse);
      expect(StatutCommande.recue.estTerminee, isTrue);
      expect(StatutCommande.annulee.estFermee, isTrue);
    });

    test('le message de confirmation est une phrase courte', () {
      final texte = StatutCommande.livree.annonce;
      expect(texte, 'Ta commande est arrivée. Tout est bon ?');
      expect(texte.length, lessThan(60), reason: 'une phrase, pas un paragraphe');
    });

    test('les slugs sont exactement ceux des enums SQL', () {
      expect(ModePaiement.values.map((p) => p.slug).toList(),
          ['especes', 'mtn_momo', 'orange_money']);
    });

    test('le paiement par defaut est l espece a la porte', () {
      expect(ModePaiement.values.first, ModePaiement.especes);
      expect(ModePaiement.resolve('mtn_momo'), ModePaiement.momo);
      // Un mode inconnu ne doit jamais retomber sur un paiement mobile :
      // la regle est l'espece, et une faute de frappe ne change pas de loi.
      expect(ModePaiement.resolve('paypal'), ModePaiement.especes);
      expect(ModePaiement.especes.estPropose, isTrue);
      expect(ModePaiement.momo.estPropose, isFalse);
    });

    test('la satisfaction est binaire, et le probleme s explique par trois motifs', () {
      expect(Satisfaction.values.length, 2);
      expect(Satisfaction.bon.estBon, isTrue);
      expect(Satisfaction.probleme.estBon, isFalse);
      expect(Satisfaction.parse('inconnue'), isNull);
      expect(MotifReception.values.length, 3);
    });
  });

  group('Commande : la verite financiere est celle de la porte', () {
    LigneCommande ligne(String id, double quantite, int prix) => LigneCommande(
          produitId: id,
          slug: 'manioc',
          nom: 'Manioc',
          categorie: Categorie.tubercule,
          quantite: quantite,
          prix: prix,
          photo: 'p.jpg',
        );

    Commande construire({
      int total = 1000,
      int cout = 600,
      int? livre,
      bool clos = false,
      StatutCommande statut = StatutCommande.nouvelle,
      DateTime? livreeLe,
    }) =>
        Commande(
          id: 'c1',
          consommateurId: 'u1',
          lignes: [ligne('p1', 5, 200)],
          statut: statut,
          montantTotal: total,
          coutAchat: cout,
          montantLivre: livre,
          livreeLe: livreeLe,
          clos: clos,
          createdLe: DateTime(2026, 11, 5),
        );

    test('aucune marge tant que la cliente n a pas solde', () {
      expect(construire(livre: 1000).marge, 0);
      expect(construire(livre: 1000, clos: true).montantDue, 1000);
      expect(construire(livre: 1000, clos: true).marge, 400);
    });

    test('le montant livre suit l argent reel, pas le papier', () {
      final gardeMoitie = construire(livre: 600, clos: true);
      expect(gardeMoitie.ecart, 400);
      expect(gardeMoitie.ecartSignificatif, isTrue);

      final integral = construire(livre: 1000, clos: true);
      expect(integral.ecart, 0);
      expect(integral.ecartSignificatif, isFalse);
    });

    test('la marge se proroge sur ce qui a ete garde', () {
      // Un panier a moitie refuse ne doit pas afficher une marge negative sur
      // une vente normale : seul le cout de la part gardee compte.
      final moitie = construire(livre: 500, clos: true);
      expect(moitie.coutGarde, 300);
      expect(moitie.marge, 200);
    });

    test('une commande sans montant livre ne calcule aucun ecart', () {
      expect(construire().ecart, 0);
      expect(construire().montantLivre, isNull);
    });

    test('la relance se declenche douze heures apres le pointage', () {
      final fraiche = construire(
        livre: 1000,
        statut: StatutCommande.livree,
        livreeLe: DateTime.now().subtract(const Duration(hours: 3)),
      );
      final attenue = construire(
        livre: 1000,
        statut: StatutCommande.livree,
        livreeLe: DateTime.now().subtract(const Duration(hours: 13)),
      );

      expect(fraiche.attendConfirmation, isTrue);
      expect(fraiche.preteARelance, isFalse);
      expect(attenue.preteARelance, isTrue);
    });

    test('le message de confirmation tient en une phrase', () {
      expect(construire().messageConfirmation, 'Ta commande est arrivée. Tout est bon ?');
    });
  });

  group('Code de liste', () {
    test('sept caracteres, tous dictables au telephone', () {
      final code = CodeListe.generer();
      expect(code.length, 7);
      expect(CodeListe.estValide(code), isTrue);

      // Les caracteres qui se confondent a l'oral sont exclus de l'alphabet.
      for (final interdits in ['o', 'i', 'l', '0', '1', '5', '9', 'u', 'v', 'b', 'd']) {
        expect(code.contains(interdits), isFalse, reason: 'interdit: $interdits');
      }
    });

    test('deux codes differents', () {
      expect(CodeListe.generer(), isNot(CodeListe.generer()));
    });

    test('le code se dicte caractere par caractere', () {
      final liste = ListeMarche(
        id: 'l1',
        consommateurId: 'u1',
        lignes: const [
          LigneCommande(
            produitId: 'p1',
            slug: 'papaye',
            nom: 'Papaye',
            categorie: Categorie.fruit,
            quantite: 2,
            prix: 300,
            photo: 'x',
          ),
        ],
        code: 'hkmpq23',
        titre: 'Ma liste',
        createdLe: DateTime(2026, 11, 5),
      );

      expect(liste.codeDicte, 'h, k, m, p, q, 2, 3');
      expect(liste.montantEstime, 600);
      expect(liste.annonceVocale, contains('hkmpq23'));
      expect(liste.estTransformee, isFalse);
    });
  });

  group('Identifiants', () {
    test('un uuid v4 bien forme et unique', () {
      final a = Identifiants.uuidV4();
      final b = Identifiants.uuidV4();
      expect(a, isNot(b));
      expect(a.length, 36);
      expect(a[14], '4', reason: 'version 4');
      expect(RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$')
          .hasMatch(a), isTrue);
    });
  });

  group('Roles et langues', () {
    test('quatre flavors, quatre noms d app', () {
      expect(AppRole.values.length, 4);
      expect(AppRole.fournisseur.appName, 'MBOA FOURNISSEUR');
      expect(AppRole.admin.appName, 'MBOA ADMIN');
      expect(AppRole.consommateur.appName, 'MBOA BIO 237');
      expect(AppRole.livreur.appName, 'MBOA LIVREUR');
    });

    test('un slug de role inconnu retombe sur l app cliente', () {
      expect(AppRole.resolve('superadmin'), AppRole.consommateur);
      expect(AppRole.resolve(null), AppRole.consommateur);
    });

    test('bassa et bamoun passent par la voix francaise', () {
      expect(Langue.bassa.ttsNative, isFalse);
      expect(Langue.bamoun.ttsNative, isFalse);
      expect(Langue.fr.ttsNative, isTrue);
      expect(Langue.pidgin.codeTts, 'en-US');
    });
  });
}
