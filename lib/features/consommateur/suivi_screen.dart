import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/data/models/commande.dart';
import '../../core/data/models/statuts.dart';
import '../../core/design_system/boutons.dart';
import '../../core/design_system/carte.dart';
import '../../core/design_system/picto.dart';
import '../../core/design_system/photo.dart';
import '../../core/design_system/tactile.dart';
import '../../core/etat/providers.dart';
import '../../core/theme/mboa_colors.dart';
import '../../core/theme/mboa_typography.dart';
import '../../core/utils/format_monnaie.dart';
import '../../core/voice/tts_service.dart';
import '../commun/suivi_colis_screen.dart';
import 'confirmation_screen.dart';

/// Le suivi : quatre icones qui s'allument.
///
///   panier -> coche Mboa -> moto -> main qui remet
///
/// Une seule icone est lisible par une personne qui ne sait pas lire : la
/// forme. Les mots dessous sont pour la fille qui aide. L'icone en cours
/// pulse, les suivantes sont grises, les precedentes sont pleines : on voit
/// d'un coup d'oeil ou on est, sans compter.
///
/// L'ecran se rafraichit tout seul quand l'admin ou le producteur fait
/// avancer la commande : c'est l'evenement temps reel qui le déclenche.
class SuiviScreen extends ConsumerStatefulWidget {
  const SuiviScreen({required this.commande, super.key});

  final Commande commande;

  @override
  ConsumerState<SuiviScreen> createState() => _SuiviScreenState();
}

class _SuiviScreenState extends ConsumerState<SuiviScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      TtsService.instance.dire(widget.commande.statut.annonce);
    });
  }

  /// Appeler le moto.
  ///
  /// Le numero ne vient pas de la commande : il sort de l'RPC
  /// `mboa.contact_livreur`, qui ne le rend qu'aux parties a la course. Une
  /// cliente appelle son livreur, elle n'en consulte pas la liste.
  Future<void> _appelerLivreur(WidgetRef ref) async {
    final numero = await ref.read(depotLivreursProvider).contact(widget.commande.id);
    if (numero == null || numero.isEmpty) {
      await TtsService.instance.dire('Le numéro du livreur n’est pas encore disponible');
      return;
    }
    await mboaTactile(annonce: 'J’appelle le livreur');
    if (!await launchUrl(Uri.parse('tel:$numero'))) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Appel impossible : $numero')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    // La commande relue de la base a preséance : c'est elle qui porte le
    // statut le plus recent, pousse par le temps reel.
    final reloades = ref.watch(commandesClienteProvider).valueOrNull;
    Commande? fraiche;
    for (final c in reloades ?? const <Commande>[]) {
      if (c.id == widget.commande.id) {
        fraiche = c;
        break;
      }
    }
    final commande = fraiche ?? widget.commande;

    final attend = commande.attendConfirmation;

    return Scaffold(
      backgroundColor: MboaColors.background,
      appBar: AppBar(
        title: const Text('Ma commande'),
        leading: IconButton(
          onPressed: () => Navigator.of(context).pop(),
          tooltip: 'Retour',
          iconSize: 36,
          icon: const PictoIcon(Picto.back, size: 36, couleur: MboaColors.surface),
        ),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(18, 18, 18, 28),
          children: [
            // La question de la reception passe avant tout le reste : c'est
            // la seule chose que l'app a a lui demander aujourd'hui.
            if (attend) ...[
              CarteBio(
                couleurFond: MboaColors.primary,
                couleurTrait: MboaColors.primary,
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      commande.messageConfirmation,
                      style: MboaTypo.titre(couleur: MboaColors.surface),
                    ),
                    const SizedBox(height: 14),
                    GrosBouton(
                      titre: 'Répondre',
                      picto: Picto.pouceLeve,
                      minHeight: 88,
                      couleurFond: MboaColors.surface,
                      couleurTexte: MboaColors.primary,
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (context) => ConfirmationScreen(commande: commande),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),
            ],
            // Le moto qui arrive. La plaque est plus grande que le nom :
            // c'est le repere qu'une personne agee verifie avant d'ouvrir,
            // et le seul que le livreur peut lui montrer sans descendre.
            if (commande.aUnLivreur &&
                (commande.statut == StatutCommande.enLivraison ||
                    commande.statut == StatutCommande.livree)) ...[
              CarteBio(
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        PhotoRonde(
                          chemin: commande.livreurPhoto ?? '',
                          cote: 72,
                          quandAbsente: Picto.moto,
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Qui arrive', style: MboaTypo.aide()),
                              Text(commande.livreurNom ?? 'Le livreur', style: MboaTypo.titre()),
                              if (commande.livreurPlaque != null &&
                                  commande.livreurPlaque!.isNotEmpty)
                                Text(commande.livreurPlaque!, style: MboaTypo.chiffreGeant()),
                              // Le prix de la course se paie a part, en main
                              // propre au moto. Le devis papier le porte deja :
                              // l'ecran doit dire la meme chose que le papier.
                              if ((commande.livreurTarif ?? 0) > 0)
                                Text(
                                  'La course : ${formaterFcfa(commande.livreurTarif!)} à payer au livreur',
                                  style: MboaTypo.aide(couleur: MboaColors.text),
                                ),
                            ],
                          ),
                        ),
                        BoutonVoix(texte: commande.livreurAnnonce),
                      ],
                    ),
                    const SizedBox(height: 12),
                    GrosBouton(
                      titre: 'Appeler le livreur',
                      picto: Picto.phone,
                      secondaire: true,
                      minHeight: 88,
                      onTap: () => _appelerLivreur(ref),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),
            ],
            CarteBio(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 20),
              child: Row(
                children: [
                  const PictoIcon(Picto.basket, size: 40),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(commande.statut.libelle, style: MboaTypo.titre()),
                  ),
                  Text(
                    formaterFcfa(commande.montantTotal),
                    style: MboaTypo.chiffre(),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            TimelineColis(commandeId: commande.id),
            const SizedBox(height: 18),
            CarteBio(
              child: Row(
                children: [
                  const PictoIcon(Picto.leaf, size: 36),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(commande.resumeProduits, style: MboaTypo.titre()),
                        Text(
                          '${commande.resumeQuantites} · '
                          '${commande.paiement?.libelle ?? 'paiement à confirmer'}',
                          style: MboaTypo.aide(),
                        ),
                      ],
                    ),
                  ),
                  BoutonVoix(texte: '${commande.resumeProduits}. ${commande.statut.annonce}.'),
                ],
              ),
            ),
            const SizedBox(height: 18),
            const SizedBox(height: 14),
            GrosBouton(
              titre: 'Mes commandes',
              picto: Picto.basket,
              secondaire: true,
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (context) => const MesCommandesScreen()),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// L'historique des commandes de la cliente.
class MesCommandesScreen extends ConsumerWidget {
  const MesCommandesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final commandes = ref.watch(commandesClienteProvider);

    return Scaffold(
      backgroundColor: MboaColors.background,
      appBar: AppBar(
        title: const Text('Mes commandes'),
        leading: IconButton(
          onPressed: () => Navigator.of(context).pop(),
          tooltip: 'Retour',
          iconSize: 36,
          icon: const PictoIcon(Picto.back, size: 36, couleur: MboaColors.surface),
        ),
      ),
      body: SafeArea(
        child: commandes.maybeWhen(
          data: (liste) {
            if (liste.isEmpty) {
              return Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const PictoIcon(Picto.basket, size: 96),
                    const SizedBox(height: 18),
                    Text('Aucune commande', style: MboaTypo.titre()),
                  ],
                ),
              );
            }
            return ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
              itemCount: liste.length,
              separatorBuilder: (context, index) => const SizedBox(height: 12),
              itemBuilder: (context, index) {
                final commande = liste[index];
                return CarteBio(
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (context) => SuiviScreen(commande: commande),
                    ),
                  ),
                  child: Row(
                    children: [
                      PictoPastille(
                        picto: commande.clos ? Picto.pouceLeve : commande.statut.jalonPicto,
                        diametre: 64,
                        allume: commande.statut != StatutCommande.nouvelle,
                        couleurFond: commande.clos ? MboaColors.primary : null,
                        couleurTrait: commande.clos ? MboaColors.primary : null,
                        couleurIcone: commande.clos ? MboaColors.surface : null,
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(commande.resumeProduits, style: MboaTypo.titre()),
                            Text(commande.statut.annonce, style: MboaTypo.aide()),
                          ],
                        ),
                      ),
                      Text(
                        formaterFcfaCourt(commande.montantTotal),
                        style: MboaTypo.chiffre(),
                      ),
                    ],
                  ),
                );
              },
            );
          },
          orElse: () => const Center(
            child: CircularProgressIndicator(color: MboaColors.primary),
          ),
        ),
      ),
    );
  }
}
