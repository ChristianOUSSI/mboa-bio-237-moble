# MBOA BIO 237

Comptoir vivrier ultra-accessible pour le Cameroun. Une codebase Flutter, quatre APK, quatre roles qui se parlent en temps reel.

MBOA BIO **achete** chez l'agriculteur, a prix reduit et en quantite, met la marchandise en stock, puis la revend a la cliente finale en devis paye a la livraison. Ce n'est pas un marche ou chacun ouvre sa boutique : le fournisseur ne vend jamais a la cliente, et la cliente ne voit ni le producteur, ni le prix d'achat, ni la file d'attente du comptoir.

```
mboa_bio/
  lib/
    main.dart                  point d'entree, lit le flavor
    app/                       shell + ecran de garde au logo officiel
    core/
      config/                  AppEnv (--dart-define) et AppRole
      theme/                   les 6 couleurs, Nunito, les 72 px
      design_system/           pictos SVG, boutons, jauge, slider, photo
      voice/                   TTS, STT, note vocale de 5 s
      data/                    modeles, depots Supabase, SQLite offline-first
      temps_reel/              le canal commun aux trois apps
      etat/                    providers Riverpod
      utils/                   FCFA, telephones, uuid, telechargement
    features/
      auth/                    numero + visage + code vocal
      fournisseur/             l'app des agriculteurs qui vendent au comptoir
      admin/                   le comptoir : achats, stock, marge, devis
      consommateur/            l'app d'achat
      livreur/                 l'app de la moto : ses courses, ses jalons
      commun/                  le suivi de colis, partage par les trois autres
  supabase/migrations/         0001 a 0016, a coller dans l'editeur SQL
  assets/
    logo/                      le visuel fourni, tel quel
    pictos/                    46 SVG au trait, dont les 8 cases du catalogue
    produits/                  les photos reelles, a deposer
  android/                     flavors, permissions, splash natif
  tool/                        bootstrap, build et trois verificateurs statiques
  test/                        logique metier + invariants de charte
```

## Ou en est le portage

Le portage Dart suit desormais la base, ecran par ecran. Ce tableau dit ce qui est fini et ce qui reste a faire :

| | Etat |
| --- | --- |
| Migrations SQL | **ecrites pour le comptoir.** `0001` a `0016` portent le stock MBOA, la table `achats`, le debit de stock a la validation du devis et son retour en cas d'annulation, les huit categories, les onze unites, la marge, le suivi de colis, l'API publique et le fichier des fournisseurs. Le seed est coherent ligne par ligne : total = somme des lignes, marge calculee sur la part reellement gardee. |
| Vocabulaire Dart | **en place.** `Categorie` (8 cases), `Unite` (11 mesures), `StatutCommande` avec `annulee`, `StatutAchat`, `Achat`, `JalonSuivi`. Les huit pictogrammes de categorie et les cinq jalons du colis sont dessines. |
| Modeles, depots et ecrans Dart | **portes pour le comptoir.** Le fournisseur propose et suit ses achats, l'admin signe, paie, negocie, valide un devis, compose un pack et lit sa marge, la cliente n'achete que du stock final, le livreur pointe ses propres courses. Plus une lecture de `nom_enum` ni de `fournisseur_id` sur une commande. |

Le troisieme verificateur compare le contrat du devis en base aux cles que `LigneCommande.fromJson` lit reellement. Il est vert : une seule liste, et les deux cotes s'accordent (`produit_id`, `slug`, `nom`, `categorie`, `unite`, `quantite`, `prix`, `cout_achat`, `photo`, `composants`). Une cle ajoutee d'un cote sans l'autre fait echouer le script, ce qui vaut mieux qu'une valeur de repli silencieuse a l'ecran.

## Ce qui est verifie, ce qui ne l'est pas

Ce poste n'a ni Flutter SDK, ni JDK, ni SDK Android, ni instance Postgres. Il faut donc distinguer tres nettement :

| | Etat |
| --- | --- |
| Migrations SQL | **ecrites et relues, jamais executees.** Aucun Postgres ici. Un troisieme script en verifie la forme (colonnes contre valeurs, cles des JSONB contre le contrat du devis, vocabulaires SQL contre leurs jumeaux Dart), pas le fond. Les erreurs probables restent des details de syntaxe, pas de conception : la RLS, le cycle du devis, le debit de stock et la marge sont logiquement coherents. |
| Code Dart | **ecrit, passe en revue par trois verificateurs statiques, jamais compile.** Ni `flutter analyze`, ni `flutter test`. Voir ci-dessous ce que ces verificateurs voient et ne voient pas. |
| APK | **non produites.** Voir « Construire ». |
| Pictogrammes SVG | **generes et valides** : 46 fichiers, tous bien formes, tous avec un `<title>`, et chacun declare dans l'enum `Picto`. |
| Logo | **copie identique** a celle fournie, meme empreinte md5, dans `assets/logo/` et dans le splash natif Android. |
| Police | **Nunito variable telechargee** (277 Ko), table `fvar` lue : axe `wght`, 200 a 1000. Le Black 900 existe donc reellement. |
| Photos produits | **absentes.** La generation d'images etait hors quota sur ce compte. Tant que `assets/produits/` est vide, la grille et la vitrine affichent le pictogramme de la categorie du produit. |

### Ce que verifient les trois scripts de `tool/`

```powershell
node tool\verifier.mjs          # imports, symboles, assets, pictos, delimitateurs, mots reserves
node tool\verifier_appels.mjs   # chaque appel de widget face a son constructeur
node tool\verifier_sql.mjs      # chaque insert face a ses colonnes, chaque JSONB face a son modele
```

Ils voient : un import qui ne pointe nulle part, un symbole du projet utilise sans import, une classe declaree deux fois sous le meme nom public, un `package:` absent du pubspec, un chemin d'asset cite mais inexistant, un SVG sans entree dans l'enum `Picto` (et l'inverse), un fichier Dart dont les delimitateurs ne s'equilibrent pas, un `MonWidget(parametreInvente: ...)` la ou le constructeur ne declare pas ce parametre, une ligne `values` plus courte que sa liste de colonnes, une cle de panier JSONB que `LigneCommande.fromJson` ne lit pas, et un slug d'enum ecrit en SQL et oublie en Dart (ou l'inverse) sur `unite_enum`, `produit_enum`, `statut_enum`.

Ils ne voient pas : les API de Flutter et des paquets. Un `Slider` mal configure, un `CardTheme` devenu `CardThemeData`, une signature changee dans `record` ou `supabase_flutter` : rien de tout cela n'est detectable sans le SDK. C'est precisement pour ca que les dependances externes sont confinees dans `core/data/mboa_reseau.dart`, `core/temps_reel/hub_realtime.dart` et `core/voice/`.

Les trois scripts ont ete controles par un test negatif : une faute inventee dans un fichier temoin est bien signalee, puis le fichier est restaure. Un verificateur qui ne trouve rien et un verificateur qui ne cherche rien se ressemblent beaucoup.

Cette difference n'est pas theorique. `Unite.with(3)` s'est ecrit tout seul, parce qu'en francais « avec » se dit *with* : onze fichiers dependaient de cet appel, et `with` est un mot reserve Dart. Sans compilateur, seul un regle pouvait le savoir, la regle 9 de `verifier.mjs` l'interdit desormais. Le seed, lui, ecrivait encore `'kg'` dans ses paniers apres le passage aux unites : la demo se serait affichee avec des quantites a zero, sans une seule erreur. `verifier_sql.mjs` compare desormais chaque cle de panier aux `json['...']` que le modele lit reellement.

Deux dependances exterieures manquent au cahier des charges, et elles sont ecrites ici plutot que cachees dans un TODO :

1. **L'OTP vocal reel.** Un appel telephonique qui dicte le code exige une passerelle de telephonie (Twilio Voice, Africa's Talking) et une Edge Function. Sans elle, le code est genere et lu par le telephone lui-meme. Le flux complet, les ecrans et la verification sont identiques dans les deux modes : brancher la passerelle ne change aucun ecran.
2. **Le debit mobile money.** MTN MoMo et Orange Money se contractent via l'operateur ou un agregateur (PeduliPay, CinetPay, Hubtel). Le reglement se declare en especes a la porte ; les deux modes restent declares dans `paiement_enum` pour le jour ou un contrat sera signe. Les logos officiels des operateurs ne sont pas embarques : leur usage demande une autorisation ecrite.

## Construire

Il faut Flutter 3.22+, un JDK 17 et le SDK Android avec l'API 34. Le depot ne contient pas le wrapper Gradle (c'est un binaire) :

```powershell
cd mboa_bio

# 1. Recupere gradlew, le wrapper et les icones de lanceur.
#    Ne touche a aucun de nos fichiers : il ne copie que ce qui manque.
powershell -ExecutionPolicy Bypass -File tool\bootstrap_android.ps1

# 2. Les quatre APK.
powershell -File tool\build_apks.ps1 -Url https://XXXX.supabase.co -Cle eyJhbGciOi...
```

Sans `-Url` ni `-Cle`, les APK tournent en demonstration sur la SQLite du telephone : tous les ecrans sont navigables, rien ne se partage entre les quatre apps.

Le couple `--flavor` / `--dart-define` est obligatoire et doit rester d'accord. `--flavor admin` seul ouvre l'app cliente.

## Brancher Supabase

1. Projet neuf sur supabase.com, region `eu-west-2` (le plus proche de Douala).
2. SQL Editor, coller dans l'ordre : `0001` a `0007`. Un seul fichier par collage, dans l'ordre des numeros.
3. `0010_devis_stock.sql` : le cycle du devis, le debit de stock a la validation et son retour a l'annulation.
4. `0012_livreurs.sql`, puis `0013_packs.sql`, puis `0014_suivi_colis.sql`, puis `0015_api_publique.sql`, puis `0016_fournisseurs.sql`. Dans cet ordre strict : la 0014 pose les triggers du journal de bord sur les statuts que la 0010 et la 0012 ont definis, la 0015 ouvre les portes `public` que les apps appellent, et la 0016 fait de la fiche fournisseur la reference des achats, sans perdre les UUID deja en base.
5. `0011_demo_seed.sql` en test seulement, **en dernier** : il ecrit dans `stock_sorti`, `cout_achat`, `pack_composants`, `livreur_id` et la table `achats`, qui n'existent pas avant. Il cree cinq comptes dans `auth.users` a la main.
6. `Settings > API` : copier l'URL et la cle `anon`.
7. Auth > Providers : activer Phone. Un fournisseur SMS (Twilio) est requis pour le canal `sms` ; sans lui l'app bascule sur le canal `voix`.
8. `insert into mboa.parametres values ('telephone_comptoir', '+237…', '…') on conflict do nothing;`, sans cette ligne, le bouton « Appeler MBOA » de la cliente reste grise et le dit.

`0012` puis `0016` reecrivent tous deux la fonction `notifier()`, **dans son integralite**. Ce n'est pas un detail de style : `create or replace` remplace tout le corps, et une version partielle ferait disparaitre les notifications des achats, des devis et des listes. La derniere version qui s'execute gagne, d'ou l'ordre strict. La 0016 est seule a savoir que le destinataire d'une nouvelle d'achat est le profil de la fiche, pas l'identifiant de la fiche.

Les `ALTER TYPE ... ADD VALUE` n'existent plus dans ce depot : depuis la rewrite, `0001` declare d'emblee les six statuts de devis, les cinq statuts d'achat et les onze unites. Cette isolation etait une contrainte de migration en cours de route, plus une necessite quand la base se construit de zero.

Les roles ne sont pas des roles Postgres : `profiles.role` est une colonne, verifiee par les policies. Un compte `admin` se fabrique en passant `{"role":"admin"}` dans `raw_user_meta_data` a l'inscription, ou par un `update profiles set role='admin'` SQL.

## Les quatre parcours

**Agriculteur** : numero -> photo du visage -> code de 4 chiffres lu a voix haute -> trois gros boutons : **vendre ma recolte**, **mes achats**, **mon stock**. « Vendre ma recolte » tient en un ecran et n'impose jamais le clavier : photographier le tas a l'appareil, toucher une des huit cases a pictogramme, choisir l'unite, pousser la quantite et le prix au gros bouton, ajouter cinq secondes de voix si le prix se discute. Il ne fixe pas le prix de revente et ne voit jamais une cliente : ce qu'il envoie est une **proposition**, que le comptoir negocie, signe ou refuse avec une raison. « Mes achats » lui rend deux chiffres, ce qui est deja paye et ce qui reste a recevoir, et le statut de chaque ligne avec le motif du refus. « Mon stock » est en lecture seule : la quantite entre par la signature du comptoir, pas par un champ sur son telephone.

**Comptoir (admin)** : la file des achats d'abord, ce que les agriculteurs attendent, dans l'ordre des depots. Signer un achat fait trois choses dans la meme transaction : creer la fiche de stock si le produit n'y est pas encore, y entrer la quantite, et recalculer le prix d'achat en moyenne glissante. Ensuite le stock, avec pour chaque reference ce qu'elle a coute, ce qu'elle est vendue et ce qu'il en reste. Le fichier des fournisseurs lui permet d'ouvrir une fiche sans compte et de saisir l'achat au nom du producteur. Puis les devis arrives, les livraisons a pointer, les motos et les plats a composer. Le pointage saisit le montant reellement encaisse a la porte, par bonds de 50 francs.

**Consommatrice** : trois gestes. Toucher une case, toucher une tuile (photo du produit, prix a 44 px, haut-parleur qui dit « Bœuf, 14 kilos disponibles, 4 000 francs le kilo »), valider le panier. **Ni nom de producteur, ni village, ni visage** : elle achete a MBOA, et un panier peut desormais melanger le manioc de Mbouda et la chevre de Fee, puisque c'est un seul stock qui part. Puis le message court a la porte : « Ta commande est arrivée. Tout est bon ? », deux pouces. Et entre les deux, le suivi : cinq jalons, la moto qui approche, le nom et la plaque de celui qui arrive.

**Livreur** : numero -> code vocal -> une liste, ses courses du jour. Une course ouverte montre la cliente, son village, son panier, le montant a encaisser a la porte, et la timeline du colis avec un seul bouton utile, « j'approche ». Il ne cree rien, ne negocie rien, ne voit ni marge ni prix d'achat : sa plaque et son nom sont deja sur le telephone de la cliente.

## Le fichier des producteurs

Un fournisseur n'a plus besoin d'un compte pour vendre au comptoir. L'admin ouvre une fiche : nom, numero, village, production et unite habituelle, avec une photo. La fiche vit seule, et l'achat peut se faire sur elle (`proposer_achat_pour`) : le comptoir photographie la marchandise, note ce que le producteur a apporte et son prix, puis signe comme d'habitude.

Le jour ou la personne installe l'application avec le meme numero, `mboa.lier_fiche_fournisseur()` rattache la fiche a son profil. Aucun deuxieme fournisseur n'apparait, et les achats deja faits restent sur la fiche. Une fiche se retire, jamais ne se supprime.

Ce fichier ne sort pas du back-office : la cliente ne lit ni le nom du producteur, ni son village, ni son numero. La RLS ne rend une fiche qu'a l'admin et au profil qui y est rattache.

## L'argent : deux transactions au lieu d'une

Le comptoir fait deux operations que le marche ouvert melangeait. Les separer est ce qui rend la marge lisible, et la paye de l'agriculteur certaine.

```
ACHAT  chez l'agriculteur            DEVIS  chez la cliente
propose -> valide -> paye            nouvelle -> validee_admin -> en_livraison -> livree -> recue
                     (stock entre)    (stock sort a la validation)                1 tap
```

### L'achat

- **Le comptoir achete ferme.** `mboa.valider_achat` cree la fiche si besoin, ajoute la quantite au stock et recalcule `prix_achat` en **moyenne glissante** sur la quantite totale. Garder le dernier prix obtenu ferait croire a une marge qu'on n'a plus des la premiere entree plus chere.
- **Signer et payer sont deux temps.** La marchandise est au stock des la signature ; l'argent peut sortir le lendemain sans bloquer la vente. Un `achats.statut` qui melangerait les deux dirait faux soit au producteur, soit a l'inventaire.
- **Un refus laisse une raison.** Ecrite ou dite, obligatoire : un agriculteur qui ne sait pas pourquoi on lui a rendu sa chevre ne la represente plus, et le comptoir perd une source sans le savoir.
- **`achats.montant` est une colonne calculee.** Personne ne peut l'ecrire faussement, ni par erreur de frappe ni par faveur.

### Le devis

- **Rien n'est encaisse dans l'app.** Le reglement se declare en especes a la porte, et le comptoir le saisit en pointant la livraison.
- **Le stock sort a la validation, pas a la livraison.** Deux clientes ne peuvent pas acheter les trois derniers kilos de chevre. La colonne `stock_sorti` est la garde unique du retour : l'annulation rend la marchandise une fois, jamais deux.
- **`montant_livre` est distinct de `montant_total`.** La mama garde souvent moins que ce qu'elle a demande. L'ecart est une donnee, pas une erreur : c'est le seul moyen de savoir qu'une reference est surevaluee ou mal photographitee.
- **La marge suit la part gardee.** `mboa.marge_devis` proroge le cout d'achat sur `montant_livre / montant_total`. Sans cette proportion, un panier a moitie refuse afficherait une **marge negative** sur une vente normale, et le bilan du comptoir deviendrait une collection de fausses pertes. Le seed en porte un exemple exprès.
- **`clos` n'est vrai que sur le pouce de la cliente**, et une marge ne compte que close. Un devis non solde n'a pas de resultat.
- **12 heures de silence ne punissent personne.** Le comptoir peut clore sur delai, en tracant `clos_par = 'delai_comptoir'`.

### Ce que la cliente ne voit pas, et comment c'est garanti

Ce n'est pas un filtre d'app : `public.vitrine` ne selectionne **pas** les colonnes `prix_achat`, `fournisseur_id` des achats, ni les fiches inactive. Une colonne qui ne sort pas de la vue ne peut pas fuite par un client mal ecrit. Le numero d'un livreur, lui, ne sort que par `mboa.contact_livreur()`, et seulement pour la cliente concernee et le comptoir ; la table `livreurs` a perdu le privilege de lecture sur `telephone_237`, parce qu'une policy filtre des lignes et jamais des colonnes. La table `fournisseurs` reste fermee par la RLS a l'admin et au profil rattache : la cliente n'a aucune ligne a lire, et l'admin rappelle un numero par `mboa.telephone_livreur` ou par la fiche.

Le devis suit la meme regle depuis la 0015 : l'app cliente lit `commandes_clientes`, une vue qui retire `cout_achat` du total **et de chaque ligne du JSONB**. Le comptoir, lui, continue de lire `commandes` en direct, parce que son ecran de validation et son bilan en ont besoin.

Une limite reste, et elle est ecrite ici plutot que decouverte plus tard : `cout_achat` vit encore dans `commandes`. Une cliente qui interrogerait la table avec son propre jeton et sa propre cle anon retrouverait le cout de **ses** lignes, que la RLS lui rend. L'app ne le fait jamais, mais la fermeture complete demande de deplacer le cout dans une table privee, ce qui n'est pas fait ici : cela touche le cycle du devis, le seed et le bilan, et ne se blinde pas sans une base sur laquelle l'executer.

La timeline reste a quatre icones pour six etats : `recue` ferme la quatrieme au lieu d'en dessiner une cinquieme, et `annulee` n'en dessine aucune, un devis annule n'est pas une etape franchie, c'est un papier qui n'existe plus.

## Le suivi de colis

La cliente, le comptoir et le livreur regardent la meme marchandise sur la route, dans le meme journal. `public.suivi_colis` porte une ligne par commande et par jalon, avec son heure et son auteur, et un index sur `(commande_id, horodatage)` : la timeline se lit comme un carnet de bord, pas comme un flux a rejouer.

```
panier_prepare -> moto_partie -> en_approche -> arrive -> remis
   (trigger)       (trigger)     (le moto)     (trigger)  (pouce de la cliente)
```

Quatre jalons tombent tout seuls quand le statut de la commande bouge. `en_approche` est le seul geste manuel : le livreur le pose depuis sa course, ou le comptoir en relayant son appel, parce qu'une position GPS couterait la batterie d'un telephone de village et promettrait une precision qui s'eteint en route. Un jalon honnete vaut mieux qu'une carte qui ne se rafraichit plus.

Ce que chacun en voit, et c'est la meme fonction `mboa.peut_lire_course` qui repond aux trois portes :

- **la cliente** lit la timeline dans le suivi de son devis, sans pouvoir rien pointer. Elle voit la moto approcher, pas le telephone du livreur, qui ne sort que par `mboa.contact_livreur` ;
- **le comptoir** lit et pointe n'importe quelle course depuis sa file de livraisons ;
- **le livreur** ne voit que ses courses, et c'est lui qui pose `en_approche`.

Le composant est un seul widget, `TimelineColis`, employe par les trois apps : cinq pictogrammes, le jalon atteint plein et horodate, les autres en contour, une annonce vocale du dernier jalon. La cliente n'a donc rien de plus a apprendre le jour ou elle appelle le comptoir.

## La liste de marché

Une liste n'est pas un panier qui attend : c'est un papier. La mama la compose quand elle veut, sans rien commander, et elle existe alors sous deux formes.

Dans l'app, elle survit a la session et se modifie. Et surtout, elle devient un **devis PNG filigrane MBOA BIO 237**, genere sur le telephone par `GabaritListe` en `dart:ui`, au format du papier que les marchandes utilisent deja :

```
logo + « la terre nous nourrit, la qualité nous distingue »
Devis du marché de Maman ROSE
05/11/2026 · Chez Mama ELISE, Mbouda
┌────────────┬───────────┬───────────────┬────────┐
│ Article    │ Unité     │ Prix unitaire │ Total  │
│ Papaye     │ 2 kilos   │ 300 F         │ 600 F  │
│ Miondo     │ 5 paquets │ 700 F         │ 3 500 F│  <- dicte a la voix
│ Frais de livraison │ Petit Jean │ 500 F │ 500 F  │
└───────────────────────┴───────────────┴────────┘
QUI ARRIVE · Petit Jean · CD 8830 CM
À payer à la livraison  5 350 FCFA  (dont 500 F à la moto)
Code du devis  H K M P Q 2 3
[ Signature du vendeur ][ Signature du client ]
```

Quatre choix se discutent, et chacun tient a une raison de marche. **Le total par ligne** : le papier fait foi a la porte, la marchande doit le relire sans rien recalculer, un test verifie que le bandeau du bas est bien la somme des lignes. **Les cases de signature restent vides** : le papier se signe a la main, et ce ne sont pas des cases decoratives, c'est la raison pour laquelle ce document existe la ou personne n'a de terminal. **Pas de photos dans le tableau** : vingt-cinq lignes, c'etait vingt-cinq telechargements depuis le village avant que l'image existe, et un devis qui n'a pas pu se faire ne sert a rien ; les ecrans, eux, gardent les photos. **La course est une ligne du tableau**, pas une note au stylo, avec sa mention « dont X F à la moto » : la marchandise se paie au vendeur, la course au chauffeur.

Ce code est la piece utile. Sept caracteres, 16 symboles, et aucun de ceux qui se confondent a l'oral : pas de `o`, `i`, `l`, `0`, `1`, `5`, `9`. Une mama qui appelle l'agence dicte « h, k, m, p, q, 2, 3 » et l'agent retrouve son devis par `mboa.liste_par_code`, qui ne rend ni son numero ni son identite.

Elle l'envoie sur WhatsApp a sa fille, la montre au livreur, ou la dicte. « Commander cette liste » la convertit en commande sans que rien soit a recomposer, et la liste garde la trace de ce qui avait ete prepare a cote de ce qui a ete garde.

## Les unites, les packs et le livreur

Trois ajouts, une seule raison : le marche ne se compte pas en kilos, un plat prepare ne s'achete pas ingredient par ingredient, et une femme agee qui ouvre sa porte veut savoir qui arrive.

**Les unites.** `public.unite_enum` : `kg, boule, bouteille, botte, morceau, part, litre, paquet, plateau, regime, sachet`. Les colonnes se lisent `quantite` + `unite` et `prix`, plus `quantite_kg` ni `prix_kg` nulle part. Deux produits du logo derogeient deja du kilo, la pasteque a la piece, le macabo a la boule, et le catalogue porte `unite_defaut` + `unite_libelle` par reference pour que le marche corrige ce que le code croit savoir : l'arachide se compte en litres, l'œuf en plateaux, le plantain mûr en regimes, le miondo en paquets. Consequence sur toute la ligne : un panier mele s'affiche « 5 kilos · 2 parts », jamais « 7 ». Additionner deux unites dans un seul nombre est l'erreur la plus facile des qu'un pack entre dans le panier, et c'est une erreur que la cliente paie a la porte. L'article (« le kilo », « la boule », « le litre ») est une donnee de l'unite et non une regle ecrite dans chaque ecran : deux ecrans avaient deja commence a corriger l'article du kilo chacun de leur cote.

**Les huit cases.** `public.categorie_enum` : fruit, tubercule, legume, cereale, viande, poisson, huile, boisson. C'est la seule chose du catalogue qui soit fermee, et elle ferme la navigation, pas l'offre. Le logo montre neuf fruits ; le comptoir vend de la chevre, du poisson fume et du bissap. Le catalogue seme en porte **cent references** (14 fruits, 8 tubercules, 15 legumes et feuilles, 14 cereales et graines, 14 viandes et œufs, 12 poissons et fruits de mer, 14 huiles et condiments, 9 boissons et laitages) : une personne qui ne lit pas ne les cherche pas dans une liste de cent lignes, elle touche une case a pictogramme, puis une photo. Les huit dessins sont generes par `tool/gen_pictos.mjs` dans le meme trait que les autres icones, et `categories.ordre` est la seule source de la disposition, la viande et le poisson ne descendent pas en bas de page parce qu'ils ne sont pas sur l'affiche.

**Les lignes libres.** Sur un vrai devis de marche, vingt articles sur vingt-cinq ne sont pas des references du catalogue : haricot, igname, oignon, gingembre, poulet, tomate, ananas, œuf, viande de porc, miondo, pomme citon, mais, sel germe, clou de girofle. Une mama qui doit reprendre un carnet pour le reste n'a aucun interet a ouvrir l'app. Une ligne de liste ou de devis est donc soit une reference du stock (`slug` connu), soit une ligne nommee a la voix : `nom`, `categorie`, `unite` et `prix` declares. `mboa.creer_devis` verifie les quatre, refuse une ligne qui se pretend du stock et ne s'y trouve pas, et laisse le prix declare tel quel. C'est assume : le comptoir valide avant que la moto parte, et la marge ne se calcule que sur `montant_livre`, saisi a la porte. Le nom dicte est gele dans le JSON, pour que la ligne dise encore « Miondo » dans six mois plutot que la valeur de repli du catalogue.

**Les packs.** Un plat prepare n'est pas une table de plus. C'est une ligne du stock du comptoir qui se cuisine avec d'autres lignes : `nom` (« Pack Ndole »), `pack_composants` en JSONB gel par slug, `unite = 'part'`. La vitrine, la grille de categories, le panier, la caisse, le devis papier, la confirmation et le suivi fonctionnent sans rien savoir, et une `CHECK` interdit la ligne ni-produit-ni-pack. Le comptoir le compose dans `packs_screen.dart` en touchant les produits de son stock ; `mboa.controle_pack()` refuse un ingredient que le catalogue ne connait pas, et un pack qui entrerait dans sa propre recette. Le nombre de parts n'est jamais saisi : `mboa.parts_livrables` le plafonne a l'ingredient le plus rare (douze bottes de ndole et deux litres de crevettes font deux parts), et `mboa.recalculer_packs()` le reprend a chaque entree comme a chaque sortie. A la validation d'un devis, `mboa.mouvement_pack` retire les composants, pas le plat : le ndole reste du ndole dans l'inventaire. Cette fonction n'est accordee ni a `anon` ni a `authenticated`, seul le cycle du devis l'appelle, sinon n'importe quelle cliente fabriquerait ses parts.

**Le livreur.** Quatrieme APK, et la plus maigre des quatre : deux boutons, ma course, mon telephone. Le moto n'a rien a moderer, rien a composer, rien a vendre. Son compte se rattache a sa fiche par `livreurs.profil_id`, et `0014` le laisse lire et pointer **ses** courses seulement ; la RLS et les RPC le verifient a chaque appel, jamais l'app seule. `public.livreurs` reste une ressource que l'admin enregistre et affecte (`mboa.affecter_livreur` pose la moto et le statut `en_livraison` dans la meme transaction). Ce qui remonte jusqu'a la cliente est choisi pour la securite, pas pour le confort : **la plaque d'abord**, puis la moto, puis le nom. La carte « Qui arrive » dans le suivi, le bloc « QUI ARRIVE » du papier, et le numero de la course, la mama doit savoir ce qu'elle doit au moto en plus de sa marchandise, a l'ecran comme sur le devis. Le telephone d'un livreur ne sort de la base que par `mboa.contact_livreur`, pour les parties a la course, et `vitrine_livreurs` l'expose sans lui. On ne supprime jamais un livreur : on le desactive, pour que ses courses passees restent rattachables a quelqu'un.

## Ce qui tient hors connexion

Ecriture en local d'abord, serveur ensuite, file d'envoi sinon. La file est rejouee dans l'ordre a chaque retour de reseau, et un echec l'arrete au lieu de continuer : rejouer une modification avant sa propre creation casserait la ligne.

Une photo de tas non televeree reste sur le telephone. Elle ne se reconstitue pas le soir, et c'est la raison d'être de toute la file.

## Charte

Six couleurs, aucune autre. Les ratios mesures (et non estimes) sont dans `lib/core/theme/mboa_colors.dart`. Deux consequences operatoires :

- `#8BC34A` ne porte jamais de texte : 1.9:1 sur le beige. Il ne fait que des formes, des jauges et des points de carte.
- Le blanc ne va que sur du `#1E5128` (9.2:1). Sur le beige, le texte est `#212121` (14.8:1).

Les tests de `test/charte_test.dart` verifient ces regles, y compris qu'aucun style ne descend sous 18 px et qu'aucune cible ne passe sous 72 px.

## Regler les versions de paquets

Les contraintes du `pubspec.yaml` visent Flutter 3.22. Si `pub get` refuse une version :

```powershell
flutter pub upgrade --major-versions
```

Les trois endroits ou une montee de version peut demander une retouche de code sont concentres et documentes : `core/data/mboa_reseau.dart`, `core/temps_reel/hub_realtime.dart`, `core/voice/`. Aucun appel de paquet ne se fait ailleurs.

## Lancer les tests

```powershell
flutter test
```

`test/logique_test.dart` couvre la monnaie, les numeros camerounais, l'enum produit face au SQL, les onze unites du marche, le gel d'un pack, la ligne dictee a la voix, le total du devis, le repere d'un livreur et la machine a etats. `test/charte_test.dart` couvre les couleurs, la typo et les tailles de cible.
