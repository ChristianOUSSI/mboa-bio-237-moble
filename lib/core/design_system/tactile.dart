import 'dart:async';

import 'package:flutter/services.dart';

import '../voice/tts_service.dart';

/// Le geste de base de l'app : taper, sentir, entendre.
///
/// La spec impose une vibration au clic. Elle n'est pas la pour le plaisir :
/// sur un telephone tenu a bout de bras par une personne qui ne lit pas, le
/// retour haptique est la seule preuve que l'appui a ete pris en compte. La
/// voix, elle, confirme QUOI.
///
/// Les deux sont non bloquants : `unawaited` sur le TTS evite qu'un moteur
/// lent retarde le changement d'ecran.
Future<void> mboaTactile({String? annonce, bool fort = true}) async {
  try {
    if (fort) {
      await HapticFeedback.heavyImpact();
    } else {
      await HapticFeedback.selectionClick();
    }
  } catch (_) {
    // Pas de moteur haptique sur certains telephones d'entree de gamme.
  }

  if (annonce != null && annonce.trim().isNotEmpty) {
    unawaited(TtsService.instance.dire(annonce));
  }
}
