update_modules() {

  # Effectuer l'appel API avec l'APIKEY et l'idKanban pour récupérer les objets JSON.
  response=$(curl -s -X GET \
     --header 'Accept: application/json' \
     --header "DOLAPIKEY:HRZDEQB4k12198tchv6q6POjDQokd59u" \
     -w '\nHTTP_STATUS:%{http_code}' \
     "${'http://localhost/client/doliboard/dolibarr/htdocs/api/index.php/'}webhostapi/getWebModuleInfo?nameModule=${$nameModule}")

    http_status=$(echo "$response" | grep HTTP_STATUS | cut -d':' -f2)

    if [ "$http_status" -eq 401 ]; then
        echo "Erreur 401 : Veuillez vérifier votre connexion via le VPN ATM."
        response=""
    elif [ "$http_status" -eq 200 ]; then
        response=$(echo "$response" | sed '$d')  # Supprime la dernière ligne (statut HTTP)
    else
        echo "Erreur : Code de statut HTTP inattendu ($http_status)"
        response=""
    fi

    local initial_dir
    modules_path="/home/client/dolibarr_test/dolibarr/htdocs/custom"
    echo $modules_path
    exit

    echo -e "\n🚀 DÉMARRAGE DE LA MISE À JOUR DES MODULES DANS : $modules_path\n"
    initial_dir=$(pwd)

    for module in "$modules_path"/*; do
        if [ -d "$module/.git" ]; then
            module_name=$(basename "$module")


            echo -e "\n🔍 Traitement du module : $module_name\n"
            # Vérification des permissions Git "dubious ownership"
            if ! git -C "$module" rev-parse --is-inside-work-tree &>/dev/null; then
                echo "⚠️  Dépôt Git non sécurisé détecté, ajout à safe.directory..."
                git config --global --add safe.directory "$module"
            fi

            # Vérifier si un remote 'origin' existe
            if ! git -C "$module" remote get-url origin &>/dev/null; then
                echo "❌ Pas de remote 'origin' configuré pour $module_name, passage au suivant."
                continue
            fi

            # Recherche du fichier de classe du module
            mod_file=$(find "$module/core" -type f -iname "mod$module_name.class.php" | head -n 1)
            if [[ -f "$mod_file" ]]; then
                if ! grep -iEq '\$this->editor_name *= *["'\''].*atm.*["'\'']' "$mod_file"; then
                    echo "⚠️  Module $module_name ignoré (éditeur non ATM)."
                    continue
                else
                    class_name=$(grep -i "class " "$mod_file" | grep -i "extends dolibarrmodules" | sed -E 's/class ([a-zA-Z0-9_]+).*/\1/' | head -n 1)
                    echo "✅ Classe du module détectée : $class_name"
                fi
            else
                echo "❌ Aucun fichier de classe trouvé pour $module_name, passage au suivant."
                continue
            fi

            # Mise à jour du module via Git
            cd "$module" || continue
            echo "🔄 Réinitialisation des modifications locales..."
            git reset --hard

            export GIT_SSH_COMMAND="ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null"

            latest=$(git ls-remote --heads origin | awk -F'/' '{print $NF}' | grep -E '^[0-9]+\.[0-9]+$' | sort -V | tail -n 1)

            if [ -n "$latest" ]; then
                echo "🌿 Passage à la branche la plus récente : $latest"

                # Vérifier si la branche distante est déjà en local
                if ! git show-ref --verify --quiet "refs/remotes/origin/$latest"; then
                    echo "📥 La branche $latest n'est pas en local, récupération..."
                    git fetch origin +refs/heads/"$latest":refs/remotes/origin/"$latest"
                fi
            else
                echo "🔎 Aucune branche versionnée trouvée, tentative avec main ou master..."
                latest=""
                if git show-ref --verify --quiet refs/remotes/origin/main; then
                    latest="main"
                elif git show-ref --verify --quiet refs/remotes/origin/master; then
                    latest="master"
                fi
            fi

            if [[ -n "$latest" ]]; then
                echo "⬇️ Positionnement sur la branche à jour du module : $latest"
                git checkout -B "$latest" origin/"$latest"
            else
                echo "❌ Aucune branche valide trouvée pour $module_name !"
                continue
            fi

            # Activation/désactivation du module dans Dolibarr
            if [[ -f "/home/client/dolibarr_test/dolibarr/module_manager.php" ]]; then
                if [[ -n "$class_name" ]]; then
                    echo "⚙️  Gestion de l'activation du module $class_name..."
                    php /home/client/dolibarr_test/dolibarr/module_manager_entity.php "$class_name"
                else
                    echo "❌ Impossible de déterminer la classe du module $module_name."
                fi
            else
                echo "❌ Fichier module_manager.php introuvable dans $(pwd)."
            fi

            cd "$initial_dir" || exit
            echo -e "✅ Fin du traitement du module : $module_name\n"
        else
            echo "⏭️  Module non versionné avec Git : $(basename "$module"), passage au suivant."
        fi
    done

    echo -e "\n✅ MISE À JOUR DES MODULES TERMINÉE !\n"
}

# Lancer la fonction en prenant les arguments en compte
update_modules "$@"
