#!/bin/bash

update_modules() {
  # ─────────────────────────────────────────────────────────────
  # 🎛️ CONFIGURATION
  # ─────────────────────────────────────────────────────────────
  apikey="VdKb0uBoO4vtV01mgA8x8QibKE1364GJ"
  url_base="https://testatm.srv138.atm-consulting.fr/api/index.php"
  modules_path="/home/client/dolibarr_test/dolibarr/htdocs/custom"
  initial_dir=$(pwd)

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

#echo "$latest dans $git_url"





    # Si la variable est déjà définie (non vide), ne pas réassigner
#    if [[ -z "$latest" ]]; then
#        latest=$(echo "$response_json" | sed -n 's/.*"version"[ ]*:[ ]*"\([^"]*\)".*/\1/p')
#    fi

#    if [ -d "$module_path/.git" ]; then
#      echo "✅ $nameModule est déjà un dépôt Git."
#      cd "$module_path" || continue

#      current_user=$(whoami)
#      owner=$(stat -c '%U' "$module_path")
#      if [[ "$owner" != "$current_user" ]]; then
#        echo "❌ Propriétaire ($owner) différent de l'utilisateur courant ($current_user), passage au module suivant."
#      #  continue
#      fi

#      current_remote=$(git remote get-url origin)
#      if [ "$current_remote" != "$git_url" ]; then
#        echo "❌ L'URL distante ($current_remote) est différente de l'URL attendue ($git_url). Passage au module suivant."
#        cd "$initial_dir"
#        continue
#      fi

#      if [ "$dry_run" = true ]; then
#        echo "[DRY-RUN] git reset --hard"
#      else
#        echo "reset --hard"
#        git reset --hard
#      fi
#
#      if [[ -n "$latest" ]]; then
#        echo "🌿 Tentative checkout sur la release : $latest"
#        current_branch=$(git rev-parse --abbrev-ref HEAD | tr -d '[:space:]')
#        latest=$(echo "$latest" | tr -d '[:space:]')
#
#        echo "$current_branch == $latest"
#
        if [[ -z "$latest" ]]; then
            echo "⚠️ La variable latest est vide. Recherche de la branche par défaut..."
            if git ls-remote --exit-code --heads origin main &> /dev/null; then
                latest="main"
                echo "🌿 La branche main existe, utilisation de main."
            elif git ls-remote --exit-code --heads origin master &> /dev/null; then
                latest="master"
                echo "🌿 La branche master existe, utilisation de master."
            else
                echo "❌ Aucune branche par défaut trouvée. Passage au module suivant."
                continue
            fi
        fi
        if [[ "$current_branch" == "$latest" ]]; then
          echo "🔄 La branche $latest est déjà checkout. Mise à jour..."
          if [ "$dry_run" = true ]; then
            echo "[DRY-RUN] git pull"
          else
            echo "git pull"
            git pull
          fi
          else
            echo "📥 Changement de branche vers $latest"
            if ! git ls-remote --exit-code --heads origin "$latest" &> /dev/null; then
              echo "📥 Branche $latest absente localement. Fetch..."
              if [ "$dry_run" = true ]; then
                echo "[DRY-RUN] git fetch origin +refs/heads/$latest:refs/remotes/origin/$latest"
              else
                echo "fetch origin"
                git fetch origin +refs/heads/"$latest":refs/remotes/origin/"$latest"
              fi
            fi
            if [ "$dry_run" = true ]; then
              echo "[DRY-RUN] git checkout -B \"$latest\" origin/$latest"
            else
              echo "checkout -B"
              git checkout -B "$latest" origin/"$latest"
            fi
          fi
      fi
#      cd "$initial_dir" || exit
#      echo -e "✅ Fin du traitement du module : $nameModule"
#
#      class_name=$(echo "$nameModule" | awk '{print toupper($0)}')
#      core_dir="${module_path}/core"
#
#      if [[ -f "/home/client/dolibarr_test/dolibarr/module_manager_entity.php" ]]; then
#        if [[ -n "$class_name" && -d "$core_dir" ]]; then
#          class_file=$(find "$core_dir" -type f -iname "mod${class_name}.class.php" | head -n 1)
#          if [[ -n "$class_file" ]]; then
#            class_filename=$(basename "$class_file")
#            real_class_name="${class_filename%.class.php}"
#
#            echo "📁 Fichier de classe trouvé : $class_filename"
#            echo "⚙️  (Dé)activation du module $real_class_name..."
#            if [ "$dry_run" = true ]; then
#              echo "[DRY-RUN] php /home/client/dolibarr_test/script_checkout/module_manager_entity.php \"$real_class_name\""
#            else
#              php /home/client/dolibarr_test/script_checkout/module_manager_entity.php "$real_class_name"
#            fi
#          else
#            echo "❌ Aucun fichier mod${class_name}.class.php trouvé dans $core_dir"
#          fi
#        else
#          echo "❌ Classe du module non déterminée ou dossier core/ manquant."
#        fi
#      else
#        echo "❌ Fichier module_manager_entity.php introuvable."
#      fi
#    else
#      echo "❌ $nameModule n'est pas un dépôt Git. Aucune mise à jour possible."
#    fi
#
  done
  echo -e "\n✅ MISE À JOUR DES MODULES TERMINÉE !\n"
}

# 🏁 PARSING DES ARGUMENTS

dry_run=false
for arg in "$@"; do
  if [[ "$arg" == "--dry-run" ]]; then
    dry_run=true
    echo "🔍 Mode simulation activé (dry-run)"
  fi
done

update_modules "$@"
