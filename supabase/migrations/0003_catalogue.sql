-- ============================================================================
-- MBOA BIO 237 - 0003 : le catalogue ouvert, les huit cases et les regles du
-- comptoir
--
-- Ce fichier porte la decision qui a change le produit : on ne vend pas neuf
-- fruits dessines sur un logo, on vend ce que le Cameroun produit. Le poisson
-- fumé de Kribi, la chèvre du Nord, le miondo de l'Ouest et le bissap de la
-- saison existent dans la meme grille que le manioc.
--
-- Trois objets :
--   * `categories` : les huit cases touchees par une personne qui ne lit pas,
--     avec leur mot, leur mot prononce et leur pictogramme.
--   * `catalogue`  : la reference des produits connus, leur mesure habituelle
--     au marche, leur prix de tendance et les paliers du curseur. Une
--     reference n'est PAS encore du stock : rien ici ne dit qu'une marchandise
--     est disponible.
--   * `mboa.parametres` : les regles chiffrees du comptoir, modifiables sans
--     redéployer une APK.
--
-- Le catalogue est seme a la main, produit par produit, et non genere : un
-- prix de tendance est une observation de marche, pas une formule. Les
-- valeurs ci-dessous sont des ordres de grandeur constates aux marches de
-- Douala, Yaounde, Bafoussam et Mbouda, a ajuster par l'admin a la premiere
-- semaine d'exploitation.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1. Les huit cases
-- ----------------------------------------------------------------------------
create table public.categories (
  slug         public.categorie_enum primary key,
  libelle      text    not null,
  libelle_voice text   not null,
  ordre        integer not null unique,

  -- Le nom du fichier dans assets/pictos. Une case sans dessin n'est pas une
  -- case : c'est le dessin qui porte la navigation, pas le mot.
  picto        text    not null
);

insert into public.categories (slug, libelle, libelle_voice, ordre, picto) values
  ('fruit',     'Fruits',                'Les fruits',                 1, 'fruit'),
  ('tubercule', 'Tubercules',            'Les tubercules',             2, 'tubercule'),
  ('legume',    'Légumes et feuilles',   'Les légumes et les feuilles',3, 'legume'),
  ('cereale',   'Céréales et graines',   'Les céréales et les graines',4, 'cereale'),
  ('viande',    'Viandes et œufs',       'Les viandes et les œufs',    5, 'viande'),
  ('poisson',   'Poissons et fruits de mer', 'Les poissons',           6, 'poisson'),
  ('huile',     'Huiles et condiments',  'Les huiles et les condiments', 7, 'huile'),
  ('boisson',   'Boissons et laitages',  'Les boissons',               8, 'boisson');

comment on table public.categories is
  'Les huit cases de la grille. Le pictogramme porte la navigation : une personne qui ne lit pas touche un dessin.';

-- ----------------------------------------------------------------------------
-- 2. La reference des produits
--
-- `unite_defaut` et `unite_libelle` disent comment le marche compte ce
-- produit-la : l'arachide en litres, l'ceuf en plateaux, le plantain mûr en
-- regimes, le macabo en boules. Le prix affiche au client est toujours
-- « tant par unite », jamais « tant au kilo » par habitude.
--
-- `paliers` est le curseur de quantite : des positions rondes, jamais un
-- continu qui demande de lire des decimales.
-- ----------------------------------------------------------------------------
create table public.catalogue (
  slug           text primary key check (slug ~ '^[a-z0-9_]{2,40}$'),
  nom            text    not null,
  categorie      public.categorie_enum not null references public.categories (slug),
  unite_defaut   public.unite_enum not null default 'kg',
  unite_libelle  text    not null,
  prix_tendance  integer not null check (prix_tendance between 1 and 1000000),
  paliers        integer[] not null default '{1,2,5,10,25}',
  perissable     boolean not null default true,
  ordre          integer not null
);

create index catalogue_categorie_idx on public.catalogue (categorie, ordre);

comment on table public.catalogue is
  'Produits connus du marché camerounais, avec leur mesure et leur prix de tendance. Une référence n''est pas un stock : la disponibilité se lit dans produits.';

insert into public.catalogue
  (slug, nom, categorie, unite_defaut, unite_libelle, prix_tendance, paliers, perissable, ordre) values

  -- Fruits ------------------------------------------------------------
  ('banane',      'Banane douce',      'fruit', 'kg',      'kilos',      250,  '{2,5,10,20,50}',   true,  1),
  ('plantain',    'Plantain',          'fruit', 'regime',  'régimes',    2500, '{1,2,4,6,10}',     true,  2),
  ('plantain_mur','Plantain mûr',      'fruit', 'regime',  'régimes',    5000, '{1,2,3,4}',        true,  3),
  ('papaye',      'Papaye',            'fruit', 'morceau', 'morceaux',   300,  '{1,2,5,10,20}',    true,  4),
  ('pasteque',    'Pastèque',          'fruit', 'morceau', 'pièces',     800,  '{1,2,5,10}',       true,  5),
  ('mandarine',   'Mandarine',         'fruit', 'kg',      'kilos',      400,  '{1,2,5,10,20}',    true,  6),
  ('orange',      'Orange',            'fruit', 'kg',      'kilos',      300,  '{2,5,10,20}',      true,  7),
  ('ananas',      'Ananas',            'fruit', 'morceau', 'pièces',     800,  '{1,2,5,10}',       true,  8),
  ('corossol',    'Corossol',          'fruit', 'morceau', 'pièces',     500,  '{1,2,3,5}',        true,  9),
  ('mangue',      'Mangue',            'fruit', 'kg',      'kilos',      350,  '{2,5,10,20}',      true, 10),
  ('avocat',      'Avocat',            'fruit', 'morceau', 'pièces',     200,  '{2,5,10,20}',      true, 11),
  ('goyave',      'Goyave',            'fruit', 'kg',      'kilos',      300,  '{1,2,5,10}',       true, 12),
  ('safou',       'Prune (safou)',     'fruit', 'kg',      'kilos',      400,  '{1,2,5}',          true, 13),
  ('coco',        'Noix de coco',      'fruit', 'morceau', 'pièces',     300,  '{1,2,5,10}',       false,14),

  -- Tubercules --------------------------------------------------------
  ('manioc',      'Manioc',            'tubercule','morceau','morceaux',  150,  '{5,10,25,50,100}', false,20),
  ('macabo',      'Macabo',            'tubercule','boule',  'boules',    350,  '{1,3,5,10,20}',    false,21),
  ('patate_douce','Patate douce',      'tubercule','kg',     'kilos',     200,  '{5,10,25,50,100}', false,22),
  ('igname',      'Igname blanc',      'tubercule','morceau','morceaux', 2500,  '{1,2,3,5,10}',     false,23),
  ('igname_jaune','Igname jaune',      'tubercule','morceau','morceaux', 1800,  '{1,2,3,5}',        false,24),
  ('taro',        'Taro',              'tubercule','kg',     'kilos',     300,  '{2,5,10,25}',      false,25),
  ('pomme_de_terre','Pomme de terre',  'tubercule','kg',     'kilos',     450,  '{2,5,10,25,50}',   false,26),
  ('carotte',     'Carotte',           'tubercule','kg',     'kilos',     500,  '{1,2,5,10}',       true, 27),

  -- Legumes et feuilles -----------------------------------------------
  ('tomate',      'Tomate',            'legume', 'litre',   'litres',     500,  '{1,2,5,10}',       true, 30),
  ('oignon',      'Oignon',            'legume', 'litre',   'litres',     750,  '{1,2,5,10}',       false,31),
  ('piment',      'Piment',            'legume', 'morceau', 'morceaux',   400,  '{1,2,5,10}',       true, 32),
  ('ndole',       'Ndolè',             'legume', 'botte',   'bottes',     300,  '{1,2,3,5,10}',     true, 33),
  ('feuille_manioc','Feuille de manioc','legume', 'botte',  'bottes',     250,  '{1,2,5}',          true, 34),
  ('morelle',     'Morelle',           'legume', 'botte',   'bottes',     200,  '{1,2,5}',          true, 35),
  ('gombo',       'Gombo',             'legume', 'kg',      'kilos',      400,  '{1,2,5,10}',       true, 36),
  ('aubergine',   'Aubergine',         'legume', 'kg',      'kilos',      350,  '{1,2,5}',          true, 37),
  ('concombre',   'Concombre',         'legume', 'morceau', 'pièces',     200,  '{1,2,5,10}',       true, 38),
  ('courgette',   'Courgette',         'legume', 'kg',      'kilos',      400,  '{1,2,5}',          true, 39),
  ('salade',      'Salade',            'legume', 'botte',   'bottes',     250,  '{1,2,5}',          true, 40),
  ('chou',        'Chou',              'legume', 'morceau', 'pièces',     500,  '{1,2,5}',          true, 41),
  ('poireau',     'Poireau',           'legume', 'botte',   'bottes',     300,  '{1,2,5}',          true, 42),
  ('celeri',      'Céleri',            'legume', 'botte',   'bottes',     250,  '{1,2,5}',          true, 43),
  ('condiment_vert','Condiment vert',  'legume', 'botte',   'bottes',     500,  '{1,2,3,5}',        true, 44),

  -- Cereales, graines et farines --------------------------------------
  ('riz',         'Riz',               'cereale','kg',      'kilos',      480,  '{1,2,5,25}',       false,50),
  ('mais',        'Maïs',              'cereale','litre',   'litres',     400,  '{1,2,5,10}',       false,51),
  ('arachide',    'Arachide',          'cereale','litre',   'litres',     800,  '{1,2,5,10}',       false,52),
  ('haricot_rouge','Haricot rouge',    'cereale','litre',   'litres',    1400,  '{1,2,5,10}',       false,53),
  ('haricot_blanc','Haricot blanc',    'cereale','litre',   'litres',    1300,  '{1,2,5,10}',       false,54),
  ('lentille',    'Lentille',          'cereale','kg',      'kilos',     1200,  '{1,2,5}',          false,55),
  ('pois_terre',  'Pois de terre',     'cereale','litre',   'litres',     900,  '{1,2,5}',          false,56),
  ('sorgho',      'Sorgho (djado)',    'cereale','litre',   'litres',     450,  '{1,2,5}',          false,57),
  ('ble',         'Blé',               'cereale','kg',      'kilos',      600,  '{1,2,5,10}',       false,58),
  ('farine_ble',  'Farine de blé',     'cereale','paquet',  'paquets',    700,  '{1,2,5,10}',       false,59),
  ('farine_manioc','Farine de manioc', 'cereale','kg',      'kilos',      350,  '{1,2,5,10}',       false,60),
  ('miondo',      'Miondo',            'cereale','paquet',  'paquets',    700,  '{1,2,5,10}',       false,61),
  ('spaghetti',   'Spaghetti',         'cereale','paquet',  'paquets',    700,  '{1,2,5,10}',       false,62),
  ('bobolo',      'Bobolo',            'cereale','morceau', 'pièces',     300,  '{1,2,5}',          true, 63),

  -- Viandes et œufs ---------------------------------------------------
  ('boeuf',       'Bœuf',              'viande', 'kg',      'kilos',     3500,  '{1,2,3,5,10}',     true,  70),
  ('chevre',      'Chèvre',            'viande', 'kg',      'kilos',     3000,  '{1,2,3,5}',        true,  71),
  ('mouton',      'Mouton',            'viande', 'kg',      'kilos',     3200,  '{1,2,3,5}',        true,  72),
  ('porc',        'Porc',              'viande', 'kg',      'kilos',     2500,  '{1,2,3,5}',        true,  73),
  ('poulet',      'Poulet',            'viande', 'morceau', 'pièces',    4000,  '{1,2,3,5}',        true,  74),
  ('poulet_bourg','Poulet de brousse', 'viande', 'morceau', 'pièces',    3000,  '{1,2,3}',          true,  75),
  ('pintade',     'Pintade',           'viande', 'morceau', 'pièces',    5000,  '{1,2,3}',          true,  76),
  ('dinde',       'Dinde',             'viande', 'morceau', 'pièces',    6000,  '{1,2}',            true,  77),
  ('lapin',       'Lapin',             'viande', 'morceau', 'pièces',    2500,  '{1,2,3}',          true,  78),
  ('gibier',      'Gibier (cob, gazelle)','viande','kg',    'kilos',     4000,  '{1,2,3,5}',        true,  79),
  ('sanglier',    'Sanglier (nko)',    'viande', 'kg',      'kilos',     4500,  '{1,2,3}',          true,  80),
  ('abats',       'Abats (foie, tripier)','viande','kg',    'kilos',     2000,  '{1,2,3}',          true,  81),
  ('boucanee',    'Viande fumée (boucanée)','viande','kg',  'kilos',     5000,  '{1,2,3,5}',        false, 82),
  ('oeuf',        'Œuf',               'viande', 'plateau', 'plateaux',  1250,  '{1,2,4,6}',        true,  83),

  -- Poissons et fruits de mer -----------------------------------------
  ('tilapie',     'Tilapie',           'poisson','kg',      'kilos',     2500,  '{1,2,3,5,10}',     true,  90),
  ('maquereau',   'Maquereau',         'poisson','morceau', 'pièces',     500,  '{2,5,10,20}',      true,  91),
  ('sardine',     'Sardine',           'poisson','litre',   'litres',     800,  '{1,2,5}',          true,  92),
  ('catou',       'Catou (clarias)',   'poisson','kg',      'kilos',     2000,  '{1,2,3,5}',        true,  93),
  ('daurade',     'Daurade',           'poisson','kg',      'kilos',     3000,  '{1,2,3}',          true,  94),
  ('poisson_fume','Poisson fumé',      'poisson','morceau', 'pièces',    1500,  '{1,2,5,10}',       false, 95),
  ('poisson_seche','Poisson séché',    'poisson','kg',      'kilos',     3500,  '{1,2,5}',          false, 96),
  ('morue',       'Morue',             'poisson','kg',      'kilos',     2500,  '{1,2,5}',          false, 97),
  ('anchois',     'Anchois (assano)',  'poisson','litre',   'litres',    1000,  '{1,2,5}',          false, 98),
  ('crevette',    'Crevette',          'poisson','litre',   'litres',    2500,  '{1,2,5}',          true,  99),
  ('crabe',       'Crabe',             'poisson','morceau', 'pièces',    2000,  '{1,2,5}',          true, 100),
  ('langouste',   'Langouste',         'poisson','kg',      'kilos',     6000,  '{1,2}',            true, 101),

  -- Huiles et condiments ----------------------------------------------
  ('huile_rouge', 'Huile rouge (palme)','huile', 'litre',   'litres',    1000,  '{1,2,5,10}',       false,110),
  ('huile_arachide','Huile d''arachide','huile', 'litre',   'litres',    1500,  '{1,2,5}',          false,111),
  ('huile_blanche','Huile blanche',    'huile',  'litre',   'litres',     900,  '{1,2,5}',          false,112),
  ('sel',         'Sel',               'huile',  'sachet',  'sachets',    100,  '{1,2,5,10}',       false,113),
  ('sel_germe',   'Sel germé',         'huile',  'sachet',  'sachets',    500,  '{1,2,5,10}',       false,114),
  ('bouillon',    'Bouillon (cube)',   'huile',  'paquet',  'paquets',    500,  '{1,2,5}',          false,115),
  ('piment_sec',  'Piment sec',        'huile',  'litre',   'litres',    1200,  '{1,2,5}',          false,116),
  ('poivre',      'Poivre (djar coriandre)','huile','litre','litres',    1500,  '{1,2,5}',          false,117),
  ('clou_girofle','Clou de girofle',   'huile',  'sachet',  'sachets',    500,  '{1,2,5}',          false,118),
  ('gingembre',   'Gingembre',         'huile',  'kg',      'kilos',     2500,  '{1,2,5}',          false,119),
  ('ail',         'Ail',               'huile',  'morceau', 'têtes',      100,  '{1,2,5,10}',       false,120),
  ('curry',       'Curry',             'huile',  'sachet',  'sachets',    300,  '{1,2,5}',          false,121),
  ('sucre',       'Sucre',             'huile',  'kg',      'kilos',      700,  '{1,2,5,10}',       false,122),
  ('beurre',      'Beurre',            'huile',  'morceau', 'paquets',   2500,  '{1,2}',            true, 123),

  -- Boissons et laitages ----------------------------------------------
  ('bissap',      'Bissap',            'boisson','bouteille','bouteilles', 500, '{1,2,5,10}',       true, 130),
  ('jus_corossol','Jus de corossol',   'boisson','bouteille','bouteilles', 700, '{1,2,5}',          true, 131),
  ('jus_ananas',  'Jus d''ananas',     'boisson','bouteille','bouteilles', 600, '{1,2,5}',          true, 132),
  ('gingembre_jus','Jus de gingembre', 'boisson','bouteille','bouteilles', 600, '{1,2,5}',          true, 133),
  ('vin_palme',   'Vin de palme (matango)','boisson','litre','litres',    1000, '{1,2,5}',          true, 134),
  ('tchap',       'Tchap',             'boisson','bouteille','bouteilles', 400, '{1,2,5}',          true, 135),
  ('lait',        'Lait',              'boisson','litre',   'litres',    1100,  '{1,2,5}',          true, 136),
  ('yaourt',      'Yaourt',            'boisson','morceau', 'pot',        300,  '{1,2,5,10}',       true, 137),
  ('eau',         'Eau',               'boisson','bouteille','bouteilles', 300, '{1,2,5,10}',       false,138);

comment on column public.catalogue.prix_tendance is
  'Prix d''observation au marché, en FCFA par unité. Sert de base au prix de revente du comptoir, pas d''obligation.';

-- ----------------------------------------------------------------------------
-- 3. Les regles chiffrees du comptoir
--
-- Une seule ligne par cle, lues par `mboa.parametre()`. Tout ce qui est une
-- decision economique et non une regle de structure vit ici : changer une
-- marge ne doit pas demander une nouvelle APK.
-- ----------------------------------------------------------------------------
create table mboa.parametres (
  cle    text primary key,
  valeur text not null,
  dit    text not null
);

insert into mboa.parametres (cle, valeur, dit) values
  ('marge_cible_pct',          '35',  'Marge visée sur le prix d''achat, en pourcentage. Un conseil affiché à l''admin, jamais appliqué tout seul.'),
  ('prix_conseille_ecart_pct', '15',  'Écart accepté entre le prix de revente et le prix du marché avant alerte.'),
  ('rupture_alerte',           '5',   'En dessous de cette quantité, la fiche passe en rupture sur l''écran du comptoir.'),
  ('duree_message_vocal_s',    '5',   'Longueur maximale de la note dictée par l''agriculteur.'),
  ('otp_digits',               '4',   'Chiffres du code vocal lu à haute voix au login.'),
  ('delai_confirmation_h',     '12',  'Heures de silence après une livraison avant que le comptoir puisse clore lui-même.'),
  ('telephone_comptoir',       '',    'Le numéro que la cliente touche pour appeler MBOA BIO. Vide tant que l''admin ne l''a pas enregistré : l''appel est alors grisé et dit « le numéro du comptoir n''est pas encore enregistré ».'),
  ('ville_livraison',          'Douala', 'Ville desservie par les motos du comptoir. Affichée sur le devis, jamais demandée à la cliente.');

comment on table mboa.parametres is
  'Les chiffres du commerce, modifiables en SQL sans redéployer. La marge est un conseil : le prix de revente reste saisi par l''admin.';
