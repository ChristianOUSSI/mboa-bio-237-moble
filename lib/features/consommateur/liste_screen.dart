import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/data/mboa_reseau.dart';
import '../../core/data/models/commande.dart';
import '../../core/data/models/langue.dart';
import '../../core/data/models/produit.dart';
import '../../core/data/models/unite.dart';
import '../../core/design_system/boutons.dart';
import '../../core/design_system/carte.dart';
import '../../core/design_system/picto.dart';
import '../../core/design_system/photo.dart';
import '../../core/design_system/tactile.dart';
import '../../core/etat/providers.dart';
import '../../core/theme/mboa_colors.dart';
import '../../core/theme/mboa_typography.dart';
import '../../core/utils/format_monnaie.dart';
import '../../core/voice/stt_service.dart';
import '../../core/voice/tts_service.dart';
import '../auth/pave_numerique.dart';
import 'commander_screen.dart';
import 'gabarit_liste.dart';

/// Ma liste de marche.
///
/// Le papier, pas le panier. Une mama prepare sa liste quand elle veut, le
/// matin au reveil ou la veille au soir, et elle n'a rien a acheter dans
/// l'immmediate. Ce qu'elle veut, c'est l'avoir en image dans sa poche :
/// pour la montrer, pour l'envoyer a sa fille, pour la dicter au telephone
/// avec son code.
///
/// Deux gestes seulement en bas de l'ecran : l'envoyer, ou la commander.
/// Tout le reste est de la preparation.
class ListeScreen extends ConsumerStatefulWidget {
  const ListeScreen({super.key});

  static const String nom = '/liste';

  @override
  ConsumerState<ListeScreen> createState() => _ListeScreenState();
}

class _ListeScreenState extends ConsumerState<ListeScreen> {
  bool _occupee = false;
  String? _message;
  bool _erreur = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _charger());
  }

  Future<void> _charger() async {
    final session = ref.read(sessionProvider);
    if (session == null) return;
    await ref.read(listeProvider.notifier).charger(session.identifiant);
  }

  Future<void> _ajouterProduit() async {
    final choisis = await showModalBottomSheet<Produit>(
      context: context,
      isScrollControlled: true,
      backgroundColor: MboaColors.background,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (context) => const _FeuilleProduits(),
    );
    if (choisis == null) return;

    final kg = choisis.estPack ? 1.0 : 1.0;
    ref.read(listeProvider.notifier).poser(choisis, kg);

    await TtsService.instance.dire(
      '${choisis.nom} ajouté. ${choisis.uniteReelle.avec(kg)}.',
    );
  }

  /// La ligne que le catalogue ne connait pas.
  ///
  /// Sur un vrai devis de marche, vingt articles sur vingt-cinq ne sont pas
  /// des produits du logo : riz, poulet, miondo, huile rouge, sel germé. Sans
  /// cette entree, le papier s'arrete a neuf lignes et la mama reprend un
  /// carnet pour le reste, ce qui supprime la seule raison d'etre du devis.
  Future<void> _ajouterLibre() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: MboaColors.background,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (context) => const _FeuilleLibre(),
    );
  }

  Future<void> _sauvegarder() async {
    final session = ref.read(sessionProvider);
    if (session == null) return;

    setState(() {
      _occupee = true;
      _message = null;
      _erreur = false;
    });

    try {
      final liste = await ref.read(listeProvider.notifier).sauvegarder(
            consommateurId: session.identifiant,
            consommateurNom: session.profil.nom,
            consommateurTelephone: session.profil.telephone,
            titre: 'Ma liste',
          );

      if (liste == null) {
        setState(() => _message = 'Ajoutez d’abord un produit');
        return;
      }

      await TtsService.instance.dire('Liste enregistrée. Votre code est ${liste.code.split('').join(', ')}');
      setState(() => _message = 'Liste enregistrée');
    } catch (e) {
      setState(() {
        _erreur = true;
        _message = 'Enregistrement impossible sur ce téléphone';
      });
    } finally {
      if (mounted) setState(() => _occupee = false);
    }
  }

  /// Genere l'image, l'attache a la liste, puis ouvre le partage.
  ///
  /// L'ordre compte : on n'envoie que ce qui est enregistre, sinon la mama
  /// partage une image que l'agent ne retrouvera pas au code qu'elle dictera.
  Future<void> _envoyer() async {
    final session = ref.read(sessionProvider);
    final etat = ref.read(listeProvider);
    if (session == null || etat.vide) return;

    setState(() {
      _occupee = true;
      _message = null;
      _erreur = false;
    });

    try {
      var liste = etat.sauvee;
      if (liste == null || etat.modifiee) {
        liste = await ref.read(listeProvider.notifier).sauvegarder(
              consommateurId: session.identifiant,
              consommateurNom: session.profil.nom,
              consommateurTelephone: session.profil.telephone,
              titre: 'Ma liste',
            );
      }
      if (liste == null) return;

      // Le moto qui a porte la commande, quand il y en a une : le papier
      // partage doit dire qui vient, sinon il ne rassure personne.
      liste = await ref.read(depotListesProvider).avecLivreur(liste);

      final png = await GabaritListe.dessiner(liste);
      if (png == null) {
        setState(() {
          _erreur = true;
          _message = 'Le dessin de la liste a échoué';
        });
        return;
      }

      final chemin = await MboaReseau.televerser(
        bucket: 'listes',
        dossier: session.identifiant,
        nom: liste.code + '.png',
        octets: png,
        mime: 'image/png',
      );
      if (chemin != null) {
        await ref.read(listeProvider.notifier).attacherImage(chemin);
      }
      await ref.read(listeProvider.notifier).marquerEnvoyee();

      final fichier = File(await _ecrireFichier(png));
      await TtsService.instance.dire('Votre liste est prête. Choisissez à qui l’envoyer.');
      await Share.shareXFiles(
        [XFile(fichier.path)],
        text: 'Ma liste Mboa Bio 237, code ${liste.code}. '
            '${formaterFcfa(liste.montantEstime)} à payer à la livraison.',
        subject: 'Liste Mboa Bio 237',
      );
    } catch (e) {
      setState(() {
        _erreur = true;
        _message = 'Envoi impossible';
      });
    } finally {
      if (mounted) setState(() => _occupee = false);
    }
  }

  static Future<String> _ecrireFichier(Uint8List png) async {
    final repertoire = await getTemporaryDirectory();
    final fichier = File('${repertoire.path}/liste_mboa.png');
    await fichier.writeAsBytes(png, flush: true);
    return fichier.path;
  }

  Future<void> _commander() async {
    final etat = ref.read(listeProvider);
    if (etat.vide) {
      await TtsService.instance.dire('Votre liste est vide');
      return;
    }

    final panier = ref.read(panierProvider.notifier);
    panier.vider();
    for (final ligne in etat.articles) {
      panier.poserLigne(ligne);
    }

    if (!mounted) return;
    Navigator.of(context).push(
      MaterialPageRoute(builder: (context) => const CommanderScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final etat = ref.watch(listeProvider);

    return Scaffold(
      backgroundColor: MboaColors.background,
      appBar: AppBar(
        title: const Text('Ma liste'),
        leading: IconButton(
          onPressed: () => Navigator.of(context).pop(),
          tooltip: 'Retour',
          iconSize: 36,
          icon: const PictoIcon(Picto.back, size: 36, couleur: MboaColors.surface),
        ),
        actions: [
          if (!etat.vide)
            IconButton(
              onPressed: () {
                ref.read(listeProvider.notifier).vider();
                TtsService.instance.dire('Liste vidée');
              },
              tooltip: 'Vider la liste',
              iconSize: 34,
              icon: const PictoIcon(Picto.trash, size: 34, couleur: MboaColors.surface),
            ),
        ],
      ),
      body: SafeArea(
        child: _occupee
            ? const Center(child: CircularProgressIndicator(color: MboaColors.primary))
            : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    child: etat.vide
                        ? _vide()
                        : ListView(
                            padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
                            children: [
                              _EnteteListe(etat: etat),
                              const SizedBox(height: 12),
                              for (final ligne in etat.articles)
                                Padding(
                                  padding: const EdgeInsets.only(bottom: 12),
                                  child: _LigneListe(ligne: ligne),
                                ),
                            ],
                          ),
                  ),
                  if (_message != null)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                      child: BandeauEtat(
                        texte: _message!,
                        couleur: _erreur ? MboaColors.error : MboaColors.primary,
                        icone: PictoIcon(
                          _erreur ? Picto.alert : Picto.check,
                          size: 30,
                          couleur: _erreur ? MboaColors.error : MboaColors.primary,
                        ),
                      ),
                    ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 18),
                    child: Column(
                      children: [
                        GrosBouton(
                          titre: etat.vide ? 'Ajouter un produit' : 'Encore un produit',
                          picto: Picto.plus,
                          sombre: true,
                          minHeight: 96,
                          onTap: _ajouterProduit,
                        ),
                        const SizedBox(height: 10),
                        GrosBouton(
                          titre: 'Autre article du marché',
                          picto: Picto.mic,
                          sousTitre: 'Riz, poulet, miondo… ce que la voix nomme',
                          secondaire: true,
                          minHeight: 96,
                          onTap: _ajouterLibre,
                        ),
                        const SizedBox(height: 10),
                        GrosBouton(
                          titre: 'Envoyer ma liste',
                          picto: Picto.partage,
                          sousTitre: 'Une image avec le logo Mboa, pour WhatsApp',
                          secondaire: true,
                          minHeight: 96,
                          onTap: etat.vide ? null : _envoyer,
                        ),
                        const SizedBox(height: 10),
                        GrosBouton(
                          titre: 'Commander cette liste',
                          picto: Picto.basket,
                          sousTitre: 'Je paie à la livraison',
                          secondaire: true,
                          minHeight: 96,
                          onTap: etat.vide ? null : _commander,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  Widget _vide() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const PictoIcon(Picto.liste, size: 120),
            const SizedBox(height: 22),
            Text('Ma liste est vide', style: MboaTypo.titre()),
            const SizedBox(height: 12),
            Text(
              'Ajoutez ce que vous voulez, même la veille. '
              'Rien n’est commandé tant que vous n’appuyez pas.',
              style: MboaTypo.aide(couleur: MboaColors.text),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

/// Le bandeau du haut : total, code, poids.
///
/// Le code n'apparait qu'une fois la liste enregistree. Afficher un code qui
/// n'existe pas encore dans la base serait promettre a la mama quelque chose
/// que l'agent ne retrouvera pas au telephone.
class _EnteteListe extends StatelessWidget {
  const _EnteteListe({required this.etat});

  final ListeState etat;

  @override
  Widget build(BuildContext context) {
    final code = etat.code;

    return CarteBio(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const PictoIcon(Picto.especes, size: 38),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Environ', style: MboaTypo.aide()),
                    Text(
                      formaterFcfa(etat.montantEstime),
                      style: MboaTypo.chiffre(),
                    ),
                  ],
                ),
              ),
              BoutonVoix(texte: etat.resumePourVoix),
            ],
          ),
          const Divider(height: 22),
          Row(
            children: [
              const PictoIcon(Picto.liste, size: 34),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  '${etat.count} produits · ${etat.resumeQuantites}',
                  style: MboaTypo.corps(),
                ),
              ),
              if (code.isNotEmpty)
                Text(
                  code.toUpperCase().split('').join(' '),
                  style: MboaTypo.chiffre(couleur: MboaColors.primary).copyWith(
                    fontSize: 26,
                    letterSpacing: 2,
                  ),
                )
              else
                Text('pas encore enregistrée', style: MboaTypo.aide()),
            ],
          ),
        ],
      ),
    );
  }
}

class _LigneListe extends ConsumerWidget {
  const _LigneListe({required this.ligne});

  final LigneCommande ligne;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pas = ligne.pas;

    return CarteBio(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      child: Row(
        children: [
          PhotoProduit(
            chemin: ligne.photo,
            categorie: ligne.categorie,
            slug: ligne.slug,
            libelle: ligne.nom,
            cote: 80,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(ligne.nom, style: MboaTypo.titre()),
                ChiffreUnite(valeur: ligne.quantiteAffichee),
              ],
            ),
          ),
          BoutonCarre(
            picto: Picto.minus,
            taille: 72,
            onTap: () {
              ref.read(listeProvider.notifier).retirer(ligne.produitId);
              TtsService.instance.dire(ligne.uniteReelle.avec(ligne.quantite - pas));
            },
            annonce: 'Retirer',
          ),
          const SizedBox(width: 8),
          BoutonCarre(
            picto: Picto.plus,
            taille: 72,
            couleurFond: MboaColors.primary,
            couleurTrait: MboaColors.primary,
            onTap: () {
              ref.read(listeProvider.notifier).ajusterQuantite(ligne, ligne.quantite + pas);
              TtsService.instance.dire(ligne.uniteReelle.avec(ligne.quantite + pas));
            },
            annonce: 'Ajouter',
          ),
        ],
      ),
    );
  }
}

/// La feuille de selection : la meme vitrine que l'ecran d'achat, sans le
/// filtre. Une liste se remplit a la main, produit par produit.
class _FeuilleProduits extends ConsumerWidget {
  const _FeuilleProduits();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final vitrine = ref.watch(vitrineProvider(null));

    return SafeArea(
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.72,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 10),
              child: Row(
                children: [
                  const PictoIcon(Picto.liste, size: 34),
                  const SizedBox(width: 12),
                  Expanded(child: Text('Choisir un produit', style: MboaTypo.titre())),
                ],
              ),
            ),
            Expanded(
              child: vitrine.maybeWhen(
                data: (liste) => GridView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    mainAxisSpacing: 12,
                    crossAxisSpacing: 12,
                    childAspectRatio: 0.78,
                  ),
                  itemCount: liste.length,
                  itemBuilder: (context, index) => CarteBio(
                    onTap: () => Navigator.of(context).pop(liste[index]),
                    padding: const EdgeInsets.fromLTRB(10, 10, 10, 8),
                    child: Column(
                      children: [
                        Expanded(
                          child: PhotoProduit(
                            chemin: liste[index].photo,
                            categorie: liste[index].categorie,
                            slug: liste[index].slug,
                            libelle: liste[index].nom,
                            cote: 110,
                            cadre: false,
                          ),
                        ),
                        Text(
                          liste[index].nom,
                          style: MboaTypo.aide(couleur: MboaColors.text),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          formaterFcfaCourt(liste[index].prix),
                          style: MboaTypo.chiffre(),
                        ),
                      ],
                    ),
                  ),
                ),
                orElse: () => const Center(
                  child: CircularProgressIndicator(color: MboaColors.primary),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// La ligne que le catalogue ne connait pas : « miondo, 5 paquets, 700 F ».
///
/// Trois gestes, aucun clavier. La voix nomme l'article, le pouce compte la
/// quantite et choisit l'unite, le pavé chiffre le prix. Le nom est gelé tel
/// qu'il a été compris : dans six mois la ligne dira encore « Miondo », et
/// non la valeur de repli du catalogue.
class _FeuilleLibre extends ConsumerStatefulWidget {
  const _FeuilleLibre();

  @override
  ConsumerState<_FeuilleLibre> createState() => _FeuilleLibreState();
}

class _FeuilleLibreState extends ConsumerState<_FeuilleLibre> {
  String _nom = '';
  double _quantite = 1;
  Unite _unite = Unite.litre;
  String _chiffres = '';
  bool _ecoute = false;

  int get _prix => int.tryParse(_chiffres) ?? 0;

  bool get _prete => _nom.trim().isNotEmpty && _quantite > 0 && _prix > 0;

  /// Le mot dicte, remis en capitale. La voix rend un minuscule, et un
  /// « miondo » tout petit au milieu d'un tableau de devis fait une ligne
  /// moins lisible que les voisines.
  static String _tituler(String dictee) {
    final propre = dictee.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (propre.isEmpty) return propre;
    return propre[0].toUpperCase() + propre.substring(1);
  }

  Future<void> _direLeNom() async {
    final langue = ref.read(sessionProvider)?.profil.langue ?? Langue.fr;
    setState(() => _ecoute = true);
    await mboaTactile(annonce: 'Dites le nom de l’article');

    String dictee;
    try {
      dictee = await SttService.instance.ecouter(langue: langue, maximumSecondes: 6);
    } catch (_) {
      dictee = '';
    }

    if (!mounted) return;
    setState(() {
      _ecoute = false;
      if (dictee.trim().isNotEmpty) _nom = _tituler(dictee);
    });

    if (dictee.trim().isEmpty) {
      await TtsService.instance.dire('Je n’ai rien entendu. Reprenez et parlez fort.');
    } else {
      await TtsService.instance.dire('C’est $_nom ?');
    }
  }

  void _compter(double delta) {
    final nouveau = (_quantite + delta).clamp(0, 999).toDouble();
    setState(() => _quantite = nouveau);
    TtsService.instance.dire(_unite.avec(nouveau));
  }

  void _ajouter() {
    if (!_prete) return;

    ref.read(listeProvider.notifier).poserLibre(
          nom: _nom,
          quantite: _quantite,
          unite: _unite,
          prix: _prix,
        );

    TtsService.instance
        .dire('$_nom ajouté. ${_unite.avec(_quantite)}, ${formaterFcfa(_prix)}.');
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const PictoIcon(Picto.mic, size: 40),
                const SizedBox(width: 14),
                Expanded(
                  child: Text('Autre article du marché', style: MboaTypo.titre()),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // 1. Le nom, dicte a la voix.
            CarteBio(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  GrosBouton(
                    titre: _nom.isEmpty ? 'Dire le nom' : 'Redire le nom',
                    picto: Picto.mic,
                    sombre: _nom.isEmpty,
                    minHeight: 92,
                    onTap: _ecoute ? null : _direLeNom,
                  ),
                  if (_nom.isNotEmpty) ...[
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            _nom,
                            style: MboaTypo.titre(couleur: MboaColors.primary)
                                .copyWith(fontSize: 46),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        BoutonVoix(texte: _nom),
                      ],
                    ),
                  ],
                  if (_ecoute)
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Text('J’écoute…', style: MboaTypo.aide()),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 14),

            // 2. La quantite, et l'unite avec laquelle elle se compte.
            CarteBio(
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      BoutonCarre(
                        picto: Picto.minus,
                        onTap: _quantite <= 0 ? null : () => _compter(-1),
                        annonce: 'Retirer ${_unite.avec(1)}',
                      ),
                      ChiffreUnite(
                        valeur: formaterKg(_quantite),
                        unite: _unite.pour(_quantite),
                        geant: true,
                      ),
                      BoutonCarre(
                        picto: Picto.plus,
                        onTap: () => _compter(1),
                        annonce: 'Ajouter ${_unite.avec(1)}',
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      for (final unite in Unite.values)
                        _PuceUnite(
                          unite: unite,
                          quantite: _quantite,
                          selectionne: unite == _unite,
                          onTap: () => setState(() => _unite = unite),
                        ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),

            // 3. Le prix, chiffre au pouce.
            CarteBio(
              child: Column(
                children: [
                  Text('Prix pour ${_unite.avecArticle}', style: MboaTypo.corps()),
                  const SizedBox(height: 6),
                  Text(
                    formaterFcfa(_prix),
                    style: MboaTypo.chiffreGeant(couleur: MboaColors.primary),
                  ),
                  const SizedBox(height: 10),
                  PaveNumerique(
                    onTouche: (touche) {
                      if (_chiffres.length >= 7) return;
                      setState(() => _chiffres += touche);
                      TtsService.instance.dire(formaterFcfa(_prix));
                    },
                    effacer: () {
                      if (_chiffres.isEmpty) return;
                      setState(() => _chiffres = _chiffres.substring(0, _chiffres.length - 1));
                    },
                    valider: _ajouter,
                    titre: 'Le prix',
                    annonce: _nom.isEmpty ? 'Le prix' : 'Le prix du $_nom',
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            GrosBouton(
              titre: 'Ajouter à ma liste',
              picto: Picto.check,
              sombre: _prete,
              minHeight: 100,
              onTap: _prete ? _ajouter : null,
            ),
            const SizedBox(height: 8),
            Text(
              _prete
                  ? '${_unite.avec(_quantite)} de $_nom · ${formaterFcfa(_prix * _quantite)} au total'
                  : 'Dites le nom, comptez la quantité, chiffrez le prix.',
              style: MboaTypo.aide(couleur: MboaColors.text),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

/// Une puce d'unite. Douze mots courts, aucun besoin d'icone : ce que la mama
/// doit reconnaitre ici est le mot qu'elle emploie elle-meme, et la puce le
/// redit a voix haute des qu'on la touche.
class _PuceUnite extends StatelessWidget {
  const _PuceUnite({
    required this.unite,
    required this.quantite,
    required this.selectionne,
    required this.onTap,
  });

  final Unite unite;
  final double quantite;
  final bool selectionne;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        mboaTactile(annonce: unite.avec(quantite), fort: false);
        onTap();
      },
      child: Container(
        height: 72,
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        decoration: BoxDecoration(
          color: selectionne ? MboaColors.primary : MboaColors.surface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: MboaColors.primary, width: 3),
        ),
        child: Text(
          unite.pluriel,
          style: MboaTypo.corps(
            couleur: selectionne ? MboaColors.surface : MboaColors.text,
          ).copyWith(fontSize: 26, fontWeight: FontWeight.w800),
        ),
      ),
    );
  }
}
