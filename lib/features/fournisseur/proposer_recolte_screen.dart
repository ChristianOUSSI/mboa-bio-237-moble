import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/data/models/catalogue.dart';
import '../../core/data/models/categorie.dart';
import '../../core/data/models/fournisseur.dart';
import '../../core/data/models/unite.dart';
import '../../core/design_system/boutons.dart';
import '../../core/design_system/carte.dart';
import '../../core/design_system/picto.dart';
import '../../core/etat/providers.dart';
import '../../core/theme/mboa_colors.dart';
import '../../core/theme/mboa_typography.dart';
import '../../core/utils/format_monnaie.dart';
import '../../core/utils/identifiants.dart';
import '../../core/voice/note_vocale.dart';
import '../../core/voice/tts_service.dart';
import 'mes_achats_screen.dart';

/// Ce que l'agriculteur a, combien, comment ca se compte, et son prix.
///
/// Cinq gestes, toujours dans le meme ordre : la photo, le nom, la case, la
/// mesure, le prix. La photo vient d'abord parce que MBOA achete sur image :
/// une proposition sans photo ferait revenir le comptoir au champ.
///
/// Le meme ecran sert au comptoir quand il achete pour une fiche sans compte
/// (`pour` non null) : la saisie, les controles et la file sont identiques,
/// seule la porte du serveur change.
///
/// Hors connexion, rien n'est perdu : la photo est ecrite sur le telephone et
/// la proposition attend dans la file avec elle.
class ProposerRecolteScreen extends ConsumerStatefulWidget {
  const ProposerRecolteScreen({this.pour, super.key});

  /// La fiche au nom de laquelle le comptoir saisit l'achat. Null quand
  /// l'agriculteur propose lui-meme.
  final Fournisseur? pour;

  @override
  ConsumerState<ProposerRecolteScreen> createState() => _ProposerRecolteScreenState();
}

class _ProposerRecolteScreenState extends ConsumerState<ProposerRecolteScreen> {
  final TextEditingController _nom = TextEditingController();
  final TextEditingController _quantite = TextEditingController(text: '1');
  final TextEditingController _prix = TextEditingController(text: '500');

  Categorie _categorie = Categorie.fruit;
  Unite _unite = Unite.kg;

  Uint8List? _photoOctets;
  String? _photoChemin;
  Uint8List? _noteOctets;
  String? _noteChemin;

  bool _occupee = false;
  String? _erreur;

  @override
  void initState() {
    super.initState();
    final fiche = widget.pour;
    if (fiche != null) {
      _unite = fiche.unite;
      final categorie = fiche.productionCategorie;
      if (categorie != null) _categorie = categorie;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      TtsService.instance.dire(
        fiche == null
            ? 'Dis ce que tu as. La photo d\'abord, puis le nom, la case, la mesure et ton prix.'
            : 'Achat pour ${fiche.nom}. Prends la marchandise en photo, puis note ce qu\'il a apporté.',
      );
    });
  }

  @override
  void dispose() {
    _nom.dispose();
    _quantite.dispose();
    _prix.dispose();
    super.dispose();
  }

  double get _pasQuantite => _unite.estPoids ? 0.5 : 1.0;

  double get _quantiteValeur {
    final brut = _quantite.text.replaceAll(',', '.').trim();
    return double.tryParse(brut) ?? 0;
  }

  int get _prixValeur {
    final brut = _prix.text.replaceAll(RegExp(r'[^0-9]'), '');
    return int.tryParse(brut) ?? 0;
  }

  String? get _prixMarche {
    final entrees = ref.watch(catalogueProvider).valueOrNull ?? const <EntreeCatalogue>[];
    final slug = Identifiants.slugDe(_nom.text);
    final entree = entrees.where((e) => e.slug == slug).firstOrNull;
    if (entree == null || entree.prixTendance <= 0) return null;
    return formaterFcfaCourt(entree.prixTendance);
  }

  Future<void> _prendrePhoto() async {
    try {
      final prise = await ImagePicker().pickImage(
        source: ImageSource.camera,
        maxWidth: 1280,
        imageQuality: 72,
      );
      if (prise == null) return;
      final octets = await File(prise.path).readAsBytes();
      if (!mounted) return;
      setState(() {
        _photoOctets = octets;
        _photoChemin = prise.path;
        _erreur = null;
      });
      await TtsService.instance.dire('Photo de la récolte enregistrée');
    } catch (e) {
      if (!mounted) return;
      setState(() => _erreur = 'La caméra ne répond pas');
    }
  }

  void _changerQuantite(double delta) {
    final nouvelle = (_quantiteValeur + delta).clamp(_pasQuantite, 99999.0);
    setState(() {
      _quantite.text = formaterKg(nouvelle);
    });
    TtsService.instance.dire(_unite.avec(nouvelle));
  }

  void _changerPrix(int delta) {
    final nouveau = (_prixValeur + delta).clamp(1, 1000000);
    setState(() {
      _prix.text = '$nouveau';
    });
    TtsService.instance.dire('${formaterFcfa(nouveau)} ${_unite.avecArticle}');
  }

  void _prendrePrixDuMarche() {
    final entrees = ref.read(catalogueProvider).valueOrNull ?? const <EntreeCatalogue>[];
    final slug = Identifiants.slugDe(_nom.text);
    final entree = entrees.where((e) => e.slug == slug).firstOrNull;
    if (entree == null) return;
    setState(() => _prix.text = '${entree.prixTendance}');
    TtsService.instance.dire('${formaterFcfa(entree.prixTendance)} ${_unite.avecArticle}');
  }

  Future<void> _enregistrerNote() async {
    final note = ref.read(noteProvider);
    if (note.enCours) {
      final chemin = await note.couper();
      if (chemin == null || !mounted) return;
      final octets = await File(chemin).readAsBytes();
      if (!mounted) return;
      setState(() {
        _noteChemin = chemin;
        _noteOctets = octets;
      });
      await TtsService.instance.dire('Message enregistré');
      return;
    }
    await note.enregistrer(dureeSecondes: 5);
  }

  Future<void> _envoyer() async {
    final nom = _nom.text.trim();

    if (_photoOctets == null) {
      setState(() => _erreur = 'La photo de la récolte est nécessaire');
      await TtsService.instance.dire('Prends la récolte en photo');
      return;
    }
    if (nom.length < 2) {
      setState(() => _erreur = 'Le nom de la marchandise est trop court');
      await TtsService.instance.dire('Dis ce que tu as');
      return;
    }
    if (_quantiteValeur <= 0) {
      setState(() => _erreur = 'La quantité doit être plus grande que zéro');
      await TtsService.instance.dire('Combien tu en as ?');
      return;
    }
    if (_prixValeur < 1) {
      setState(() => _erreur = 'Le prix doit être plus grand que zéro');
      await TtsService.instance.dire('Ton prix ?');
      return;
    }

    setState(() {
      _occupee = true;
      _erreur = null;
    });

    try {
      final depot = ref.read(depotAchatsProvider);
      final fiche = widget.pour;
      final achat = fiche == null
          ? await depot.proposer(
              nom: nom,
              categorie: _categorie,
              quantite: _quantiteValeur,
              unite: _unite,
              prixDemande: _prixValeur,
              photoOctets: _photoOctets!,
              audioOctets: _noteOctets,
            )
          : await depot.proposerPour(
              fournisseurId: fiche.id,
              nom: nom,
              categorie: _categorie,
              quantite: _quantiteValeur,
              unite: _unite,
              prixDemande: _prixValeur,
              photoOctets: _photoOctets!,
              audioOctets: _noteOctets,
            );

      if (achat == null) {
        setState(() {
          _erreur = fiche == null
              ? 'Le comptoir n\'a pas reçu la proposition. Réessaie dans un instant.'
              : 'L\'achat n\'a pas pu être envoyé. Vérifie le réseau et réessaie.';
        });
        return;
      }

      ref.invalidate(achatsEnAttenteProvider);

      final String message;
      if (fiche == null) {
        ref.invalidate(mesAchatsProvider);
        ref.invalidate(mesGainsProvider);
        final enAttente = !achat.photoUrl.startsWith('http') &&
            !achat.photoUrl.startsWith('produits/');
        message = enAttente
            ? '$nom attend sur le téléphone. Il partira avec le réseau.'
            : '$nom est proposé au comptoir.';
      } else {
        message = '$nom est saisi pour ${fiche.nom}.';
      }

      if (!mounted) return;
      await TtsService.instance.dire(message);
      if (!mounted) return;
      Navigator.of(context).pop();
    } finally {
      if (mounted) setState(() => _occupee = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: MboaColors.background,
      appBar: AppBar(
        title: Text(widget.pour == null ? 'Vendre ma récolte' : 'Achat pour ${widget.pour!.nom}'),
        leading: IconButton(
          onPressed: () => Navigator.of(context).pop(),
          tooltip: 'Retour',
          iconSize: 36,
          icon: const PictoIcon(Picto.back, size: 36, couleur: MboaColors.surface),
        ),
        actions: [
          if (widget.pour == null)
            IconButton(
              onPressed: () => Navigator.of(context).pushReplacement(
                MaterialPageRoute(builder: (context) => const MesAchatsScreen()),
              ),
              tooltip: 'Mes achats',
              iconSize: 34,
              icon: const PictoIcon(Picto.basket, size: 34, couleur: MboaColors.surface),
            ),
        ],
      ),
      body: SafeArea(
        child: _occupee
            ? const Center(child: CircularProgressIndicator(color: MboaColors.primary))
            : ListView(
                padding: const EdgeInsets.fromLTRB(18, 16, 18, 28),
                children: [
                  const _SectionTitre(
                    titre: 'La photo de la récolte',
                    aide: 'Le comptoir achète sur image',
                  ),
                  const SizedBox(height: 8),
                  if (_photoOctets != null) ...[
                    ClipRRect(
                      borderRadius: BorderRadius.circular(20),
                      child: Image.memory(
                        _photoOctets!,
                        height: 210,
                        width: double.infinity,
                        fit: BoxFit.cover,
                      ),
                    ),
                    const SizedBox(height: 8),
                  ],
                  GrosBouton(
                    titre: _photoOctets == null ? 'Photographier' : 'Refaire la photo',
                    picto: Picto.camera,
                    sousTitre: _photoChemin == null ? null : 'La photo est gardée sur le téléphone',
                    sombre: _photoOctets == null,
                    secondaire: _photoOctets != null,
                    minHeight: 96,
                    onTap: _prendrePhoto,
                  ),
                  const SizedBox(height: 22),

                  _SectionTitre(
                    titre: widget.pour == null ? 'Ce que tu as' : 'Ce qu\'il a',
                    aide: 'Un mot court, comme au marché',
                  ),
                  const SizedBox(height: 8),
                  CarteBio(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    child: TextField(
                      controller: _nom,
                      style: MboaTypo.titre(),
                      textCapitalization: TextCapitalization.words,
                      onChanged: (_) => setState(() {}),
                      decoration: const InputDecoration(
                        border: InputBorder.none,
                        hintText: 'Exemple : Manioc',
                        hintStyle: TextStyle(color: MboaColors.textDoux, fontSize: 24),
                      ),
                    ),
                  ),
                  const SizedBox(height: 22),

                  const _SectionTitre(
                    titre: 'La case',
                    aide: 'Touche le dessin qui lui ressemble',
                  ),
                  const SizedBox(height: 10),
                  GridView.count(
                    crossAxisCount: 2,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    mainAxisSpacing: 10,
                    crossAxisSpacing: 10,
                    childAspectRatio: 2.7,
                    children: [
                      for (final cat in Categorie.values)
                        _TuileCategorie(
                          categorie: cat,
                          choisi: _categorie == cat,
                          onTap: () {
                            setState(() => _categorie = cat);
                            TtsService.instance.dire(cat.libelleVoice);
                          },
                        ),
                    ],
                  ),
                  const SizedBox(height: 22),

                  const _SectionTitre(
                    titre: 'La mesure',
                    aide: 'Comment ça se compte',
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final unite in Unite.values)
                        ChoiceChip(
                          label: Text(
                            unite.pluriel,
                            style: MboaTypo.corps(couleur: MboaColors.text),
                          ),
                          selected: _unite == unite,
                          onSelected: (_) {
                            setState(() => _unite = unite);
                            TtsService.instance.dire('Les ${unite.pluriel}');
                          },
                          backgroundColor: MboaColors.surface,
                          selectedColor: MboaColors.secondaryDoux,
                          side: const BorderSide(color: MboaColors.trait, width: 2),
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  _ChampNombre(
                    controleur: _quantite,
                    suffixe: _unite.pour(_quantiteValeur),
                    annonceMoins: 'Moins ${_unite.avec(_pasQuantite)}',
                    annoncePlus: 'Plus ${_unite.avec(_pasQuantite)}',
                    onMoins: _quantiteValeur <= _pasQuantite ? null : () => _changerQuantite(-_pasQuantite),
                    onPlus: () => _changerQuantite(_pasQuantite),
                    onSaisie: (_) => setState(() {}),
                  ),
                  const SizedBox(height: 22),

                  _SectionTitre(
                    titre: widget.pour == null ? 'Ton prix' : 'Son prix',
                    aide: 'Le prix d\'une ${_unite.un}',
                  ),
                  const SizedBox(height: 8),
                  _ChampNombre(
                    controleur: _prix,
                    suffixe: 'F ${_unite.avecArticle}',
                    annonceMoins: 'Moins cinquante francs',
                    annoncePlus: 'Plus cinquante francs',
                    onMoins: _prixValeur <= 50 ? null : () => _changerPrix(-50),
                    onPlus: () => _changerPrix(50),
                    onSaisie: (_) => setState(() {}),
                  ),
                  if (_prixMarche != null) ...[
                    const SizedBox(height: 10),
                    GrosBouton(
                      titre: 'Prix du marché',
                      chiffre: _prixMarche,
                      picto: Picto.priceTag,
                      secondaire: true,
                      minHeight: 80,
                      onTap: _prendrePrixDuMarche,
                    ),
                  ],
                  const SizedBox(height: 20),

                  GrosBouton(
                    titre: _noteOctets == null ? 'Décrire à voix' : 'Message enregistré',
                    picto: Picto.mic,
                    secondaire: true,
                    minHeight: 88,
                    onTap: _enregistrerNote,
                  ),

                  if (_erreur != null) ...[
                    const SizedBox(height: 16),
                    BandeauEtat(
                      texte: _erreur!,
                      couleur: MboaColors.error,
                      icone: const PictoIcon(Picto.alert, size: 30, couleur: MboaColors.error),
                    ),
                  ],

                  const SizedBox(height: 22),
                  GrosBouton(
                    titre: widget.pour == null
                        ? 'Proposer au comptoir'
                        : 'Saisir pour ${widget.pour!.nom}',
                    picto: Picto.handGive,
                    sousTitre: 'Le comptoir regarde et répond',
                    sombre: true,
                    minHeight: 108,
                    onTap: _envoyer,
                  ),
                ],
              ),
      ),
    );
  }
}

class _SectionTitre extends StatelessWidget {
  const _SectionTitre({required this.titre, required this.aide});

  final String titre;
  final String aide;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(titre, style: MboaTypo.titre()),
        Text(aide, style: MboaTypo.aide(couleur: MboaColors.text)),
      ],
    );
  }
}

/// Une case du catalogue, avec son dessin. La case choisie se remplit de vert
/// clair : sur un telephone au soleil, un simple filet ne se voit pas.
class _TuileCategorie extends StatelessWidget {
  const _TuileCategorie({
    required this.categorie,
    required this.choisi,
    required this.onTap,
  });

  final Categorie categorie;
  final bool choisi;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return CarteBio(
      onTap: onTap,
      couleurFond: choisi ? MboaColors.secondaryDoux : MboaColors.surface,
      couleurTrait: choisi ? MboaColors.primary : MboaColors.trait,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      child: Row(
        children: [
          PictoIcon(Picto.pourCategorie(categorie), size: 34),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              categorie.libelle,
              style: MboaTypo.corps(couleur: MboaColors.text),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

/// Un nombre qu'on peut soit taper, soit pousser par gros boutons.
///
/// Les deux existent ensemble : pousser arrange celui qui ne veut pas du
/// clavier, taper arrange celui qui vend deux cents kilos. Un seul des deux
/// aurait exclu la moitie des utilisateurs.
class _ChampNombre extends StatelessWidget {
  const _ChampNombre({
    required this.controleur,
    required this.suffixe,
    required this.annonceMoins,
    required this.annoncePlus,
    required this.onMoins,
    required this.onPlus,
    required this.onSaisie,
  });

  final TextEditingController controleur;
  final String suffixe;
  final String annonceMoins;
  final String annoncePlus;
  final VoidCallback? onMoins;
  final VoidCallback onPlus;
  final ValueChanged<String> onSaisie;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        BoutonCarre(
          picto: Picto.minus,
          taille: 80,
          onTap: onMoins,
          annonce: annonceMoins,
        ),
        const SizedBox(width: 10),
        Expanded(
          child: CarteBio(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: controleur,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'[0-9,\.]')),
                    ],
                    textAlign: TextAlign.center,
                    style: MboaTypo.chiffreGeant(),
                    onChanged: onSaisie,
                    decoration: const InputDecoration(
                      border: InputBorder.none,
                      isDense: true,
                    ),
                  ),
                ),
                Text(
                  suffixe,
                  style: MboaTypo.corps(couleur: MboaColors.textDoux),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 10),
        BoutonCarre(
          picto: Picto.plus,
          taille: 80,
          couleurFond: MboaColors.primary,
          couleurTrait: MboaColors.primary,
          onTap: onPlus,
          annonce: annoncePlus,
        ),
      ],
    );
  }
}
