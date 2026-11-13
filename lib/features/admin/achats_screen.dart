import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/data/models/achat.dart';
import '../../core/data/models/catalogue.dart';
import '../../core/design_system/boutons.dart';
import '../../core/design_system/carte.dart';
import '../../core/design_system/picto.dart';
import '../../core/design_system/photo.dart';
import '../../core/etat/providers.dart';
import '../../core/theme/mboa_colors.dart';
import '../../core/theme/mboa_typography.dart';
import '../../core/utils/format_monnaie.dart';
import '../../core/utils/identifiants.dart';
import '../../core/voice/note_vocale.dart';
import '../../core/voice/tts_service.dart';

/// Ce que les producteurs proposent au comptoir, et l'argent qui reste du.
///
/// Deux sections, dans l'ordre du travail : les propositions a signer, puis
/// les achats signes qui attendent leur paiement. Signer fait entrer la
/// marchandise au stock ; payer fait sortir l'argent. Les deux gestes sont
/// separes parce que confondre les deux fait croire qu'un stock paye est un
/// stock qui existe, et l'inverse.
class AchatsScreen extends ConsumerWidget {
  const AchatsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final aSigner = ref.watch(achatsEnAttenteProvider);
    final aPayer = ref.watch(achatsAPayerProvider);

    return Scaffold(
      backgroundColor: MboaColors.background,
      appBar: AppBar(
        title: const Text('Achats des producteurs'),
        leading: IconButton(
          onPressed: () => Navigator.of(context).pop(),
          tooltip: 'Retour',
          iconSize: 36,
          icon: const PictoIcon(Picto.back, size: 36, couleur: MboaColors.surface),
        ),
        actions: [
          IconButton(
            onPressed: () {
              ref.invalidate(achatsEnAttenteProvider);
              ref.invalidate(achatsAPayerProvider);
            },
            tooltip: 'Rafraîchir',
            iconSize: 34,
            icon: const PictoIcon(Picto.sync, size: 34, couleur: MboaColors.surface),
          ),
        ],
      ),
      body: SafeArea(
        child: RefreshIndicator(
          color: MboaColors.primary,
          onRefresh: () async {
            ref.invalidate(achatsEnAttenteProvider);
            ref.invalidate(achatsAPayerProvider);
            await ref.read(achatsEnAttenteProvider.future);
          },
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 28),
            children: [
              _TitreSection(
                texte: 'À signer',
                picto: Picto.handGive,
                nombre: aSigner.valueOrNull?.length ?? 0,
              ),
              const SizedBox(height: 12),
              ...aSigner.maybeWhen(
                data: (liste) => liste.isEmpty
                    ? [const _Vide('Aucune proposition en attente', Picto.check)]
                    : [
                        for (final achat in liste) ...[
                          _CarteProposition(achat: achat),
                          const SizedBox(height: 14),
                        ],
                      ],
                orElse: () => [const _Chargement()],
              ),
              const SizedBox(height: 24),
              _TitreSection(
                texte: 'À payer',
                picto: Picto.money,
                nombre: aPayer.valueOrNull?.length ?? 0,
              ),
              const SizedBox(height: 6),
              Text(
                'La marchandise est entrée au stock. L\'argent doit sortir.',
                style: MboaTypo.aide(),
              ),
              const SizedBox(height: 12),
              ...aPayer.maybeWhen(
                data: (liste) => liste.isEmpty
                    ? [const _Vide('Tout le monde est payé', Picto.pouceLeve)]
                    : [
                        for (final achat in liste) ...[
                          _CarteAPayer(achat: achat),
                          const SizedBox(height: 14),
                        ],
                      ],
                orElse: () => [const _Chargement()],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TitreSection extends StatelessWidget {
  const _TitreSection({
    required this.texte,
    required this.picto,
    required this.nombre,
  });

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
      padding: EdgeInsets.all(18),
      child: Center(child: CircularProgressIndicator(color: MboaColors.primary)),
    );
  }
}

/// Une proposition entrante : la photo, ce qui est demandé, et le prix dit.
class _CarteProposition extends StatelessWidget {
  const _CarteProposition({required this.achat});

  final Achat achat;

  @override
  Widget build(BuildContext context) {
    return CarteBio(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              PhotoProduit(
                chemin: achat.photoUrl,
                categorie: achat.categorie,
                slug: achat.slug,
                libelle: achat.nom,
                cote: 96,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(achat.nom, style: MboaTypo.titre()),
                    Text(achat.unite.avec(achat.quantite), style: MboaTypo.corps()),
                    Text(
                      'Demande : ${formaterFcfaCourt(achat.prixDemande)} ${achat.unite.avecArticle}',
                      style: MboaTypo.aide(couleur: MboaColors.primary),
                    ),
                    if (achat.proposeLe != null)
                      Text(
                        'Proposé le ${_jourProposition(achat.proposeLe)}',
                        style: MboaTypo.aide(couleur: MboaColors.textDoux),
                      ),
                  ],
                ),
              ),
              BoutonVoix(texte: _annonceProposition(achat)),
            ],
          ),
          if (achat.audioUrl != null) ...[
            const SizedBox(height: 10),
            BoutonCarre(
              picto: Picto.speaker,
              annonce: 'Écouter le producteur',
              onTap: () => NoteVocaleService.instance.lire(achat.audioUrl!),
            ),
          ],
          const SizedBox(height: 12),
          GrosBouton(
            titre: 'Signer l\'achat',
            picto: Picto.check,
            sousTitre: 'Fixer les deux prix et faire entrer au stock',
            sombre: true,
            minHeight: 92,
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (context) => NegocierAchatScreen(achat: achat),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Un achat deja signe : il ne reste que l'argent.
class _CarteAPayer extends ConsumerStatefulWidget {
  const _CarteAPayer({required this.achat});

  final Achat achat;

  @override
  ConsumerState<_CarteAPayer> createState() => _CarteAPayerState();
}

class _CarteAPayerState extends ConsumerState<_CarteAPayer> {
  bool _occupee = false;

  Future<void> _payer() async {
    final confirme = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: MboaColors.surface,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 20, 18, 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Payer ${formaterFcfa(widget.achat.montant)} ?', style: MboaTypo.titre()),
              const SizedBox(height: 6),
              Text(
                '${widget.achat.nom}, ${widget.achat.unite.avec(widget.achat.quantite)}',
                style: MboaTypo.corps(),
              ),
              const SizedBox(height: 18),
              GrosBouton(
                titre: 'Confirmer le paiement',
                picto: Picto.money,
                sombre: true,
                minHeight: 96,
                onTap: () => Navigator.of(context).pop(true),
              ),
              const SizedBox(height: 10),
              GrosBouton(
                titre: 'Annuler',
                picto: Picto.back,
                secondaire: true,
                minHeight: 80,
                onTap: () => Navigator.of(context).pop(false),
              ),
            ],
          ),
        ),
      ),
    );

    if (confirme != true || !mounted) return;

    setState(() => _occupee = true);
    try {
      final paye = await ref.read(depotAchatsProvider).payer(widget.achat);
      if (paye == null) {
        if (!mounted) return;
        setState(() => _occupee = false);
        await TtsService.instance.dire('Le serveur a refusé le paiement');
        return;
      }

      ref.invalidate(achatsAPayerProvider);
      ref.invalidate(mesAchatsProvider);
      ref.invalidate(mesGainsProvider);

      if (!mounted) return;
      await TtsService.instance.dire(
        '${widget.achat.nom} payé. ${formaterFcfa(widget.achat.montant)}.',
      );
    } finally {
      if (mounted) setState(() => _occupee = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final achat = widget.achat;

    return CarteBio(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              PhotoProduit(
                chemin: achat.photoUrl,
                categorie: achat.categorie,
                slug: achat.slug,
                libelle: achat.nom,
                cote: 84,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(achat.nom, style: MboaTypo.titre()),
                    Text(
                      '${achat.unite.avec(achat.quantite)} · ${formaterFcfaCourt(achat.montant)}',
                      style: MboaTypo.corps(),
                    ),
                  ],
                ),
              ),
              BoutonVoix(texte: '${achat.annonce}. ${formaterFcfa(achat.montant)} à payer.'),
            ],
          ),
          const SizedBox(height: 12),
          GrosBouton(
            titre: _occupee ? 'Paiement en cours' : 'Payer',
            picto: Picto.money,
            chiffre: formaterFcfaCourt(achat.montant),
            minHeight: 88,
            onTap: _occupee ? null : _payer,
          ),
        ],
      ),
    );
  }
}

/// La signature d'un achat : deux prix, une marge, une decision.
///
/// Le prix demande par le producteur reste affiche pendant tout le
/// marchandage. Le prix d'achat signe et le prix de revente se reglent
/// separement, et la marge se voit avant de signer : c'est le seul moment ou
/// l'admin peut encore refuser une entree qui ferait vendre a perte.
class NegocierAchatScreen extends ConsumerStatefulWidget {
  const NegocierAchatScreen({required this.achat, super.key});

  final Achat achat;

  @override
  ConsumerState<NegocierAchatScreen> createState() => _NegocierAchatScreenState();
}

class _NegocierAchatScreenState extends ConsumerState<NegocierAchatScreen> {
  late final TextEditingController _prixAchat;
  late final TextEditingController _prixVente;

  bool _occupee = false;
  String? _erreur;

  @override
  void initState() {
    super.initState();
    _prixAchat = TextEditingController(text: '${widget.achat.prixDemande}');
    _prixVente = TextEditingController(text: '${_venteParDefaut()}');
    WidgetsBinding.instance.addPostFrameCallback((_) {
      TtsService.instance.dire(
        '${widget.achat.annonce}. Le producteur demande ${formaterFcfa(widget.achat.prixDemande)}.',
      );
    });
  }

  @override
  void dispose() {
    _prixAchat.dispose();
    _prixVente.dispose();
    super.dispose();
  }

  int get _achatValeur => int.tryParse(_prixAchat.text) ?? 0;
  int get _venteValeur => int.tryParse(_prixVente.text) ?? 0;

  int get _margeUnite => _venteValeur - _achatValeur;
  int get _margeTotale => (_margeUnite * widget.achat.quantite).round();

  /// Le prix de revente propose : le prix du marche s'il est connu, sinon le
  /// prix demande augmente d'un quart, arrondi aux cinquante francs.
  int _venteParDefaut() {
    final entrees = ref.read(catalogueProvider).valueOrNull ?? const <EntreeCatalogue>[];
    final slug = widget.achat.slug.isEmpty
        ? Identifiants.slugDe(widget.achat.nom)
        : widget.achat.slug;
    final entree = entrees.where((e) => e.slug == slug).firstOrNull;
    final base = (entree != null && entree.prixTendance > 0)
        ? entree.prixTendance
        : (widget.achat.prixDemande * 1.25).round();
    final multiple = (base / 50).round() * 50;
    return multiple < 50 ? 50 : multiple;
  }

  void _bouger(TextEditingController controleur, int delta) {
    final courant = int.tryParse(controleur.text) ?? 0;
    final nouveau = (courant + delta).clamp(1, 1000000);
    setState(() => controleur.text = '$nouveau');
    TtsService.instance.dire(formaterFcfa(nouveau));
  }

  Future<void> _acheter() async {
    if (_achatValeur < 1) {
      setState(() => _erreur = 'Le prix d\'achat doit être plus grand que zéro');
      return;
    }
    if (_venteValeur < 1) {
      setState(() => _erreur = 'Le prix de revente doit être plus grand que zéro');
      return;
    }

    setState(() {
      _occupee = true;
      _erreur = null;
    });

    try {
      final valide = await ref.read(depotAchatsProvider).valider(
            achat: widget.achat,
            prixAchat: _achatValeur,
            prixRevente: _venteValeur,
          );

      if (valide == null) {
        setState(() {
          _erreur = 'Le serveur a refusé cet achat. Vérifie les prix et réessaie.';
        });
        return;
      }

      ref.invalidate(achatsEnAttenteProvider);
      ref.invalidate(achatsAPayerProvider);
      ref.invalidate(stockProvider);
      ref.invalidate(vitrineProvider(null));
      ref.invalidate(commandesAdminProvider);

      if (!mounted) return;
      await TtsService.instance.dire(
        '${widget.achat.nom} acheté. ${widget.achat.unite.avec(widget.achat.quantite)} entre au stock.',
      );
      if (!mounted) return;
      Navigator.of(context).pop();
    } finally {
      if (mounted) setState(() => _occupee = false);
    }
  }

  Future<void> _refuser() async {
    const motifs = [
      'Le prix ne convient pas',
      'La quantité n\'est pas juste',
      'La qualité n\'est pas bonne',
      'La photo ne correspond pas',
    ];

    final motif = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: MboaColors.surface,
      isScrollControlled: true,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Pourquoi refuser ?', style: MboaTypo.titre()),
              const SizedBox(height: 4),
              Text(
                'Le producteur verra cette raison sur son téléphone.',
                style: MboaTypo.aide(couleur: MboaColors.text),
              ),
              const SizedBox(height: 14),
              for (final m in motifs) ...[
                GrosBouton(
                  titre: m,
                  picto: Picto.close,
                  secondaire: true,
                  minHeight: 80,
                  onTap: () => Navigator.of(context).pop(m),
                ),
                const SizedBox(height: 8),
              ],
              GrosBouton(
                titre: 'Revenir',
                picto: Picto.back,
                secondaire: true,
                minHeight: 72,
                onTap: () => Navigator.of(context).pop(),
              ),
            ],
          ),
        ),
      ),
    );

    if (motif == null || !mounted) return;

    setState(() {
      _occupee = true;
      _erreur = null;
    });

    try {
      final refuse = await ref.read(depotAchatsProvider).refuser(
            achat: widget.achat,
            motif: motif,
          );

      if (refuse == null) {
        setState(() => _erreur = 'Le serveur a refusé le refus. Réessaie.');
        return;
      }

      ref.invalidate(achatsEnAttenteProvider);
      ref.invalidate(achatsAPayerProvider);
      ref.invalidate(mesAchatsProvider);

      if (!mounted) return;
      await TtsService.instance.dire('Proposition refusée. $motif.');
      if (!mounted) return;
      Navigator.of(context).pop();
    } finally {
      if (mounted) setState(() => _occupee = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final achat = widget.achat;

    return Scaffold(
      backgroundColor: MboaColors.background,
      appBar: AppBar(
        title: Text(achat.nom),
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
                padding: const EdgeInsets.fromLTRB(18, 16, 18, 28),
                children: [
                  CarteBio(
                    padding: const EdgeInsets.all(14),
                    child: Row(
                      children: [
                        PhotoProduit(
                          chemin: achat.photoUrl,
                          categorie: achat.categorie,
                          slug: achat.slug,
                          libelle: achat.nom,
                          cote: 112,
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(achat.unite.avec(achat.quantite), style: MboaTypo.titre()),
                              Text(achat.categorie.libelle, style: MboaTypo.aide()),
                              const SizedBox(height: 6),
                              Text(
                                'Demande : ${formaterFcfaCourt(achat.prixDemande)} ${achat.unite.avecArticle}',
                                style: MboaTypo.corps(couleur: MboaColors.primary),
                              ),
                            ],
                          ),
                        ),
                        BoutonVoix(texte: achat.annonce),
                      ],
                    ),
                  ),
                  const SizedBox(height: 22),

                  Text('Prix d\'achat', style: MboaTypo.titre()),
                  Text(
                    'Ce que MBOA paie au producteur',
                    style: MboaTypo.aide(couleur: MboaColors.text),
                  ),
                  const SizedBox(height: 8),
                  _ChampPrix(
                    controleur: _prixAchat,
                    suffixe: 'F ${achat.unite.avecArticle}',
                    onMoins: _achatValeur <= 50 ? null : () => _bouger(_prixAchat, -50),
                    onPlus: () => _bouger(_prixAchat, 50),
                    onSaisie: (_) => setState(() {}),
                  ),
                  const SizedBox(height: 22),

                  Text('Prix de revente', style: MboaTypo.titre()),
                  Text(
                    'Ce que la cliente paiera à la porte',
                    style: MboaTypo.aide(couleur: MboaColors.text),
                  ),
                  const SizedBox(height: 8),
                  _ChampPrix(
                    controleur: _prixVente,
                    suffixe: 'F ${achat.unite.avecArticle}',
                    onMoins: _venteValeur <= 50 ? null : () => _bouger(_prixVente, -50),
                    onPlus: () => _bouger(_prixVente, 50),
                    onSaisie: (_) => setState(() {}),
                  ),
                  const SizedBox(height: 18),

                  CarteBio(
                    couleurFond: _margeTotale < 0 ? MboaColors.errorDoux : MboaColors.secondaryDoux,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                    child: Row(
                      children: [
                        PictoIcon(
                          _margeTotale < 0 ? Picto.alert : Picto.money,
                          size: 36,
                          couleur: _margeTotale < 0 ? MboaColors.error : MboaColors.primary,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Marge sur cet achat', style: MboaTypo.aide(couleur: MboaColors.text)),
                              Text(
                                formaterFcfa(_margeTotale),
                                style: MboaTypo.chiffre(
                                  couleur: _margeTotale < 0 ? MboaColors.error : MboaColors.primary,
                                ),
                              ),
                              Text(
                                'soit ${formaterFcfaCourt(_margeUnite)} ${achat.unite.avecArticle}',
                                style: MboaTypo.aide(couleur: MboaColors.text),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
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
                    titre: 'Signer l\'achat',
                    picto: Picto.check,
                    sousTitre: 'La marchandise entre au stock',
                    sombre: true,
                    minHeight: 108,
                    onTap: _acheter,
                  ),
                  const SizedBox(height: 12),
                  GrosBouton(
                    titre: 'Refuser',
                    picto: Picto.close,
                    sousTitre: 'Le producteur verra la raison',
                    couleurFond: MboaColors.error,
                    couleurTexte: MboaColors.surface,
                    minHeight: 92,
                    onTap: _refuser,
                  ),
                ],
              ),
      ),
    );
  }
}

class _ChampPrix extends StatelessWidget {
  const _ChampPrix({
    required this.controleur,
    required this.suffixe,
    required this.onMoins,
    required this.onPlus,
    required this.onSaisie,
  });

  final TextEditingController controleur;
  final String suffixe;
  final VoidCallback? onMoins;
  final VoidCallback onPlus;
  final ValueChanged<String> onSaisie;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        BoutonCarre(
          picto: Picto.minus,
          taille: 76,
          onTap: onMoins,
          annonce: 'Moins cinquante francs',
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
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    textAlign: TextAlign.center,
                    style: MboaTypo.chiffreGeant(),
                    onChanged: onSaisie,
                    decoration: const InputDecoration(
                      border: InputBorder.none,
                      isDense: true,
                    ),
                  ),
                ),
                Text(suffixe, style: MboaTypo.aide(couleur: MboaColors.textDoux)),
              ],
            ),
          ),
        ),
        const SizedBox(width: 10),
        BoutonCarre(
          picto: Picto.plus,
          taille: 76,
          couleurFond: MboaColors.primary,
          couleurTrait: MboaColors.primary,
          onTap: onPlus,
          annonce: 'Plus cinquante francs',
        ),
      ],
    );
  }
}

String _annonceProposition(Achat achat) {
  final base = '${achat.nom}, ${achat.unite.avec(achat.quantite)}, '
      '${formaterFcfa(achat.prixDemande)} ${achat.unite.avecArticle}';
  final audio = achat.audioUrl == null ? '' : '. Le producteur a laissé un message.';
  return '$base$audio';
}

String _jourProposition(DateTime? valeur) {
  if (valeur == null) return '';
  final jour = valeur.day.toString().padLeft(2, '0');
  final mois = valeur.month.toString().padLeft(2, '0');
  return '$jour/$mois/${valeur.year}';
}
