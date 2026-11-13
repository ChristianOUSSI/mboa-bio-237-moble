-- ============================================================================
-- MBOA BIO 237 - 0005 : Row Level Security
--
-- Le principe qui organize ce fichier : ce que la cliente ne doit pas voir
-- n'est pas « filtre par l'app », c'est absent de ce qu'elle peut lire. Une
-- colonne sensible ne se cache pas en la masquant a l'ecran, elle se cache en
-- n'entrant jamais dans une requete que le role anonyme ou le role cliente
-- peut formuler.
--
-- Trois objets protègent le back-office :
--   * `public.vitrine`  : la vue lue par l'app cliente. Pas de prix d'achat,
--     pas de producteur, pas de fiche inactive.
--   * `achats`          : lise par l'agriculteur qui l'a propose, et par
--     l'admin. Personne d'autre ne peut en sélectionner une ligne.
--   * `profiles`        : la cliente ne lit plus les profils des
--     producteurs. Le nom d'un village ne prouve rien, et un visage sur une
--     tuile n'est pas une garantie sanitaire.
--
-- Toutes les policies qui ont besoin de relire la propre table visée passent
-- par une fonction SECURITY DEFINER du schema mboa : sans cela, la policy de
-- profiles se rappelle elle-meme et Postgres refuse la recursion.
-- ============================================================================

alter table public.profiles   enable row level security;
alter table public.produits   enable row level security;
alter table public.achats     enable row level security;
alter table public.commandes  enable row level security;
alter table public.categories enable row level security;
alter table public.catalogue  enable row level security;

-- ----------------------------------------------------------------------------
-- 1. PROFILES
-- ----------------------------------------------------------------------------
create policy profiles_lecture_soi
  on public.profiles for select
  to authenticated
  using (id = (select auth.uid()) or mboa.est_admin());

-- Le trigger mboa.creer_profil() est SECURITY DEFINER : il ecrit le profil
-- avant que l'utilisateur ait quoi que ce soit en propre. Cette policy ne
-- couvre donc que la mise a jour du profil par son titulaire.
create policy profiles_ecriture_soi
  on public.profiles for update
  to authenticated
  using (id = (select auth.uid()) and mboa.est_admin() is not true)
  with check (id = (select auth.uid()));

create policy profiles_admin_tout
  on public.profiles for all
  to authenticated
  using (mboa.est_admin())
  with check (mboa.est_admin());

-- La policy ci-dessus dit a qui appartient la ligne, pas ce qu'on peut y
-- ecrire. Sans ce verrou, n'importe quel compte pouvait faire
-- `update profiles set role = 'admin'` sur sa propre ligne, et `est_admin()`
-- lui aurait repondu oui a la requete suivante. Une policy ne restreint pas
-- les colonnes ; un privilege, oui.
revoke update on public.profiles from authenticated;
grant update (nom, village, langue, photo_visage, latitude, longitude)
  on public.profiles to authenticated;

-- Le gel d'un compte (`actif`) et le changement de `role` restent donc au
-- SQL Editor du comptoir. Quand un ecran les demandera, ils passeront par une
-- RPC `security definer` gardee par `est_admin()`, pas par une colonne
-- ouverte.

-- Pas d'insertion directe : le profil nait du trigger d'inscription. Pas de
-- suppression : un compte se gele, il ne disparait pas (historique d'achats).

-- ----------------------------------------------------------------------------
-- 2. PRODUITS : le stock du comptoir
--
-- L'app cliente ne lit jamais cette table. Elle lit `public.vitrine`, plus
-- bas. Ici, seul l'admin ecrit, et le role authentifie lit pour connaitre
-- l'etat reel du stock dans l'app admin.
-- ----------------------------------------------------------------------------
create policy produits_admin_tout
  on public.produits for all
  to authenticated
  using (mboa.est_admin())
  with check (mboa.est_admin());

comment on policy produits_admin_tout on public.produits is
  'Aucune lecture cliente directe : le prix d''achat est dans cette table. La cliente passe par la vue vitrine.';

-- ----------------------------------------------------------------------------
-- LA VITRINE : la seule surface de produits lisible par une cliente.
--
-- `security_invoker = false` est volontaire et n'est pas une faille : la vue
-- ne selectionne que des colonnes sans valeur marchande pour un tiers, et
-- elle est definie par le proprietaire de la table. Ce qu'elle expose est un
-- choix, pas une fuite : slug, nom, categorie, unite, quantite, prix de
-- revente, photo. Ce qu'elle tait est tout le reste.
-- ----------------------------------------------------------------------------
create or replace view public.vitrine
with (security_invoker = false) as
select
  p.id,
  p.slug,
  p.nom,
  p.categorie,
  p.unite,
  p.quantite,
  p.prix,
  coalesce(p.photo_filigranee, p.photo_reelle) as photo,
  p.audio_description_url,
  p.perissable
from public.produits p
where p.actif
  and p.quantite > 0
  and p.prix > 1;

comment on view public.vitrine is
  'La marchandise visible par une cliente. Le prix d''achat, le producteur et les fiches gelées n''entrent pas dans cette vue.';

-- Pas de `create policy` sur une vue : Postgres refuse la RLS sur autre
-- chose qu'une table, et la migration entiere s'arretait ici. La vue porte
-- deja son propre filtre dans son `where`, et le `grant` ci-dessus est la
-- seule porte : ce qui n'est pas selectionne par la vue n'existe pas pour
-- l'appelant.
grant select on public.vitrine to anon, authenticated;

-- ----------------------------------------------------------------------------
-- 3. ACHATS : la moitie cachee du commerce
-- ----------------------------------------------------------------------------
create policy achats_lecture_partie
  on public.achats for select
  to authenticated
  using (fournisseur_id = (select auth.uid()) or mboa.est_admin());

-- Un agriculteur cree ses propres propositions, et ne peut les modifier que
-- tant qu'elles ne sont pas signees. La signature, le payement et le refus
-- appartiennent a l'admin, par RPC SECURITY DEFINER.
create policy achats_proposition
  on public.achats for insert
  to authenticated
  with check (
    fournisseur_id = (select auth.uid())
    and statut = 'propose'
  );

create policy achats_retrait_avant_signature
  on public.achats for update
  to authenticated
  using (
    fournisseur_id = (select auth.uid())
    and statut = 'propose'
    and mboa.est_admin() is not true
  )
  with check (statut in ('propose', 'annule'));

-- Rien ne se supprime : une marchandise refusee laisse une trace, sinon le
-- comptoir ne peut plus expliquer a un agriculteur pourquoi on ne lui a rien
-- achete la saison derniere.

create policy achats_admin_tout
  on public.achats for all
  to authenticated
  using (mboa.est_admin())
  with check (mboa.est_admin());

-- ----------------------------------------------------------------------------
-- 4. COMMANDES (devis)
-- ----------------------------------------------------------------------------
create policy devis_lecture_partie
  on public.commandes for select
  to authenticated
  using (consommateur_id = (select auth.uid()) or mboa.est_admin());

-- La cliente ne touche jamais au statut ni au montant : tout passe par
-- mboa.creer_devis (0010), qui verrouille, decrete et reserve le stock.
create policy devis_ecriture_interdite
  on public.commandes for update
  to authenticated
  using (false)
  with check (false);

create policy devis_admin_tout
  on public.commandes for all
  to authenticated
  using (mboa.est_admin())
  with check (mboa.est_admin());

-- ----------------------------------------------------------------------------
-- 5. CATEGORIES et CATALOGUE : lecture publique, ecriture comptoir
--
-- Un produit du catalogue n'est pas encore du stock : la cliente lit la
-- vitrine, pas le catalogue. Le catalogue sert a l'app admin (prix de
-- tendance, mesure habituelle) et a la feuille de proposition de
-- l'agriculteur, qui choisit une categorie a pictogramme au lieu d'ecrire.
-- ----------------------------------------------------------------------------
create policy categories_lecture_tous
  on public.categories for select
  to anon, authenticated
  using (true);

create policy categories_ecriture_admin
  on public.categories for all
  to authenticated
  using (mboa.est_admin())
  with check (mboa.est_admin());

create policy catalogue_lecture_tous
  on public.catalogue for select
  to anon, authenticated
  using (true);

create policy catalogue_ecriture_admin
  on public.catalogue for all
  to authenticated
  using (mboa.est_admin())
  with check (mboa.est_admin());

-- ----------------------------------------------------------------------------
-- 6. Les fonctions du schema mboa ne sont pas appelables du client.
--
-- `proposer_achat` et les RPC de devis (0010) sont accordees explicitement
-- plus bas ; tout le reste reste dans le schema prive. Sans ce retract, un
-- role authenticated pourrait appeler mboa.valider_achat directement.
-- ----------------------------------------------------------------------------
revoke all on all functions in schema mboa from public;
revoke all on all functions in schema mboa from anon;
revoke all on all functions in schema mboa from authenticated;

grant execute on function mboa.proposer_achat(text, public.categorie_enum, numeric, public.unite_enum, integer, text, text) to authenticated;
grant execute on function mboa.mes_achats() to authenticated;
grant execute on function mboa.mes_gains() to authenticated;
grant execute on function mboa.contact_comptoir() to authenticated;

comment on schema mboa is
  'Fonctions internes. Rien n''est exécutable par un client sauf ce qui est accordé ligne à ligne ci-dessus.';
