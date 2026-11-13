import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/data/models/achat.dart';
import '../../core/design_system/boutons.dart';
import '../../core/design_system/carte.dart';
import '../../core/design_system/picto.dart';
import '../../core/design_system/photo.dart';
import '../../core/etat/providers.dart';
import '../../core/theme/mboa_colors.dart';
import '../../core/theme/mboa_typography.dart';
import '../../core/utils/format_monnaie.dart';
import '../../core/voice/note_vocale.dart';

/// Ce que le comptoir a acheté à l'agriculteur, et ce qu'il doit encore.
///
/// Deux chiffres en haut, puis les propositions du plus récent au plus ancien.
/// Un achat et un paiement ne se confondent pas : une marchandise achetée et
/// pas encore payée reste visible avec son argent dû. C'est la seule façon de
/// pouvoir répondre à « où est mon argent ? » sans mentir.
class MesAchatsScreen extends ConsumerWidget {
  const MesAchatsScreen({super.key});

  Future<void> _rafraichir(WidgetRef ref) async {
    ref.invalidate(mesAchatsProvider);
    ref.invalidate(mesGainsProvider);
    await ref.read(mesAchatsProvider.future);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final achats = ref.watch(mesAchatsProvider);
    final gains = ref.watch(mesGainsProvider).valueOrNull ?? const <String, int>{};

    return Scaffold(
      backgroundColor: MboaColors.background,
      appBar: AppBar(
        title: const Text('Mes achats'),
        leading: IconButton(
          onPressed: () => Navigator.of(context).pop(),
          tooltip: 'Retour',
          iconSize: 36,
          icon: const PictoIcon(Picto.back, size: 36, couleur: MboaColors.surface),
        ),
      ),
      body: SafeArea(
        child: RefreshIndicator(
          color: MboaColors.primary,
          onRefresh: () => _rafraichir(ref),
          child: achats.maybeWhen(
            data: (liste) => ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(18, 16, 18, 28),
              children: [
                _Gains(gains: gains),
                const SizedBox(height: 18),
                if (liste.isEmpty)
                  const _AucunAchat()
                else
                  for (final achat in liste) ...[
                    _CarteAchat(achat: achat),
                    const SizedBox(height: 14),
                  ],
              ],
            ),
            orElse: () => ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              children: const [
                SizedBox(height: 180),
                Center(child: CircularProgressIndicator(color: MboaColors.primary)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Les deux seuls chiffres qui comptent pour un producteur : ce qui est déjà
/// sorti, et ce qui doit encore sortir.
class _Gains extends StatelessWidget {
  const _Gains({required this.gains});

  final Map<String, int> gains;

  @override
  Widget build(BuildContext context) {
    return CarteBio(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: _Gain(
              picto: Picto.check,
              libelle: 'Déjà payé',
              montant: gains['paye'] ?? 0,
            ),
          ),
          Container(
            width: 2,
            height: 74,
            color: MboaColors.trait,
          ),
          const SizedBox(width: 14),
          Expanded(
            child: _Gain(
              picto: Picto.clock,
              libelle: 'À recevoir',
              montant: gains['en_attente'] ?? 0,
            ),
          ),
        ],
      ),
    );
  }
}

class _Gain extends StatelessWidget {
  const _Gain({
    required this.picto,
    required this.libelle,
    required this.montant,
  });

  final Picto picto;
  final String libelle;
  final int montant;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            PictoIcon(picto, size: 28),
            const SizedBox(width: 8),
            Expanded(child: Text(libelle, style: MboaTypo.aide(couleur: MboaColors.text))),
          ],
        ),
        const SizedBox(height: 4),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(formaterFcfaCourt(montant), style: MboaTypo.chiffre()),
        ),
      ],
    );
  }
}

class _CarteAchat extends ConsumerWidget {
  const _CarteAchat({required this.achat});

  final Achat achat;

  String get _annonce {
    final morceau = '${achat.annonce}. ${achat.statut.annonce}.';
    final motif = achat.motif;
    return motif == null || motif.isEmpty ? morceau : '$morceau Raison : $motif.';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final (fond, teinte, picto) = switch (achat.statut) {
      StatutAchat.propose => (MboaColors.primaryDoux, MboaColors.primary, Picto.clock),
      StatutAchat.valide => (MboaColors.secondaryDoux, MboaColors.primary, Picto.check),
      StatutAchat.paye => (MboaColors.primary, MboaColors.surface, Picto.money),
      StatutAchat.litige => (MboaColors.errorDoux, MboaColors.error, Picto.alert),
      StatutAchat.annule => (MboaColors.errorDoux, MboaColors.error, Picto.close),
    };

    return CarteBio(
      couleurTrait: achat.statut == StatutAchat.litige ? MboaColors.error : MboaColors.trait,
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              PhotoProduit(
                chemin: achat.photoUrl,
                categorie: achat.categorie,
                slug: achat.slug,
                libelle: achat.nom,
                cote: 88,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(achat.nom, style: MboaTypo.titre()),
                    Text(achat.unite.avec(achat.quantite), style: MboaTypo.corps()),
                    const SizedBox(height: 4),
                    _Pastille(texte: achat.statut.libelle, fond: fond, teinte: teinte, picto: picto),
                  ],
                ),
              ),
              BoutonVoix(texte: _annonce),
            ],
          ),
          const Divider(height: 22),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      achat.statut.estPayee
                          ? 'Payé'
                          : achat.statut.estPrise
                              ? 'Acheté'
                              : 'Demandé',
                      style: MboaTypo.aide(couleur: MboaColors.text),
                    ),
                    Text(
                      formaterFcfa(achat.montant),
                      style: MboaTypo.chiffre(),
                    ),
                  ],
                ),
              ),
              if (achat.prixMarchand != null && achat.prixMarchand != achat.prixDemande)
                Text(
                  'Tu demandais ${formaterFcfaCourt(achat.prixDemande)}',
                  style: MboaTypo.aide(couleur: MboaColors.textDoux),
                ),
            ],
          ),
          if (achat.motif != null && achat.motif!.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              'Raison : ${achat.motif}',
              style: MboaTypo.corps(couleur: MboaColors.error),
            ),
            if (achat.motifAudioUrl != null)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: BoutonCarre(
                  picto: Picto.speaker,
                  annonce: 'Écouter la raison du refus',
                  onTap: () => NoteVocaleService.instance.lire(achat.motifAudioUrl!),
                ),
              ),
          ],
          if (achat.proposeLe != null) ...[
            const SizedBox(height: 8),
            Text(
              'Proposé le ${_jourAchat(achat.proposeLe)}',
              style: MboaTypo.aide(couleur: MboaColors.textDoux),
            ),
          ],
        ],
      ),
    );
  }
}

class _Pastille extends StatelessWidget {
  const _Pastille({
    required this.texte,
    required this.fond,
    required this.teinte,
    required this.picto,
  });

  final String texte;
  final Color fond;
  final Color teinte;
  final Picto picto;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: fond,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          PictoIcon(picto, size: 22, couleur: teinte),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              texte,
              style: MboaTypo.aide(couleur: teinte),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

class _AucunAchat extends StatelessWidget {
  const _AucunAchat();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 44),
      child: Column(
        children: [
          const PictoIcon(Picto.basket, size: 96),
          const SizedBox(height: 18),
          Text('Aucun achat', style: MboaTypo.titre(), textAlign: TextAlign.center),
          const SizedBox(height: 10),
          Text(
            'Propose ta récolte : le comptoir la regarde et te répond',
            style: MboaTypo.aide(couleur: MboaColors.text),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

String _jourAchat(DateTime? valeur) {
  if (valeur == null) return '';
  final jour = valeur.day.toString().padLeft(2, '0');
  final mois = valeur.month.toString().padLeft(2, '0');
  return '$jour/$mois/${valeur.year}';
}
