<?php

declare(strict_types=1);

$path = (string) (parse_url($_SERVER['REQUEST_URI'] ?? '/', PHP_URL_PATH) ?: '/');
if (preg_match('#^/(?:src|tests)/#', $path) || preg_match('#^/(?:config(?:\.local)?(?:\.example)?\.php|router\.php|README\.md)$#i', $path)) {
    http_response_code(404);
    echo 'Not found';
    return true;
}
$file = realpath(__DIR__ . $path);
$root = realpath(__DIR__);
if ($file !== false && $root !== false && str_starts_with($file, $root . DIRECTORY_SEPARATOR) && is_file($file)) {
    return false;
}
require __DIR__ . '/index.php';
