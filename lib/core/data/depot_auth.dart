import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/app_role.dart';
import 'base_locale.dart';
import 'mboa_reseau.dart';
import 'models/langue.dart';
import 'models/profil.dart';

/// Resultat d'une demande de code.
class OtpDemande {
  const OtpDemande({
    required this.telephone,
    required this.canal,
    this.code,
    this.message = 'Code envoyé',
  });

  final String telephone;

  /// `voix` : le code est prononce par l'app ; `sms` : il arrive par SMS.
  final String canal;

  /// Present uniquement en canal `voix`, ou l'app est a la fois generateur et
  /// verificateur. En canal SMS, l'app ne connait jamais le code.
  final String? code;

  final String message;

  bool get codeConnu => code != null;
}

/// Ou vit la verification des 4 chiffres.
enum CanalOtp {
  /// L'app genere le code, le lit a haute voix, et le verifie elle-meme.
  /// Sert hors connexion, en demonstration, et tant que la passerelle
  /// telephonie n'est pas activee.
  voixLocale,

  /// Supabase `signInWithOtp` par SMS.
  smsSupabase,
}

/// Authentification sans mot de passe saisi.
///
/// Le couple `numero de telephone + photo du visage` tient lieu d'identite.
/// Deux decisions sont deliberees et il faut les assumer :
///
///   1. la photo du visage n'est PAS une biometrie. Aucune comparaison
///      automatique n'est faite : elle sert a la personne qui ne sait pas
///      lire pour reconnaitre sa propre ligne et confirmer « c'est moi ».
///      Un controle facial aurait ajoute une dependance d'apprentissage
///      automatique et une collecte de donnees sensibles, pour un resultat
///      mediocre sur les telephone d'entree de gamme vises.
///   2. l'OTP vocal reel (l'appel qui dicte le code) demande une passerelle
///      telephonie derriere une Edge Function. Sans elle, le code est genere
///      et lu localement. Le reste du flux est identique dans les deux modes :
///      changer de canal ne change aucun ecran.
class DepotAuth {
  DepotAuth(this._base);

  final BaseLocale _base;
  final Random _hasard = Random.secure();

  CanalOtp get canal => MboaReseau.client == null ? CanalOtp.voixLocale : CanalOtp.smsSupabase;

  SupabaseClient? get _client => MboaReseau.client;

  /// « 1 2 3 4 » : 4 chiffres, le zero en tete est autorise, c'est un code et
  /// non un nombre.
  String _genererCode() => List.generate(4, (_) => _hasard.nextInt(10)).join();

  /// Etape 1 : le producteur a saisi son numero sur le pave numerique geant.
  ///
  /// Jette [AuthException] quand le numero ne peut pas etre camerounais :
  /// l'ecran le dit a haute voix plutot que d'attendre un echec SMS dix
  /// secondes plus tard.
  Future<OtpDemande> demanderCode(
    String telephone, {
    AppRole role = AppRole.fournisseur,
  }) async {
    final normalise = normaliserTelephone(telephone);
    if (normalise == null) {
      throw AuthException(
        'Le numéro doit commencer par 6 ou 2 et faire 9 chiffres',
      );
    }

    final client = _client;
    if (client == null) {
      final code = _genererCode();
      await _base.ecrireEtat(_cleOtp(normalise), code);
      return OtpDemande(telephone: normalise, canal: 'voix', code: code);
    }

    try {
      await client.auth.signInWithOtp(
        phone: normalise,
        shouldCreateUser: true,
        // Le role part dans les metadonnees d'inscription : c'est le trigger
        // mboa.creer_profil() qui en fait la colonne profiles.role.
        data: {'role': role.slug},
      );
      return OtpDemande(telephone: normalise, canal: 'sms');
    } catch (e) {
      debugPrint('OTP SMS refuse: $e');
      final code = _genererCode();
      await _base.ecrireEtat(_cleOtp(normalise), code);
      return OtpDemande(
        telephone: normalise,
        canal: 'voix',
        code: code,
        message: 'SMS indisponible, la voix remplace le message',
      );
    }
  }

  /// Etape 2 : verification, puis lecture du profil qui en decoule.
  Future<Profil> validerCode({
    required String telephone,
    required String code,
    required AppRole role,
    Uint8List? photoVisageOctets,
  }) async {
    final normalise = normaliserTelephone(telephone) ?? telephone;
    final client = _client;

    if (client != null && canal == CanalOtp.smsSupabase) {
      final reponse = await client.auth.verifyOTP(
        phone: normalise,
        token: code,
        type: OtpType.sms,
      );
      final profil = await _depuisSession(normalise, role);
      if (photoVisageOctets != null) {
        final chemin = await enregistrerVisage(profil.id, photoVisageOctets);
        return profil.copieAvec(photoVisage: chemin);
      }
      return profil;
    }

    final attendu = await _base.lireEtat(_cleOtp(normalise));
    if (attendu == null || attendu != code) {
      throw AuthException('Code incorrect');
    }
    // Le code ne sert qu'une fois.
    await _base.ecrireEtat(_cleOtp(normalise), '');

    final identifiant = await _identifiantPour(normalise);
    final chemin = photoVisageOctets == null
        ? await visageDe(identifiant)
        : await enregistrerVisage(identifiant, photoVisageOctets);

    final existant = await _profilLocal(identifiant);
    final profil = existant?.copieAvec(
          telephone: normalise,
          photoVisage: chemin,
        ) ??
        Profil(
          id: identifiant,
          role: role.slug,
          nom: 'Nouveau',
          village: 'Inconnu',
          telephone: normalise,
          langue: Langue.resolve(await _base.lireEtat('langue')),
          photoVisage: chemin,
        );

    await _base.stocker(Entites.profil, profil.toMap());
    await _base.ecrireEtat('session', profil.id);
    return profil;
  }

  Future<String?> enregistrerVisage(String identifiant, Uint8List octets) async {
    final distant = await MboaReseau.televerser(
      bucket: 'visages',
      dossier: identifiant,
      nom: 'visage.jpg',
      octets: octets,
      mime: 'image/jpeg',
    );
    final chemin = distant ?? 'local/visages/$identifiant.jpg';
    await _base.ecrireEtat('visage_$identifiant', chemin);
    return chemin;
  }

  Future<String?> visageDe(String identifiant) => _base.lireEtat('visage_$identifiant');

  Future<void> deconnexion() async {
    await _base.ecrireEtat('session', '');
    try {
      await _client?.auth.signOut();
    } catch (e) {
      debugPrint('deconnexion distante echouee: $e');
    }
  }

  /// Profil de la session en cours, ou null si personne n'est connecte.
  Future<Profil?> profilActuel() async {
    final client = _client;
    if (client != null && client.auth.currentSession != null) {
      final user = client.auth.currentUser;
      if (user != null) {
        try {
          final ligne = await client.from('profiles').select().eq('id', user.id).maybeSingle();
          if (ligne != null) {
            final profil = Profil.fromMap(ligne);
            await _base.stocker(Entites.profil, profil.toMap());
            return profil;
          }
        } catch (e) {
          debugPrint('profil distant illisible, repli local: $e');
        }
      }
    }

    final identifiant = await _base.lireEtat('session');
    if (identifiant == null || identifiant.isEmpty) return null;
    return _profilLocal(identifiant);
  }

  /// Le profil complet d'un compte, pour l'admin seulement.
  ///
  /// La policy `profiles_lecture_soi_meme` ne rend la ligne qu'a son titulaire
  /// ou a un admin : un compte consommateur qui appellerait cette methode sur
  /// le numero d'une autre recevrait null, pas une erreur. C'est le bon
  /// comportement : l'ecran de livraison doit tourner meme sans l'info.
  Future<Profil?> profilParId(String identifiant) async {
    final client = MboaReseau.client;
    if (client != null) {
      try {
        final ligne = await client
            .from('profiles')
            .select()
            .eq('id', identifiant)
            .maybeSingle();
        if (ligne != null) {
          final profil = Profil.fromMap(ligne);
          await _base.stocker(Entites.profil, profil.toMap());
          return profil;
        }
      } catch (e) {
        debugPrint('profil $identifiant inaccessible: $e');
      }
    }

    return _profilLocal(identifiant);
  }

  /// Le numero de telephone d'un profil, pour le bouton « Appeler ».
  ///
  /// Seuls les admins obtiennent quelque chose : la policy
  /// `profiles_lecture_soi_meme` ne rend la ligne complete qu'a l'interesse
  /// ou a un compte admin. En mode local, la meme information est lue dans
  /// le cache, ce qui couvre la demonstration.
  Future<String?> telephoneProfil(String profilId) async {
    final client = MboaReseau.client;
    if (client != null) {
      try {
        final ligne = await client
            .from('profiles')
            .select('telephone_237')
            .eq('id', profilId)
            .maybeSingle();
        final numero = ligne?['telephone_237'] as String?;
        if (numero != null) return numero;
      } catch (e) {
        debugPrint('telephone profil inaccessible: $e');
      }
    }

    for (final ligne in await _base.lignesCachees(Entites.profil)) {
      if (ligne['id'] == profilId) return ligne['telephone_237'] as String?;
    }
    return null;
  }

  Future<Profil?> _profilLocal(String identifiant) async {
    final lignes = await _base.lignesCachees(Entites.profil);
    for (final ligne in lignes) {
      if (ligne['id'] == identifiant) return Profil.fromMap(ligne);
    }
    return null;
  }

  Future<Profil> _depuisSession(String telephone, AppRole role) async {
    final user = _client?.auth.currentUser;
    if (user == null) throw AuthException('Session impossible');

    Map<String, dynamic>? ligne;
    try {
      ligne = await _client!.from('profiles').select().eq('id', user.id).maybeSingle();
    } catch (e) {
      debugPrint('profils inaccessible: $e');
    }

    final profil = ligne != null
        ? Profil.fromMap(ligne)
        : Profil(
            id: user.id,
            role: role.slug,
            nom: 'Nouveau',
            village: 'Inconnu',
            telephone: telephone,
            langue: Langue.fr,
          );

    await _base.stocker(Entites.profil, profil.toMap());
    await _base.ecrireEtat('session', profil.id);
    return profil;
  }

  Future<String> _identifiantPour(String telephone) async {
    final existant = await _base.lireEtat('id_$telephone');
    if (existant != null && existant.isNotEmpty) return existant;
    // Identifiant derive du numero : un producteur qui change de telephone
    // retrouve ses recoltes, et l'absence de serveur ne cree pas deux comptes
    // differents pour la meme mama.
    final genere = 'v${Random.secure().nextInt(1 << 40).toRadixString(16)}';
    await _base.ecrireEtat('id_$telephone', genere);
    return genere;
  }

  Future<void> memoriserLangue(Langue langue) => _base.ecrireEtat('langue', langue.slug);

  static String _cleOtp(String telephone) => 'otp_$telephone';
}

/// +237 6 99 12 34 56 -> `+237699123456`.
///
/// Accepte le prefixe saisi ou non, les espaces et les points. Renvoie null
/// quand le numero ne peut pas etre camerounais : un abonne local fait 9
/// chiffres apres +237, et commence par 6 (mobile) ou 2 (fixe).
String? normaliserTelephone(String saisi) {
  final chiffres = saisi.replaceAll(RegExp(r'[^0-9]'), '');

  var corps = chiffres;
  if (corps.startsWith('237')) corps = corps.substring(3);

  // Certains clavier ne laissent passer que 8 chiffres : le premier est un 0
  // d'appel international, pas une partie du numero.
  if (corps.length == 10 && corps.startsWith('0')) corps = corps.substring(1);

  if (corps.length != 9) return null;
  if (!corps.startsWith('6') && !corps.startsWith('2')) return null;
  return '+237$corps';
}
