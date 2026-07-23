<?php

declare(strict_types=1);

final class ApiController
{
    public static function handle(LocalDataClient $client, string $path): never
    {
        header('Content-Type: application/json; charset=utf-8');
        header('Access-Control-Allow-Origin: *');
        header('Access-Control-Allow-Methods: GET, OPTIONS');
        header('Access-Control-Allow-Headers: content-type');
        header('X-Content-Type-Options: nosniff');

        if (($_SERVER['REQUEST_METHOD'] ?? 'GET') === 'OPTIONS') {
            http_response_code(204);
            exit;
        }
        if (($_SERVER['REQUEST_METHOD'] ?? 'GET') !== 'GET') {
            http_response_code(405);
            echo json_encode(['error' => 'Method not allowed'], JSON_UNESCAPED_SLASHES);
            exit;
        }

        $result = $client->get('/' . ltrim($path, '/'), $_GET);
        http_response_code($result['status']);
        echo json_encode($result['ok'] ? $result['data'] : ['error' => $result['error']], JSON_UNESCAPED_SLASHES | JSON_UNESCAPED_UNICODE);
        exit;
    }
}
