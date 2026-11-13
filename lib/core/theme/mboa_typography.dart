import 'package:flutter/painting.dart';

import 'mboa_colors.dart';

/// Echelle typographique MBOA BIO 237.
///
/// Trois regles non negociables, verifiees par le widget de test de typo :
///   1. aucun texte sous 18 px ;
///   2. tout titre en Nunito Black (huit 900) a 24 px au minimum ;
///   3. tout nombre isole (prix, kilos, code OTP) a 32 px au minimum.
///
/// Nunito est embarquee en police variable (axe wght 200 a 1000) : un seul
/// fichier TTF dans assets/fonts/, et le poids est demande par FontVariation.
/// Sans variable font, `FontVariation` est ignore silencieusement et le
/// fallback FontWeight.w900 reprend la meme silhouette.
class MboaTypo {
  const MboaTypo._();

  static const String famille = 'Nunito';

  /// Poids Black demande a la police variable.
  static const List<FontVariation> noir = [FontVariation('wght', 900)];

  /// Poids Bold des chiffres.
  static const List<FontVariation> gras = [FontVariation('wght', 700)];

  static const int seuilMinimum = 18;
  static const int titreMinimum = 24;
  static const int chiffreMinimum = 32;

  /// Titre d'ecran. 28 px : plus grand que le minimum, parce que l'ecran
  /// suivant ne doit jamais se meriter.
  static TextStyle ecran({Color couleur = MboaColors.text}) => TextStyle(
        fontFamily: famille,
        fontFamilyFallback: const ['Nunito', 'sans-serif'],
        fontSize: 28,
        fontWeight: FontWeight.w900,
        fontVariations: noir,
        color: couleur,
        height: 1.15,
      );

  /// Titre de section et libelle des gros boutons.
  static TextStyle titre({Color couleur = MboaColors.text}) => TextStyle(
        fontFamily: famille,
        fontSize: 24,
        fontWeight: FontWeight.w900,
        fontVariations: noir,
        color: couleur,
        height: 1.2,
      );

  /// Texte courant. 20 px : une phrase de confirmation reste lisible a
  /// bout de bras, telephone a hauteur d'epaule.
  static TextStyle corps({Color couleur = MboaColors.text}) => TextStyle(
        fontFamily: famille,
        fontSize: 20,
        fontWeight: FontWeight.w600,
        fontVariations: const [FontVariation('wght', 600)],
        color: couleur,
        height: 1.35,
      );

  /// Mention la plus petite autorisee : 18 px pile.
  static TextStyle aide({Color couleur = MboaColors.textDoux}) => TextStyle(
        fontFamily: famille,
        fontSize: 18,
        fontWeight: FontWeight.w600,
        fontVariations: const [FontVariation('wght', 600)],
        color: couleur,
        height: 1.3,
      );

  /// Prix, kilos, code OTP. 32 px, le chiffre est l'information.
  static TextStyle chiffre({Color couleur = MboaColors.primary}) => TextStyle(
        fontFamily: famille,
        fontSize: 32,
        fontWeight: FontWeight.w800,
        fontVariations: gras,
        color: couleur,
        height: 1.05,
        letterSpacing: -0.5,
      );

  /// Le chiffre du slider de quantite : 44 px, lisible sans lunettes.
  static TextStyle chiffreGeant({Color couleur = MboaColors.primary}) => TextStyle(
        fontFamily: famille,
        fontSize: 44,
        fontWeight: FontWeight.w900,
        fontVariations: noir,
        color: couleur,
        height: 1.0,
      );

  /// Le texte est toujours centre ou aligne a gauche, jamais justifie : la
  /// justification cree des trous que l'il ne sait pas suivre.
  static TextTheme get textTheme {
    final corps = MboaTypo.corps();
    final titre = MboaTypo.titre();
    return TextTheme(
      displayLarge: titre.copyWith(fontSize: 32),
      displayMedium: titre.copyWith(fontSize: 28),
      displaySmall: titre,
      headlineMedium: titre,
      headlineSmall: titre,
      titleLarge: titre,
      titleMedium: titre,
      titleSmall: titre.copyWith(fontSize: 20),
      bodyLarge: corps,
      bodyMedium: corps,
      bodySmall: MboaTypo.aide(),
      labelLarge: titre,
      labelMedium: corps,
      labelSmall: MboaTypo.aide(),
    );
  }
}
