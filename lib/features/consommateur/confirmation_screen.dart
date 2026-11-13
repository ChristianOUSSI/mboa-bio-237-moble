import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/data/models/categorie.dart';
import '../../core/data/models/commande.dart';
import '../../core/data/models/statuts.dart';
import '../../core/design_system/boutons.dart';
import '../../core/design_system/carte.dart';
import '../../core/design_system/picto.dart';
import '../../core/design_system/photo.dart';
import '../../core/etat/providers.dart';
import '../../core/theme/mboa_colors.dart';
import '../../core/theme/mboa_typography.dart';
import '../../core/utils/format_monnaie.dart';
import '../../core/voice/note_vocale.dart';
import '../../core/voice/tts_service.dart';

/// Le message court promis apres chaque livraison.
///
/// Une phrase, lue a voix haute a l'entree. Deux pouces, a 96 px. Rien
/// d'autre a cet instant : pas de resume, pas de numer de commande, pas de
/// bouton « voir les details ». Une femme de 60 ans qui vient de recevoir sa
/// papaye a autre chose a faire que comprendre une interface.
///
/// Le pouce baisse n'est pas une note. C'est une porte : il deplie trois
/// motifs dessines et la possibility de les dire avec sa voix, et il laisse
/// la commande ouverte. Rien n'est du tant que le desaccord n'est pas tranche
/// par l'admin.
class ConfirmationScreen extends ConsumerStatefulWidget {
  const ConfirmationScreen({required this.commande, super.key});

  final Commande commande;

  @override
  ConsumerState<ConfirmationScreen> createState() => _ConfirmationScreenState();
}

class _ConfirmationScreenState extends ConsumerState<ConfirmationScreen> {
  /// Vrai des que la cliente a touche le pouce baisse : l'ecran bascule sur
  /// les trois motifs. Ce n'est pas encore une reponse.
  bool _signale = false;

  /// La reponse definitive, posee par le bouton d'envoi ou par le pouce leve.
  Satisfaction? _reponse;

  MotifReception? _motif;
  String? _noteChemin;
  Uint8List? _noteOctets;
  bool _occupee = false;
  bool _fini = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      TtsService.instance.dire(widget.commande.messageConfirmation);
    });
  }

  Future<void> _repondre(Satisfaction satisfaction) async {
    setState(() {
      _reponse = satisfaction;
      _occupee = true;
    });

    await ref.read(depotCommandesProvider).confirmerReception(
          id: widget.commande.id,
          bon: satisfaction.estBon,
          motif: satisfaction.estBon ? null : _motif,
          audioOctets: _noteOctets,
        );

    ref.invalidate(commandesClienteProvider);
    ref.invalidate(aConfirmerProvider);
    ref.invalidate(confirmationsAttenteProvider);

    if (!mounted) return;
    setState(() {
      _occupee = false;
      _fini = true;
    });

    await TtsService.instance.dire(satisfaction.estBon
        ? 'Merci. C’est fermé.'
        : 'Mboa est prévenu. On vous rappelle.');

    if (!mounted) return;
    await Future<void>.delayed(const Duration(milliseconds: 900));
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _enregistrerRaison() async {
    final note = ref.read(noteProvider);
    if (note.enCours) {
      final chemin = await note.couper();
      if (chemin == null || !mounted) return;
      final octets = await File(chemin).readAsBytes();
      if (!mounted) return;
      setState(() {
        _noteChemin = chemin;
        _noteOctets = octets;
      });
      await TtsService.instance.dire('C’est enregistré');
      return;
    }
    await note.enregistrer(dureeSecondes: 5);
  }

  @override
  Widget build(BuildContext context) {
    final commande = widget.commande;

    return Scaffold(
      backgroundColor: MboaColors.background,
      body: SafeArea(
        child: _occupee || _fini
            ? Center(
                child: _fini
                    ? const PictoIcon(Picto.check, size: 120)
                    : const CircularProgressIndicator(color: MboaColors.primary),
              )
            : Padding(
                padding: const EdgeInsets.fromLTRB(20, 26, 20, 26),
                child: _corps(commande),
              ),
      ),
    );
  }

  Widget _corps(Commande commande) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Ce qu'elle a recu, en une image et un chiffre. Pas la liste
        // complete : la photo du panier suffit a reconnaitre.
        Center(
          child: PhotoProduit(
            chemin: commande.lignes.isEmpty ? '' : commande.lignes.first.photo,
            categorie: commande.lignes.isEmpty ? Categorie.fruit : commande.lignes.first.categorie,
            slug: commande.lignes.isEmpty ? null : commande.lignes.first.slug,
            libelle: commande.lignes.isEmpty ? null : commande.lignes.first.nom,
            cote: 150,
          ),
        ),
        const SizedBox(height: 24),
        Text(
          commande.messageConfirmation,
          style: MboaTypo.ecran(),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 10),
        Text(
          'Vous avez payé ${formaterFcfa(commande.montantLivre ?? commande.montantTotal)}',
          style: MboaTypo.corps(couleur: MboaColors.textDoux),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 28),
        if (!_signale) ...[
          _Pouce(
            satisfaction: Satisfaction.bon,
            onTap: () => _repondre(Satisfaction.bon),
          ),
          _Pouce(
            satisfaction: Satisfaction.probleme,
            onTap: () {
              setState(() => _signale = true);
              TtsService.instance.dire('Quel problème ? Choisissez une image.');
            },
          ),
        ] else ...[
          Text('Quel problème ?', style: MboaTypo.titre(), textAlign: TextAlign.center),
          const SizedBox(height: 12),
          for (final motif in MotifReception.values) ...[
            GrosBouton(
              titre: motif.libelle,
              picto: motif.picto,
              sombre: _motif == motif,
              minHeight: 88,
              onTap: () {
                setState(() => _motif = motif);
                TtsService.instance.dire(motif.libelle);
              },
            ),
            const SizedBox(height: 10),
          ],
          GrosBouton(
            titre: _noteOctets == null ? 'Le dire' : 'Raison enregistrée',
            picto: Picto.mic,
            secondaire: true,
            minHeight: 88,
            onTap: _enregistrerRaison,
          ),
          const SizedBox(height: 14),
          GrosBouton(
            titre: 'Envoyer',
            picto: Picto.check,
            sombre: _motif != null,
            minHeight: 96,
            onTap: _motif == null ? null : () => _repondre(Satisfaction.probleme),
          ),
          GrosBouton(
            titre: 'Finalement, tout est bon',
            picto: Picto.pouceLeve,
            secondaire: true,
            minHeight: 88,
            onTap: () => setState(() => _signale = false),
          ),
        ],
      ],
    );
  }
}

/// Le pouce, a la taille d'une main.
///
/// 96 px et non 72 : c'est la seule cible que l'on presse en tenant un panier
/// de l'autre bras. La charte donne un minimum, pas une consigne.
class _Pouce extends StatelessWidget {
  const _Pouce({required this.satisfaction, required this.onTap});

  final Satisfaction satisfaction;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final probleme = !satisfaction.estBon;

    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: GrosBouton(
        titre: satisfaction.libelle,
        image: PictoIcon(
          satisfaction.picto,
          size: 64,
          couleur: probleme ? MboaColors.error : MboaColors.primary,
          label: satisfaction.annonceAuProducteur,
        ),
        // Le pouce leve est sombre : c'est la reponse attendue, et la seule
        // que l'on veut voir en vert. Le pouce baisse reste clair avec son
        // trait rouge, pour ne pas crier une nuisance.
        sombre: !probleme,
        couleurFond: probleme ? MboaColors.surface : null,
        couleurTrait: probleme ? MboaColors.error : null,
        minHeight: 96,
        annonce: satisfaction.libelle,
        onTap: onTap,
      ),
    );
  }
}
