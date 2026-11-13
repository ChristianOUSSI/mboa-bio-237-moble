package bio.mboa.mboa_bio

import io.flutter.embedding.android.FlutterActivity

/**
 * Activite unique des trois flavors.
 *
 * Rien de specifique ici : les trois apps partagent le meme embeddinger, et
 * toute la logique de role vit cote Dart (`AppEnv.role`). Une classe
 * Kotlin par flavor serait la bonne place pour un splash natif avec un logo
 * different, mais le logo MBOA BIO 237 est commun aux trois par charte.
 *
 * Le splash Android est assure par `@style/LaunchTheme`, defini dans
 * res/values/styles.xml, qui affiche le JPEG officiel pendant que le moteur
 * Dart demarre. C'est ce qui evite l'ecran blanc de deux secondes que
 * l'utilisateur age interprète comme un telephone bloque.
 */
class MainActivity : FlutterActivity()
