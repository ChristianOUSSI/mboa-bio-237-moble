import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/design_system/boutons.dart';
import '../../core/design_system/carte.dart';
import '../../core/design_system/picto.dart';
import '../../core/etat/providers.dart';
import '../../core/theme/mboa_colors.dart';
import '../../core/theme/mboa_typography.dart';
import '../../core/voice/tts_service.dart';
import '../auth/connexion_screen.dart';
import 'mes_achats_screen.dart';
import 'proposer_recolte_screen.dart';
import 'stock_screen.dart';

/// L'ecran unique du producteur : trois gestes, rien de plus.
///
/// Le producteur propose ce qu'il a, il suit ses achats, il regarde ce qui
/// reste au comptoir. Il ne fixe plus le prix de revente et ne voit jamais la
/// marge de MBOA : son metier s'arrete a la vente. Pas de menu, pas d'onglet,
/// pas de barre du bas. Une mama de 60 ans qui rouvre l'app trois semaines
/// plus tard doit retrouver le meme ecran, a la meme place.
class AccueilFournisseurScreen extends ConsumerStatefulWidget {
  const AccueilFournisseurScreen({super.key});

  static const String nom = '/fournisseur';

  @override
  ConsumerState<AccueilFournisseurScreen> createState() => _AccueilFournisseurScreenState();
}

class _AccueilFournisseurScreenState extends ConsumerState<AccueilFournisseurScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final session = ref.read(sessionProvider);
      if (session == null) return;
      TtsService.instance.dire(
        '${session.profil.prenom}. Trois boutons : vendre ma récolte, mes achats, mon stock.',
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
    final session = ref.watch(sessionProvider);
    final file = ref.watch(fileAttenteProvider);
    final connecte = ref.watch(reseauProvider).value ?? false;

    if (session == null) {
      return Scaffold(
        backgroundColor: MboaColors.background,
        body: const Center(child: CircularProgressIndicator(color: MboaColors.primary)),
      );
    }

    return Scaffold(
      backgroundColor: MboaColors.background,
      appBar: AppBar(
        title: Text(session.profil.prenom),
        actions: [
          IconButton(
            onPressed: _quitter,
            tooltip: 'Se déconnecter',
            iconSize: 34,
            icon: const PictoIcon(Picto.close, size: 34, couleur: MboaColors.surface),
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 28),
          children: [
            CarteBio(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
              child: Row(
                children: [
                  const PictoIcon(Picto.leaf, size: 40),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(session.profil.village, style: MboaTypo.titre()),
                        Text(session.profil.telephone, style: MboaTypo.aide()),
                      ],
                    ),
                  ),
                  BoutonVoix(
                    texte: '${session.profil.vitrine}. Téléphone ${session.profil.telephone}',
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            GrosBouton(
              titre: 'Vendre ma récolte',
              picto: Picto.handGive,
              sousTitre: 'Photo, quantité, ton prix',
              sombre: true,
              minHeight: 124,
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (context) => const ProposerRecolteScreen()),
              ),
            ),
            const SizedBox(height: 16),
            GrosBouton(
              titre: 'Mes achats',
              picto: Picto.basket,
              sousTitre: 'Ce que le comptoir m\'a acheté et ce qu\'il doit',
              secondaire: true,
              minHeight: 104,
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (context) => const MesAchatsScreen()),
              ),
            ),
            const SizedBox(height: 16),
            GrosBouton(
              titre: 'Mon stock',
              picto: Picto.priceTag,
              sousTitre: 'Ce qui reste au comptoir',
              secondaire: true,
              minHeight: 104,
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (context) => const StockScreen()),
              ),
            ),
            const SizedBox(height: 22),
            _Bandeaux(file: file, connecte: connecte),
          ],
        ),
      ),
    );
  }
}

/// Les deux seuls etats systeme utiles au producteur : le reseau, et ce qui
/// attend encore d'etre envoye.
class _Bandeaux extends StatelessWidget {
  const _Bandeaux({required this.file, required this.connecte});

  final AsyncValue<int> file;
  final bool connecte;

  @override
  Widget build(BuildContext context) {
    final attente = file.value ?? 0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (!connecte)
          const BandeauEtat(
            texte: 'Pas de réseau. Vos données restent ici et partiront seules.',
            couleur: MboaColors.primary,
            icone: PictoIcon(Picto.sync, size: 30),
          )
        else if (attente > 0)
          BandeauEtat(
            texte: '$attente envoi${attente > 1 ? 's' : ''} en attente',
            couleur: MboaColors.primary,
            icone: const PictoIcon(Picto.sync, size: 30),
          )
        else
          const BandeauEtat(
            texte: 'Tout est envoyé',
            couleur: MboaColors.primary,
            icone: PictoIcon(Picto.check, size: 30),
          ),
      ],
    );
  }
}
