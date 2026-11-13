-- ============================================================================
-- MBOA BIO 237 - 0010 : le devis, du panier signe au stock qui part
--
-- Ce fichier porte la deuxieme decision du modele : le stock sort a la
-- validation du devis, pas a la livraison.
--
-- Pourquoi. Le comptoir vend des produits rares par kilos : trois kilos de
-- chèvre, deux plateaux d'œufs. Si le stock ne bouge qu'a la livraison, deux
-- clientes peuvent valider le meme dernier kilos a dix minutes d'ecart, la
-- seconde recoit un « rupture » qu'on ne peut plus reparer, et le comptoir
-- doit s'excuser. La quantite disponible doit donc diminuer au moment precis
-- ou le comptoir s'engage.
--
-- Ce qui va avec : l'annulation fait revenir la marchandise. Un devis
-- annule, un litige complet, une cliente introuvable au bout delai : le stock
-- est rendu, ligne par ligne, a partir du JSONB fige a la caisse. C'est la
-- moitie obligatoire de la regle, et l'autre moitie est de ne jamais rendre
-- deux fois.
-- ============================================================================

begin;

-- ----------------------------------------------------------------------------
-- 1. Les colonnes que le cycle de vie ajoute a la table du 0002
-- ----------------------------------------------------------------------------
alter table public.commandes
  add column if not exists livree_le       timestamptz,
  add column if not exists livree_par      uuid references public.profiles (id) on delete set null,
  add column if not exists recue_le        timestamptz,
  add column if not exists recue_par       uuid references public.profiles (id) on delete set null,
  add column if not exists satisfaction    text check (satisfaction in ('bon', 'probleme')),
  add column if not exists satisfaction_motif text,
  add column if not exists satisfaction_audio text,
  add column if not exists clos            boolean not null default false,
  add column if not exists clos_par        text,
  add column if not exists annule_le       timestamptz,
  add column if not exists annule_par      uuid references public.profiles (id) on delete set null,
  add column if not exists motif_annulation text,

  -- Le stock est-il deja sorti ? Une colonne, et pas un statut : un devis
  -- annule reste annule, mais le retour ne doit se jouer qu'une fois.
  add column if not exists stock_sorti     boolean not null default false;

comment on column public.commandes.stock_sorti is
  'Vrai quand les quantites du devis ont ete retirees du stock. Garde unique du retour : sans elle, deux annulations rendraient la meme marchandise.';

-- ----------------------------------------------------------------------------
-- 2. La caisse : creer le devis
--
-- Le prix ET le cout d'achat de chaque ligne sont figes dans le JSONB a la
-- seconde ou la cliente appuie. Six mois plus tard, la marge du devis se
-- relit sans avoir a savoir ce que coutait la marchandise a l'epoque.
--
-- La disponibilite est verifiee ici, mais pas consomme : c'est la validation
-- qui reserve. Une panier qui n'est pas encore un devis engage personne.
-- ----------------------------------------------------------------------------
create or replace function mboa.creer_devis(
  p_produits jsonb,
  p_moto boolean default true
)
returns public.commandes
language plpgsql
security definer
set search_path = public
as $$
declare
  v_item    jsonb;
  v_prod    public.produits;
  v_lignes  jsonb := '[]'::jsonb;
  v_total   integer := 0;
  v_cout    integer := 0;
  v_qte     numeric;
  v_cmd     public.commandes;
begin
  if not mboa.est_consominateur() then
    raise exception 'seule une cliente peut envoyer un devis' using errcode = '42501';
  end if;

  if jsonb_typeof(p_produits) <> 'array' or jsonb_array_length(p_produits) = 0 then
    raise exception 'panier vide';
  end if;

  for v_item in select * from jsonb_array_elements(p_produits)
  loop
    v_qte := coalesce((v_item ->> 'quantite')::numeric, 0);
    if v_qte <= 0 then
      raise exception 'quantite invalide pour %', coalesce(v_item ->> 'nom', 'cette ligne');
    end if;

    -- Une ligne sans slug connu est une ligne dictee a la voix : elle reste
    -- au devis, sans prix fige depuis le stock, et l'admin la chiffre a la
    -- validation. Elle ne peut pas pecher le stock, puisqu'elle n'en a pas.
    if nullif(v_item ->> 'slug', '') is null then
      if coalesce((v_item ->> 'prix')::integer, 0) < 1 then
        raise exception 'une ligne libre doit porter un prix';
      end if;
      v_lignes := v_lignes || (v_item || jsonb_build_object('cout_achat', 0))::jsonb;
      v_total  := v_total + (v_qte * (v_item ->> 'prix')::integer)::integer;
      continue;
    end if;

    select * into v_prod from public.produits where slug = (v_item ->> 'slug');
    if not found then
      raise exception 'produit % inconnu du comptoir', v_item ->> 'slug';
    end if;
    if not v_prod.actif then
      raise exception '% n''est plus a la vente', v_prod.nom;
    end if;
    if v_prod.quantite < v_qte then
      raise exception 'pas assez de % : % sur %',
        v_prod.nom, v_qte, v_prod.unite;
    end if;

    -- Le prix affiche n'est jamais celui que la cliente a vu a l'ecran :
    -- c'est celui du comptoir a la seconde de la caisse. Un cache de liste
    -- age de deux jours ne fixe pas un prix.
    v_lignes := v_lignes || jsonb_build_object(
      'produit_id', v_prod.id,
      'slug',       v_prod.slug,
      'nom',        v_prod.nom,
      'categorie',  v_prod.categorie,
      'unite',      v_prod.unite,
      'quantite',   v_qte,
      'prix',       v_prod.prix,
      'cout_achat', coalesce(v_prod.prix_achat, 0),
      'photo',      coalesce(v_prod.photo_filigranee, v_prod.photo_reelle)
    );

    v_total := v_total + (v_qte * v_prod.prix)::integer;
    v_cout  := v_cout  + (v_qte * coalesce(v_prod.prix_achat, 0))::integer;
  end loop;

  insert into public.commandes
    (consommateur_id, produits, statut_enum, montant_total, cout_achat,
     paiement, livraison_moto)
  values
    ((select auth.uid()), v_lignes, 'nouvelle', v_total, v_cout,
     'especes', p_moto)
  returning * into v_cmd;

  return v_cmd;
end;
$$;

comment on function mboa.creer_devis is
  'La caisse. Fige prix et coût d''achat ligne à ligne, vérifie la disponibilité, ne réserve pas encore.';

-- ----------------------------------------------------------------------------
-- 3. La validation : c'est ici que le stock sort
-- ----------------------------------------------------------------------------
create or replace function mboa.valider_devis(p_commande_id uuid)
returns public.commandes
language plpgsql
security definer
set search_path = public
as $$
declare
  v_cmd   public.commandes;
  v_item  jsonb;
  v_qte   numeric;
  v_slug  text;
begin
  if not mboa.est_admin() then
    raise exception 'seul le comptoir valide un devis' using errcode = '42501';
  end if;

  select * into v_cmd from public.commandes where id = p_commande_id for update;
  if not found then
    raise exception 'devis inconnu';
  end if;

  if v_cmd.statut_enum <> 'nouvelle' then
    raise exception 'un devis au statut % ne se valide pas', v_cmd.statut_enum;
  end if;
  if v_cmd.stock_sorti then
    raise exception 'ce devis a deja retire du stock';
  end if;

  -- Verrou ligne par ligne, dans l'ordre du panier. Entre la caisse et la
  -- signature, un autre devis a pu vider la meme reference : la relecture
  -- sous verrou est la seule chose qui empeche la survente.
  for v_item in select * from jsonb_array_elements(v_cmd.produits)
  loop
    v_slug := nullif(v_item ->> 'slug', '');
    if v_slug is null then
      continue;
    end if;

    v_qte := (v_item ->> 'quantite')::numeric;

    -- Une part de pack ne sort pas elle-meme du stock : ce sont ses
    -- ingredients qui partent, et le nombre de parts restantes se recalcule
    -- derriere (0013). Le pack n'a pas de quantite propre a soustraire.
    if jsonb_typeof(v_item -> 'composants') = 'array'
       and jsonb_array_length(v_item -> 'composants') > 0 then
      perform mboa.mouvement_pack(v_item, -1);
      continue;
    end if;

    update public.produits
       set quantite = quantite - v_qte
     where slug = v_slug
       and quantite >= v_qte;

    if not found then
      raise exception 'plus assez de % au stock pour valider ce devis', v_slug;
    end if;
  end loop;

  update public.commandes
     set statut_enum = 'validee_admin',
         stock_sorti = true
   where id = p_commande_id
  returning * into v_cmd;

  -- Un ingredient parti est un plat en moins : les packs recalculent leurs
  -- parts disponibles apres chaque sortie, pack ou pas.
  perform mboa.recalculer_packs();

  return v_cmd;
end;
$$;

-- ----------------------------------------------------------------------------
-- 4. L'annulation : la marchandise revient
--
-- Une seule entree par la porte : la colonne stock_sorti se remet a faux
-- dans la meme transaction que le rendu, ce qui rend le double retour
-- impossible meme si l'admin rappuie.
-- ----------------------------------------------------------------------------
create or replace function mboa.annuler_devis(
  p_commande_id uuid,
  p_motif text default null,
  p_audio_url text default null
)
returns public.commandes
language plpgsql
security definer
set search_path = public
as $$
declare
  v_cmd  public.commandes;
  v_item jsonb;
  v_slug text;
begin
  if not mboa.est_admin() then
    raise exception 'seul le comptoir annule un devis' using errcode = '42501';
  end if;

  select * into v_cmd from public.commandes where id = p_commande_id for update;
  if not found then
    raise exception 'devis inconnu';
  end if;

  if v_cmd.statut_enum in ('livree', 'recue', 'annulee') then
    raise exception 'un devis remis ne s''annule plus: c''est un litige' using errcode = '42501';
  end if;

  if v_cmd.stock_sorti then
    for v_item in select * from jsonb_array_elements(v_cmd.produits)
    loop
      v_slug := nullif(v_item ->> 'slug', '');
      if v_slug is null then
        continue;
      end if;

      -- `on conflict` n'existe pas sur un UPDATE : la fiche a pu etre retiree
      -- du catalogue entre-temps. Rendons ce qui existe, ignorons le reste,
      -- sans laisser l'annulation echouer la dessus.
      if jsonb_typeof(v_item -> 'composants') = 'array'
         and jsonb_array_length(v_item -> 'composants') > 0 then
        perform mboa.mouvement_pack(v_item, 1);
        continue;
      end if;

      update public.produits
         set quantite = quantite + (v_item ->> 'quantite')::numeric
       where slug = v_slug;
    end loop;

    perform mboa.recalculer_packs();
  end if;

  update public.commandes
     set statut_enum     = 'annulee',
         stock_sorti     = false,
         annule_le       = now(),
         annule_par      = (select auth.uid()),
         motif_annulation = coalesce(nullif(trim(p_motif), ''), 'annule par le comptoir'),
         satisfaction_audio = coalesce(p_audio_url, satisfaction_audio)
   where id = p_commande_id
  returning * into v_cmd;

  return v_cmd;
end;
$$;

-- ----------------------------------------------------------------------------
-- 5. Le pointage a la porte, et le pouce de la cliente
--
-- Le stock n'a plus rien a voir ici : il est sorti a la validation. Le
-- pointage enregistre ce qui a ete reellement garde et paye, et c'est ce
-- montant, jamais le panier demande, qui fait la marge.
-- ----------------------------------------------------------------------------
create or replace function mboa.pointer_livraison(
  p_commande_id uuid,
  p_montant_livre integer
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
    raise exception 'seul le comptoir pointe une livraison' using errcode = '42501';
  end if;

  select * into v_cmd from public.commandes where id = p_commande_id for update;
  if not found then
    raise exception 'devis inconnu';
  end if;

  if v_cmd.statut_enum not in ('validee_admin', 'en_livraison') then
    raise exception 'on ne livre pas un devis au statut %', v_cmd.statut_enum;
  end if;

  if p_montant_livre is null or p_montant_livre < 0 then
    raise exception 'montant livre invalide';
  end if;

  -- On ne peut pas encaisser plus que ce que le devis demandait. La marge
  -- se protege aussi des erreurs de frappe : 15 000 saisis pour 1 500
  -- ferait apparaitre une marge de 15 000.
  if p_montant_livre > v_cmd.montant_total then
    raise exception 'on ne peut pas encaisser plus que le devis (% > %)',
      p_montant_livre, v_cmd.montant_total;
  end if;

  update public.commandes
     set statut_enum   = 'livree',
         montant_livre = p_montant_livre,
         livree_le     = now(),
         livree_par    = (select auth.uid())
   where id = p_commande_id
  returning * into v_cmd;

  return v_cmd;
end;
$$;

create or replace function mboa.confirmer_reception(
  p_commande_id uuid,
  p_bon boolean,
  p_motif text default null,
  p_audio_url text default null
)
returns public.commandes
language plpgsql
security definer
set search_path = public
as $$
declare
  v_cmd public.commandes;
begin
  if not mboa.est_consominateur() then
    raise exception 'seule la cliente confirme sa reception' using errcode = '42501';
  end if;

  select * into v_cmd from public.commandes where id = p_commande_id for update;
  if not found then
    raise exception 'devis inconnu';
  end if;

  if v_cmd.statut_enum <> 'livree' then
    raise exception 'on ne confirme pas un devis au statut %', v_cmd.statut_enum;
  end if;

  if v_cmd.consommateur_id <> (select auth.uid()) then
    raise exception 'acces refuse a ce devis' using errcode = '42501';
  end if;

  update public.commandes
     set statut_enum        = 'recue',
         recue_le           = now(),
         recue_par          = (select auth.uid()),
         satisfaction       = case when p_bon then 'bon' else 'probleme' end,
         satisfaction_motif = case when p_bon then null else coalesce(nullif(trim(p_motif), ''), 'non precise') end,
         satisfaction_audio = p_audio_url
   where id = p_commande_id
  returning * into v_cmd;

  return v_cmd;
end;
$$;

-- ----------------------------------------------------------------------------
-- 6. Gardes de statut et de solde
--
-- Le statut ne se decrete pas a la main : les RPC ci-dessus sont les seules
-- portes. Un client qui enverrait `statut_enum = 'livree'` par l'API se
-- heurte a cette exception, et le message dit ce qui est interdit, pas
-- seulement qu'une policy a refuse.
-- ----------------------------------------------------------------------------
create or replace function mboa.controle_statut_commande()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.statut_enum = old.statut_enum then
    return new;
  end if;

  -- Les RPC passent par la meme table : l'auteur du changement est controle
  -- par la fonction, pas par la policy, donc on laisse passer quand la
  -- transition suit l'ordre du cycle de vie.
  if old.statut_enum = 'nouvelle'      and new.statut_enum in ('validee_admin', 'annulee') then return new; end if;
  if old.statut_enum = 'validee_admin' and new.statut_enum in ('en_livraison', 'annulee')   then return new; end if;
  if old.statut_enum = 'en_livraison'  and new.statut_enum in ('livree', 'annulee')         then return new; end if;
  if old.statut_enum = 'livree'        and new.statut_enum = 'recue'                        then return new; end if;

  -- Hors de l'ordre, seul le comptoir peut revenir en arriere, et seulement
  -- pour rouvrir un litige.
  if mboa.est_admin() and new.statut_enum <> 'recue' then
    return new;
  end if;

  raise exception 'transition de statut interdite: % -> %', old.statut_enum, new.statut_enum
    using errcode = '42501';
end;
$$;

drop trigger if exists commandes_statut_garde on public.commandes;
create trigger commandes_statut_garde
  before update of statut_enum on public.commandes
  for each row execute function mboa.controle_statut_commande();

-- ----------------------------------------------------------------------------
-- Le solde ne se declare que sur le pouce de la cliente, ou sur une cloture
-- de delai decidee par le comptoir. Un devis annule ne solde jamais rien.
-- ----------------------------------------------------------------------------
create or replace function mboa.controle_clore()
returns trigger
language plpgsql
as $$
begin
  if new.clos and not old.clos then
    if new.statut_enum not in ('livree', 'recue') then
      raise exception 'on ne solde pas un devis au statut %', new.statut_enum;
    end if;
    if coalesce(new.satisfaction, 'bon') = 'probleme' and new.clos_par is distinct from 'admin_litige' then
      raise exception 'un pouce baisse ne solde pas: le comptoir tranche d''abord';
    end if;
    new.clos_le := coalesce(new.clos_le, now());
  end if;

  if not new.clos then
    new.clos_le := null;
  end if;

  return new;
end;
$$;

alter table public.commandes
  add column if not exists clos_le timestamptz;

drop trigger if exists commandes_clore on public.commandes;
create trigger commandes_clore
  before update on public.commandes
  for each row execute function mboa.controle_clore();

-- ----------------------------------------------------------------------------
-- 7. La marge, en lecture seulement
--
-- Pas de colonne: une marge se calcule de ce qui est deja fige. L'exposer
-- comme une fonction evite qu'un declenchement mal ordonne la calcule sur un
-- montant_livre pas encore saisi.
--
-- Le cout est proroge sur ce qui a ete garde, et pas sur ce qui etait
-- demande. Une cliente qui ne prend qu'un kilo de chevre sur deux a paye
-- 3 500 et le comptoir a garde le reste au stock : compter les 6 000 de cout
-- entier ferait apparaitre une marge negative sur une vente normale, et le
-- bilan du comptoir deviendrait une collection de fausses pertes.
-- ----------------------------------------------------------------------------
create or replace function mboa.marge_devis(p_commande_id uuid)
returns integer
language sql
stable
security definer
set search_path = public
as $$
  select case
    when not c.clos then 0
    when c.montant_total <= 0 then coalesce(c.montant_livre, 0)
    else coalesce(c.montant_livre, 0)
         - round(c.cout_achat::numeric * coalesce(c.montant_livre, 0) / c.montant_total)::integer
  end
  from public.commandes c
  where c.id = p_commande_id
$$;

comment on function mboa.marge_devis is
  'Ce que le devis a rapporté. Zéro tant que la cliente n''a pas soldé ; le coût d''achat suit la fraction réellement gardée à la porte.';

-- ----------------------------------------------------------------------------
-- 8. Les devis qui attendent une reponse
--
-- La fonction rend des lignes completes, cout d'achat compris. Elle est
-- pourtant accordee a `authenticated` par la 0015, d'ou le `est_admin()` dans
-- le `where` : une cliente qui l'appelle recoit un ensemble vide, jamais les
-- devis des autres.
-- ----------------------------------------------------------------------------
create or replace function mboa.devis_sans_confirmation(p_delai interval default '12 hours')
returns setof public.commandes
language sql
stable
security definer
set search_path = public
as $$
  select c.*
  from public.commandes c
  where mboa.est_admin()
    and c.statut_enum = 'livree'
    and c.livree_le < now() - p_delai
  order by c.livree_le asc
$$;

-- Le silence d'une personne agee ne doit pas punir le comptoir ni bloquer la
-- fiche : passe le delai, l'admin peut solder lui-meme, en le tracant.
create or replace function mboa.fermer_sur_delai(p_commande_id uuid)
returns public.commandes
language plpgsql
security definer
set search_path = public
as $$
declare
  v_cmd public.commandes;
begin
  if not mboa.est_admin() then
    raise exception 'seul le comptoir clot sur delai' using errcode = '42501';
  end if;

  select * into v_cmd from public.commandes where id = p_commande_id for update;
  if not found then
    raise exception 'devis inconnu';
  end if;

  if v_cmd.statut_enum <> 'livree' then
    raise exception 'on clot un devis livre, pas un devis %', v_cmd.statut_enum;
  end if;

  update public.commandes
     set statut_enum = 'recue',
         recue_le    = now(),
         satisfaction = null,
         clos        = true,
         clos_par    = 'delai_comptoir'
   where id = p_commande_id
  returning * into v_cmd;

  return v_cmd;
end;
$$;

-- ----------------------------------------------------------------------------
-- 9. Les listes de marche, devenues de simples brouillons de devis
--
-- Une liste n'a plus de fournisseur : la cliente prepare ce qu'elle veut
-- chez MBOA, pas chez un village. Le code court dictable reste, c'est la
-- piece utile du papier.
-- ----------------------------------------------------------------------------
create table public.listes (
  id                uuid primary key default gen_random_uuid(),
  consommateur_id   uuid not null references public.profiles (id) on delete cascade,
  produits          jsonb not null check (jsonb_typeof(produits) = 'array'),
  code              text   not null unique check (code ~ '^[a-z0-9]{6,8}$'),
  titre             text   not null default 'Ma liste',
  image_url         text,
  montant_estime    integer not null default 0 check (montant_estime >= 0),
  transformee_en    uuid references public.commandes (id) on delete set null,
  transformee_le    timestamptz,
  envoyee_le        timestamptz,
  created_at        timestamptz not null default now(),
  updated_at        timestamptz not null default now()
);

create index listes_conso_idx on public.listes (consommateur_id, created_at desc);
create unique index listes_code_idx on public.listes (code);

alter table public.listes enable row level security;

create policy listes_lecture_soi
  on public.listes for select
  to authenticated
  using (consommateur_id = (select auth.uid()) or mboa.est_admin());

create policy listes_ecriture_soi
  on public.listes for all
  to authenticated
  using (consommateur_id = (select auth.uid()) and mboa.est_consominateur())
  with check (consommateur_id = (select auth.uid()));

create policy listes_admin_tout
  on public.listes for all
  to authenticated
  using (mboa.est_admin())
  with check (mboa.est_admin());

create or replace function mboa.liste_par_code(p_code text)
returns public.listes
language sql
stable
security definer
set search_path = public
as $$
  select l.*
  from public.listes l
  where l.code = lower(trim(p_code))
$$;

comment on function mboa.liste_par_code is
  'Retrouve le papier d''une mama au telephone. Ne rend ni son numéro, ni son identite : le code est la seule cle que l''agent a le droit de taper.';

create trigger listes_touch before update on public.listes
  for each row execute function mboa.touche_updated_at();

-- ----------------------------------------------------------------------------
-- 10. Accords
-- ----------------------------------------------------------------------------
grant execute on function mboa.creer_devis(jsonb, boolean) to authenticated;
grant execute on function mboa.valider_devis(uuid) to authenticated;
grant execute on function mboa.annuler_devis(uuid, text, text) to authenticated;
grant execute on function mboa.pointer_livraison(uuid, integer) to authenticated;
grant execute on function mboa.confirmer_reception(uuid, boolean, text, text) to authenticated;
grant execute on function mboa.fermer_sur_delai(uuid) to authenticated;
grant execute on function mboa.marge_devis(uuid) to authenticated;
grant execute on function mboa.devis_sans_confirmation(interval) to authenticated;
grant execute on function mboa.liste_par_code(text) to authenticated;

commit;
