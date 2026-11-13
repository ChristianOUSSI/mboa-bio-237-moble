import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/design_system/boutons.dart';
import '../../core/design_system/carte.dart';
import '../../core/design_system/picto.dart';
import '../../core/etat/providers.dart';
import '../../core/theme/mboa_colors.dart';
import '../../core/theme/mboa_typography.dart';
import '../../core/utils/format_monnaie.dart';
import '../../core/voice/tts_service.dart';
import 'signature_screen.dart';

/// Le troisieme geste de l'achat : confirmer, sans payer.
///
/// Remplace l'ancien ecran de paiement. Il n'y a plus de MoMo, plus d'Orange
/// Money, plus de reference a recopier : la regle est que la mama paie a la
/// porte, quand elle a la marchandise devant elle. Ce qui etait un formulaire
/// d'encaissement devient une question de logistique.
///
/// Trois informations, trois tailles :
///   * combien, en chiffres geants ;
///   * quand et comment, la moto ou le retrait ;
///   * un seul bouton, tout en bas, qui engage.
///
/// Le total est annonce a voix haute a l'entree. Une personne qui ne lit pas
/// doit savoir avant d'appuyer ce qu'elle va devoir preparer dans sa main.
class CommanderScreen extends ConsumerStatefulWidget {
  const CommanderScreen({super.key});

  @override
  ConsumerState<CommanderScreen> createState() => _CommanderScreenState();
}

class _CommanderScreenState extends ConsumerState<CommanderScreen> {
  bool _moto = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final panier = ref.read(panierProvider);
      TtsService.instance.dire(
        'Vous paierez ${formaterFcfa(panier.montantTotal)} quand la marchandise arrive.',
      );
    });
  }

  void _commander() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => SignatureScreen(livraisonMoto: _moto),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final panier = ref.watch(panierProvider);

    return Scaffold(
      backgroundColor: MboaColors.background,
      appBar: AppBar(
        title: const Text('Commander'),
        leading: IconButton(
          onPressed: () => Navigator.of(context).pop(),
          tooltip: 'Retour',
          iconSize: 36,
          icon: const PictoIcon(Picto.back, size: 36, couleur: MboaColors.surface),
        ),
      ),
      body: SafeArea(
        child: panier.vide
            ? Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const PictoIcon(Picto.basket, size: 96),
                    const SizedBox(height: 18),
                    Text('Panier vide', style: MboaTypo.titre()),
                  ],
                ),
              )
            : ListView(
                padding: const EdgeInsets.fromLTRB(18, 16, 18, 26),
                children: [
                  // Le total d'abord, et en plus grand que tout le reste :
                  // c'est la seule chose que la mama doit retenir.
                  CarteBio(
                    couleurFond: MboaColors.primary,
                    couleurTrait: MboaColors.primary,
                    padding: const EdgeInsets.fromLTRB(20, 22, 20, 20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'A presenter a la porte',
                          style: MboaTypo.corps(couleur: MboaColors.surface),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          formaterFcfa(panier.montantTotal),
                          style: MboaTypo.chiffreGeant(couleur: MboaColors.surface),
                        ),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            const PictoIcon(
                              Picto.especes,
                              size: 30,
                              couleur: MboaColors.secondary,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                'Le producteur est paye en especes, a la livraison',
                                style: MboaTypo.aide(couleur: MboaColors.surface),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
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
                              Text(panier.resumePourVoix, style: MboaTypo.titre()),
                              Text(
                                '${panier.count} produits · ${panier.resumeQuantites}',
                                style: MboaTypo.aide(),
                              ),
                            ],
                          ),
                        ),
                        BoutonVoix(texte: panier.resumePourVoix),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text('Comment vous l’avez ?', style: MboaTypo.titre()),
                  const SizedBox(height: 12),
                  GrosBouton(
                    titre: _moto ? 'Livré chez moi' : 'Je viens chercher',
                    picto: _moto ? Picto.moto : Picto.person,
                    sousTitre: _moto
                        ? 'La moto du village apporte le panier'
                        : 'Je passe au point de collecte',
                    sombre: true,
                    minHeight: 104,
                    onTap: () {
                      setState(() => _moto = !_moto);
                      TtsService.instance.dire(
                        _moto ? 'Livraison à moto' : 'Retrait au point de collecte',
                      );
                    },
                  ),
                  const SizedBox(height: 14),
                  BandeauEtat(
                    texte: 'Total à payer à la livraison : ${formaterFcfa(panier.montantTotal)}.',
                    couleur: MboaColors.primary,
                    icone: const PictoIcon(Picto.money, size: 30),
                  ),
                  const SizedBox(height: 22),
                  GrosBouton(
                    titre: 'Commander',
                    picto: Picto.check,
                    sombre: true,
                    minHeight: 112,
                    sousTitre: 'Je paie à la livraison',
                    onTap: _commander,
                  ),
                ],
              ),
      ),
    );
  }
}
