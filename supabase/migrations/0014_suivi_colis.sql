-- ============================================================================
-- MBOA BIO 237 - 0014 : le suivi de colis, lu par les trois roles
--
-- La cliente, le comptoir et le livreur suivent la meme marchandise sur la
-- route. Le suivi est un journal de bord : une ligne par commande et par
-- jalon, avec un horodatage et un auteur. Pas de flux GPS : une position en
-- temps reel exigerait un GPS actif sur un telephone a la batterie faible,
-- et un jalon honnete vaut mieux qu'une precision qui s'eteint en route.
--
-- Les cinq jalons, dans l'ordre du voyage :
--   panier_prepare  le comptoir a sorti et empaquete la marchandise
--   moto_partie     le livreur a charge et quitte le depot
--   en_approche     le livreur est proche, la cliente peut se preparer
--   arrive          la moto est devant la porte
--   remis           la cliente a confirme la reception
--
-- Quatre jalons sont poses automatiquement par un trigger quand le statut de
-- la commande change ; `en_approche` est le seul geste manuel, pose par le
-- livreur sur sa course ou par le comptoir qui relaie son appel.
--
-- Le livreur a desormais un compte (role `livreur`) rattache a sa fiche par
-- `livreurs.profil_id`. Il ne voit et ne pointe que SES courses : la RLS et
-- les RPC le verifient a chaque lecture, jamais l'app seule.
-- ============================================================================

begin;

create type public.jalon_enum as enum (
  'panier_prepare',
  'moto_partie',
  'en_approche',
  'arrive',
  'remis'
);

create table public.suivi_colis (
  id           uuid primary key default gen_random_uuid(),
  commande_id  uuid not null references public.commandes (id) on delete cascade,
  jalon        public.jalon_enum not null,
  horodatage   timestamptz not null default now(),
  auteur       text not null default 'admin',

  -- Pointer deux fois la meme etape ne cree pas de doublon : la timeline se
  -- lit comme un journal, pas comme un flux d'evenements a replay.
  constraint suivi_colis_unique unique (commande_id, jalon)
);

create index suivi_colis_commande_idx on public.suivi_colis (commande_id, horodatage);

-- ----------------------------------------------------------------------------
-- Qui a le droit de lire une course : la cliente, le comptoir, ou le livreur
-- auquel la course est affectee. Une seule fonction, reutilisee par la RLS et
-- par les RPC, pour que les trois portes disent la meme chose.
-- ----------------------------------------------------------------------------
create or replace function mboa.peut_lire_course(p_commande_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select mboa.est_admin()
      or exists (
        select 1 from public.commandes c
        where c.id = p_commande_id and c.consommateur_id = (select auth.uid())
      )
      or exists (
        select 1 from public.commandes c
        where c.id = p_commande_id and c.livreur_id = mboa.livreur_de_session()
      )
$$;

alter table public.suivi_colis enable row level security;

create policy suivi_lecture_parties
  on public.suivi_colis for select
  to authenticated
  using (mboa.peut_lire_course(commande_id));

-- Le comptoir pose tout ; le livreur pose les jalons de route de sa course.
create policy suivi_ecriture_parties
  on public.suivi_colis for insert
  to authenticated
  with check (
    mboa.est_admin()
    or exists (
      select 1 from public.commandes c
      where c.id = commande_id and c.livreur_id = mboa.livreur_de_session()
    )
  );

-- ----------------------------------------------------------------------------
-- Realtime : la timeline se rafraichit chez les trois roles quand un jalon
-- tombe. La RLS ci-dessus filtre deja ce que chaque abonné recoit.
-- ----------------------------------------------------------------------------
alter table public.suivi_colis replica identity full;

do $$
begin
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'suivi_colis'
  ) then
    alter publication supabase_realtime add table public.suivi_colis;
  end if;
end
$$;

-- ----------------------------------------------------------------------------
-- Pointer une etape. Le livreur ne peut poser que les jalons de route de sa
-- propre course ; le comptoir peut tout reprendre. L'ordre est garde ici en
-- plus du trigger, pour qu'un jalon ne precede pas celui qui le rend possible.
-- ----------------------------------------------------------------------------
create or replace function mboa.pointer_suivi(
  p_commande_id uuid,
  p_jalon public.jalon_enum,
  p_auteur text default 'admin'
)
returns public.suivi_colis
language plpgsql
security definer
set search_path = public
as $$
declare
  v_ligne   public.suivi_colis;
  v_statut  public.statut_enum;
  v_livreur uuid;
begin
  if not mboa.peut_lire_course(p_commande_id) then
    raise exception 'acces refuse a cette course' using errcode = '42501';
  end if;

  select statut_enum, livreur_id into v_statut, v_livreur
  from public.commandes where id = p_commande_id;

  if not found then
    raise exception 'commande introuvable';
  end if;

  -- Un livreur ne pointe que sa course, et seulement les jalons de route.
  if not mboa.est_admin() then
    if v_livreur is null or v_livreur <> mboa.livreur_de_session() then
      raise exception 'cette course n''est pas la votre' using errcode = '42501';
    end if;
    if p_jalon not in ('moto_partie', 'en_approche') then
      raise exception 'ce jalon appartient au comptoir ou a la cliente' using errcode = '42501';
    end if;
  end if;

  if p_jalon = 'en_approche' and v_statut not in ('en_livraison', 'livree') then
    raise exception 'la moto n''est pas encore en route';
  end if;
  if p_jalon = 'moto_partie' and v_statut not in ('validee_admin', 'en_livraison', 'livree') then
    raise exception 'le devis n''est pas encore valide';
  end if;

  insert into public.suivi_colis (commande_id, jalon, auteur)
  values (p_commande_id, p_jalon, coalesce(nullif(p_auteur, ''), 'admin'))
  on conflict (commande_id, jalon) do nothing
  returning * into v_ligne;

  if v_ligne is null then
    select * into v_ligne from public.suivi_colis
    where commande_id = p_commande_id and jalon = p_jalon;
  end if;

  return v_ligne;
end;
$$;

-- ----------------------------------------------------------------------------
-- Le trigger qui pose les jalons automatiques quand le statut avance. Il
-- n'appelle aucune fonction de notification : la publication realtime ci-dessus
-- suffit, et appeler un trigger hors de son contexte serait une erreur.
-- ----------------------------------------------------------------------------
create or replace function mboa.synchro_suivi_colis()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_jalon public.jalon_enum;
begin
  if new.statut_enum is distinct from old.statut_enum then
    v_jalon := case new.statut_enum
      when 'validee_admin' then 'panier_prepare'::public.jalon_enum
      when 'en_livraison'  then 'moto_partie'::public.jalon_enum
      when 'livree'        then 'arrive'::public.jalon_enum
      when 'recue'         then 'remis'::public.jalon_enum
      else null
    end;

    if v_jalon is not null then
      insert into public.suivi_colis (commande_id, jalon, auteur)
      values (new.id, v_jalon, 'auto')
      on conflict (commande_id, jalon) do nothing;
    end if;
  end if;

  return new;
end;
$$;

drop trigger if exists synchro_suivi_colis on public.commandes;
create trigger synchro_suivi_colis
  after update of statut_enum on public.commandes
  for each row execute function mboa.synchro_suivi_colis();

-- ----------------------------------------------------------------------------
-- Lire la timeline d'une course, pour les trois roles.
-- ----------------------------------------------------------------------------
create or replace function mboa.suivi_commande(p_commande_id uuid)
returns table (jalon public.jalon_enum, horodatage timestamptz, auteur text)
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  if not mboa.peut_lire_course(p_commande_id) then
    raise exception 'acces refuse a cette course' using errcode = '42501';
  end if;

  return query
    select s.jalon, s.horodatage, s.auteur
    from public.suivi_colis s
    where s.commande_id = p_commande_id
    order by s.horodatage asc;
end;
$$;

-- ----------------------------------------------------------------------------
-- Les courses du livreur connecte : ce qu'il porte aujourd'hui, et le numero
-- de la personne a qui il remet. Jamais les couts d'achat du comptoir.
--
-- Le numero sort uniquement pour une course affectee a ce livreur, et
-- uniquement tant qu'elle vit : c'est l'equivalent de `contact_livreur` cote
-- cliente, et sans lui un moto ne trouve pas une concession au fond d'un
-- quartier.
-- ----------------------------------------------------------------------------
create or replace function mboa.mes_courses()
returns table (
  id uuid, statut_enum public.statut_enum, montant_total integer,
  created_at timestamptz, livree_le timestamptz,
  cliente_nom text, cliente_village text, cliente_tel text, produits jsonb
)
language sql
stable
security definer
set search_path = public
as $$
  select c.id, c.statut_enum, c.montant_total, c.created_at, c.livree_le,
         p.nom, p.village, p.telephone_237,
         (select coalesce(jsonb_agg(l - 'cout_achat'), '[]'::jsonb)
            from jsonb_array_elements(c.produits) as l)
  from public.commandes c
  join public.profiles p on p.id = c.consommateur_id
  where c.livreur_id = mboa.livreur_de_session()
    and c.statut_enum in ('validee_admin', 'en_livraison', 'livree')
  order by c.created_at asc
$$;

grant execute on function mboa.pointer_suivi(uuid, public.jalon_enum, text) to authenticated;
grant execute on function mboa.suivi_commande(uuid) to authenticated;
grant execute on function mboa.mes_courses() to authenticated;

commit;
