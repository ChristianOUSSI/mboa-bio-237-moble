import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/data/models/commande.dart';
import '../../core/data/models/statuts.dart';
import '../../core/design_system/boutons.dart';
import '../../core/design_system/carte.dart';
import '../../core/design_system/picto.dart';
import '../../core/etat/providers.dart';
import '../../core/theme/mboa_colors.dart';
import '../../core/theme/mboa_typography.dart';
import '../../core/utils/format_monnaie.dart';
import 'validation_screen.dart';

/// Les devis qui attendent une decision du comptoir.
///
/// Un devis nouveau n'a pas encore touche le stock : c'est la validation qui
/// le fait sortir. L'admin ouvre la fiche, voit ce qui est demande et ce que
/// la vente rapporte, puis valide ou refuse. Un refus retourne le stock, un
/// oubli le bloque : d'ou le compteur en haut de l'ecran.
class DevisScreen extends ConsumerWidget {
  const DevisScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final commandes = ref.watch(commandesAdminProvider);

    return Scaffold(
      backgroundColor: MboaColors.background,
      appBar: AppBar(
        title: const Text('Devis à valider'),
        leading: IconButton(
          onPressed: () => Navigator.of(context).pop(),
          tooltip: 'Retour',
          iconSize: 36,
          icon: const PictoIcon(Picto.back, size: 36, couleur: MboaColors.surface),
        ),
        actions: [
          IconButton(
            onPressed: () => ref.invalidate(commandesAdminProvider),
            tooltip: 'Rafraîchir',
            iconSize: 34,
            icon: const PictoIcon(Picto.sync, size: 34, couleur: MboaColors.surface),
          ),
        ],
      ),
      body: SafeArea(
        child: RefreshIndicator(
          color: MboaColors.primary,
          onRefresh: () async {
            ref.invalidate(commandesAdminProvider);
            await ref.read(commandesAdminProvider.future);
          },
          child: commandes.maybeWhen(
            data: (liste) {
              final nouvelles = liste
                  .where((c) => c.statut == StatutCommande.nouvelle)
                  .toList(growable: false);

              if (nouvelles.isEmpty) {
                return ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  children: const [
                    SizedBox(height: 120),
                    _Vide(),
                  ],
                );
              }

              return ListView.separated(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 28),
                itemCount: nouvelles.length,
                separatorBuilder: (context, index) => const SizedBox(height: 14),
                itemBuilder: (context, index) => _CarteDevis(commande: nouvelles[index]),
              );
            },
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

class _CarteDevis extends StatelessWidget {
  const _CarteDevis({required this.commande});

  final Commande commande;

  String get _annonce {
    final lignes = commande.lignes.length;
    return 'Devis ${commande.id.split('-').first}, '
        '$lignes ligne${lignes > 1 ? 's' : ''}, '
        '${formaterFcfa(commande.montantTotal)}.';
  }

  @override
  Widget build(BuildContext context) {
    return CarteBio(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              PictoPastille(
                picto: commande.statut.jalonPicto,
                diametre: 62,
                allume: true,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(commande.resumeProduits, style: MboaTypo.titre()),
                    Text(
                      commande.resumeQuantites,
                      style: MboaTypo.aide(couleur: MboaColors.text),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      'Reçu le ${_jourDevis(commande.createdLe)}',
                      style: MboaTypo.aide(couleur: MboaColors.textDoux),
                    ),
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
                    Text('Montant', style: MboaTypo.aide(couleur: MboaColors.text)),
                    Text(
                      formaterFcfa(commande.montantTotal),
                      style: MboaTypo.chiffre(),
                    ),
                  ],
                ),
              ),
              if (commande.livraisonMoto)
                const PictoIcon(Picto.moto, size: 34),
            ],
          ),
          const SizedBox(height: 12),
          GrosBouton(
            titre: 'Ouvrir le devis',
            picto: Picto.check,
            sousTitre: 'Valider, le stock sortira',
            sombre: true,
            minHeight: 92,
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (context) => ValidationScreen(commande: commande),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Vide extends StatelessWidget {
  const _Vide();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 34),
      child: Column(
        children: [
          const PictoIcon(Picto.check, size: 96),
          const SizedBox(height: 18),
          Text('Aucun devis en attente', style: MboaTypo.titre(), textAlign: TextAlign.center),
          const SizedBox(height: 10),
          Text(
            'Les devis validés passent dans les livraisons à pointer',
            style: MboaTypo.aide(couleur: MboaColors.text),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

String _jourDevis(DateTime valeur) {
  final jour = valeur.day.toString().padLeft(2, '0');
  final mois = valeur.month.toString().padLeft(2, '0');
  return '$jour/$mois/${valeur.year}';
}
