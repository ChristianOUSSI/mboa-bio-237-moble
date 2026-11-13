import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/data/models/commande.dart';
import '../../core/data/models/livreur.dart';
import '../../core/design_system/boutons.dart';
import '../../core/design_system/carte.dart';
import '../../core/design_system/picto.dart';
import '../../core/design_system/photo.dart';
import '../../core/design_system/tactile.dart';
import '../../core/etat/providers.dart';
import '../../core/theme/mboa_colors.dart';
import '../../core/theme/mboa_typography.dart';
import '../../core/utils/format_monnaie.dart';
import '../../core/voice/tts_service.dart';
import '../commun/suivi_colis_screen.dart';
import 'livreurs_screen.dart';

/// Le pointage des livraisons.
///
/// C'est la tache quotidienne reelle de l'admin, et elle n'a rien a voir avec
/// le controle qualite : la marchandise est partie, il faut dire ce qui est
/// rentre. Trois choses sur chaque ligne, dans l'ordre :
///
///   * a qui on a porte, et ce qui etait demande ;
///   * ce qui a ete garde, ajuste par bonds de 50 francs ;
///   * un bouton, « Pointer livre ».
///
/// Le montant livre ne peut pas depasser le panier demande : la regle est
/// reprise ici en plus du serveur, parce que l'admin est le seul a pouvoir
/// la franchir et qu'un champ mal calibre suffit a creer un litige.
///
/// En dessous, les livrees sans reponse depuis 12 heures. Les clore n'est pas
/// une faveur : sans ca, l'argent du producteur reste suspendu au silence
/// d'une personne qui n'a peut-etre plus de credit telephone.
class LivraisonScreen extends ConsumerWidget {
  const LivraisonScreen({this.integree = false, super.key});

  /// Embarque dans le tableau de bord : pas de Scaffold, pas de fleche de
  /// retour. Une fleche qui ferait sortir de l'app depuis son propre poste de
  /// travail est un piege.
  final bool integree;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final aPointer = ref.watch(livraisonsAPointerProvider);
    final relances = ref.watch(relancesProvider);

    final contenu = SafeArea(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 26),
        children: [
          _TitreSection('À pointer', Picto.moto, aPointer.valueOrNull?.length ?? 0),
          const SizedBox(height: 12),
          ...aPointer.maybeWhen(
            data: (liste) => liste.isEmpty
                ? [const _Vide('Rien en route', Picto.check)]
                : [for (final c in liste) _CarteLivraison(commande: c)],
            orElse: () => [const _Chargement()],
          ),
          const SizedBox(height: 26),
          _TitreSection('Sans réponse', Picto.clock, relances.valueOrNull?.length ?? 0),
          const SizedBox(height: 6),
          Text(
            'Livrées depuis plus de 12 heures, la cliente n’a pas répondu.',
            style: MboaTypo.aide(),
          ),
          const SizedBox(height: 12),
          ...relances.maybeWhen(
            data: (liste) => liste.isEmpty
                ? [const _Vide('Tout le monde a répondu', Picto.pouceLeve)]
                : [for (final c in liste) _CarteRelance(commande: c)],
            orElse: () => [const SizedBox(height: 8)],
          ),
        ],
      ),
    );

    if (integree) return contenu;

    return Scaffold(
      backgroundColor: MboaColors.background,
      appBar: AppBar(
        title: const Text('Livraisons'),
        leading: IconButton(
          onPressed: () => Navigator.of(context).pop(),
          tooltip: 'Retour',
          iconSize: 36,
          icon: const PictoIcon(Picto.back, size: 36, couleur: MboaColors.surface),
        ),
      ),
      body: contenu,
    );
  }
}

class _TitreSection extends StatelessWidget {
  const _TitreSection(this.texte, this.picto, this.nombre);

  final String texte;
  final Picto picto;
  final int nombre;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        PictoIcon(picto, size: 32),
        const SizedBox(width: 12),
        Expanded(child: Text(texte, style: MboaTypo.titre())),
        Text('$nombre', style: MboaTypo.chiffre()),
      ],
    );
  }
}

class _Vide extends StatelessWidget {
  const _Vide(this.texte, this.picto);

  final String texte;
  final Picto picto;

  @override
  Widget build(BuildContext context) {
    return CarteBio(
      child: Row(
        children: [
          PictoIcon(picto, size: 40),
          const SizedBox(width: 14),
          Expanded(child: Text(texte, style: MboaTypo.corps())),
        ],
      ),
    );
  }
}

class _Chargement extends StatelessWidget {
  const _Chargement();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 28),
      child: Center(child: CircularProgressIndicator(color: MboaColors.primary)),
    );
  }
}

/// Une ligne de livraison en attente de pointage.
class _CarteLivraison extends ConsumerStatefulWidget {
  const _CarteLivraison({required this.commande});

  final Commande commande;

  @override
  ConsumerState<_CarteLivraison> createState() => _CarteLivraisonState();
}

class _CarteLivraisonState extends ConsumerState<_CarteLivraison> {
  /// Le pas de 50 francs : assez fin pour coller au marche, assez grossier
  /// pour qu'une reduction se fasse en trois appuis et pas en dix.
  static const int _pas = 50;

  int? _montant;
  bool _occupee = false;

  Commande get _commande => widget.commande;

  /// Le montant propose au premier affichage est le panier entier. Reduire
  /// est l'exception, et c'est elle qui doit couter un appui.
  int get _montantLivre => _montant ?? _commande.montantTotal;

  int get _ecart => _commande.montantTotal - _montantLivre;

  bool get _reduit => _ecart > 0;

  void _ajuster(int delta) {
    final nouveau = (_montantLivre + delta).clamp(0, _commande.montantTotal);
    setState(() => _montant = nouveau);
    TtsService.instance.dire(formaterFcfa(nouveau));
  }

  /// Affecter le moto avant qu'il parte.
  ///
  /// L'RPC serveur fait les trois choses d'un coup : la colonne, le passage
  /// en `en_livraison` si la commande etait seulement validee, et la
  /// notification. L'admin n'a qu'un choix a faire.
  Future<void> _choisirLivreur() async {
    final livreurs = ref.read(livreursProvider).valueOrNull ?? const [];
    if (livreurs.isEmpty) {
      await TtsService.instance.dire('Ajoute d’abord un livreur dans l’annuaire');
      if (!mounted) return;
      Navigator.of(context).push(
        MaterialPageRoute(builder: (context) => const LivreursScreen()),
      );
      return;
    }

    final choisi = await showModalBottomSheet<Livreur>(
      context: context,
      backgroundColor: MboaColors.background,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (context) => ListView(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 20),
        children: [
          Text('Qui part ?', style: MboaTypo.titre()),
          const SizedBox(height: 12),
          for (final l in livreurs)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: GrosBouton(
                titre: l.nom,
                sousTitre: l.repere,
                secondaire: true,
                minHeight: 88,
                chiffre: l.tarifCourse > 0 ? '${l.tarifCourse}' : null,
                onTap: () => Navigator.of(context).pop(l),
              ),
            ),
        ],
      ),
    );
    if (choisi == null) return;

    final ok = await ref.read(depotLivreursProvider).affecter(
          commandeId: _commande.id,
          livreurId: choisi.id,
        );

    ref.invalidate(livraisonsAPointerProvider);
    ref.invalidate(commandesAdminProvider);
    ref.invalidate(commandesClienteProvider);

    await TtsService.instance.dire(
      ok
          ? 'C’est ${choisi.nom} qui y va, plaque ${choisi.repere}'
          : 'Affectation enregistrée sur ce téléphone, elle partira au réseau',
    );
  }

  Future<void> _pointer() async {
    setState(() => _occupee = true);
    try {
      await ref.read(depotCommandesProvider).pointerLivraison(
            id: _commande.id,
            montantLivre: _montantLivre,
          );

      ref.invalidate(livraisonsAPointerProvider);
      ref.invalidate(relancesProvider);
      ref.invalidate(commandesAdminProvider);
      ref.invalidate(commandesClienteProvider);
      ref.invalidate(vitrineProvider(null));
      ref.invalidate(suiviColisProvider(_commande.id));

      await TtsService.instance.dire(
        _reduit
            ? 'Livraison pointée avec une réduction. La cliente va devoir confirmer.'
            : 'Livraison pointée. La cliente va devoir confirmer.',
      );
    } finally {
      if (mounted) setState(() => _occupee = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final commande = _commande;
    final cliente = ref.watch(profilParIdProvider(commande.consommateurId));

    return CarteBio(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              PhotoRonde(
                chemin: cliente.valueOrNull?.photoVisage ?? '',
                cote: 64,
                quandAbsente: Picto.person,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      cliente.valueOrNull?.prenom ?? 'La cliente',
                      style: MboaTypo.titre(),
                    ),
                    Text(
                      cliente.valueOrNull?.village ?? '',
                      style: MboaTypo.aide(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              BoutonCarre(
                picto: Picto.phone,
                taille: 64,
                onTap: () => _appeler(cliente.valueOrNull?.telephone),
                annonce: 'Appeler la cliente',
              ),
            ],
          ),
          const Divider(height: 22),
          Text(commande.resumeProduits, style: MboaTypo.corps()),
          Text(
            '${commande.resumeQuantites} · demandé ${formaterFcfa(commande.montantTotal)}',
            style: MboaTypo.aide(),
          ),
          const SizedBox(height: 16),
          Text('Encaissé à la porte', style: MboaTypo.titre()),
          const SizedBox(height: 8),
          Row(
            children: [
              BoutonCarre(
                picto: Picto.minus,
                taille: 88,
                onTap: _montantLivre <= 0 ? null : () => _ajuster(-_pas),
                annonce: 'Moins cinquante francs',
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Center(
                  child: Text(
                    formaterFcfa(_montantLivre),
                    style: MboaTypo.chiffreGeant(
                      couleur: _reduit ? MboaColors.error : MboaColors.primary,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              BoutonCarre(
                picto: Picto.plus,
                taille: 88,
                couleurFond: MboaColors.primary,
                couleurTrait: MboaColors.primary,
                onTap: _montantLivre >= commande.montantTotal ? null : () => _ajuster(_pas),
                annonce: 'Plus cinquante francs',
              ),
            ],
          ),
          if (_reduit) ...[
            const SizedBox(height: 10),
            BandeauEtat(
              texte: 'La cliente a gardé moins : ${formaterFcfa(_ecart)} en moins. '
                  'La marge se proroge sur ce montant, pas sur le panier.',
              couleur: MboaColors.error,
              icone: const PictoIcon(Picto.alert, size: 28, couleur: MboaColors.error),
            ),
          ],
          const SizedBox(height: 16),
          // Le moto affecte, affiche avant le bouton de pointage : pointer
          // une livraison sans savoir qui la porte, c'est signer en blanc.
          CarteBio(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
            onTap: _choisirLivreur,
            child: Row(
              children: [
                PhotoRonde(
                  chemin: _commande.livreurPhoto ?? '',
                  cote: 64,
                  quandAbsente: Picto.moto,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _commande.aUnLivreur ? _commande.livreurNom ?? 'Livreur' : 'Aucun livreur',
                        style: MboaTypo.titre(),
                      ),
                      Text(
                        _commande.aUnLivreur
                            ? _commande.livreurResume
                            : 'Touchez pour choisir la moto',
                        style: MboaTypo.aide(),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                const PictoIcon(Picto.plus, size: 34),
              ],
            ),
          ),
          const SizedBox(height: 16),
          TimelineColis(
            commandeId: commande.id,
            peutPointer: true,
            encadre: false,
          ),
          const SizedBox(height: 16),
          GrosBouton(
            titre: 'Pointer livré',
            picto: Picto.handGive,
            sousTitre: 'La cliente recevra le message de confirmation',
            sombre: true,
            minHeight: 104,
            onTap: _occupee ? null : _pointer,
          ),
        ],
      ),
    );
  }

  Future<void> _appeler(String? numero) async {
    if (numero == null || numero.isEmpty) {
      await TtsService.instance.dire('Le numéro de la cliente est indisponible');
      return;
    }
    await mboaTactile(annonce: 'J’appelle la cliente');
    if (!await launchUrl(Uri.parse('tel:$numero'))) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Appel impossible : $numero')),
      );
    }
  }
}

/// Une livraison restee sans reponse.
class _CarteRelance extends ConsumerStatefulWidget {
  const _CarteRelance({required this.commande});

  final Commande commande;

  @override
  ConsumerState<_CarteRelance> createState() => _CarteRelanceState();
}

class _CarteRelanceState extends ConsumerState<_CarteRelance> {
  bool _occupee = false;

  Future<void> _clore() async {
    setState(() => _occupee = true);
    try {
      await ref.read(depotCommandesProvider).fermerSurDelai(widget.commande.id);
      ref.invalidate(relancesProvider);
      ref.invalidate(commandesClienteProvider);
      await TtsService.instance.dire('Commande fermée sans réponse de la cliente.');
    } finally {
      if (mounted) setState(() => _occupee = false);
    }
  }

  Future<void> _rappeler() async {
    final numero = await ref.read(depotAuthProvider).telephoneProfil(widget.commande.consommateurId);
    if (numero == null || numero.isEmpty) {
      await TtsService.instance.dire('Numéro indisponible');
      return;
    }
    await launchUrl(Uri.parse('tel:$numero'));
  }

  @override
  Widget build(BuildContext context) {
    final heures = widget.commande.depuisLivraison?.inHours ?? 0;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: CarteBio(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const PictoIcon(Picto.clock, size: 34),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(widget.commande.resumeProduits, style: MboaTypo.titre()),
                      Text(
                        'Livrée il y a $heures heures · '
                        '${formaterFcfa(widget.commande.montantLivre ?? 0)} encaissés',
                        style: MboaTypo.aide(),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: GrosBouton(
                    titre: 'Rappeler',
                    picto: Picto.phone,
                    secondaire: true,
                    minHeight: 88,
                    onTap: _rappeler,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: GrosBouton(
                    titre: _occupee ? '…' : 'Clore',
                    picto: Picto.check,
                    sombre: !_occupee,
                    minHeight: 88,
                    onTap: _occupee ? null : _clore,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
