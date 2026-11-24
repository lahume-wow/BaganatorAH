#!/usr/bin/env bash
# =====================================================================
#  Publie une nouvelle version de Baganator AH en une commande.
#
#  ./release.sh              version corrective   1.2.3 -> 1.2.4
#  ./release.sh minor        nouvelle fonction    1.2.3 -> 1.3.0
#  ./release.sh major        changement majeur    1.2.3 -> 2.0.0
#  ./release.sh beta         version de test      1.2.3 -> 1.3.0-beta1 -> 1.3.0-beta2...
#  ./release.sh 1.0.0        version précise
#
#  Options : --dry-run (-n) montre ce qui serait fait sans rien changer
#            --yes (-y)     ne demande pas de confirmation
#            --no-watch     ne suit pas la publication sur GitHub
#
#  Notes de version : ce que vous avez écrit sous "## Unreleased" dans
#  CHANGELOG.md. Si cette section est vide, la liste des commits depuis
#  la dernière version est utilisée.
#
#  Le script met à jour CHANGELOG.md, crée le commit et le tag, et les
#  envoie sur GitHub. GitHub Actions publie alors sur CurseForge.
# =====================================================================
set -euo pipefail
cd "$(dirname "$0")"

BUMP="patch"; DRY_RUN=0; ASSUME_YES=0; WATCH=1
BRANCH="main"
CHANGELOG="CHANGELOG.md"

usage() { sed -n '3,21p' "$0" | sed 's/^#  \{0,1\}//'; exit 0; }
die()   { printf '\033[31mErreur :\033[0m %s\n' "$*" >&2; exit 1; }
info()  { printf '\033[36m==>\033[0m %s\n' "$*"; }
warn()  { printf '\033[33mAttention :\033[0m %s\n' "$*" >&2; }

for arg in "$@"; do
  case "$arg" in
    -n|--dry-run) DRY_RUN=1 ;;
    -y|--yes) ASSUME_YES=1 ;;
    --no-watch) WATCH=0 ;;
    -h|--help) usage ;;
    -*) die "option inconnue : $arg (voir ./release.sh --help)" ;;
    *) BUMP="$arg" ;;
  esac
done

# ---------------------------------------------------------------------
# 1. Vérifications
# ---------------------------------------------------------------------
git rev-parse --git-dir >/dev/null 2>&1 || die "ce dossier n'est pas un dépôt git."

current_branch=$(git rev-parse --abbrev-ref HEAD)
[ "$current_branch" = "$BRANCH" ] || die "placez-vous sur la branche $BRANCH (actuellement : $current_branch)."

# Seul CHANGELOG.md peut avoir des modifications non commitées (vos notes).
dirty=$(git status --porcelain -- . ":(exclude)$CHANGELOG")
[ -z "$dirty" ] || die "des modifications ne sont pas commitées :
$dirty
Commitez-les (ou mettez-les de côté) avant de publier."

info "Récupération de l'état de GitHub..."
git fetch --quiet --tags origin || die "impossible de joindre GitHub (git fetch)."
if git rev-parse --verify --quiet "origin/$BRANCH" >/dev/null; then
  git merge-base --is-ancestor "origin/$BRANCH" HEAD \
    || die "votre branche est en retard sur GitHub : faites d'abord git pull."
fi

toc=$(ls ./*.toc 2>/dev/null | head -n1)
[ -n "$toc" ] || die "fichier .toc introuvable."
if grep -q "TON_PSEUDO" "$toc"; then
  die "remplacez TON_PSEUDO par votre pseudo dans $toc (ligne ## Author)."
fi
if ! grep -qE '^## X-Curse-Project-ID: *[0-9]+' "$toc"; then
  if [ "$DRY_RUN" = 1 ]; then
    warn "pas de ligne « ## X-Curse-Project-ID: <numéro> » dans $toc : CurseForge ne recevrait rien."
  else
    die "ajoutez « ## X-Curse-Project-ID: <numéro du projet> » dans $toc, sinon rien n'est envoyé sur CurseForge."
  fi
fi

# Vérification de la syntaxe Lua si un compilateur Lua est installé.
luac_bin=$(command -v luac5.1 || command -v luac || true)
if [ -n "$luac_bin" ]; then
  for f in ./*.lua; do
    "$luac_bin" -p "$f" || die "erreur de syntaxe dans $f."
  done
  rm -f luac.out
  info "Syntaxe Lua vérifiée ($(basename "$luac_bin"))."
else
  warn "syntaxe Lua non vérifiée (installez-la avec : sudo apt install lua5.1)."
fi

# ---------------------------------------------------------------------
# 2. Numéro de la nouvelle version
# ---------------------------------------------------------------------
last_tag=$(git describe --tags --abbrev=0 --match 'v[0-9]*' 2>/dev/null || true)
last="${last_tag#v}"
base="${last%%-*}"                       # 1.3.0-beta2 -> 1.3.0
pre=""; [ "$last" != "$base" ] && pre="${last#*-}"   # -> beta2

if [ -z "$last_tag" ]; then
  major=0; minor=0; patch=0
else
  IFS=. read -r major minor patch <<<"$base"
fi

case "$BUMP" in
  patch)
    if [ -z "$last_tag" ]; then new="1.0.0"
    elif [ -n "$pre" ]; then new="$base"                      # finalise la bêta
    else new="$major.$minor.$((patch + 1))"; fi ;;
  minor)
    if [ -z "$last_tag" ]; then new="1.0.0"
    elif [ -n "$pre" ] && [ "$patch" = 0 ]; then new="$base"  # 1.3.0-beta2 -> 1.3.0
    else new="$major.$((minor + 1)).0"; fi ;;
  major)
    if [ -z "$last_tag" ]; then new="1.0.0"
    elif [ -n "$pre" ] && [ "$minor" = 0 ] && [ "$patch" = 0 ]; then new="$base"
    else new="$((major + 1)).0.0"; fi ;;
  beta)
    if [[ "$pre" =~ ^beta([0-9]+)$ ]]; then
      new="$base-beta$((BASH_REMATCH[1] + 1))"
    elif [ -z "$last_tag" ]; then new="1.0.0-beta1"
    else new="$major.$((minor + 1)).0-beta1"; fi ;;
  [0-9]*.[0-9]*.[0-9]*)
    [[ "$BUMP" =~ ^[0-9]+\.[0-9]+\.[0-9]+(-(alpha|beta)[0-9]+)?$ ]] \
      || die "version invalide : $BUMP (exemples : 1.2.0, 1.3.0-beta1)."
    new="$BUMP" ;;
  *) die "type de version inconnu : $BUMP (patch, minor, major, beta ou X.Y.Z)." ;;
esac

tag="v$new"
git rev-parse -q --verify "refs/tags/$tag" >/dev/null && die "le tag $tag existe déjà."

# ---------------------------------------------------------------------
# 3. Notes de version
# ---------------------------------------------------------------------
[ -f "$CHANGELOG" ] || printf '# Changelog\n\n## Unreleased\n' > "$CHANGELOG"

# Section "## Unreleased" (jusqu'au titre ## suivant), sans lignes vides autour.
notes=$(awk '
  /^## / { if (inside) exit; if (tolower($2) == "unreleased") { inside = 1; next } }
  inside { print }
' "$CHANGELOG" | sed -e '/./,$!d' | sed -e :a -e '/^\n*$/{$d;N;ba' -e '}')

source_notes="section Unreleased de CHANGELOG.md"
if [ -z "$notes" ]; then
  range="${last_tag:+$last_tag..}HEAD"
  notes=$(git log --no-merges --reverse --pretty='- %s' "$range" | grep -v -E '^- Release v[0-9]' || true)
  source_notes="commits depuis ${last_tag:-le début}"
fi

# Version finale après des bêtas (ex. 1.1.0 après 1.1.0-beta1 et -beta2) :
# on y reprend les notes des bêtas, pour les joueurs qui ne les ont pas eues.
if [[ "$new" != *-* ]]; then
  beta_notes=$(awk -v prefix="v$new-" '
    /^## / { inside = (index($2, prefix) == 1); next }
    inside && NF { print }
  ' "$CHANGELOG")
  if [ -n "$beta_notes" ]; then
    notes=$(printf '%s\n%s\n' "$notes" "$beta_notes" | awk 'NF && !seen[$0]++')
    source_notes="$source_notes + notes des bêtas v$new"
  fi
fi
[ -n "$notes" ] || die "rien à publier : aucune note sous « ## Unreleased » et aucun commit depuis $last_tag."

kind="version"; [[ "$new" == *-* ]] && kind="version de test (bêta, marquée comme telle sur CurseForge)"
echo
info "Dernière version : ${last_tag:-aucune}"
info "Nouvelle $kind : $tag"
info "Notes ($source_notes) :"
echo "------------------------------------------------------------"
echo "$notes"
echo "------------------------------------------------------------"

if [ "$DRY_RUN" = 1 ]; then
  info "Simulation (--dry-run) : rien n'a été modifié."
  exit 0
fi

if [ "$ASSUME_YES" != 1 ]; then
  read -r -p "Publier $tag sur GitHub et CurseForge ? [o/N] " answer
  [[ "$answer" =~ ^[oOyY]$ ]] || { info "Annulé."; exit 0; }
fi

# ---------------------------------------------------------------------
# 4. CHANGELOG.md : les notes passent sous un titre daté, une section
#    "## Unreleased" vide est remise en haut pour la suite.
# ---------------------------------------------------------------------
today=$(date +%Y-%m-%d)
notes_file=$(mktemp)
printf '%s\n' "$notes" > "$notes_file"
tmp=$(mktemp)
awk -v header="## $tag - $today" -v notes_file="$notes_file" '
  function print_release() {
    print "## Unreleased"; print ""
    print header; print ""
    while ((getline line < notes_file) > 0) print line
    print ""
    done = 1
  }
  /^## / && !done {
    if (tolower($2) == "unreleased") { skipping = 1; next }
    print_release()
  }
  skipping && /^## / { skipping = 0 }
  skipping { next }
  { print }
  END { if (!done) print_release() }
' "$CHANGELOG" > "$tmp"
cat "$tmp" > "$CHANGELOG"
rm -f "$tmp" "$notes_file"

# ---------------------------------------------------------------------
# 5. Commit, tag, envoi
# ---------------------------------------------------------------------
git add "$CHANGELOG"
git commit --quiet -m "Release $tag"
git tag -a "$tag" -m "$tag" -m "$notes"
info "Envoi sur GitHub..."
git push --quiet origin "$BRANCH"
git push --quiet origin "$tag"

repo_url=$(git remote get-url origin | sed -E 's#^git@github.com:#https://github.com/#; s#\.git$##')
info "$tag envoyé. Publication en cours : $repo_url/actions"

# ---------------------------------------------------------------------
# 6. Suivi de la publication (si l'outil gh est installé)
# ---------------------------------------------------------------------
if [ "$WATCH" = 1 ] && command -v gh >/dev/null 2>&1; then
  info "Suivi de la publication (Ctrl+C pour arrêter de suivre, la publication continue)..."
  run_id=""
  for _ in 1 2 3 4 5 6; do
    sleep 5
    run_id=$(gh run list --workflow release.yml --branch "$tag" --limit 1 \
             --json databaseId --jq '.[0].databaseId' 2>/dev/null || true)
    [ -n "$run_id" ] && break
  done
  if [ -n "$run_id" ]; then
    if gh run watch "$run_id" --exit-status; then
      info "Publié : $tag est sur GitHub et envoyé à CurseForge."
    else
      die "la publication a échoué. Détails : gh run view $run_id --log-failed"
    fi
  else
    warn "publication introuvable pour l'instant ; suivez-la sur $repo_url/actions"
  fi
fi
