#!/bin/bash

# DOLAPIKEY et URL de base de l'API
apikey="HRZDEQB4k12198tchv6q6POjDQokd59u"
url_base="http://localhost/client/doliboard/dolibarr/htdocs/api/index.php"

# Dossier contenant les modules
modules_path="/home/client/dolibarr_test/dolibarr/htdocs/custom"
initial_dir=$(pwd)

echo -e "\n🚀 DÉMARRAGE DE LA MISE À JOUR DES MODULES DANS : $modules_path\n"

# Boucle sur chaque répertoire (module)
for module_path in "$modules_path"/*/; do
    # Récupération du nom du module à partir du chemin
    nameModule=$(basename "$module_path")
    echo -e "🔍 Traitement du module : $nameModule"

    # Appel API pour récupérer les infos du module
    response=$(curl -s -X GET \
      --header 'Accept: application/json' \
      --header "DOLAPIKEY: $apikey" \
      -w '\nHTTP_STATUS:%{http_code}' \
      "${url_base}/webhostapi/getWebModuleInfo?nameModule=${nameModule}"
    )

    http_status=$(echo "$response" | grep HTTP_STATUS | cut -d':' -f2)

    if [ "$http_status" -eq 401 ]; then
        echo "❌ Erreur 401 : Veuillez vérifier votre connexion via le VPN ATM."
        response=""
    elif [ "$http_status" -eq 200 ]; then
        response=$(echo "$response" | sed '$d')  # Supprimer la dernière ligne
        echo "✅ Réponse API pour $nameModule : $response"
        # Tu peux ici parser $response si besoin, ou lancer une mise à jour
    else
        echo "❌ Erreur : Code HTTP inattendu ($http_status) pour le module $nameModule"
        response=""
    fi

    echo
done

cd "$initial_dir" || exit
