import 'package:flutter/material.dart';

import 'mboa_colors.dart';
import 'mboa_typography.dart';

/// Theme unique, trois personnalisations legeres selon le role.
///
/// Les ecarts restent dans la palette : l'admin travaille sur des colonnes,
/// donc ses surfaces sont blanches ; le fournisseur voit le champ, donc ses
/// surfaces restent beiges. Aucun vert hors des deux autorises.
class MboaTheme {
  const MboaTheme._();

  /// Taille minimale absolue d'une cible tactile, en pixels logiques.
  /// 72 px : un pouce age, sur un ecran 5 pouces, avec des gants.
  static const double cibleMinimale = 72;

  /// Marge entre deux cibles : evite de toucher le bouton d'a cote.
  static const double espacementCible = 16;

  static ThemeData get fournisseur => _base(surfacesBeiges: true);

  static ThemeData get admin => _base(surfacesBeiges: false);

  static ThemeData get consommateur => _base(surfacesBeiges: true);

  static ThemeData get livreur => _base(surfacesBeiges: false);

  static ThemeData _base({required bool surfacesBeiges}) {
    final texte = MboaTypo.textTheme;

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      scaffoldBackgroundColor: MboaColors.background,
      fontFamily: MboaTypo.famille,
      textTheme: texte,
      colorScheme: const ColorScheme.light(
        primary: MboaColors.primary,
        onPrimary: MboaColors.surface,
        secondary: MboaColors.secondary,
        onSecondary: MboaColors.primary,
        surface: MboaColors.background,
        onSurface: MboaColors.text,
        error: MboaColors.error,
        onError: MboaColors.surface,
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: MboaColors.primary,
        foregroundColor: MboaColors.surface,
        elevation: 0,
        centerTitle: true,
        titleTextStyle: MboaTypo.titre(couleur: MboaColors.surface),
        iconTheme: const IconThemeData(color: MboaColors.surface, size: 32),
      ),
      cardTheme: CardTheme(
        color: surfacesBeiges ? MboaColors.background : MboaColors.surface,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: const BorderSide(color: MboaColors.trait, width: 2),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size.fromHeight(cibleMinimale),
          backgroundColor: MboaColors.primary,
          foregroundColor: MboaColors.surface,
          textStyle: MboaTypo.titre(couleur: MboaColors.surface),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          minimumSize: const Size.fromHeight(cibleMinimale),
          foregroundColor: MboaColors.primary,
          textStyle: MboaTypo.titre(),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: MboaColors.primary,
        contentTextStyle: MboaTypo.corps(couleur: MboaColors.surface),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      sliderTheme: SliderThemeData(
        trackHeight: 18,
        activeTrackColor: MboaColors.primary,
        inactiveTrackColor: MboaColors.primaryDoux,
        thumbColor: MboaColors.surface,
        overlayColor: MboaColors.secondaryDoux,
        // Le pouce est une cible tactile, pas un curseur de precision.
        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 26),
        trackShape: const RectangularSliderTrackShape(),
      ),
      dialogTheme: DialogTheme(
        backgroundColor: MboaColors.background,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        titleTextStyle: MboaTypo.titre(),
        contentTextStyle: MboaTypo.corps(),
      ),
      dividerTheme: const DividerThemeData(
        color: MboaColors.trait,
        thickness: 2,
        space: 2,
      ),
      iconTheme: const IconThemeData(color: MboaColors.primary, size: 40),
      visualDensity: VisualDensity.standard,
    );
  }
}
