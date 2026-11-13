-- ============================================================================
-- MBOA BIO 237 - 0011 : purge du jeu de demonstration et remise a zero
--
-- A executer UNE FOIS sur les bases ou le seed de demonstration a deja ete
-- joue. Il supprime toutes les donnees de test et remet le comptoir dans un
-- etat vierge : aucun produit, aucun fournisseur, aucun livreur, aucune commande.
--
-- Le catalogue de REFERENCE (table catalogue) est conserve : il ne s'agit pas
-- de donnees de test mais du referentiel produits et prix de base, sans
-- lequel l'application n'a rien a afficher au premier lancement.
--
-- Apres cette migration, la base est vierge. Le compte admin est cree par
-- l'application (mot de passe initial : admin123, a changer a la premiere
-- connexion sur chaque nouvel appareil).
-- ============================================================================

begin;

-- ----------------------------------------------------------------------------
-- Suppression des profils de demonstration, de leurs comptes auth et de leurs
-- donnees metier. L'ordre respecte les dependances.
-- ----------------------------------------------------------------------------

delete from mboa.notifications
 where destinataire in (
   '00000000-0000-0000-0000-0000000000a1'::uuid,
   '00000000-0000-0000-0000-0000000000f1',
   '00000000-0000-0000-0000-0000000000f2',
   '00000000-0000-0000-0000-0000000000f3',
   '00000000-0000-0000-0000-0000000000c1');

delete from public.listes
 where consommateur_id = '00000000-0000-0000-0000-0000000000c1'::uuid;

delete from public.commandes_clientes
 where consommateur_id = '00000000-0000-0000-0000-0000000000c1'::uuid;

delete from public.commandes
 where consommateur_id = '00000000-0000-0000-0000-0000000000c1'::uuid;

delete from public.achats
 where fournisseur_id in ('00000000-0000-0000-0000-0000000000f1'::uuid,
                          '00000000-0000-0000-0000-0000000000f2',
                          '00000000-0000-0000-0000-0000000000f3');

-- ----------------------------------------------------------------------------
-- Le stock et la vitrine : tout part, le comptoir repart de zero.
-- ----------------------------------------------------------------------------

delete from public.produits;

delete from public.vitrine;

delete from public.packs;

delete from public.fournisseurs;

delete from public.livreurs;

-- ----------------------------------------------------------------------------
-- Comptes de demonstration dans auth.users.
-- Les identifiants de demo sont supprimes ; les comptes reels sont conserves.
-- ----------------------------------------------------------------------------

delete from auth.users
 where id in (
   '00000000-0000-0000-0000-0000000000c1'::uuid,
   '00000000-0000-0000-0000-0000000000f1'::uuid,
   '00000000-0000-0000-0000-0000000000f2'::uuid,
   '00000000-0000-0000-0000-0000000000f3'::uuid,
   '00000000-0000-0000-0000-0000000000a1'::uuid);

commit;

-- ----------------------------------------------------------------------------
-- Verification : toutes ces requetes doivent renvoyer 0 ligne.
-- ----------------------------------------------------------------------------

select 'notifications' as tableau, count(*) as restant from mboa.notifications
union all select 'listes', count(*) from public.listes
union all select 'commandes', count(*) from public.commandes
union all select 'achats', count(*) from public.achats
union all select 'produits', count(*) from public.produits
union all select 'vitrine', count(*) from public.vitrine
union all select 'fournisseurs', count(*) from public.fournisseurs
union all select 'livreurs', count(*) from public.livreurs;
