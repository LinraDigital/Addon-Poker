# LD - Poker (v1.0.1)

Texas Hold'em No Limit dans une taverne, entre joueurs proches. Les pièces d'or (PO) sont **fictives** : aucun or réel n'est échangé.

## Installation
Copier le dossier `LD_Poker` dans `World of Warcraft\_<version>_\Interface\AddOns\`. Interface : 16001.

## Commandes
- `/poker` (ou `/ldpoker`) : ouvrir / fermer la table
- `/poker scale 0.9` : taille de la fenêtre (0.5 à 1.5)
- `/poker reset` : remettre sa bourse à 1 000 PO et effacer sa dette

## Jouer
1. Formez un groupe (ou jouez seul contre des bots).
2. L'hôte règle les blindes et la cave, puis clique sur **Créer une table**. Il s'assoit automatiquement.
3. Les autres ouvrent `/poker`, cliquent sur **Rechercher** puis **Rejoindre**.
4. L'hôte peut ajouter des **bots**, puis clique sur **Lancer**. Les mains s'enchaînent toutes seules.
5. Le bouton **Aide** (en haut au centre) affiche le classement des mains avec des exemples.

Jusqu'à 7 joueurs. Si l'option « joueurs proches » est cochée (par défaut), il faut être à environ 28 m de l'hôte pour rejoindre ; un joueur trop loin est mis de côté pour la main suivante et se couche automatiquement quand vient son tour. Temps de parole : 30 s, puis « parler » si possible, sinon « se coucher ».

## Règles appliquées (résumé)
- Chaque joueur reçoit 2 cartes cachées, puis 5 cartes communes arrivent : flop (3), turn (1), river (1). Quatre tours d'enchères.
- Blindes : petite blinde à gauche du donneur, grosse blinde ensuite. En tête-à-tête, le donneur pose la petite blinde et parle en premier avant le flop.
- Mise minimale = grosse blinde. Une relance doit au moins égaler la dernière mise ou relance.
- Un tapis plus petit qu'une relance complète ne permet pas de re-relancer à ceux qui ont déjà parlé.
- Pots annexes automatiques quand un joueur est à tapis.
- Abattage : meilleure main de 5 cartes parmi 7. Égalité = pot partagé.

## Bourse et dettes
- Chaque personnage a une **bourse** fictive (1 000 PO au départ), sauvegardée entre les sessions.
- À la table, on ne joue que les jetons posés devant soi : **jamais de dette pendant une main**. Sans assez de jetons, on fait tapis.
- Si la bourse ne suffit pas pour une cave ou une **recave**, l'**aubergiste** prête la différence (jusqu'à 5 000 PO de dette).
- En quittant la table, les jetons reviennent dans la bourse et **remboursent d'abord la dette**. Le bouton **Rembourser** permet aussi de payer depuis la bourse.

## Limites connues
- L'hôte fait tourner la partie : techniquement, son client connaît toutes les cartes. À réserver à des joueurs de confiance.
- La bourse est stockée sur l'ordinateur de chaque joueur.
- Si l'hôte se déconnecte, la table disparaît (les jetons en jeu sont perdus). S'il ferme la table proprement, chacun récupère ses jetons, mises en cours comprises.
