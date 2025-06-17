#!/bin/bash
errors=()
cmd=()
declare -A cmds_by_module
current_module=""
# ───────────────────────────────────────────────
# 🎯 Fonction pour pull avec retries
# ───────────────────────────────────────────────
try_git_pull() {
  local branch="$1"
  local module="$2"
  for i in {1..3}; do
      if git pull origin "$branch"; then
        log_cmd "git pull origin "$branch""
        return 0
      fi
    sleep 3
  done
  log_error "❌ Échec de git pull après 3 tentatives sur le module $module"
  return 1
}
log_error() {
  local message="$1"
  errors+=("$message")
}
log_cmd() {
  local cmd="$1"
  cmds_by_module["$current_module"]+="$cmd"$'\n'
}
module_in_progress() {
  local nameModule="$1"
  current_module="$nameModule"
      echo -e "\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
      echo "🔍 Traitement du module : $nameModule"
      echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
}
dolibarr_in_progess() {
  local dolibarr_dir="$1"
    echo -e "\n============================================"
    echo "🚀 Lancement sur $dolibarr_dir"
    echo "============================================"
}
update_modules() {
  # ─────────────────────────────────────────────────────────────
  # 🎛️ CONFIGURATION
  # ─────────────────────────────────────────────────────────────
  local dolibarr_base_path="$1"
  local api_key="$2"
  local url_base="$3"
  local module_manager_entity="$4"

  if [[ ! -d "$dolibarr_base_path/htdocs/custom" ]]; then
    log_error "❌ Dossier $dolibarr_base_path/htdocs/custom introuvable"
    return
  fi

  local modules_path="$dolibarr_base_path/htdocs/custom"
  local initial_dir
  initial_dir=$(pwd)
  for module_full_path in "$modules_path"/*/; do
    module_path="${module_full_path%/}"
    nameModule=$(basename "$module_path")

    module_in_progress "$nameModule"

    response=$(curl -s -X GET \
      --header 'Accept: application/json' \
      --header "DOLAPIKEY: $api_key" \
      -w '\nHTTP_STATUS:%{http_code}' \
      "${url_base}/webhostapi/getWebModuleByInstallName?nameModule=${nameModule}")
    http_status=$(echo "$response" | grep HTTP_STATUS | cut -d':' -f2)

    if [ "$http_status" -eq 401 ]; then
      log_error "❌ Erreur 401 : Vérifiez votre connexion VPN ATM."
      return
    elif [ "$http_status" -ne 200 ]; then
      log_error "❌ $nameModule -> Erreur HTTP ($http_status)"
      cd "$initial_dir"
      continue
    fi

    response_json=$(echo "$response" | sed '$d')
    git_url=$(echo "$response_json" | grep -o '"git_url"[ ]*:[ ]*"[^"]*"' | cut -d':' -f2- | tr -d ' "')
    latest=$(echo "$response_json" | grep -o '"module_version"[ ]*:[ ]*"[^"]*"' | head -n 1 | cut -d':' -f2 | tr -d ' "')

    # Si la variable est déjà définie (non vide), ne pas réassigner
    if [[ -z "$latest" ]]; then
        latest=$(echo "$response_json" | sed -n 's/.*"version"[ ]*:[ ]*"\([^"]*\)".*/\1/p')
    fi

    if [ -d "$module_path/.git" ]; then
      cd "$module_path" || continue
#      Check sur le propriétaire du repertoire, -> voir si utile
#      current_user=$(whoami)
#      owner=$(stat -c '%U' "$module_path")
#      if [[ "$owner" != "$current_user" ]]; then
#        echo "❌ Propriétaire ($owner) différent de l'utilisateur courant ($current_user), passage au module suivant."
#        continue
#      fi
      current_remote=$(git remote get-url origin)
      if [ "$current_remote" != "$git_url" ]; then
        log_error "❌ $nameModule -> L'URL distante ($current_remote) est différente de l'URL attendue ($git_url)."
        cd "$initial_dir"
        continue
      fi
      # Si "latest" est vide, Passage au module suivant.
       if [[ -z "$latest" ]]; then
        log_error "❌ $nameModule -> Aucune branche par défaut trouvée."
        cd "$initial_dir"
        continue
       fi
      if [ "$dry_run" = true ]; then
        echo "[DRY-RUN] git reset --hard"
      else
        log_cmd "git reset --hard"
        git reset --hard
      fi
      if [[ -n "$latest" ]]; then
        current_branch=$(git rev-parse --abbrev-ref HEAD | tr -d '[:space:]')
        latest=$(echo "$latest" | tr -d '[:space:]')
        # Si on est déjà sur la bonne branche : simple pull
        if [[ "$current_branch" == "$latest" ]]; then
            if [ "$dry_run" = true ]; then
                echo "[DRY-RUN] git pull"
            else
                try_git_pull "$latest" "$nameModule"
            fi
        else
            # On vérifie que la branche existe bien sur le remote (précaution supplémentaire)
            if ! git ls-remote --exit-code --heads origin "$latest" &> /dev/null; then
              echo "git ls-remote --exit-code --heads origin "$latest""
                log_error "❌ $nameModule -> La branche $latest n'existe pas sur le remote."
                cd "$initial_dir"
                continue
            fi
            # On s’assure que la référence origin/$latest est à jour (toujours faire un fetch)
            if [ "$dry_run" = true ]; then
                echo "[DRY-RUN] git fetch origin +refs/heads/$latest:refs/remotes/origin/$latest"
                echo "[DRY-RUN] git checkout -B \"$latest\" origin/$latest"
            else
                log_cmd "fetch origin +refs/heads/"$latest":refs/remotes/origin/"$latest""
                log_cmd "checkout -B $latest"
                git fetch origin +refs/heads/"$latest":refs/remotes/origin/"$latest"
                git checkout -B "$latest" origin/"$latest"
            fi
        fi
      fi
      cd "$initial_dir" || exit
      class_name=$(echo "$nameModule" | awk '{print toupper($0)}')
      core_dir="${module_path}/core"
    if [[ "$skip_activation" != true ]]; then
      if [[ -f $module_manager_entity ]]; then
        if [[ -n "$class_name" && -d "$core_dir" ]]; then
          class_file=$(find "$core_dir" -type f -iname "mod${class_name}.class.php" | head -n 1)
          if [[ -n "$class_file" ]]; then
            class_filename=$(basename "$class_file")
            real_class_name="${class_filename%.class.php}"
            run_mode="false"
            if [ "$dry_run" = true ]; then
              run_mode="true"
            fi
            php "$module_manager_entity" "$dolibarr_base_path" "$real_class_name" "$run_mode"
          else
            log_error "❌ $nameModule -> Aucun fichier mod${class_name}.class.php trouvé dans $core_dir"
          fi
        else
          log_error "❌ $nameModule -> Classe du module non déterminée ou dossier core/ manquant."
        fi
      else
        log_error "❌ $nameModule -> Fichier module_manager_entity.php introuvable."
      fi
    fi
    else
      log_error "❌ $nameModule -> n'est pas un dépôt Git. Aucune mise à jour possible."
    fi
  done
}

# ───────────────────────────────────────────────
# 🏁 Parsing des arguments
# ───────────────────────────────────────────────
dry_run=false
for arg in "$@"; do
  if [[ "$arg" == "--dry-run" ]]; then
    dry_run=true
    echo "🔍 Mode simulation activé (dry-run)"
  elif [[ "$arg" == "--no-activation" ]]; then
    skip_activation=true
  fi
done
# ───────────────────────────────────────────────
# ▶️ Appel de la fonction principale
# ───────────────────────────────────────────────
# Chemin de base où sont tous les Dolibarr à traiter
base_dir="/home/client/pack_git/"
api_key="klI0NMf92Ky6nfO326nBa8S2hVKi3KMz"
url_base="http://localhost/client/doliboard/dolibarr/htdocs/api/index.php"
module_manager_entity="/home/client/pack_git/script_checkout/module_manager_entity.php"

# Boucle sur tous les dossiers Dolibarr dans ce chemin
for dolibarr_dir in "$base_dir"/*/; do
  if [[ ! -d "$dolibarr_dir" ]]; then
    continue
  fi
  if [[ ! -d "$dolibarr_dir/htdocs/custom" ]]; then
    log_error "⚠️ $(basename "$dolibarr_dir") ne contient pas de dossier htdocs/custom, ignoré."
    continue
  fi
  dolibarr_in_progess "$(basename "$dolibarr_dir")"
  update_modules "$dolibarr_dir" "$api_key" "$url_base" "$module_manager_entity"
done

if (( ${#cmds_by_module[@]} > 0 )); then
  echo -e "\n📘 Commandes exécutées par module :"
  if [[ "$skip_activation" = true ]]; then
    echo "⛔ Mode sans activation activé (pas d'appel à module_manager_entity.php)"
  fi
  for module in "${!cmds_by_module[@]}"; do
    echo -e "\n🔧 $module :"
    echo -e "${cmds_by_module[$module]}"
  done
fi

if (( ${#errors[@]} > 0 )); then
  echo -e "\n📦 Total des erreurs : ${#errors[@]}"
  echo -e "\n🚨 Résumé des erreurs :"
  for err in "${errors[@]}"; do
    echo "$err"
  done
else
  echo -e "\n✅ Aucune erreur détectée."
fi