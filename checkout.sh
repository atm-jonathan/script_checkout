#!/bin/bash

update_modules() {
  # ─────────────────────────────────────────────────────────────
  # 🎛️ CONFIGURATION
  # ─────────────────────────────────────────────────────────────
  apikey="HRZDEQB4k12198tchv6q6POjDQokd59u"
  url_base="http://localhost/client/doliboard/dolibarr/htdocs/api/index.php"
  dry_run=false
  modules_path="${1:-/home/client/dolibarr_test/dolibarr/htdocs/custom}"  # Argument ou valeur par défaut
  initial_dir=$(pwd)

  # Vérifie si --dry-run est passé
  [[ "$2" == "--dry-run" || "$1" == "--dry-run" ]] && dry_run=true

  echo -e "\n🚀 DÉMARRAGE DE LA MISE À JOUR DES MODULES DANS : $modules_path"
  $dry_run && echo "🔍 MODE DRY RUN ACTIVÉ — Aucune modification ne sera appliquée."

  for module in "$modules_path"/*; do
    module_name=$(basename "$module")

    echo -e "\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "🔍 Traitement du module : $module_name"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

    # ─────────────────────────────────────────────────────────────
    # 🌐 APPEL API POUR INFOS DU MODULE
    # ─────────────────────────────────────────────────────────────
    response=$(curl -s -X GET \
      --header 'Accept: application/json' \
      --header "DOLAPIKEY: $apikey" \
      -w '\nHTTP_STATUS:%{http_code}' \
      "${url_base}/webhostapi/getWebModuleInfo?nameModule=${module_name}"
    )
    http_status=$(echo "$response" | grep HTTP_STATUS | cut -d':' -f2)

    if [ "$http_status" -eq 401 ]; then
      echo "❌ Erreur 401 : Vérifiez votre connexion VPN ATM."
      continue
    elif [ "$http_status" -ne 200 ]; then
      echo "❌ Erreur HTTP ($http_status) pour $module_name"
      continue
    fi

    # On enlève la ligne HTTP_STATUS
    response=$(echo "$response" | sed '$d')

    git_url=$(echo "$response" | grep -oP '"git_url"\s*:\s*"\K[^"]+')
    latest=$(echo "$response" | grep -oP '"last_release"\s*:\s*"\K[^"]+')

    if [[ -z "$git_url" ]]; then
      echo "❌ Pas d'URL Git pour $module_name. On continue sans mise à jour."
    fi

    # ─────────────────────────────────────────────────────────────
    # 🔁 MISE À JOUR DU MODULE SI GIT DISPONIBLE
    # ─────────────────────────────────────────────────────────────
    if [ -d "$module/.git" ]; then
      echo "✅ $module_name est déjà un dépôt Git."
      cd "$module" || continue

      $dry_run || git remote set-url origin "$git_url"
      $dry_run || git reset --hard

      if [[ -n "$latest" ]]; then
        echo "🌿 Tentative checkout sur la release : $latest"
        if ! git ls-remote --exit-code --heads origin "$latest" &> /dev/null; then
          echo "📥 Branche $latest absente localement. Fetch..."
          $dry_run || git fetch origin +refs/heads/"$latest":refs/remotes/origin/"$latest"
        fi
        $dry_run || git checkout -B "$latest" origin/"$latest"
      else
        echo "🔎 Aucune release définie. Tentative sur main/master"
        for branch in main master; do
          if git show-ref --verify --quiet refs/remotes/origin/$branch; then
            $dry_run || git checkout -B "$branch" origin/"$branch"
            break
          fi
        done
      fi
    # ─────────────────────────────────────────────────────────────
    # 🔁 MAJ GIT NON DISPONIBLE
    # ─────────────────────────────────────────────────────────────
    elif [[ -n "$git_url" ]]; then
      echo "⏭️  $module_name n'est pas un dépôt Git. Clonage du dépôt..."
      temp_clone_dir=$(mktemp -d)

      if [[ -n "$latest" ]]; then
        git_clone_cmd="git clone -b $latest \"$git_url\" \"$temp_clone_dir\""
      else
        git_clone_cmd="git clone \"$git_url\" \"$temp_clone_dir\""
      fi

      echo "🔧 $git_clone_cmd"
      $dry_run || eval "$git_clone_cmd"

      echo "🧩 Synchronisation avec rsync..."
      $dry_run || rsync -a --delete "$temp_clone_dir/" "$module/"
      $dry_run || rm -rf "$temp_clone_dir"
    else
      echo "⚠️  Aucune action Git effectuée pour $module_name"
    fi

    # ─────────────────────────────────────────────────────────────
    # ⚙️ ACTIVATION / DÉSACTIVATION DU MODULE
    # ─────────────────────────────────────────────────────────────
    class_name=$(echo "$module_name" | awk '{print toupper($0)}')

    if [[ -f "/home/client/dolibarr_test/dolibarr/module_manager_entity.php" ]]; then
      if [[ -n "$class_name" ]]; then
        echo "⚙️  (Dé)activation du module $class_name..."
        $dry_run || php /home/client/dolibarr_test/dolibarr/module_manager_entity.php "$class_name"
      else
        echo "❌ Classe du module non déterminée."
      fi
    else
      echo "❌ Fichier module_manager_entity.php introuvable."
    fi

    cd "$initial_dir" || exit
    echo -e "✅ Fin du traitement du module : $module_name"
  done

  echo -e "\n✅ MISE À JOUR DES MODULES TERMINÉE !\n"
}

# Appel de la fonction avec les arguments
update_modules "$@"
