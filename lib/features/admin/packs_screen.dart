import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/data/models/catalogue.dart';
import '../../core/data/models/categorie.dart';
import '../../core/data/models/pack_composant.dart';
import '../../core/data/models/produit.dart';
import '../../core/data/models/unite.dart';
import '../../core/design_system/boutons.dart';
import '../../core/design_system/carte.dart';
import '../../core/design_system/picto.dart';
import '../../core/design_system/photo.dart';
import '../../core/etat/providers.dart';
import '../../core/theme/mboa_colors.dart';
import '../../core/theme/mboa_typography.dart';
import '../../core/utils/format_monnaie.dart';
import '../../core/voice/note_vocale.dart';
import '../../core/voice/tts_service.dart';

/// Les packs de plats prepares.
///
/// Un pack, c'est un repas deja calcule pour la mama : « Pack Ndolé, 3 boules
/// de ndolé, un paquet de crevettes, une bouteille d'huile rouge, cinq
/// morceaux de manioc ». Elle appuie une fois, elle a son diner.
///
/// C'est l'admin qui les compose, à partir du catalogue. Le comptoir prépare
/// et vend, il n'y a plus de producteur à choisir. Le serveur vérifie que
/// chaque ingrédient existe au catalogue, l'écran le montre.
class PacksScreen extends ConsumerWidget {
  const PacksScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final packs = ref.watch(packsProvider);

    return Scaffold(
      backgroundColor: MboaColors.background,
      appBar: AppBar(
        title: const Text('Packs de plats'),
        leading: IconButton(
          onPressed: () => Navigator.of(context).pop(),
          tooltip: 'Retour',
          iconSize: 36,
          icon: const PictoIcon(Picto.back, size: 36, couleur: MboaColors.surface),
        ),
      ),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: packs.maybeWhen(
                data: (liste) => liste.isEmpty
                    ? const _AucunPack()
                    : ListView.separated(
                        padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
                        itemCount: liste.length,
                        separatorBuilder: (context, index) => const SizedBox(height: 12),
                        itemBuilder: (context, index) => _CartePack(pack: liste[index]),
                      ),
                orElse: () => const Center(
                  child: CircularProgressIndicator(color: MboaColors.primary),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 18),
              child: GrosBouton(
                titre: 'Composer un pack',
                picto: Picto.leaf,
                sousTitre: 'Un plat, plusieurs ingrédients, un prix',
                sombre: true,
                minHeight: 104,
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (context) => const ComposerPackScreen()),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AucunPack extends StatelessWidget {
  const _AucunPack();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const PictoIcon(Picto.leaf, size: 110),
          const SizedBox(height: 20),
          Text('Aucun pack', style: MboaTypo.titre()),
          const SizedBox(height: 10),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 44),
            child: Text(
              'Compose le premier : la mama appuie une fois et elle a son repas',
              style: MboaTypo.aide(couleur: MboaColors.text),
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    );
  }
}

class _CartePack extends StatelessWidget {
  const _CartePack({required this.pack});

  final Produit pack;

  @override
  Widget build(BuildContext context) {
    return CarteBio(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              PhotoProduit(
                chemin: pack.photo,
                categorie: pack.categorie,
                slug: pack.slug,
                libelle: pack.nom,
                cote: 96,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(pack.nom, style: MboaTypo.titre()),
                    Text(
                      '${pack.composants.length} ingrédients',
                      style: MboaTypo.aide(),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      '${pack.quantite.toInt()} parts · ${pack.prix} F la part',
                      style: MboaTypo.corps(couleur: MboaColors.primary),
                    ),
                  ],
                ),
              ),
              BoutonVoix(texte: pack.annonceVocale),
            ],
          ),
          const Divider(height: 22),
          for (final c in pack.composants)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                children: [
                  PictoIcon(Picto.pourSlug(c.slug, pack.categorie), size: 26),
                  const SizedBox(width: 10),
                  Expanded(child: Text(c.annonce, style: MboaTypo.corps())),
                ],
              ),
            ),
          const SizedBox(height: 6),
          Text(
            'Prix de la part : ${formaterFcfa(pack.prix)}',
            style: MboaTypo.aide(),
          ),
        ],
      ),
    );
  }
}

/// La composition d'un pack.
///
/// Cinq gestes, dans l'ordre où l'admin pense : nommer le plat, choisir la
/// catégorie, toucher les ingrédients du catalogue, régler les quantités,
/// fixer le prix, photographier, décrire à voix. Pas de producteur à choisir
///, le comptoir prépare et vend.
class ComposerPackScreen extends ConsumerStatefulWidget {
  const ComposerPackScreen({this.pack, super.key});

  final Produit? pack;

  @override
  ConsumerState<ComposerPackScreen> createState() => _ComposerPackScreenState();
}

class _ComposerPackScreenState extends ConsumerState<ComposerPackScreen> {
  static const int _pasPrix = 50;

  final TextEditingController _nom = TextEditingController();

  /// Les composants, dans l'ordre où l'admin les a touchés. Cet ordre est
  /// gelé dans le JSONB et ressort tel quel chez la cliente.
  final Map<String, PackComposant> _composants = {};

  Categorie _categorie = Categorie.legume;
  int _prixPart = 2500;
  Uint8List? _photoOctets;
  String? _photoChemin;
  Uint8List? _noteOctets;
  String? _noteChemin;
  bool _occupee = false;
  String? _erreur;

  bool get _edition => widget.pack != null;

  List<PackComposant> get _liste => _composants.values.toList(growable: false);

  @override
  void initState() {
    super.initState();
    final existant = widget.pack;
    if (existant != null) {
      _nom.text = existant.nom;
      _prixPart = existant.prix;
      _photoChemin = existant.photoReelle;
      _categorie = existant.categorie;
      for (final c in existant.composants) {
        _composants[c.slug] = c;
      }
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      TtsService.instance.dire('Compose ton pack. Touche les ingrédients dans la grille.');
    });
  }

  @override
  void dispose() {
    _nom.dispose();
    super.dispose();
  }

  void _toucher(EntreeCatalogue entree) {
    final slug = entree.slug;
    setState(() {
      if (_composants.containsKey(slug)) {
        _composants.remove(slug);
      } else {
        _composants[slug] = PackComposant(
          slug: slug,
          nom: entree.nom,
          quantite: 1.0,
          unite: entree.uniteReelle,
        );
      }
    });
    TtsService.instance.dire(
      _composants.containsKey(slug)
          ? '${entree.nom} ajouté'
          : '${entree.nom} retiré',
    );
  }

  void _quantite(String slug, double delta) {
    final courant = _composants[slug];
    if (courant == null) return;
    final nouvelle = (courant.quantite + delta).clamp(1.0, 999.0).toDouble();
    setState(() {
      _composants[slug] = courant.copieAvec(quantite: nouvelle);
    });
    TtsService.instance.dire(courant.unite.avec(nouvelle));
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
      });
      await TtsService.instance.dire('Photo du plat enregistrée');
    } catch (e) {
      if (!mounted) return;
      setState(() => _erreur = 'La caméra ne répond pas');
    }
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
      return;
    }
    await note.enregistrer(dureeSecondes: 5);
  }

  Future<void> _enregistrer() async {
    final nom = _nom.text.trim();

    if (nom.length < 3) {
      setState(() => _erreur = 'Le nom du pack est trop court');
      await TtsService.instance.dire('Donne un nom au pack');
      return;
    }
    if (_liste.length < 2) {
      setState(() => _erreur = 'Un pack se compose d\'au moins deux ingrédients');
      await TtsService.instance.dire('Deux ingrédients au minimum');
      return;
    }
    if (!_edition && _photoOctets == null) {
      setState(() => _erreur = 'La photo du plat est nécessaire');
      await TtsService.instance.dire('Prends le plat en photo');
      return;
    }

    setState(() {
      _occupee = true;
      _erreur = null;
    });

    try {
      final depot = ref.read(depotProduitsProvider);

      if (_edition) {
        final ok = await depot.modifierPack(
          slug: widget.pack!.slug,
          composants: _liste,
          prixParPart: _prixPart,
        );
        if (!ok) {
          setState(() => _erreur = 'Le serveur a refusé la modification');
          return;
        }
      } else {
        final cree = await depot.creerPack(
          nom: nom,
          categorie: _categorie,
          composants: _liste,
          prixParPart: _prixPart,
          photoOctets: _photoOctets!,
          audioOctets: _noteOctets,
        );
        if (cree == null) {
          setState(() => _erreur =
              "Le serveur a refusé ce pack. Vérifie que tous les ingrédients sont au catalogue.");
          return;
        }
      }

      ref.invalidate(packsProvider);
      ref.invalidate(vitrineProvider(null));

      if (!mounted) return;
      await TtsService.instance.dire('$nom est en vente à $_prixPart francs la part');
      if (!mounted) return;
      Navigator.of(context).pop();
    } finally {
      if (mounted) setState(() => _occupee = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final catalogue = ref.watch(catalogueProvider);

    return Scaffold(
      backgroundColor: MboaColors.background,
      appBar: AppBar(
        title: Text(_edition ? 'Modifier le pack' : 'Composer un pack'),
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
                  // 1. Le nom
                  Text('Le nom du plat', style: MboaTypo.titre()),
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
                        hintText: 'Exemple : Pack Ndolé',
                        hintStyle: TextStyle(color: MboaColors.textDoux, fontSize: 24),
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),

                  // 1b. La catégorie
                  Text('La catégorie', style: MboaTypo.titre()),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final cat in Categorie.values)
                        ChoiceChip(
                          label: Text(
                            cat.libelle,
                            style: MboaTypo.corps(couleur: MboaColors.text),
                          ),
                          selected: _categorie == cat,
                          onSelected: (_) {
                            setState(() => _categorie = cat);
                            TtsService.instance.dire(cat.libelle);
                          },
                          backgroundColor: MboaColors.surface,
                          selectedColor: MboaColors.secondaryDoux,
                          side: const BorderSide(color: MboaColors.trait, width: 2),
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        ),
                    ],
                  ),
                  const SizedBox(height: 22),

                  // 2. Les ingrédients
                  Text('Ce qu\'il y a dedans', style: MboaTypo.titre()),
                  Text(
                    'Touche un produit pour l\'ajouter, retouche pour l\'enlever',
                    style: MboaTypo.aide(),
                  ),
                  const SizedBox(height: 10),
                  catalogue.maybeWhen(
                    data: (entrees) => GridView.count(
                      crossAxisCount: 3,
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      mainAxisSpacing: 10,
                      crossAxisSpacing: 10,
                      childAspectRatio: 0.86,
                      children: [
                        for (final entree in entrees)
                          _TuileIngredient(
                            entree: entree,
                            composant: _composants[entree.slug],
                            onTap: () => _toucher(entree),
                          ),
                      ],
                    ),
                    orElse: () => const Padding(
                      padding: EdgeInsets.all(20),
                      child: Center(
                        child: CircularProgressIndicator(color: MboaColors.primary),
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),
                  if (_liste.isNotEmpty)
                    _ReglageQuantites(
                      composants: _liste,
                      categorie: _categorie,
                      onDelta: _quantite,
                    ),

                  const SizedBox(height: 22),

                  // 3. Le prix
                  Text('Le prix de la part', style: MboaTypo.titre()),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      BoutonCarre(
                        picto: Picto.minus,
                        taille: 88,
                        onTap: _prixPart <= _pasPrix ? null : () => setState(() => _prixPart -= _pasPrix),
                        annonce: 'Moins cinquante francs',
                      ),
                      Expanded(
                        child: Center(
                          child: Text(formaterFcfa(_prixPart), style: MboaTypo.chiffreGeant()),
                        ),
                      ),
                      BoutonCarre(
                        picto: Picto.plus,
                        taille: 88,
                        couleurFond: MboaColors.primary,
                        couleurTrait: MboaColors.primary,
                        onTap: () => setState(() => _prixPart += _pasPrix),
                        annonce: 'Plus cinquante francs',
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'Coût estimé des ingrédients : ${formaterFcfa(_coutIngredients)}',
                    style: MboaTypo.aide(),
                    textAlign: TextAlign.center,
                  ),

                  const SizedBox(height: 22),

                  // 4. La photo et la voix
                  GrosBouton(
                    titre: _photoChemin == null ? 'Photographier le plat' : 'Photo prise',
                    picto: Picto.camera,
                    secondaire: true,
                    minHeight: 96,
                    onTap: _prendrePhoto,
                  ),
                  const SizedBox(height: 10),
                  GrosBouton(
                    titre: _noteOctets == null ? 'Décrire le plat' : 'Message enregistré',
                    picto: Picto.mic,
                    secondaire: true,
                    minHeight: 96,
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
                    titre: _edition ? 'Enregistrer' : 'Mettre ce pack en vente',
                    picto: Picto.check,
                    sombre: true,
                    minHeight: 104,
                    onTap: _enregistrer,
                  ),
                ],
              ),
      ),
    );
  }

  int get _coutIngredients => _liste.fold(
        0,
        (somme, c) => somme + (c.quantite * _prixCatalogue(c.slug)).round(),
      );

  /// Le prix de tendance d'un ingrédient, depuis le catalogue en cache.
  int _prixCatalogue(String slug) {
    final entrees = ref.read(catalogueProvider).valueOrNull ?? const [];
    final entree = entrees.where((e) => e.slug == slug).firstOrNull;
    return entree?.prixTendance ?? 500;
  }
}

/// Une tuile de la grille du catalogue, avec son état de sélection.
class _TuileIngredient extends StatelessWidget {
  const _TuileIngredient({
    required this.entree,
    required this.composant,
    required this.onTap,
  });

  final EntreeCatalogue entree;
  final PackComposant? composant;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final choisi = composant != null;

    return CarteBio(
      onTap: onTap,
      couleurFond: choisi ? MboaColors.secondaryDoux : MboaColors.surface,
      couleurTrait: choisi ? MboaColors.primary : MboaColors.trait,
      padding: const EdgeInsets.fromLTRB(6, 8, 6, 6),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: PhotoProduit(
              chemin: '',
              categorie: entree.categorie,
              slug: entree.slug,
              libelle: entree.nom,
              cote: 74,
              cadre: false,
            ),
          ),
          Text(
            entree.nom,
            style: MboaTypo.aide(couleur: MboaColors.text),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
          ),
          if (choisi)
            Text(
              composant!.libelleCourt,
              style: MboaTypo.chiffre(couleur: MboaColors.primary).copyWith(fontSize: 22),
            )
          else
            const SizedBox(height: 22),
        ],
      ),
    );
  }
}

/// Le réglage fin des quantités, sous la grille.
class _ReglageQuantites extends StatelessWidget {
  const _ReglageQuantites({
    required this.composants,
    required this.categorie,
    required this.onDelta,
  });

  final List<PackComposant> composants;
  final Categorie categorie;
  final void Function(String, double) onDelta;

  @override
  Widget build(BuildContext context) {
    return CarteBio(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final c in composants)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                children: [
                  PictoIcon(Picto.pourSlug(c.slug, categorie), size: 34),
                  const SizedBox(width: 12),
                  Expanded(child: Text(c.libelle, style: MboaTypo.corps())),
                  BoutonCarre(
                    picto: Picto.minus,
                    taille: 64,
                    onTap: c.quantite <= 1 ? null : () => onDelta(c.slug, -1),
                  ),
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 96,
                    child: Text(
                      c.libelleCourt,
                      style: MboaTypo.chiffre().copyWith(fontSize: 24),
                      textAlign: TextAlign.center,
                    ),
                  ),
                  const SizedBox(width: 8),
                  BoutonCarre(
                    picto: Picto.plus,
                    taille: 64,
                    couleurFond: MboaColors.primary,
                    couleurTrait: MboaColors.primary,
                    onTap: () => onDelta(c.slug, 1),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
