# Photos reelles des 9 produits du logo

Ce dossier n'est pas vide par accident : `pubspec.yaml` declare `assets/produits/`,
il faut donc au moins un fichier pour que le dossier survit au controle de version.

## Ce que l'app affiche aujourd'hui

Tant qu'aucune photo n'est presente ici, la grille 3x3 du fournisseur et la
vitrine du consommateur basculent sur le pictogramme SVG correspondant
(`assets/pictos/<produit>.svg`). C'est le comportement voulu par le design
system icon-first, et c'est aussi ce qui garantit que l'app reste lisible hors
connexion.

## Nomenclature exacte des 9 fichiers

Un fichier par produit, nom = valeur de `public.produit_enum`, PNG ou JPG,
cote court >= 600 px, photo reelle prise au champ :

| Fichier a deposer        | Produit du logo |
| ------------------------ | --------------- |
| `banane.png`             | Banane          |
| `plantain.png`           | Plantain        |
| `papaye.png`             | Papaye          |
| `pasteque.png`           | Pastèque        |
| `patate_douce.png`       | Patate douce    |
| `mandarine.png`          | Mandarine       |
| `pomme_de_terre.png`     | Pomme de terre  |
| `manioc.png`             | Manioc          |
| `macabo.png`             | Macabo          |

## Regle importante

Ces visuels ne sont que la **reference du catalogue** : ce que voit le
consommateur sur une annonce, c'est la photo du tas prise par le fournisseur
et filigranee par l'admin (`produits.photo_reelle` / `photo_filigranee` dans
le bucket Storage `produits`). Aucune photo generee ou d'illustration ne doit
tenir lieu de preuve de recolte : la confiance de la mama du marche repose sur
le fait que la photo montre le vrai tas.
