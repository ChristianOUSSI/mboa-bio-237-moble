// ============================================================================
// Verificateur statique du depot MBOA BIO 237
//
// Ce poste n'a pas le SDK Flutter : ni `analyze`, ni `test`, ni `build`.
// Ce script remplace la moitie du `flutter analyze`, la partie qui se verifie
// sans compiler :
//
//   1. tout import relatif ou `package:mboa_bio` designe un fichier qui existe ;
//   2. tout symbole du projet utilise dans un fichier est importe ;
//   3. aucun nom de classe n'est declare deux fois ;
//   4. les references de paquets du pubspec sont celles du code.
//
// Les regles 2 et 3 attrapent les vraies fautes de ce genre de projet :
// l'oubli d'import, le copier-coller de classe, le symbole rebaptise dans un
// seul des trois fichiers qui l'utilisaient.
//
//   node tool/verifier.mjs
// ============================================================================

import { readFileSync, readdirSync, statSync } from 'node:fs';
import { join, relative, posix, sep } from 'node:path';

const racine = process.argv[2] ?? '.';
const racinePosix = racine.split(sep).join(posix.sep);
const versRacine = (chemin) => chemin.split(sep).join(posix.sep).replace(racinePosix + '/', '');

// La liste des paquets acceptes se lit dans le pubspec, elle n'est pas
// tenue a la main : une liste figee est une source de faux positifs a chaque
// dependance ajoutee, et un faux positif qui se repete finit par etre ignore.
const pubspecLu = readFileSync(join(racine, 'pubspec.yaml'), 'utf8');
const paquetsDuPubspec = new Set(
  [...pubspecLu.matchAll(/^ {2}([a-z_][a-z0-9_]*):/gm)].map((m) => m[1]),
);
const paquetsAutorises = new Set([
  ...paquetsDuPubspec,
  'mboa_bio',
  'flutter_localizations',
  'flutter_test',
  'flutter_lints',
]);

function fichiersDossier(dossier, extension) {
  const sortie = [];
  for (const nom of readdirSync(dossier)) {
    if (nom === 'build' || nom === '.dart_tool') continue;
    const chemin = join(dossier, nom);
    if (statSync(chemin).isDirectory()) sortie.push(...fichiersDossier(chemin, extension));
    else if (nom.endsWith(extension)) sortie.push(chemin.split(sep).join(posix.sep));
  }
  return sortie;
}

const sources = [
  ...fichiersDossier(join(racine, 'lib'), '.dart'),
  ...fichiersDossier(join(racine, 'test'), '.dart'),
];

const probleme = [];
const erreur = (fichier, message) => probleme.push(`${fichier}: ${message}`);

// ----------------------------------------------------------------------------
// 1. Table des symboles declares
// ----------------------------------------------------------------------------
const declarations = new Map(); // nom -> Set de fichiers
const contenu = new Map(); // fichier -> texte sans commentaires ni chaines
const brutParFichier = new Map(); // fichier -> texte integral, pour lire les imports

const regexDeclaration =
  /^(?:abstract\s+|sealed\s+|final\s+|base\s+|interface\s+)*(class|enum|mixin|typedef)\s+([A-Za-z_]\w*)/gm;

for (const fichier of sources) {
  const brut = readFileSync(fichier, 'utf8');
  // L'ordre compte, et l'ancre aussi.
  //
  // Les chaines DOUBLES partent avant les simples : une apostrophe francaise
  // a l'interieur d'une chaine double ("d'au moins deux elements") sinon
  // ouvre une fausse chaine simple. Et les regex de chaine ne doivent jamais
  // traverser un retour a la ligne, sous peine d'avaler la moitie du fichier
  // comme un seul littéral et de declarer les accolades disparues.
  const propre = brut
    .replace(/\/\*[\s\S]*?\*\//g, ' ')
    .replace(/\/\/.*$/gm, ' ')
    .replace(/"(?:\\.|[^"\\\n])*"/g, '""')
    .replace(/'(?:\\.|[^'\\\n])*'/g, "''");
  contenu.set(fichier, propre);
  brutParFichier.set(fichier, brut);

  for (const [, , nom] of propre.matchAll(regexDeclaration)) {
    if (!declarations.has(nom)) declarations.set(nom, new Set());
    declarations.get(nom).add(fichier);
  }

  // Fonctions et variables de plus haut niveau.
  //
  // `extension on Produit` n'est pas une declaration nommee : le mot `on`
  // suivait l'en-tete d'extension et se retrouvait enregistre comme un symbole
  // du projet, ce qui faisait sonner faux chaque fichier qui l'utilisait.
  for (const m of propre.matchAll(/^(?:const |final |late )?([A-Za-z_][\w<>?, ]*?)\s+([a-zA-Z_]\w*)\s*(?:=|\(|;)/gm)) {
    const nom = m[2];
    if (['main', 'if', 'for', 'while', 'return', 'void', 'class', 'enum', 'on', 'get', 'set'].includes(nom)) continue;
    if (!declarations.has(nom)) declarations.set(nom, new Set());
    declarations.get(nom).add(fichier);
  }
}

for (const [nom, fichiers] of declarations) {
  // Un nom precede d'un underscore est prive a sa bibliotheque : deux
  // `_Ligne` dans deux fichiers distincts sont parfaitement legal en Dart.
  if (nom.startsWith('_')) continue;
  if (fichiers.size > 1) {
    erreur('PROJET', `symbole declare deux fois : ${nom} dans ${[...fichiers].join(', ')}`);
  }
}

// ----------------------------------------------------------------------------
// 2. Imports : existence, puis couverture des symboles utilises
// ----------------------------------------------------------------------------
const regexImport = /^import\s+['"]([^'"]+)['"]/gm;

const cheminDeImport = (fichier, cible) => {
  // Tous les chemins du script sont normalises en slashes : la resolution
  // doit rester en posix, sinon join() Windows produit un chemin mixte qui
  // ne correspond a rien.
  if (cible.startsWith('package:mboa_bio/')) {
    return posix.normalize(posix.join(racinePosix, 'lib', cible.slice('package:mboa_bio/'.length)));
  }
  if (cible.startsWith('package:')) return null;
  return posix.normalize(posix.join(posix.dirname(fichier), cible));
};

for (const fichier of sources) {
  const texte = contenu.get(fichier);
  // Les imports se lisent dans le texte brut : l assainisseur remplace toute
  // chaine par une chaine vide, y compris celle d un import.
  const imports = [...brutParFichier.get(fichier).matchAll(regexImport)].map((m) => m[1]);

  const resolus = new Set();
  for (const cible of imports) {
    if (cible.startsWith('dart:')) continue;

    const chemin = cheminDeImport(fichier, cible);

    if (cible.startsWith('package:') && !cible.startsWith('package:mboa_bio/')) {
      const nomPaquet = cible.slice('package:'.length).split('/')[0];
      if (!paquetsAutorises.has(nomPaquet)) {
        erreur(versRacine(fichier), `paquet non declare au pubspec : ${nomPaquet}`);
      }
      continue;
    }

    if (chemin == null) continue;
    if (!sources.includes(chemin)) {
      erreur(versRacine(fichier), `import introuvable : ${cible}`);
      continue;
    }
    resolus.add(chemin);
  }

  // Symboles du projet utilises ici mais declares ailleurs et non importes.
  for (const [nom, fichiersSource] of declarations) {
    if (fichiersSource.has(fichier)) continue;
    if (!new RegExp(`\\b${nom}\\b`).test(texte)) continue;

    const couvert = [...fichiersSource].some((s) => resolus.has(s));
    if (!couvert) {
      erreur(versRacine(fichier), `symbole utilise sans import : ${nom} (declare dans ${[...fichiersSource].map((f) => versRacine(f)).join(', ')})`);
    }
  }
}

function readFileSyncExists(chemin) {
  try {
    readFileSync(chemin);
    return true;
  } catch {
    return false;
  }
}

// ----------------------------------------------------------------------------
// 3. Paquets cites dans le code mais absents du pubspec
// ----------------------------------------------------------------------------
const pubspec = readFileSync(join(racine, 'pubspec.yaml'), 'utf8');
const paquetsPubspec = new Set(
  [...pubspec.matchAll(/^ {2}([a-z_][a-z0-9_]*):/gm)].map((m) => m[1]),
);

for (const fichier of sources) {
  const texte = contenu.get(fichier);
  for (const m of texte.matchAll(/^import\s+'package:([a-z_0-9]+)/gm)) {
    if (!paquetsPubspec.has(m[1])) {
      erreur(versRacine(fichier), `package importé sans entrée au pubspec : ${m[1]}`);
    }
  }
}

// ----------------------------------------------------------------------------
// 4. Assets cites dans le Dart qui n'existent pas
// ----------------------------------------------------------------------------
for (const fichier of sources) {
  const texte = contenu.get(fichier);
  for (const m of fichier.endsWith('.dart') ? texte.matchAll(/['"](assets\/[\w/.-]+\.\w+)['"]/g) : []) {
    if (!readFileSyncExists(join(racine, m[1]))) {
      erreur(versRacine(fichier), `asset manque : ${m[1]}`);
    }
  }
}

// ----------------------------------------------------------------------------
// 6. Apostrophe dans une chaine Dart delimitee par des apostrophes
//
// `throw StateError('Un pack se compose d'au moins deux elements')` est une
// erreur de syntaxe, pas une faute de gout : la chaine se termine au `d'`,
// et le reste de la ligne devient du code. Le francais en contient partout.
//
// La regle est structurelle, pas lexicale : hors commentaires, hors chaines
// doubles ou backquotees, et HORS chaines triple-quotées (le SQL embarque
// dans ce projet en est plein), une ligne doit contenir un nombre PAIR
// d'apostrophes non echappees. Un nombre impair ne peut venir que d'une
// chaine simple fermee trop tot.
// ----------------------------------------------------------------------------
function sansChainesMultilignes(texte) {
  return texte
    .replace(/'''[\s\S]*?'''/g, "''")
    .replace(/"""[\s\S]*?"""/g, '""');
}

for (const fichier of sources) {
  const lignes = sansChainesMultilignes(readFileSync(fichier, 'utf8')).split('\n');

  lignes.forEach((ligne, index) => {
    if (/^\s*(\/\/|\/\*|\*)/.test(ligne)) return;

    const sansAutres = ligne
      .replace(/"(?:\\.|[^"\\])*"/g, '')
      .replace(/`(?:\\.|[^`\\])*`/g, '')
      .replace(/\/\/.*$/, '');

    const nb = (sansAutres.match(/(?<!\\)'/g) || []).length;
    if (nb % 2 !== 0) {
      erreur(
        versRacine(fichier),
        `ligne ${index + 1}: ${nb} apostrophe(s), chaine simple probablement fermee trop tot`,
      );
    }
  });
}

// ----------------------------------------------------------------------------
// 7. Equilibre des delimitateurs
//
// Sans compilateur, un fichier tronque ou une accolade oubliee est l'erreur
// la plus probable d'un depot ecrit a l'aveugle. Le controle est grossier
// (il ne connait pas la grammaire Dart) mais il attrape la classe de faute
// qui ferait echouer `pub get` sur la premiere ligne.
// ----------------------------------------------------------------------------
for (const fichier of sources) {
  const texte = sansChainesMultilignes(contenu.get(fichier));
  const compte = { '(': 0, '[': 0, '{': 0 };
  const fermante = { ')': '(', ']': '[', '}': '{' };
  let desequilibre = null;

  for (const c of texte) {
    if (compte[c] !== undefined) compte[c]++;
    else if (fermante[c]) {
      const jumelle = fermante[c];
      if (compte[jumelle] === 0) {
        desequilibre = `fermante "${c}" sans ouverte`;
        break;
      }
      compte[jumelle]--;
    }
  }

  if (!desequilibre) {
    const restant = Object.entries(compte).filter(([, n]) => n > 0);
    if (restant.length) desequilibre = restant.map(([c, n]) => `${n} x "${c}"`).join(', ');
  }
  if (desequilibre) erreur(versRacine(fichier), `delimitateurs: ${desequilibre}`);
}

// ----------------------------------------------------------------------------
// 6. Tous les pictogrammes sont declares dans l'enum Picto, et inversement
// ----------------------------------------------------------------------------
const svg = readdirSync(join(racine, 'assets', 'pictos')).filter((f) => f.endsWith('.svg'));
// Texte brut ici aussi : les noms de fichier sont des chaines de caracteres,
// et l'assainisseur les efface.
const pictoDart = brutParFichier.get(posix.join(racinePosix, 'lib/core/design_system/picto.dart')) ?? '';
const fichiersPicto = new Set([...pictoDart.matchAll(/\w+\('([\w-]+)'\)/g)].map((m) => m[1]));

for (const nom of svg) {
  if (!fichiersPicto.has(nom.replace('.svg', ''))) {
    erreur('PICTOS', `SVG sans entrée dans l'enum Picto : ${nom}`);
  }
}
for (const nom of fichiersPicto) {
  if (!svg.includes(`${nom}.svg`)) {
    erreur('PICTOS', `enum Picto sans fichier : ${nom}.svg`);
  }
}

// ----------------------------------------------------------------------------
// 8. Noms retires, jamais reintroduits
//
// Un renommage laisse toujours des orphelins : `ligne.kg` apres que le champ
// est devenu `quantite`, `CardTheme` apres que Flutter l'a rebaptise. Le
// compilateur les verrait, mais il n'est pas ici. Cette liste est donc la
// memoire des renommages du projet : chaque regle ajoutee ici est une faute
// qui ne peut plus revenir incognito.
// ----------------------------------------------------------------------------
const retirs = [
  // `Unite.kg` est l'unite kilos, parfaitement legitime ; `this.kg` est un
  // champ local d'un widget prive. Seuls les acces aux champs rebaptises sont
  // une faute, et un motif textuel brut les confondait avec les deux.
  [/[^.\w]([a-zA-Z_]\w*)\.kg\b/, 'LigneCommande.kg est devenu quantite (unites multiples depuis les packs)',
    (m) => m[1] === 'Unite' || m[1] === 'this'],
  [/\bquantiteKg\b/, 'Produit.quantiteKg est devenu quantite', null],
  [/\bprixKg\b/, 'Produit.prixKg est devenu prixUnitaire', null],
  [/\bkgTotal\b/, 'Commande.kgTotal est devenu resumeQuantites, un texte', null],
  [/\bquantite_kg\b/, 'colonne SQL renommee quantite', null],
  [/\bprix_kg\b/, 'colonne SQL renommee prix_unitaire', null],
  [/\bPaiementScreen\b/, 'remplace par CommanderScreen : on ne paie plus dans l app', null],
  [/_livre\(/, 'le producteur ne pointe plus la livraison, c est l admin', null],
];

for (const fichier of sources) {
  const texte = brutParFichier.get(fichier);
  const lignes = texte.split('\n');

  lignes.forEach((ligne, index) => {
    if (/^\s*(\/\/|\/\*|\*)/.test(ligne)) return;

    for (const [motif, raison, exempter] of retirs) {
      const m = ligne.match(motif);
      if (!m) continue;
      if (exempter && exempter(m)) continue;
      erreur(
        versRacine(fichier),
        `ligne ${index + 1}: ${raison} | ${ligne.trim().slice(0, 60)}`,
      );
    }
  });
}

// ----------------------------------------------------------------------------
// 9. Mots reserves Dart employes comme noms de membre
//
// `Unite.with(3)` s'est ecrit tout seul, parce qu'en francais « avec » se dit
// with. Le compilateur refuserait la ligne : un mot reserve ne peut pas etre
// un nom de membre, donc aucun `X.with(...)` legitime n'existe dans Dart ni
// dans un paquet. Pas de faux positif possible, et la regle tient sur ce seul
// argument, c'est le genre de faute qu'aucun humain ne voit en relisant.
//
// `super(...)` et `Foo.new` sont exclus : ce sont des formes legitimes du
// langage, pas des noms de membre.
// ----------------------------------------------------------------------------
const reserves = [
  'with', 'in', 'is', 'case', 'class', 'enum', 'void', 'var', 'final',
  'try', 'for', 'if', 'while', 'return',
];
const reserveAppel = new RegExp(`\\.(${reserves.join('|')})\\s*\\(`);
const reserveGetter = new RegExp(`\\bget\\s+(${reserves.join('|')})\\b`);
const reserveDeclaration = /[\w<>?,]+\s+(with|in|is|case|class|enum)\s*\(/;

for (const fichier of sources) {
  const lignes = sansChainesMultilignes(contenu.get(fichier)).split('\n');

  lignes.forEach((ligne, index) => {
    if (/^\s*(\/\/|\/\*|\*)/.test(ligne)) return;
    const m = reserveAppel.exec(ligne) ?? reserveGetter.exec(ligne) ?? reserveDeclaration.exec(ligne);
    if (m) {
      erreur(
        versRacine(fichier),
        `ligne ${index + 1}: « ${m[1] ?? m[2]} » est un mot reserve Dart, jamais un nom de membre | ${ligne.trim().slice(0, 60)}`,
      );
    }
  });
}

// ----------------------------------------------------------------------------
if (probleme.length === 0) {
  console.log(`verifie : ${sources.length} fichiers Dart, ${svg.length} pictogrammes, aucun probleme`);
} else {
  console.log(`${probleme.length} probleme(s) :`);
  for (const p of probleme) console.log('  - ' + p);
  process.exitCode = 1;
}
