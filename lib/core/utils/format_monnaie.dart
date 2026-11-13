import 'package:flutter/material.dart';

import '../theme/mboa_colors.dart';
import '../theme/mboa_typography.dart';

/// 1 250 -> « 1 250 FCFA », avec une espace insecable fine entre les
/// milliers pour que le chiffre ne se casse jamais en deux en fin de ligne.
String formaterFcfa(int montant) => '${_groupes(montant)} FCFA';

/// 1 250 -> « 1 250 F », la forme courte utilisee dans les tuiles.
String formaterFcfaCourt(int montant) => '${_groupes(montant)} F';

String _groupes(int montant) {
  final chiffres = montant.abs().toString();
  final tampons = <String>[];
  for (var i = chiffres.length; i > 0; i -= 3) {
    final debut = (i - 3).clamp(0, chiffres.length);
    tampons.insert(0, chiffres.substring(debut, i));
  }
  // U+00A0 : espace insecable. Le groupe de chiffres ne se casse jamais en
  // debut de ligne, et le TTS l'entend comme une simple pause.
  final joint = tampons.join('\u00A0');
  return montant < 0 ? '-$joint' : joint;
}

/// 2.0 -> « 2 », 2.5 -> « 2,5 ». Le TTS n'a jamais a entendre « virgule zero ».
String formaterKg(double kg) {
  final arrondi = kg.roundToDouble();
  final texte = (kg - arrondi).abs() < 0.01
      ? arrondi.toStringAsFixed(0)
      : kg.toStringAsFixed(1);
  return texte.replaceAll('.', ',');
}

/// Un nombre isole, a 32 px minimum, avec son unite en plus petit.
class ChiffreUnite extends StatelessWidget {
  const ChiffreUnite({
    required this.valeur,
    this.unite,
    this.geant = false,
    this.couleur,
    super.key,
  });

  final String valeur;
  final String? unite;
  final bool geant;
  final Color? couleur;

  @override
  Widget build(BuildContext context) {
    final style = geant ? MboaTypo.chiffreGeant(couleur: couleur ?? MboaColors.primary) : MboaTypo.chiffre(couleur: couleur ?? MboaColors.primary);
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        Text(valeur, style: style),
        if (unite != null) ...[
          const SizedBox(width: 6),
          Text(unite!, style: MboaTypo.corps(couleur: couleur ?? MboaColors.textDoux)),
        ],
      ],
    );
  }
}
