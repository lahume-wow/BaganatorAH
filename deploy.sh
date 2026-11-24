#!/usr/bin/env bash
# Copie l'addon depuis WSL vers le dossier AddOns de WoW Forever (Windows).
# Chemin différent ? Lancer : WOW_ADDONS="/mnt/d/Jeux/World of Warcraft/_forever_/Interface/AddOns" ./deploy.sh
set -euo pipefail
WOW_ADDONS="${WOW_ADDONS:-/mnt/c/Program Files (x86)/World of Warcraft/_forever_/Interface/AddOns}"
SRC="$(cd "$(dirname "$0")" && pwd)"

if [ ! -d "$WOW_ADDONS" ]; then
  echo "Dossier introuvable : $WOW_ADDONS" >&2
  echo "Indiquez le bon chemin avec WOW_ADDONS=... ./deploy.sh" >&2
  exit 1
fi

rsync -a --delete \
  --exclude '.git' --exclude '.github' --exclude '.gitignore' --exclude '.pkgmeta' \
  --exclude 'deploy.sh' --exclude '*.md' --exclude '.release' \
  "$SRC/" "$WOW_ADDONS/BaganatorAH/"
echo "Addon copié dans $WOW_ADDONS/BaganatorAH. Faites /reload en jeu."
