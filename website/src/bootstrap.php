<?php

declare(strict_types=1);

$config = require dirname(__DIR__) . '/config.php';
require_once __DIR__ . '/Support.php';
require_once __DIR__ . '/DataClient.php';
require_once __DIR__ . '/Db.php';
require_once __DIR__ . '/A2S.php';
require_once __DIR__ . '/Steam.php';
require_once __DIR__ . '/LocalDataClient.php';
require_once __DIR__ . '/ApiController.php';
require_once __DIR__ . '/Layout.php';
require_once __DIR__ . '/Pages.php';
require_once __DIR__ . '/Motd.php';

$api = new LocalDataClient();
