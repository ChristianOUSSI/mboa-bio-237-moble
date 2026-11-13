-- ============================================================================
-- MBOA BIO 237 - 0002 : les tables du comptoir
--
-- profiles / produits / achats / commandes.
--
-- Le modele economique est ecrit dans le schema, pas dans le code : MBOA BIO
-- achete la marchandise chez l'agriculteur, l'entree au stock, puis la revend
-- a la cliente finale. Trois consequences, toutes visibles ci-dessous.
--
--   1. `produits` n'appartient plus a un agriculteur. C'est le stock du
--      comptoir : une ligne par produit vendu, avec sa quantite disponible,
--      son prix de revente et, a cote, son prix d'achat.
--   2. `achats` est la moitie cachee du commerce. Ce que l'agriculteur
--      propose, ce que le comptoir signe, ce qu'il paie. Rien de cette table
--      n'atteint la cliente.
--   3. `commandes` n'a plus de `fournisseur_id`. La cliente achete a MBOA,
--      donc un panier peut melanger le manioc de Mbouda et le bœuf de Fee :
--      la regle du « un panier = un village » tombait avec le modele
--      precedent, et la contrainte de base avec lui.
--
-- Le prix d'achat et la marge ne sont pas caches « par politesse » : ils sont
-- absents des vues lues par l'app cliente, et la RLS de 0005 le verifie. Une
-- colonne qu'il ne faut pas montrer ne doit pas exister dans la requete.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1. PROFILES
-- 1 ligne par humain inscrit. La cle d'identite n'est pas un mot de passe :
-- c'est le numero camerounais + la photo du visage (cf. 0004).
-- ----------------------------------------------------------------------------
create table public.profiles (
  id              uuid primary key references auth.users (id) on delete cascade,
  role            public.role_enum     not null default 'consommateur',
  nom             text                 not null,
  village         text                 not null,
  photo_visage    text,
  telephone_237   text                 not null unique,
  langue          public.langue_enum   not null default 'fr',

  -- Coordonnees du champ : servent a placer le point vert sur la carte admin
  -- et a dire a la moto ou charger la marchandise.
  latitude        double precision,
  longitude       double precision,

  -- L'admin peut geler un compte sans le supprimer (litige en cours).
  actif           boolean              not null default true,
  created_at      timestamptz          not null default now(),
  updated_at      timestamptz          not null default now(),

  constraint profiles_telephone_format
    check (telephone_237 ~ '^\+237[26][0-9]{8}$'),

  constraint profiles_nom_court
    check (char_length(nom) between 1 and 60)
);

create index profiles_role_idx    on public.profiles (role);
create index profiles_village_idx on public.profiles (village);

comment on table public.profiles is
  'Identite des 3 roles. telephone_237 est la seule cle de connexion : pas de mot de passe saisi.';
comment on column public.profiles.photo_visage is
  'Chemin Storage "visages/<uuid>.jpg". Sert de second facteur visuel au login.';
comment on column public.profiles.village is
  E'Pour un fournisseur : le village où il produit, et où la moto va charger. '
  'Pour une cliente : où elle reçoit. Ce champ ne s''affiche plus sur la tuile '
  'du catalogue.';

-- ----------------------------------------------------------------------------
-- 2. PRODUITS : le stock du comptoir
--
-- Une ligne = un produit que MBOA BIO vend, pas un tas photographié par un
-- producteur. Le nom est du texte libre : le Cameroun ne tient pas dans neuf
-- valeurs d'enum, et une femme qui cherche du poisson fumé ou de la chèvre
-- doit le trouver.
--
-- `slug` est la cle stable (lowercase, sans accent, underscore) qui sert a
-- retrouver la fiche quand un achat arrive, a nommer le fichier photo et a
-- grouper les ventes. C'est lui qui empeche « Boeuf », « bœuf » et « BŒUF »
-- de devenir trois stocks differents.
-- ----------------------------------------------------------------------------
create table public.produits (
  id              uuid primary key default gen_random_uuid(),
  slug            text                 not null unique,
  nom             text                 not null,
  categorie       public.categorie_enum not null,

  -- L'unite dit ce que compte `quantite` et ce que facture `prix`. Le marche
  -- compte en litres, boules, paquets, plateaux et regimes autant qu'en kilos.
  unite           public.unite_enum    not null default 'kg',

  -- Stock disponible a la vente. Enleve a la validation du devis, remis en
  -- cas d'annulation : c'est la seule garde qui empeche deux clientes
  -- d'acheter les trois derniers kilos de bœuf.
  quantite        numeric(8, 2)        not null default 0 check (quantite >= 0),

  -- Prix de revente, celui que la cliente voit et paie.
  prix            integer              not null check (prix between 1 and 1000000),

  -- Ce que la marchandise a coute au comptoir, en moyenne glissante sur les
  -- entrées. JAMAIS exposé a l'app cliente : la RLS de 0005 ne le met dans
  -- aucune vue, et la jointure de la vitrine ne le demande pas.
  prix_achat      integer              check (prix_achat between 1 and 1000000),

  photo_reelle    text                 not null,
  photo_filigranee text,
  audio_description_url text,

  -- Un produit qui tourne se perit : la jauge et le bilan ne disent pas la
  -- meme chose d'un stock de tubercules et d'un stock de viande.
  perissable      boolean              not null default true,

  -- Retire de la vitrine sans effacer : l'historique des ventes et la carte
  -- du prix du marche doivent survivre a l'arret d'une reference.
  actif           boolean              not null default true,

  created_at      timestamptz          not null default now(),
  updated_at      timestamptz          not null default now(),

  constraint produits_nom_court check (char_length(nom) between 2 and 60),
  constraint produits_slug_forme check (slug ~ '^[a-z0-9_]{2,40}$')
);

-- La requete la plus chaude de la plateforme : la grille de la cliente, par
-- categorie, dans les produits réellement en stock.
create index produits_vitrine_idx on public.produits (categorie, nom)
  where actif and quantite > 0;

create index produits_stock_idx   on public.produits (quantite);
create index produits_categorie_idx on public.produits (categorie);

comment on table public.produits is
  'Stock du comptoir MBOA BIO. Une ligne par produit vendu, prix de revente visible, prix d''achat réservé à l''admin.';
comment on column public.produits.prix_achat is
  'Coût moyen d''entrée au stock, recalculé à chaque achat validé. Colonne sensible : absente de toute vue lue par la cliente.';

-- ----------------------------------------------------------------------------
-- 3. ACHATS : la moitie que la cliente ne voit pas
--
-- L'agriculteur propose ce qu'il a, comment il le compte et a quel prix.
-- L'admin signe : la ligne passe a `valide`, la quantite entre au stock du
-- comptoir, et le prix d'achat moyen se recalcule. Le payement est un temps
-- distinct, parce qu'un depot d'especes peut avoir lieu le lendemain sans
-- bloquer la marchandise.
--
-- C'est aussi la porte d'entree d'un produit dans le catalogue : si le slug
-- n'existe pas encore, la validation le cree. Personne n'a a « demander un
-- nouveau produit » a un developpeur.
-- ----------------------------------------------------------------------------
create table public.achats (
  id              uuid primary key default gen_random_uuid(),

  -- L'agriculteur qui vend au comptoir. Pas une vitrine, pas de lien avec les
  -- commandes des clientes : la chaine s'arrete ici cote visible.
  fournisseur_id  uuid                 not null references public.profiles (id) on delete cascade,

  -- Renseigne a la validation, quand la fiche stock existe ou vient d'etre
  -- creee. `on delete set null` : supprimer un produit du catalogue ne doit
  -- pas effacer la trace de ce qu'il a coute.
  produit_id      uuid                 references public.produits (id) on delete set null,

  slug            text                 not null,
  nom             text                 not null,
  categorie       public.categorie_enum not null,
  unite           public.unite_enum    not null default 'kg',

  quantite        numeric(8, 2)        not null check (quantite > 0),

  -- Le prix demande par l'agriculteur, par unite. L'admin peut le discuter
  -- avant de signer : c'est `prix_achat` qui entre au stock, pas celui-ci.
  prix_demande    integer              not null check (prix_demande between 1 and 1000000),
  prix_achat      integer              check (prix_achat between 1 and 1000000),

  -- Ce que la marchandise a coute au comptoir. La colonne est calculee, donc
  -- personne ne peut l'ecrire faussement par inadvertance.
  montant         integer generated always as (round(quantite * coalesce(prix_achat, prix_demande))) stored,

  statut          public.statut_achat_enum not null default 'propose',

  -- Photo de la marchandise et note de 5 s : « j'ai quarante kilos de manioc
  -- coupé, à cent vingt le kilo ». L'agriculteur ne tape rien.
  photo_url       text                 not null,
  audio_url       text,

  -- Motif ecrit et motif dit, pour un refus ou un litige a la reception.
  motif           text,
  motif_audio_url text,

  propose_le      timestamptz          not null default now(),
  valide_le       timestamptz,
  valide_par      uuid                 references public.profiles (id) on delete set null,
  paye_le         timestamptz,
  paye_par        uuid                 references public.profiles (id) on delete set null,

  created_at      timestamptz          not null default now(),
  updated_at      timestamptz          not null default now(),

  constraint achats_slug_forme check (slug ~ '^[a-z0-9_]{2,40}$'),
  constraint achats_nom_court  check (char_length(nom) between 2 and 60),

  -- Un achat signe doit dire ce qu'il a vraiment coute : sans prix d'achat,
  -- la marge du comptoir devient une supposition.
  constraint achats_prix_valide check (statut = 'propose' or prix_achat is not null)
);

-- La file d'attente de l'admin, dans l'ordre des depots.
create index achats_file_idx    on public.achats (statut, propose_le asc);

-- Ce que l'agriculteur a vendu au comptoir : son seul ecran de gains.
create index achats_fournisseur_idx on public.achats (fournisseur_id, propose_le desc);

comment on table public.achats is
  'Achats du comptoir chez les agriculteurs. Table invisible pour la cliente : aucune vue, aucune jointure, aucun champ.';
comment on column public.achats.montant is
  'quantite × prix d''achat (prix demandé tant que l''achat n''est pas signé). Colonne calculee, jamais saisie.';

-- ----------------------------------------------------------------------------
-- 4. COMMANDES : le devis de la cliente
-- ----------------------------------------------------------------------------
create table public.commandes (
  id                  uuid primary key default gen_random_uuid(),
  consommateur_id     uuid        not null references public.profiles (id) on delete cascade,

  -- Fige au moment de la caisse : nom, categorie, unite, quantite, prix de
  -- revente et cout d'achat de chaque ligne. Le recu ne doit pas bouger quand
  -- le stock ou les prix bougent apres.
  produits            jsonb       not null,

  statut_enum         public.statut_enum not null default 'nouvelle',
  montant_total       integer     not null check (montant_total >= 0),

  -- Ce que les lignes ont coute au comptoir, fige a la validation. La marge
  -- se lit par difference : c'est la seule mesure qui interesse le comptoir,
  -- et elle ne se recalcule pas sur un prix qui a change depuis.
  cout_achat          integer     not null default 0 check (cout_achat >= 0),

  -- Encaisse a la porte, saisi par l'admin en pointant la livraison.
  montant_livre       integer     check (montant_livre >= 0),

  paiement            public.paiement_enum not null default 'especes',
  paiement_ref        text,
  livraison_moto      boolean     not null default true,

  -- Le moto qui porte le panier. Ajoute par 0012, avec sa propre table.
  -- (voir 0012_livreurs.sql)

  photo_livraison_url text,
  signature_url       text,

  -- Confirmation par la cliente : un tap, deux pouces.
  livree_le           timestamptz,
  livree_par          uuid references public.profiles (id) on delete set null,
  recue_le            timestamptz,
  recue_par           uuid references public.profiles (id) on delete set null,
  satisfaction        text check (satisfaction in ('bon', 'probleme')),
  satisfaction_motif  text,
  satisfaction_audio  text,

  -- Vrai quand le devis est financierement solde. C'est ce champ, et lui
  -- seul, qui fait exister la marge dans le bilan.
  clos                boolean     not null default false,
  clos_par            text,

  -- Annulation : le stock revient, et il faut savoir qui a decide et pourquoi.
  annule_le           timestamptz,
  annule_par          uuid references public.profiles (id) on delete set null,
  motif_annulation    text,

  -- Appel vocal automatisse passe a la cliente a la reception.
  appel_vocal_fait    boolean     not null default false,
  appel_vocal_le      timestamptz,

  created_at          timestamptz not null default now(),
  updated_at          timestamptz not null default now(),

  constraint commandes_produit_non_vide
    check (jsonb_typeof(produits) = 'array' and jsonb_array_length(produits) > 0),

  -- On ne se commande rien a soi-meme.
  constraint commande_pour_quelqu_un check (consommateur_id is not null),

  -- La solde ne se declare que sur un devis termine.
  constraint commandes_clos_final
    check (not clos or statut_enum in ('livree', 'recue'))
);

create index commandes_conso_idx  on public.commandes (consommateur_id, created_at desc);
create index commandes_statut_idx on public.commandes (statut_enum, created_at asc);
create index commandes_file_idx   on public.commandes (created_at asc)
  where statut_enum in ('nouvelle', 'validee_admin');

comment on column public.commandes.produits is
  E'[{"produit_id":"uuid","slug":"manioc","nom":"Manioc","categorie":"tubercule",'
  '"quantite":5.0,"unite":"kg","prix":300,"cout_achat":150,"photo":"chemin"}]\n'
  'ou une ligne dictee a la voix que le catalogue ne connait pas encore :\n'
  '[{"slug":"","nom":"Miondo","categorie":"legume","quantite":5.0,"unite":"paquet",'
  '"prix":700,"photo":""}]';
comment on column public.commandes.cout_achat is
  'Somme des coûts d''achat des lignes, figée à la validation. La marge du devis = montant_livre - cout_achat.';
