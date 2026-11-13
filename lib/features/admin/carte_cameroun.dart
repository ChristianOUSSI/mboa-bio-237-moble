import 'package:flutter/material.dart';

import '../../core/data/models/repere.dart';
import '../../core/design_system/picto.dart';
import '../../core/theme/mboa_colors.dart';
import '../../core/theme/mboa_typography.dart';

/// La carte du Cameroun et ses points verts.
///
/// Le contour est une silhouette schematique, pas une frontiere officielle :
/// il sert a situer un village par rapport a un autre, pas a tracer une ligne.
/// Les coordonnees des localites, elles, sont reelles, et c'est elles qui
/// decident de la position du point.
///
/// Un point vaut un village, pas un producteur. Dix mama de Mbouda font un
/// gros point, sinon la carte devient un semis illisible sur un ecran de
/// cinq pouces.
class CarteCameroun extends StatelessWidget {
  const CarteCameroun({
    required this.repere,
    this.choisi,
    this.onChoisi,
    super.key,
  });

  final List<RepereVillage> repere;
  final RepereVillage? choisi;
  final ValueChanged<RepereVillage?>? onChoisi;

  /// L'emprise geographique du Cameroun, en degres.
  static const double _ouest = 8.3;
  static const double _est = 16.3;
  static const double _sud = 2.1;
  static const double _nord = 13.3;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => onChoisi?.call(null),
      child: LayoutBuilder(
        builder: (context, contraintes) {
          final taille = Size(contraintes.maxWidth, contraintes.maxHeight);

          return Stack(
            children: [
              CustomPaint(
                size: taille,
                painter: _SilhouettePainter(
                  projection: _Projection(taille),
                ),
              ),
              for (final point in repere)
                Positioned(
                  left: (_Projection(taille).x(point.longitude) - 22).clamp(0, taille.width - 44),
                  top: (_Projection(taille).y(point.latitude) - 22).clamp(0, taille.height - 44),
                  child: _Point(
                    repere: point,
                    actif: choisi?.village == point.village,
                    onTap: () => onChoisi?.call(point),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  /// Projection equirectangulaire simple.
  ///
  /// A cette echelle, une projection conique ne change rien de visible et
  /// coute un ordre de grandeur en complexite : le bon choix est le simple.
  static double longitudeDe(double x, double largeur) =>
      _ouest + (x / largeur) * (_est - _ouest);

  static double latitudeDe(double y, double hauteur) =>
      _nord - (y / hauteur) * (_nord - _sud);
}

class _Projection {
  _Projection(this.taille);

  final Size taille;

  double x(double longitude) => (longitude - CarteCameroun._ouest) /
          (CarteCameroun._est - CarteCameroun._ouest) *
          taille.width;

  double y(double latitude) => (CarteCameroun._nord - latitude) /
          (CarteCameroun._nord - CarteCameroun._sud) *
          taille.height;
}

class _SilhouettePainter extends CustomPainter {
  _SilhouettePainter({required this.projection});

  final _Projection projection;

  /// Contour schematique du Cameroun, en (longitude, latitude), sens
  /// horaire depuis la cote oceanique pres de Douala.
  static const List<List<double>> _contour = [
    [9.0, 4.3],
    [9.3, 3.4],
    [10.0, 2.3],
    [11.6, 2.2],
    [13.5, 2.2],
    [14.6, 2.2],
    [15.2, 3.8],
    [16.1, 4.0],
    [15.8, 5.5],
    [14.7, 6.0],
    [14.2, 7.5],
    [15.3, 7.9],
    [15.1, 9.3],
    [13.9, 9.6],
    [14.2, 11.2],
    [14.8, 11.6],
    [14.1, 13.1],
    [12.8, 13.1],
    [11.9, 12.6],
    [10.9, 11.4],
    [9.9, 10.0],
    [9.3, 8.5],
    [8.6, 7.0],
    [8.9, 5.6],
  ];

  @override
  void paint(Canvas canvas, Size taille) {
    final chemin = Path();
    for (var i = 0; i < _contour.length; i++) {
      final point = Offset(projection.x(_contour[i][0]), projection.y(_contour[i][1]));
      if (i == 0) {
        chemin.moveTo(point.dx, point.dy);
      } else {
        chemin.lineTo(point.dx, point.dy);
      }
    }
    chemin.close();

    canvas.drawPath(
      chemin,
      Paint()
        ..color = MboaColors.primaryDoux
        ..style = PaintingStyle.fill,
    );
    canvas.drawPath(
      chemin,
      Paint()
        ..color = MboaColors.primary
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..strokeJoin = StrokeJoin.round,
    );

    // Yaoundé et Douala sont les deux seules villes marquees : ce sont les
    // deux points de collecte, donc les deux repères dont l'admin a besoin.
    for (final capitale in [
      [11.5021, 3.8480],
      [9.7044, 4.0483],
    ]) {
      final o = Offset(projection.x(capitale[0]), projection.y(capitale[1]));
      canvas.drawCircle(o, 5, Paint()..color = MboaColors.primary);
    }
  }

  @override
  bool shouldRepaint(_SilhouettePainter ancien) => ancien.projection.taille != projection.taille;
}

class _Point extends StatelessWidget {
  const _Point({required this.repere, required this.actif, required this.onTap});

  final RepereVillage repere;
  final bool actif;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final diametre = repere.diametre;

    return Semantics(
      button: true,
      label: repere.annonce,
      child: GestureDetector(
        onTap: onTap,
        child: SizedBox(
          width: 44,
          height: 44,
          child: Stack(
            alignment: Alignment.center,
            children: [
              Container(
                width: diametre,
                height: diametre,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: MboaColors.secondary,
                  border: Border.all(
                    color: actif ? MboaColors.text : MboaColors.primary,
                    width: actif ? 4 : 2,
                  ),
                ),
              ),
              if (actif)
                Positioned(
                  bottom: -26,
                  child: Text(
                    repere.village,
                    style: MboaTypo.aide(couleur: MboaColors.text),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Le resume du village choisi, pose sur la carte.
class FicheVillage extends StatelessWidget {
  const FicheVillage({required this.repere, super.key});

  final RepereVillage repere;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: MboaColors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: MboaColors.primary, width: 3),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const PictoIcon(Picto.person, size: 32),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(repere.village, style: MboaTypo.titre()),
              Text(
                '${repere.fournisseurs} producteurs',
                style: MboaTypo.aide(),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
