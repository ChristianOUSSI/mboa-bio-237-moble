import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/data/models/suivi_colis.dart';
import '../../core/design_system/boutons.dart';
import '../../core/design_system/carte.dart';
import '../../core/design_system/picto.dart';
import '../../core/etat/providers.dart';
import '../../core/theme/mboa_colors.dart';
import '../../core/theme/mboa_typography.dart';
import '../../core/voice/tts_service.dart';

/// Le dessin de chaque jalon. La forme porte le sens avant le mot : une
/// personne qui ne lit pas reconnait le panier, la moto, la main qui remet.
Picto _pictoDe(JalonSuivi jalon) => switch (jalon) {
      JalonSuivi.panierPrepare => Picto.basket,
      JalonSuivi.motoPartie => Picto.moto,
      JalonSuivi.enApproche => Picto.clock,
      JalonSuivi.arrive => Picto.map,
      JalonSuivi.remis => Picto.pouceLeve,
    };

String _heure(DateTime? quand) {
  if (quand == null) return '';
  final h = quand.hour.toString().padLeft(2, '0');
  final m = quand.minute.toString().padLeft(2, '0');
  return '$h:$m';
}

/// La timeline du colis, embeddable dans n'importe quel ecran des trois roles.
///
/// Cinq jalons dans l'ordre du voyage. Ceux qui sont poses sont pleins et
/// horodates ; les autres restent en contour, pour que l'oeil voie d'un coup
/// ce qui reste a faire. Le jalon en cours est le dernier pose : c'est lui que
/// la voix lit quand on appuie sur le haut-parleur.
class TimelineColis extends ConsumerWidget {
  const TimelineColis({
    required this.commandeId,
    this.peutPointer = false,
    this.encadre = true,
    this.auteur = 'admin',
    super.key,
  });

  final String commandeId;

  /// Vrai pour le comptoir et le livreur : ils peuvent poser le jalon
  /// manuel « le livreur approche ». La cliente ne pointe rien, elle lit.
  final bool peutPointer;

  /// Faux quand la timeline est deja dans une carte : deux cadres imbriques
  /// font une bordure epaisse qui donne l'impression d'un bloc a part.
  final bool encadre;

  /// Qui pose le jalon manuel. Informatif, mais il distingue le moto qui
  /// previent lui-meme du comptoir qui relaie son appel.
  final String auteur;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final suivi = ref.watch(suiviColisProvider(commandeId));

    return suivi.when(
      loading: () => const Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: Center(child: CircularProgressIndicator(color: MboaColors.primary)),
      ),
      error: (e, _) => CarteBio(
        child: Text(
          'Le suivi n’est pas disponible pour le moment.',
          style: MboaTypo.corps(couleur: MboaColors.text),
        ),
      ),
      data: (s) => _corps(context, ref, s),
    );
  }

  Widget _corps(BuildContext context, WidgetRef ref, SuiviColis suivi) {
    final timeline = suivi.timeline;
    final dernier = suivi.dernierRang;
    final phrase = suivi.derniereEtape == null
        ? 'Votre colis attend au comptoir.'
        : '${suivi.derniereEtape!.jalon.libelle}. ${suivi.derniereEtape!.jalon.description}.';

    final manuelRestant = peutPointer &&
        !suivi.enApproche &&
        suivi.derniereEtape != null &&
        dernier >= JalonSuivi.motoPartie.rang &&
        dernier < JalonSuivi.arrive.rang;

    final contenu = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const PictoIcon(Picto.moto, size: 36),
              const SizedBox(width: 12),
              Expanded(child: Text('Suivi du colis', style: MboaTypo.titre())),
              BoutonVoix(texte: phrase),
            ],
          ),
          const SizedBox(height: 18),
          for (var i = 0; i < timeline.length; i++) ...[
            _Jalon(
              etape: timeline[i],
              allume: timeline[i].estPose,
              enCours: i == dernier,
              estDernier: i == timeline.length - 1,
            ),
          ],
          if (manuelRestant) ...[
            const SizedBox(height: 16),
            GrosBouton(
              titre: 'Le livreur approche',
              picto: Picto.clock,
              sombre: true,
              minHeight: 88,
              onTap: () async {
                await ref.read(depotCommandesProvider).pointerSuivi(
                      commandeId: commandeId,
                      jalon: JalonSuivi.enApproche,
                      auteur: auteur,
                    );
                ref.invalidate(suiviColisProvider(commandeId));
                await TtsService.instance.dire('Le livreur approche, préparez-vous.');
              },
            ),
          ],
        ],
      );

    if (!encadre) return contenu;
    return CarteBio(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
      child: contenu,
    );
  }
}

class _Jalon extends StatelessWidget {
  const _Jalon({
    required this.etape,
    required this.allume,
    required this.enCours,
    required this.estDernier,
  });

  final EtapeTimeline etape;
  final bool allume;
  final bool enCours;
  final bool estDernier;

  @override
  Widget build(BuildContext context) {
    final jalon = etape.jalon;
    final heure = _heure(etape.horodatage);

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Column(
            children: [
              PictoPastille(
                picto: _pictoDe(jalon),
                diametre: 72,
                allume: allume,
                couleurFond: enCours ? MboaColors.primary : null,
                couleurTrait: enCours ? MboaColors.primary : null,
                couleurIcone: enCours ? MboaColors.surface : null,
                label: jalon.libelle,
              ),
              if (!estDernier)
                Expanded(
                  child: Container(
                    width: 6,
                    margin: const EdgeInsets.symmetric(vertical: 4),
                    decoration: BoxDecoration(
                      color: allume ? MboaColors.primary : MboaColors.primaryDoux,
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: estDernier ? 0 : 22, top: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          jalon.libelle,
                          style: MboaTypo.titre(
                            couleur: allume ? MboaColors.text : MboaColors.textDoux,
                          ),
                        ),
                      ),
                      if (heure.isNotEmpty)
                        Text(heure, style: MboaTypo.chiffre()),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    jalon.description,
                    style: MboaTypo.aide(
                      couleur: allume ? MboaColors.text : MboaColors.textDoux,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// L'ecran plein de suivi, utilise par le livreur sur sa course. La cliente
/// et le comptoir embarquent [TimelineColis] dans leurs ecrans existants.
class SuiviColisScreen extends ConsumerWidget {
  const SuiviColisScreen({
    required this.commandeId,
    required this.titre,
    this.peutPointer = false,
    this.auteur = 'admin',
    super.key,
  });

  final String commandeId;
  final String titre;
  final bool peutPointer;
  final String auteur;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      backgroundColor: MboaColors.background,
      appBar: AppBar(
        title: Text(titre),
        leading: IconButton(
          onPressed: () => Navigator.of(context).pop(),
          tooltip: 'Retour',
          iconSize: 36,
          icon: const PictoIcon(Picto.back, size: 36, couleur: MboaColors.surface),
        ),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
          children: [
            TimelineColis(
              commandeId: commandeId,
              peutPointer: peutPointer,
              auteur: auteur,
            ),
          ],
        ),
      ),
    );
  }
}
