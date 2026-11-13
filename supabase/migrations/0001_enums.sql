-- ============================================================================
-- MBOA BIO 237 - 0001 : schema, extensions et enums
-- Application : comptoir vivrier ultra-accessible (Cameroun).
-- MBOA BIO achete chez l'agriculteur, met en stock, revend en devis paye a
-- la livraison. Trois roles partagent la meme base : fournisseur (vendeur de
-- marchandise brute), admin (le comptoir), consommateur (la cliente finale).
-- ============================================================================

create schema if not exists mboa;
alter default privileges in schema mboa revoke execute on functions from public;
revoke create on schema public from public, anon, authenticated;

comment on schema mboa is
  'Fonctions internes (RLS, triggers, contact chiffre). Ne jamais exposer au client.';

create extension if not exists pgcrypto with schema extensions;

-- ----------------------------------------------------------------------------
-- Roles de l'application. Le flavor Flutter decide quel role est demande a
-- l'inscription ; la colonne profiles.role fait foi cote serveur.
-- ----------------------------------------------------------------------------
create type public.role_enum as enum ('fournisseur', 'admin', 'consommateur', 'livreur');

-- ----------------------------------------------------------------------------
-- Les huit cases du catalogue. Une personne qui ne lit pas ne cherche pas un
-- produit dans une liste de quatre-vingts lignes : elle touche une case, puis
-- une photo. Le nombre de cases tient sur un ecran sans scroll, ce qui est le
-- seul critere qui vaille ici.
--
-- Ce n'est PAS la liste des produits du logo : le logo montre neuf fruits, la
-- platforme vend tout ce qui se produit au Cameroun, viandes et poissons
-- compris. Un enum ferme de produits aurait recree la limite que ce fichier
-- supprime.
-- ----------------------------------------------------------------------------
create type public.categorie_enum as enum (
  'fruit',
  'tubercule',
  'legume',
  'cereale',
  'viande',
  'poisson',
  'huile',
  'boisson'
);

comment on type public.categorie_enum is
  E'« huile » couvre huiles et condiments (huile rouge, sel germé, clou de '
  'girofle, piment sec). « boisson » couvre boissons et laitages (bissap, vin '
  'de palme, lait, yaourt). Huit cases, pas une de plus : la grille doit tenir '
  'sans défilement.';

-- ----------------------------------------------------------------------------
-- Ce que compte une quantite. Le marche ne vend pas tout au kilo : le macabo
-- en boules, l'arachide en litres, le miondo en paquets, l'ceuf en plateaux,
-- le plantain mûr en regimes. Une colonne de quantite sans unite associee
-- affiche un prix que la cliente ne retrouvera pas a la porte.
-- ----------------------------------------------------------------------------
create type public.unite_enum as enum (
  'kg',
  'boule',
  'bouteille',
  'botte',
  'morceau',
  'part',
  'litre',
  'paquet',
  'plateau',
  'regime',
  'sachet'
);

-- ----------------------------------------------------------------------------
-- Cycle de vie d'un devis. Le stock part a la validation, pas a la livraison :
-- deux clientes ne peuvent pas acheter les trois derniers kilos de bœuf.
-- nouvelle        -> la cliente vient d'envoyer son devis
-- validee_admin   -> le comptoir a valide, le stock est sorti
-- en_livraison    -> la moto est partie du depot
-- livree          -> remise en main propre
-- recue           -> la cliente a pose son pouce ; seul ce tap solde
-- annulee         -> le stock est revenu, rien n'est du
--
-- Six valeurs, quatre icones a l'ecran : `recue` ne dessine pas une
-- cinquieme case, elle ferme la quatrieme en un pouce plein.
-- ----------------------------------------------------------------------------
create type public.statut_enum as enum (
  'nouvelle',
  'validee_admin',
  'en_livraison',
  'livree',
  'recue',
  'annulee'
);

-- ----------------------------------------------------------------------------
-- Etat de la marchandise proposee par un agriculteur. C'est l'autre moitie du
-- commerce : le comptoir achete ferme, il ne prend pas en consignation.
--
-- Un seul enum pour la file d'attente du comptoir. La qualite et le payement
-- sont deux questions differentes, mais aucune ne se joue sur deux colonnes
-- qui peuvent se contredire : `litige` est une entree par le refus, jamais
-- par le payement.
--
-- propose -> l'agriculteur a dit quoi, combien et a quel prix
-- valide  -> le comptoir signe, la marchandise entre au stock
-- paye    -> l'argent est sorti, l'agriculteur n'attend plus rien
-- litige  -> refuse a la reception, le stock ne bouge pas
-- annule  -> plus personne n'attend rien de personne
--
-- La moderation des produits du catalogue MBOA n'existe plus : un produit
-- n'est pas « valide par l'admin », il est entre au stock par un achat.
-- ----------------------------------------------------------------------------
create type public.statut_achat_enum as enum (
  'propose',
  'valide',
  'paye',
  'litige',
  'annule'
);

comment on type public.statut_achat_enum is
  E'valide = entrée de stock immédiate et prix d''achat figé sur la ligne ; '
  'payé = la sortie d''argent est enregistrée par l''admin. Les deux sont '
  'distincts parce qu''un payement peut passer par un dépôt d''espèces le '
  'lendemain, sans bloquer la marchandise. litige = la marchandise est '
  'refusée à la réception, le stock ne bouge pas.';

-- Le reglement se fait a la porte, en especes. Les deux marques restent
-- declarees pour l'historique : un client qui paie a la moto peut toujours
-- avoir demande un envoi MoMo, et le devis doit dire lequel.
create type public.paiement_enum as enum ('especes', 'mtn_momo', 'orange_money');

create type public.langue_enum as enum ('fr', 'bassa', 'bamoun', 'pidgin');

comment on type public.langue_enum is
  'Langue lue par le TTS. fr = francais, pidgin = Cameroonian Pidgin English.';
