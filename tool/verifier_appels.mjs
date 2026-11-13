// ============================================================================
// Verificateur d'appels de widgets
//
// Le poste n'a pas de compilateur. Ce qu'un `flutter analyze` aurait vu en
// premier : un nom d'argument qui n'existe pas dans le constructeur appele.
// Ce script reconstruit la table des parametres nommes de chaque classe du
// projet, puis verifie chaque site d'appel.
//
// Il ne couvre que ce que le projet declare lui-meme : les classes de Flutter
// et des paquets sont hors de portee, et c'est justement la que le vrai
// `analyze` sera indispensable.
//
//   node tool/verifier_appels.mjs
// ============================================================================

import { readFileSync, readdirSync, statSync } from 'node:fs';
import { join, sep, posix } from 'node:path';

const racine = process.argv[2] ?? '.';

function fichiers(dossier) {
  const sortie = [];
  if (!statSyncExiste(dossier)) return sortie;
  for (const nom of readdirSync(dossier)) {
    if (nom === 'build' || nom === '.dart_tool') continue;
    const chemin = join(dossier, nom);
    if (statSync(chemin).isDirectory()) sortie.push(...fichiers(chemin));
    else if (nom.endsWith('.dart')) sortie.push(chemin.split(sep).join(posix.sep));
  }
  return sortie;
}

function statSyncExiste(chemin) {
  try {
    statSync(chemin);
    return true;
  } catch {
    return false;
  }
}

const sources = [...fichiers(join(racine, 'lib')), ...fichiers(join(racine, 'test'))];

// ----------------------------------------------------------------------------
// 1. Table des constructeurs
// ----------------------------------------------------------------------------

/** Retire les commentaires : un exemple dans un doc-block n'est pas un appel. */
function sansCommentaires(texte) {
  return texte
    .replace(/\/\*[\s\S]*?\*\//g, ' ')
    .replace(/^[ \t]*\/\/.*$/gm, ' ')
    .replace(/^[ \t]*\/\/\/.*$/gm, ' ');
}

/**
 * Les parametres nommes du constructeur principal d'une classe.
 *
 * Deux formes se croisent dans ce projet :
 *   ClassName({required this.id, this.couleur = rouge, super.key});
 *   ClassName(this.id, {this.taille = 40});
 * `super.key` est un parametre nomme implicite (key), toujours accepte.
 *
 * La liste est extraite par comptage de parentheses, pas par regex : elle
 * commence souvent par une accolade, et un regex qui exclut `{` la rate
 * systematiquement.
 */
function parametresNommes(texte, nomClasse) {
  const resultat = new Set(['key']);
  const recherche = new RegExp(`(?:^|[^.\\w])(?:const\\s+)?${nomClasse}\\s*\\(`, 'g');

  let m;
  while ((m = recherche.exec(texte)) !== null) {
    const ouverte = texte.indexOf('(', m.index + m[0].length - 1);
    const corps = extraireParentheses(texte, ouverte);
    if (corps === null) continue;

    // Seul le groupe entre accolades compte comme parametres nommes.
    const nommes = corps.match(/\{[\s\S]*\}/);
    if (!nommes) continue;

    for (const entree of decouper(nommes[0].slice(1, -1))) {
      const this_ = entree.match(/(?:this\.|super\.)(\w+)/);
      if (this_) {
        resultat.add(this_[1]);
        continue;
      }
      const nu = entree.match(/(\w+)\s*(?:=[\s\S]*)?$/);
      if (nu && !/^(required|covariant|final|const)$/.test(nu[1])) resultat.add(nu[1]);
    }
  }
  return resultat;
}

/** Le contenu entre la parenthese ouverte et sa fermante jumelle. */
function extraireParentheses(texte, indexOuverture) {
  let profondeur = 0;
  for (let i = indexOuverture; i < texte.length; i++) {
    const c = texte[i];
    if (c === '(' || c === '[' || c === '{') profondeur++;
    else if (c === ')' || c === ']' || c === '}') {
      profondeur--;
      if (profondeur === 0) return texte.slice(indexOuverture + 1, i);
    }
  }
  return null;
}

/** Decoupe une liste de parametres sur les virgules de niveau 0. */
function decouper(corps) {
  const parties = [];
  let profondeur = 0;
  let depart = 0;
  for (let i = 0; i < corps.length; i++) {
    const c = corps[i];
    if ('([{'.includes(c)) profondeur++;
    else if (')]}'.includes(c)) profondeur--;
    else if (c === ',' && profondeur === 0) {
      parties.push(corps.slice(depart, i));
      depart = i + 1;
    }
  }
  parties.push(corps.slice(depart));
  return parties.filter((p) => p.trim().length > 0);
}

const classes = new Map();
const textes = new Map();

for (const fichier of sources) {
  const texte = sansCommentaires(readFileSync(fichier, 'utf8'));
  textes.set(fichier, texte);

  for (const m of texte.matchAll(/\b(class|enum)\s+([A-Z]\w*)/g)) {
    const nom = m[2];
    if (!classes.has(nom)) classes.set(nom, new Set());
    classes.get(nom).add(fichier);
  }
}

for (const [nom, fichiersSource] of classes) {
  const union = new Set(['key']);
  for (const fichier of fichiersSource) {
    for (const p of parametresNommes(textes.get(fichier), nom)) union.add(p);
  }
  classes.set(nom, union);
}

// ----------------------------------------------------------------------------
// 2. Sites d'appel
// ----------------------------------------------------------------------------

/** Les `nom:` de niveau 0 a l'interieur des parentheses de l'appel. */
function argumentsNommes(texte, debut) {
  const resultat = [];
  let profondeur = 0;
  let i = debut;
  let depart = -1;

  for (; i < texte.length; i++) {
    const c = texte[i];
    if (c === '(') {
      profondeur++;
      if (profondeur === 1) depart = -1;
      continue;
    }
    if (c === ')') {
      profondeur--;
      if (profondeur === 0) {
        // Le dernier argument n'est suivi d'aucune virgule : sans ce push,
        // tout ce qui precede la fermante echappait a la verification.
        if (depart >= 0) resultat.push(texte.slice(depart, i).trim());
        break;
      }
      continue;
    }
    if (profondeur !== 1) continue;

    if (c === ',') {
      if (depart >= 0) resultat.push(texte.slice(depart, i).trim());
      depart = -1;
      continue;
    }
    if (depart < 0 && /\w/.test(c)) depart = i;
  }
  return resultat;
}

const probleme = [];


for (const fichier of sources) {
  const texte = textes.get(fichier);

  // Seules les constructions nues comptent : `MboaReseau.televerser(` est un
  // appel de methode statique, pas un constructeur, et ses arguments nommes
  // n'ont rien a voir avec une liste de parametres de classe.
  for (const m of texte.matchAll(/(^|[^.\w])([A-Z]\w*)\s*\(/g)) {
    const nom = m[2];
    const parametres = classes.get(nom);
    if (!parametres) continue;

    const indexParen = (m.index + m[1].length) + nom.length;
    const avant = texte.slice(indexParen + 1, indexParen + 2);
    if (avant === '.') continue;

    for (const argument of argumentsNommes(texte, indexParen)) {
      const deuxPoints = argument.indexOf(':');
      if (deuxPoints <= 0) continue;
      const cle = argument.slice(0, deuxPoints).trim();
      if (!/^[\w$]+$/.test(cle)) continue;
      if (parametres.has(cle)) continue;

      // Les labels d'arguments de fonction (builder:, onX:) et les
      // expressions conditionnelles ne sont pas des parametres de widget.
      if (/^(builder|itemBuilder|separatorBuilder|errorBuilder|loadingBuilder|frameBuilder|transitionBuilder|layoutBuilder|onTap|onChanged|onPressed|orElse|data|child|children)$/.test(cle)) continue;

      const ligne = texte.slice(0, m.index).split('\n').length;
      probleme.push(`${fichier}:${ligne} - ${nom} n'a pas de parametre "${cle}"`);
    }
  }
}

// ----------------------------------------------------------------------------
// Dedoublonnage et resultat
// ----------------------------------------------------------------------------
const uniques = [...new Set(probleme)];

if (uniques.length === 0) {
  console.log(`verifie : ${classes.size} classes, aucun argument inconnu`);
} else {
  console.log(`${uniques.length} probleme(s) :`);
  for (const p of uniques) console.log('  - ' + p);
  process.exitCode = 1;
}
