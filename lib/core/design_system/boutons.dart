import 'package:flutter/material.dart';

import '../theme/mboa_colors.dart';
import '../theme/mboa_typography.dart';
import '../theme/mboa_theme.dart';
import '../voice/tts_service.dart';
import 'picto.dart';
import 'tactile.dart';

/// Bouton principal de toutes les apps : au moins 72 px de haut, une icone,
/// un mot, et une annonce vocale a l'appui.
///
/// C'est le composant ou se joue l'accessibilite. Trois regles y sont
/// verrouillees :
///   * la hauteur minimale de [MboaTheme.cibleMinimale], jamais negociee ;
///   * le libelle est un mot, jamais une phrase ;
///   * l'annonce vocale est lue AVANT l'action, pour que l'utilisateur
///     comprenne ce qu'il vient de declencher.
class GrosBouton extends StatefulWidget {
  const GrosBouton({
    required this.titre,
    this.picto,
    this.image,
    this.chiffre,
    this.sousTitre,
    this.onTap,
    this.annonce,
    this.couleurFond,
    this.couleurTexte,
    this.couleurTrait,
    this.sombre = false,
    this.minHeight = 104,
    this.secondaire = false,
    super.key,
  });

  final String titre;
  final Picto? picto;

  /// Une photo a la place de l'icone : c'est le cas des tuiles de la grille
  /// 3x3, ou le producteur touche la photo du fruit, pas son symbole.
  final Widget? image;

  /// Nombre affiche a droite, a 32 px minimum (prix, kilos, commandes).
  final String? chiffre;

  final String? sousTitre;
  final VoidCallback? onTap;

  /// Ce que la voix dit. Par defaut le titre, puis le sous-titre.
  final String? annonce;

  final Color? couleurFond;
  final Color? couleurTexte;

  /// Le trait du contour. Le laisser null le deduit du fond : sombre = meme
  /// couleur que la surface, clair = le filet de charte.
  ///
  /// Le rouge n'est passe ici que pour le pouce baisse : un bouton qui mène a
  /// un litige doit se distinguer sans hurler.
  final Color? couleurTrait;

  /// Fond vert fonce, texte blanc : l'etat « action engageante ».
  final bool sombre;

  /// Fond blanc, texte vert : l'etat neutre, pour les deuxieme et troisieme
  /// choix d'un ecran.
  final bool secondaire;

  final double minHeight;

  @override
  State<GrosBouton> createState() => _GrosBoutonState();
}

class _GrosBoutonState extends State<GrosBouton> {
  bool _appuie = false;

  Color get _fond {
    if (widget.couleurFond != null) return widget.couleurFond!;
    if (widget.sombre) return MboaColors.primary;
    return MboaColors.surface;
  }

  Color get _texte {
    if (widget.couleurTexte != null) return widget.couleurTexte!;
    if (widget.sombre) return MboaColors.surface;
    return MboaColors.text;
  }

  Future<void> _cliquer() async {
    if (widget.onTap == null) return;
    await mboaTactile(
      annonce: widget.annonce ??
          [widget.titre, widget.sousTitre]
              .whereType<String>()
              .where((s) => s.isNotEmpty)
              .join(', '),
    );
    widget.onTap!();
  }

  @override
  Widget build(BuildContext context) {
    final actif = widget.onTap != null;

    return Semantics(
      button: true,
      enabled: actif,
      label: widget.annonce ?? widget.titre,
      child: GestureDetector(
        onTap: actif ? _cliquer : null,
        onTapDown: actif ? (_) => setState(() => _appuie = true) : null,
        onTapCancel: actif ? () => setState(() => _appuie = false) : null,
        onTapUp: actif ? (_) => setState(() => _appuie = false) : null,
        child: AnimatedScale(
          scale: _appuie ? 0.97 : 1,
          duration: const Duration(milliseconds: 90),
          child: Container(
            constraints: BoxConstraints(minHeight: widget.minHeight),
            decoration: BoxDecoration(
              color: _fond,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(
                color: widget.couleurTrait ??
                    (widget.sombre ? MboaColors.primary : MboaColors.trait),
                width: 3,
              ),
              boxShadow: widget.sombre
                  ? null
                  : const [BoxShadow(color: MboaColors.ombre, blurRadius: 10, offset: Offset(0, 4))],
            ),
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
            child: Row(
              children: [
                if (widget.image != null)
                  SizedBox(width: 64, height: 64, child: widget.image)
                else if (widget.picto != null)
                  PictoPastille(
                    picto: widget.picto!,
                    diametre: 64,
                    allume: true,
                    couleurFond: widget.sombre ? MboaColors.surface : null,
                    couleurTrait: widget.sombre ? MboaColors.surface : null,
                  ),
                if (widget.image != null || widget.picto != null) const SizedBox(width: 18),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.titre,
                        style: MboaTypo.titre(couleur: _texte),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (widget.sousTitre != null)
                        Text(
                          widget.sousTitre!,
                          style: MboaTypo.aide(couleur: widget.sombre ? MboaColors.surface : MboaColors.textDoux),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                    ],
                  ),
                ),
                if (widget.chiffre != null) ...[
                  const SizedBox(width: 12),
                  Text(
                    widget.chiffre!,
                    style: MboaTypo.chiffre(
                      couleur: widget.sombre ? MboaColors.surface : MboaColors.primary,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Bouton carre de 72 px : les plus et moins du panier, le haut-parleur d'une
/// tuile, la corbeille d'un litige.
class BoutonCarre extends StatelessWidget {
  const BoutonCarre({
    required this.picto,
    this.onTap,
    this.annonce,
    this.couleurFond,
    this.couleurTrait,
    this.taille = MboaTheme.cibleMinimale,
    this.error = false,
    super.key,
  });

  final Picto picto;
  final VoidCallback? onTap;
  final String? annonce;
  final Color? couleurFond;
  final Color? couleurTrait;
  final double taille;

  /// Le rouge n'est jamais decoratif : il n'existe que pour la poubelle et
  /// les actions destructrices.
  final bool error;

  @override
  Widget build(BuildContext context) {
    final fond = couleurFond ?? (error ? MboaColors.error : MboaColors.surface);
    final trait = couleurTrait ?? (error ? MboaColors.error : MboaColors.trait);
    final teinte = error ? MboaColors.surface : MboaColors.primary;

    return Semantics(
      button: true,
      label: annonce ?? picto.annonce,
      child: GestureDetector(
        onTap: onTap == null
            ? null
            : () async {
                await mboaTactile(
                  annonce: annonce ?? picto.annonce,
                  fort: error,
                );
                onTap!();
              },
        child: Container(
          width: taille,
          height: taille,
          decoration: BoxDecoration(
            color: fond,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: trait, width: 3),
          ),
          child: Center(
            child: PictoIcon(picto, size: taille * 0.5, couleur: teinte),
          ),
        ),
      ),
    );
  }
}

/// La tuile-haut-parleur : partout ou l'app doit dire un texte long.
///
/// Separe du bouton d'action parce que sur un ecran de 5 pouces, « ecouter »
/// et « acheter » ne doivent jamais partager la meme cible.
class BoutonVoix extends StatelessWidget {
  const BoutonVoix({required this.texte, this.resume, super.key});

  final String texte;
  final String? resume;

  @override
  Widget build(BuildContext context) {
    return BoutonCarre(
      picto: Picto.speaker,
      annonce: resume ?? texte,
      couleurFond: MboaColors.background,
      couleurTrait: MboaColors.primary,
      onTap: () => TtsService.instance.dire(texte),
    );
  }
}
