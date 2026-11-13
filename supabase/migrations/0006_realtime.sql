-- ============================================================================
-- MBOA BIO 237 - 0006 : temps reel du comptoir
--
-- Les trois apps ecoutent le meme canal, mais plus rien ne se passe comme
-- avant :
--   agriculteur propose  -> table achats   -> le comptoir est prevenu
--   comptoir signe       -> achats = valide + produits.quantite bouge
--                          -> la vitrine de la cliente change toute seule
--   cliente envoie       -> table commandes -> le comptoir voit le devis
--   comptoir valide      -> stock sorti    -> la quantite disparait chez
--                          toutes les clientes en meme temps
--
-- C'est ce dernier point qui justifie le temps reel dans ce modele : sur un
-- stock commun, une quantite qui ne se rafraichit pas toute seule veut dire
-- deux clientes qui croient acheter les trois derniers kilos de chevre.
-- ============================================================================

do $$
begin
  -- La publication supabase_realtime existe sur tout projet heberge ; on
  -- ajoute les tables une a une pour rester idempotent.
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'produits'
  ) then
    alter publication supabase_realtime add table public.produits;
  end if;

  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'achats'
  ) then
    alter publication supabase_realtime add table public.achats;
  end if;

  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'commandes'
  ) then
    alter publication supabase_realtime add table public.commandes;
  end if;

  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'profiles'
  ) then
    alter publication supabase_realtime add table public.profiles;
  end if;
end
$$;

-- `replica identity full` sur produits : le payload doit porter l'avant et
-- l'apres pour qu'une fiche qui passe de 12 a 0 parte de la vitrine sans
-- recharger la page.
--
-- Sur commandes, c'est la RLS qui filtre ce que chaque app recoit ; les
-- numeros de telephone ne transitent pas par les evenements WebSocket, ils
-- ne sortent que par les RPC de contact.
alter table public.produits  replica identity full;
alter table public.achats    replica identity full;
alter table public.commandes replica identity full;

comment on table public.commandes is
  'Replica identity full : le payload realtime doit porter l''avant/apres pour que la file du comptoir se mette a jour sans recharger.';

-- ----------------------------------------------------------------------------
-- Compteur d'evenements non lus par role. L'app allume une pastille sonore au
-- reveil ; on garde un mini journal plutot que de pousser du bruit en continu.
-- ----------------------------------------------------------------------------
create table mboa.notifications (
  id          bigint generated always as identity primary key,
  destinataire uuid not null references public.profiles (id) on delete cascade,
  type        text not null,
  objet_id    uuid,
  texte_voice text not null,
  lue         boolean not null default false,
  created_at  timestamptz not null default now()
);

create index notifications_dest_idx on mboa.notifications (destinataire, lue, created_at desc);

alter table mboa.notifications enable row level security;

create policy notifications_lecture_destinataire
  on mboa.notifications for select
  to authenticated
  using (destinataire = (select auth.uid()) or mboa.est_admin());

create policy notifications_marquer_lue
  on mboa.notifications for update
  to authenticated
  using (destinataire = (select auth.uid()))
  with check (destinataire = (select auth.uid()));

do $$
begin
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime' and schemaname = 'mboa' and tablename = 'notifications'
  ) then
    alter publication supabase_realtime add table mboa.notifications;
  end if;
end
$$;

-- ----------------------------------------------------------------------------
-- Notification crossée par la base, pas par le client : si le telephone du
-- vendeur sonne trente secondes plus tard, l'app n'etait peut-etre pas ouverte.
--
-- ATTENTION : 0012_livreurs.sql REMPLACE cette fonction dans son integralite
-- pour y ajouter les branches du livreur. Toute nouvelle notification doit
-- etre ajoutee la-bas, dans la liste complete, et pas ici.
-- ----------------------------------------------------------------------------
create or replace function mboa.notifier()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if tg_table_name::text = 'achats' and tg_op = 'INSERT' then
    insert into mboa.notifications (destinataire, type, objet_id, texte_voice)
      select p.id, 'achat_attend', new.id, 'Un agriculteur attend votre réponse'
      from public.profiles p
      where p.role = 'admin' and p.actif;

  elsif tg_table_name::text = 'achats' and tg_op = 'UPDATE'
        and new.statut is distinct from old.statut then
    insert into mboa.notifications (destinataire, type, objet_id, texte_voice)
    values (
      new.fournisseur_id,
      'achat_statut',
      new.id,
      case new.statut
        when 'valide' then 'Le comptoir a acheté votre marchandise'
        when 'paye'   then 'Le comptoir vous a payé'
        when 'annule' then 'Le comptoir n''a pas retenu votre marchandise'
        when 'litige' then 'Un problème est signalé sur votre marchandise'
        else 'Nouvelle du comptoir'
      end
    );

  elsif tg_table_name::text = 'commandes' and tg_op = 'INSERT' then
    insert into mboa.notifications (destinataire, type, objet_id, texte_voice)
      select p.id, 'devis_recu', new.id, 'Un devis vient d''arriver au comptoir'
      from public.profiles p
      where p.role = 'admin' and p.actif;

  elsif tg_table_name::text = 'commandes' and tg_op = 'UPDATE'
        and new.statut_enum is distinct from old.statut_enum then
    insert into mboa.notifications (destinataire, type, objet_id, texte_voice)
    values (
      new.consommateur_id,
      'devis_statut',
      new.id,
      case new.statut_enum
        when 'validee_admin' then 'Votre devis est validé, le stock est réservé'
        when 'en_livraison'  then 'La moto est en route'
        when 'livree'        then 'Commande livrée, merci'
        when 'recue'         then 'Commande fermée, merci'
        when 'annulee'       then 'Votre devis a été annulé'
        else 'Devis mis à jour'
      end
    );
  end if;

  return coalesce(new, old);
end;
$$;

create trigger achats_notif after insert or update on public.achats
  for each row execute function mboa.notifier();

create trigger commandes_notif after insert or update on public.commandes
  for each row execute function mboa.notifier();
