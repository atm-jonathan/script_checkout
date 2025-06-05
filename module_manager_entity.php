<?php

if (count($argv) != 3) {
    echo "❌ Utilisation : php module_manager_entity.php /chemin/vers/dolibarr modMyModule\n";
    exit(1);
}

$dolibarrPath = rtrim($argv[1], '/');
$moduleClass = $argv[2];

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
} else {
    require_once $dolibarrPath . '/htdocs/multicompany/class/actions_multicompany.class.php';
}
// === OUTILS MODULE ===
function isModuleCurrentlyActive($moduleClass, $entityId) {
    global $db;
    $moduleShortName = strtoupper(str_replace('mod', '', $moduleClass));
    $sql = "SELECT value FROM " . $db->prefix() . "const WHERE name = 'MAIN_MODULE_" . $moduleShortName . "' AND entity = " . intval($entityId);
    $res = $db->query($sql);
    if ($res && ($obj = $db->fetch_object($res))) {
        return $obj->value == '1';
    }
    return false;
}
function disableCustomModule($moduleClass) {
    global $db;
    if (class_exists($moduleClass)) {
        $mod = new $moduleClass($db);
        $ret = $mod->remove();
        echo $ret > 0 ? "✅ Module $moduleClass désactivé\n" : "❌ Échec désactivation $moduleClass\n";
    } else {
        echo "❌ Classe $moduleClass introuvable\n";
    }
}
function enableCustomModule($moduleClass) {
    global $db;
    if (class_exists($moduleClass)) {
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
        echo '----------------'.$entityLabel.'----------------';
    }
    // Charger classe module dynamiquement
    $moduleName = strtolower(str_replace('mod', '', $moduleClass));
    $classPath = "$dolibarrPath/htdocs/custom/$moduleName/core/modules/$moduleClass.class.php";
    if (!file_exists($classPath)) {
        echo "❌ Fichier de classe module introuvable : $classPath\n";
        continue;
    } else {
        echo "TROUVÉ : $classPath\n";
    }
    require_once $classPath;

    if ($ret > 0) {
        if (isModuleCurrentlyActive($moduleClass, $fkEntity)) {
            echo "🔻 Désactivation du module $moduleClass...\n";
            disableCustomModule($moduleClass);
            echo "🔺 Réactivation du module $moduleClass...\n";
            enableCustomModule($moduleClass);
        } else {
            echo "✅ Le module $moduleClass est déjà désactivé. Aucun changement nécessaire.\n";
        }
    } else {
        echo "❌ Erreur lors du changement d'entité\n";
    }

    echo "=== 🟢 Fin du traitement pour l'entité $fkEntity ===\n";
}

$db = null;
