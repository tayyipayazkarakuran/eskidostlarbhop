<?php

declare(strict_types=1);

require_once __DIR__ . '/src/bootstrap.php';

$requestPath = (string) (parse_url($_SERVER['REQUEST_URI'] ?? '/', PHP_URL_PATH) ?: '/');
$base = $config['base_url'];
if ($base !== '' && str_starts_with($requestPath, $base)) {
    $requestPath = substr($requestPath, strlen($base)) ?: '/';
}
$path = trim(rawurldecode($requestPath), '/');
$parts = $path === '' ? [] : explode('/', $path);
$route = $parts[0] ?? '';

switch ($route) {
    case 'api':
        ApiController::handle($api, $path);
    case '':
        Pages::home($api);
        break;
    case 'profile':
        $id = $parts[1] ?? '';
        if ($id === '') {
            header('Location: ' . Support::url('/'));
            exit;
        }
        Pages::profile($api, $id);
        break;
    case 'badges':
        Pages::badges($api);
        break;
    case 'market':
        Pages::market($api);
        break;
    case 'top-credits':
        Pages::topCredits($api);
        break;
    case 'motd':
        Motd::render($api);
        break;
    case 'map':
        $map = Support::cleanMap($parts[1] ?? '');
        $mode = Support::mode(Support::modeId($parts[2] ?? 'normal'));
        header('Location: ' . Support::url('/motd', ['map' => $map, 'mode' => $mode['key']]), true, 302);
        exit;
    default:
        http_response_code(404);
        Layout::header('Page not found');
        echo '<main id="content" class="content-wrap page-body">';
        Layout::pageIntro('404 / OFF ROUTE', 'That line ends here.', 'The requested page does not exist on this timing network.');
        echo '<a class="button button-light" href="' . Support::e(Support::url('/')) . '">Return to timing</a></main>';
        Layout::footer();
}
