<?php

declare(strict_types=1);

final class Pages
{
    public static function home(DataClient $api): void
    {
        global $config;
        $rawMap = (string) ($_GET['map'] ?? '');
        $map = Support::cleanMap($rawMap);
        $modeId = Support::modeId($_GET['mode'] ?? 'normal');
        $mode = Support::mode($modeId);
        $tab = in_array($_GET['tab'] ?? '', ['pro15', 'all-records'], true) ? (string) $_GET['tab'] : '';

        $requests = [
            'status' => ['/api/status'],
            'maps' => ['/api/maps'],
            'pro15' => ['/api/pro15', ['limit' => 15]],
            'ticker' => ['/api/live-ticker', ['limit' => 15]],
        ];
        if ($map !== '') {
            $requests['records'] = ['/api/best-records', ['map' => $map, 'mode' => $mode['key'], 'limit' => 15]];
        } elseif ($tab === 'all-records') {
            $requests['records'] = ['/api/best-records', ['mode' => $mode['key'], 'limit' => 200]];
        }
        $responses = $api->multi($requests);

        $status = self::data($responses['status'] ?? null, []);
        $maps = self::listData($responses['maps'] ?? null);
        $pro15 = self::listData($responses['pro15'] ?? null);
        $ticker = self::listData($responses['ticker'] ?? null);
        $records = self::listData($responses['records'] ?? null);
        $game = is_array($status['game'] ?? null) ? $status['game'] : [];
        $gameOnline = (bool) ($game['online'] ?? false);
        $gameMapName = (string) ($game['map'] ?? 'Unavailable');
        $gameMapLength = mb_strlen($gameMapName);
        $gameMapClass = $gameMapLength > 18 ? ' is-very-long' : ($gameMapLength > 11 ? ' is-long' : '');
        $dbConnected = (bool) ($status['connected'] ?? false);
        $schemaCompatible = (bool) ($status['schemaCompatible'] ?? false);

        $fastest = $pro15[0] ?? [];
        foreach ($pro15 as $runner) {
            if (Support::number($runner['absolute_best_ms'] ?? 0) > 0 &&
                (Support::number($fastest['absolute_best_ms'] ?? 0) === 0 || Support::number($runner['absolute_best_ms']) < Support::number($fastest['absolute_best_ms']))) {
                $fastest = $runner;
            }
        }
        $totalRecords = 0;
        foreach ($maps as $mapRow) $totalRecords += Support::number($mapRow['record_count'] ?? 0);

        Layout::header('', 'home');
        ?>
<main id="content">
    <section class="hero-shell">
        <div class="hero-copy">
            <p class="eyebrow"><span class="eyebrow-index">T/01</span> CS 1.6 COMPETITIVE BHOP</p>
            <h1>EVERY<br><span>MILLISECOND</span><br>LEAVES A TRACE.</h1>
            <p class="hero-deck">Live routes, exact splits and the players who keep moving the line.</p>
            <div class="hero-actions">
                <?php if (self::validConnect($config['public_connect'])): ?>
                <button class="button button-light" type="button" data-copy="connect <?= Support::e($config['public_connect']) ?>">
                    Copy connect
                </button>
                <a class="button button-ghost" href="steam://connect/<?= Support::e($config['public_connect']) ?>">Open in Steam</a>
                <?php else: ?>
                <span class="button button-disabled" title="Set BHOP_PUBLIC_CONNECT to enable joining">Connect address unavailable</span>
                <?php endif; ?>
            </div>
        </div>

        <aside class="live-board" data-server-card data-online="<?= $gameOnline ? '1' : '0' ?>">
            <div class="live-board-head">
                <span>LIVE SERVER / A2S</span>
                <span class="online-label" data-game-state><?= $gameOnline ? 'ONLINE' : 'OFFLINE' ?></span>
            </div>
            <div class="server-map">
                <small>CURRENT MAP</small>
                <strong class="server-map-name<?= $gameMapClass ?>" data-game-map><?= Support::e($gameMapName) ?></strong>
            </div>
            <div class="server-count">
                <span><strong data-game-players><?= Support::number($game['players'] ?? 0) ?></strong> / <?= Support::number($game['maxPlayers'] ?? 0) ?></span>
                <small>RUNNERS CONNECTED</small>
            </div>
            <div class="player-strip" data-game-list>
                <?php self::renderPlayers(is_array($game['playerList'] ?? null) ? $game['playerList'] : [], $gameOnline); ?>
            </div>
        </aside>

        <div class="hero-time" aria-label="Fastest recorded time">
            <span class="hero-time-label">FASTEST RECORDED SPLIT</span>
            <strong><?= Support::time($fastest['absolute_best_ms'] ?? 0) ?></strong>
            <span><?= Support::e($fastest['name'] ?? 'Waiting for a recorded run') ?></span>
        </div>
    </section>

    <div class="timing-rail" aria-hidden="true">
        <span class="rail-beam"></span>
        <?php for ($i = 0; $i < 12; $i++): ?><i style="--tick:<?= $i ?>"></i><?php endfor; ?>
        <b>0.000</b><b>0.250</b><b>0.500</b><b>0.750</b><b>1.000</b>
    </div>

    <section class="telemetry" aria-label="Network statistics">
        <div><span>MAPS LOGGED</span><strong><?= count($maps) ?></strong></div>
        <div><span>PERSONAL BESTS</span><strong><?= number_format($totalRecords) ?></strong></div>
        <div><span>TOP RECORD HOLDER</span><strong><?= Support::e($pro15[0]['name'] ?? '—') ?></strong></div>
        <div><span>DATABASE</span><strong><?= $dbConnected ? 'SYNCED' : 'OFFLINE' ?></strong></div>
    </section>

    <div class="content-wrap">
        <?php if (!$api->configured()): ?>
            <?php Layout::alert('DATABASE NOT CONFIGURED', 'Set the BHOP_DB_* environment variables before publishing this site. No placeholder records are shown.'); ?>
        <?php elseif (!($responses['status']['ok'] ?? false)): ?>
            <?php Layout::alert('LIVE DATA UNAVAILABLE', 'The timing API could not be reached. Try again shortly.'); ?>
        <?php elseif (!$dbConnected): ?>
            <?php Layout::alert('DATABASE OFFLINE', 'Leaderboard data is unavailable while the read-only database connection is down.'); ?>
        <?php elseif (!$schemaCompatible): ?>
            <?php Layout::alert('SCHEMA INCOMPATIBLE', 'The timer database is missing required tables or columns.'); ?>
        <?php endif; ?>
        <?php if (($responses['status']['ok'] ?? false) && !$gameOnline): ?>
            <?php Layout::alert('SERVER STATUS UNAVAILABLE', 'Leaderboard data is still online, but the game server did not answer the A2S query.', 'neutral'); ?>
        <?php endif; ?>
        <?php if ($rawMap !== '' && $map === ''): ?>
            <?php Layout::alert('INVALID MAP FILTER', 'Map names may contain only letters, numbers, underscores and hyphens.'); ?>
        <?php endif; ?>

        <section class="section-block" id="maps">
            <div class="section-heading">
                <div><p class="eyebrow"><span class="eyebrow-index">T/02</span> ROUTE INDEX</p><h2>Choose a line.</h2></div>
                <label class="map-search"><span>FILTER MAPS</span><input type="search" placeholder="bhop_..." data-map-search autocomplete="off"></label>
            </div>
            <?php self::modeTabs($modeId, $tab); ?>
            <?php if ($maps === []): ?>
                <?php Layout::emptyState('No maps recorded', 'Completed runs will appear here after the API reports them.'); ?>
            <?php else: ?>
            <div class="map-grid" data-map-grid>
                <?php foreach ($maps as $mapRow): self::mapCard($mapRow, $modeId); endforeach; ?>
            </div>
            <p class="filter-empty" data-filter-empty hidden>No map names match this filter.</p>
            <?php endif; ?>
        </section>

        <?php if ($map !== ''): ?>
        <section class="section-block leaderboard-focus" id="leaderboard">
            <div class="section-heading compact">
                <div><p class="eyebrow"><span class="eyebrow-index">T/03</span> SELECTED ROUTE</p><h2><?= Support::e($map) ?></h2></div>
                <span class="section-context"><?= Support::e($mode['label']) ?> / TOP 15</span>
            </div>
            <?php self::bestRecordsTable($records, false); ?>
        </section>
        <?php elseif ($tab === 'all-records'): ?>
        <section class="section-block leaderboard-focus" id="leaderboard">
            <div class="section-heading compact">
                <div><p class="eyebrow"><span class="eyebrow-index">T/03</span> CURRENT BESTS</p><h2>All records.</h2></div>
                <span class="section-context"><?= Support::e($mode['label']) ?></span>
            </div>
            <?php self::bestRecordsTable($records, true); ?>
        </section>
        <?php endif; ?>

        <div class="dual-grid" id="rankings">
            <section class="section-block">
                <div class="section-heading compact">
                    <div><p class="eyebrow"><span class="eyebrow-index">T/04</span> GLOBAL PRO15</p><h2>Record holders.</h2></div>
                    <a class="text-link" href="<?= Support::e(Support::url('/', ['tab' => 'pro15'])) ?>#rankings">FULL TABLE</a>
                </div>
                <?php self::pro15Table($pro15); ?>
            </section>
            <section class="section-block ticker-panel">
                <div class="section-heading compact">
                    <div><p class="eyebrow"><span class="eyebrow-index">T/05</span> FINISH SIGNAL</p><h2>Live runs.</h2></div>
                    <span class="live-pulse">20S REFRESH</span>
                </div>
                <div class="ticker-list" data-live-ticker>
                    <?php self::ticker($ticker); ?>
                </div>
            </section>
        </div>
    </div>
</main>
        <?php
        Layout::footer();
    }

    public static function profile(DataClient $api, string $id): void
    {
        $result = $api->get('/api/player/' . rawurlencode($id));
        if (!$result['ok']) {
            http_response_code(in_array($result['status'], [404, 503], true) ? $result['status'] : 503);
            Layout::header('Player unavailable');
            echo '<main id="content" class="content-wrap page-body">';
            Layout::pageIntro('PLAYER FILE', 'Player unavailable.', $result['status'] === 404 ? 'No timing or economy profile matches this identifier.' : 'The player service is temporarily unavailable.');
            echo '<a class="button button-ghost" href="' . Support::e(Support::url('/')) . '">Back to timing</a></main>';
            Layout::footer();
            return;
        }
        $player = $result['data'];
        $credits = is_array($player['credits'] ?? null) ? $player['credits'] : null;
        $balance = $credits ? Support::number($credits['total_credits'] ?? 0) - Support::number($credits['spent_credits'] ?? 0) : 0;
        $progress = Support::badgeProgress($credits ? Support::number($credits['total_credits'] ?? 0) : 0);
        $steam = is_array($player['steamProfile'] ?? null) ? $player['steamProfile'] : [];
        $avatar = filter_var($steam['avatar'] ?? null, FILTER_VALIDATE_URL) ? (string) $steam['avatar'] : '';

        Layout::header((string) ($player['name'] ?? 'Player'));
        ?>
<main id="content" class="content-wrap page-body">
    <a class="back-link" href="<?= Support::e(Support::url('/')) ?>">← Back to timing</a>
    <section class="profile-hero">
        <div class="profile-avatar"><?php if ($avatar !== ''): ?><img src="<?= Support::e($avatar) ?>" alt=""><?php else: ?><?= Support::e(Support::initials($player['name'] ?? '')) ?><?php endif; ?></div>
        <div class="profile-title">
            <p class="eyebrow">PLAYER FILE / <?= Support::e($player['authid'] ?? $id) ?></p>
            <h1><?= Support::e($player['name'] ?? 'Unknown player') ?></h1>
            <div class="profile-tags">
                <?php if (!empty($player['steamId64'])): ?><span><?= Support::e($player['steamId64']) ?></span><?php endif; ?>
                <?php if (!empty($player['badge']['name'])): ?><span><?= Support::e($player['badge']['name']) ?></span><?php endif; ?>
            </div>
        </div>
        <?php if (!empty($player['steamId64'])): ?><a class="button button-light profile-steam" target="_blank" rel="noopener" href="https://steamcommunity.com/profiles/<?= Support::e($player['steamId64']) ?>">Steam profile ↗</a><?php endif; ?>
    </section>

    <section class="telemetry profile-metrics">
        <div><span>GLOBAL RANK</span><strong><?= !empty($player['rank']) ? '#' . Support::number($player['rank']) : '—' ?></strong></div>
        <div><span>PERSONAL BESTS</span><strong><?= Support::number($player['totalBests'] ?? 0) ?></strong></div>
        <div><span>RECORDED RUNS</span><strong><?= Support::number($player['totalRecords'] ?? 0) ?></strong></div>
        <div><span>LAST ACTIVE</span><strong class="metric-date"><?= Support::e(Support::date($player['lastActive'] ?? 0)) ?></strong></div>
    </section>

    <?php if ($credits): ?>
    <section class="credit-card">
        <div><p class="eyebrow">ECONOMY SIGNAL</p><h2><?= number_format($balance) ?> <small>AVAILABLE CREDITS</small></h2></div>
        <div class="credit-numbers"><span><?= number_format(Support::number($credits['total_credits'] ?? 0)) ?> earned</span><span><?= number_format(Support::number($credits['spent_credits'] ?? 0)) ?> spent</span></div>
        <div class="progress-label"><span><?= Support::e($progress['current']) ?></span><span><?= $progress['next'] ? 'Next: ' . Support::e($progress['next']) : 'Maximum tier reached' ?></span></div>
        <div class="progress-track" role="progressbar" aria-valuenow="<?= $progress['percent'] ?>" aria-valuemin="0" aria-valuemax="100"><i style="width:<?= $progress['percent'] ?>%"></i></div>
    </section>
    <?php endif; ?>

    <div class="profile-grid">
        <section class="section-block">
            <div class="section-heading compact"><div><p class="eyebrow">PERSONAL BESTS</p><h2>Fastest lines.</h2></div></div>
            <?php self::bestRecordsTable(is_array($player['bests'] ?? null) ? $player['bests'] : [], true); ?>
        </section>
        <aside class="section-block inventory-panel">
            <div class="section-heading compact"><div><p class="eyebrow">LOADOUT</p><h2>Inventory.</h2></div></div>
            <?php $inventory = is_array($player['inventory'] ?? null) ? $player['inventory'] : []; ?>
            <?php if ($inventory === []): ?><?php Layout::emptyState('No items', 'This player has not purchased a market item.'); ?>
            <?php else: ?><ul class="inventory-list"><?php foreach ($inventory as $item): ?><li><span><?= Support::e($item['name'] ?? 'Unknown item') ?><small><?= Support::e(Support::marketType($item['item_type'] ?? '')) ?></small></span><time><?= Support::e(Support::date($item['purchased_at'] ?? 0)) ?></time></li><?php endforeach; ?></ul><?php endif; ?>
        </aside>
    </div>

    <section class="section-block">
        <div class="section-heading compact"><div><p class="eyebrow">RECENT FINISHES</p><h2>Latest attempts.</h2></div></div>
        <?php self::finishTable(is_array($player['records'] ?? null) ? array_slice($player['records'], 0, 50) : []); ?>
    </section>
</main>
        <?php
        Layout::footer();
    }

    public static function badges(DataClient $api): void
    {
        $result = $api->get('/api/badges');
        $badges = self::listData($result);
        Layout::header('Badge progression', 'badges');
        ?>
<main id="content" class="content-wrap page-body">
    <?php Layout::pageIntro('CREDIT MILESTONES', 'Earn the next mark.', 'Badges track total credits earned on the server. Spending credits never removes progress.'); ?>
    <?php if (!$result['ok']): ?><?php Layout::alert('BADGES UNAVAILABLE', 'The badge catalog could not be loaded.'); ?><?php endif; ?>
    <section class="badge-ladder">
        <?php foreach ($badges as $index => $badge): ?>
        <article class="badge-rung">
            <span class="badge-index"><?= str_pad((string) ($index + 1), 2, '0', STR_PAD_LEFT) ?></span>
            <div class="badge-emblem" aria-hidden="true"><i></i><b><?= strtoupper(substr((string) ($badge['name'] ?? '?'), 0, 1)) ?></b></div>
            <div><h2><?= Support::e($badge['name'] ?? 'Unknown tier') ?></h2><p><?= number_format(Support::number($badge['credits'] ?? 0)) ?> total credits</p></div>
        </article>
        <?php endforeach; ?>
        <?php if ($badges === []): ?><?php Layout::emptyState('No badge tiers', 'The API returned an empty badge catalog.'); ?><?php endif; ?>
    </section>
</main>
        <?php
        Layout::footer();
    }

    public static function market(DataClient $api): void
    {
        $result = $api->get('/api/market');
        $items = self::listData($result);
        Layout::header('Credits market', 'market');
        ?>
<main id="content" class="content-wrap page-body">
    <?php Layout::pageIntro('SERVER LOADOUT', 'Spend what you earned.', 'A read-only view of the items available through the in-game credits market.'); ?>
    <?php if (!$result['ok']): ?><?php Layout::alert('MARKET UNAVAILABLE', 'The market catalog could not be loaded.'); ?><?php endif; ?>
    <div class="market-grid">
        <?php foreach ($items as $item): ?>
        <article class="market-item">
            <div class="market-id">ITEM / <?= str_pad((string) Support::number($item['item_id'] ?? 0), 3, '0', STR_PAD_LEFT) ?></div>
            <div class="market-shape" aria-hidden="true"><span></span></div>
            <div class="market-copy"><p><?= Support::e(Support::marketType($item['item_type'] ?? '')) ?></p><h2><?= Support::e($item['name'] ?? 'Unknown item') ?></h2></div>
            <strong><?= number_format(Support::number($item['price'] ?? 0)) ?> <small>CR</small></strong>
        </article>
        <?php endforeach; ?>
    </div>
    <?php if ($items === []): ?><?php Layout::emptyState('No market items', 'The API returned an empty market catalog.'); ?><?php endif; ?>
</main>
        <?php
        Layout::footer();
    }

    public static function topCredits(DataClient $api): void
    {
        $result = $api->get('/api/top-credits', ['limit' => 100]);
        $players = self::listData($result);
        Layout::header('Top credits', 'credits');
        ?>
<main id="content" class="content-wrap page-body">
    <?php Layout::pageIntro('ECONOMY RANKING', 'Credits leave a trail.', 'Automatic player profiles ranked by total credits earned.'); ?>
    <?php if (!$result['ok']): ?><?php Layout::alert('CREDIT RANKING UNAVAILABLE', 'The player economy could not be loaded.'); ?><?php endif; ?>
    <section class="section-block credit-table-wrap">
        <?php if ($players === []): ?><?php Layout::emptyState('No player profiles', 'Credit activity will appear here automatically.'); ?>
        <?php else: ?><div class="table-scroll"><table class="data-table credits-table"><thead><tr><th>Rank</th><th>Runner</th><th>Badge</th><th class="align-right">Balance</th><th class="align-right">Earned</th></tr></thead><tbody>
        <?php foreach ($players as $index => $player): $profileId = (string) ($player['player_key'] ?? ''); ?><tr><td class="rank-cell"><?= str_pad((string) ($index + 1), 2, '0', STR_PAD_LEFT) ?></td><td><?php if ($profileId !== ''): ?><a href="<?= Support::e(Support::url('/profile/' . rawurlencode($profileId))) ?>"><?= Support::e($player['name'] ?? 'Unknown player') ?></a><?php else: ?><?= Support::e($player['name'] ?? 'Unknown player') ?><?php endif; ?></td><td><span class="table-tag"><?= Support::e($player['badge'] ?? 'Unranked') ?></span></td><td class="align-right time-cell"><?= number_format(Support::number($player['balance'] ?? 0)) ?></td><td class="align-right"><?= number_format(Support::number($player['total_credits'] ?? 0)) ?></td></tr><?php endforeach; ?>
        </tbody></table></div><?php endif; ?>
    </section>
</main>
        <?php
        Layout::footer();
    }

    private static function modeTabs(int $selected, string $tab = ''): void
    {
        echo '<div class="mode-tabs" aria-label="Timer modes">';
        foreach (Support::MODES as $id => $mode) {
            $query = ['mode' => $mode['key']];
            if ($tab !== '') $query['tab'] = $tab;
            printf('<a href="%s#maps"%s><span>%s</span><small>%s</small></a>',
                Support::e(Support::url('/', $query)), $id === $selected ? ' class="is-active" aria-current="true"' : '', Support::e($mode['short']), Support::e($mode['label']));
        }
        echo '</div>';
    }

    private static function mapCard(array $row, int $modeId): void
    {
        $name = Support::cleanMap($row['map'] ?? '');
        if ($name === '') return;
        $summary = null;
        foreach (is_array($row['modes'] ?? null) ? $row['modes'] : [] as $candidate) {
            if (Support::number($candidate['mode'] ?? -1) === $modeId) { $summary = $candidate; break; }
        }
        $mode = Support::mode($modeId);
        $count = Support::number($summary['record_count'] ?? 0);
        $time = $summary['world_record_ms'] ?? 0;
        $holder = $summary['wr_holder'] ?? null;
        ?>
<a class="map-card" data-map-card data-map-name="<?= Support::e(strtolower($name)) ?>" href="<?= Support::e(Support::url('/', ['map' => $name, 'mode' => $mode['key']])) ?>#leaderboard">
    <span class="map-card-line" aria-hidden="true"></span>
    <span class="map-name"><?= Support::e($name) ?></span>
    <span class="map-time"><?= Support::time($time) ?></span>
    <span class="map-holder"><?= $holder ? Support::e($holder) : 'No ' . Support::e($mode['short']) . ' record' ?></span>
    <span class="map-count"><?= $count ?> PB<?= $count === 1 ? '' : 'S' ?> ↗</span>
</a>
        <?php
    }

    private static function pro15Table(array $rows): void
    {
        if ($rows === []) { Layout::emptyState('No record holders', 'Global rankings will appear after players set personal bests.'); return; }
        echo '<div class="table-scroll"><table class="data-table"><thead><tr><th>Rank</th><th>Runner</th><th class="align-right">Records</th><th class="align-right">Fastest</th></tr></thead><tbody>';
        foreach ($rows as $index => $row) {
            $href = Support::url('/profile/' . rawurlencode((string) ($row['authid'] ?? '')));
            printf('<tr><td class="rank-cell">%s</td><td><a href="%s">%s</a></td><td class="align-right">%s</td><td class="align-right time-cell">%s</td></tr>',
                str_pad((string) ($index + 1), 2, '0', STR_PAD_LEFT), Support::e($href), Support::e($row['name'] ?? 'Unknown player'), number_format(Support::number($row['total_records'] ?? 0)), Support::time($row['absolute_best_ms'] ?? 0));
        }
        echo '</tbody></table></div>';
    }

    private static function bestRecordsTable(array $rows, bool $showMap): void
    {
        if ($rows === []) { Layout::emptyState('No best times', 'No personal bests match this route and mode.'); return; }
        echo '<div class="table-scroll"><table class="data-table"><thead><tr><th>Rank</th><th>Runner</th>' . ($showMap ? '<th>Map / Mode</th>' : '') . '<th class="align-right">Time</th><th class="align-right">Recorded</th></tr></thead><tbody>';
        foreach ($rows as $index => $row) {
            $href = Support::url('/profile/' . rawurlencode((string) ($row['authid'] ?? '')));
            $mode = Support::mode(Support::number($row['mode'] ?? 0));
            echo '<tr><td class="rank-cell">' . str_pad((string) ($index + 1), 2, '0', STR_PAD_LEFT) . '</td><td><a href="' . Support::e($href) . '">' . Support::e($row['name'] ?? 'Unknown player') . '</a></td>';
            if ($showMap) echo '<td><span class="map-table-name">' . Support::e($row['map'] ?? '—') . '</span><small class="cell-sub">' . Support::e($mode['label']) . '</small></td>';
            echo '<td class="align-right time-cell">' . Support::time($row['best_time_ms'] ?? 0) . '</td><td class="align-right date-cell">' . Support::e(Support::date($row['updated_at'] ?? 0)) . '</td></tr>';
        }
        echo '</tbody></table></div>';
    }

    private static function finishTable(array $rows): void
    {
        if ($rows === []) { Layout::emptyState('No finishes', 'No recorded runs are linked to this player.'); return; }
        echo '<div class="table-scroll"><table class="data-table"><thead><tr><th>Map</th><th>Mode</th><th class="align-right">Time</th><th class="align-right">Finished</th></tr></thead><tbody>';
        foreach ($rows as $row) {
            $mode = Support::mode(Support::number($row['mode'] ?? 0));
            printf('<tr><td class="map-table-name">%s</td><td>%s</td><td class="align-right time-cell">%s</td><td class="align-right date-cell">%s</td></tr>', Support::e($row['map'] ?? '—'), Support::e($mode['label']), Support::time($row['time_ms'] ?? 0), Support::e(Support::date($row['created_at'] ?? 0)));
        }
        echo '</tbody></table></div>';
    }

    private static function ticker(array $rows): void
    {
        if ($rows === []) { Layout::emptyState('No recent finishes', 'New runs will pulse through this feed.'); return; }
        foreach ($rows as $row) {
            $tag = Support::bool($row['is_wr'] ?? false) ? 'WR' : (Support::bool($row['is_pb'] ?? false) ? 'PB' : 'FINISH');
            echo '<article class="ticker-item"><span class="ticker-tag tag-' . strtolower($tag) . '">' . $tag . '</span><div><strong>' . Support::e($row['player'] ?? 'Unknown player') . '</strong><span>' . Support::e($row['map'] ?? '—') . ' · ' . Support::e($row['mode_label'] ?? Support::mode(Support::number($row['mode'] ?? 0))['label']) . '</span></div><time>' . Support::time($row['time'] ?? 0) . '<small>' . Support::e(Support::relativeTime($row['timestamp'] ?? 0)) . '</small></time></article>';
        }
    }

    private static function renderPlayers(array $players, bool $online): void
    {
        if ($players === []) {
            echo '<p>' . ($online ? 'The server is clear. First run is yours.' : 'Player list unavailable.') . '</p>';
            return;
        }
        foreach (array_slice($players, 0, 6) as $player) {
            echo '<span><i></i><b>' . Support::e($player['name'] ?? 'unnamed') . '</b><small>' . Support::e(Support::duration($player['duration'] ?? 0)) . '</small></span>';
        }
    }

    private static function data(?array $result, array $fallback): array
    {
        return ($result['ok'] ?? false) && is_array($result['data'] ?? null) ? $result['data'] : $fallback;
    }

    private static function listData(?array $result): array
    {
        $data = self::data($result, []);
        return array_is_list($data) ? $data : [];
    }

    private static function validConnect(string $address): bool
    {
        return preg_match('/^(?:[A-Za-z0-9.-]+|\[[0-9A-Fa-f:]+\]):\d{1,5}$/', $address) === 1;
    }
}
