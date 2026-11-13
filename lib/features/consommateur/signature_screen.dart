import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/design_system/boutons.dart';
import '../../core/design_system/carte.dart';
import '../../core/design_system/picto.dart';
import '../../core/design_system/photo.dart';
import '../../core/etat/providers.dart';
import '../../core/theme/mboa_colors.dart';
import '../../core/theme/mboa_typography.dart';
import '../../core/utils/format_monnaie.dart';
import '../../core/voice/tts_service.dart';
import 'suivi_screen.dart';

/// La preuve que c'est bien elle qui a commande.
///
/// Deux moyens, au choix, et souvent les deux :
///   * dessiner sa signature au doigt, meme sans savoir ecrire son nom ;
///   * se prendre en photo a cote du panier.
///
/// La signature n'est pas comparee, pas normalisee, pas analysee : elle est
/// stockee comme image, horodatee, et rattachee a la commande. C'est une
/// preuve pour un litige futur, pas un controle.
///
/// Depuis le paiement a la porte, cet ecran n'encaisse rien. Il ferme la
/// commande : c'est le dernier geste avant que la moto parte.
class SignatureScreen extends ConsumerStatefulWidget {
  const SignatureScreen({required this.livraisonMoto, super.key});

  final bool livraisonMoto;

  @override
  ConsumerState<SignatureScreen> createState() => _SignatureScreenState();
}

class _SignatureScreenState extends ConsumerState<SignatureScreen> {
  static const double _hauteurPad = 220;

  final List<List<Offset>> _signes = [];

  /// La taille reelle du pad, relevee par le LayoutBuilder. Les points du
  /// geste sont deja dans ce referentiel : sans cette mesure, la copie
  /// rasterisee serait decalee ou etiree.
  Size _taillePad = Size.zero;

  Uint8List? _photoOctets;
  String? _photoChemin;
  bool _occupee = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      TtsService.instance.dire('Signez avec votre doigt dans le cadre blanc.');
    });
  }

  void _commencer(Offset position) => setState(() => _signes.add([position]));

  void _bouger(Offset position) {
    if (_signes.isEmpty) return;
    setState(() => _signes.last.add(position));
  }

  bool get _signee => _signes.any((s) => s.length > 2);

  Future<void> _prendrePhoto() async {
    try {
      final prise = await ImagePicker().pickImage(
        source: ImageSource.camera,
        maxWidth: 900,
        imageQuality: 70,
      );
      if (prise == null) return;
      final octets = await File(prise.path).readAsBytes();
      if (!mounted) return;
      setState(() {
        _photoOctets = octets;
        _photoChemin = prise.path;
      });
      await TtsService.instance.dire('Photo enregistrée');
    } catch (e) {
      if (!mounted) return;
      await TtsService.instance.dire('La caméra ne répond pas');
    }
  }

  Future<Uint8List?> _rasteriser() async {
    if (!_signee || _taillePad.isEmpty) return null;

    final largeur = _taillePad.width.round();
    final hauteur = _taillePad.height.round();

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);

    final encre = Paint()
      ..color = MboaColors.text
      ..strokeWidth = 5
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;

    for (final signe in _signes) {
      if (signe.length < 2) continue;
      canvas.drawPoints(ui.PointMode.polygon, signe, encre);
    }

    final picture = recorder.endRecording();
    final image = await picture.toImage(largeur, hauteur);
    final octets = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    return octets?.buffer.asUint8List();
  }

  Future<void> _valider() async {
    final session = ref.read(sessionProvider);
    final panier = ref.read(panierProvider);
    if (session == null || panier.vide) return;

    setState(() => _occupee = true);
    try {
      final vitrine = ref.read(vitrineProvider(null)).valueOrNull ?? const [];
      final premiere = vitrine.where((p) => p.id == panier.articles.first.produitId).toList();

      final commande = await ref.read(depotCommandesProvider).commander(
            consommateurId: session.identifiant,
            lignes: panier.articles,
            livraisonMoto: widget.livraisonMoto,
            photoOctets: _photoOctets,
          );

      // La signature part apres la commande : elle lui est rattachee, et un
      // echec d'ecriture ne doit pas empecher la commande d'exister.
      final trace = await _rasteriser();
      if (trace != null) {
        await ref.read(depotCommandesProvider).marquerSignature(commande.id, trace);
      }

      ref.read(panierProvider.notifier).vider();

      if (!mounted) return;
      await TtsService.instance.dire('Commande enregistrée. Vous payez à la livraison.');
      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (context) => SuiviScreen(commande: commande)),
        (route) => false,
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _occupee = false);
      await TtsService.instance.dire(
        'La caisse ne répond pas. Gardez cette page ouverte, on réessaie.',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final panier = ref.watch(panierProvider);

    return Scaffold(
      backgroundColor: MboaColors.background,
      appBar: AppBar(
        title: const Text('C’est moi'),
        leading: IconButton(
          onPressed: () => Navigator.of(context).pop(),
          tooltip: 'Retour',
          iconSize: 36,
          icon: const PictoIcon(Picto.back, size: 36, couleur: MboaColors.surface),
        ),
      ),
      body: SafeArea(
        child: _occupee
            ? const Center(child: CircularProgressIndicator(color: MboaColors.primary))
            : ListView(
                padding: const EdgeInsets.fromLTRB(18, 16, 18, 26),
                children: [
                  CarteBio(
                    padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                    child: Row(
                      children: [
                        const PictoIcon(Picto.especes, size: 36),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            widget.livraisonMoto
                                ? 'Vous payez à la porte de chez vous'
                                : 'Vous payez au point de collecte',
                            style: MboaTypo.corps(),
                          ),
                        ),
                        Text(formaterFcfa(panier.montantTotal), style: MboaTypo.chiffre()),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text('Ma signature', style: MboaTypo.titre()),
                  const SizedBox(height: 10),
                  LayoutBuilder(
                    builder: (context, contraintes) {
                      _taillePad = Size(contraintes.maxWidth, _hauteurPad);
                      return Container(
                        height: _hauteurPad,
                        decoration: BoxDecoration(
                          color: MboaColors.surface,
                          borderRadius: BorderRadius.circular(22),
                          border: Border.all(color: MboaColors.primary, width: 3),
                        ),
                        child: GestureDetector(
                          onPanStart: (details) => _commencer(details.localPosition),
                          onPanUpdate: (details) => _bouger(details.localPosition),
                          child: CustomPaint(
                            painter: _PadSignature(signes: _signes),
                            child: Center(
                              child: Text(
                                _signee ? '' : 'Signez ici',
                                style: MboaTypo.corps(couleur: MboaColors.textDoux),
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: GrosBouton(
                          titre: 'Effacer',
                          picto: Picto.minus,
                          secondaire: true,
                          onTap: () {
                            setState(_signes.clear);
                            TtsService.instance.dire('Signature effacée');
                          },
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: GrosBouton(
                          titre: 'Aide',
                          picto: Picto.speaker,
                          secondaire: true,
                          onTap: () => TtsService.instance.dire(
                            'Signez avec le doigt dans le cadre. Vous pouvez effacer et recommencer.',
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 22),
                  GrosBouton(
                    titre: _photoChemin == null ? 'Me prendre en photo' : 'Photo prise',
                    picto: Picto.camera,
                    sousTitre: 'Facultatif, mais plus sûr',
                    secondaire: true,
                    minHeight: 96,
                    image: _photoChemin == null
                        ? null
                        : PhotoRonde(chemin: _photoChemin!, cote: 64),
                    onTap: _prendrePhoto,
                  ),
                  const SizedBox(height: 16),
                  GrosBouton(
                    titre: 'J’ai signé',
                    picto: Picto.check,
                    sombre: _signee,
                    minHeight: 112,
                    onTap: _signee ? _valider : null,
                  ),
                ],
              ),
      ),
    );
  }
}

/// Le pad : les traits deja traces, et la ligne de sol qui guide le geste.
class _PadSignature extends CustomPainter {
  _PadSignature({required this.signes});

  final List<List<Offset>> signes;

  @override
  void paint(Canvas canvas, Size taille) {
    final guide = Paint()
      ..color = MboaColors.trait
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(
      Offset(taille.width * 0.08, taille.height * 0.68),
      Offset(taille.width * 0.92, taille.height * 0.68),
      guide,
    );

    final encre = Paint()
      ..color = MboaColors.text
      ..strokeWidth = 5
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;

    for (final signe in signes) {
      if (signe.length < 2) continue;
      canvas.drawPoints(ui.PointMode.polygon, signe, encre);
    }
  }

  @override
  bool shouldRepaint(_PadSignature ancien) => ancien.signes != signes;
}
