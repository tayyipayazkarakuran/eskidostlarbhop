<?php

define('DB_HOST', '45.143.11.212');
define('DB_PORT', 3306);
define('DB_NAME', 'bhop');
define('DB_USER', 'bhopuser1');
define('DB_PASS', 'password');
define('DB_CHARSET', 'utf8');

define('PRO_LIMIT', 15);

define('MODES', [
    0 => 'normal',
    1 => 'lowgrav',
    2 => 'dbjump',
]);

define('MODE_NAMES', [
    'normal'  => 'Normal',
    'lowgrav' => 'Low Gravity',
    'dbjump'  => 'Double Jump',
]);

function db_connect()
{
    static $pdo = null;

    if ($pdo !== null) {
        return $pdo;
    }

    $dsn = 'mysql:host=' . DB_HOST . ';port=' . DB_PORT . ';dbname=' . DB_NAME . ';charset=' . DB_CHARSET;

    try {
        $pdo = new PDO($dsn, DB_USER, DB_PASS, [
            PDO::ATTR_ERRMODE            => PDO::ERRMODE_EXCEPTION,
            PDO::ATTR_DEFAULT_FETCH_MODE  => PDO::FETCH_ASSOC,
            PDO::ATTR_EMULATE_PREPARES    => false,
        ]);
    } catch (PDOException $e) {
        $pdo = null;
    }

    return $pdo;
}

function db_tables_exist($pdo)
{
    if (!$pdo) {
        return false;
    }

    try {
        $stmt = $pdo->query("SHOW TABLES LIKE 'bhop_best'");
        return $stmt && $stmt->fetch() !== false;
    } catch (PDOException $e) {
        return false;
    }
}

function db_ensure_schema($pdo)
{
    if (!$pdo) {
        return false;
    }

    $pdo->exec("CREATE TABLE IF NOT EXISTS bhop_records (
        id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,
        record_key VARCHAR(160) NOT NULL UNIQUE,
        map VARCHAR(64) NOT NULL,
        authid VARCHAR(35) NOT NULL,
        name VARCHAR(32) NOT NULL,
        mode TINYINT UNSIGNED NOT NULL DEFAULT 0,
        time_ms INT UNSIGNED NOT NULL,
        created_at INT UNSIGNED NOT NULL
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8");

    $pdo->exec("CREATE TABLE IF NOT EXISTS bhop_best (
        map VARCHAR(64) NOT NULL,
        authid VARCHAR(35) NOT NULL,
        name VARCHAR(32) NOT NULL,
        mode TINYINT UNSIGNED NOT NULL DEFAULT 0,
        best_time_ms INT UNSIGNED NOT NULL,
        updated_at INT UNSIGNED NOT NULL,
        PRIMARY KEY (map, mode, authid)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8");

    db_add_mode_column($pdo, 'bhop_records');
    db_add_mode_column($pdo, 'bhop_best');
    db_fix_best_primary_key($pdo);

    return true;
}

function db_has_column($pdo, $table, $column)
{
    try {
        $stmt = $pdo->prepare("SHOW COLUMNS FROM `{$table}` LIKE :col");
        $stmt->execute(['col' => $column]);
        return $stmt->fetch() !== false;
    } catch (PDOException $e) {
        return false;
    }
}

function db_add_mode_column($pdo, $table)
{
    if (!db_has_column($pdo, $table, 'mode')) {
        try {
            $pdo->exec("ALTER TABLE `{$table}` ADD COLUMN mode TINYINT UNSIGNED NOT NULL DEFAULT 0");
        } catch (PDOException $e) {
            // Column may already exist from a concurrent request
        }
    }
}

function db_fix_best_primary_key($pdo)
{
    if (!db_has_column($pdo, 'bhop_best', 'mode')) {
        return;
    }

    try {
        $rows = $pdo->query("SHOW INDEX FROM bhop_best WHERE Key_name = 'PRIMARY'")->fetchAll(PDO::FETCH_ASSOC);
        $pk_cols = array_map(function ($r) { return $r['Column_name']; }, $rows);
        sort($pk_cols);
        $has_mode = in_array('mode', $pk_cols);
        if (!$has_mode) {
            $pdo->exec("ALTER TABLE bhop_best DROP PRIMARY KEY, ADD PRIMARY KEY (map, mode, authid)");
        }
    } catch (PDOException $e) {
        // PK may already be correct
    }
}

function get_pro15($pdo, $map, $mode)
{
    if (!$pdo) {
        return [];
    }

    $sql = "SELECT name, best_time_ms AS time_ms
            FROM bhop_best
            WHERE map = :map AND mode = :mode
            ORDER BY best_time_ms ASC
            LIMIT :limit";

    $stmt = $pdo->prepare($sql);
    $stmt->bindValue(':map', $map, PDO::PARAM_STR);
    $stmt->bindValue(':mode', $mode, PDO::PARAM_INT);
    $stmt->bindValue(':limit', PRO_LIMIT, PDO::PARAM_INT);
    $stmt->execute();

    return $stmt->fetchAll();
}

function get_all_maps($pdo)
{
    if (!$pdo) {
        return [];
    }

    $sql = "SELECT DISTINCT map FROM bhop_best ORDER BY map ASC";
    $stmt = $pdo->query($sql);

    return $stmt ? $stmt->fetchAll(PDO::FETCH_COLUMN) : [];
}

function get_maps_with_counts($pdo)
{
    if (!$pdo) {
        return [];
    }

    $sql = "SELECT map, mode, COUNT(*) AS player_count, MIN(best_time_ms) AS wr_time
            FROM bhop_best
            GROUP BY map, mode
            ORDER BY map ASC, mode ASC";

    $stmt = $pdo->query($sql);

    return $stmt ? $stmt->fetchAll() : [];
}

function get_total_records($pdo)
{
    if (!$pdo) {
        return 0;
    }

    $sql = "SELECT COUNT(DISTINCT authid) AS total FROM bhop_best";
    $stmt = $pdo->query($sql);

    if ($stmt && $row = $stmt->fetch()) {
        return (int) $row['total'];
    }

    return 0;
}

function get_wr_for_map($pdo, $map, $mode)
{
    if (!$pdo) {
        return null;
    }

    $sql = "SELECT name, best_time_ms AS time_ms
            FROM bhop_best
            WHERE map = :map AND mode = :mode
            ORDER BY best_time_ms ASC
            LIMIT 1";

    $stmt = $pdo->prepare($sql);
    $stmt->execute(['map' => $map, 'mode' => $mode]);
    $row = $stmt->fetch();

    return $row ?: null;
}

function format_time($ms)
{
    if ($ms <= 0) {
        return '--:--.---';
    }

    $minutes  = floor($ms / 60000);
    $seconds   = floor(($ms % 60000) / 1000);
    $millis    = $ms % 1000;

    return sprintf('%d:%02d.%03d', $minutes, $seconds, $millis);
}

function mode_from_param($param)
{
    $param = strtolower(trim($param));

    if ($param === 'normal' || $param === '0') {
        return 0;
    }

    if ($param === 'lowgrav' || $param === 'low_gravity' || $param === 'lowgravity' || $param === '1') {
        return 1;
    }

    if ($param === 'dbjump' || $param === 'doublejump' || $param === 'double_jump' || $param === '2') {
        return 2;
    }

    return 0;
}

function mode_key($mode_id)
{
    return MODES[$mode_id] ?? 'normal';
}

function mode_label($mode_id)
{
    $key = mode_key($mode_id);
    return MODE_NAMES[$key] ?? 'Normal';
}

function esc($str)
{
    return htmlspecialchars($str, ENT_QUOTES, 'UTF-8');
}
