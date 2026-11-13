-- ============================================================================
-- MBOA BIO 237 - 0007 : buckets Storage et regles d'acces
-- Convention d'arborescence imposee par les policies :
--   <uuid-du-proprietaire>/<domaine>/<horodatage>.<ext>
-- Un fournisseur ne peut donc ecrire que dans son propre dossier.
-- ============================================================================

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values
  -- Photos des tas. Publiques : c'est la vitrine du marche.
  ('produits',   'produits',   true,  8388608,
     array['image/jpeg', 'image/png', 'image/webp']),

  -- Messages vocaux de 5 s. Publiques : le consommateur appuie sur le haut-parleur.
  ('audios',     'audios',     true,  1048576,
     array['audio/mpeg', 'audio/mp4', 'audio/ogg', 'audio/webm', 'audio/wav']),

  -- Photo du visage : donnee personnelle, jamais publique.
  ('visages',    'visages',    false, 4194304,
     array['image/jpeg', 'image/png']),

  -- Signature et photo de remise en main propre : preuve de livraison.
  ('preuves',     'preuves',   false, 8388608,
     array['image/jpeg', 'image/png'])
on conflict (id) do update set
  public             = excluded.public,
  file_size_limit    = excluded.file_size_limit,
  allowed_mime_types = excluded.allowed_mime_types;

-- ----------------------------------------------------------------------------
-- Lecture
-- ----------------------------------------------------------------------------
-- Les buckets 'produits' et 'audios' sont publics : pas de policy de select
-- necessaire, l'URL signee n'est pas requise pour la vitrine.

create policy "preuves et visages : proprietaire et admin"
  on storage.objects for select
  to authenticated
  using (
    bucket_id in ('visages', 'preuves')
    and (
      mboa.est_admin()
      or (storage.foldername(name))[1] = (select auth.uid())::text
      -- Le client d'une commande peut prouver qu'il a bien recu son panier.
      or exists (
        select 1 from public.commandes c
        where c.signature_url like '%' || storage.objects.name
           or c.photo_livraison_url like '%' || storage.objects.name
      )
    )
  );

-- ----------------------------------------------------------------------------
-- Ecriture
-- ----------------------------------------------------------------------------
create policy "fournisseur depose dans son dossier"
  on storage.objects for insert
  to authenticated
  with check (
    bucket_id in ('produits', 'audios', 'visages', 'preuves')
    and (storage.foldername(name))[1] = (select auth.uid())::text
  );

create policy "remplacement dans son dossier"
  on storage.objects for update
  to authenticated
  using (
    (storage.foldername(name))[1] = (select auth.uid())::text or mboa.est_admin()
  )
  with check (
    (storage.foldername(name))[1] = (select auth.uid())::text or mboa.est_admin()
  );

-- L'admin nettoie les photos non conformes ; le fournisseur retire sa recolte.
create policy "suppression par le proprietaire ou l'admin"
  on storage.objects for delete
  to authenticated
  using (
    mboa.est_admin()
    or (storage.foldername(name))[1] = (select auth.uid())::text
  );
