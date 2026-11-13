// ============================================================================
// MBOA BIO 237 - generateur de pictogrammes
//
// Le design system est icon-first : chaque action de l'app est portee par un
// pictogramme au trait, jamais par un emoji ni par un glyphe Unicode. Les
// sources des 38 icones vivent ici pour garantir un style strictement
// identique (viewBox 24, trait 1.6, bouts ronds) ; le rendu est commité dans
// assets/pictos/*.svg et peut etre edite a la main ensuite.
//
//   node tool/gen_pictos.mjs
//
// Regles de dessin :
//   * aucune couleur par defaut : le trait est #212121 et le widget Flutter
//     le recolore avec BlendMode.srcIn. Seules les marques de paiement
//     gardent leur couleur, et l'app ne les teinte pas.
//   * pas de texte dans le SVG : flutter_svg ne rend pas les <text> avec une
//     police embarquee, et le libelle est de toute facon porte par le TTS.
// ============================================================================

import { writeFileSync, mkdirSync } from 'node:fs';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const here = dirname(fileURLToPath(import.meta.url));
const outDir = resolve(here, '..', 'assets', 'pictos');
mkdirSync(outDir, { recursive: true });

const STROKE = '#212121';

/** Enveloppe commune : meme cadre, meme epaisseur, meme rendu des coins. */
function svg(titre, corps, couleur = STROKE) {
  return [
    `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" width="24" height="24"`,
    `     fill="none" stroke="${couleur}" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round">`,
    `  <title>${titre}</title>`,
    `  ${corps}`,
    `</svg>`,
    '',
  ].join('\n');
}

// ----------------------------------------------------------------------------
// 27 pictogrammes d'action
// ----------------------------------------------------------------------------
const ui = {
  camera: [
    'Appareil photo : ajouter ma récolte',
    '<path d="M3 8.6h3.2L7.8 6h8.4l1.6 2.6H21v11.3H3z"/>',
    '<circle cx="12" cy="14.2" r="3.4"/>',
    '<path d="M18.4 11.2h1"/>',
  ],
  basket: [
    'Panier : ma récolte en cours',
    '<path d="M3.6 9.8h16.8l-1.8 10.4H5.4z"/>',
    '<path d="M8.4 9.8 10.2 4M15.6 9.8 13.8 4"/>',
    '<path d="M9.4 13v4.2M12 13v4.2M14.6 13v4.2"/>',
  ],
  money: [
    'Billet : mon argent',
    '<rect x="2.4" y="6.6" width="19.2" height="10.8" rx="1.8"/>',
    '<circle cx="12" cy="12" r="2.9"/>',
    '<path d="M5.6 9.6v4.8M18.4 9.6v4.8"/>',
  ],
  speaker: [
    'Haut-parleur : ecouter',
    '<path d="M3.8 9.4h3.4L11.6 5.4v13.2L7.2 14.6H3.8z"/>',
    '<path d="M15 9.6a3.7 3.7 0 0 1 0 4.8"/>',
    '<path d="M17.8 7.2a7.2 7.2 0 0 1 0 9.6"/>',
  ],
  mic: [
    'Micro : parler / commander à la voix',
    '<rect x="9" y="2.8" width="6" height="11.2" rx="3"/>',
    '<path d="M5.4 11.4a6.6 6.6 0 0 0 13.2 0"/>',
    '<path d="M12 18.2V21.4M8.6 21.4h6.8"/>',
  ],
  trash: [
    'Poubelle : refuser la récolte',
    '<path d="M3.6 6.4h16.8"/>',
    '<path d="M9.4 6.4V3.8h5.2v2.6"/>',
    '<path d="M5.6 6.4 6.8 20.6h10.4L18.4 6.4"/>',
    '<path d="M10 10.2v6.6M14 10.2v6.6"/>',
  ],
  moto: [
    'Moto : livraison',
    '<circle cx="4.8" cy="16.8" r="3.2"/>',
    '<circle cx="19.2" cy="16.8" r="3.2"/>',
    '<path d="M4.8 16.8 9 10.6h5.2l4.6 6.2"/>',
    '<path d="M12.6 8.2h4.2"/>',
    '<path d="M8.4 12.8h6.4"/>',
  ],
  check: [
    'Coche : récolte validée par MBOA',
    '<circle cx="12" cy="12" r="9"/>',
    '<path d="M7.4 12.4 10.4 15.4 16.6 8.6"/>',
  ],
  'hand-give': [
    'Main ouverte : colis remis',
    '<path d="M7.4 20.8c-2.4-.6-3.8-2.6-3.8-5v-4a1.5 1.5 0 0 1 3 0v-1.2"/>',
    '<path d="M6.6 10.6V6.2a1.5 1.5 0 0 1 3 0V9.4"/>',
    '<path d="M9.6 9.4V5.4a1.5 1.5 0 0 1 3 0v4"/>',
    '<path d="M12.6 9.4V6.4a1.5 1.5 0 0 1 3 0v6.4"/>',
    '<path d="M15.6 12.8c1.6.4 2.6 1.6 2.6 3.2 0 2.6-1.6 4.8-4.4 4.8"/>',
  ],
  plus: [
    'Plus : ajouter un kilo',
    '<path d="M12 5v14" stroke-width="2.8"/>',
    '<path d="M5 12h14" stroke-width="2.8"/>',
  ],
  minus: [
    'Moins : retirer un kilo',
    '<path d="M5 12h14" stroke-width="2.8"/>',
  ],
  phone: [
    'Téléphone : appeler',
    '<path d="M4.6 3.4h4l1.6 4.6-2.4 1.6a12 12 0 0 0 6.6 6.6l1.6-2.4 4.6 1.6v4a1.8 1.8 0 0 1-1.9 1.8C10.6 20.6 3.4 13.4 2.8 5.3A1.8 1.8 0 0 1 4.6 3.4z"/>',
  ],
  face: [
    'Visage : photo du visage pour se connecter',
    '<circle cx="12" cy="9.4" r="5.2"/>',
    '<circle cx="10.2" cy="8.6" r=".7" fill="#212121" stroke="none"/>',
    '<circle cx="13.8" cy="8.6" r=".7" fill="#212121" stroke="none"/>',
    '<path d="M9.8 11.4c1.4 1.1 3 1.1 4.4 0"/>',
    '<path d="M4.6 21c1.2-3.4 4-5.2 7.4-5.2s6.2 1.8 7.4 5.2"/>',
  ],
  map: [
    'Carte : les villages',
    '<path d="M3 6.4 9 3.8l6 2.6 6-2.6v13.6L15 20.2l-6-2.6L3 20.2z"/>',
    '<path d="M9 3.8v13.8M15 6.4v13.8"/>',
  ],
  'price-tag': [
    'Étiquette : prix au kilo',
    '<path d="M12.6 3.4H20.6V11.4L11.8 20.2a1.7 1.7 0 0 1-2.4 0L3.8 14.6a1.7 1.7 0 0 1 0-2.4z"/>',
    '<circle cx="16.6" cy="7.4" r="1.5"/>',
  ],
  leaf: [
    'Feuille : bio du village',
    '<path d="M20.4 3.6C10 3.6 4.4 7.8 4.4 14.4c0 2.2 1 4 1 4C12.4 22 20.4 15.8 20.4 3.6z"/>',
    '<path d="M5.4 18.6C8.8 15 13.4 11.4 18 8.2"/>',
  ],
  sync: [
    'Flèches : envoi des données au réseau',
    '<path d="M20 12a8 8 0 0 1-13.8 5.5"/>',
    '<path d="M4 12a8 8 0 0 1 13.8-5.5"/>',
    '<path d="M17.8 3v3.5h-3.5M6.2 21v-3.5h3.5"/>',
  ],
  alert: [
    'Triangle : litige',
    '<path d="M12 3.8 21.2 19.8H2.8z"/>',
    '<path d="M12 9.4v4.6"/>',
    '<circle cx="12" cy="16.8" r=".9" fill="#212121" stroke="none"/>',
  ],
  person: [
    'Personne : le producteur',
    '<circle cx="12" cy="7.8" r="4.2"/>',
    '<path d="M4.8 20.8c.9-4 3.7-6.2 7.2-6.2s6.3 2.2 7.2 6.2"/>',
  ],
  back: [
    'Flèche retour : revenir à l’écran précédent',
    '<path d="M19.5 12H5.2"/>',
    '<path d="M10.8 6.4 5.2 12l5.6 5.6"/>',
  ],
  close: [
    'Croix : fermer sans enregistrer',
    '<path d="M6 6 18 18M18 6 6 18" stroke-width="2.4"/>',
  ],
  clock: [
    'Horloge : le délai de livraison',
    '<circle cx="12" cy="12" r="8.6"/>',
    '<path d="M12 7.2V12l3.6 2.4"/>',
  ],
  'pouce-leve': [
    'Pouce levé : tout est bon',
    '<path d="M7.4 20.6V10.8l3.2-6.4c1.3 0 2.2 1 2.2 2.3v3.9h4.4c1.5 0 2.6 1.4 2.2 2.8l-1.8 6.4'
      + 'c-.4 1.2-1.5 2-2.8 2H7.4z"/>',
    '<rect x="2.8" y="10.6" width="4.6" height="10" rx="1.4"/>',
  ],
  'pouce-baisse': [
    'Pouce baissé : il y a un problème',
    '<path d="M7.4 3.4v9.8l3.2 6.4c1.3 0 2.2-1 2.2-2.3v-3.9h4.4c1.5 0 2.6-1.4 2.2-2.8l-1.8-6.4'
      + 'c-.4-1.2-1.5-2-2.8-2H7.4z"/>',
    '<rect x="2.8" y="3.4" width="4.6" height="10" rx="1.4"/>',
  ],
  liste: [
    'Liste de marché',
    '<path d="M5.4 3.4h13.2v17.2H5.4z"/>',
    '<path d="M8.4 8.2h7.2M8.4 12h7.2M8.4 15.8h4.4"/>',
    '<path d="M3.6 6.4h1.8M3.6 10.4h1.8M3.6 14.4h1.8"/>',
  ],
  partage: [
    'Partager la liste',
    '<circle cx="17.6" cy="5.6" r="2.8"/>',
    '<circle cx="6.2" cy="12" r="2.8"/>',
    '<circle cx="17.6" cy="18.4" r="2.8"/>',
    '<path d="M8.7 10.7 15.1 6.9M8.7 13.3l6.4 3.8"/>',
  ],
  especes: [
    'Paiement en espèces à la livraison',
    '<rect x="2.6" y="8.2" width="14.4" height="8.4" rx="1.6"/>',
    '<circle cx="9.8" cy="12.4" r="2.2"/>',
    '<circle cx="18.6" cy="15.6" r="3.2"/>',
    '<path d="M18.6 14.2v2.8M17.4 15.6h2.4"/>',
  ],
};

// ----------------------------------------------------------------------------
// 9 produits du logo, dans l'ordre de la grille 3x3
// ----------------------------------------------------------------------------
const produits = {
  banane: [
    'Banane',
    '<path d="M4.4 5.4c0 6.4 4.2 11.6 10.8 11.6 2.2 0 3.8-.8 4.4-2 .4-1-.3-1.7-1.3-1.4-2.8.8-5.8-.6-7.8-2.9-1.6-2-2.4-4-2.4-5.6 0-1.1-.6-1.7-1.5-1.7s-2.2.9-2.2 2z"/>',
    '<path d="M19.6 15c1.4.4 2.4 1.4 2.4 2.6"/>',
    '<path d="M6.4 4.6h4.2"/>',
  ],
  plantain: [
    'Plantain',
    '<path d="M3.4 6.6c.6 7.2 5.4 12.6 12.6 13.4 2.4.2 4-.6 4.6-1.9.4-1-.4-1.7-1.4-1.5-3 .6-6.2-.9-8.4-3.4C8.4 10.4 7.4 8 7.2 6.2c-.1-1.1-.7-1.6-1.7-1.5s-2.2 1-2.1 1.9z"/>',
    '<path d="M5.4 5.2 7.8 3"/>',
  ],
  papaye: [
    'Papaye',
    '<path d="M12 4.2c3.8 1.6 6 5 6 8.6 0 4.2-2.7 7-6 7s-6-2.8-6-7c0-3.6 2.2-7 6-8.6z"/>',
    '<path d="M12 4.2V2.4"/>',
    '<circle cx="10.4" cy="12.6" r=".8" fill="#212121" stroke="none"/>',
    '<circle cx="13.6" cy="12.6" r=".8" fill="#212121" stroke="none"/>',
    '<circle cx="12" cy="15.4" r=".8" fill="#212121" stroke="none"/>',
    '<circle cx="12" cy="9.8" r=".8" fill="#212121" stroke="none"/>',
  ],
  pasteque: [
    'Pastèque',
    '<circle cx="9.4" cy="12.4" r="7.6"/>',
    '<path d="M5.4 6.6c1.6 3.8 1.6 8 0 11.8M13.4 6.6c-1.6 3.8-1.6 8 0 11.8M9.4 4.8v15.2"/>',
    '<path d="M17.4 19.6a6.4 6.4 0 0 0 4.4-11"/>',
    '<path d="M17.4 19.6 21.8 8.6"/>',
  ],
  patate_douce: [
    'Patate douce',
    '<path d="M3.6 13.4c1.8-3.6 6-5.4 9.4-4 3.2 1.4 4.2 5.2 2.4 8-1.8 2.8-6 3.6-9 1.8-2.6-1.6-4-3.8-2.8-5.8z"/>',
    '<path d="M13.8 5.4c2.6-1.6 5.8-.6 7 2 1.2 2.4-.2 5.2-2.8 6"/>',
    '<path d="M6.6 9.4 4.4 7"/>',
  ],
  mandarine: [
    'Mandarine',
    '<circle cx="12" cy="13.6" r="7"/>',
    '<path d="M12 6.6v14M5.2 13.6h13.6M7.2 8.6c3 2 6.6 2 9.6 0M7.2 18.6c3-2 6.6-2 9.6 0"/>',
    '<path d="M12 6.6c0-2 1.6-3.4 3.8-3.4 0 2-1.6 3.4-3.8 3.4z"/>',
  ],
  pomme_de_terre: [
    'Pomme de terre',
    '<path d="M4.6 12.6c.6-4.2 4.6-7.2 9-6.6 4.4.6 7.2 4.2 6.4 8.2-.8 4.2-5 7-9.2 6.4-4.2-.6-6.8-3.8-6.2-8z"/>',
    '<circle cx="9.6" cy="10.6" r=".8" fill="#212121" stroke="none"/>',
    '<circle cx="14.6" cy="13.4" r=".8" fill="#212121" stroke="none"/>',
    '<circle cx="10.4" cy="16.4" r=".8" fill="#212121" stroke="none"/>',
  ],
  manioc: [
    'Manioc',
    '<path d="M3.4 8.6 14 5.4c1.4-.4 2.6.4 2.8 1.6l.4 1.8c.2 1.2-.8 2.2-2.2 2.6L4.6 14c-1.4.4-2.6-.4-2.8-1.6l-.2-1.6c-.2-1.2.6-2 1.8-2.2z"/>',
    '<path d="M17.6 11.4c1.4.4 2.2 1.6 2 2.8l-.4 2.2c-.2 1.4-1.4 2.2-2.8 1.8"/>',
    '<path d="M16.6 18.2l4.6-1.4"/>',
    '<circle cx="18.8" cy="8.6" r="2.2"/>',
  ],
  macabo: [
    'Macabo',
    '<path d="M8.4 6.2c3 0 5.2 2.6 5.2 5.8S11 18.4 8 18.4 2.8 15.6 2.8 12.2 5.4 6.2 8.4 6.2z"/>',
    '<path d="M17 5.2c2.8.6 4.6 3.4 4.2 6.4-.4 3-3 5.2-5.8 4.6"/>',
    '<path d="M8.4 6.2c-1 3.2-1 7.2.4 12.2"/>',
    '<path d="M17 5.2 15.6 3"/>',
  ],
};

// ----------------------------------------------------------------------------
// Les huit cases du catalogue ouvert.
//
// Elles ne ressemblent pas aux neuf produits du logo : une case n'est pas un
// fruit, c'est une porte. Chacune doit se reconnaitre a sa silhouette avant
// de se reconnaitre a son mot, parce qu'une partie des utilisatrices ne lit
// pas. Le trait reste le meme (1.6, bouts ronds) pour que la grille paraisse
// dessinee par la meme main que le reste de l'app.
// ----------------------------------------------------------------------------
const categories = {
  fruit: [
    'Fruits',
    '<circle cx="9.6" cy="14.4" r="6"/>',
    '<path d="M9.6 8.4c0-2.2 1.8-3.8 4.4-4 .2 2.4-1.8 4.2-4.4 4z"/>',
    '<circle cx="17.4" cy="10.4" r="3.4"/>',
  ],
  tubercule: [
    'Tubercules',
    '<path d="M3.4 9.2 12.6 6.4c1.4-.4 2.6.4 2.8 1.6l.2 1.4c.2 1.2-.8 2.2-2.2 2.6L4.4 14.8c-1.4.4-2.6-.4-2.8-1.6l-.2-1.4c-.2-1.2.6-2.2 2-2.6z"/>',
    '<circle cx="18.4" cy="15.6" r="4.2"/>',
    '<path d="M15.8 13 21 18.2"/>',
  ],
  legume: [
    'Légumes et feuilles',
    '<path d="M12 21.2c-4.8-1.8-7.6-5.8-7.6-10.4 0-3 1.2-5.6 3-7.2 2.8 1.2 4.4 3.8 5 6.8"/>',
    '<path d="M12 21.2c4.8-1.8 7.6-5.8 7.6-10.4 0-2.4-.8-4.6-2.2-6.2"/>',
    '<path d="M12 21.2V10.4"/>',
  ],
  cereale: [
    'Céréales et graines',
    '<path d="M12 21.4V8.6"/>',
    '<path d="M12 8.6c0-3.2 2.2-5.4 5.4-5.8.4 3.2-1.8 5.6-5.4 5.8z"/>',
    '<path d="M12 13c-3.2 0-5.4-2-5.8-5 3.2-.4 5.6 1.8 5.8 5z"/>',
    '<path d="M12 17.4c3.2 0 5.4-2 5.8-5-3.2-.4-5.6 1.8-5.8 5z"/>',
  ],
  viande: [
    'Viandes et œufs',
    '<path d="M6.4 7.6c4-2 9.6-.8 11.8 3 2 3.6.4 7.8-3.4 9.2-4.2 1.4-9-.6-10.6-4.4-1.2-3 .2-6 2.2-7.8z"/>',
    '<circle cx="8.6" cy="9.6" r="1.6"/>',
    '<path d="M18.4 18c1.8.8 3.6.2 4.4-1.4"/>',
  ],
  poisson: [
    'Poissons et fruits de mer',
    '<path d="M3.4 12c3-3.8 7.4-5.6 11.4-4.6 2.6.6 4.6 2.6 5.6 4.6-1 2-3 4-5.6 4.6-4 1-8.4-.8-11.4-4.6z"/>',
    '<path d="M20.4 12c1.2-1.6 2.2-2.6 2.2-2.6v5.2S21.6 13.6 20.4 12z"/>',
    '<circle cx="8.2" cy="11" r=".9" fill="#212121" stroke="none"/>',
    '<path d="M13 8.4c1 2.4 1 4.8 0 7.2"/>',
  ],
  huile: [
    'Huiles et condiments',
    '<path d="M9.6 3.4h4v2.4l1.6 2.4c.6.8.8 1.6.8 2.6v8.4c0 1.4-1 2.4-2.4 2.4h-4.4c-1.4 0-2.4-1-2.4-2.4v-8.4c0-1 .2-1.8.8-2.6l1.6-2.4z"/>',
    '<path d="M7.6 13.6h8"/>',
    '<path d="M19.8 4.4c1.4 2 2 3.2 2 4.2a2 2 0 1 1-4 0c0-1 .6-2.2 2-4.2z"/>',
  ],
  boisson: [
    'Boissons et laitages',
    '<path d="M6.4 4.6h11.2l-1.4 14.2c-.2 1.2-1.2 2-2.4 2h-3.6c-1.2 0-2.2-.8-2.4-2z"/>',
    '<path d="M7.6 11.8h8.8"/>',
    '<path d="M15.6 4.6 17.4 1.6"/>',
  ],
};

// ----------------------------------------------------------------------------
// Marques de paiement. Couleurs de marque conservees, jamais teintees par
// l'app. Ce sont des MARQUES DE REMPLACEMENT : les logos officiels MTN et
// Orange ne sont pas embarques, leur usage demande une autorisation.
// ----------------------------------------------------------------------------
const paiement = {
  momo: [
    'MTN Mobile Money',
    '<rect x="2.4" y="2.4" width="19.2" height="19.2" rx="4.4" fill="#FFCC00" stroke="#212121"/>',
    '<path d="M7 16.4V8.4l5 4.6 5-4.6v8" stroke-width="2.2"/>',
  ],
  'orange-money': [
    'Orange Money',
    '<rect x="2.4" y="2.4" width="19.2" height="19.2" rx="4.4" fill="#FF7900" stroke="#212121"/>',
    '<circle cx="12" cy="10.4" r="3.4"/>',
    '<path d="M8.6 17.4h6.8" stroke-width="2.2"/>',
  ],
};

let total = 0;
for (const groupe of [ui, produits, categories, paiement]) {
  for (const [nom, [titre, ...corps]] of Object.entries(groupe)) {
    const fichier = join(outDir, `${nom}.svg`);
    writeFileSync(fichier, svg(titre, corps.join('\n  ')), 'utf8');
    total += 1;
  }
}

console.log(`${total} pictogrammes ecrits dans ${outDir}`);
