import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/config/app_env.dart';
import '../core/config/app_role.dart';
import '../core/etat/providers.dart';
import '../core/temps_reel/hub_realtime.dart';
import '../core/theme/mboa_colors.dart';
import '../core/theme/mboa_theme.dart';
import '../core/theme/mboa_typography.dart';
import '../core/voice/tts_service.dart';
import '../features/admin/tableau_admin_screen.dart';
import '../features/auth/connexion_screen.dart';
import '../features/consommateur/marche_screen.dart';
import '../features/fournisseur/accueil_fournisseur_screen.dart';
import '../features/livreur/accueil_livreur_screen.dart';

/// Le shell commun des trois apps.
///
/// Une seule instance de `MaterialApp` : les trois flavors ne different que
/// par l'ecran racine et le theme de surface. C'est ce qui garantit qu'un
/// correctif de typo ou de contraste profite aux trois en meme temps.
class MboaApp extends ConsumerStatefulWidget {
  const MboaApp({super.key});

  @override
  ConsumerState<MboaApp> createState() => _MboaAppState();
}

class _MboaAppState extends ConsumerState<MboaApp> {
  @override
  void initState() {
    super.initState();
    // L'ecoute des evenements doit survivre a tous les changements d'ecran :
    // elle vit ici, et non dans un des trois accueils.
    WidgetsBinding.instance.addPostFrameCallback((_) => _brancherEvenements());
  }

  void _brancherEvenements() {
    ref.listen<AsyncValue<EvenementMboa>>(evenementProvider, (prec, suivant) {
      final evenement = suivant.valueOrNull;
      if (evenement == null) return;
      ref.read(emetteurSonProvider).traiter(evenement);

      // L'appel automatisse au producteur n'est passe que dans sa propre app :
      // un admin ne doit pas entendre sonner la commande d'un autre.
      if (evenement.type == TypeEvenement.commandeRecue &&
          AppEnv.role == AppRole.fournisseur) {
        ref.read(appelVocalProvider.notifier).enfiler(evenement.id);
      }

      // Le suivi de colis : quand un jalon est pose, la timeline se rafraichit.
      // L'identifiant de la commande est dans le payload du jalon.
      if (evenement.type == TypeEvenement.suiviColis) {
        final commandeId = evenement.apres['commande_id'] as String?;
        if (commandeId != null) {
          ref.invalidate(suiviColisProvider(commandeId));
        }
        ref.invalidate(commandesAdminProvider);
        ref.invalidate(commandesClienteProvider);
        ref.invalidate(mesCoursesProvider);
      }

      // Une course change de statut : le livreur la voit avancer sans
      // recharger son ecran.
      if (evenement.type == TypeEvenement.commandeChangee) {
        ref.invalidate(mesCoursesProvider);
      }
    });
  }

  ThemeData get _theme => switch (AppEnv.role) {
        AppRole.fournisseur => MboaTheme.fournisseur,
        AppRole.admin => MboaTheme.admin,
        AppRole.consommateur => MboaTheme.consommateur,
        AppRole.livreur => MboaTheme.livreur,
      };

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: AppEnv.role.appName,
      debugShowCheckedModeBanner: false,
      theme: _theme,
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [Locale('fr', 'CM'), Locale('en', 'CM')],
      locale: const Locale('fr', 'CM'),
      home: const EcranGarde(),
      routes: const {
        ConnexionScreen.nom: ConnexionScreen(),
        AccueilFournisseurScreen.nom: AccueilFournisseurScreen(),
        MarcheScreen.nom: MarcheScreen(),
        TableauAdminScreen.nom: TableauAdminScreen(),
        AccueilLivreurScreen.nom: AccueilLivreurScreen(),
      },
    );
  }
}

/// Le point d'entree unique : le logo MBOA BIO 237, puis la reprise de session.
///
/// Le splash n'est pas un temps mort. Il dit a haute voix quelle app est
/// ouverte, parce que les trois icones se ressemblent sur le telephone d'une
/// mama qui recoit les trois.
class EcranGarde extends ConsumerStatefulWidget {
  const EcranGarde({super.key});

  @override
  ConsumerState<EcranGarde> createState() => _EcranGardeState();
}

class _EcranGardeState extends ConsumerState<EcranGarde> {
  static const Duration _dureeLogo = Duration(milliseconds: 1400);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _demarrer());
  }

  Future<void> _demarrer() async {
    await TtsService.instance.dire('Mboa Bio deux trois sept');
    await Future<void>.delayed(_dureeLogo);
    if (!mounted) return;

    await ref.read(sessionProvider.notifier).demarrer();
    if (!mounted) return;

    final connectee = ref.read(sessionProvider);
    Navigator.of(context).pushReplacementNamed(
      connectee == null ? ConnexionScreen.nom : _racineDe(connectee.role),
    );
  }

  static String _racineDe(AppRole role) => switch (role) {
        AppRole.fournisseur => AccueilFournisseurScreen.nom,
        AppRole.admin => TableauAdminScreen.nom,
        AppRole.consommateur => MarcheScreen.nom,
        AppRole.livreur => AccueilLivreurScreen.nom,
      };

  @override
  Widget build(BuildContext context) {
    final largeur = MediaQuery.sizeOf(context).width;

    return Scaffold(
      backgroundColor: MboaColors.background,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Le logo fourni est le visuel officiel : il n'est jamais regenere,
            // recadre ni recolore. C'est la seule image de l'app qui compte.
            Image.asset(
              'assets/logo/mboa_bio_237.jpeg',
              width: largeur * 0.78,
              semanticLabel: 'Logo Mboa Bio 237',
            ),
            const SizedBox(height: 24),
            Text(AppEnv.role.appName, style: MboaTypo.titre()),
            const SizedBox(height: 10),
            const _BandeauChargement(),
            if (AppEnv.problemeConfig != null) ...[
              const SizedBox(height: 18),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: Text(
                  AppEnv.problemeConfig!,
                  textAlign: TextAlign.center,
                  style: MboaTypo.aide(couleur: MboaColors.text),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _BandeauChargement extends StatelessWidget {
  const _BandeauChargement();

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(
          width: 22,
          height: 22,
          child: CircularProgressIndicator(strokeWidth: 3, color: MboaColors.primary),
        ),
        const SizedBox(width: 14),
        Text('Chargement', style: MboaTypo.aide(couleur: MboaColors.text)),
      ],
    );
  }
}
