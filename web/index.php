<?php
require_once __DIR__ . '/db.php';

$map  = isset($_GET['map'])  ? trim($_GET['map'])  : '';
$mode = isset($_GET['mode']) ? trim($_GET['mode'])  : '';

$is_motd = ($map !== '');

if ($is_motd) {
    $mode_id  = mode_from_param($mode);
    $mode_key = mode_key($mode_id);
    $mode_name = mode_label($mode_id);
    $map_safe  = esc($map);
    $title     = 'Pro15 - ' . $map_safe . ' (' . $mode_name . ')';
} else {
    $mode_id   = isset($_GET['m']) ? mode_from_param($_GET['m']) : 0;
    $mode_key  = mode_key($mode_id);
    $mode_name = mode_label($mode_id);
    $title     = 'BMOD Leaderboard';
}

$pdo = db_connect();
$db_ok = db_tables_exist($pdo);
if (!$db_ok && $pdo) {
    db_ensure_schema($pdo);
    $db_ok = db_tables_exist($pdo);
}
?>
<!DOCTYPE html>
<html>
<head>
<meta charset="utf-8">
<?php if (!$is_motd): ?>
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<?php endif; ?>
<title><?php echo $title; ?></title>
<style>
<?php echo file_get_contents(__DIR__ . '/style.css'); ?>
<?php if ($is_motd): ?>
.motd-only { display: block; }
.full-only  { display: none; }
<?php else: ?>
.motd-only { display: none; }
.full-only  { display: block; }
<?php endif; ?>
</style>
</head>
<body>

<?php if ($is_motd): ?>
<div class="site-header">
    <h1><?php echo esc($map); ?></h1>
    <p><?php echo $mode_name; ?> &middot; Pro15</p>
</div>

<div class="container">
    <?php
    $wr = get_wr_for_map($pdo, $map, $mode_id);
    if ($wr):
    ?>
    <div class="wr-banner">
        <div class="wr-label">World Record</div>
        <div class="wr-time"><?php echo format_time($wr['time_ms']); ?></div>
        <div class="wr-holder"><?php echo esc($wr['name']); ?></div>
    </div>
    <?php endif; ?>

    <?php
    $records = get_pro15($pdo, $map, $mode_id);
    if (empty($records)):
    ?>
    <div class="no-records">No records yet for this map and mode.</div>
    <?php else: ?>
    <table class="leaderboard">
        <thead>
            <tr>
                <th style="width:30px">#</th>
                <th>Player</th>
                <th style="width:100px;text-align:right">Time</th>
            </tr>
        </thead>
        <tbody>
        <?php foreach ($records as $i => $r): $rank = $i + 1; ?>
            <tr class="rank-<?php echo $rank; ?>">
                <td><?php echo $rank; ?></td>
                <td><?php echo esc($r['name']); ?></td>
                <td style="text-align:right"><?php echo format_time($r['time_ms']); ?></td>
            </tr>
        <?php endforeach; ?>
        </tbody>
    </table>
    <?php endif; ?>

    <div class="motd-footer">
        <a href="/?map=<?php echo urlencode($map); ?>&mode=<?php echo $mode_key; ?>" target="_blank">View full leaderboard</a>
    </div>
</div>

<?php else: ?>

<div class="site-header">
    <h1>BMOD Leaderboard</h1>
    <p>Counter-Strike 1.6 Bhop Timer Records</p>
</div>

<div class="site-nav">
    <a href="/" class="active">All Maps</a>
    <?php foreach (MODES as $mid => $mkey): ?>
    <a href="/?m=<?php echo $mid; ?>"<?php if ($mid === $mode_id) echo ' class="active"'; ?>><?php echo esc(MODE_NAMES[$mkey]); ?></a>
    <?php endforeach; ?>
</div>

<div class="container">

    <?php if ($db_ok):
        $total_players = get_total_records($pdo);
        $all_maps = get_all_maps($pdo);
    ?>
    <div class="stats-bar">
        <div class="stat-box">
            <div class="stat-value"><?php echo count($all_maps); ?></div>
            <div class="stat-label">Maps</div>
        </div>
        <div class="stat-box">
            <div class="stat-value"><?php echo $total_players; ?></div>
            <div class="stat-label">Players</div>
        </div>
        <div class="stat-box">
            <div class="stat-value"><?php echo $mode_name; ?></div>
            <div class="stat-label">Mode</div>
        </div>
    </div>

    <?php if ($map !== ''): ?>
        <a href="/" class="back-link">&larr; All Maps</a>
        <div class="section-title"><?php echo esc($map); ?> &mdash; <?php echo $mode_name; ?></div>

        <?php
        $wr = get_wr_for_map($pdo, $map, $mode_id);
        if ($wr):
        ?>
        <div class="wr-banner">
            <div class="wr-label">World Record</div>
            <div class="wr-time"><?php echo format_time($wr['time_ms']); ?></div>
            <div class="wr-holder"><?php echo esc($wr['name']); ?></div>
        </div>
        <?php endif; ?>

        <?php
        $records = get_pro15($pdo, $map, $mode_id);
        if (empty($records)):
        ?>
        <div class="no-records">No records yet.</div>
        <?php else: ?>
        <table class="leaderboard">
            <thead>
                <tr>
                    <th style="width:30px">#</th>
                    <th>Player</th>
                    <th style="width:100px;text-align:right">Time</th>
                </tr>
            </thead>
            <tbody>
            <?php foreach ($records as $i => $r): $rank = $i + 1; ?>
                <tr class="rank-<?php echo $rank; ?>">
                    <td><?php echo $rank; ?></td>
                    <td><?php echo esc($r['name']); ?></td>
                    <td style="text-align:right"><?php echo format_time($r['time_ms']); ?></td>
                </tr>
            <?php endforeach; ?>
            </tbody>
        </table>
        <?php endif; ?>

    <?php else: ?>

        <div class="section-title">Maps with Records</div>

        <?php if (empty($all_maps)): ?>
        <div class="no-records">No maps have records yet. Players need to complete runs on the server first.</div>
        <?php else: ?>
        <div class="map-grid">
        <?php foreach ($all_maps as $m): ?>
            <a href="/?map=<?php echo urlencode($m); ?>&m=<?php echo $mode_id; ?>" class="map-card">
                <div class="map-name"><?php echo esc($m); ?></div>
                <div class="map-info">
                    <?php
                    $m_wr = get_wr_for_map($pdo, $m, $mode_id);
                    if ($m_wr):
                        echo esc($m_wr['name']) . ' &middot; ' . format_time($m_wr['time_ms']);
                    else:
                        echo 'No records';
                    endif;
                    ?>
                </div>
            </a>
        <?php endforeach; ?>
        </div>
        <?php endif; ?>

    <?php endif; ?>

    <?php else: ?>
    <div class="no-records">
        <p>Database connection failed or tables do not exist yet.</p>
        <p style="margin-top:8px">Make sure the MySQL credentials in <code>db.php</code> are correct and the <code>bhop_timer</code> database has been created.</p>
        <p style="margin-top:8px">See <code>../dist/bmod-server/docs/bhop_timer_mysql_setup.sql</code> for the setup script.</p>
    </div>
    <?php endif; ?>

</div>

<div class="footer">
    BMOD Bhop Timer &middot; CS 1.6
</div>

<?php endif; ?>

</body>
</html>