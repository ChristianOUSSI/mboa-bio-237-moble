import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/data/models/livreur.dart';
import '../../core/data/models/statuts.dart';
import '../../core/data/models/suivi_colis.dart';
import '../../core/design_system/boutons.dart';
import '../../core/design_system/carte.dart';
import '../../core/design_system/picto.dart';
import '../../core/etat/providers.dart';
import '../../core/theme/mboa_colors.dart';
import '../../core/theme/mboa_typography.dart';
import '../../core/utils/format_monnaie.dart';
import '../../core/voice/tts_service.dart';
import '../auth/connexion_screen.dart';
import '../commun/suivi_colis_screen.dart';

/// L'ecran du moto : ses courses, dans l'ordre du depart.
///
/// Trois informations par course, et rien d'autre : qui, quoi, combien. Le
/// livreur ne voit jamais le cout d'achat du comptoir, et il n'a pas de stock
/// a gerer. Un seul geste lui appartient vraiment, dire qu'il approche, pour
/// que la cliente se prepare avant qu'il frappe.
class AccueilLivreurScreen extends ConsumerWidget {
  const AccueilLivreurScreen({super.key});

  static const String nom = '/livreur';

  Future<void> _quitter(BuildContext context, WidgetRef ref) async {
    await TtsService.instance.dire('À bientôt');
    await ref.read(sessionProvider.notifier).deconnexion();
    if (!context.mounted) return;
    Navigator.of(context).pushNamedAndRemoveUntil(ConnexionScreen.nom, (route) => false);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionProvider);
    final fiche = ref.watch(maFicheLivreurProvider);
    final courses = ref.watch(mesCoursesProvider);

    return Scaffold(
      backgroundColor: MboaColors.background,
      appBar: AppBar(
        title: const Text('Mes courses'),
        actions: [
          IconButton(
            onPressed: () => _quitter(context, ref),
            tooltip: 'Se déconnecter',
            iconSize: 34,
            icon: const PictoIcon(Picto.close, size: 34, couleur: MboaColors.surface),
          ),
        ],
      ),
      body: SafeArea(
        child: RefreshIndicator(
          color: MboaColors.primary,
          onRefresh: () async {
            ref.invalidate(maFicheLivreurProvider);
            await ref.read(mesCoursesProvider.future);
          },
          child: ListView(
            padding: const EdgeInsets.fromLTRB(18, 18, 18, 28),
            children: [
              if (session != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 14),
                  child: Text(
                    'Bonjour ${session.profil.prenom}',
                    style: MboaTypo.titre(),
                  ),
                ),
              fiche.when(
                loading: () => const Padding(
                  padding: EdgeInsets.symmetric(vertical: 20),
                  child: Center(
                    child: CircularProgressIndicator(color: MboaColors.primary),
                  ),
                ),
                error: (e, _) => const _FicheAbsente(),
                data: (l) => l == null ? const _FicheAbsente() : _CarteFiche(fiche: l),
              ),
              const SizedBox(height: 22),
              courses.when(
                loading: () => const Padding(
                  padding: EdgeInsets.symmetric(vertical: 32),
                  child: Center(
                    child: CircularProgressIndicator(color: MboaColors.primary),
                  ),
                ),
                error: (e, _) => CarteBio(
                  child: Text(
                    'Les courses ne sont pas disponibles pour le moment.',
                    style: MboaTypo.corps(),
                  ),
                ),
                data: (liste) => _ListeCourses(courses: liste),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CarteFiche extends StatelessWidget {
  const _CarteFiche({required this.fiche});

  final Livreur fiche;

  @override
  Widget build(BuildContext context) {
    return CarteBio(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      child: Row(
        children: [
          const PictoIcon(Picto.moto, size: 48),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(fiche.nom, style: MboaTypo.titre()),
                const SizedBox(height: 2),
                Text(fiche.repere, style: MboaTypo.aide()),
              ],
            ),
          ),
          BoutonVoix(texte: fiche.annonce),
        ],
      ),
    );
  }
}

/// Un compte sans fiche ne peut pas travailler : c'est le comptoir qui
/// rattache le moto a un numero. L'ecran le dit, et donne le numero a appeler.
class _FicheAbsente extends ConsumerWidget {
  const _FicheAbsente();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return CarteBio(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const PictoPastille(picto: Picto.alert, diametre: 64),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  'Votre fiche n’est pas encore rattachée',
                  style: MboaTypo.titre(),
                ),
              ),
              const BoutonVoix(
                texte: 'Votre fiche n’est pas encore rattachée. '
                    'Appelez le comptoir Mboa Bio.',
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            'Le comptoir doit enregistrer votre moto et votre numéro. '
            'Appelez le comptoir pour finir.',
            style: MboaTypo.corps(),
          ),
          const SizedBox(height: 16),
          GrosBouton(
            titre: 'Appeler le comptoir',
            picto: Picto.phone,
            sombre: true,
            onTap: () async {
              final numero = await ref.read(depotCommandesProvider).contactComptoir();
              if (numero == null || numero.isEmpty) {
                await TtsService.instance.dire(
                  'Le numéro du comptoir n’est pas encore enregistré.',
                );
                return;
              }
              await launchUrl(Uri.parse('tel:$numero'));
            },
          ),
        ],
      ),
    );
  }
}

class _ListeCourses extends StatelessWidget {
  const _ListeCourses({required this.courses});

  final List<CourseLivreur> courses;

  @override
  Widget build(BuildContext context) {
    if (courses.isEmpty) {
      return CarteBio(
        child: Column(
          children: [
            const PictoPastille(picto: Picto.check, diametre: 88),
            const SizedBox(height: 14),
            Text('Aucune course pour le moment', style: MboaTypo.titre()),
            const SizedBox(height: 6),
            Text(
              'Le comptoir vous affecte une course quand le panier est prêt.',
              textAlign: TextAlign.center,
              style: MboaTypo.aide(),
            ),
            const SizedBox(height: 10),
            const BoutonVoix(
              texte: 'Aucune course pour le moment. '
                  'Le comptoir vous affecte une course quand le panier est prêt.',
            ),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          courses.length == 1 ? '1 course' : '${courses.length} courses',
          style: MboaTypo.aide(couleur: MboaColors.text),
        ),
        const SizedBox(height: 10),
        for (final course in courses) ...[
          _CarteCourse(course: course),
          const SizedBox(height: 16),
        ],
      ],
    );
  }
}

class _CarteCourse extends ConsumerWidget {
  const _CarteCourse({required this.course});

  final CourseLivreur course;

  Picto get _picto => switch (course.statut) {
        StatutCommande.valideeAdmin => Picto.basket,
        StatutCommande.enLivraison => Picto.moto,
        StatutCommande.livree => Picto.check,
        _ => Picto.clock,
      };

  String get _etape => switch (course.statut) {
        StatutCommande.valideeAdmin => 'À charger au comptoir',
        StatutCommande.enLivraison => 'En route',
        StatutCommande.livree => 'Livrée, attente de la cliente',
        _ => 'En préparation',
      };

  Future<void> _approcher(BuildContext context, WidgetRef ref) async {
    await ref.read(depotCommandesProvider).pointerSuivi(
          commandeId: course.id,
          jalon: JalonSuivi.enApproche,
          auteur: 'livreur',
        );
    ref.invalidate(suiviColisProvider(course.id));
    ref.invalidate(mesCoursesProvider);
    await TtsService.instance.dire('Le livreur approche, préparez-vous.');
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('La cliente est prévenue que vous approchez'),
        backgroundColor: MboaColors.primary,
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final peutApprocher = course.enRoute;

    return CarteBio(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              PictoPastille(picto: _picto, diametre: 64),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(course.clienteLabel, style: MboaTypo.titre()),
                    const SizedBox(height: 2),
                    Text(_etape, style: MboaTypo.aide()),
                  ],
                ),
              ),
              BoutonVoix(texte: course.annonce),
            ],
          ),
          const SizedBox(height: 16),
          Text(course.resumeQuantites, style: MboaTypo.chiffre()),
          const SizedBox(height: 10),
          Row(
            children: [
              const PictoIcon(Picto.especes, size: 34),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'À encaisser ${formaterFcfa(course.montantTotal)}',
                  style: MboaTypo.corps(),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              if (course.clienteTelephone != null)
                Padding(
                  padding: const EdgeInsets.only(right: 12),
                  child: BoutonCarre(
                    picto: Picto.phone,
                    annonce: 'Appeler la cliente',
                    onTap: () => launchUrl(
                      Uri.parse('tel:${course.clienteTelephone}'),
                    ),
                  ),
                ),
              Expanded(
                child: peutApprocher
                    ? GrosBouton(
                        titre: 'Le livreur approche',
                        picto: Picto.clock,
                        sombre: true,
                        minHeight: 88,
                        onTap: () => _approcher(context, ref),
                      )
                    : GrosBouton(
                        titre: 'Voir le suivi',
                        picto: Picto.map,
                        secondaire: true,
                        minHeight: 88,
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (context) => SuiviColisScreen(
                              commandeId: course.id,
                              titre: course.clienteLabel,
                              peutPointer: true,
                              auteur: 'livreur',
                            ),
                          ),
                        ),
                      ),
              ),
            ],
          ),
          if (peutApprocher) ...[
            const SizedBox(height: 10),
            TextButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (context) => SuiviColisScreen(
                    commandeId: course.id,
                    titre: course.clienteLabel,
                    peutPointer: true,
                    auteur: 'livreur',
                  ),
                ),
              ),
              child: Text('Voir le détail du suivi', style: MboaTypo.aide()),
            ),
          ],
        ],
      ),
    );
  }
}
