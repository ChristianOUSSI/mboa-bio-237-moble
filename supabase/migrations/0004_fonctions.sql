-- ============================================================================
-- MBOA BIO 237 - 0004 : fonctions internes, triggers et moteur d'achat
--
-- Ce fichier contient la moitie economique du produit : ce qui se passe
-- quand un agriculteur propose de la marchandise et quand le comptoir signe.
--
-- Toutes les fonctions lues par les policies sont SECURITY DEFINER : elles
-- lisent profiles sans declencher la policy de profiles, ce qui casse la
-- recursion RLS sur cette table.
--
-- Il n'y a plus de commission. Le comptoir ne preleve pas un pourcentage sur
-- une vente entre deux particuliers : il achete a un prix, il revend a un
-- autre, et la difference est sa seule richesse. Le calcul de marge se fait
-- donc a la validation du devis (0010), pas a l'insertion.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- Helpers de policy
-- ----------------------------------------------------------------------------
create or replace function mboa.role_utilisateur()
returns public.role_enum
language sql
stable
security definer
set search_path = public
as $$
  select p.role
  from public.profiles p
  where p.id = (select auth.uid())
$$;

create or replace function mboa.est_admin()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(mboa.role_utilisateur() = 'admin', false)
$$;

create or replace function mboa.est_fournisseur()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(mboa.role_utilisateur() = 'fournisseur', false)
$$;

create or replace function mboa.est_consominateur()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(mboa.role_utilisateur() = 'consommateur', false)
$$;

create or replace function mboa.est_livreur()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(mboa.role_utilisateur() = 'livreur', false)
$$;

-- Le livreur connecte, retrouve par le lien livreurs.profil_id. Renvoie null
-- quand le compte n'est rattache a aucune moto : un livreur sans fiche ne
-- porte aucune course, et ne doit donc rien voir ni pointer.
create or replace function mboa.livreur_de_session()
returns uuid
language sql
stable
security definer
set search_path = public
as $$
  select l.id
  from public.livreurs l
  where l.profil_id = (select auth.uid())
    and l.actif
  limit 1
$$;

-- ----------------------------------------------------------------------------
-- Les regles chiffrees du comptoir, lues au lieu d'etre gravées dans le code.
-- Modifier la marge visee ne doit jamais demander une nouvelle APK.
-- ----------------------------------------------------------------------------
create or replace function mboa.parametre(p_cle text, p_defaut text default '0')
returns text
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(
    (select valeur from mboa.parametres where cle = p_cle),
    p_defaut
  )
$$;

-- ----------------------------------------------------------------------------
-- Le nom dicté a la voix devient une cle de stock.
--
-- « Bœuf », « boeuf » et « BOEUF » doivent taper dans le meme tas, sinon le
-- comptoir se reveille avec trois stocks d'un meme produit et une marge
-- fausse sur chacun. `translate` n'etant pas capable de sortir deux lettres
-- pour une (œ → oe), le remplacement se fait avant.
-- ----------------------------------------------------------------------------
create or replace function mboa.slugifier(p_nom text)
returns text
language sql
immutable
as $$
  select nullif(
    trim(both '_' from
      regexp_replace(
        translate(
          lower(replace(replace(p_nom, 'œ', 'oe'), 'æ', 'ae')),
          'àáâäãåèéêëìíîïòóôõöùúûüçñ',
          'aaaaaaeeeeeeeeooooooouuuucn'
        ),
        '[^a-z0-9]+', '_', 'g'
      )),
    ''
  )
$$;

comment on function mboa.slugifier(text) is
  'Le nom parlé, réduit à une cle stable et sans accent. C''est la seule porte d''entrée d''un produit au stock.';

-- ----------------------------------------------------------------------------
-- Creation automatique du profil a l'inscription.
-- Le flux Flutter cree le compte avec le seul numero de telephone (OTP vocal),
-- puis envoie nom / village / photo de visage / langue. Le role vient du
-- flavor : il est passe dans user_metadata.role par le client d'inscription.
-- ----------------------------------------------------------------------------
create or replace function mboa.creer_profil()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_role public.role_enum;
begin
  v_role := coalesce(
    (new.raw_user_meta_data ->> 'role')::public.role_enum,
    'consommateur'
  );

  insert into public.profiles (id, role, nom, village, telephone_237, langue)
  values (
    new.id,
    v_role,
    -- Le nom arrive parfois vide : on met un marqueur plutot qu'une chaine
    -- vide, l'ecran suivant le corrige avant toute autre action.
    coalesce(nullif(new.raw_user_meta_data ->> 'nom', ''), 'NOUVEAU'),
    coalesce(nullif(new.raw_user_meta_data ->> 'village', ''), 'INCONNU'),
    new.phone,
    coalesce((new.raw_user_meta_data ->> 'langue')::public.langue_enum, 'fr')
  )
  on conflict (id) do nothing;

  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function mboa.creer_profil();

-- ----------------------------------------------------------------------------
-- updated_at automatique
-- ----------------------------------------------------------------------------
create or replace function mboa.touche_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

create trigger profiles_touch  before update on public.profiles  for each row execute function mboa.touche_updated_at();
create trigger produits_touch  before update on public.produits  for each row execute function mboa.touche_updated_at();
create trigger achats_touch    before update on public.achats    for each row execute function mboa.touche_updated_at();
create trigger commandes_touch before update on public.commandes for each row execute function mboa.touche_updated_at();

-- ============================================================================
-- LE MOTEUR D'ACHAT : ce qui remplace l'ancienne validation de recolte
--
-- L'agriculteur ne met plus rien en vente lui-meme. Il propose, le comptoir
-- signe, et la signature fait trois choses dans le meme ordre :
--   1. le produit rejoint le catalogue s'il n'y est pas encore ;
--   2. la quantite entre au stock disponible ;
--   3. le prix d'achat devient une moyenne glissante, pas le dernier prix
--      obtenu -- sinon une grosse commande bon marche ferait croire a une
--      marge qu'on n'a plus.
-- ============================================================================

create or replace function mboa.trouver_produit(p_slug text)
returns uuid
language sql
stable
security definer
set search_path = public
as $$
  select id from public.produits where slug = p_slug
$$;

-- ----------------------------------------------------------------------------
-- L'agriculteur propose : quoi, combien, comment, a quel prix.
-- Le prix passe a la caisse, la quantite aussi, et la photo comme la note de
-- cinq secondes sont obligatoires : c'est ce que l'admin regarde avant de
-- signer, personne n'achete du manioc sur une phrase.
-- ----------------------------------------------------------------------------
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
  v_slug text;
  v_achat public.achats;
begin
  if not mboa.est_fournisseur() then
    raise exception 'seul un agriculteur peut proposer une marchandise' using errcode = '42501';
  end if;

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
    (fournisseur_id, slug, nom, categorie, unite, quantite, prix_demande,
     photo_url, audio_url, statut)
  values
    ((select auth.uid()), v_slug, trim(p_nom), p_categorie, p_unite,
     p_quantite, p_prix_demande, p_photo_url, p_audio_url, 'propose')
  returning * into v_achat;

  return v_achat;
end;
$$;

comment on function mboa.proposer_achat is
  'La porte d''entrée d''un agriculteur : il dicte ce qu''il a, l''admin décide. Rien n''est visible aux clientes avant signature.';

-- ----------------------------------------------------------------------------
-- Le comptoir signe. C'est la seule facon de faire entrer de la marchandise
-- au stock, et la seule ou le prix d'achat se fige.
--
-- `p_prix_achat` est l'argument qui compte : l'admin peut marchander avant de
-- signer, et le prix demande par l'agriculteur n'est qu'une proposition.
-- ----------------------------------------------------------------------------
create or replace function mboa.valider_achat(
  p_achat_id uuid,
  p_prix_achat integer,
  p_prix_revente integer default null
)
returns public.achats
language plpgsql
security definer
set search_path = public
as $$
declare
  v_achat  public.achats;
  v_prod   public.produits;
  v_quantite_avant numeric := 0;
  v_cout_avant     integer := 0;
  v_nouveau_cout   integer;
  v_uid uuid := (select auth.uid());
begin
  if not mboa.est_admin() then
    raise exception 'seul le comptoir signe un achat' using errcode = '42501';
  end if;

  select * into v_achat from public.achats where id = p_achat_id for update;
  if not found then
    raise exception 'achat inconnu';
  end if;

  if v_achat.statut <> 'propose' then
    raise exception 'un achat au statut % ne se valide pas', v_achat.statut;
  end if;

  if p_prix_achat is null or p_prix_achat < 1 or p_prix_achat > 1000000 then
    raise exception 'prix d''achat invalide';
  end if;

  -- 1. La fiche produit, creee si personne ne l'avait encore vendue.
  select * into v_prod from public.produits where slug = v_achat.slug for update;

  if not found then
    insert into public.produits
      (slug, nom, categorie, unite, quantite, prix, prix_achat, photo_reelle, perissable)
    values
      (v_achat.slug, v_achat.nom, v_achat.categorie, v_achat.unite, 0,
       -- Pas de prix de revente sans indication de l'admin : le produit
       -- arrive au stock a zero franc et reste hors vitrine jusqu'a ce qu'on
       -- lui en donne un. C'est volontaire, un prix invente ici serait une
       -- decision prise a la place du comptoir.
       coalesce(p_prix_revente, 1),
       p_prix_achat,
       v_achat.photo_url,
       v_achat.categorie in ('viande', 'poisson', 'fruit', 'legume'))
    returning * into v_prod;

    -- Un prix de revente a zero n'est pas un prix : la fiche est marquee
    -- inactif tant que l'admin ne l'a pas chiffree.
    if p_prix_revente is null then
      update public.produits set actif = false where id = v_prod.id;
    end if;
  else
    v_quantite_avant := v_prod.quantite;
    v_cout_avant     := coalesce(v_prod.prix_achat, p_prix_achat);

    -- 2. Le cout moyen glissant. Une entree a 120 quand le stock est a 150
    --    pour 100 units ne doit pas effacer le stock precedent.
    if p_prix_revente is not null then
      update public.produits
         set prix = p_prix_revente, actif = true
       where id = v_prod.id;
    end if;
  end if;

  -- 3. L'entree, puis le cout moyen recalculé sur le stock total.
  update public.produits
     set quantite   = quantite + v_achat.quantite,
         prix_achat = round(
           (v_quantite_avant * v_cout_avant + v_achat.quantite * p_prix_achat)
           / nullif(v_quantite_avant + v_achat.quantite, 0)
         )::integer
   where id = v_prod.id
  returning * into v_prod;

  update public.achats
     set statut      = 'valide',
         prix_achat  = p_prix_achat,
         produit_id  = v_prod.id,
         unite       = v_achat.unite,
         valide_le   = now(),
         valide_par  = v_uid
   where id = p_achat_id
  returning * into v_achat;

  -- Une entree change le nombre de parts que les plats permettent de faire.
  perform mboa.recalculer_packs();

  return v_achat;
end;
$$;

comment on function mboa.valider_achat is
  'Entrée de stock. Le prix d''achat devient une moyenne glissante sur la quantité totale, jamais le dernier prix obtenu.';

-- ----------------------------------------------------------------------------
-- Le payement est un temps distinct de la signature : la marchandise est
-- deja au stock, l'argent peut sortir le lendemain sans bloquer la vente.
-- ----------------------------------------------------------------------------
create or replace function mboa.payer_achat(p_achat_id uuid)
returns public.achats
language plpgsql
security definer
set search_path = public
as $$
declare
  v_achat public.achats;
begin
  if not mboa.est_admin() then
    raise exception 'seul le comptoir enregistre un payement' using errcode = '42501';
  end if;

  select * into v_achat from public.achats where id = p_achat_id for update;
  if not found then
    raise exception 'achat inconnu';
  end if;

  if v_achat.statut <> 'valide' then
    raise exception 'on ne paie que ce qui a été signé, pas un achat %', v_achat.statut;
  end if;

  update public.achats
     set statut  = 'paye',
         paye_le = now(),
         paye_par = (select auth.uid())
   where id = p_achat_id
  returning * into v_achat;

  return v_achat;
end;
$$;

-- ----------------------------------------------------------------------------
-- Refuser ou contester une marchandise. Le stock ne bouge pas : rien n'est
-- jamais entre. Une raison est obligatoire, écrite ou dite, parce qu'un
-- agriculteur qui ne sait pas pourquoi on lui a rendu sa chèvre ne la
-- représente plus.
-- ----------------------------------------------------------------------------
create or replace function mboa.refuser_achat(
  p_achat_id uuid,
  p_motif text default null,
  p_motif_audio_url text default null,
  p_litige boolean default false
)
returns public.achats
language plpgsql
security definer
set search_path = public
as $$
declare
  v_achat public.achats;
begin
  if not mboa.est_admin() then
    raise exception 'seul le comptoir refuse une marchandise' using errcode = '42501';
  end if;

  select * into v_achat from public.achats where id = p_achat_id for update;
  if not found then
    raise exception 'achat inconnu';
  end if;

  if v_achat.statut in ('paye', 'valide') then
    raise exception 'un achat déjà signé ne se refuse plus: passer par le litige' using errcode = '42501';
  end if;

  if coalesce(char_length(nullif(trim(p_motif), '')), 0) < 3
     and p_motif_audio_url is null then
    raise exception 'un refus exige une raison, écrite ou dite';
  end if;

  update public.achats
     set statut          = case when p_litige then 'litige' else 'annule' end,
         motif           = nullif(trim(p_motif), ''),
         motif_audio_url = p_motif_audio_url
   where id = p_achat_id
  returning * into v_achat;

  return v_achat;
end;
$$;

-- ----------------------------------------------------------------------------
-- L'agriculteur relit ses propres propositions, et le compte de ce que le
-- comptoir lui doit. Pas de vue sur les ventes : il ne connait ni le prix de
-- revente, ni les clientes.
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
  where a.fournisseur_id = (select auth.uid())
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
  where a.fournisseur_id = (select auth.uid());
$$;

-- ----------------------------------------------------------------------------
-- Contact chiffre : un numero n'est jamais lisible en clair par un tiers.
-- La cliente n'appelle plus un producteur (elle n'en connait pas) : elle
-- appelle le comptoir, dont le numero est un parametre, et le livreur dont
-- le numero sort par 0012.
-- ----------------------------------------------------------------------------
create or replace function mboa.contact_comptoir()
returns text
language sql
stable
security definer
set search_path = public
as $$
  select mboa.parametre('telephone_comptoir', '')
$$;

comment on function mboa.contact_comptoir() is
  'Le numéro que la cliente touche pour appeler MBOA BIO. Vide tant que l''admin ne l''a pas enregistré dans mboa.parametres.';
