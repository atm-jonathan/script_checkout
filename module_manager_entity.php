<?php

$res = 0;
$tmp = empty($_SERVER['SCRIPT_FILENAME']) ? '' : $_SERVER['SCRIPT_FILENAME'];
$tmp2 = realpath(__FILE__);
$i = strlen($tmp) - 1;
$j = strlen($tmp2) - 1;

while ($i > 0 && $j > 0 && isset($tmp[$i]) && isset($tmp2[$j]) && $tmp[$i] == $tmp2[$j]) {
	$i--;
	$j--;
}


require_once "/home/client/dolibarr_test/dolibarr/htdocs/master.inc.php";
require_once DOL_DOCUMENT_ROOT . '/core/lib/admin.lib.php';

global $db;

// Récupérer le nom du module à activer/désactiver
$moduleClass = $argv[1];

// Vérifier si le module est actif
function isModuleCurrentlyActive($moduleClass, $entity) {
	global $db;
	$moduleClass = strtoupper(str_replace('mod', '', $moduleClass));
	$sql = "SELECT value FROM " . $db->prefix() . "const WHERE name = 'MAIN_MODULE_" . $moduleClass . "'";
	if ($entity > 0) {
		$sql .= " AND entity = $entity";
	}
	$resql = $db->query($sql);
	if ($resql) {
		$obj = $db->fetch_object($resql);
		return (is_object($obj) && $obj->value == '1');
	}
	return false;
}

// Désactiver un module
function disableCustomModule($moduleClass) {
	global $db;
	if (class_exists($moduleClass)) {
		$objMod = new $moduleClass($db);
		$ret = $objMod->remove();
		if ($ret <= 0) {
			echo "❌ Erreur : Impossible de désactiver le module $moduleClass\n";
		} else {
			echo "✅ Module $moduleClass désactivé avec succès\n";
		}
	} else {
		echo "❌ Erreur : Classe du module $moduleClass introuvable\n";
	}
}

// Activer un module
function enableCustomModule($moduleClass) {
	global $db;
	if (class_exists($moduleClass)) {
		$objMod = new $moduleClass($db);
		$ret = $objMod->init();
		if ($ret < 0) {
			echo "❌ Erreur : Impossible d'activer le module $moduleClass\n";
		} else {
			echo "✅ Module $moduleClass activé avec succès\n";
		}
	} else {
		echo "❌ Erreur : Classe du module $moduleClass introuvable\n";
	}
}

// Récupérer les entités actives
$entities = [];
$sql = 'SELECT rowid, label FROM ' . MAIN_DB_PREFIX . 'entity WHERE active = 1 ORDER BY rowid ASC';
$res = $db->query($sql);

if ($res) {
	while ($obj = $db->fetch_object($res)) {
		$entities[$obj->rowid] = $obj->label;
	}
}
$entities = empty($entities) ? [1 => 'no entity'] : $entities;

// Traiter les modules pour chaque entité
foreach ($entities as $fkEntity => $entityLabel) {

	echo "\n=== 🔵 Début du traitement pour l'entité $fkEntity : $entityLabel ===\n";

	if ($fkEntity != 0 && $entityLabel != 'no entity') {
		$actionsMulticompany = new ActionsMulticompany($db);
		$ret = $actionsMulticompany->switchEntity($fkEntity, 1);
	} else {
		$ret = 1;
	}

	$moduleName = strtolower(str_replace('mod', '', $moduleClass));
	$class =  $moduleClass . '.class.php';
	$classPath = "/home/client/dolibarr_test/dolibarr/htdocs/custom/$moduleName/core/modules/$class";
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
	echo "\n=== 🟢 Fin du traitement pour l'entité $fkEntity : $entityLabel ===\n";
}

?>
