import 'package:flutter/material.dart';

import '../../core/design_system/picto.dart';
import '../../core/design_system/tactile.dart';
import '../../core/theme/mboa_colors.dart';
import '../../core/theme/mboa_typography.dart';

/// Le pave numerique geant.
///
/// Le clavier systeme est absent de tout le parcours : ses touches font
/// environ 44 px, ses symboles inutiles occupent la moitie de l'ecran, et sa
/// disposition change selon la marque du telephone. Ici, dix touches de 72 px
/// minimum, toujours au meme endroit, avec le chiffre a 32 px.
class PaveNumerique extends StatelessWidget {
  const PaveNumerique({
    required this.onTouche,
    this.effacer,
    this.valider,
    this.titre,
    this.annonce,
    this.largeurMaximale = 340,
    super.key,
  });

  /// Recoit le caractere tape.
  final ValueChanged<String> onTouche;

  final VoidCallback? effacer;
  final VoidCallback? valider;

  /// Ce que la voix dit a chaque appui : le chiffre, puis le numero complet.
  final String? titre;

  final String? annonce;

  final double largeurMaximale;

  static const List<String> _rangee1 = ['1', '2', '3'];
  static const List<String> _rangee2 = ['4', '5', '6'];
  static const List<String> _rangee3 = ['7', '8', '9'];

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: largeurMaximale),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (titre != null) ...[
              Text(titre!, style: MboaTypo.titre(), textAlign: TextAlign.center),
              const SizedBox(height: 14),
            ],
            for (final rangee in [_rangee1, _rangee2, _rangee3])
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Row(
                  children: _entrelace(
                    [
                      for (final chiffre in rangee)
                        Expanded(child: _Touche(chiffre: chiffre, onTouche: onTouche, annonce: annonce)),
                    ],
                  ),
                ),
              ),
            Row(
              children: _entrelace([
                Expanded(
                  child: _ToucheSpeciale(
                    picto: Picto.minus,
                    libelle: 'Effacer',
                    onTap: effacer,
                  ),
                ),
                Expanded(
                  child: _Touche(chiffre: '0', onTouche: onTouche, annonce: annonce),
                ),
                Expanded(
                  child: _ToucheSpeciale(
                    picto: Picto.check,
                    libelle: 'Valider',
                    onTap: valider,
                    sombre: true,
                  ),
                ),
              ]),
            ),
          ],
        ),
      ),
    );
  }

  /// Insere un espace de 12 px entre les colonnes, sans en mettre apres la
  /// derniere : le pave doit rester centre, pas decale vers la gauche.
  static List<Widget> _entrelace(List<Widget> enfants) {
    final resultat = <Widget>[];
    for (var i = 0; i < enfants.length; i++) {
      if (i > 0) resultat.add(const SizedBox(width: 12));
      resultat.add(enfants[i]);
    }
    return resultat;
  }
}

class _Touche extends StatelessWidget {
  const _Touche({required this.chiffre, required this.onTouche, this.annonce});

  final String chiffre;
  final ValueChanged<String> onTouche;
  final String? annonce;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Chiffre $chiffre',
      child: GestureDetector(
        onTap: () {
          mboaTactile(
            annonce: annonce == null ? chiffre : '$chiffre. $annonce',
            fort: true,
          );
          onTouche(chiffre);
        },
        child: Container(
          height: 72,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: MboaColors.surface,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: MboaColors.primary, width: 3),
          ),
          child: Text(chiffre, style: MboaTypo.chiffre()),
        ),
      ),
    );
  }
}

class _ToucheSpeciale extends StatelessWidget {
  const _ToucheSpeciale({
    required this.picto,
    required this.libelle,
    required this.onTap,
    this.sombre = false,
  });

  final Picto picto;
  final String libelle;
  final VoidCallback? onTap;
  final bool sombre;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: libelle,
      child: GestureDetector(
        onTap: onTap == null
            ? null
            : () {
                mboaTactile(annonce: libelle);
                onTap!();
              },
        child: Container(
          height: 72,
          decoration: BoxDecoration(
            color: sombre ? MboaColors.primary : MboaColors.surface,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: sombre ? MboaColors.primary : MboaColors.trait,
              width: 3,
            ),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              PictoIcon(picto, size: 26, couleur: sombre ? MboaColors.surface : MboaColors.primary),
              Text(
                libelle,
                style: MboaTypo.aide(couleur: sombre ? MboaColors.surface : MboaColors.text),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
