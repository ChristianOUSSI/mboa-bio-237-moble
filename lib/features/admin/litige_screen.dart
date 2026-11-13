import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/data/models/commande.dart';
import '../../core/data/models/statuts.dart';
import '../../core/design_system/boutons.dart';
import '../../core/design_system/carte.dart';
import '../../core/design_system/picto.dart';
import '../../core/design_system/photo.dart';
import '../../core/etat/providers.dart';
import '../../core/theme/mboa_colors.dart';
import '../../core/theme/mboa_typography.dart';
import '../../core/voice/note_vocale.dart';
import '../../core/voice/tts_service.dart';

/// Le traitement d'un litige de livraison.
///
/// La cliente a dit « problème » au moment de la réception. L'admin choisit
/// parmi quatre motifs dessinés, enregistre une note vocale si besoin, et
/// confirme. La commande passe en `recue` avec `satisfaction = probleme`,
/// sans être close : le litige reste ouvert jusqu'à ce que l'admin tranche.
class LitigeScreen extends ConsumerStatefulWidget {
  const LitigeScreen({required this.commande, super.key});

  final Commande commande;

  @override
  ConsumerState<LitigeScreen> createState() => _LitigeScreenState();
}

enum MotifLitige {
  produitManquant('Rien n\'est arrivé', 'Le panier n\'est pas arrivé ou est vide', Picto.basket, MotifReception.rienRecu),
  produitAbime('Produit abîmé', 'Un produit est endommagé ou périmé', Picto.alert, MotifReception.abime),
  quantiteFausse('Quantité incorrecte', 'Ce n\'est pas la bonne quantité', Picto.priceTag, MotifReception.quantite);

  const MotifLitige(this.libelle, this.detail, this.picto, this.motif);

  final String libelle;
  final String detail;
  final Picto picto;
  final MotifReception motif;
}

class _LitigeScreenState extends ConsumerState<LitigeScreen> {
  MotifLitige? _motif;
  String? _noteChemin;
  Uint8List? _noteOctets;
  bool _occupee = false;

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
      await TtsService.instance.dire('Raison enregistrée');
      return;
    }
    await note.enregistrer(dureeSecondes: 5);
  }

  Future<void> _confirmer() async {
    final motif = _motif;
    if (motif == null) return;

    setState(() => _occupee = true);
    try {
      // Le motif vocal reste attaché à la commande, pas à un produit :
      // la cliente parle du panier, pas d'une tomate isolée.
      await ref.read(depotCommandesProvider).confirmerReception(
            id: widget.commande.id,
            bon: false,
            motif: motif.motif,
            audioOctets: _noteOctets,
          );

      ref.invalidate(commandesAdminProvider);
      ref.invalidate(commandesClienteProvider);

      if (!mounted) return;
      await TtsService.instance.dire('Litige enregistré. ${motif.libelle}.');
      if (!mounted) return;
      Navigator.of(context).pop();
    } finally {
      if (mounted) setState(() => _occupee = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: MboaColors.background,
      appBar: AppBar(
        title: const Text('Litige de livraison'),
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
              couleurTrait: MboaColors.error,
              child: Row(
                children: [
                  const PictoIcon(Picto.alert, size: 48, couleur: MboaColors.error),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Devis ${widget.commande.id.split('-').first}', style: MboaTypo.titre()),
                        Text(
                          widget.commande.resumeQuantites,
                          style: MboaTypo.aide(),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            Text('Quel problème ?', style: MboaTypo.titre()),
            const SizedBox(height: 12),
            for (final motif in MotifLitige.values) ...[
              GrosBouton(
                titre: motif.libelle,
                picto: motif.picto,
                sousTitre: motif.detail,
                sombre: _motif == motif,
                minHeight: 96,
                onTap: () {
                  setState(() => _motif = motif);
                  TtsService.instance.dire(motif.libelle);
                },
              ),
              const SizedBox(height: 10),
            ],
            const SizedBox(height: 10),
            GrosBouton(
              titre: _noteOctets == null ? 'Dire la raison' : 'Raison enregistrée',
              picto: Picto.mic,
              sousTitre: 'Cinq secondes, optionnel',
              secondaire: true,
              minHeight: 96,
              onTap: _enregistrerRaison,
            ),
            if (_noteChemin != null) ...[
              const SizedBox(height: 10),
              GrosBouton(
                titre: 'Réécouter',
                picto: Picto.speaker,
                secondaire: true,
                onTap: () => ref.read(noteProvider).lire(_noteChemin!),
              ),
            ],
            const SizedBox(height: 22),
            GrosBouton(
              titre: 'Confirmer le litige',
              picto: Picto.trash,
              sousTitre: 'La commande reste ouverte',
              couleurFond: MboaColors.error,
              couleurTexte: MboaColors.surface,
              minHeight: 112,
              onTap: (_motif == null || _occupee) ? null : _confirmer,
            ),
          ],
        ),
      ),
    );
  }
}
