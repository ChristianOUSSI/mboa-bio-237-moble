# ============================================================================
# MBOA BIO 237 - ProGuard / R8
#
# minify est actif en release. Les quatre bibliotheques ci-dessous sont
# interrogees par reflection depuis le code Dart (method channels) : sans
# regle explicite, R8 renomme leurs classes et l'APK casse au premier appel
# de micro ou de camera, jamais au demarrage. C'est le type de bug qui
# n'atteint jamais la personne qui le declenche.
# ============================================================================

-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }

# Voix
-keep class com.idlefish.fluttertts.** { *; }
-keep class com.csdcorp.speech_to_text.** { *; }

# Enregistrement et lecture des notes de cinq secondes
-keep class com.llfbandit.record.** { *; }
-keep class xyz.justsoft.audioplayers.** { *; }

# Camera et selection d'image
-keep class io.flutter.plugins.imagepicker.** { *; }

# Les modeles Dart serialises en JSON ne passent pas par reflection : rien a
# garder de ce cote-la.

-dontwarn org.jetbrains.annotations.**
