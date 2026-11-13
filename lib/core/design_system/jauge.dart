import 'package:flutter/material.dart';

import '../theme/mboa_colors.dart';

/// Jauge de stock : une barre verte qui se vide.
///
/// Le vert clair [MboaColors.secondary] est autorise ici parce qu'il ne porte
/// aucun texte, seulement une surface. Le contour vert fonce garantit que la
/// jauge reste visible sur le beige, la ou une simple aplat de vert clair
/// disparaitrait au soleil.
class JaugeStock extends StatelessWidget {
  const JaugeStock({
    required this.ratio,
    this.hauteur = 20,
    this.quasiVide = false,
    super.key,
  });

  /// Remplissage de 0.0 a 1.0.
  final double ratio;

  /// Vrai quand le tas est a zero : la jauge passe en rouge et non pas vide,
  /// parce qu'une barre vide ne se distingue pas d'un chargement.
  final bool quasiVide;

  final double hauteur;

  @override
  Widget build(BuildContext context) {
    final remplissage = ratio.clamp(0.0, 1.0);

    return Container(
      height: hauteur,
      decoration: BoxDecoration(
        color: MboaColors.background,
        borderRadius: BorderRadius.circular(hauteur / 2),
        border: Border.all(
          color: quasiVide ? MboaColors.error : MboaColors.primary,
          width: 2.5,
        ),
      ),
      child: LayoutBuilder(
        builder: (context, contrainte) => Align(
          alignment: Alignment.centerLeft,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 260),
            curve: Curves.easeOut,
            width: (contrainte.maxWidth - 5) * remplissage,
            decoration: BoxDecoration(
              color: quasiVide ? MboaColors.error : MboaColors.secondary,
              borderRadius: BorderRadius.circular(hauteur / 2),
            ),
          ),
        ),
      ),
    );
  }
}
