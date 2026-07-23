<?php

declare(strict_types=1);

$localConfigFile = __DIR__ . '/config.local.php';
$local = is_file($localConfigFile) ? require $localConfigFile : [];
if (!is_array($local)) $local = [];
$setting = static function (string $environment, string $key, mixed $default = '') use ($local): mixed {
    $value = getenv($environment);
    return $value !== false && $value !== '' ? $value : ($local[$key] ?? $default);
};

$databaseHost = trim((string) $setting('BHOP_DB_HOST', 'db_host'));
$databasePort = (int) $setting('BHOP_DB_PORT', 'db_port', 3306);
$databaseName = trim((string) $setting('BHOP_DB_DB', 'db_name'));
$databaseUser = trim((string) $setting('BHOP_DB_USER', 'db_user'));
$databasePass = (string) $setting('BHOP_DB_PASS', 'db_pass');
$databasePrefix = trim((string) $setting('BHOP_DB_PREFIX', 'db_prefix', 'bhop_'));
if (!preg_match('/^[A-Za-z][A-Za-z0-9_]{0,47}$/', $databasePrefix)) $databasePrefix = 'bhop_';
$gameHost = trim((string) $setting('BHOP_GAME_HOST', 'game_host', '127.0.0.1'));
$gamePort = (int) $setting('BHOP_GAME_PORT', 'game_port', 27016);
$baseUrl = rtrim(trim((string) $setting('WEBSITE_BASE_URL', 'base_url')), '/');
$timezone = trim((string) $setting('APP_TIMEZONE', 'timezone', 'Europe/Istanbul'));
if (!in_array($timezone, timezone_identifiers_list(), true)) $timezone = 'Europe/Istanbul';
date_default_timezone_set($timezone);

define('DB_HOST', $databaseHost);
define('DB_PORT', $databasePort > 0 ? $databasePort : 3306);
define('DB_NAME', $databaseName);
define('DB_USER', $databaseUser);
define('DB_PASS', $databasePass);
define('DB_TABLE_PREFIX', $databasePrefix);
define('DB_CHARSET', 'utf8mb4');
define('DB_CONFIGURED', DB_HOST !== '' && DB_NAME !== '' && DB_USER !== '');
define('GAME_HOST', $gameHost !== '' ? $gameHost : '127.0.0.1');
define('GAME_PORT', $gamePort > 0 ? $gamePort : 27016);
define('STEAM_ENRICHMENT_ENABLED', filter_var($setting('BHOP_STEAM_ENRICHMENT', 'steam_enrichment', false), FILTER_VALIDATE_BOOL));

define('MODES', [0 => 'normal', 1 => 'lowgrav', 2 => 'dbjump', 3 => 'normal200', 4 => 'normal333', 5 => 'normal500', 6 => 'normal1000', 7 => 'simple']);
define('MODE_LABELS', [
    'normal' => 'Normal 131 FPS', 'lowgrav' => 'Low Gravity', 'dbjump' => 'Double Jump',
    'normal200' => 'Normal 200 FPS', 'normal333' => 'Normal 333 FPS',
    'normal500' => 'Normal 500 FPS', 'normal1000' => 'Normal 1000 FPS', 'simple' => 'Simple',
]);
define('MODE_SUFFIXES', [
    'normal' => '', 'lowgrav' => '_lowgrav', 'dbjump' => '_dbjump',
    'normal200' => '_normal200', 'normal333' => '_normal333',
    'normal500' => '_normal500', 'normal1000' => '_normal1000', 'simple' => '_simple',
]);
define('MODE_FPS', ['normal' => 131, 'lowgrav' => 1000, 'dbjump' => 1000, 'normal200' => 200, 'normal333' => 333, 'normal500' => 500, 'normal1000' => 1000, 'simple' => 0]);
define('NORMAL_FPS_MODE_IDS', [0, 3, 4, 5, 6]);
define('MODE_DISPLAY_ORDER', [0, 3, 4, 5, 6, 1, 2, 7]);
define('PRO_LIMIT', 15);
define('MARKET_TYPE_LABELS', [
    'custom_prefix' => 'Chat customization', 'join_message' => 'Join customization',
    'knife' => 'Knife skin', 'knife_skin' => 'Knife skin', 'vip_skin' => 'VIP knife skin',
    'wrsound' => 'WR sound', 'wr_sound' => 'WR sound', 'trail' => 'Trail',
]);
define('REQUIRED_SCHEMA', [
    'best' => ['map', 'authid', 'name', 'mode', 'best_time_ms', 'updated_at'],
    'records' => ['id', 'record_key', 'map', 'authid', 'name', 'mode', 'time_ms', 'created_at'],
    'players' => ['player_key', 'identity_type', 'steamid64', 'authid', 'name', 'total_credits', 'spent_credits', 'hook_reward', 'custom_prefix', 'revision', 'updated_at'],
    'inventory' => ['event_key', 'player_key', 'item_id', 'purchased_at'],
    'market_items' => ['item_id', 'name', 'price', 'item_type', 'effect_value'],
]);
define('BADGE_THRESHOLDS', [10 => 'Bronze I', 50 => 'Bronze II', 100 => 'Silver I', 250 => 'Silver II', 500 => 'Gold I', 1000 => 'Gold II', 2000 => 'Platinum I', 5000 => 'Platinum II', 10000 => 'Diamond I', 20000 => 'Diamond II']);
define('BASE_URL', $baseUrl);

return [
    'site_name' => 'ESKIDOSTLAR BHOP',
    'tagline' => 'Every millisecond leaves a trace.',
    'public_connect' => trim((string) $setting('BHOP_PUBLIC_CONNECT', 'public_connect')),
    'base_url' => $baseUrl,
    'timezone' => $timezone,
    'database_configured' => DB_CONFIGURED,
    'game_host' => GAME_HOST,
    'game_port' => GAME_PORT,
];
