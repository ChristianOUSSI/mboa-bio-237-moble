-- ============================================================================
-- MBOA BIO 237 - 0015 : la porte d'entree des applications
--
-- Toute la logique vit dans le schema `mboa` : c'est la que sont les verrous,
-- les controles de role et les calculs de stock. PostgREST, lui, n'expose que
-- `public`. Sans ce fichier, l'app compile et chaque appel echoue en 404 :
-- les fonctions existent, mais aucune porte ne s'ouvre sur elles.
--
-- Chaque enveloppe ci-dessous est volontairement mince. Elle ne verifie rien
-- et n'ajoute rien : la securite reste dans `mboa`, ou elle est ecrite une
-- seule fois. Une enveloppe `security invoker` ne peut pas contourner la RLS
-- ni les controles de `security definer` qu'elle appelle.
--
-- Seul `authenticated` recoit l'autorisation d'execution. `anon` n'a aucune
-- de ces portes : pas de devis, pas de course, pas de numero.
-- ============================================================================

begin;

-- ----------------------------------------------------------------------------
-- Le marche et le stock
-- ----------------------------------------------------------------------------
create or replace function public.parts_livrables(p_slug text)
returns numeric
language sql
security invoker
set search_path = public
as $$ select mboa.parts_livrables(p_slug) $$;

create or replace function public.creer_pack(
  p_nom text,
  p_categorie public.categorie_enum,
  p_composants jsonb,
  p_prix integer,
  p_photo_url text,
  p_audio_url text default null
)
returns public.produits
language sql
security invoker
set search_path = public
as $$ select mboa.creer_pack(p_nom, p_categorie, p_composants, p_prix, p_photo_url, p_audio_url) $$;

create or replace function public.modifier_pack(
  p_slug text,
  p_composants jsonb,
  p_prix integer,
  p_photo_url text default null,
  p_audio_url text default null
)
returns public.produits
language sql
security invoker
set search_path = public
as $$ select mboa.modifier_pack(p_slug, p_composants, p_prix, p_photo_url, p_audio_url) $$;

create or replace function public.recalculer_packs()
returns void
language sql
security invoker
set search_path = public
as $$ select mboa.recalculer_packs() $$;

-- ----------------------------------------------------------------------------
-- L'achat au producteur
-- ----------------------------------------------------------------------------
create or replace function public.proposer_achat(
  p_nom text,
  p_categorie public.categorie_enum,
  p_quantite numeric,
  p_unite public.unite_enum,
  p_prix_demande integer,
  p_photo_url text,
  p_audio_url text default null
)
returns public.achats
language sql
security invoker
set search_path = public
as $$ select mboa.proposer_achat(p_nom, p_categorie, p_quantite, p_unite, p_prix_demande, p_photo_url, p_audio_url) $$;

create or replace function public.valider_achat(
  p_achat_id uuid,
  p_prix_achat integer,
  p_prix_revente integer default null
)
returns public.achats
language sql
security invoker
set search_path = public
as $$ select mboa.valider_achat(p_achat_id, p_prix_achat, p_prix_revente) $$;

create or replace function public.payer_achat(p_achat_id uuid)
returns public.achats
language sql
security invoker
set search_path = public
as $$ select mboa.payer_achat(p_achat_id) $$;

create or replace function public.refuser_achat(
  p_achat_id uuid,
  p_motif text default null,
  p_motif_audio_url text default null,
  p_litige boolean default false
)
returns public.achats
language sql
security invoker
set search_path = public
as $$ select mboa.refuser_achat(p_achat_id, p_motif, p_motif_audio_url, p_litige) $$;

create or replace function public.mes_achats()
returns setof public.achats
language sql
security invoker
set search_path = public
as $$ select * from mboa.mes_achats() $$;

create or replace function public.mes_gains()
returns table (paye integer, en_attente integer)
language sql
security invoker
set search_path = public
as $$ select * from mboa.mes_gains() $$;

-- ----------------------------------------------------------------------------
-- Le devis de la cliente
-- ----------------------------------------------------------------------------
create or replace function public.creer_devis(
  p_produits jsonb,
  p_moto boolean default true
)
returns public.commandes
language sql
security invoker
set search_path = public
as $$ select mboa.creer_devis(p_produits, p_moto) $$;

create or replace function public.valider_devis(p_commande_id uuid)
returns public.commandes
language sql
security invoker
set search_path = public
as $$ select mboa.valider_devis(p_commande_id) $$;

create or replace function public.annuler_devis(
  p_commande_id uuid,
  p_motif text default null,
  p_audio_url text default null
)
returns public.commandes
language sql
security invoker
set search_path = public
as $$ select mboa.annuler_devis(p_commande_id, p_motif, p_audio_url) $$;

create or replace function public.pointer_livraison(
  p_commande_id uuid,
  p_montant_livre integer
)
returns public.commandes
language sql
security invoker
set search_path = public
as $$ select mboa.pointer_livraison(p_commande_id, p_montant_livre) $$;

create or replace function public.confirmer_reception(
  p_commande_id uuid,
  p_bon boolean,
  p_motif text default null,
  p_audio_url text default null
)
returns public.commandes
language sql
security invoker
set search_path = public
as $$ select mboa.confirmer_reception(p_commande_id, p_bon, p_motif, p_audio_url) $$;

create or replace function public.fermer_sur_delai(p_commande_id uuid)
returns public.commandes
language sql
security invoker
set search_path = public
as $$ select mboa.fermer_sur_delai(p_commande_id) $$;

create or replace function public.devis_sans_confirmation(p_delai interval default '12 hours')
returns setof public.commandes
language sql
security invoker
set search_path = public
as $$ select * from mboa.devis_sans_confirmation(p_delai) $$;

create or replace function public.marge_devis(p_commande_id uuid)
returns integer
language sql
security invoker
set search_path = public
as $$ select mboa.marge_devis(p_commande_id) $$;

create or replace function public.liste_par_code(p_code text)
returns public.listes
language sql
security invoker
set search_path = public
as $$ select mboa.liste_par_code(p_code) $$;

-- ----------------------------------------------------------------------------
-- Le devis tel que la cliente a le droit de le lire
--
-- La RLS de `commandes` rend ses propres lignes a la cliente, mais une ligne
-- porte deux choses qu'elle ne doit pas voir : `cout_achat`, et le cout
-- d'achat de chaque ligne a l'interieur du JSONB `produits`. Une policy ne
-- sait pas masquer une colonne. Cette vue, elle, projette : le JSON perd sa
-- cle `cout_achat` ligne par ligne, le cout total ne sort pas, et le livreur
-- arrive en objet imbrique pour que l'app n'ait pas besoin de joindre une
-- table dont le numero est protege par privilege de colonne.
--
-- `security_invoker = true` : la RLS de `commandes` s'applique a l'appelant.
-- Le comptoir garde `commandes` en direct, avec ses couts, pour son ecran de
-- validation et son bilan.
-- ----------------------------------------------------------------------------
create or replace view public.commandes_clientes
with (security_invoker = true) as
select
  c.id,
  c.consommateur_id,
  (
    select coalesce(jsonb_agg(l - 'cout_achat'), '[]'::jsonb)
    from jsonb_array_elements(c.produits) as l
  ) as produits,
  c.statut_enum,
  c.montant_total,
  c.montant_livre,
  c.paiement,
  c.paiement_ref,
  c.livraison_moto,
  c.livreur_id,
  c.stock_sorti,
  c.photo_livraison_url,
  c.signature_url,
  c.livree_le,
  c.recue_le,
  c.satisfaction,
  c.satisfaction_motif,
  c.satisfaction_audio,
  c.clos,
  c.annule_le,
  c.motif_annulation,
  c.created_at,
  c.updated_at,
  case
    when l.id is null then null
    else jsonb_build_object(
      'nom', l.nom,
      'photo', l.photo,
      'moto', l.moto,
      'plaque', l.plaque,
      'tarif_course', l.tarif_course
    )
  end as livreur
from public.commandes c
left join public.livreurs l on l.id = c.livreur_id;

comment on view public.commandes_clientes is
  'Le devis sans cout d''achat, ni ligne par ligne ni en total. La cliente et le livreur lisent cette vue, le comptoir lit la table.';

grant select on public.commandes_clientes to authenticated;

-- ----------------------------------------------------------------------------
-- Les livreurs et les courses
-- ----------------------------------------------------------------------------
create or replace function public.contact_comptoir()
returns text
language sql
security invoker
set search_path = public
as $$ select mboa.contact_comptoir() $$;

create or replace function public.contact_livreur(p_commande_id uuid)
returns text
language sql
security invoker
set search_path = public
as $$ select mboa.contact_livreur(p_commande_id) $$;

create or replace function public.affecter_livreur(
  p_commande_id uuid,
  p_livreur_id uuid
)
returns public.commandes
language sql
security invoker
set search_path = public
as $$ select mboa.affecter_livreur(p_commande_id, p_livreur_id) $$;

create or replace function public.pointer_suivi(
  p_commande_id uuid,
  p_jalon public.jalon_enum,
  p_auteur text default 'admin'
)
returns public.suivi_colis
language sql
security invoker
set search_path = public
as $$ select mboa.pointer_suivi(p_commande_id, p_jalon, p_auteur) $$;

create or replace function public.suivi_commande(p_commande_id uuid)
returns table (jalon public.jalon_enum, horodatage timestamptz, auteur text)
language sql
security invoker
set search_path = public
as $$ select * from mboa.suivi_commande(p_commande_id) $$;

create or replace function public.mes_courses()
returns table (
  id uuid, statut_enum public.statut_enum, montant_total integer,
  created_at timestamptz, livree_le timestamptz,
  cliente_nom text, cliente_village text, cliente_tel text, produits jsonb
)
language sql
security invoker
set search_path = public
as $$ select * from mboa.mes_courses() $$;

-- ----------------------------------------------------------------------------
-- Les portes : authenticated seulement.
-- ----------------------------------------------------------------------------
do $$
declare
  v_porte text;
begin
  foreach v_porte in array array[
    'public.parts_livrables(text)',
    'public.creer_pack(text, public.categorie_enum, jsonb, integer, text, text)',
    'public.modifier_pack(text, jsonb, integer, text, text)',
    'public.recalculer_packs()',
    'public.proposer_achat(text, public.categorie_enum, numeric, public.unite_enum, integer, text, text)',
    'public.valider_achat(uuid, integer, integer)',
    'public.payer_achat(uuid)',
    'public.refuser_achat(uuid, text, text, boolean)',
    'public.mes_achats()',
    'public.mes_gains()',
    'public.creer_devis(jsonb, boolean)',
    'public.valider_devis(uuid)',
    'public.annuler_devis(uuid, text, text)',
    'public.pointer_livraison(uuid, integer)',
    'public.confirmer_reception(uuid, boolean, text, text)',
    'public.fermer_sur_delai(uuid)',
    'public.devis_sans_confirmation(interval)',
    'public.marge_devis(uuid)',
    'public.liste_par_code(text)',
    'public.contact_comptoir()',
    'public.contact_livreur(uuid)',
    'public.affecter_livreur(uuid, uuid)',
    'public.pointer_suivi(uuid, public.jalon_enum, text)',
    'public.suivi_commande(uuid)',
    'public.mes_courses()'
  ]
  loop
    execute format('revoke all on function %s from public, anon', v_porte);
    execute format('grant execute on function %s to authenticated', v_porte);
  end loop;
end
$$;

commit;
