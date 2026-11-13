import 'package:flutter/material.dart';

import '../theme/mboa_colors.dart';

/// Carte de surface : le contenant de presque tout l'app.
///
/// Le filet de 2 px remplace l'ombre portee sur les ecrans clairs : sur un
/// Tecno a luminosite maximale en plein soleil, une ombre de 10 % disparait,
/// un trait de 2 px non.
class CarteBio extends StatelessWidget {
  const CarteBio({
    required this.child,
    this.couleurFond,
    this.couleurTrait,
    this.padding = const EdgeInsets.all(18),
    this.onTap,
    this.largeur,
    super.key,
  });

  final Widget child;
  final Color? couleurFond;
  final Color? couleurTrait;
  final EdgeInsets padding;
  final VoidCallback? onTap;
  final double? largeur;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: largeur,
      decoration: BoxDecoration(
        color: couleurFond ?? MboaColors.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: couleurTrait ?? MboaColors.trait, width: 2),
        boxShadow: const [BoxShadow(color: MboaColors.ombre, blurRadius: 8, offset: Offset(0, 3))],
      ),
      clipBehavior: Clip.antiAlias,
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: onTap,
          child: Padding(padding: padding, child: child),
        ),
      ),
    );
  }
}

/// Titre de section, precede d'une pastille : jamais de paragraphe d'intro.
class SectionTitre extends StatelessWidget {
  const SectionTitre({required this.titre, this.icone, this.droite, super.key});

  final String titre;
  final Widget? icone;
  final Widget? droite;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        if (icone != null) ...[icone!, const SizedBox(width: 12)],
        Expanded(child: Text(titre, style: Theme.of(context).textTheme.titleLarge)),
        if (droite != null) droite!,
      ],
    );
  }
}

/// Bandeau d'etat : hors connexion, envoi en attente, erreur de caisse.
///
/// Il ne se remplace jamais par un toast : un toast disparait pendant que
/// l'utilisateur cherche son telephone des deux mains.
class BandeauEtat extends StatelessWidget {
  const BandeauEtat({
    required this.texte,
    required this.couleur,
    this.icone,
    this.action,
    super.key,
  });

  final String texte;
  final Color couleur;
  final Widget? icone;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: couleur.withOpacity(0.10),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: couleur, width: 2),
      ),
      child: Row(
        children: [
          if (icone != null) ...[icone!, const SizedBox(width: 12)],
          Expanded(
            child: Text(
              texte,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: couleur),
            ),
          ),
          if (action != null) action!,
        ],
      ),
    );
  }
}
