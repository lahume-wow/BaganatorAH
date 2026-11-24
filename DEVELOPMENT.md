# Développer et publier Baganator AH

## Au quotidien

1. Modifier le code.
2. Tester en jeu : `./deploy.sh`, puis `/reload` dans WoW.
3. Noter ce qui change pour les joueurs dans `CHANGELOG.md`, sous `## Unreleased` (en anglais, une ligne par
   changement, par exemple `- Fix: the bag button now appears on the category view.`).
4. Commiter : `git add -A && git commit -m "Fix: ..."` puis `git push`.

Les notes de `## Unreleased` peuvent s'écrire au fil de l'eau ou juste avant la publication ; elles n'ont même pas
besoin d'être commitées, le script de publication s'en charge.

## Publier une version : une seule commande

```bash
./release.sh            # correctif           1.2.3 -> 1.2.4
./release.sh minor      # nouvelle fonction   1.2.3 -> 1.3.0
./release.sh major      # gros changement     1.2.3 -> 2.0.0
./release.sh beta       # version de test     1.2.3 -> 1.3.0-beta1, puis -beta2...
./release.sh 1.5.0      # numéro précis
./release.sh -n         # simulation : montre la version et les notes, ne change rien
```

Le script :

1. vérifie que tout est commité (sauf `CHANGELOG.md`), que vous êtes sur `main` et à jour avec GitHub, que le
   TOC contient votre pseudo et l'ID CurseForge, et la syntaxe Lua si `lua5.1` est installé ;
2. calcule le numéro de version à partir du dernier tag ;
3. prend les notes sous `## Unreleased` ; si cette section est vide, il utilise la liste des commits depuis la
   dernière version ;
4. affiche la version et les notes, et demande confirmation ;
5. range les notes sous `## vX.Y.Z - date` dans `CHANGELOG.md`, crée le commit « Release vX.Y.Z » et le tag,
   et envoie le tout sur GitHub ;
6. suit la publication sur GitHub Actions si l'outil `gh` est installé.

GitHub Actions fabrique alors le zip, crée la release GitHub et envoie le fichier sur CurseForge, avec comme
changelog **uniquement les notes de cette version**.

## Bêtas

`./release.sh beta` publie une version de test, marquée « Beta » sur CurseForge : seuls les joueurs qui ont choisi
de recevoir les bêtas la reçoivent. Pour la publier ensuite en version normale, lancez `./release.sh` : la
version finale reprend automatiquement les notes de toutes ses bêtas.

## En cas de problème

| Message | Que faire |
|---|---|
| des modifications ne sont pas commitées | `git add -A && git commit -m "..."` puis relancer |
| votre branche est en retard sur GitHub | `git pull` puis relancer |
| rien à publier | aucune note et aucun commit depuis la dernière version |
| la publication a échoué | `gh run view <numéro> --log-failed`, ou l'onglet Actions sur GitHub |

Une version publiée par erreur se corrige en publiant la suivante ; sur CurseForge, un fichier peut aussi être
archivé depuis la page du projet.

## Outils utiles (une seule fois)

```bash
sudo apt install -y lua5.1 gh   # vérification de la syntaxe Lua, suivi de la publication
gh auth login
```
