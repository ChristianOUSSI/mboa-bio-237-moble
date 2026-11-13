-- ============================================================================
-- MBOA BIO 237 - 0016 : le fichier des fournisseurs
--
-- Jusqu'ici, un fournisseur n'existait que par son compte : `achats.fournisseur_id`
-- pointait sur `profiles`, et il fallait qu'il s'inscrive pour que le comptoir
-- puisse lui acheter quelque chose. Ce n'est pas comme cela qu'un depot
-- travaille. Le comptoir connait des producteurs qui n'ont pas de smartphone,
-- qui vendent une fois par saison, et dont le nom suffit.
--
-- La fiche devient donc la reference. Elle vit sans compte, l'admin la cree au
-- comptoir, et l'achat peut se faire sur la fiche. Le jour ou la personne
-- installe l'application avec le meme numero, la fiche se rattache toute seule
-- a son profil : deux ecritures ne creent plus deux fournisseurs.
--
-- Ce que la cliente ne voit toujours pas : ni le nom du producteur, ni ce que
-- le comptoir lui a paye. Le fichier est un outil de back-office.
-- ============================================================================

begin;

-- ----------------------------------------------------------------------------
-- 1. LA FICHE
--
-- `profil_id` reste vide tant que la personne n'a pas de compte. `id` est
-- l'identifiant que portent les achats, pas celui du profil : une fiche creee
-- au comptoir garde son identite meme apres le rattachement.
--
-- La production est en deux morceaux : la case (huit valeurs, comme partout)
-- et le mot libre du marche. La case peut rester vide sur une fiche creee par
-- l'inscription, parce que le formulaire d'inscription ne demande pas encore
-- la production. L'admin la complete en ouvrant la fiche, et l'ecran le dit
-- au lieu d'inventer une categorie.
-- ----------------------------------------------------------------------------
create table public.fournisseurs (
  id                   uuid primary key default gen_random_uuid(),

  profil_id            uuid unique references public.profiles (id) on delete set null,

  nom                  text    not null,
  telephone_237        text    not null unique,
  village              text    not null default 'INCONNU',
  photo                text,

  production_categorie public.categorie_enum,
  production_libre     text,

  -- L'unite habituelle du producteur. C'est elle que l'ecran d'achat propose
  -- d'abord : le macabo se compte en boules, l'arachide en litres.
  unite                public.unite_enum not null default 'kg',

  actif                boolean not null default true,

  created_at           timestamptz not null default now(),
  updated_at           timestamptz not null default now(),

  constraint fournisseurs_nom_court      check (char_length(nom) between 2 and 60),
  constraint fournisseurs_village_court  check (char_length(village) between 2 and 60),
  constraint fournisseurs_telephone_form check (telephone_237 ~ '^\+237[26][0-9]{8}$'),
  constraint fournisseurs_production_courte
    check (production_libre is null or char_length(production_libre) between 2 and 120)
);

create index fournisseurs_nom_idx on public.fournisseurs (nom);
create index fournisseurs_actif_idx on public.fournisseurs (actif);

comment on table public.fournisseurs is
  'Le fichier des producteurs du comptoir. Une fiche peut exister sans compte, et se rattache au profil le jour ou le numero s''inscrit.';
comment on column public.fournisseurs.profil_id is
  'Compte rattache, optionnel. Un producteur sans smartphone garde sa fiche et vend quand meme.';
comment on column public.fournisseurs.production_categorie is
  'La case de production, vide tant que l''admin ne l''a pas choisie. L''ecran ecrit « a preciser » plutot que de deviner.';

create trigger fournisseurs_touch before update on public.fournisseurs
  for each row execute function mboa.touche_updated_at();

-- ----------------------------------------------------------------------------
-- 2. LES FICHES QUI EXISTENT DEJA
--
-- Chaque profil fournisseur, et chaque profil deja cite par un achat, recoit
-- une fiche avec `id = profil.id`. C'est volontaire : tous les UUID d'achats
-- deja en base restent valides quand la cle etrangere change de cible, y
-- compris dans le jeu de demonstration.
-- ----------------------------------------------------------------------------
insert into public.fournisseurs
  (id, profil_id, nom, telephone_237, village, photo, unite, actif, created_at, updated_at)
select
  p.id, p.id, p.nom, p.telephone_237, p.village, p.photo_visage,
  'kg', p.actif, p.created_at, p.updated_at
from public.profiles p
where p.role = 'fournisseur'
   or exists (select 1 from public.achats a where a.fournisseur_id = p.id)
on conflict (id) do nothing;

-- ----------------------------------------------------------------------------
-- 3. L'ACHAT PORTE UNE FICHE, PLUS UN COMPTE
-- ----------------------------------------------------------------------------
alter table public.achats drop constraint if exists achats_fournisseur_id_fkey;
alter table public.achats add constraint achats_fournisseur_id_fkey
  foreign key (fournisseur_id) references public.fournisseurs (id) on delete restrict;

-- Qui a saisi la proposition. Renseigne par l'agriculteur lui-meme, ou par le
-- comptoir quand il achete au nom d'une fiche sans compte. Sert a expliquer
-- une ligne plus tard, pas a decider quoi que ce soit.
alter table public.achats
  add column if not exists saisi_par uuid references public.profiles (id) on delete set null;

comment on column public.achats.fournisseur_id is
  'La fiche du producteur. Elle peut exister sans compte : le comptoir achete chez des gens qui n''ont pas d''application.';
comment on column public.achats.saisi_par is
  'Le compte qui a tape la proposition. L''agriculteur, ou l''admin quand il achete pour une fiche sans compte.';

-- ----------------------------------------------------------------------------
-- 4. LE RATTACHEMENT AUTOMATIQUE
--
-- Un numero de telephone est deja unique chez les profils. Quand un profil
-- fournisseur apparait, la fiche qui porte ce numero se rattache a lui. Si
-- aucune fiche n'existe, elle est creee avec l'identifiant du profil, ce qui
-- garde le cache hors ligne du telephone coherent.
--
-- La fiche reste la source pour la production et l'unite : ce sont des
-- decisions du comptoir. Le profil reste la source pour le nom et le village.
-- ----------------------------------------------------------------------------
create or replace function mboa.lier_fiche_fournisseur()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_fiche public.fournisseurs;
begin
  if new.role <> 'fournisseur' then
    return new;
  end if;

  select * into v_fiche
  from public.fournisseurs
  where telephone_237 = new.telephone_237
  for update;

  if found then
    update public.fournisseurs
       set profil_id = new.id,
           nom       = new.nom,
           village   = new.village,
           photo     = coalesce(photo, new.photo_visage)
     where id = v_fiche.id;
    return new;
  end if;

  insert into public.fournisseurs
    (id, profil_id, nom, telephone_237, village, photo, unite, actif)
  values
    (new.id, new.id, new.nom, new.telephone_237, new.village,
     new.photo_visage, 'kg', new.actif);

  return new;
end;
$$;

drop trigger if exists profiles_fiche_fournisseur on public.profiles;
create trigger profiles_fiche_fournisseur
  after insert or update of role, telephone_237, nom, village, photo_visage
  on public.profiles
  for each row execute function mboa.lier_fiche_fournisseur();

comment on function mboa.lier_fiche_fournisseur() is
  'Un fournisseur qui installe l''app retrouve sa fiche par son numero, au lieu d''en creer une deuxieme.';

-- ----------------------------------------------------------------------------
-- 5. LA FICHE DU COMPTE CONNECTE
-- ----------------------------------------------------------------------------
create or replace function mboa.ma_fiche_fournisseur()
returns uuid
language sql
stable
security definer
set search_path = public
as $$
  select f.id
  from public.fournisseurs f
  where f.profil_id = (select auth.uid())
  limit 1
$$;

comment on function mboa.ma_fiche_fournisseur() is
  'La fiche du compte connecte. Sert aux policies d''achats et aux RPC du producteur, sans relire fournisseurs en recursion.';

-- ----------------------------------------------------------------------------
-- 6. PROPOSER UN ACHAT
--
-- La saisie commune est extraite pour que l'agriculteur et le comptoir passent
-- exactement les memes controles. Seule la porte d'entree change.
-- ----------------------------------------------------------------------------
create or replace function mboa.creer_proposition(
  p_fournisseur_id uuid,
  p_saisi_par uuid,
  p_nom text,
  p_categorie public.categorie_enum,
  p_quantite numeric,
  p_unite public.unite_enum,
  p_prix_demande integer,
  p_photo_url text,
  p_audio_url text
)
returns public.achats
language plpgsql
security definer
set search_path = public
as $$
declare
  v_slug  text;
  v_achat public.achats;
begin
  if char_length(trim(p_nom)) < 2 then
    raise exception 'la marchandise doit avoir un nom';
  end if;

  v_slug := mboa.slugifier(p_nom);
  if v_slug is null then
    raise exception 'ce nom ne peut pas devenir une cle de stock';
  end if;

  if p_quantite is null or p_quantite <= 0 then
    raise exception 'quantite invalide';
  end if;
  if p_prix_demande is null or p_prix_demande < 1 or p_prix_demande > 1000000 then
    raise exception 'prix demande invalide';
  end if;
  if p_photo_url is null or p_photo_url = '' then
    raise exception 'une proposition sans photo de la marchandise n''est pas une proposition';
  end if;

  insert into public.achats
    (fournisseur_id, saisi_par, slug, nom, categorie, unite, quantite,
     prix_demande, photo_url, audio_url, statut)
  values
    (p_fournisseur_id, p_saisi_par, v_slug, trim(p_nom), p_categorie, p_unite,
     p_quantite, p_prix_demande, p_photo_url, p_audio_url, 'propose')
  returning * into v_achat;

  return v_achat;
end;
$$;

create or replace function mboa.proposer_achat(
  p_nom text,
  p_categorie public.categorie_enum,
  p_quantite numeric,
  p_unite public.unite_enum,
  p_prix_demande integer,
  p_photo_url text,
  p_audio_url text default null
)
returns public.achats
language plpgsql
security definer
set search_path = public
as $$
declare
  v_fiche uuid := mboa.ma_fiche_fournisseur();
begin
  if not mboa.est_fournisseur() then
    raise exception 'seul un agriculteur peut proposer une marchandise' using errcode = '42501';
  end if;

  if v_fiche is null then
    raise exception 'ce compte n''a pas de fiche fournisseur' using errcode = '42501';
  end if;

  if not exists (select 1 from public.fournisseurs where id = v_fiche and actif) then
    raise exception 'cette fiche fournisseur est suspendue' using errcode = '42501';
  end if;

  return mboa.creer_proposition(
    v_fiche, (select auth.uid()), p_nom, p_categorie, p_quantite,
    p_unite, p_prix_demande, p_photo_url, p_audio_url
  );
end;
$$;

comment on function mboa.proposer_achat is
  'La porte d''entree d''un agriculteur : il dicte ce qu''il a, l''admin decide. Rien n''est visible aux clientes avant signature.';

-- Le comptoir achete au nom d'une fiche. C'est le geste du depot qui recoit
-- une livraison d'un producteur sans smartphone : la marchandise est la,
-- l'admin la photographie et la saisit, et la fiche garde la trace.
create or replace function mboa.proposer_achat_pour(
  p_fournisseur_id uuid,
  p_nom text,
  p_categorie public.categorie_enum,
  p_quantite numeric,
  p_unite public.unite_enum,
  p_prix_demande integer,
  p_photo_url text,
  p_audio_url text default null
)
returns public.achats
language plpgsql
security definer
set search_path = public
as $$
begin
  if not mboa.est_admin() then
    raise exception 'seul le comptoir saisit un achat pour une fiche' using errcode = '42501';
  end if;

  if not exists (
    select 1 from public.fournisseurs
    where id = p_fournisseur_id and actif
  ) then
    raise exception 'fiche fournisseur inconnue ou suspendue';
  end if;

  return mboa.creer_proposition(
    p_fournisseur_id, (select auth.uid()), p_nom, p_categorie, p_quantite,
    p_unite, p_prix_demande, p_photo_url, p_audio_url
  );
end;
$$;

comment on function mboa.proposer_achat_pour is
  'Le comptoir saisit l''achat d''un producteur qui n''a pas d''application. Meme controle, meme file, meme signature.';

-- ----------------------------------------------------------------------------
-- 7. CE QUE L'AGRICULTEUR RELIT
-- ----------------------------------------------------------------------------
create or replace function mboa.mes_achats()
returns setof public.achats
language sql
stable
security definer
set search_path = public
as $$
  select a.*
  from public.achats a
  where a.fournisseur_id = mboa.ma_fiche_fournisseur()
  order by a.propose_le desc
$$;

create or replace function mboa.mes_gains()
returns table (paye integer, en_attente integer)
language sql
stable
security definer
set search_path = public
as $$
  select
    coalesce(sum(a.montant) filter (where a.statut = 'paye'), 0)::integer,
    coalesce(sum(a.montant) filter (where a.statut in ('valide', 'propose')), 0)::integer
  from public.achats a
  where a.fournisseur_id = mboa.ma_fiche_fournisseur();
$$;

-- ----------------------------------------------------------------------------
-- 8. LES POLICIES D'ACHATS
--
-- La policy ne compare plus l'identifiant du profil a `fournisseur_id` : elle
-- demande la fiche du compte. Une fiche sans compte n'a donc aucune lecture,
-- et l'admin garde la sienne.
-- ----------------------------------------------------------------------------
drop policy if exists achats_lecture_partie on public.achats;
create policy achats_lecture_partie
  on public.achats for select
  to authenticated
  using (
    fournisseur_id = mboa.ma_fiche_fournisseur()
    or mboa.est_admin()
  );

drop policy if exists achats_proposition on public.achats;
create policy achats_proposition
  on public.achats for insert
  to authenticated
  with check (
    fournisseur_id = mboa.ma_fiche_fournisseur()
    and statut = 'propose'
  );

drop policy if exists achats_retrait_avant_signature on public.achats;
create policy achats_retrait_avant_signature
  on public.achats for update
  to authenticated
  using (
    fournisseur_id = mboa.ma_fiche_fournisseur()
    and statut = 'propose'
    and mboa.est_admin() is not true
  )
  with check (statut in ('propose', 'annule'));

-- ----------------------------------------------------------------------------
-- 9. LE FICHIER LUI-MEME
--
-- L'admin lit et ecrit tout. Un fournisseur lit sa fiche, et seulement elle.
-- Aucune autre role n'a de ligne : la cliente ne connait pas le producteur,
-- et le livreur n'a rien a y faire.
-- ----------------------------------------------------------------------------
alter table public.fournisseurs enable row level security;

create policy fournisseurs_lecture_admin
  on public.fournisseurs for select
  to authenticated
  using (mboa.est_admin());

create policy fournisseurs_lecture_soi
  on public.fournisseurs for select
  to authenticated
  using (profil_id = (select auth.uid()));

create policy fournisseurs_ecriture_admin
  on public.fournisseurs for insert
  to authenticated
  with check (mboa.est_admin());

create policy fournisseurs_maj_admin
  on public.fournisseurs for update
  to authenticated
  using (mboa.est_admin())
  with check (mboa.est_admin());

-- Une fiche ne se supprime pas : des achats et de l'argent y sont rattaches.
create policy fournisseurs_aucune_suppression
  on public.fournisseurs for delete
  to authenticated
  using (false);

revoke all on public.fournisseurs from anon;
revoke all on public.fournisseurs from authenticated;
grant select, insert, update on public.fournisseurs to authenticated;

-- ----------------------------------------------------------------------------
-- 10. LES NOTIFICATIONS, A LA LISTE COMPLETE
--
-- Cette fonction remplace encore mboa.notifier() en entier. Deux changements :
--   * l'achat saisi par le comptoir ne notifie pas le comptoir lui-meme ;
--   * le destinataire d'une nouvelle d'achat est le profil de la fiche, pas
--     l'identifiant de la fiche. Une fiche sans compte ne recoit rien, et
--     c'est normal : elle n'a pas de telephone dans l'application.
-- ----------------------------------------------------------------------------
create or replace function mboa.notifier()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_dest uuid;
begin
  -- Un agriculteur qui propose attend une reponse. Quand l'admin saisit
  -- lui-meme l'achat, il n'a pas besoin qu'on le lui annonce.
  if tg_table_name::text = 'achats' and tg_op = 'INSERT' then
    if not mboa.est_admin() then
      insert into mboa.notifications (destinataire, type, objet_id, texte_voice)
        select p.id, 'achat_attend', new.id, 'Un agriculteur attend votre réponse'
        from public.profiles p
        where p.role = 'admin' and p.actif;
    end if;

  elsif tg_table_name::text = 'achats' and tg_op = 'UPDATE' then
    if new.statut <> old.statut then
      select f.profil_id into v_dest
      from public.fournisseurs f
      where f.id = new.fournisseur_id;

      if v_dest is not null then
        insert into mboa.notifications (destinataire, type, objet_id, texte_voice)
        values (
          v_dest,
          'achat_statut',
          new.id,
          case new.statut
            when 'valide'  then 'Le comptoir a acheté votre marchandise'
            when 'paye'    then 'Le comptoir vous a payé'
            when 'annule'  then 'Le comptoir n''a pas retenu votre marchandise'
            when 'litige'  then 'Un problème est signalé sur votre marchandise'
            else 'Nouvelle du comptoir'
          end
        );
      end if;
    end if;

  -- Le stock bouge : le comptoir doit le savoir, c'est sa marchandise.
  elsif tg_table_name::text = 'produits' and tg_op = 'UPDATE' then
    if new.quantite is distinct from old.quantite
       and new.quantite <= (mboa.parametre('rupture_alerte', '5'))::numeric then
      insert into mboa.notifications (destinataire, type, objet_id, texte_voice)
        select p.id, 'stock_faible', new.id,
               'Plus que ' || new.quantite || ' ' || new.unite || ' de ' || new.nom || ' au comptoir'
        from public.profiles p
        where p.role = 'admin' and p.actif;
    end if;

  elsif tg_table_name::text = 'commandes' and tg_op = 'INSERT' then
    insert into mboa.notifications (destinataire, type, objet_id, texte_voice)
      select p.id, 'devis_recu', new.id, 'Un devis vient d''arriver au comptoir'
      from public.profiles p
      where p.role = 'admin' and p.actif;

  elsif tg_table_name::text = 'commandes' and tg_op = 'UPDATE' then
    -- Une course qui change de mains : la cliente voit qui vient.
    if new.livreur_id is not null
       and new.livreur_id is distinct from old.livreur_id then
      insert into mboa.notifications (destinataire, type, objet_id, texte_voice)
      values (new.consommateur_id, 'course_affectee', new.id,
              'Votre panier est en route avec ' ||
              coalesce((select l.nom from public.livreurs l where l.id = new.livreur_id), 'une moto'));

    elsif new.statut_enum = 'livree' and old.statut_enum is distinct from 'livree' then
      insert into mboa.notifications (destinataire, type, objet_id, texte_voice)
      values (new.consommateur_id, 'livre', new.id,
              'Ta commande est arrivée. Tout est bon ?');

    elsif new.satisfaction is not null
          and old.satisfaction is distinct from new.satisfaction then
      insert into mboa.notifications (destinataire, type, objet_id, texte_voice)
        select p.id, 'satisfaction', new.id,
               case new.satisfaction
                 when 'bon'      then 'La cliente a accepté sa marchandise'
                 when 'probleme' then 'La cliente signale un problème'
                 else 'Réponse reçue'
               end
        from public.profiles p
        where p.role = 'admin' and p.actif;

    elsif new.statut_enum is distinct from old.statut_enum then
      insert into mboa.notifications (destinataire, type, objet_id, texte_voice)
      values (new.consommateur_id, 'devis_statut', new.id,
              case new.statut_enum
                when 'validee_admin' then 'Votre devis est validé, le stock est réservé'
                when 'en_livraison'  then 'La moto est en route'
                when 'recue'         then 'Commande fermée, merci'
                when 'annulee'       then 'Votre devis a été annulé'
                else 'Devis mis à jour'
              end);
    end if;

  elsif tg_table_name::text = 'listes' and tg_op = 'INSERT' then
    insert into mboa.notifications (destinataire, type, objet_id, texte_voice)
      select p.id, 'liste_recue', new.id, 'Une liste de marché est prête à être chiffrée'
      from public.profiles p
      where p.role = 'admin' and p.actif;
  end if;

  return coalesce(new, old);
end;
$$;

-- ----------------------------------------------------------------------------
-- 11. LE NUMERO DU LIVREUR, RENDU A L'ADMIN
--
-- La 0012 a retire le privilege de colonne sur `telephone_237` pour que le
-- numero ne sorte plus par un select. L'admin, lui, en a besoin pour rappeler
-- la moto depuis l'annuaire et pour preremplir la fiche. Il le lit donc par
-- une porte nommee, gardee par `est_admin()`.
-- ----------------------------------------------------------------------------
create or replace function mboa.telephone_livreur(p_livreur_id uuid)
returns text
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  if not mboa.est_admin() then
    raise exception 'seul le comptoir lit ce numero' using errcode = '42501';
  end if;

  return (select telephone_237 from public.livreurs where id = p_livreur_id);
end;
$$;

comment on function mboa.telephone_livreur is
  'Le numero d''un livreur pour le comptoir. La cliente garde contact_livreur, qui verifie la course.';

-- ----------------------------------------------------------------------------
-- 12. LES PORTES DU SCHEMA PUBLIC
-- ----------------------------------------------------------------------------
create or replace function public.proposer_achat_pour(
  p_fournisseur_id uuid,
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
as $$ select mboa.proposer_achat_pour(p_fournisseur_id, p_nom, p_categorie, p_quantite, p_unite, p_prix_demande, p_photo_url, p_audio_url) $$;

create or replace function public.telephone_livreur(p_livreur_id uuid)
returns text
language sql
security invoker
set search_path = public
as $$ select mboa.telephone_livreur(p_livreur_id) $$;

-- ----------------------------------------------------------------------------
-- 13. LES PRIVILEGES
--
-- Les fonctions creees dans cette migration sont executables par PUBLIC par
-- defaut en Postgres. On ferme, puis on ouvre les deux seules portes utiles.
-- ----------------------------------------------------------------------------
revoke all on function mboa.creer_proposition(uuid, uuid, text, public.categorie_enum, numeric, public.unite_enum, integer, text, text) from public, anon, authenticated;
revoke all on function mboa.lier_fiche_fournisseur() from public, anon, authenticated;
revoke all on function mboa.ma_fiche_fournisseur() from public, anon;
grant execute on function mboa.ma_fiche_fournisseur() to authenticated;
grant execute on function mboa.proposer_achat_pour(uuid, text, public.categorie_enum, numeric, public.unite_enum, integer, text, text) to authenticated;
grant execute on function mboa.telephone_livreur(uuid) to authenticated;

revoke all on function public.proposer_achat_pour(uuid, text, public.categorie_enum, numeric, public.unite_enum, integer, text, text) from public, anon;
grant execute on function public.proposer_achat_pour(uuid, text, public.categorie_enum, numeric, public.unite_enum, integer, text, text) to authenticated;

revoke all on function public.telephone_livreur(uuid) from public, anon;
grant execute on function public.telephone_livreur(uuid) to authenticated;

commit;
