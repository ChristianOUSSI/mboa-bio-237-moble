import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';

import '../../core/theme/mboa_colors.dart';
import '../../core/theme/mboa_typography.dart';

/// Recadrage et filigrane d'une photo de recolte.
///
/// Tout est fait avec `dart:ui`, sans dependance d'imagerie : sur un projet
/// a trois flavors et quatre personnes, embarquer un moteur d'image externe
/// est une dette que la validation ne justifie pas.
///
/// Deux operations, dans cet ordre :
///   1. recadrage central en 4:5. Le format vertical est celui du telephone,
///      et le recadrage central est celui qui garde le tas au milieu ;
///   2. bandeau filigrane en bas, avec MBOA BIO 237 en Nunito Black.
///
/// Le filigrane n'est pas une signature de gout : c'est la seule trace qui
/// permette, trois semaines plus tard, de dire qu'une photo volee a un autre
/// compte etait bien une photo Mboa.
class Filigrane {
  const Filigrane._();

  static const String texte = 'MBOA BIO 237';
  static const double _ratio = 4 / 5;
  static const int _cote = 1024;

  /// Renvoie les octets PNG filigranes, ou null si l'image est illisible.
  ///
  /// Null n'est pas une erreur bloquante : l'admin garde alors la photo
  /// brute, et la fiche reste visible.
  static Future<Uint8List?> appliquer(Uint8List octets) async {
    final ui.Image image;
    try {
      image = await decodeImageFromList(octets);
    } catch (_) {
      return null;
    }

    final largeur = image.width;
    final hauteur = image.height;
    if (largeur <= 0 || hauteur <= 0) {
      image.dispose();
      return null;
    }

    // Recadrage central : on garde la plus grande fenetre 4:5 possible.
    double sourceLargeur = largeur.toDouble();
    double sourceHauteur = hauteur.toDouble();

    if (sourceLargeur / sourceHauteur > _ratio) {
      sourceLargeur = sourceHauteur * _ratio;
    } else {
      sourceHauteur = sourceLargeur / _ratio;
    }

    final src = Rect.fromLTWH(
      (largeur - sourceLargeur) / 2,
      (hauteur - sourceHauteur) / 2,
      sourceLargeur,
      sourceHauteur,
    );

    final destination = Rect.fromLTWH(0, 0, _cote.toDouble(), _cote / _ratio);

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder)
      ..save()
      ..clipRect(destination);

    canvas.drawImageRect(image, src, destination, Paint()..filterQuality = FilterQuality.high);
    image.dispose();

    _bandeau(canvas, destination);
    canvas.restore();

    final picture = recorder.endRecording();
    final sortie = await picture.toImage(_cote, (_cote / _ratio).round());
    final data = await sortie.toByteData(format: ui.ImageByteFormat.png);
    sortie.dispose();

    return data?.buffer.asUint8List();
  }

  /// Le bandeau du bas : fond vert fonce a 78 %, texte blanc, feuille.
  ///
  /// Le blanc sur vert fonce donne 9.2:1 de contraste, ce qui laisse le
  /// filigrane lisible meme sur une photo sombre de fin de journee.
  static void _bandeau(Canvas canvas, Rect zone) {
    final hauteurBandeau = zone.height * 0.11;
    final bandeau = Rect.fromLTWH(
      zone.left,
      zone.bottom - hauteurBandeau,
      zone.width,
      hauteurBandeau,
    );

    canvas.drawRect(
      bandeau,
      Paint()..color = MboaColors.primary.withOpacity(0.78),
    );

    final style = MboaTypo.titre(couleur: MboaColors.surface).copyWith(
      fontSize: hauteurBandeau * 0.52,
      letterSpacing: 1.5,
    );

    final peinture = TextPainter(
      text: TextSpan(text: texte, style: style),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: bandeau.width - 24);

    peinture.paint(
      canvas,
      Offset(
        bandeau.left + (bandeau.width - peinture.width) / 2,
        bandeau.top + (bandeau.height - peinture.height) / 2,
      ),
    );
  }
}
