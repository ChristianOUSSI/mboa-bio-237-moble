-- ============================================================================
-- MBOA BIO 237 - 0013 : les packs de plats prepares
--
-- Un pack n'est pas une table de plus. C'est une ligne du stock du comptoir
-- qui se cuisine avec d'autres lignes : « Pack Ndele, trois bottes de ndole,
-- un kilo de crevettes, une bouteille d'huile rouge, cinq morceaux de
-- manioc », vendu a la part.
--
-- Le garder dans `produits` est le seul choix qui ne casse rien : la
-- vitrine, la grille de categories, le panier, la caisse, le devis papier, la
-- confirmation et le suivi fonctionnent deja. Une table `packs` a part
-- aurait oblige chaque ecran a demander « est-ce un produit ou un pack ? »,
-- et c'est exactement la complexite que les utilisatrices agees refusaient.
--
-- Ce que la base doit garantir :
--   * une ligne est soit un produit simple, soit un pack nomme et compose ;
--   * un pack se compte en parts, toujours ;
--   * chaque composant existe au catalogue, et sa quantite est positive ;
--   * le nombre de parts vendables est plafonne par l'ingredient le plus
--     rare, et se recalcule a chaque mouvement de stock ;
--   * a la validation du devis, ce sont les composants qui sortent du stock,
--     pas le pack : le ndole reste du ndole dans l'inventaire.
-- ============================================================================

begin;

-- ----------------------------------------------------------------------------
-- 1. La ligne devient polymorphe
-- ----------------------------------------------------------------------------
alter table public.produits
  add column if not exists pack_composants jsonb;

alter table public.produits
  drop constraint if exists produits_soit_produit_soit_pack,
  add constraint produits_soit_produit_soit_pack check (
    pack_composants is null
    or (
      jsonb_typeof(pack_composants) = 'array'
      and jsonb_array_length(pack_composants) >= 2
      and unite = 'part'
    )
  );

comment on column public.produits.pack_composants is
  E'[{"slug":"ndole","nom":"Ndolè","quantite":3.0,"unite":"botte"}]. La recette, figée à la composition.';

create index if not exists produits_packs_idx
  on public.produits (categorie, nom)
  where pack_composants is not null;

-- ----------------------------------------------------------------------------
-- 2. Controler une recette
--
-- Un composant qui ne designe rien au catalogue serait une part vendue dans
-- le vide : rien a retirer du stock, rien a montrer a la cliente. Le controle
-- se fait a l'ecriture et non a la vente, pour que l'admin voie son erreur
-- pendant qu'il compose et pas quand une cliente paie a sa porte.
-- ----------------------------------------------------------------------------
create or replace function mboa.controle_pack()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_item jsonb;
  v_slug text;
begin
  if new.pack_composants is null then
    return new;
  end if;

  for v_item in select * from jsonb_array_elements(new.pack_composants)
  loop
    v_slug := nullif(trim(coalesce(v_item ->> 'slug', '')), '');

    if v_slug is null then
      raise exception 'un composant de pack doit designer un produit du catalogue';
    end if;

    if not exists (select 1 from public.catalogue c where c.slug = v_slug) then
      raise exception 'composant % inconnu du catalogue', v_slug;
    end if;

    if coalesce((v_item ->> 'quantite')::numeric, 0) <= 0 then
      raise exception 'un composant de pack doit etre en quantite positive';
    end if;

    -- Un pack qui entrerait dans sa propre recette bouclerait a l'infini au
    -- calcul des parts livrables.
    if v_slug = new.slug then
      raise exception 'un pack ne peut pas entrer dans sa propre recette';
    end if;
  end loop;

  return new;
end;
$$;

drop trigger if exists produits_pack_garde on public.produits;
create trigger produits_pack_garde
  before insert or update on public.produits
  for each row execute function mboa.controle_pack();

-- ----------------------------------------------------------------------------
-- 3. Combien de parts le stock permet-il de faire ?
--
-- Le plafond est l'ingredient le plus rare, pas la moyenne. Douze bottes de
-- ndole et deux crevettes font deux parts, et c'est ce chiffre-la que la
-- vitrine doit afficher : une part de plus serait un plat incomplet livre a
-- la porte.
-- ----------------------------------------------------------------------------
create or replace function mboa.parts_livrables(p_slug text)
returns numeric
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(
    min(
      floor(
        coalesce((select pr.quantite from public.produits pr where pr.slug = c ->> 'slug'), 0)
        / nullif((c ->> 'quantite')::numeric, 0)
      )
    )::numeric,
    0
  )
  from public.produits p,
       jsonb_array_elements(p.pack_composants) as c
  where p.slug = p_slug
    and p.pack_composants is not null
$$;

-- Apres chaque mouvement de stock, les packs reprennent le nombre de parts
-- que leur recette autorise. Une fonction appelee par les RPC, pas un
-- trigger : un trigger sur produits qui en met a jour d'autres produits se
-- rappelle lui-meme.
create or replace function mboa.recalculer_packs()
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_slug text;
begin
  for v_slug in select p.slug from public.produits p where p.pack_composants is not null
  loop
    update public.produits
       set quantite = mboa.parts_livrables(v_slug)
     where slug = v_slug
       and quantite is distinct from mboa.parts_livrables(v_slug);
  end loop;
end;
$$;

-- ----------------------------------------------------------------------------
-- 4. Le cout d'achat d'une part
--
-- La somme des ingredients au prix d'achat du stock. Sans cette colonne, la
-- marge d'un plat ne se lirait nulle part, et un pack vendu moins cher que
-- sa recette passerait inapercu.
-- ----------------------------------------------------------------------------
create or replace function mboa.cout_recette(p_composants jsonb)
returns integer
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(
    sum(
      (c ->> 'quantite')::numeric
      * coalesce((select pr.prix_achat from public.produits pr where pr.slug = c ->> 'slug'), 0)
    )::integer,
    0
  )
  from jsonb_array_elements(p_composants) as c
$$;

-- ----------------------------------------------------------------------------
-- 5. Le mouvement de stock d'une part
--
-- Un seul code pour les deux sens : `p_facteur` vaut -1 quand un devis est
-- valide (la part sort, les ingredients aussi) et +1 quand il est annule
-- (tout revient). Ecrire deux fonctions separees aurait garanti qu'oublier
-- l'une des deux desequilibre l'inventaire.
-- ----------------------------------------------------------------------------
create or replace function mboa.mouvement_pack(
  p_ligne jsonb,
  p_facteur integer
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_composant jsonb;
  v_slug      text;
  v_qte       numeric;
begin
  if p_facteur not in (-1, 1) then
    raise exception 'facteur de mouvement invalide';
  end if;

  for v_composant in
    select * from jsonb_array_elements(coalesce(p_ligne -> 'composants', '[]'::jsonb))
  loop
    v_slug := nullif(v_composant ->> 'slug', '');
    if v_slug is null then
      continue;
    end if;

    -- Une part demande la quantite de recette, autant de fois qu'il y a de
    -- parts dans la ligne.
    v_qte := abs((v_composant ->> 'quantite')::numeric)
             * abs(coalesce((p_ligne ->> 'quantite')::numeric, 1));

    if p_facteur < 0 then
      update public.produits
         set quantite = quantite - v_qte
       where slug = v_slug
         and quantite >= v_qte;

      if not found then
        raise exception 'plus assez de % pour ce pack', v_slug;
      end if;
    else
      update public.produits
         set quantite = quantite + v_qte
       where slug = v_slug;
    end if;
  end loop;

  perform mboa.recalculer_packs();
end;
$$;

comment on function mboa.mouvement_pack is
  'Sortie ou retour des ingrédients d''une part de pack. Appelé par valider_devis et annuler_devis (0010), jamais par le client.';

-- ----------------------------------------------------------------------------
-- 6. Composer et recomposer un pack, cote comptoir
--
-- L'admin est l'auteur du plat : il choisit les ingredients, les quantites,
-- le nom et le prix de la part. La fiche nait avec son nombre de parts
-- calcule sur le stock du jour, jamais saisi a la main.
-- ----------------------------------------------------------------------------
create or replace function mboa.creer_pack(
  p_nom text,
  p_categorie public.categorie_enum,
  p_composants jsonb,
  p_prix integer,
  p_photo_url text,
  p_audio_url text default null
)
returns public.produits
language plpgsql
security definer
set search_path = public
as $$
declare
  v_slug text;
  v_prod public.produits;
begin
  if not mboa.est_admin() then
    raise exception 'seul le comptoir compose un pack' using errcode = '42501';
  end if;

  if char_length(trim(p_nom)) not between 3 and 60 then
    raise exception 'un pack a besoin d''un nom, entre 3 et 60 lettres';
  end if;

  if jsonb_typeof(p_composants) <> 'array' or jsonb_array_length(p_composants) < 2 then
    raise exception 'un pack se compose d''au moins deux ingredients';
  end if;

  if p_prix is null or p_prix < 1 or p_prix > 1000000 then
    raise exception 'prix de la part invalide';
  end if;

  v_slug := mboa.slugifier(p_nom);
  if v_slug is null then
    raise exception 'ce nom ne peut pas devenir une cle de stock';
  end if;

  -- Un pack qui existerait deja n'est pas une nouvelle fiche : on recompose
  -- l'ancien. Deux « Pack Ndele » au stock seraient une faute d'inventaire,
  -- pas une offre de plus.
  if exists (select 1 from public.produits where slug = v_slug) then
    return mboa.modifier_pack(v_slug, p_composants, p_prix, p_photo_url, p_audio_url);
  end if;

  insert into public.produits
    (slug, nom, categorie, unite, quantite, prix, prix_achat,
     photo_reelle, audio_description_url, pack_composants, perissable, actif)
  values
    (v_slug, trim(p_nom), p_categorie, 'part', 0, p_prix,
     mboa.cout_recette(p_composants),
     p_photo_url, p_audio_url, p_composants, true, true);

  perform mboa.recalculer_packs();

  select * into v_prod from public.produits where slug = v_slug;
  return v_prod;
end;
$$;

create or replace function mboa.modifier_pack(
  p_slug text,
  p_composants jsonb,
  p_prix integer,
  p_photo_url text default null,
  p_audio_url text default null
)
returns public.produits
language plpgsql
security definer
set search_path = public
as $$
declare
  v_prod public.produits;
begin
  if not mboa.est_admin() then
    raise exception 'seul le comptoir recompose un pack' using errcode = '42501';
  end if;

  select * into v_prod from public.produits where slug = p_slug for update;
  if not found then
    raise exception 'pack % inconnu', p_slug;
  end if;

  if v_prod.pack_composants is null then
    raise exception '% n''est pas un pack', v_prod.nom;
  end if;

  update public.produits
     set pack_composants       = p_composants,
         prix                  = coalesce(p_prix, prix),
         prix_achat            = mboa.cout_recette(p_composants),
         photo_reelle          = coalesce(p_photo_url, photo_reelle),
         audio_description_url = coalesce(p_audio_url, audio_description_url)
   where slug = p_slug;

  perform mboa.recalculer_packs();

  select * into v_prod from public.produits where slug = p_slug;
  return v_prod;
end;
$$;

-- ----------------------------------------------------------------------------
-- 7. Le dernier mot sur les droits
--
-- `0005` retractait tout le schema mboa, mais il s'execute avant que les
-- RPC des devis (0010) et les fonctions de ce fichier existent : par defaut,
-- Postgres donne EXECUTE a `public` a toute fonction nouvelle. Ce bloc
-- remet donc le schema entier sous cle, puis ne rouvre que la liste nommee.
-- C'est la seule facon de garantir que rien, dans `mboa`, n'est appelable
-- par une cliente par accident d'oubli.
-- ----------------------------------------------------------------------------
revoke all on all functions in schema mboa from public, anon, authenticated;

grant execute on function mboa.role_utilisateur() to authenticated;
grant execute on function mboa.est_admin() to authenticated;
grant execute on function mboa.est_fournisseur() to authenticated;
grant execute on function mboa.est_consominateur() to authenticated;
grant execute on function mboa.parametre(text, text) to anon, authenticated;
grant execute on function mboa.contact_comptoir() to authenticated;

-- Cote agriculteur : il propose, il relit ses depots.
grant execute on function mboa.proposer_achat(text, public.categorie_enum, numeric, public.unite_enum, integer, text, text) to authenticated;
grant execute on function mboa.mes_achats() to authenticated;
grant execute on function mboa.mes_gains() to authenticated;

-- Cote cliente : la caisse et le pouce.
grant execute on function mboa.creer_devis(jsonb, boolean) to authenticated;
grant execute on function mboa.confirmer_reception(uuid, boolean, text, text) to authenticated;
grant execute on function mboa.liste_par_code(text) to authenticated;

-- Cote comptoir. Les trois la sont gardees en interne par un controle
-- `est_admin()` a l'interieur de chaque fonction : le droit d'appeler ne
-- donne pas le droit de decider.
grant execute on function mboa.valider_achat(uuid, integer, integer) to authenticated;
grant execute on function mboa.payer_achat(uuid) to authenticated;
grant execute on function mboa.refuser_achat(uuid, text, text, boolean) to authenticated;
grant execute on function mboa.valider_devis(uuid) to authenticated;
grant execute on function mboa.annuler_devis(uuid, text, text) to authenticated;
grant execute on function mboa.pointer_livraison(uuid, integer) to authenticated;
grant execute on function mboa.fermer_sur_delai(uuid) to authenticated;
grant execute on function mboa.devis_sans_confirmation(interval) to authenticated;
grant execute on function mboa.marge_devis(uuid) to authenticated;
grant execute on function mboa.creer_pack(text, public.categorie_enum, jsonb, integer, text, text) to authenticated;
grant execute on function mboa.modifier_pack(text, jsonb, integer, text, text) to authenticated;
grant execute on function mboa.parts_livrables(text) to authenticated;
grant execute on function mboa.affecter_livreur(uuid, uuid) to authenticated;
grant execute on function mboa.contact_livreur(uuid) to authenticated;

-- Rien de ce qui ecrit dans le stock ne sort du schema : `mouvement_pack`,
-- `recalculer_packs` et `cout_recette` restent appelees par les RPC seulement.
-- Sans cette ligne, une cliente fabriquerait ses parts ou gonflerait son
-- propre stock avant de payer.
comment on function mboa.mouvement_pack is
  'Interne. Retire ou rend les ingredients d''une part. Jamais callable par un client.';

commit;
