#!/bin/bash

# ───────────────────────────────────────────────
# 🎯 Fonction pour pull avec retries
# ───────────────────────────────────────────────
try_git_pull() {
  local branch="$1"
  for i in {1..3}; do
    echo "🌀 Tentative $i de git pull..."
    git pull origin "$branch" && return 0
    sleep 3
  done
  echo "❌ Échec de git pull après 3 tentatives"
  return 1
}

update_modules() {
  # ─────────────────────────────────────────────────────────────
  # 🎛️ CONFIGURATION
  # ─────────────────────────────────────────────────────────────
  apikey="VdKb0uBoO4vtV01mgA8x8QibKE1364GJ"
  url_base="https://testatm.srv138.atm-consulting.fr/api/index.php"
  local dolibarr_base_path="$1"

  if [[ ! -d "$dolibarr_base_path/htdocs/custom" ]]; then
    echo "❌ Dossier $dolibarr_base_path/htdocs/custom introuvable"
    return
  fi

  local modules_path="$dolibarr_base_path/htdocs/custom"
  local initial_dir
  initial_dir=$(pwd)

  echo "🔁 Parcours des modules dans : $modules_path"

  echo -e "\n🚀 DÉMARRAGE DE LA MISE À JOUR DES MODULES DANS : $modules_path\n"

  for module_full_path in "$modules_path"/*/; do
    module_path="${module_full_path%/}"
    nameModule=$(basename "$module_path")

    echo -e "\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "🔍 Traitement du module : $nameModule"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

    response=$(curl -s -X GET \
      --header 'Accept: application/json' \
      --header "DOLAPIKEY: $apikey" \
      -w '\nHTTP_STATUS:%{http_code}' \
      "${url_base}/webhostapi/getWebModuleByInstallName?nameModule=${nameModule}")
    http_status=$(echo "$response" | grep HTTP_STATUS | cut -d':' -f2)

    if [ "$http_status" -eq 401 ]; then
      echo "❌ Erreur 401 : Vérifiez votre connexion VPN ATM."
      continue
    elif [ "$http_status" -ne 200 ]; then
      echo "❌ Erreur HTTP ($http_status) pour $nameModule"
      continue
    fi

    response_json=$(echo "$response" | sed '$d')
    git_url=$(echo "$response_json" | grep -o '"git_url"[ ]*:[ ]*"[^"]*"' | cut -d':' -f2- | tr -d ' "')
    latest=$(echo "$response_json" | grep -o '"module_version"[ ]*:[ ]*"[^"]*"' | head -n 1 | cut -d':' -f2 | tr -d ' "')
    echo "----- $git_url pour $latest ------"
#
#    # Si la variable est déjà définie (non vide), ne pas réassigner
#    if [[ -z "$latest" ]]; then
#        latest=$(echo "$response_json" | sed -n 's/.*"version"[ ]*:[ ]*"\([^"]*\)".*/\1/p')
#    fi
#
    if [ -d "$module_path/.git" ]; then
      echo "✅ $nameModule est déjà un dépôt Git."
      cd "$module_path" || continue

#      current_user=$(whoami)
#      owner=$(stat -c '%U' "$module_path")
#      if [[ "$owner" != "$current_user" ]]; then
#        echo "❌ Propriétaire ($owner) différent de l'utilisateur courant ($current_user), passage au module suivant."
#        continue
#      fi

      current_remote=$(git remote get-url origin)
      if [ "$current_remote" != "$git_url" ]; then
        echo "❌ L'URL distante ($current_remote) est différente de l'URL attendue ($git_url). Passage au module suivant."
        cd "$initial_dir"
        continue
      fi
      if [ "$dry_run" = true ]; then
        echo "[DRY-RUN] git reset --hard"
      else
        echo "git reset --hard"
        git reset --hard
      fi

      if [[ -n "$latest" ]]; then
        echo "🌿 Tentative checkout sur la release : $latest"
        current_branch=$(git rev-parse --abbrev-ref HEAD | tr -d '[:space:]')
        latest=$(echo "$latest" | tr -d '[:space:]')

        echo "$current_branch == $latest"

      # Si "latest" est vide, Passage au module suivant.
       if [[ -z "$latest" ]]; then
         echo "❌ Aucune branche par défaut trouvée. Passage au module suivant."
         continue
       fi

        # Si on est déjà sur la bonne branche : simple pull
        if [[ "$current_branch" == "$latest" ]]; then
            echo "🔄 La branche $latest est déjà checkout. Mise à jour..."
            if [ "$dry_run" = true ]; then
                echo "[DRY-RUN] git pull"
            else
                echo "git pull"
                try_git_pull "$latest"
            fi
        else
            echo "📥 Changement de branche vers $latest"

            # On vérifie que la branche existe bien sur le remote (précaution supplémentaire)
            if ! git ls-remote --exit-code --heads origin "$latest" &> /dev/null; then
                echo "❌ La branche $latest n'existe pas sur le remote. Passage au module suivant."
                continue
            fi

            # On s’assure que la référence origin/$latest est à jour (toujours faire un fetch)
            if [ "$dry_run" = true ]; then
                echo "[DRY-RUN] git fetch origin +refs/heads/$latest:refs/remotes/origin/$latest"
                echo "[DRY-RUN] git checkout -B \"$latest\" origin/$latest"
            else
                echo "fetch origin/$latest"
                git fetch origin +refs/heads/"$latest":refs/remotes/origin/"$latest"
                echo "checkout -B $latest"
                git checkout -B "$latest" origin/"$latest"
            fi
        fi
      fi
      cd "$initial_dir" || exit
      echo -e "✅ Fin du traitement GIT du module : $nameModule"

      class_name=$(echo "$nameModule" | awk '{print toupper($0)}')
      core_dir="${module_path}/core"

      if [[ -f "/home/client/pack_git/script_checkout/module_manager_entity.php" ]]; then
        if [[ -n "$class_name" && -d "$core_dir" ]]; then
          class_file=$(find "$core_dir" -type f -iname "mod${class_name}.class.php" | head -n 1)
          if [[ -n "$class_file" ]]; then
            class_filename=$(basename "$class_file")
            real_class_name="${class_filename%.class.php}"
            echo "📁 Fichier de classe trouvé : $class_filename"
            if [ "$dry_run" = true ]; then
              echo "[DRY-RUN] php /home/client/pack_git/script_checkout/module_manager_entity.php "$dolibarr_base_path" \"$real_class_name\""
            else
              php /home/client/pack_git/script_checkout/module_manager_entity.php "$dolibarr_base_path" "$real_class_name"
            fi
          else
            echo "❌ Aucun fichier mod${class_name}.class.php trouvé dans $core_dir"
          fi
        else
          echo "❌ Classe du module non déterminée ou dossier core/ manquant."
        fi
      else
        echo "❌ Fichier module_manager_entity.php introuvable."
      fi

    else
      echo "❌ $nameModule n'est pas un dépôt Git. Aucune mise à jour possible."
    fi
  done
#  echo -e "\n✅ MISE À JOUR DES MODULES TERMINÉE !\n"
}

# ───────────────────────────────────────────────
# 🏁 Parsing des arguments
# ───────────────────────────────────────────────
dry_run=false
for arg in "$@"; do
  if [[ "$arg" == "--dry-run" ]]; then
    dry_run=true
    echo "🔍 Mode simulation activé (dry-run)"
  fi
done

# ───────────────────────────────────────────────
# ▶️ Appel de la fonction principale
# ───────────────────────────────────────────────
# Chemin de base où sont tous les Dolibarr à traiter
base_dir="/home/client/pack_git/"

# Boucle sur tous les dossiers Dolibarr dans ce chemin
for dolibarr_dir in "$base_dir"/*/; do
  if [[ ! -d "$dolibarr_dir" ]]; then
  continue
  fi
  if [[ ! -d "$dolibarr_dir/htdocs/custom" ]]; then
  echo "⚠️ $(basename "$dolibarr_dir") ne contient pas de dossier htdocs/custom, ignoré."
  continue
  fi
  echo -e "\n=============================="
  echo "🚀 Lancement sur $(basename "$dolibarr_dir")"
  echo "=============================="
  update_modules "$dolibarr_dir"
done
