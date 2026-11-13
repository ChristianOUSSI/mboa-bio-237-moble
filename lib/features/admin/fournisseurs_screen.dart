import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/data/depot_auth.dart' show normaliserTelephone;
import '../../core/data/models/categorie.dart';
import '../../core/data/models/fournisseur.dart';
import '../../core/data/models/unite.dart';
import '../../core/design_system/boutons.dart';
import '../../core/design_system/carte.dart';
import '../../core/design_system/picto.dart';
import '../../core/design_system/photo.dart';
import '../../core/etat/providers.dart';
import '../../core/theme/mboa_colors.dart';
import '../../core/theme/mboa_typography.dart';
import '../../core/voice/tts_service.dart';
import '../auth/pave_numerique.dart';
import '../fournisseur/proposer_recolte_screen.dart';

/// Le fichier des producteurs du comptoir.
///
/// Une fiche peut exister sans compte : le comptoir achete chez des gens qui
/// n'ont pas de smartphone. Le jour ou la personne installe l'application
/// avec le meme numero, le serveur rattache la fiche toute seule. L'admin n'a
/// donc pas de lien a gerer, seulement des fiches a tenir.
class FournisseursScreen extends ConsumerWidget {
  const FournisseursScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final fournisseurs = ref.watch(fournisseursProvider);

    return Scaffold(
      backgroundColor: MboaColors.background,
      appBar: AppBar(
        title: const Text('Fournisseurs'),
        leading: IconButton(
          onPressed: () => Navigator.of(context).pop(),
          tooltip: 'Retour',
          iconSize: 36,
          icon: const PictoIcon(Picto.back, size: 36, couleur: MboaColors.surface),
        ),
        actions: [
          IconButton(
            onPressed: () => ref.invalidate(fournisseursProvider),
            tooltip: 'Rafraîchir',
            iconSize: 34,
            icon: const PictoIcon(Picto.sync, size: 34, couleur: MboaColors.surface),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: fournisseurs.maybeWhen(
                data: (liste) => liste.isEmpty
                    ? const _Personne()
                    : ListView.separated(
                        padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
                        itemCount: liste.length,
                        separatorBuilder: (context, index) => const SizedBox(height: 12),
                        itemBuilder: (context, index) => _CarteFournisseur(fiche: liste[index]),
                      ),
                orElse: () => const Center(
                  child: CircularProgressIndicator(color: MboaColors.primary),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 18),
              child: GrosBouton(
                titre: 'Ajouter un fournisseur',
                picto: Picto.plus,
                sombre: true,
                minHeight: 104,
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (context) => const FicheFournisseurScreen()),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Personne extends StatelessWidget {
  const _Personne();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const PictoIcon(Picto.person, size: 110),
          const SizedBox(height: 20),
          Text('Aucun fournisseur', style: MboaTypo.titre()),
          const SizedBox(height: 10),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 44),
            child: Text(
              'Ajoute un producteur du village. Sa fiche vit même sans téléphone.',
              style: MboaTypo.aide(couleur: MboaColors.text),
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    );
  }
}

class _CarteFournisseur extends ConsumerWidget {
  const _CarteFournisseur({required this.fiche});

  final Fournisseur fiche;

  Future<void> _appeler() async {
    if (fiche.telephone.isEmpty) {
      await TtsService.instance.dire('Pas de numéro pour ce fournisseur');
      return;
    }
    await TtsService.instance.dire('J’appelle ${fiche.nom}');
    if (!await launchUrl(Uri.parse('tel:${fiche.telephone}'))) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Appel impossible : ${fiche.telephone}')),
      );
    }
  }

  Future<void> _retirer(WidgetRef ref) async {
    final sur = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Retirer ce fournisseur ?'),
        content: Text('${fiche.nom} ne recevra plus d’achat. Ses achats passés restent.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Non')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Retirer')),
        ],
      ),
    );
    if (sur != true) return;

    await ref.read(depotFournisseursProvider).desactiver(fiche.id);
    ref.invalidate(fournisseursProvider);
    await TtsService.instance.dire('${fiche.nom} retiré du fichier');
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return CarteBio(
      couleurTrait: fiche.actif ? MboaColors.trait : MboaColors.error,
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(builder: (context) => FicheFournisseurScreen(fiche: fiche)),
      ),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              PhotoRonde(chemin: fiche.photo ?? '', cote: 72, quandAbsente: Picto.person),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(fiche.nom, style: MboaTypo.titre()),
                    Text(
                      '${fiche.village} · ${fiche.production}',
                      style: MboaTypo.aide(),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(fiche.unite.pluriel, style: MboaTypo.corps()),
                  Text(
                    fiche.lie ? 'compte lié' : 'sans compte',
                    style: MboaTypo.aide(
                      couleur: fiche.lie ? MboaColors.primary : MboaColors.textDoux,
                    ),
                  ),
                  if (!fiche.actif)
                    Text('retiré', style: MboaTypo.aide(couleur: MboaColors.error)),
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              BoutonCarre(
                picto: Picto.phone,
                taille: 72,
                onTap: _appeler,
                annonce: 'Appeler ${fiche.nom}',
              ),
              const SizedBox(width: 10),
              BoutonCarre(
                picto: Picto.speaker,
                taille: 72,
                couleurFond: MboaColors.background,
                onTap: () => TtsService.instance.dire(fiche.annonce),
                annonce: 'Écouter la fiche',
              ),
              const Spacer(),
              if (fiche.actif)
                BoutonCarre(
                  picto: Picto.trash,
                  taille: 72,
                  error: true,
                  onTap: () => _retirer(ref),
                  annonce: 'Retirer ce fournisseur',
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// La fiche de creation et de modification.
///
/// Le formulaire ne demande que ce qu'un producteur a vraiment : son nom, son
/// numero, son village, ce qu'il produit et comment il le compte. Pas de
/// quantite, pas de jour de marche : le comptoir negocie le volume a chaque
/// passage, et une fiche qui vieillit mal vaut moins qu'une fiche courte.
class FicheFournisseurScreen extends ConsumerStatefulWidget {
  const FicheFournisseurScreen({this.fiche, super.key});

  final Fournisseur? fiche;

  @override
  ConsumerState<FicheFournisseurScreen> createState() => _FicheFournisseurScreenState();
}

class _FicheFournisseurScreenState extends ConsumerState<FicheFournisseurScreen> {
  final TextEditingController _nom = TextEditingController();
  final TextEditingController _village = TextEditingController();
  final TextEditingController _productionLibre = TextEditingController();

  String _telephone = '';
  Categorie? _categorie;
  Unite _unite = Unite.kg;
  Uint8List? _photoOctets;
  String? _photoChemin;
  bool _occupee = false;
  String? _erreur;

  bool get _edition => widget.fiche != null;

  @override
  void initState() {
    super.initState();
    final existante = widget.fiche;
    if (existante != null) {
      _nom.text = existante.nom;
      _village.text = existante.village;
      _productionLibre.text = existante.productionLibre;
      _telephone = existante.telephone.replaceAll('+237', '');
      _categorie = existante.productionCategorie;
      _unite = existante.unite;
      _photoChemin = existante.photo;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      TtsService.instance.dire(_edition ? 'Modifier la fiche' : 'Nouveau fournisseur');
    });
  }

  @override
  void dispose() {
    _nom.dispose();
    _village.dispose();
    _productionLibre.dispose();
    super.dispose();
  }

  Future<void> _prendrePhoto() async {
    try {
      final prise = await ImagePicker().pickImage(
        source: ImageSource.camera,
        maxWidth: 720,
        imageQuality: 70,
      );
      if (prise == null) return;
      final octets = await File(prise.path).readAsBytes();
      if (!mounted) return;
      setState(() {
        _photoOctets = octets;
        _photoChemin = prise.path;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _erreur = 'La caméra ne répond pas');
    }
  }

  Future<void> _enregistrer() async {
    final depot = ref.read(depotFournisseursProvider);
    final nom = _nom.text.trim();
    final village = _village.text.trim();
    final categorie = _categorie;

    if (nom.isEmpty ||
        village.isEmpty ||
        categorie == null ||
        normaliserTelephone(_telephone) == null) {
      setState(() => _erreur = 'Nom, village, numéro et production sont nécessaires');
      await TtsService.instance.dire('Nom, village, numéro et production sont nécessaires');
      return;
    }

    setState(() {
      _occupee = true;
      _erreur = null;
    });

    try {
      final existante = widget.fiche;
      final enregistre = existante == null
          ? await depot.creer(
              nom: nom,
              telephone: _telephone,
              village: village,
              productionCategorie: categorie,
              productionLibre: _productionLibre.text,
              unite: _unite,
              photoOctets: _photoOctets,
            )
          : await depot.modifier(
              existante.copieAvec(
                nom: nom,
                telephone: normaliserTelephone(_telephone)!,
                village: village,
                productionCategorie: categorie,
                productionLibre: _productionLibre.text.trim(),
                unite: _unite,
              ),
              photoOctets: _photoOctets,
            );

      if (enregistre == null) {
        setState(() => _erreur = 'Le serveur a refusé la fiche');
        return;
      }

      ref.invalidate(fournisseursProvider);

      if (!mounted) return;
      await TtsService.instance.dire('${enregistre.nom} enregistré');
      if (!mounted) return;
      Navigator.of(context).pop();
    } finally {
      if (mounted) setState(() => _occupee = false);
    }
  }

  Future<void> _acheter() async {
    final fiche = widget.fiche;
    if (fiche == null || !fiche.actif) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => ProposerRecolteScreen(pour: fiche),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: MboaColors.background,
      appBar: AppBar(
        title: Text(_edition ? 'Modifier' : 'Nouveau fournisseur'),
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
                  Center(
                    child: PhotoRonde(
                      chemin: _photoChemin ?? '',
                      cote: 150,
                      quandAbsente: Picto.person,
                      couleurLiseret: _photoOctets == null ? MboaColors.trait : MboaColors.primary,
                    ),
                  ),
                  const SizedBox(height: 14),
                  GrosBouton(
                    titre: 'Photo du fournisseur',
                    picto: Picto.camera,
                    secondaire: true,
                    minHeight: 88,
                    onTap: _prendrePhoto,
                  ),
                  const SizedBox(height: 20),
                  const _Champ('Son nom', Picto.person),
                  CarteBio(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    child: TextField(
                      controller: _nom,
                      style: MboaTypo.titre(),
                      textCapitalization: TextCapitalization.words,
                      decoration: const InputDecoration(
                        border: InputBorder.none,
                        hintText: 'Exemple : Papa Jean',
                        hintStyle: TextStyle(color: MboaColors.textDoux, fontSize: 20),
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),
                  const _Champ('Son numéro', Picto.phone),
                  const SizedBox(height: 8),
                  CarteBio(
                    child: Text(
                      '+237 ${_telephone.isEmpty ? '…' : _telephone}',
                      style: MboaTypo.chiffreGeant(
                        couleur: _telephone.isEmpty ? MboaColors.textDoux : MboaColors.primary,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                  const SizedBox(height: 10),
                  PaveNumerique(
                    onTouche: (c) {
                      if (_telephone.length < 9) setState(() => _telephone += c);
                    },
                    effacer: _telephone.isEmpty
                        ? null
                        : () => setState(
                              () => _telephone = _telephone.substring(0, _telephone.length - 1),
                            ),
                  ),
                  const SizedBox(height: 18),
                  const _Champ('Son village', Picto.map),
                  CarteBio(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    child: TextField(
                      controller: _village,
                      style: MboaTypo.corps(),
                      textCapitalization: TextCapitalization.words,
                      decoration: const InputDecoration(
                        border: InputBorder.none,
                        hintText: 'Exemple : Mbouda',
                        hintStyle: TextStyle(color: MboaColors.textDoux, fontSize: 20),
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),
                  const _Champ('Sa production', Picto.leaf),
                  const SizedBox(height: 8),
                  GridView.count(
                    crossAxisCount: 2,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    mainAxisSpacing: 10,
                    crossAxisSpacing: 10,
                    childAspectRatio: 2.7,
                    children: [
                      for (final cat in Categorie.values)
                        _TuileProduction(
                          categorie: cat,
                          choisi: _categorie == cat,
                          onTap: () {
                            setState(() => _categorie = cat);
                            TtsService.instance.dire(cat.libelleVoice);
                          },
                        ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  CarteBio(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    child: TextField(
                      controller: _productionLibre,
                      style: MboaTypo.corps(),
                      textCapitalization: TextCapitalization.sentences,
                      decoration: const InputDecoration(
                        border: InputBorder.none,
                        hintText: 'Le mot du marché, exemple : igname de Mbouda',
                        hintStyle: TextStyle(color: MboaColors.textDoux, fontSize: 18),
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),
                  const _Champ('Sa mesure habituelle', Picto.liste),
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
                  if (_edition && widget.fiche!.actif) ...[
                    const SizedBox(height: 22),
                    GrosBouton(
                      titre: 'Acheter sa récolte',
                      picto: Picto.handGive,
                      sousTitre: 'Le comptoir saisit l’achat pour lui',
                      secondaire: true,
                      minHeight: 96,
                      onTap: _acheter,
                    ),
                  ],
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
                    titre: _edition ? 'Enregistrer' : 'Ajouter ce fournisseur',
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
}

class _Champ extends StatelessWidget {
  const _Champ(this.texte, this.picto);

  final String texte;
  final Picto picto;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        PictoIcon(picto, size: 28),
        const SizedBox(width: 10),
        Text(texte, style: MboaTypo.titre()),
      ],
    );
  }
}

class _TuileProduction extends StatelessWidget {
  const _TuileProduction({
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
