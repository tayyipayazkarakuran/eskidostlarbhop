<?php

declare(strict_types=1);

// Copy to config.local.php for local development only. Never commit or package
// the copied file. Environment variables override these values.
return [
    'db_host' => '127.0.0.1',
    'db_port' => 3306,
    'db_name' => 'bhop_timer',
    'db_user' => 'bhop_web_readonly',
    'db_pass' => 'CHANGE_ME',
    'db_prefix' => 'bhop_',
    'game_host' => '127.0.0.1',
    'game_port' => 27016,
    'public_connect' => 'YOUR_SERVER_ADDRESS:27015',
    'base_url' => '',
    'timezone' => 'Europe/Istanbul',
    'steam_enrichment' => false,
];
