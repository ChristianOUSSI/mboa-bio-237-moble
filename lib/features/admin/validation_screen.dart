import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/data/models/commande.dart';
import '../../core/design_system/boutons.dart';
import '../../core/design_system/carte.dart';
import '../../core/design_system/photo.dart';
import '../../core/design_system/picto.dart';
import '../../core/design_system/tactile.dart';
import '../../core/etat/providers.dart';
import '../../core/theme/mboa_colors.dart';
import '../../core/theme/mboa_typography.dart';
import '../../core/utils/format_monnaie.dart';
import '../../core/voice/tts_service.dart';

/// La fiche de validation d'un devis.
///
/// L'admin voit une commande nouvelle et décide : la faire passer à
/// « validée » (le stock sort) ou la refuser (annulation, retour de stock).
///
/// Pas de filigrane, pas de prix conseillé : le prix est figé au moment du
/// devis, et la photo de la cliente est sa preuve, pas une publicité. La
/// marge se calcule côté base (`mboa.marge_devis`), pas côté app.
class ValidationScreen extends ConsumerStatefulWidget {
  const ValidationScreen({required this.commande, super.key});

  final Commande commande;

  @override
  ConsumerState<ValidationScreen> createState() => _ValidationScreenState();
}

class _ValidationScreenState extends ConsumerState<ValidationScreen> {
  bool _occupee = false;
  String? _message;
  bool _erreur = false;

  Future<void> _valider() async {
    setState(() {
      _occupee = true;
      _message = 'Validation en cours';
      _erreur = false;
    });

    try {
      await ref.read(depotCommandesProvider).valider(widget.commande.id);

      ref.invalidate(commandesAdminProvider);
      ref.invalidate(commandesClienteProvider);
      ref.invalidate(livraisonsAPointerProvider);

      if (!mounted) return;
      setState(() {
        _message = 'Devis validé. Le stock est sorti.';
      });
      await TtsService.instance.dire('Devis validé. La moto peut partir.');
      if (!mounted) return;
      await Future<void>.delayed(const Duration(milliseconds: 700));
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _erreur = true;
        _message = 'Validation impossible : $e';
      });
    } finally {
      if (mounted) setState(() => _occupee = false);
    }
  }

  Future<void> _refuser() async {
    setState(() {
      _occupee = true;
      _message = 'Annulation en cours';
      _erreur = false;
    });

    try {
      await ref.read(depotCommandesProvider).annuler(
            id: widget.commande.id,
            motif: 'Refusé par le comptoir',
          );

      ref.invalidate(commandesAdminProvider);
      ref.invalidate(commandesClienteProvider);
      ref.invalidate(vitrineProvider(null));

      if (!mounted) return;
      setState(() {
        _message = 'Devis refusé. Le stock est retourné.';
      });
      await TtsService.instance.dire('Devis refusé. Le stock est retourné.');
      if (!mounted) return;
      await Future<void>.delayed(const Duration(milliseconds: 700));
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _erreur = true;
        _message = 'Annulation impossible : $e';
      });
    } finally {
      if (mounted) setState(() => _occupee = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final commande = widget.commande;

    return Scaffold(
      backgroundColor: MboaColors.background,
      appBar: AppBar(
        title: Text('Devis ${commande.id.split('-').first}'),
        leading: IconButton(
          onPressed: () => Navigator.of(context).pop(),
          tooltip: 'Retour',
          iconSize: 36,
          icon: const PictoIcon(Picto.back, size: 36, couleur: MboaColors.surface),
        ),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(18, 16, 18, 26),
          children: [
            CarteBio(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: _Chiffre(
                          libelle: 'Montant',
                          valeur: formaterFcfaCourt(commande.montantTotal),
                        ),
                      ),
                      Expanded(
                        child: _Chiffre(
                          libelle: 'Coût d\'achat',
                          valeur: formaterFcfaCourt(commande.coutAchat),
                        ),
                      ),
                      Expanded(
                        child: _Chiffre(
                          libelle: 'Marge',
                          valeur: formaterFcfaCourt(commande.marge),
                          accent: true,
                        ),
                      ),
                    ],
                  ),
                  const Divider(height: 22),
                  ...commande.lignes.map((ligne) => Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: Row(
                          children: [
                            PhotoProduit(
                              chemin: ligne.photo,
                              categorie: ligne.categorie,
                              slug: ligne.slug,
                              libelle: ligne.nom,
                              cote: 56,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(ligne.nom, style: MboaTypo.corps()),
                                  Text(
                                    '${ligne.quantiteAffichee} · ${formaterFcfaCourt(ligne.sousTotal)}',
                                    style: MboaTypo.aide(),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      )),
                  if (commande.livraisonMoto) ...[
                    const Divider(height: 22),
                    Row(
                      children: [
                        const PictoIcon(Picto.moto, size: 30),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Livraison en moto',
                            style: MboaTypo.corps(),
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            if (_message != null) ...[
              const SizedBox(height: 16),
              BandeauEtat(
                texte: _message!,
                couleur: _erreur ? MboaColors.error : MboaColors.primary,
                icone: PictoIcon(
                  _erreur ? Picto.alert : Picto.sync,
                  size: 30,
                  couleur: _erreur ? MboaColors.error : MboaColors.primary,
                ),
              ),
            ],
            const SizedBox(height: 20),
            GrosBouton(
              titre: 'Valider le devis',
              picto: Picto.check,
              sousTitre: 'Le stock sort, la moto peut partir',
              sombre: !_occupee,
              minHeight: 112,
              onTap: _occupee ? null : _valider,
            ),
            const SizedBox(height: 14),
            GrosBouton(
              titre: 'Refuser',
              picto: Picto.trash,
              sousTitre: 'Annulation, retour de stock',
              couleurFond: MboaColors.error,
              couleurTexte: MboaColors.surface,
              minHeight: 96,
              onTap: _occupee ? null : _refuser,
            ),
          ],
        ),
      ),
    );
  }
}

class _Chiffre extends StatelessWidget {
  const _Chiffre({
    required this.libelle,
    required this.valeur,
    this.accent = false,
  });

  final String libelle;
  final String valeur;
  final bool accent;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(libelle, style: MboaTypo.aide()),
        Text(
          valeur,
          style: MboaTypo.chiffre(couleur: accent ? MboaColors.primary : MboaColors.text),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }
}
