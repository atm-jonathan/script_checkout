#!/bin/bash

update_modules() {
  # ─────────────────────────────────────────────────────────────
  # 🎛️ CONFIGURATION
  # ─────────────────────────────────────────────────────────────
  apikey="HRZDEQB4k12198tchv6q6POjDQokd59u"
  url_base="http://localhost/client/doliboard/dolibarr/htdocs/api/index.php"
  modules_path="/home/client/dolibarr_test/dolibarr/htdocs/custom"
  initial_dir=$(pwd)

  echo -e "\n🚀 DÉMARRAGE DE LA MISE À JOUR DES MODULES DANS : $modules_path\n"

  for module_full_path in "$modules_path"/*/; do
    module_path="${module_full_path%/}"
    nameModule=$(basename "$module_path")

    echo -e "\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "🔍 Traitement du module : $nameModule"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

    # ─────────────────────────────────────────────────────────────
    # 🌐 APPEL API POUR INFOS DU MODULE
    # ─────────────────────────────────────────────────────────────
    response=$(curl -s -X GET \
      --header 'Accept: application/json' \
      --header "DOLAPIKEY: $apikey" \
      -w '\nHTTP_STATUS:%{http_code}' \
      "${url_base}/webhostapi/getWebModuleInfo?nameModule=${nameModule}"
    )
    http_status=$(echo "$response" | grep HTTP_STATUS | cut -d':' -f2)

    if [ "$http_status" -eq 401 ]; then
      echo "❌ Erreur 401 : Vérifiez votre connexion VPN ATM."
      continue
    elif [ "$http_status" -ne 200 ]; then
      echo "❌ Erreur HTTP ($http_status) pour $nameModule"
      continue
    fi

    response=$(echo "$response" | sed '$d')
    git_url=$(echo "$response" | grep -oP '"git_url"\s*:\s*"\K[^"]+')
    latest=$(echo "$response" | grep -oP '"last_release"\s*:\s*"\K[^"]+')

    if [[ -z "$git_url" ]]; then
      echo "❌ Pas d'URL Git pour $nameModule. On continue sans mise à jour."
    fi

    # ─────────────────────────────────────────────────────────────
    # 🔁 MISE À JOUR DU MODULE SI GIT DISPONIBLE
    # ─────────────────────────────────────────────────────────────
    if [ -d "$module_path/.git" ]; then
      echo "✅ $nameModule est déjà un dépôt Git."
      cd "$module_path" || continue

      $dry_run && echo "[DRY-RUN] git remote set-url origin \"$git_url\"" || git remote set-url origin "$git_url"
      $dry_run && echo "[DRY-RUN] git reset --hard" || git reset --hard

      if [[ -n "$latest" ]]; then
        echo "🌿 Tentative checkout sur la release : $latest"
        if ! git ls-remote --exit-code --heads origin "$latest" &> /dev/null; then
          echo "📥 Branche $latest absente localement. Fetch..."
          $dry_run && echo "[DRY-RUN] git fetch origin +refs/heads/$latest:refs/remotes/origin/$latest" || \
          git fetch origin +refs/heads/"$latest":refs/remotes/origin/"$latest"
        fi
        $dry_run && echo "[DRY-RUN] git checkout -B \"$latest\" origin/$latest" || git checkout -B "$latest" origin/"$latest"
      else
        echo "🔎 Aucune release définie. Tentative sur main/master"
        for branch in main master; do
          if git show-ref --verify --quiet refs/remotes/origin/$branch; then
            $dry_run && echo "[DRY-RUN] git checkout -B \"$branch\" origin/$branch" || \
            git checkout -B "$branch" origin/"$branch"
            break
          fi
        done
      fi

    # ─────────────────────────────────────────────────────────────
    # 🔁 MISE À JOUR DU MODULE SANS GIT
    # ─────────────────────────────────────────────────────────────
    elif [[ -n "$git_url" ]]; then
      echo "⏭️  $nameModule n'est pas un dépôt Git. Clonage du dépôt..."
      temp_clone_dir=$(mktemp -d)

      if [[ -n "$latest" ]]; then
        git_clone_cmd="git clone -b $latest \"$git_url\" \"$temp_clone_dir\""
      else
        git_clone_cmd="git clone \"$git_url\" \"$temp_clone_dir\""
      fi

      echo "🔧 $git_clone_cmd"
      $dry_run && echo "[DRY-RUN] $git_clone_cmd" || eval "$git_clone_cmd"

      echo "🧩 Synchronisation avec rsync..."
      $dry_run && echo "[DRY-RUN] rsync -a --delete \"$temp_clone_dir/\" \"$module_path\"" || \
      rsync -a --delete "$temp_clone_dir/" "$module_path"

      $dry_run && echo "[DRY-RUN] rm -rf \"$temp_clone_dir\"" || rm -rf "$temp_clone_dir"
    else
      echo "⚠️  Aucune action Git effectuée pour $nameModule"
    fi

    # ─────────────────────────────────────────────────────────────
    # ⚙️ ACTIVATION / DÉSACTIVATION DU MODULE
    # ─────────────────────────────────────────────────────────────
    class_name=$(echo "$nameModule" | awk '{print toupper($0)}')

    if [[ -f "/home/client/dolibarr_test/dolibarr/module_manager_entity.php" ]]; then
      if [[ -n "$class_name" ]]; then
        echo "⚙️  (Dé)activation du module $class_name..."
        $dry_run && echo "[DRY-RUN] php /home/client/dolibarr_test/dolibarr/module_manager_entity.php \"$class_name\"" || \
        php /home/client/dolibarr_test/dolibarr/module_manager_entity.php "$class_name"
      else
        echo "❌ Classe du module non déterminée."
      fi
    else
      echo "❌ Fichier module_manager_entity.php introuvable."
    fi

    cd "$initial_dir" || exit
    echo -e "✅ Fin du traitement du module : $nameModule"
  done

  echo -e "\n✅ MISE À JOUR DES MODULES TERMINÉE !\n"
}

# ─────────────────────────────────────────────────────────────
# 🏁 PARSING DES ARGUMENTS
# ─────────────────────────────────────────────────────────────
dry_run=false
for arg in "$@"; do
  if [[ "$arg" == "--dry-run" ]]; then
    dry_run=true
    echo "🔍 Mode simulation activé (dry-run)"
  fi
done

# ─────────────────────────────────────────────────────────────
# 🚀 LANCEMENT
# ─────────────────────────────────────────────────────────────
update_modules "$@"
