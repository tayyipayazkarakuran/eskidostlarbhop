<?php
require_once __DIR__ . '/db.php';

$map  = isset($_GET['map'])  ? trim($_GET['map'])  : '';
$mode = isset($_GET['mode']) ? trim($_GET['mode'])  : 'normal';

$mode_id   = mode_from_param($mode);
$mode_key  = mode_key($mode_id);
$mode_name = mode_label($mode_id);
$map_safe  = esc($map);

$pdo    = db_connect();
$db_ok  = db_tables_exist($pdo);
if (!$db_ok && $pdo) {
    db_ensure_schema($pdo);
    $db_ok = db_tables_exist($pdo);
}
$records = $db_ok ? get_pro15($pdo, $map, $mode_id) : [];
$wr      = $db_ok ? get_wr_for_map($pdo, $map, $mode_id) : null;
?>
<!DOCTYPE html>
<html>
<head>
<meta charset="utf-8">
<title>Pro15 - <?php echo $map_safe; ?> (<?php echo $mode_name; ?>)</title>
<style>
*{margin:0;padding:0;box-sizing:border-box}
body{background:#101218;color:#d7e2ef;font-family:Verdana,Geneva,Tahoma,sans-serif;font-size:11px;line-height:1.4}
a{color:#69d98f;text-decoration:none}
a:hover{text-decoration:underline}
.header{text-align:center;padding:6px 8px;border-bottom:2px solid #69d98f;background:#202936}
.header h1{color:#69d98f;font-size:14px;letter-spacing:1px}
.header p{color:#8899aa;font-size:9px;margin-top:2px}
.wr{background:#202936;border:1px solid #69d98f;border-radius:4px;margin:6px 8px;padding:6px;text-align:center}
.wr .l{font-size:8px;text-transform:uppercase;letter-spacing:2px;color:#69d98f}
.wr .t{font-size:18px;font-weight:bold;color:#ffd700;margin:2px 0}
.wr .n{font-size:10px;color:#d7e2ef}
table{width:100%;border-collapse:collapse;margin:4px 0}
th{background:#202936;color:#69d98f;text-align:left;padding:4px 6px;font-size:9px;text-transform:uppercase;letter-spacing:1px;border-bottom:2px solid #69d98f}
td{padding:3px 6px;border-bottom:1px solid #1a202b;font-size:10px}
tr:nth-child(even) td{background:#141a22}
.r1 td{color:#ffd700}
.r2 td{color:#c0c0c0}
.r3 td{color:#cd7f32}
.empty{text-align:center;padding:16px;color:#8899aa;font-size:10px}
.foot{text-align:center;padding:6px;color:#4a5568;font-size:8px}
.foot a{color:#69d98f}
</style>
</head>
<body>

<div class="header">
    <h1><?php echo $map_safe; ?></h1>
    <p><?php echo $mode_name; ?> Pro15</p>
</div>

<?php if ($wr): ?>
<div class="wr">
    <div class="l">World Record</div>
    <div class="t"><?php echo format_time($wr['time_ms']); ?></div>
    <div class="n"><?php echo esc($wr['name']); ?></div>
</div>
<?php endif; ?>

<?php if (empty($records)): ?>
<div class="empty">No records yet for this map and mode.</div>
<?php else: ?>
<table>
    <thead><tr><th style="width:24px">#</th><th>Player</th><th style="width:85px;text-align:right">Time</th></tr></thead>
    <tbody>
    <?php foreach ($records as $i => $r): $rank = $i + 1; ?>
    <tr class="r<?php echo $rank <= 3 ? $rank : ''; ?>">
        <td><?php echo $rank; ?></td>
        <td><?php echo esc($r['name']); ?></td>
        <td style="text-align:right"><?php echo format_time($r['time_ms']); ?></td>
    </tr>
    <?php endforeach; ?>
    </tbody>
</table>
<?php endif; ?>

<div class="foot">
    <a href="?" target="_blank">Full Leaderboard</a>
</div>

</body>
</html>