// Renommage des colonnes de quantite et de prix, prepare pour les packs.
//
// `quantite_kg` et `prix_kg` mentaient des qu'un produit ne se vend pas au
// kilo : le macabo en boules, l'huile en bouteilles, le pack ndole en parts.
// Le projet n'etant applique a aucun projet Supabase, les migrations sont
// corrigees sur place plutot que de cumuler un `create then rename` que
// personne n'aura jamais a rejouer.
//
//   node tool/renommer_colonnes.mjs
import { readFileSync, writeFileSync, readdirSync } from 'node:fs';
import { join } from 'node:path';

const dossier = 'supabase/migrations';

const regles = [
  // Colonnes de produits
  ['quantite_kg', 'quantite'],
  ['prix_kg', 'prix_unitaire'],
  ['prix_conseille_kg', 'prix_conseille'],
  // Colonnes de catalogue
  ['prix_tendance_kg', 'prix_tendance'],
  ['paliers_kg', 'paliers'],
  // Cles du JSONB des lignes de panier
  ["'kg'", "'quantite'"],
  ["'nom_enum'", "'nom_enum'"],
];

const cibles = readdirSync(dossier).filter((f) => f.endsWith('.sql')).sort();
const rapport = [];

for (const fichier of cibles) {
  const chemin = join(dossier, fichier);
  const avant = readFileSync(chemin, 'utf8');
  let apres = avant;

  for (const [de, vers] of regles) {
    if (de === vers) continue;
    // Le mot doit etre isolé : sinon `prix_tendance_kg` deviendrait
    // `prix_tendance_prix_unitaire`.
    const motif = new RegExp(`\\b${de.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')}\\b`, 'g');
    apres = apres.replace(motif, vers);
  }

  if (apres !== avant) {
    writeFileSync(chemin, apres);
    const nb = avant.split('\n').filter((l, i) => l !== apres.split('\n')[i]).length;
    rapport.push(`${fichier} : ${nb} ligne(s) touchee(s)`);
  }
}

console.log(rapport.join('\n') || 'rien a renommer');

// Controles : aucune occurrence orpheline ne doit survivre.
const orphelines = ['quantite_kg', 'prix_kg', 'prix_conseille_kg', 'prix_tendance_kg', 'paliers_kg'];
for (const mot of orphelines) {
  for (const fichier of readdirSync(dossier).filter((f) => f.endsWith('.sql'))) {
    const s = readFileSync(join(dossier, fichier), 'utf8');
    if (new RegExp(`\\b${mot}\\b`).test(s)) {
      console.log(`  RESTE ${mot} dans ${fichier}`);
    }
  }
}
