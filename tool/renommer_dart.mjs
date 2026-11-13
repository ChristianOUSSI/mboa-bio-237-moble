// Propage le renommage des colonnes de quantite et de prix cote Dart.
//
// Les identifiants Dart portent le nom de la colonne SQL : garder
// `quantiteKg` pour une colonne devenue `quantite` aurait deplace le
// mensage, pas corrige. Les cles de serialisation JSONB suivent aussi, sinon
// le cache local et la base ne se comprennent plus.
//
//   node tool/renommer_dart.mjs
import { readFileSync, writeFileSync, readdirSync, statSync } from 'node:fs';
import { join } from 'node:path';

function fichiers(dossier, extension) {
  const sortie = [];
  for (const nom of readdirSync(dossier)) {
    if (nom === 'build' || nom === '.dart_tool') continue;
    const chemin = join(dossier, nom);
    if (statSync(chemin).isDirectory()) sortie.push(...fichiers(chemin, extension));
    else if (nom.endsWith(extension)) sortie.push(chemin);
  }
  return sortie;
}

const cibles = [
  ...fichiers('lib', '.dart'),
  ...fichiers('test', '.dart'),
];

const regles = [
  // Identifiants Dart
  [/\bquantiteKg\b/g, 'quantite'],
  [/\bprixKg\b/g, 'prixUnitaire'],
  [/\bkgTotal\b/g, 'resumeQuantites'],
  // Cles de serialisation
  [/'quantite_kg'/g, "'quantite'"],
  [/'prix_kg'/g, "'prix_unitaire'"],
  [/'prix_conseille_kg'/g, "'prix_conseille'"],
  [/'prix_tendance_kg'/g, "'prix_tendance'"],
  [/'paliers_kg'/g, "'paliers'"],
  // Cle de la ligne de panier
  [/'kg'/g, "'quantite'"],
];

const touches = [];

for (const fichier of cibles) {
  const avant = readFileSync(fichier, 'utf8');
  let apres = avant;
  for (const [motif, vers] of regles) apres = apres.replace(motif, vers);
  if (apres !== avant) {
    writeFileSync(fichier, apres);
    touches.push(fichier);
  }
}

console.log(`${touches.length} fichier(s) Dart modifie(s)`);

// Aucun ancien nom ne doit survivre.
const interdits = [
  'quantiteKg', 'prixKg', 'kgTotal', 'quantite_kg', 'prix_kg',
  'prix_conseille_kg', 'prix_tendance_kg', 'paliers_kg',
];
for (const mot of interdits) {
  for (const fichier of cibles) {
    const s = readFileSync(fichier, 'utf8');
    if (new RegExp(`\\b${mot.replace(/\\\$/g, '\\$')}\\b`).test(s)) {
      console.log(`  RESTE ${mot} dans ${fichier}`);
    }
  }
}
