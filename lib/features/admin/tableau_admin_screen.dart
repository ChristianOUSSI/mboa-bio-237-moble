import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/data/models/repere.dart';
import '../../core/data/models/statuts.dart';
import '../../core/design_system/boutons.dart';
import '../../core/design_system/carte.dart';
import '../../core/design_system/picto.dart';
import '../../core/etat/providers.dart';
import '../../core/theme/mboa_colors.dart';
import '../../core/theme/mboa_typography.dart';
import '../../core/voice/tts_service.dart';
import '../auth/connexion_screen.dart';
import 'achats_screen.dart';
import 'bilan_screen.dart';
import 'carte_cameroun.dart';
import 'devis_screen.dart';
import 'fournisseurs_screen.dart';
import 'livraison_screen.dart';
import 'livreurs_screen.dart';
import 'packs_screen.dart';
import 'prix_screen.dart';
import 'stock_admin_screen.dart';

/// Le poste de travail du comptoir.
///
/// Deux zones, dans le sens de la journee : la carte en haut pour savoir
/// d'ou vient l'offre, les livraisons en bas pour pointer ce qui est parti.
/// L'admin ne choisit plus ce qu'il valide : il achete, il revend, il livre.
///
/// La carte est repliee par defaut. Sur un ecran de telephone, deux zones
/// qui se disputent la hauteur finissent par n'en rendre aucune utilisable :
/// le repli est le compromis, pas la paresse.
class TableauAdminScreen extends ConsumerStatefulWidget {
  const TableauAdminScreen({super.key});

  static const String nom = '/admin';

  @override
  ConsumerState<TableauAdminScreen> createState() => _TableauAdminScreenState();
}

class _TableauAdminScreenState extends ConsumerState<TableauAdminScreen> {
  bool _carteOuverte = false;
  RepereVillage? _choisi;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      TtsService.instance.dire(
        'Comptoir. Trois chiffres : les devis à valider, les récoltes à signer, les livraisons à pointer.',
      );
    });
  }

  Future<void> _quitter() async {
    await TtsService.instance.dire('À bientôt');
    await ref.read(sessionProvider.notifier).deconnexion();
    if (!mounted) return;
    Navigator.of(context).pushNamedAndRemoveUntil(ConnexionScreen.nom, (route) => false);
  }

  @override
  Widget build(BuildContext context) {
    final commandes = ref.watch(commandesAdminProvider).valueOrNull ?? const [];
    final aValider = commandes.where((c) => c.statut == StatutCommande.nouvelle).length;
    final aPointer = commandes
        .where((c) =>
            c.statut == StatutCommande.valideeAdmin || c.statut == StatutCommande.enLivraison)
        .length;
    final aSigner = ref.watch(achatsEnAttenteProvider).valueOrNull?.length ?? 0;
    final repere = ref.watch(repereProvider).valueOrNull ?? const <RepereVillage>[];

    return Scaffold(
      backgroundColor: MboaColors.background,
      appBar: AppBar(
        title: const Text('Comptoir MBOA'),
        actions: [
          IconButton(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (context) => const StockAdminScreen()),
            ),
            tooltip: 'Stock et marges',
            iconSize: 34,
            icon: const PictoIcon(Picto.basket, size: 34, couleur: MboaColors.surface),
          ),
          IconButton(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (context) => const PacksScreen()),
            ),
            tooltip: 'Packs de plats',
            iconSize: 34,
            icon: const PictoIcon(Picto.leaf, size: 34, couleur: MboaColors.surface),
          ),
          IconButton(
            onPressed: _quitter,
            tooltip: 'Se déconnecter',
            iconSize: 34,
            icon: const PictoIcon(Picto.close, size: 34, couleur: MboaColors.surface),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _Compteurs(
              aValider: aValider,
              aSigner: aSigner,
              aPointer: aPointer,
              onDevis: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (context) => const DevisScreen()),
              ),
              onAchats: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (context) => const AchatsScreen()),
              ),
              onLivraisons: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (context) => const LivraisonScreen()),
              ),
            ),
            const SizedBox(height: 10),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: _Raccourci(
                          libelle: 'Fournisseurs',
                          picto: Picto.person,
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute(builder: (context) => const FournisseursScreen()),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _Raccourci(
                          libelle: 'Livreurs',
                          picto: Picto.moto,
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute(builder: (context) => const LivreursScreen()),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: _Raccourci(
                          libelle: 'Bilan',
                          picto: Picto.money,
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute(builder: (context) => const BilanScreen()),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _Raccourci(
                          libelle: 'Prix du marché',
                          picto: Picto.priceTag,
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute(builder: (context) => const PrixScreen()),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            if (_carteOuverte) ...[
              const SizedBox(height: 10),
              CarteBio(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
                child: Column(
                  children: [
                    SizedBox(
                      height: 232,
                      child: CarteCameroun(
                        repere: repere,
                        choisi: _choisi,
                        onChoisi: (point) {
                          setState(() => _choisi = point);
                          if (point != null) TtsService.instance.dire(point.annonce);
                        },
                      ),
                    ),
                    if (_choisi != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: FicheVillage(repere: _choisi!),
                      ),
                  ],
                ),
              ),
            ],
            Row(
              children: [
                Expanded(
                  child: GrosBouton(
                    titre: _carteOuverte ? 'Cacher la carte' : 'Voir la carte',
                    picto: Picto.map,
                    secondaire: true,
                    minHeight: 72,
                    onTap: () => setState(() => _carteOuverte = !_carteOuverte),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: const LivraisonScreen(integree: true),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Les trois chiffres du jour, chacun ouvrant son chantier.
///
/// L'attente est plus grande que les autres parce que c'est la seule que
/// l'admin peut reduire en travaillant. Un chiffre qu'on ne peut pas toucher
/// n'est qu'un decor : ici, toucher « 3 devis » ouvre les trois devis.
class _Compteurs extends StatelessWidget {
  const _Compteurs({
    required this.aValider,
    required this.aSigner,
    required this.aPointer,
    required this.onDevis,
    required this.onAchats,
    required this.onLivraisons,
  });

  final int aValider;
  final int aSigner;
  final int aPointer;
  final VoidCallback onDevis;
  final VoidCallback onAchats;
  final VoidCallback onLivraisons;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Compteur(
            picto: Picto.clock,
            valeur: '$aValider',
            libelle: 'devis',
            taille: 36,
            important: aValider > 0,
            onTap: onDevis,
          ),
          const SizedBox(width: 10),
          _Compteur(
            picto: Picto.handGive,
            valeur: '$aSigner',
            libelle: 'récoltes',
            taille: 36,
            important: aSigner > 0,
            onTap: onAchats,
          ),
          const SizedBox(width: 10),
          _Compteur(
            picto: Picto.moto,
            valeur: '$aPointer',
            libelle: 'à pointer',
            taille: 30,
            couleur: aPointer > 0 ? MboaColors.secondary : null,
            onTap: onLivraisons,
          ),
        ],
      ),
    );
  }
}

class _Compteur extends StatelessWidget {
  const _Compteur({
    required this.picto,
    required this.valeur,
    required this.libelle,
    required this.taille,
    required this.onTap,
    this.couleur,
    this.important = false,
  });

  final Picto picto;
  final String valeur;
  final String libelle;
  final double taille;
  final VoidCallback onTap;
  final Color? couleur;
  final bool important;

  @override
  Widget build(BuildContext context) {
    final teinte = couleur ?? MboaColors.primary;

    return Expanded(
      flex: important ? 12 : 8,
      child: CarteBio(
        onTap: onTap,
        couleurFond: important ? MboaColors.secondaryDoux : MboaColors.surface,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            PictoIcon(picto, size: 26, couleur: teinte),
            const SizedBox(height: 4),
            Text(
              valeur,
              style: MboaTypo.chiffre(couleur: teinte).copyWith(fontSize: taille),
            ),
            Text(
              libelle,
              style: MboaTypo.aide(couleur: MboaColors.text),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}

/// Un raccourci dessine, avec son mot dessous. Deux par ligne : quatre cotes
/// a cotes couperaient les mots ou descendraient sous la cible de 72 px.
class _Raccourci extends StatelessWidget {
  const _Raccourci({
    required this.libelle,
    required this.picto,
    required this.onTap,
  });

  final String libelle;
  final Picto picto;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return CarteBio(
      onTap: onTap,
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          PictoIcon(picto, size: 30),
          const SizedBox(height: 2),
          Text(
            libelle,
            style: MboaTypo.aide(couleur: MboaColors.text),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
