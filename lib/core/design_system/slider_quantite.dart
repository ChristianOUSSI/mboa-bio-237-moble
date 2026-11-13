import 'dart:async';

import 'package:flutter/material.dart';

import '../data/models/categorie.dart';
import '../data/models/unite.dart';
import '../theme/mboa_colors.dart';
import '../theme/mboa_typography.dart';
import '../utils/format_monnaie.dart';
import '../voice/tts_service.dart';
import 'picto.dart';

/// Le curseur de quantite.
///
/// Pas de clavier, pas de champ numerique : des paliers ronds, un tas qui
/// grossit a l'ecran, et le nombre qui se dit tout haut. Le pouce glisse,
/// l'oeil voit la montagne grandir, l'oreille confirme.
///
/// [unite] est obligatoire a l'usage : un curseur qui dit « 5 » sans dire
/// « kilos », « boules » ou « litres » laisse l'utilisatrice deviner ce
/// qu'elle va payer.
class SliderQuantite extends StatefulWidget {
  const SliderQuantite({
    required this.paliers,
    required this.index,
    required this.onChanged,
    required this.categorie,
    required this.unite,
    this.slug,
    this.libelle,
    super.key,
  });

  final List<int> paliers;
  final int index;
  final ValueChanged<int> onChanged;

  /// La case du produit, pour le dessin du tas qui grossit.
  final Categorie categorie;

  /// La mesure reelle du produit : c'est elle qui est dite a voix haute.
  final Unite unite;

  /// La cle du produit, pour tenter son pictogramme avant celui de la case.
  final String? slug;

  /// Le nom prononce. A defaut, celui de la categorie.
  final String? libelle;

  @override
  State<SliderQuantite> createState() => _SliderQuantiteState();
}

class _SliderQuantiteState extends State<SliderQuantite> {
  Timer? _retardVoix;

  @override
  void dispose() {
    _retardVoix?.cancel();
    super.dispose();
  }

  /// Le chiffre est vocalise avec un petit retard : glisser sur un pouce
  /// traverse trois paliers, et s'entendre dire « dix, vingt, cinquante »
  /// dans le desordre est pire que de n'entendre que la valeur finale.
  void _dire(int index) {
    _retardVoix?.cancel();
    _retardVoix = Timer(const Duration(milliseconds: 420), () {
      if (mounted) {
        TtsService.instance.dire(widget.unite.avec(widget.paliers[index].toDouble()));
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final quantite = widget.paliers[widget.index].toDouble();

    return Column(
      children: [
        TasQuiGrossit(
          categorie: widget.categorie,
          slug: widget.slug,
          progression: widget.paliers.length < 2
              ? 1
              : widget.index / (widget.paliers.length - 1),
        ),
        const SizedBox(height: 10),
        ChiffreUnite(
          valeur: formaterKg(quantite),
          unite: widget.unite.pour(quantite),
          geant: true,
        ),
        Slider(
          value: widget.index.toDouble(),
          min: 0,
          max: (widget.paliers.length - 1).toDouble(),
          divisions: widget.paliers.length - 1,
          label: '${widget.paliers[widget.index]}',
          onChanged: (valeur) {
            final index = valeur.round();
            setState(() {});
            widget.onChanged(index);
            _dire(index);
          },
        ),
        // Les paliers sont marques par des points, pas par des chiffres :
        // lire « 2 5 10 20 50 » alignes sous un curseur est un exercice de
        // lecture que l'on cherche justement a eviter.
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            for (var i = 0; i < widget.paliers.length; i++)
              Container(
                width: 14,
                height: 14,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: i <= widget.index ? MboaColors.primary : MboaColors.primaryDoux,
                ),
              ),
          ],
        ),
      ],
    );
  }
}

/// Le tas qui grossit : une montagne dessinee et le pictogramme du produit
/// qui prend de la place a mesure qu'on monte le curseur.
class TasQuiGrossit extends StatelessWidget {
  const TasQuiGrossit({
    required this.categorie,
    required this.progression,
    this.slug,
    this.hauteur = 132,
    super.key,
  });

  final Categorie categorie;

  /// La cle du produit, pour son propre dessin s'il en a un.
  final String? slug;

  /// 0.0 = un petit tas, 1.0 = le tas plein.
  final double progression;

  final double hauteur;

  @override
  Widget build(BuildContext context) {
    final remplie = progression.clamp(0.0, 1.0);

    return SizedBox(
      height: hauteur,
      width: double.infinity,
      child: Stack(
        alignment: Alignment.bottomCenter,
        children: [
          CustomPaint(
            size: Size.infinite,
            painter: _TasPainter(remplie: remplie),
          ),
          Padding(
            padding: EdgeInsets.only(bottom: hauteur * (0.12 + 0.30 * remplie)),
            child: PictoIcon(
              Picto.pourSlug(slug ?? '', categorie),
              size: 40 + 56 * remplie,
              couleur: MboaColors.primary,
              label: categorie.libelle,
            ),
          ),
        ],
      ),
    );
  }
}

class _TasPainter extends CustomPainter {
  _TasPainter({required this.remplie});

  final double remplie;

  @override
  void paint(Canvas canvas, Size taille) {
    final sol = taille.height - 6;
    final trait = Paint()
      ..color = MboaColors.primary
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeJoin = StrokeJoin.round;
    final fond = Paint()
      ..color = MboaColors.secondaryDoux
      ..style = PaintingStyle.fill;

    final hauteurTas = 26 + (taille.height - 40) * remplie;
    final demiLargeur = taille.width * (0.30 + 0.18 * remplie);
    final cx = taille.width / 2;

    final chemin = Path()
      ..moveTo(cx - demiLargeur, sol)
      ..quadraticBezierTo(cx - demiLargeur * 0.45, sol - hauteurTas, cx, sol - hauteurTas)
      ..quadraticBezierTo(cx + demiLargeur * 0.45, sol - hauteurTas, cx + demiLargeur, sol)
      ..close();

    canvas.drawPath(chemin, fond);
    canvas.drawPath(chemin, trait);

    // La ligne de terre reste fixe : c'est le repere qui permet de voir que
    // c'est le tas qui monte, et non tout l'ecran qui change d'echelle.
    final terre = Paint()
      ..color = MboaColors.primary
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(12, sol, taille.width - 12, sol, terre);
  }

  @override
  bool shouldRepaint(_TasPainter ancien) => ancien.remplie != remplie;
}
