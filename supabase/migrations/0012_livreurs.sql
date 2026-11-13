-- ============================================================================
-- MBOA BIO 237 - 0012 : les livreurs du comptoir
--
-- Le livreur est une ressource du comptoir et, depuis la 0014, un quatrieme
-- role d'application avec sa propre APK. L'admin enregistre la fiche et
-- l'affecte ; le livreur, lui, ne cree rien, ne valide rien, ne negocie rien.
-- Il lit ses courses et pousse un jalon. C'est le seul ecran de l'app dont le
-- contenu vient d'une RPC et non d'une table ouverte.
--
-- Ce que la mama doit pouvoir savoir avant d'ouvrir sa porte : qui arrive,
-- sur quelle moto, a quel numero. C'est tout l'objet de cette table, et c'est
-- le seul endroit ou le back-office du comptoir touche la cliente.
--
-- Depuis le modele du comptoir, la course part du depot MBOA et non du
-- village : un panier melange desormais le manioc de Mbouda et la chevre de
-- Fee, et une seule moto le porte.
-- ============================================================================

begin;

create table public.livreurs (
  id             uuid primary key default gen_random_uuid(),

  -- Lie au compte quand le livreur a aussi une app, jamais obligatoire :
  -- un bayam-sellam du quartier n'a pas de smartphone.
  profil_id      uuid references public.profiles (id) on delete set null,

  nom            text    not null,

  -- Unique : deux motos avec le meme numero, c'est une affectation impossible.
  telephone_237  text    not null unique,

  photo          text,

  -- Immatriculation, telle qu'elle est peinte sur la garde-boue. La mama
  -- reconnait la moto avant de reconnaitre le visage.
  moto           text,
  plaque         text,

  -- Le quartier ou le depot d'ou il part. Sert a grouper les courses.
  zone           text    not null,

  -- Prix de la course, en FCFA. Declare ici pour que le comptoir puisse
  -- l'ecrire sur le devis : une mama qui attend doit savoir ce qu'elle doit
  -- au moto en plus de sa marchandise.
  tarif_course   integer not null default 0
    check (tarif_course between 0 and 50000),

  -- On ne supprime pas un livreur : ses courses passees doivent rester
  -- rattachables a quelqu'un.
  actif          boolean not null default true,

  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now(),

  constraint livreurs_nom_court check (char_length(nom) between 2 and 60),
  constraint livreurs_zone_courte check (char_length(zone) between 2 and 60),
  constraint livreurs_telephone_format check (telephone_237 ~ '^\+237[26][0-9]{8}$')
);

create index livreurs_zone_idx on public.livreurs (zone, actif);

comment on table public.livreurs is
  'Les moto du comptoir. Gérées par l''admin, affichées à la cliente, jamais un compte qui se connecte.';
comment on column public.livreurs.plaque is
  'Immatriculation. Le repere que la mama verifie avant d''ouvrir sa porte.';

create trigger livreurs_touch before update on public.livreurs
  for each row execute function mboa.touche_updated_at();

-- ----------------------------------------------------------------------------
-- Le devis porte son livreur
-- ----------------------------------------------------------------------------
alter table public.commandes
  add column if not exists livreur_id uuid references public.livreurs (id) on delete set null;

create index commandes_livreur_idx on public.commandes (livreur_id, created_at desc);

comment on column public.commandes.livreur_id is
  'Affecte par le comptoir au moment du depart. C''est lui qui rend la carte « qui arrive » possible chez la cliente.';

-- ----------------------------------------------------------------------------
-- Vitrine sans telephone
--
-- Une projection portee par la vue, pas par la table : le numero ne sort
-- jamais par cette porte, il ne sort que par mboa.contact_livreur(), pour les
-- deux personnes qui ont le droit de l'appeler ce jour-la.
-- ----------------------------------------------------------------------------
create or replace view public.vitrine_livreurs as
  select l.id, l.nom, l.photo, l.moto, l.plaque, l.zone, l.tarif_course
  from public.livreurs l
  where l.actif;

comment on view public.vitrine_livreurs is
  'Les moto actives, sans leur numéro. La cliente voit qui peut arriver, pas comment le joindre.';

grant select on public.vitrine_livreurs to anon, authenticated;

-- ----------------------------------------------------------------------------
-- RLS
-- ----------------------------------------------------------------------------
alter table public.livreurs enable row level security;
alter table public.livreurs force row level security;

-- Le tableau des livreurs est lisible par tout le monde : c'est un annuaire
-- de service public, pas un carnet d'adresses. La colonne telephone reste
-- protegee par la vue, pas par cette policy.
create policy livreurs_lecture_tous
  on public.livreurs for select
  to anon, authenticated
  using (true);

create policy livreurs_ecriture_admin
  on public.livreurs for insert
  to authenticated
  with check (mboa.est_admin());

create policy livreurs_maj_admin
  on public.livreurs for update
  to authenticated
  using (mboa.est_admin())
  with check (mboa.est_admin());

-- La suppression est refusee a tout le monde, admin compris : on met actif =
-- false. Une course payee sans livreur identifiable est une course contestee.
create policy livreurs_aucune_suppression
  on public.livreurs for delete
  to authenticated
  using (false);

-- Pas de `create policy` sur `vitrine_livreurs` : Postgres refuse la RLS sur
-- une vue, et la migration s'arretait la. Le `grant select` pose plus haut
-- est la seule porte, et la vue ne selectionne jamais le numero.

-- La RLS filtre des lignes, jamais des colonnes : `using (true)` laissait
-- donc `select telephone_237 from livreurs` accessible a tout porteur de la
-- cle anon, alors que le commentaire de la policy promettait le contraire.
-- Le seul verrou possible est un privilege de colonne. L'app lit deja ses
-- livreurs avec une liste explicite, sans le numero.
revoke select on public.livreurs from anon;
revoke select on public.livreurs from authenticated;
grant select (id, profil_id, nom, photo, moto, plaque, zone, tarif_course, actif, created_at, updated_at)
  on public.livreurs to authenticated;

-- ----------------------------------------------------------------------------
-- Le numero du livreur, rendu aux seules parties
-- ----------------------------------------------------------------------------
create or replace function mboa.contact_livreur(p_commande_id uuid)
returns text
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_cmd public.commandes;
  v_uid uuid := (select auth.uid());
begin
  select * into v_cmd from public.commandes where id = p_commande_id;
  if not found then
    raise exception 'devis inconnu';
  end if;

  if v_cmd.livreur_id is null then
    return null;
  end if;

  -- Deux personnes, pas trois : la cliente qui recoit, le comptoir qui
  -- organise. L'agriculteur n'est pas partie a la course, il a vendu sa
  -- marchandise au depot et n'a plus rien a y faire.
  if not mboa.est_admin() and v_cmd.consommateur_id <> v_uid then
    raise exception 'acces refuse a ce numero' using errcode = '42501';
  end if;

  return (select telephone_237 from public.livreurs where id = v_cmd.livreur_id);
end;
$$;

comment on function mboa.contact_livreur is
  'Le seul chemin par lequel un numero de livreur quitte la base. Reserve a la cliente et au comptoir.';

-- ----------------------------------------------------------------------------
-- Affecter un livreur : le geste du comptoir au depart de la moto
--
-- Appeler directement l'UPDATE de la commande suffirait, mais cette fonction
-- pose trois choses que l'interface oublie toujours : le statut qui passe en
-- livraison, l'heure de depart, et la notification.
-- ----------------------------------------------------------------------------
create or replace function mboa.affecter_livreur(
  p_commande_id uuid,
  p_livreur_id uuid
)
returns public.commandes
language plpgsql
security definer
set search_path = public
as $$
declare
  v_cmd public.commandes;
begin
  if not mboa.est_admin() then
    raise exception 'seul le comptoir affecte un livreur' using errcode = '42501';
  end if;

  select * into v_cmd from public.commandes where id = p_commande_id for update;
  if not found then
    raise exception 'devis inconnu';
  end if;

  -- Un devis a l'etat `nouvelle` n'est pas encore engage : on ne monte pas
  -- une moto pour un panier que le comptoir n'a pas valide.
  if v_cmd.statut_enum not in ('validee_admin', 'en_livraison') then
    raise exception 'on n''affecte une moto qu''a un devis validé, pas au statut %', v_cmd.statut_enum;
  end if;

  if not exists (select 1 from public.livreurs where id = p_livreur_id and actif) then
    raise exception 'livreur inconnu ou inactive';
  end if;

  update public.commandes
     set livreur_id  = p_livreur_id,
         statut_enum = 'en_livraison'::public.statut_enum
   where id = p_commande_id
  returning * into v_cmd;

  return v_cmd;
end;
$$;

grant execute on function mboa.affecter_livreur(uuid, uuid) to authenticated;
grant execute on function mboa.contact_livreur(uuid) to authenticated;

-- ----------------------------------------------------------------------------
-- Les notifications du comptoir.
--
-- ATTENTION : cette fonction REMPLACE mboa.notifier() dans son integralite.
-- Un `create or replace` partiel effacerait les branches des achats, des
-- devis et des listes. Toute nouvelle notification doit donc etre ajoutee
-- ICI, a la liste complete, et nulle part ailleurs.
-- ----------------------------------------------------------------------------
create or replace function mboa.notifier()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := (select auth.uid());
begin
  -- Un agriculteur qui propose attend une reponse : c'est la seule
  -- notification qu'il recoit, et elle decide de sa journee.
  if tg_table_name::text = 'achats' and tg_op = 'INSERT' then
    insert into mboa.notifications (destinataire, type, objet_id, texte_voice)
      select p.id, 'achat_attend', new.id, 'Un agriculteur attend votre réponse'
      from public.profiles p
      where p.role = 'admin' and p.actif;

  elsif tg_table_name::text = 'achats' and tg_op = 'UPDATE' then
    if new.statut <> old.statut then
      insert into mboa.notifications (destinataire, type, objet_id, texte_voice)
      values (
        new.fournisseur_id,
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

drop trigger if exists commandes_livreur_notif on public.commandes;
create trigger commandes_livreur_notif after update of livreur_id on public.commandes
  for each row execute function mboa.notifier();

-- La jointure de l'app comptoir a besoin du nom du livreur avec le devis.
alter table public.livreurs replica identity full;

do $$
begin
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'livreurs'
  ) then
    alter publication supabase_realtime add table public.livreurs;
  end if;
end
$$;

commit;
