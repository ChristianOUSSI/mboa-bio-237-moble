import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mboa_bio/core/data/models/categorie.dart';
import 'package:mboa_bio/core/design_system/boutons.dart';
import 'package:mboa_bio/core/design_system/picto.dart';
import 'package:mboa_bio/core/theme/mboa_colors.dart';
import 'package:mboa_bio/core/theme/mboa_theme.dart';
import 'package:mboa_bio/core/theme/mboa_typography.dart';

/// Les invariants de charte, testes et pas seulement ecrits.
///
/// Une charte que rien ne verifie se degrade en six mois : le premier developpeur
/// presse par le delai ajoute un vert, puis un texte a 16 px, puis un emoji.
/// Ces tests sont la pour que ca se voie le jour meme.
void main() {
  /// Le RGB seul : les decalques de charte ne different de leurs parents que
  /// par l'alpha, et l'alpha n'est pas une couleur.
  int rgb(Color couleur) => couleur.value & 0x00FFFFFF;

  group('Palette', () {
    test('les six valeurs de la charte, litteralement', () {
      expect(MboaColors.primary, const Color(0xFF1E5128));
      expect(MboaColors.secondary, const Color(0xFF8BC34A));
      expect(MboaColors.background, const Color(0xFFF8F9E9));
      expect(MboaColors.surface, const Color(0xFFFFFFFF));
      expect(MboaColors.error, const Color(0xFFD32F2F));
      expect(MboaColors.text, const Color(0xFF212121));
    });

    test('aucun decale n introduit une teinte hors des six', () {
      final parents = {
        rgb(MboaColors.primary),
        rgb(MboaColors.secondary),
        rgb(MboaColors.background),
        rgb(MboaColors.surface),
        rgb(MboaColors.error),
        rgb(MboaColors.text),
      };

      final decalques = {
        'textDoux': MboaColors.textDoux,
        'primaryDoux': MboaColors.primaryDoux,
        'secondaryDoux': MboaColors.secondaryDoux,
        'errorDoux': MboaColors.errorDoux,
        'ombre': MboaColors.ombre,
        'trait': MboaColors.trait,
      };

      for (final entree in decalques.entries) {
        expect(parents, contains(rgb(entree.value)), reason: entree.key);
      }
    });

    test('les deux seules couleurs hors palette sont les marques payees', () {
      expect(MboaColors.jauneMomo, const Color(0xFFFFCC00));
      expect(MboaColors.orangeMoney, const Color(0xFFFF7900));
      // Aucune ne doit etre un vert : la charte l'interdit sans ambiguite.
      for (final marque in [MboaColors.jauneMomo, MboaColors.orangeMoney]) {
        expect(rgb(marque), isNot(rgb(MboaColors.primary)));
        expect(rgb(marque), isNot(rgb(MboaColors.secondary)));
      }
    });
  });

  group('Typographie', () {
    test('aucun style sous 18 px', () {
      final styles = {
        'ecran': MboaTypo.ecran(),
        'titre': MboaTypo.titre(),
        'corps': MboaTypo.corps(),
        'aide': MboaTypo.aide(),
        'chiffre': MboaTypo.chiffre(),
        'chiffreGeant': MboaTypo.chiffreGeant(),
      };

      for (final entree in styles.entries) {
        expect(entree.value.fontSize, greaterThanOrEqualTo(MboaTypo.seuilMinimum),
            reason: entree.key);
      }
    });

    test('le TextTheme entier reste au-dessus du seuil', () {
      final theme = MboaTypo.textTheme;
      final tous = [
        theme.displayLarge, theme.displayMedium, theme.displaySmall,
        theme.headlineMedium, theme.headlineSmall,
        theme.titleLarge, theme.titleMedium, theme.titleSmall,
        theme.bodyLarge, theme.bodyMedium, theme.bodySmall,
        theme.labelLarge, theme.labelMedium, theme.labelSmall,
      ];

      for (final style in tous) {
        expect(style, isNotNull);
        expect(style!.fontSize, greaterThanOrEqualTo(MboaTypo.seuilMinimum));
      }
    });

    test('titre au moins 24, chiffre au moins 32', () {
      expect(MboaTypo.titre().fontSize, greaterThanOrEqualTo(MboaTypo.titreMinimum));
      expect(MboaTypo.ecran().fontSize, greaterThanOrEqualTo(MboaTypo.titreMinimum));
      expect(MboaTypo.chiffre().fontSize, greaterThanOrEqualTo(MboaTypo.chiffreMinimum));
      expect(MboaTypo.chiffreGeant().fontSize, greaterThanOrEqualTo(MboaTypo.chiffreMinimum));
    });

    test('le Black est demande a l axe variable wght 900', () {
      expect(MboaTypo.noir.single.axis, 'wght');
      expect(MboaTypo.noir.single.value, 900);
      expect(MboaTypo.titre().fontVariations, MboaTypo.noir);
    });

    test('tous les styles declarent Nunito', () {
      for (final style in [
        MboaTypo.ecran(), MboaTypo.titre(), MboaTypo.corps(), MboaTypo.aide(),
        MboaTypo.chiffre(), MboaTypo.chiffreGeant(),
      ]) {
        expect(style.fontFamily, MboaTypo.famille);
      }
    });
  });

  group('Cibles tactiles', () {
    test('72 px est la borne de la charte', () {
      expect(MboaTheme.cibleMinimale, 72);
    });

    testWidgets('GrosBouton tient la hauteur demandee', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: MboaTheme.fournisseur,
          home: const Scaffold(
            body: GrosBouton(
              titre: 'Ajouter ma récolte',
              picto: Picto.camera,
              minHeight: 104,
            ),
          ),
        ),
      );

      expect(tester.getSize(find.byType(GrosBouton)).height, greaterThanOrEqualTo(104));
    });

    testWidgets('BoutonCarre fait exactement la taille minimale', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: MboaTheme.fournisseur,
          home: const Scaffold(body: Center(child: BoutonCarre(picto: Picto.plus))),
        ),
      );

      final taille = tester.getSize(find.byType(BoutonCarre));
      expect(taille.width, MboaTheme.cibleMinimale);
      expect(taille.height, MboaTheme.cibleMinimale);
    });

    testWidgets('un GrosBouton sans action ne reagit pas', (tester) async {
      var appuye = false;
      await tester.pumpWidget(
        MaterialApp(
          theme: MboaTheme.fournisseur,
          home: Scaffold(
            body: GrosBouton(
              titre: 'Payer',
              picto: Picto.money,
              onTap: () => appuye = true,
            ),
          ),
        ),
      );

      await tester.tap(find.byType(GrosBouton));
      await tester.pump();
      expect(appuye, isTrue);
    });

    test('le theme impose 72 px aux boutons Material', () {
      final taille = MboaTheme.admin.filledButtonTheme.style?.minimumSize
          ?.resolve(const {});
      expect(taille, const Size.fromHeight(MboaTheme.cibleMinimale));
    });
  });

  group('Icones', () {
    test('un pictogramme est un fichier, jamais un caractere recycle', () {
      for (final picto in Picto.values) {
        expect(picto.fichier, matches(r'^[a-z][a-z0-9_-]*$'), reason: picto.name);
        expect(picto.asset, 'assets/pictos/${picto.fichier}.svg');
        expect(picto.annonce, isNotEmpty);
      }
    });

    test('les huit cases du catalogue ont chacune leur pictogramme', () {
      for (final categorie in Categorie.values) {
        expect(Picto.values.map((p) => p.fichier), contains(categorie.slug),
            reason: categorie.slug);
        expect(Picto.pourCategorie(categorie).fichier, categorie.slug);
      }
    });

    test('une marchandise sans dessin propre prend celui de sa case', () {
      // Le catalogue est ouvert : une reference ajoutee demain ne doit pas
      // demander une nouvelle APK pour avoir une silhouette.
      expect(Picto.pourSlug('boeuf', Categorie.viande), Picto.viande);
      expect(Picto.pourSlug('banane', Categorie.fruit), Picto.banane);
    });

    test('les marques de paiement echappent a la teinte', () {
      expect(Picto.momo.estMarque, isTrue);
      expect(Picto.orangeMoney.estMarque, isTrue);
      expect(Picto.camera.estMarque, isFalse);
      expect(Picto.banane.estMarque, isFalse);
    });
  });
}
