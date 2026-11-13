import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/data/depot_auth.dart' show normaliserTelephone;
import '../../core/data/models/livreur.dart';
import '../../core/design_system/boutons.dart';
import '../../core/design_system/carte.dart';
import '../../core/design_system/picto.dart';
import '../../core/design_system/photo.dart';
import '../../core/etat/providers.dart';
import '../../core/theme/mboa_colors.dart';
import '../../core/theme/mboa_typography.dart';
import '../../core/utils/format_monnaie.dart';
import '../../core/voice/tts_service.dart';
import '../auth/pave_numerique.dart';

/// L'annuaire des livreurs.
///
/// Un livreur n'est pas un compte : il n'a pas d'application, pas de mot de
/// passe. C'est une fiche que l'admin remplit une fois, et qui ressort a
/// l'ecran de la cliente au moment ou la moto part.
///
/// La plaque est le champ le plus important de la fiche, et le seul que la
/// mama regardera vraiment avant d'ouvrir sa porte. Il est donc affiche en
/// caracteres plus gros que le nom.
class LivreursScreen extends ConsumerWidget {
  const LivreursScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final livreurs = ref.watch(livreursCompletsProvider);

    return Scaffold(
      backgroundColor: MboaColors.background,
      appBar: AppBar(
        title: const Text('Livreurs'),
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
              child: livreurs.maybeWhen(
                data: (liste) => liste.isEmpty
                    ? const _Personne()
                    : ListView.separated(
                        padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
                        itemCount: liste.length,
                        separatorBuilder: (context, index) => const SizedBox(height: 12),
                        itemBuilder: (context, index) => _CarteLivreur(livreur: liste[index]),
                      ),
                orElse: () => const Center(
                  child: CircularProgressIndicator(color: MboaColors.primary),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 18),
              child: GrosBouton(
                titre: 'Ajouter un livreur',
                picto: Picto.plus,
                sombre: true,
                minHeight: 104,
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (context) => const FicheLivreurScreen()),
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
          const PictoIcon(Picto.moto, size: 110),
          const SizedBox(height: 20),
          Text('Aucun livreur', style: MboaTypo.titre()),
          const SizedBox(height: 10),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 44),
            child: Text(
              'Ajoute le moto du village : la cliente verra sa plaque avant d’ouvrir sa porte',
              style: MboaTypo.aide(couleur: MboaColors.text),
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    );
  }
}

class _CarteLivreur extends ConsumerWidget {
  const _CarteLivreur({required this.livreur});

  final Livreur livreur;

  Future<void> _appeler(BuildContext context, WidgetRef ref) async {
    // Le numero ne sort plus par un select depuis la 0012 : il vient d'une
    // porte nommee, pour le comptoir seulement.
    var numero = livreur.telephone;
    if (numero.isEmpty) {
      numero = await ref.read(depotLivreursProvider).telephone(livreur.id) ?? '';
    }
    if (numero.isEmpty) {
      await TtsService.instance.dire('Pas de numéro pour ce livreur');
      return;
    }
    await TtsService.instance.dire('J’appelle ${livreur.nom}');
    if (!context.mounted) return;
    if (!await launchUrl(Uri.parse('tel:$numero'))) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Appel impossible : $numero')),
      );
    }
  }

  Future<void> _desactiver(WidgetRef ref) async {
    final sur = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Retirer ce livreur ?'),
        content: Text('${livreur.nom} cessera d’être proposé. Ses courses passées restent.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Non')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Retirer')),
        ],
      ),
    );
    if (sur != true) return;

    await ref.read(depotLivreursProvider).desactiver(livreur.id);
    ref.invalidate(livreursProvider);
    ref.invalidate(livreursCompletsProvider);
    await TtsService.instance.dire('${livreur.nom} retiré de la liste');
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return CarteBio(
      couleurTrait: livreur.actif ? MboaColors.trait : MboaColors.error,
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(builder: (context) => FicheLivreurScreen(livreur: livreur)),
      ),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              PhotoRonde(chemin: livreur.photo ?? '', cote: 72, quandAbsente: Picto.moto),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(livreur.nom, style: MboaTypo.titre()),
                    Text(
                      '${livreur.zone}'
                      '${livreur.moto != null && livreur.moto!.isNotEmpty ? ' · ${livreur.moto}' : ''}',
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
                  // La plaque avant le tarif : c'est elle que la cliente
                  // verifie, le tarif c'est ce qu'elle doit preparer.
                  if (livreur.plaque != null && livreur.plaque!.isNotEmpty)
                    Text(livreur.plaque!, style: MboaTypo.chiffre(couleur: MboaColors.primary)),
                  if (livreur.tarifCourse > 0)
                    Text(formaterFcfaCourt(livreur.tarifCourse), style: MboaTypo.corps()),
                  if (!livreur.actif)
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
                onTap: () => _appeler(context, ref),
                annonce: 'Appeler ${livreur.nom}',
              ),
              const SizedBox(width: 10),
              BoutonCarre(
                picto: Picto.speaker,
                taille: 72,
                couleurFond: MboaColors.background,
                onTap: () => TtsService.instance.dire(livreur.annonce),
                annonce: 'Écouter la fiche',
              ),
              const Spacer(),
              if (livreur.actif)
                BoutonCarre(
                  picto: Picto.trash,
                  taille: 72,
                  error: true,
                  onTap: () => _desactiver(context, ref),
                  annonce: 'Retirer ce livreur',
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
/// Le telephone se saisit sur le pave numerique geant, jamais au clavier :
/// un numero mal tape est une course qui n'arrive pas. Le nom et la plaque
/// restent au clavier, ce sont les deux seules choses que l'admin sait ecrire.
class FicheLivreurScreen extends ConsumerStatefulWidget {
  const FicheLivreurScreen({this.livreur, super.key});

  final Livreur? livreur;

  @override
  ConsumerState<FicheLivreurScreen> createState() => _FicheLivreurScreenState();
}

class _FicheLivreurScreenState extends ConsumerState<FicheLivreurScreen> {
  static const List<String> _zones = [
    'Mbouda', 'Bafoussam', 'Dschang', 'Bamenda', 'Foumban',
    'Nkongsamba', 'Douala', 'Yaoundé', 'Bertoua', 'Garoua', 'Maroua',
  ];

  static const int _pasTarif = 100;

  final TextEditingController _nom = TextEditingController();
  final TextEditingController _plaque = TextEditingController();
  final TextEditingController _moto = TextEditingController();

  String _telephone = '';
  String? _zone;
  int _tarif = 0;
  Uint8List? _photoOctets;
  String? _photoChemin;
  bool _occupee = false;
  String? _erreur;

  bool get _edition => widget.livreur != null;

  @override
  void initState() {
    super.initState();
    final existant = widget.livreur;
    if (existant != null) {
      _nom.text = existant.nom;
      _plaque.text = existant.plaque ?? '';
      _moto.text = existant.moto ?? '';
      _telephone = existant.telephone.replaceAll('+237', '');
      _zone = existant.zone;
      _tarif = existant.tarifCourse;
      _photoChemin = existant.photo;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (existant != null && _telephone.isEmpty) {
        final numero = await ref.read(depotLivreursProvider).telephone(existant.id);
        if (numero != null && numero.isNotEmpty && mounted) {
          setState(() => _telephone = numero.replaceAll('+237', ''));
        }
      }
      await TtsService.instance.dire(_edition ? 'Modifier le livreur' : 'Nouveau livreur');
    });
  }

  @override
  void dispose() {
    _nom.dispose();
    _plaque.dispose();
    _moto.dispose();
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
    final depot = ref.read(depotLivreursProvider);
    final nom = _nom.text.trim();

    if (nom.isEmpty || _zone == null || normaliserTelephone(_telephone) == null) {
      setState(() => _erreur = 'Nom, zone et numéro sont nécessaires');
      await TtsService.instance.dire('Nom, zone et numéro sont nécessaires');
      return;
    }

    setState(() {
      _occupee = true;
      _erreur = null;
    });

    try {
      final existant = widget.livreur;
      final enregistre = existant == null
          ? await depot.creer(
              nom: nom,
              telephone: _telephone,
              zone: _zone!,
              moto: _moto.text.trim(),
              plaque: _plaque.text.trim(),
              tarifCourse: _tarif,
              photoOctets: _photoOctets,
            )
          : await depot.modifier(
              existant.copieAvec(
                nom: nom,
                telephone: normaliserTelephone(_telephone)!,
                zone: _zone!,
                moto: _moto.text.trim(),
                plaque: _plaque.text.trim(),
                tarifCourse: _tarif,
              ),
              photoOctets: _photoOctets,
            );

      if (enregistre == null) {
        setState(() => _erreur = 'Le serveur a refusé la fiche');
        return;
      }

      ref.invalidate(livreursProvider);
      ref.invalidate(livreursCompletsProvider);

      if (!mounted) return;
      await TtsService.instance.dire('${enregistre.nom} enregistré, plaque ${enregistre.plaque ?? 'non notée'}');
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
        title: Text(_edition ? 'Modifier' : 'Nouveau livreur'),
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
                      quandAbsente: Picto.moto,
                      couleurLiseret: _photoOctets == null ? MboaColors.trait : MboaColors.primary,
                    ),
                  ),
                  const SizedBox(height: 14),
                  GrosBouton(
                    titre: 'Photo du livreur',
                    picto: Picto.camera,
                    secondaire: true,
                    minHeight: 88,
                    onTap: _prendrePhoto,
                  ),
                  const SizedBox(height: 20),
                  const _Champ('Nom', Picto.person),
                  CarteBio(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    child: TextField(
                      controller: _nom,
                      style: MboaTypo.titre(),
                      textCapitalization: TextCapitalization.words,
                      decoration: const InputDecoration(
                        border: InputBorder.none,
                        hintText: 'Exemple : Ibrahim',
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
                  const _Champ('Sa zone', Picto.map),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final zone in _zones)
                        ChoiceChip(
                          label: Text(zone, style: MboaTypo.corps(couleur: MboaColors.text)),
                          selected: _zone == zone,
                          onSelected: (_) => setState(() => _zone = zone),
                          backgroundColor: MboaColors.surface,
                          selectedColor: MboaColors.secondaryDoux,
                          side: const BorderSide(color: MboaColors.trait, width: 2),
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                        ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  const _Champ('Immatriculation de la moto', Picto.moto),
                  CarteBio(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    child: TextField(
                      controller: _plaque,
                      style: MboaTypo.chiffre(),
                      textCapitalization: TextCapitalization.characters,
                      decoration: const InputDecoration(
                        border: InputBorder.none,
                        hintText: 'Exemple : AB 1234 CM',
                        hintStyle: TextStyle(color: MboaColors.textDoux, fontSize: 24),
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  const _Champ('La moto', Picto.moto),
                  CarteBio(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    child: TextField(
                      controller: _moto,
                      style: MboaTypo.corps(),
                      decoration: const InputDecoration(
                        border: InputBorder.none,
                        hintText: 'Marque et couleur, pour la reconnaître',
                        hintStyle: TextStyle(color: MboaColors.textDoux, fontSize: 20),
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),
                  const _Champ('Prix de la course', Picto.priceTag),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      BoutonCarre(
                        picto: Picto.minus,
                        taille: 88,
                        onTap: _tarif <= 0 ? null : () => setState(() => _tarif -= _pasTarif),
                        annonce: 'Moins cent francs',
                      ),
                      Expanded(
                        child: Center(
                          child: Text(formaterFcfa(_tarif), style: MboaTypo.chiffreGeant()),
                        ),
                      ),
                      BoutonCarre(
                        picto: Picto.plus,
                        taille: 88,
                        couleurFond: MboaColors.primary,
                        couleurTrait: MboaColors.primary,
                        onTap: () => setState(() => _tarif += _pasTarif),
                        annonce: 'Plus cent francs',
                      ),
                    ],
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
                    titre: _edition ? 'Enregistrer' : 'Ajouter ce livreur',
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
