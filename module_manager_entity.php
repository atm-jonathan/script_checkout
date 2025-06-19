<?php

if (count($argv) != 4) {
    echo "❌ Utilisation : php module_manager_entity.php /chemin/vers/dolibarr modMyModule true|false\n";
    exit(1);
}

$dolibarrPath = rtrim($argv[1], '/');
$moduleClass = $argv[2];
$dryRun = filter_var($argv[3], FILTER_VALIDATE_BOOLEAN);

echo $dryRun ? "🔍 Mode dry-run activé (aucune modification en base)\n" : "✏️ Mode réel (modifications effectuées)\n";

// === CHARGER conf.php ===
$confFile = $dolibarrPath . '/htdocs/conf/conf.php';
if (!file_exists($confFile)) {
    echo "❌ Fichier conf.php introuvable : $confFile\n";
    exit(1);
}
require $confFile;

// === INCLURE master.inc.php & lib SQL ===
require_once $dolibarrPath . '/htdocs/master.inc.php';
require_once $dolibarrPath . '/htdocs/core/lib/admin.lib.php';
require_once $dolibarrPath . '/htdocs/core/lib/functions2.lib.php';
require_once $dolibarrPath . '/htdocs/core/lib/functions.lib.php';

// === CRÉER INSTANCE DB ===
$db = getDoliDBInstance(
    $dolibarr_main_db_type,
    $dolibarr_main_db_host,
    $dolibarr_main_db_user,
    $dolibarr_main_db_pass,
    $dolibarr_main_db_name,
    (int) $dolibarr_main_db_port
);

if (!$db || $db->error) {
    echo "❌ Erreur connexion base de données : " . ($db->error ?? 'inconnue') . "\n";
    exit(1);
}

// === DÉTECTER ENTITÉS ===
$entities = [];
$res = $db->query('SHOW TABLES LIKE "' . $db->prefix() . 'entity"');
if ($res && $db->num_rows($res)) {
    $res = $db->query('SELECT rowid, label FROM ' . $db->prefix() . 'entity WHERE active = 1 ORDER BY rowid ASC');
    while ($obj = $db->fetch_object($res)) {
        $entities[$obj->rowid] = $obj->label;
    }
}
if (empty($entities)) {
    $entities = [1 => 'no entity'];
} elseif (isModEnabled('multicompany')) {
    require_once $dolibarrPath . '/htdocs/custom/multicompany/class/actions_multicompany.class.php';
}

// === OUTILS MODULE ===
/**
 * Checks if a specific module is currently active for a given entity.
 *
 * @param string $moduleClass The class name of the module to be checked.
 * @param int $entityId The ID of the entity to check the module's activation status for.
 * @return bool Returns true if the module is active for the given entity, false otherwise.
 */
function isModuleCurrentlyActive(string $moduleClass, int $entityId):bool {
    global $db;
    $moduleShortName = strtoupper(str_replace('mod', '', $moduleClass));
    $sql = "SELECT value FROM " . $db->prefix() . "const WHERE name = 'MAIN_MODULE_" . $moduleShortName . "' AND entity = " . intval($entityId);
    $res = $db->query($sql);
    if ($res && ($obj = $db->fetch_object($res))) {
        return $obj->value == true;
    }
    return false;
}

/**
 * Disables a custom module by invoking its removal process.
 *
 * @param string $moduleClass The class name of the module to be disabled.
 * @param bool $dryRun If true, simulates the disabling process without making any actual changes.
 * @return void
 */
function disableCustomModule(string $moduleClass, bool $dryRun) :void {
    global $db;
    if (class_exists($moduleClass)) {
        if ($dryRun) {
            echo "💤 [DRY-RUN] Simuler la désactivation de $moduleClass\n";
            return;
        }
        $mod = new $moduleClass($db);
        $ret = $mod->remove();
        echo $ret > 0 ? "✅ Module $moduleClass désactivé\n" : "❌ Échec désactivation $moduleClass\n";
    } else {
        echo "❌ Classe $moduleClass introuvable\n";
    }
}

/**
 * Enables a custom module by initializing its class and executing its init method.
 * If the class does not exist or initialization fails, an appropriate message is displayed.
 * Optionally supports dry-run mode to simulate activation without performing actual actions.
 *
 * @param string $moduleClass The name of the module class to enable.
 * @param bool $dryRun If true, simulates the activation without actually initializing the module.
 * @return void
 */
function enableCustomModule(string $moduleClass, bool $dryRun) :void {
    global $db;
    if (class_exists($moduleClass)) {
        if ($dryRun) {
            echo "💤 [DRY-RUN] Simuler l’activation de $moduleClass\n";
            return;
        }
        $mod = new $moduleClass($db);
        $ret = $mod->init();
        echo $ret >= 0 ? "✅ Module $moduleClass activé\n" : "❌ Échec activation $moduleClass\n";
    } else {
        echo "❌ Classe $moduleClass introuvable\n";
    }
}

// === PARCOURIR LES ENTITÉS ===
foreach ($entities as $fkEntity => $entityLabel) {
    echo "\n=== 🔵 Début du traitement pour l'entité $fkEntity : $entityLabel ===\n";
    $ret = 1;
    if ($fkEntity != 0 && $entityLabel != 'no entity') {
        $actionsMulticompany = new ActionsMulticompany($db);
        $ret = $actionsMulticompany->switchEntity($fkEntity, 1);
    } else {
        echo "---------------- $entityLabel ----------------\n";
    }

    // Charger classe module dynamiquement
    $moduleName = strtolower(str_replace('mod', '', $moduleClass));
    $classPath = "$dolibarrPath/htdocs/custom/$moduleName/core/modules/$moduleClass.class.php";
    if (!file_exists($classPath)) {
        echo "❌ Fichier de classe module introuvable : $classPath\n";
        continue;
    } else {
        echo "📄 Classe module trouvée : $classPath\n";
    }
    require_once $classPath;

    if ($ret > 0) {
        if (isModuleCurrentlyActive($moduleClass, $fkEntity)) {
            echo "🔻 Le module est actif. Déactivation...\n";
            disableCustomModule($moduleClass, $dryRun);
            echo "🔺 Réactivation du module...\n";
            enableCustomModule($moduleClass, $dryRun);
        } else {
            echo "✅ Le module $moduleClass est déjà désactivé. Aucun changement nécessaire.\n";
        }
    } else {
        echo "❌ Erreur lors du changement d'entité\n";
    }

    echo "=== 🟢 Fin du traitement pour l'entité $fkEntity ===\n";
}

$db = null;
