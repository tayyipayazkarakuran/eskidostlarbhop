<?php

declare(strict_types=1);

final class Motd
{
    public static function render(DataClient $api): void
    {
        $view = strtolower(trim((string) ($_GET['view'] ?? 'pro15')));
        match ($view) {
            'badges' => self::badges($api),
            'topcredits' => self::credits($api),
            'profile' => self::profile($api),
            default => self::pro15($api),
        };
    }

    private static function pro15(DataClient $api): void
    {
        $map = Support::cleanMap($_GET['map'] ?? '');
        $modeId = Support::modeId($_GET['mode'] ?? 'normal');
        $mode = Support::mode($modeId);
        if ($map !== '') {
            $result = $api->get('/api/best-records', ['map' => $map, 'mode' => $mode['key'], 'limit' => 15]);
            $rows = self::listData($result);
            self::header(strtoupper($map), $mode['label']);
            self::modeTabs($map, $modeId);
            self::tableStart('Player', 'Time');
            foreach ($rows as $index => $row) {
                self::rankRow($index + 1, (string) ($row['name'] ?? 'Unknown'), Support::time($row['best_time_ms'] ?? 0), (string) ($row['authid'] ?? ''));
            }
            if ($rows === []) self::emptyRow($result['ok'] ? 'No records for this route.' : 'Timing data unavailable.');
            self::tableEnd();
            self::footer();
            return;
        }

        $result = $api->get('/api/pro15', ['limit' => 15]);
        $rows = self::listData($result);
        self::header('GLOBAL PRO15', 'Record holders by current personal best count');
        self::tableStart('Player', 'Best');
        foreach ($rows as $index => $row) {
            self::rankRow($index + 1, (string) ($row['name'] ?? 'Unknown'), Support::time($row['absolute_best_ms'] ?? 0), (string) ($row['authid'] ?? ''));
        }
        if ($rows === []) self::emptyRow($result['ok'] ? 'No global records.' : 'Timing data unavailable.');
        self::tableEnd();
        self::footer();
    }

    private static function badges(DataClient $api): void
    {
        $result = $api->get('/api/badges');
        $rows = self::listData($result);
        self::header('BADGES', 'Credit milestones');
        self::tableStart('Badge', 'Credits');
        foreach ($rows as $index => $row) {
            echo '<tr><td class="rank">' . ($index + 1) . '</td><td>' . Support::e($row['name'] ?? 'Unknown') . '</td><td class="right mono">' . number_format(Support::number($row['credits'] ?? 0)) . '</td></tr>';
        }
        if ($rows === []) self::emptyRow($result['ok'] ? 'No badge tiers.' : 'Badge data unavailable.');
        self::tableEnd();
        self::footer();
    }

    private static function credits(DataClient $api): void
    {
        $result = $api->get('/api/top-credits', ['limit' => 15]);
        $rows = self::listData($result);
        self::header('TOP CREDITS', 'Automatic player profiles');
        self::tableStart('Player', 'Balance');
        foreach ($rows as $index => $row) {
            self::rankRow($index + 1, (string) ($row['name'] ?? 'Unknown'), number_format(Support::number($row['balance'] ?? 0)), (string) ($row['player_key'] ?? ''));
        }
        if ($rows === []) self::emptyRow($result['ok'] ? 'No player profiles.' : 'Credit data unavailable.');
        self::tableEnd();
        self::footer();
    }

    private static function profile(DataClient $api): void
    {
        $input = trim((string) ($_GET['authid'] ?? ''));
        if ($input === '') {
            header('Location: ' . Support::url('/motd'));
            exit;
        }
        $result = $api->get('/api/player/' . rawurlencode($input));
        $player = ($result['ok'] ?? false) && is_array($result['data'] ?? null) ? $result['data'] : [];
        $bests = is_array($player['bests'] ?? null) ? array_slice($player['bests'], 0, 12) : [];
        $economy = is_array($player['credits'] ?? null) ? $player['credits'] : null;
        $name = (string) ($player['name'] ?? ($bests[0]['name'] ?? 'Unknown player'));
        $subtitle = count($bests) . ' personal bests';
        if ($economy) {
            $balance = Support::number($economy['total_credits'] ?? 0) - Support::number($economy['spent_credits'] ?? 0);
            $subtitle .= ' / ' . number_format($balance) . ' cr';
        }
        self::header($name, $subtitle);
        $displayId = (string) ($player['authid'] ?? $input);
        echo '<div class="profileline"><span class="initials">' . Support::e(Support::initials($name)) . '</span><b>' . Support::e($name) . '</b><small>' . Support::e($displayId) . '</small></div>';
        self::tableStart('Map / Mode', 'Time', false);
        foreach ($bests as $row) {
            $mode = Support::mode(Support::number($row['mode'] ?? 0));
            echo '<tr><td><b>' . Support::e($row['map'] ?? '—') . '</b><small class="sub">' . Support::e($mode['short']) . '</small></td><td class="right mono">' . Support::time($row['best_time_ms'] ?? 0) . '</td></tr>';
        }
        if ($bests === []) self::emptyRow(($result['ok'] ?? false) ? 'No timed records.' : 'Player data unavailable.', 2);
        self::tableEnd();
        self::footer();
    }

    private static function header(string $title, string $subtitle): void
    {
        $cssFile = dirname(__DIR__) . '/assets/css/motd.css';
        $css = is_file($cssFile) ? (string) file_get_contents($cssFile) : '';
        ?>
<!doctype html>
<html>
<head>
<meta charset="utf-8">
<title><?= Support::e($title) ?> - ESKIDOSTLAR BHOP</title>
<style><?= $css ?></style>
</head>
<body>
<div class="frame">
<div class="nav"><a href="<?= Support::e(Support::url('/motd')) ?>">PRO15</a><a href="<?= Support::e(Support::url('/motd', ['view' => 'badges'])) ?>">BADGES</a><a href="<?= Support::e(Support::url('/motd', ['view' => 'topcredits'])) ?>">CREDITS</a><a href="<?= Support::e(Support::url('/')) ?>">WEB</a></div>
<h1><?= Support::e($title) ?></h1>
<p class="subtitle"><?= Support::e($subtitle) ?></p>
        <?php
    }

    private static function modeTabs(string $map, int $selected): void
    {
        echo '<table class="modes"><tr>';
        foreach (Support::MODES as $id => $mode) {
            echo '<td' . ($id === $selected ? ' class="on"' : '') . '><a href="' . Support::e(Support::url('/motd', ['map' => $map, 'mode' => $mode['key']])) . '">' . Support::e($mode['short']) . '</a></td>';
        }
        echo '</tr></table>';
    }

    private static function tableStart(string $middle, string $right, bool $rank = true): void
    {
        echo '<table class="board"><thead><tr>' . ($rank ? '<th class="rank">#</th>' : '') . '<th>' . Support::e($middle) . '</th><th class="right">' . Support::e($right) . '</th></tr></thead><tbody>';
    }

    private static function tableEnd(): void { echo '</tbody></table>'; }

    private static function rankRow(int $rank, string $name, string $value, string $id): void
    {
        $nameCell = $id !== '' ? '<a href="' . Support::e(Support::url('/motd', ['view' => 'profile', 'authid' => $id])) . '">' . Support::e($name) . '</a>' : Support::e($name);
        echo '<tr><td class="rank">' . $rank . '</td><td>' . $nameCell . '</td><td class="right mono">' . Support::e($value) . '</td></tr>';
    }

    private static function emptyRow(string $message, int $columns = 3): void
    {
        echo '<tr><td colspan="' . $columns . '" class="empty">' . Support::e($message) . '</td></tr>';
    }

    private static function footer(): void
    {
        echo '<div class="foot">ESKIDOSTLAR / LIVE TIMING</div></div></body></html>';
    }

    private static function listData(array $result): array
    {
        $data = ($result['ok'] ?? false) && is_array($result['data'] ?? null) ? $result['data'] : [];
        return array_is_list($data) ? $data : [];
    }
}
