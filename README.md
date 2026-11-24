# Baganator AH

Ajoute un bouton **Scan HV** au-dessus des fenêtres de banque et de sacs de Baganator.

- **Clic gauche** : envoie tous les objets distincts affichés (personnage sélectionné dans Baganator,
  reroll compris) à Auctionator (`Auctionator.API.v1.MultiSearchExact`), qui les recherche dans une liste temporaire.
- **Clic droit** : ouvre (ou ferme) la fenêtre d'options.

## Installation
Copier le dossier `BaganatorAH` dans `World of Warcraft\_forever_\Interface\AddOns\`
(Auctionator, Baganator et Syndicator doivent être installés), puis `/reload`.

## Options
Les objets liés sont toujours ignorés : ils ne peuvent pas être vendus à l'HV.

- **Affichage** : boutons visibles seulement quand l'HV est ouvert.
- **Filtrer par rareté** : une case par rareté (Médiocre à Légendaire). Gris décoché par défaut.
- **Scanner uniquement** : équipement, composants d'artisanat, consommables.
  Seuls les objets des catégories cochées sont scannés ; aucune case cochée = tous les objets.
- **Filtrer des objets** : liste d'objets exclus du scan. Saisir un nom, un itemID, ou faire Maj+clic sur un
  objet, puis Entrée. Bouton X pour retirer ; molette pour faire défiler.

Si les boutons sont masqués (option « seulement à l'HV »), les options restent accessibles avec `/bah options`.

## Langues
Anglais, français, allemand, espagnol (Espagne et Mexique), italien, portugais (Brésil), russe, coréen,
chinois simplifié et traditionnel. Les textes sont dans `Locales.lua` ; une clé absente s'affiche en anglais.
Les sorties de diagnostic (`/bah who`, `/bah dump`, `/bah debug`) restent en anglais.

## Commandes (`/bah`)
| Commande | Effet |
|---|---|
| `/bah scan [bank\|bags] [Nom-Royaume]` | lance la recherche (fenêtre visible, ou personnage indiqué ; banque par défaut) |
| `/bah options` | ouvre la fenêtre d'options |
| `/bah quality <0-5>` | coche les raretés à partir de ce niveau (0 = gris, 1 = blanc, 2 = vert...) |
| `/bah attach` | relance la détection des fenêtres de banque et de sacs |
| `/bah who` | montre quel personnage est détecté dans la fenêtre Baganator (et comment) |
| `/bah dump [bank\|bags] [Nom-Royaume]` | diagnostic des données lues dans Syndicator |
| `/bah debug` | diagnostic (API trouvées, fenêtres détectées) |

## Si quelque chose ne marche pas
- « Rien à chercher » : le message indique ce qui a été ignoré (rareté, catégories, exclusions...). Vérifier les options.
- Le bouton des sacs n'apparaît pas ou ne trouve rien : `/bah debug` puis `/bah dump bags`.
- Le mauvais personnage est scanné : `/bah who`, fenêtre ouverte sur le reroll.
- Les boutons ont disparu : l'option « seulement à l'HV » est peut-être cochée (`/bah options`).
