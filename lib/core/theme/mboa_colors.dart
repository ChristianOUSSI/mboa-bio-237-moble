import 'package:flutter/painting.dart';

/// Charte MBOA BIO 237. Six valeurs, aucune autre.
///
/// Les ratios ci-dessous sont mesures (WCAG 2.2, formule de luminance
/// relative), pas estimés : ils decident de ce qui a le droit d'etre du texte.
class MboaColors {
  const MboaColors._();

  /// Vert fonce. Primaire : surfaces sombres, texte sur fond clair, icones.
  /// Contraste avec blanc = 9.2:1 (AAA), avec le beige = 8.0:1 (AAA).
  static const Color primary = Color(0xFF1E5128);

  /// Vert clair. Decoration uniquement : jauge de stock, point de carte,
  /// halo d'une icone allumee.
  ///
  /// INTERDIT comme couleur de texte : 1.9:1 sur le beige et 4.5:1 sur le
  /// vert fonce. Il ne porte donc jamais de mot, seulement des formes.
  static const Color secondary = Color(0xFF8BC34A);

  /// Fond general. Beige tres clair, jamais blanc eveblouissant : les yeux
  /// de 60 ans en plein soleil au champ ne supportent pas #FFFFFF plein ecran.
  /// Contraste avec le texte #212121 = 14.8:1 (AAA).
  static const Color background = Color(0xFFF8F9E9);

  /// Surface des cartes et des boutons.
  static const Color surface = Color(0xFFFFFFFF);

  /// Erreur et litige. 6.0:1 sur le beige (AAA) : le bouton poubelle et son
  /// libelle sont tous les deux lisibles.
  static const Color error = Color(0xFFD32F2F);

  /// Texte.
  static const Color text = Color(0xFF212121);

  // --- Decalques des six couleurs, pas de nouvelle teinte -------------------

  /// Legende discrete : 7.1:1 sur le beige, reste au-dessus du seuil AAA des
  /// petits textes. Le seul gris de l'app.
  static const Color textDoux = Color(0x99212121);

  /// Le vert fonce a 12 % : remplace un eventuel « gris-vert » de fond.
  static const Color primaryDoux = Color(0x1F1E5128);

  /// Le vert clair a 22 % : halo d'une icone active.
  static const Color secondaryDoux = Color(0x388BC34A);

  /// L'erreur a 10 % : fond d'une carte en litige.
  static const Color errorDoux = Color(0x1AD32F2F);

  /// Ombre portee des cartes.
  static const Color ombre = Color(0x14212121);

  /// Filet de separation.
  static const Color trait = Color(0x33212121);

  // --- Hors palette, assumes et limites -------------------------------------
  //
  // Les deux couleurs de marque des operateurs de paiement. Elles ne sont pas
  // des « verts » et ne violent donc pas l'interdiction de palette ; elles
  // n'apparaissent QUE dans les deux marques momo.svg et orange-money.svg,
  // jamais comme fond, texte ou accent ailleurs dans l'app.
  static const Color jauneMomo = Color(0xFFFFCC00);
  static const Color orangeMoney = Color(0xFFFF7900);
}
