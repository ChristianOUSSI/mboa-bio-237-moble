// Verifie les migrations SQL sans serveur Postgres sous la main.
//
// Trois regles, choisies parce que chacune correspond a une faute deja
// commise ici et que Postgres ne signale PAS :
//   1. une ligne `values` plus courte que sa liste de colonnes glisse les
//      valeurs sur les mauvaises colonnes, ou echoue avec un message
//      illisible ;
//   2. deux fois la meme colonne dans une liste : la seconde gagne,
//      silencieusement ;
//   3. les cles des JSONB de panier doivent etre celles que `LigneCommande
//      .fromJson` lit. Le seed a longtemps ecrit `kg` apres le passage aux
//      unites : toute la demo s'affichait avec des quantites a zero, sans
//      une seule erreur.
//
// Le texte d'abord masque (chaines, commentaires, corps dollar-quotes) puis
// scanne est la cle du metier : une apostrophe dans un commentaire francais
// sinon casse tout le decoupage.
//
// usage : node tool/verifier_sql.mjs [dossier]

import { readFileSync, readdirSync, existsSync } from 'node:fs';
import path from 'node:path';

const racine = process.argv[2] || '.';
const dossierMigrations = path.join(racine, 'supabase', 'migrations');
const fichierModele = path.join(racine, 'lib/core/data/models/commande.dart');

const problems = [];
const fichiers = readdirSync(dossierMigrations)
  .filter((f) => f.endsWith('.sql'))
  .sort();

// ---------------------------------------------------------------------------
// Masquage : remplace le contenu des zones non code par des espaces, longueur
// et sauts de ligne conserves, pour que les index du masque pointent encore
// dans le texte original.
// ---------------------------------------------------------------------------
function masquer(sql) {
  const sortie = [...sql];
  const blanc = (i) => {
    if (sql[i] !== '\n') sortie[i] = ' ';
  };

  let i = 0;
  while (i < sql.length) {
    const c = sql[i];
    const suite = sql.slice(i, i + 2);

    if (suite === '--') {
      while (i < sql.length && sql[i] !== '\n') blanc(i++);
      continue;
    }
    if (suite === '/*') {
      const fin = sql.indexOf('*/', i + 2);
      const borne = fin < 0 ? sql.length : fin;
      while (i < borne) blanc(i++);
      i = fin < 0 ? sql.length : i + 2;
      continue;
    }
    if (c === "'") {
      i++;
      while (i < sql.length) {
        if (sql[i] === "'" && sql[i + 1] === "'") {
          blanc(i++);
          blanc(i++);
          continue;
        }
        if (sql[i] === "'") break;
        blanc(i++);
      }
      i = Math.min(i + 1, sql.length);
      continue;
    }
    if (c === '$') {
      const etiq = /^\$[A-Za-z_0-9]*\$/.exec(sql.slice(i));
      if (etiq) {
        const balise = etiq[0];
        const fin = sql.indexOf(balise, i + balise.length);
        const borne = fin < 0 ? sql.length : fin + balise.length;
        while (i < borne) blanc(i++);
        i = borne;
        continue;
      }
    }
    i++;
  }

  return sortie.join('');
}

function ouvrirParen(sql, masque, indexParen) {
  let profondeur = 0;
  for (let i = indexParen; i < sql.length; i++) {
    if (masque[i] === '(') profondeur++;
    else if (masque[i] === ')') {
      profondeur--;
      if (profondeur === 0) return { debut: indexParen, fin: i };
    }
  }
  return null;
}

// Decoupe un contenu de parentheses a la virgule de premier niveau.
function decouper(sql, masque, zone) {
  const morceaux = [];
  let profondeur = 0;
  let depart = zone.debut + 1;
  for (let i = depart; i < zone.fin; i++) {
    const c = masque[i];
    if (c === '(' || c === '[') profondeur++;
    else if (c === ')' || c === ']') profondeur--;
    else if (c === ',' && profondeur === 0) {
      morceaux.push({ debut: depart, fin: i });
      depart = i + 1;
    }
  }
  morceaux.push({ debut: depart, fin: zone.fin });
  return morceaux.filter((m) => sql.slice(m.debut, m.fin).trim().length > 0);
}

// ---------------------------------------------------------------------------
// 1 et 2 : chaque insert
// ---------------------------------------------------------------------------
const insertRe = /\binsert\s+into\s+([a-z_.]+)\s*\(/gi;

function traiterInsert(fichier, sql, masque, match) {
  const table = match[1].toLowerCase();
  const zoneColonnes = ouvrirParen(sql, masque, match.index + match[0].length - 1);
  if (!zoneColonnes) return null;

  const colonnes = decouper(sql, masque, zoneColonnes).map((m) => {
    const brut = sql.slice(m.debut, m.fin).trim();
    return brut.split(/[\s(]+/)[0].toLowerCase().replace(/"/g, '');
  });

  const vus = new Map();
  for (const [i, nom] of colonnes.entries()) {
    if (vus.has(nom)) {
      problems.push(`${fichier}: insert dans ${table}, colonne « ${nom} » deux fois (${vus.get(nom) + 1} et ${i + 1})`);
    } else {
      vus.set(nom, i);
    }
  }

  const apres = masque.slice(zoneColonnes.fin + 1);
  const mValues = /^\s*(values|select)\b/i.exec(apres);
  // `insert ... select` : le nombre de valeurs depend de la requete, pas du
  // texte. Rien a verifier ici.
  if (!mValues || /select/i.test(mValues[1])) return null;

  let curseur = zoneColonnes.fin + 1 + mValues[0].length;
  const lignes = [];

  for (;;) {
    const reste = masque.slice(curseur);
    const mTuple = /^\s*,?\s*\(/.exec(reste);
    if (!mTuple) break;
    const indexParen = curseur + mTuple[0].length - 1;
    const zone = ouvrirParen(sql, masque, indexParen);
    if (!zone) break;
    lignes.push(decouper(sql, masque, zone));
    curseur = zone.fin + 1;

    const suite = /^\s*([,;]|\bon\s+conflict\b)/i.exec(masque.slice(curseur));
    if (!suite || suite[1] !== ',') break;
  }

  for (const [i, morceaux] of lignes.entries()) {
    if (morceaux.length !== colonnes.length) {
      const numero = ligne(sql, morceaux.length ? morceaux[0].debut : zoneColonnes.fin);
      problems.push(
        `${fichier}:${numero}: insert dans ${table}, ${colonnes.length} colonnes mais ${morceaux.length} valeurs (ligne ${i + 1} du bloc values)`,
      );
    }
  }

  return { table, colonnes, lignes };
}

function ligne(sql, index) {
  let n = 1;
  for (let i = 0; i < index && i < sql.length; i++) if (sql[i] === '\n') n++;
  return n;
}

// ---------------------------------------------------------------------------
// 3 : les cles des JSONB de panier, confrontees au contrat du devis
//
// Deux contrats, parce qu'un panier contient deux niveaux d'objets : la
// ligne (ce que la cliente a mis dans son panier) et le composant de pack
// (ce qui sort du stock du comptoir).
//
// Le contrat est declare ici et miroir le commentaire SQL de
// `public.commandes.produits` (0002). Ce ne sont plus les `fromJson` du
// modele Dart qui le dictaient : depuis le modele du comptoir, le JSON est
// ecrit par `mboa.creer_devis` en base, et la base a etre rewritee la
// premiere. Le modele Dart est confronte a part, en une seule ligne, par
// la regle 5.
// ---------------------------------------------------------------------------
const contratLigne = [
  'produit_id', 'slug', 'nom', 'categorie', 'unite', 'quantite', 'prix',
  'cout_achat', 'photo', 'composants',
];
const obligatoireLigne = ['slug', 'nom', 'categorie', 'quantite', 'prix', 'photo'];
const contratComposant = ['slug', 'nom', 'quantite', 'unite'];
const obligatoireComposant = ['slug', 'quantite', 'unite'];

// Une ligne que le catalogue ne connait pas n'a pas de slug, donc pas de
// fiche pour lui preter une unite : c'est la ligne elle-meme qui la porte.
const obligatoireLigneLibre = ['nom', 'categorie', 'quantite', 'unite', 'prix'];
// Tous les `jsonb_build_object` d'une zone, avec les cles de leurs arguments.
function objetsDans(sql, masque, zone) {
  const texte = masque.slice(zone.debut, zone.fin + 1);
  const trouves = [];
  for (const m of texte.matchAll(/jsonb_build_object\s*\(/gi)) {
    const indexParen = zone.debut + m.index + m[0].length - 1;
    const sous = ouvrirParen(sql, masque, indexParen);
    if (!sous) continue;
    const args = decouper(sql, masque, sous);
    const cles = new Map();
    for (let i = 0; i < args.length; i += 2) {
      const cle = sql.slice(args[i].debut, args[i].fin).trim().replace(/'/g, '');
      cles.set(cle, args[i + 1]);
    }
    trouves.push({ ...sous, cles });
  }
  return trouves;
}

const tablesPanier = new Set(['public.commandes', 'commandes', 'public.listes', 'listes']);

function verifierPanier(fichier, sql, masque, zoneLigne) {
  const objets = objetsDans(sql, masque, zoneLigne);
  if (objets.length === 0) return;
  const signer = (index) => `${fichier}:${ligne(sql, index)}`;
  const fautes = (absentes, inconnues, connues) => {
    const parties = [];
    if (absentes.length) parties.push(`sans ${absentes.map((c) => `« ${c} »`).join(', ')}`);
    if (inconnues.length) parties.push(`avec ${inconnues.map((c) => `« ${c} »`).join(', ')}`);
    return `${parties.join(' et ')} ; le modele lit ${connues.join(', ')}`;
  };

  // Un objet est un composant quand un autre objet l'enveloppe : les deux
  // n'ont pas le meme contrat, et les confondre serait inventer des fautes.
  for (const objet of objets) {
    const cleSet = new Set(objet.cles.keys());
    const enveloppe = objets.some(
      (autre) => autre !== objet && autre.debut < objet.debut && autre.fin > objet.fin,
    );

    if (enveloppe) {
      const inconnues = [...cleSet].filter((c) => !contratComposant.includes(c));
      const absentes = obligatoireComposant.filter((c) => !cleSet.has(c));
      if (inconnues.length || absentes.length) {
        problems.push(`${signer(objet.debut)}: composant de pack, ${fautes(absentes, inconnues, contratComposant)}`);
      }
      continue;
    }

    const inconnues = [...cleSet].filter((c) => !contratLigne.includes(c));
    // Une ligne dictee a la voix n'a pas de slug : le catalogue ne connait
    // pas son article. Elle doit en revanche porter son unite, puisqu'aucune
    // fiche ne la lui donnera.
    const libre = !cleSet.has('slug') || /^''$/.test(sql.slice(
      objet.cles.get('slug')?.debut ?? 0,
      objet.cles.get('slug')?.fin ?? 0,
    ).trim());
    const requises = libre ? obligatoireLigneLibre : obligatoireLigne;
    const absentes = requises.filter((c) => !cleSet.has(c));
    if (inconnues.length || absentes.length) {
      problems.push(`${signer(objet.debut)}: ${libre ? 'ligne libre' : 'panier'}, ${fautes(absentes, inconnues, contratLigne)}`);
    }
  }
}

let inserts = 0;
for (const fichier of fichiers) {
  const sql = readFileSync(path.join(dossierMigrations, fichier), 'utf8');
  const masque = masquer(sql);

  for (const m of sql.matchAll(insertRe)) {
    const resulat = traiterInsert(fichier, sql, masque, m);
    if (!resulat) continue;
    inserts++;

    if (!tablesPanier.has(resulat.table)) continue;
    const indexColonne = resulat.colonnes.indexOf('produits');
    if (indexColonne < 0) continue;

    for (const morceaux of resulat.lignes) {
      if (morceaux.length <= indexColonne) continue;
      verifierPanier(fichier, sql, masque, morceaux[indexColonne]);
    }
  }
}

// ---------------------------------------------------------------------------
// 4. Les vocabulaires partages : un enum SQL et son jumeau Dart
//
// `unite_enum`, `categorie_enum`, `statut_enum` et `statut_achat_enum` sont
// ecrits deux fois, une par cote. Une valeur ajoutee en SQL et oubliee en
// Dart ne provoque aucune erreur : `Unite.resolve` retombe sur le kilo,
// `Categorie.resolve` sur le fruit, et le document affiche une valeur fausse
// en toute quietude. C'est deja arrive dans ce depot, d'ou cette regle.
//
// `produit_enum` a disparu du schema : le catalogue est ouvert, les produits
// sont du texte et une categorie. Un enum de neuf fruits dessinait une
// limite que la plateforme n'a plus.
// ---------------------------------------------------------------------------
const vocabulaires = [
  { type: 'unite_enum', dart: 'lib/core/data/models/unite.dart', enum_: 'Unite' },
  { type: 'categorie_enum', dart: 'lib/core/data/models/categorie.dart', enum_: 'Categorie' },
  { type: 'statut_enum', dart: 'lib/core/data/models/statuts.dart', enum_: 'StatutCommande' },
  { type: 'statut_achat_enum', dart: 'lib/core/data/models/achat.dart', enum_: 'StatutAchat' },
];

const enSql = new Map();
for (const fichier of fichiers) {
  const sql = readFileSync(path.join(dossierMigrations, fichier), 'utf8');
  const masque = masquer(sql);

  for (const m of masque.matchAll(/create type public\.(\w+) as enum \(([\s\S]*?)\)/gi)) {
    const nom = m[1];
    const valeurs = [...sql.slice(m.index, m.index + m[0].length).matchAll(/'([a-z_]+)'/g)]
      .map((x) => x[1]);
    if (!enSql.has(nom)) enSql.set(nom, new Set());
    for (const v of valeurs) enSql.get(nom).add(v);
  }

  // La valeur est cherchee dans le texte original : le masque remplace le
  // contenu des chaines par des espaces, et un `'litre'` n'existe donc pas
  // dans le masque. Seule la charpente du `alter type` s'y lit.
  for (const m of masque.matchAll(/alter type public\.(\w+) add value if not exists\s*'[^']*'/gi)) {
    const valeur = /'([a-z_]+)'/.exec(sql.slice(m.index, m.index + m[0].length))[1];
    if (!enSql.has(m[1])) enSql.set(m[1], new Set());
    enSql.get(m[1]).add(valeur);
  }
}

function slugsDart(fichier, nomEnum) {
  const chemin = path.join(racine, fichier);
  if (!existsSync(chemin)) return null;
  const texte = readFileSync(chemin, 'utf8');
  const bloc = new RegExp(`enum ${nomEnum} \\{([\\s\\S]*?);`).exec(texte);
  if (!bloc) return null;
  // Le premier chaine de chaque entree est le slug commun avec la base, que
  // l'entree l'ecrive en position (`kg('kg', ...)`) ou nommee
  // (`fruit(slug: 'fruit', ...)`).
  return new Set(
    [...bloc[1].matchAll(/^\s*[A-Za-z_]\w*\(\s*(?:\w+:\s*)?'([a-z_]+)'/gm)].map((m) => m[1]),
  );
}

for (const { type, dart, enum_ } of vocabulaires) {
  const sql = enSql.get(type);
  const dartSlugs = slugsDart(dart, enum_);
  if (!sql) {
    problems.push(`vocabulaire: aucun enum public.${type} trouve dans les migrations`);
    continue;
  }
  if (!dartSlugs) {
    // Un fichier qui n'existe pas encore n'est pas une faute : c'est la
    // file de la passe Dart. Un seul message, pas un message par valeur.
    problems.push(`vocabulaire: ${enum_} reste a ecrire dans ${dart} (public.${type} a ${sql.size} valeurs)`);
    continue;
  }

  const oubliesDart = [...sql].filter((v) => !dartSlugs.has(v));
  const oubliesSql = [...dartSlugs].filter((v) => !sql.has(v));
  if (oubliesDart.length) {
    problems.push(
      `vocabulaire: ${type} a ${oubliesDart.map((v) => `« ${v} »`).join(', ')} en SQL, absent de ${enum_}.dart`,
    );
  }
  if (oubliesSql.length) {
    problems.push(
      `vocabulaire: ${enum_} cite ${oubliesSql.map((v) => `« ${v} »`).join(', ')} que public.${type} ne connait pas`,
    );
  }
}

// ---------------------------------------------------------------------------
// 5. Le modele Dart parle-t-il encore l'ancien langage ?
//
// Une seule ligne de diagnostic, et non une par cle : quand le contrat
// change de cote, les douze symptomes sont un seul travail. C'est la file de
// la passe Dart, pas une faute par ligne de seed.
// ---------------------------------------------------------------------------
function clesLues(fichier, nomClasse) {
  const chemin = path.join(racine, fichier);
  if (!existsSync(chemin)) return null;
  const texte = readFileSync(chemin, 'utf8');
  const bloc = new RegExp(`factory ${nomClasse}\\.fromJson[\\s\\S]*?\\n\\s*\\}`).exec(texte);
  if (!bloc) return null;
  return new Set([...bloc[0].matchAll(/json\['([a-z_]+)'\]/g)].map((m) => m[1]));
}

const luDart = clesLues('lib/core/data/models/commande.dart', 'LigneCommande');
if (luDart) {
  const surannees = [...luDart].filter((c) => !contratLigne.includes(c));
  const manquantes = contratLigne.filter((c) => !luDart.has(c));
  if (surannees.length || manquantes.length) {
    problems.push(
      `contrat: LigneCommande.fromJson lit ${[...luDart].join(', ')} ; ` +
      `le devis en base ecrit ${contratLigne.join(', ')} ` +
      `(en trop: ${surannees.join(', ') || 'rien'} ; en attente: ${manquantes.join(', ') || 'rien'})`,
    );
  }
}

if (problems.length > 0) {
  for (const p of problems) console.log(`  ${p}`);
  console.error(`verifier_sql : ${problems.length} probleme(s) sur ${inserts} insert(s)`);
  process.exit(1);
}

console.log(`verifie : ${fichiers.length} migrations, ${inserts} insert(s), aucun probleme`);
