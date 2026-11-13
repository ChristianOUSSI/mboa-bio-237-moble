import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';

import '../../core/data/mboa_reseau.dart';
import '../../core/data/models/liste.dart';
import '../../core/theme/mboa_colors.dart';
import '../../core/theme/mboa_typography.dart';
import '../../core/utils/format_monnaie.dart';
import '../../core/utils/telechargement.dart';

/// Le gabarit qui dessine le devis de marche en une seule image.
///
/// Ce n'est pas une capture d'ecran : c'est un papier. Il est dessine en
/// `dart:ui`, hors de toute widget tree, pour que le rendu soit identique
/// qu'on soit sur un Tecno de 2019 ou sur un tel de test, et pour qu'aucune
/// barre d'etat, aucun bouton, aucun filigrane d'interface ne se retrouve
/// grave dans le document que la mama envoie a sa fille ou montre a la moto.
///
/// Le modele est le devis que les marchandes utilisent deja : quatre colonnes,
/// une ligne pour la course, un total, deux cases ou signer. Ce n'est pas un
/// caprice de mise en page. Un papier que la mama reconnait est un papier
/// qu'elle remplit sans rien avoir a apprendre.
///
/// Quatre choses que l'image doit porter, dans cet ordre :
///   * le logo et le nom de la cliente, pour que le papier soit reconnu ;
///   * le tableau, une ligne par article, avec son total a chaque ligne ;
///   * le montant a payer a la porte, en blanc sur vert, a la plus grande
///     taille du document ;
///   * le code court, assez grand pour etre lu a travers un telephone.
///
/// Le code est la piece utile : une mama qui appelle l'agence dicte
/// « h, k, m, p, q, 2, 3 » et l'agent retrouve son devis. Sans lui, l'image
/// n'est qu'un papier joliment decoré.
///
/// Les photos ne sont plus dans le tableau. Vingt-cinq lignes, c'etait
/// vingt-cinq telechargements a lancer depuis le village avant que l'image
/// existe, et un devis qui n'a pas pu se faire ne sert a rien : ce sont les
/// ecrans qui gardent les photos, pour celles et ceux qui ne lisent pas.
class GabaritListe {
  const GabaritListe._();

  static const double _largeur = 1080;
  static const double _marge = 64;

  // --------------------------------------------------------------------------
  // Le cadre, ecrit en un seul endroit
  //
  // La hauteur du document se calcule avec ces constantes et rien d'autre. Un
  // bloc dessine plus bas que ce que la formule promet laisse un trou, et un
  // trou au milieu d'un papier se voit tout de suite.
  // --------------------------------------------------------------------------

  static const double _coteLogo = 200;
  static const double _hauteurTagline = 46;
  static const double _hauteurBande = 92;
  static const double _hauteurMeta = 52;
  static const double _hauteurRegle = 30;

  /// Le chapeau : marges, logo, devise, bandeau de titre, ligne de date.
  static const double _chapeau = _marge +
      _coteLogo +
      24 +
      _hauteurTagline +
      _hauteurBande +
      26 +
      _hauteurMeta +
      _hauteurRegle;

  static const double _hauteurEnteteTableau = 86;
  static const double _hauteurLigne = 78;

  /// Les quatre colonnes du papier, dans l'ordre.
  ///
  /// Largeurs mesurees sur les mots les plus longs qu'elles portent :
  /// « Prix unitaire » a 30 px, « Viande de porc » a 34 px, « 10 000 F » a
  /// 34 px. Une colonne trop etroite ne provoque aucune erreur, elle ellipse
  /// un montant ou coupe un nom, et c'est exactement ce qu'on ne veut pas
  /// voir sur le papier qui fait foi.
  static const double _colArticle = 340;
  static const double _colUnite = 190;
  static const double _colPrix = 240;
  static const double _colTotal = 182;

  static const double _ecart = 28;
  static const double _hauteurTotal = 176;
  static const double _hauteurCode = 160;
  static const double _hauteurSignatures = 200;
  static const double _hauteurLivreur = 156;
  static const double _hauteurPied = 58;

  /// Le socle, du bandeau vert jusqu'au numero de la cliente.
  static double _socle(ListeMarche liste) =>
      _hauteurTotal +
      _ecart +
      _hauteurCode +
      _ecart +
      _hauteurSignatures +
      24 +
      _hauteurPied +
      (liste.aUnLivreur ? _hauteurLivreur + _ecart : 0);

  /// Hauteur totale : chapeau, tableau, socle.
  ///
  /// Un devis de trente articles sort du cadre de l'ecran, mais pas de
  /// l'image : le document s'etire, il ne rogne rien.
  static double _hauteur(ListeMarche liste) {
    final tableau = _hauteurEnteteTableau +
        liste.lignes.length * _hauteurLigne +
        (liste.aUnLivreur && liste.livreurTarif != null ? _hauteurLigne : 0);
    return (_chapeau + tableau + _ecart + _socle(liste)).toDouble();
  }

  /// Dessine le devis et renvoie les octets PNG.
  static Future<Uint8List?> dessiner(ListeMarche liste) async {
    final hauteur = _hauteur(liste);
    final logo = await _chargerImage('assets/logo/mboa_bio_237.jpeg');

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final taille = Size(_largeur, hauteur);

    _fond(canvas, taille);
    _filigrane(canvas, taille);

    _tableau(canvas, liste, _enTete(canvas, logo, liste));
    _pied(canvas, liste, taille);

    logo?.dispose();

    final picture = recorder.endRecording();
    final image = await picture.toImage(_largeur.round(), hauteur.round());
    final octets = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();

    return octets?.buffer.asUint8List();
  }

  // --------------------------------------------------------------------------
  // Fonds
  // --------------------------------------------------------------------------

  static void _fond(Canvas canvas, Size taille) {
    canvas.drawRect(
      Offset.zero & taille,
      Paint()..color = MboaColors.background,
    );

    // Un filet vert de 8 px sur tout le tour : c'est ce qui fait « document
    // Mboa » avant meme qu'on ait lu un mot.
    final cadre = Paint()
      ..color = MboaColors.primary
      ..style = PaintingStyle.stroke
      ..strokeWidth = 8;
    canvas.drawRect(
      Rect.fromLTWH(4, 4, taille.width - 8, taille.height - 8),
      cadre,
    );
  }

  /// Le filigrane diagonal, a 5 % : present, jamais genant.
  ///
  /// Il ne rend pas le devis infalsifiable, personne ne croit ça. Il rend
  /// visible le fait qu'un papier a ete fabrique par Mboa et pas photocopie
  /// depuis un carnet, et c'est deja beaucoup dans un marche.
  static void _filigrane(Canvas canvas, Size taille) {
    final style = TextStyle(
      fontFamily: MboaTypo.famille,
      fontSize: 76,
      fontWeight: FontWeight.w900,
      fontVariations: MboaTypo.noir,
      color: MboaColors.primary.withOpacity(0.05),
    );

    final texte = TextPainter(
      text: const TextSpan(text: 'MBOA BIO 237'),
      textDirection: TextDirection.ltr,
      textAlign: TextAlign.center,
    )..layout();

    canvas.save();
    canvas.translate(taille.width / 2, taille.height / 2);
    canvas.rotate(-0.42);
    for (var ligne = -3; ligne <= 3; ligne++) {
      for (var colonne = -1; colonne <= 1; colonne++) {
        texte.paint(
          canvas,
          Offset(
            colonne * 620 - texte.width / 2,
            ligne * 190 - texte.height / 2,
          ),
        );
      }
    }
    canvas.restore();
  }

  // --------------------------------------------------------------------------
  // Ecriture
  // --------------------------------------------------------------------------

  static void _ecire(
    Canvas canvas,
    String texte, {
    required TextStyle style,
    required double y,
    double x = _marge,
    double largeur = 900,
    bool centre = false,
    int maxLines = 2,
  }) {
    final peinture = TextPainter(
      text: TextSpan(text: texte, style: style),
      textDirection: TextDirection.ltr,
      textAlign: centre ? TextAlign.center : TextAlign.start,
      maxLines: maxLines,
      ellipsis: '...',
    )..layout(maxWidth: largeur);

    peinture.paint(
      canvas,
      Offset(centre ? (_largeur - peinture.width) / 2 : x, y),
    );
  }

  /// Un chiffre aligne sur le bord droit de sa colonne. Les trois colonnes
  /// numeriques se lisent a la verticale : si les unites ne s'alignent pas,
  /// l'addition se fait a l'oeil, et l'oeil se trompe.
  static void _chiffre(
    Canvas canvas,
    String texte, {
    required double droite,
    required double y,
    required TextStyle style,
  }) {
    final peinture = TextPainter(
      text: TextSpan(text: texte, style: style),
      textDirection: TextDirection.ltr,
    )..layout();

    peinture.paint(canvas, Offset(droite - peinture.width, y));
  }

  // --------------------------------------------------------------------------
  // Chapeau
  // --------------------------------------------------------------------------

  /// Dessine le chapeau et renvoie le y ou commence le tableau.
  static double _enTete(Canvas canvas, ui.Image? logo, ListeMarche liste) {
    var y = _marge.toDouble();

    if (logo != null) {
      canvas.drawImageRect(
        logo,
        Rect.fromLTWH(0, 0, logo.width.toDouble(), logo.height.toDouble()),
        Rect.fromLTWH((_largeur - _coteLogo) / 2, y, _coteLogo, _coteLogo),
        Paint()..filterQuality = FilterQuality.high,
      );
    }
    y += _coteLogo + 24;

    _ecire(
      canvas,
      'la terre nous nourrit, la qualité nous distingue',
      style: MboaTypo.aide(couleur: MboaColors.primary)
          .copyWith(fontSize: 30, fontWeight: FontWeight.w800),
      y: y,
      largeur: _largeur - 2 * _marge,
      centre: true,
      maxLines: 1,
    );
    y += _hauteurTagline;

    // Le bandeau porte le nom de la cliente, pas le titre qu'elle a tape :
    // c'est le papier de maman Michelle, et c'est comme ça qu'on le range.
    final client = liste.consommateurNom;
    final titre = client == null || client.isEmpty
        ? liste.titre
        : 'Devis du marché de $client';

    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(_marge, y, _largeur - 2 * _marge, _hauteurBande),
        const Radius.circular(18),
      ),
      Paint()..color = MboaColors.primary,
    );

    _ecire(
      canvas,
      titre,
      style: MboaTypo.titre(couleur: MboaColors.surface).copyWith(fontSize: 44),
      y: y + 20,
      largeur: _largeur - 2 * _marge,
      centre: true,
      maxLines: 1,
    );
    y += _hauteurBande + 26;

    final nom = liste.consommateurNom ?? 'la cliente';
    final chez = 'Chez $nom';

    _ecire(
      canvas,
      '${_date(liste.createdLe)}   ·   $chez',
      style: MboaTypo.corps(couleur: MboaColors.text)
          .copyWith(fontSize: 34, fontWeight: FontWeight.w800),
      y: y + 8,
      largeur: _largeur - 2 * _marge,
      centre: true,
      maxLines: 1,
    );
    y += _hauteurMeta;

    canvas.drawLine(
      Offset(_marge, y + 10),
      Offset(_largeur - _marge, y + 10),
      Paint()
        ..color = MboaColors.trait
        ..strokeWidth = 3,
    );
    return y + _hauteurRegle;
  }

  static String _date(DateTime le) {
    final j = le.day.toString().padLeft(2, '0');
    final m = le.month.toString().padLeft(2, '0');
    return '$j/$m/${le.year}';
  }

  // --------------------------------------------------------------------------
  // Le tableau
  // --------------------------------------------------------------------------

  static const double _xArticle = _marge + _colArticle;
  static const double _xUnite = _xArticle + _colUnite;
  static const double _xPrix = _xUnite + _colPrix;
  static const double _xTotal = _xPrix + _colTotal;

  static void _tableau(Canvas canvas, ListeMarche liste, double y) {
    // L'entete de colonnes, en blanc sur vert : c'est elle qui dit que ce
    // papier est un devis et pas une liste de courses recopiee.
    canvas.drawRect(
      Rect.fromLTWH(_marge, y, _xTotal - _marge, _hauteurEnteteTableau),
      Paint()..color = MboaColors.primary,
    );

    final styleEntete = MboaTypo.aide(couleur: MboaColors.surface)
        .copyWith(fontSize: 30, fontWeight: FontWeight.w900);

    _ecire(
      canvas,
      'Article',
      style: styleEntete,
      y: y + 26,
      x: _marge + 16,
      largeur: _colArticle - 32,
      maxLines: 1,
    );
    _chiffre(canvas, 'Unité', droite: _xUnite - 18, y: y + 26, style: styleEntete);
    _chiffre(canvas, 'Prix unitaire', droite: _xPrix - 18, y: y + 26, style: styleEntete);
    _chiffre(canvas, 'Total', droite: _xTotal - 18, y: y + 26, style: styleEntete);

    var bas = y + _hauteurEnteteTableau;

    final styleNom = MboaTypo.corps(couleur: MboaColors.text)
        .copyWith(fontSize: 34, fontWeight: FontWeight.w800);
    final styleUnite =
        MboaTypo.corps(couleur: MboaColors.textDoux).copyWith(fontSize: 32);
    final stylePrix = MboaTypo.chiffre(couleur: MboaColors.text).copyWith(fontSize: 32);
    final styleTotal = MboaTypo.chiffre(couleur: MboaColors.text)
        .copyWith(fontSize: 34, fontWeight: FontWeight.w900);

    for (final ligne in liste.lignes) {
      _cellule(canvas, bas);

      _ecire(
        canvas,
        ligne.nom,
        style: styleNom,
        y: bas + 20,
        x: _marge + 16,
        largeur: _colArticle - 32,
        maxLines: 1,
      );
      _chiffre(
        canvas,
        ligne.uniteReelle.avec(ligne.quantite),
        droite: _xUnite - 18,
        y: bas + 22,
        style: styleUnite,
      );
      _chiffre(
        canvas,
        formaterFcfaCourt(ligne.prix),
        droite: _xPrix - 18,
        y: bas + 22,
        style: stylePrix,
      );
      _chiffre(
        canvas,
        formaterFcfaCourt(ligne.sousTotal),
        droite: _xTotal - 18,
        y: bas + 20,
        style: styleTotal,
      );

      bas += _hauteurLigne;
    }

    // La course tient une ligne du tableau, pas une note au stylo : c'est un
    // montant que la mama remet en main propre au moto, et il doit apparaitre
    // avec les autres, pas en dessous d'eux.
    if (liste.aUnLivreur && liste.livreurTarif != null) {
      _cellule(canvas, bas, fond: MboaColors.secondaryDoux);

      final tarif = formaterFcfaCourt(liste.livreurTarif!);

      _ecire(
        canvas,
        'Frais de livraison',
        style: MboaTypo.corps(couleur: MboaColors.text)
            .copyWith(fontSize: 32, fontWeight: FontWeight.w900),
        y: bas + 22,
        x: _marge + 16,
        largeur: _colArticle - 32,
        maxLines: 1,
      );
      _chiffre(
        canvas,
        liste.livreurNom ?? 'moto',
        droite: _xUnite - 18,
        y: bas + 24,
        style: MboaTypo.aide(couleur: MboaColors.textDoux).copyWith(fontSize: 28),
      );
      _chiffre(canvas, tarif, droite: _xPrix - 18, y: bas + 22, style: stylePrix);
      _chiffre(canvas, tarif, droite: _xTotal - 18, y: bas + 20, style: styleTotal);

      bas += _hauteurLigne;
    }

    // Le trait épais sous le tableau : la fin des lignes, le debut des
    // montants.
    canvas.drawLine(
      Offset(_marge, bas),
      Offset(_xTotal, bas),
      Paint()
        ..color = MboaColors.primary
        ..strokeWidth = 5,
    );
  }

  /// Une rangee : fond papier, puis les filets qui la separent de ses
  /// voisines. Le blanc sur le beige du papier est ce qui rend les colonnes
  /// lisibles sans loupe.
  static void _cellule(Canvas canvas, double y, {Color? fond}) {
    canvas.drawRect(
      Rect.fromLTWH(_marge, y, _xTotal - _marge, _hauteurLigne),
      Paint()..color = fond ?? MboaColors.surface,
    );

    final filet = Paint()
      ..color = MboaColors.primary
      ..strokeWidth = 2;

    for (final x in [_marge, _xArticle, _xUnite, _xPrix, _xTotal]) {
      canvas.drawLine(Offset(x, y), Offset(x, y + _hauteurLigne), filet);
    }
    canvas.drawLine(
      Offset(_marge, y + _hauteurLigne),
      Offset(_xTotal, y + _hauteurLigne),
      filet,
    );
  }

  // --------------------------------------------------------------------------
  // Socle
  // --------------------------------------------------------------------------

  static void _pied(Canvas canvas, ListeMarche liste, Size taille) {
    final signaturesHaut = taille.height - _hauteurPied - 24 - _hauteurSignatures;
    final codeHaut = signaturesHaut - _ecart - _hauteurCode;
    final totalHaut = codeHaut - _ecart - _hauteurTotal;
    final largeurBandeau = taille.width - 2 * _marge;

    // Le bloc « qui vient », au-dessus du total : la plaque est le plus grand
    // champ apres le montant, parce que c'est le repere que la mama verifie
    // avant d'ouvrir sa porte, et le seul que le moto peut lui montrer sans
    // descendre de la bete.
    if (liste.aUnLivreur) {
      final haut = totalHaut - _ecart - _hauteurLivreur;

      final boite = RRect.fromRectAndRadius(
        Rect.fromLTWH(_marge, haut, largeurBandeau, _hauteurLivreur),
        const Radius.circular(28),
      );
      canvas.drawRRect(boite, Paint()..color = MboaColors.surface);
      canvas.drawRRect(
        boite,
        Paint()
          ..color = MboaColors.primary
          ..style = PaintingStyle.stroke
          ..strokeWidth = 4,
      );

      _ecire(
        canvas,
        'QUI ARRIVE',
        style: MboaTypo.aide().copyWith(fontSize: 28, letterSpacing: 2),
        y: haut + 14,
        largeur: largeurBandeau,
        centre: true,
      );

      _ecire(
        canvas,
        liste.livreurNom ?? '',
        style: MboaTypo.titre(couleur: MboaColors.text).copyWith(fontSize: 40),
        y: haut + 52,
        largeur: largeurBandeau,
        centre: true,
        maxLines: 1,
      );

      final plaque = liste.livreurPlaque;
      final telephone = liste.livreurTelephone;
      final repere = [
        if (plaque != null && plaque.isNotEmpty) plaque,
        if (telephone != null && telephone.isNotEmpty) telephone,
      ].join('   ·   ');

      _ecire(
        canvas,
        repere,
        style: MboaTypo.chiffre().copyWith(fontSize: plaque != null ? 44 : 34),
        y: haut + 96,
        largeur: largeurBandeau,
        centre: true,
        maxLines: 1,
      );
    }

    // Le total, en blanc sur vert fonce : la seule zone sombre du document,
    // donc celle ou l'oeil va chercher le montant.
    final bandeau = RRect.fromRectAndRadius(
      Rect.fromLTWH(_marge, totalHaut, largeurBandeau, _hauteurTotal),
      const Radius.circular(28),
    );
    canvas.drawRRect(bandeau, Paint()..color = MboaColors.primary);

    _ecire(
      canvas,
      'À payer à la livraison',
      style: MboaTypo.aide(couleur: MboaColors.surface).copyWith(fontSize: 32),
      y: totalHaut + 16,
      largeur: largeurBandeau,
      centre: true,
    );

    _ecire(
      canvas,
      formaterFcfa(liste.montantAPayer),
      style: MboaTypo.chiffreGeant(couleur: MboaColors.surface).copyWith(fontSize: 72),
      y: totalHaut + 52,
      largeur: largeurBandeau,
      centre: true,
      maxLines: 1,
    );

    // Le detail « dont la moto » : la marchandise se paie au vendeur, la
    // course se paie au chauffeur, et les deux ne sortent pas de la meme
    // poche. Un total sec ferait croire a la mama qu'elle doit tout a une
    // seule personne.
    final tarif = liste.livreurTarif;
    if (tarif != null && tarif > 0) {
      _ecire(
        canvas,
        'dont ${formaterFcfa(tarif)} à la moto',
        style: MboaTypo.aide(couleur: MboaColors.surface).copyWith(fontSize: 26),
        y: totalHaut + 142,
        largeur: largeurBandeau,
        centre: true,
      );
    }

    // Le code, plus grand que tout sauf le total : c'est l'information que la
    // mama doit pouvoir dicter sans chercher ses lunettes.
    _ecire(
      canvas,
      'Code du devis, à dicter par téléphone',
      style: MboaTypo.aide().copyWith(fontSize: 28),
      y: codeHaut + 6,
      largeur: largeurBandeau,
      centre: true,
    );

    _ecire(
      canvas,
      liste.code.toUpperCase().split('').join(' '),
      style: MboaTypo.chiffreGeant().copyWith(fontSize: 66, letterSpacing: 8),
      y: codeHaut + 46,
      largeur: largeurBandeau,
      centre: true,
      maxLines: 1,
    );

    // Les deux cases de signature restent vides : le papier se signe a la
    // main, chez la marchande comme a la porte. Ce ne sont pas des cases
    // decoratives, c'est la raison pour laquelle ce document existe.
    final moitie = (largeurBandeau - 26) / 2;
    for (var i = 0; i < 2; i++) {
      final gauche = _marge + i * (moitie + 26);

      final boite = RRect.fromRectAndRadius(
        Rect.fromLTWH(gauche, signaturesHaut, moitie, _hauteurSignatures),
        const Radius.circular(14),
      );
      canvas.drawRRect(boite, Paint()..color = MboaColors.surface);
      canvas.drawRRect(
        boite,
        Paint()
          ..color = MboaColors.primary
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3,
      );

      _ecire(
        canvas,
        i == 0 ? 'Signature du vendeur' : 'Signature du client',
        style: MboaTypo.aide(couleur: MboaColors.textDoux)
            .copyWith(fontSize: 26, fontWeight: FontWeight.w800),
        y: signaturesHaut + 14,
        x: gauche + 16,
        largeur: moitie - 32,
        maxLines: 1,
      );
    }

    final pied = [
      if (liste.consommateurNom != null) liste.consommateurNom!,
      if (liste.consommateurTelephone != null) liste.consommateurTelephone!,
    ].join('  ·  ');

    _ecire(
      canvas,
      pied,
      style: MboaTypo.aide().copyWith(fontSize: 30),
      y: taille.height - _hauteurPied,
      largeur: largeurBandeau,
      centre: true,
    );
  }

  // --------------------------------------------------------------------------
  // Images
  // --------------------------------------------------------------------------

  /// Charge une image depuis un asset, une URL publique ou un chemin Storage.
  ///
  /// Renvoie null sur n'importe quel echec : le gabarit ne doit jamais
  /// echouer a cause du logo.
  static Future<ui.Image?> _chargerImage(String chemin) async {
    if (chemin.isEmpty) return null;

    try {
      if (chemin.startsWith('assets/')) {
        return await ui.imageFromAsset(chemin, 1.0);
      }

      final url = MboaReseau.urlPublique(chemin);
      if (url == null) return null;

      final octets = await telechargerBinaire(url);
      if (octets == null) return null;

      final codec = await ui.instantiateImageCodec(octets);
      final frame = await codec.getNextFrame();
      return frame.image;
    } catch (_) {
      return null;
    }
  }
}
