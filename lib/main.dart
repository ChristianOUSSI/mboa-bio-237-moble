import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/mboa_app.dart';
import 'core/data/base_locale.dart';
import 'core/data/mboa_reseau.dart';
import 'core/etat/providers.dart';
import 'core/voice/tts_service.dart';

/// MBOA BIO 237. Une codebase, trois flavors.
///
/// Le flavor Android (`--flavor fournisseur`) arrive ici par
/// `--dart-define=MBOA_ROLE`. Rien d'autre ne change entre les trois apps :
/// memes depots, meme theme, meme base. C'est l'ecran d'entree qui differe.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Portrait only : un ecran tourne, c'est un pouce qui ne sait plus ou il
  // est, et les trois flows sont construits pour tenir sans défilement lateral.
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  // L'ordre importe. Le reseau d'abord : il decide si les depots peuvent
  // parler a Supabase. La base SQLite ensuite : elle sert de support a tout.
  // La voix en dernier : son moteur peut mettre une seconde, et l'app doit
  // s'ouvrir meme sans lui.
  await MboaReseau.initialiser();
  final base = await BaseLocale.ouvrir();
  await TtsService.instance.demarrer();

  runApp(
    ProviderScope(
      overrides: [baseLocaleProvider.overrideWithValue(base)],
      child: const MboaApp(),
    ),
  );
}
