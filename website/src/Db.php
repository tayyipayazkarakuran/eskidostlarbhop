<?php

declare(strict_types=1);

require_once __DIR__ . '/../config.php';

final class Db
{
    private static ?PDO $pdo = null;
    /** @var array{ok:bool,message:string}|null */
    private static ?array $schemaStatus = null;

    public static function tableName(string $suffix): string
    {
        if (!preg_match('/^[a-z][a-z0-9_]*$/', $suffix)) {
            throw new InvalidArgumentException('Invalid database table suffix.');
        }
        return DB_TABLE_PREFIX . $suffix;
    }

    private static function table(string $suffix): string
    {
        return sprintf('%c%s%c', 96, self::tableName($suffix), 96);
    }

    public static function connect(): ?PDO
    {
        if (self::$pdo !== null) {
            return (self::$schemaStatus['ok'] ?? true) ? self::$pdo : null;
        }

        if (!DB_CONFIGURED) {
            return null;
        }

        $dsn = sprintf(
            'mysql:host=%s;port=%d;dbname=%s;charset=%s',
            DB_HOST,
            DB_PORT,
            DB_NAME,
            DB_CHARSET
        );

        try {
            self::$pdo = new PDO($dsn, DB_USER, DB_PASS, [
                PDO::ATTR_ERRMODE            => PDO::ERRMODE_EXCEPTION,
                PDO::ATTR_DEFAULT_FETCH_MODE => PDO::FETCH_ASSOC,
                PDO::ATTR_EMULATE_PREPARES   => false,
                PDO::ATTR_TIMEOUT            => 3,
            ]);
            self::$schemaStatus = self::inspectSchema(self::$pdo);
            if (!self::$schemaStatus['ok']) {
                return null;
            }
        } catch (PDOException $e) {
            error_log('Leaderboard database connection failed.');
            self::$pdo = null;
        }

        return self::$pdo;
    }

    public static function connected(): bool
    {
        return self::connect() !== null;
    }

    public static function tablesExist(): bool
    {
        return self::schemaStatus()['ok'];
    }

    /** @return array{ok:bool,message:string} */
    public static function schemaStatus(): array
    {
        if (self::$schemaStatus !== null) {
            return self::$schemaStatus;
        }

        $pdo = self::connect();
        if (self::$schemaStatus !== null) {
            return self::$schemaStatus;
        }
        if (!$pdo) {
            return self::$schemaStatus = [
                'ok' => false,
                'message' => DB_CONFIGURED
                    ? 'The leaderboard database is currently unavailable.'
                    : 'Database configuration is missing.',
            ];
        }

        return self::$schemaStatus = self::inspectSchema($pdo);
    }

    /** @return array{ok:bool,message:string} */
    private static function inspectSchema(PDO $pdo): array
    {
        try {
            foreach (REQUIRED_SCHEMA as $table => $requiredColumns) {
                $tableName = self::table($table);
                $rows = $pdo->query("SHOW COLUMNS FROM {$tableName}")->fetchAll();
                $actual = array_column($rows, 'Field');
                if (array_diff($requiredColumns, $actual)) {
                    return ['ok' => false, 'message' => 'The database schema is not compatible with the current timer plugin.'];
                }
            }
        } catch (PDOException $e) {
            return ['ok' => false, 'message' => 'The database schema is not compatible with the current timer plugin.'];
        }

        return ['ok' => true, 'message' => ''];
    }

    /**
     * Convert a base map + mode into the suffixed map name used in this database.
     */
    public static function mapForMode(string $baseMap, int $modeId): string
    {
        $suffix = MODE_SUFFIXES[self::getModeKey($modeId)] ?? '';
        return $suffix !== '' ? $baseMap . $suffix : $baseMap;
    }

    /**
     * Query best records by map and mode, with optional legacy suffix fallback.
     *
     * @return array<int, array{map:string,authid:string,name:string,best_time_ms:int,updated_at:int,mode:int}>
     */
    private static function getBestRecordsForMapMode(string $baseMap, int $mode, int $limit): array
    {
        $baseMap = self::normalizeMapName($baseMap) ?? '';
        if ($baseMap === '' || !isset(MODES[$mode])) {
            return [];
        }

        $pdo = self::connect();
        if (!$pdo) {
            return [];
        }

        $bestTable = self::table('best');
        // Try new-style: clean map name + mode column
        $sql = "SELECT * FROM {$bestTable}
                WHERE map = :map AND mode = :mode
                ORDER BY best_time_ms ASC
                LIMIT :limit";

        $stmt = $pdo->prepare($sql);
        $stmt->bindValue(':map', $baseMap, PDO::PARAM_STR);
        $stmt->bindValue(':mode', $mode, PDO::PARAM_INT);
        $stmt->bindValue(':limit', $limit, PDO::PARAM_INT);
        $stmt->execute();
        $rows = $stmt->fetchAll();

        if (!empty($rows)) {
            return $rows;
        }

        // Legacy fallback: try suffixed map name with mode=0
        $suffixed = self::mapForMode($baseMap, $mode);
        if ($suffixed !== $baseMap) {
            $sql2 = "SELECT * FROM {$bestTable}
                     WHERE map = :map AND mode = 0
                     ORDER BY best_time_ms ASC
                     LIMIT :limit";

            $stmt2 = $pdo->prepare($sql2);
            $stmt2->bindValue(':map', $suffixed, PDO::PARAM_STR);
            $stmt2->bindValue(':limit', $limit, PDO::PARAM_INT);
            $stmt2->execute();
            return $stmt2->fetchAll();
        }

        return [];
    }

    // -----------------------------------------------------------------------
    // Queries
    // -----------------------------------------------------------------------

    /**
     * @return array<int, array{authid:string,name:string,total_records:int,absolute_best_ms:int,last_active:int}>
     */
    public static function getPro15Global(int $limit = PRO_LIMIT): array
    {
        $pdo = self::connect();
        if (!$pdo) {
            return [];
        }

        $bestTable = self::table('best');
        $sql = "SELECT
                    authid,
                    SUBSTRING_INDEX(GROUP_CONCAT(name ORDER BY updated_at DESC SEPARATOR '\n'), '\n', 1) AS name,
                    COUNT(*) AS total_records,
                    MIN(best_time_ms) AS absolute_best_ms,
                    MAX(updated_at) AS last_active
                FROM {$bestTable}
                GROUP BY authid
                ORDER BY total_records DESC, absolute_best_ms ASC
                LIMIT :limit";

        $stmt = $pdo->prepare($sql);
        $stmt->bindValue(':limit', $limit, PDO::PARAM_INT);
        $stmt->execute();

        return $stmt->fetchAll();
    }

    /**
     * @return array<int, array{id:int,record_key:string,map:string,authid:string,name:string,mode:int,time_ms:int,created_at:int}>
     */
    public static function getRecords(?string $map = null, ?string $authid = null, int $limit = 100, ?int $mode = null): array
    {
        $pdo = self::connect();
        if (!$pdo) {
            return [];
        }

        $clauses = [];
        $params = [];

        if ($map !== null && $map !== '') {
            $map = self::normalizeMapName($map);
            if ($map === null) {
                return [];
            }
            $clauses[] = 'map = :map';
            $params[':map'] = $map;
        }

        if ($authid !== null && $authid !== '') {
            $clauses[] = 'authid = :authid';
            $params[':authid'] = $authid;
        }

        if ($mode !== null && isset(MODES[$mode])) {
            $clauses[] = 'mode = :mode';
            $params[':mode'] = $mode;
        }

        $where = $clauses ? 'WHERE ' . implode(' AND ', $clauses) : '';
        $recordsTable = self::table('records');
        $sql = "SELECT * FROM {$recordsTable} {$where} ORDER BY created_at DESC LIMIT :limit";

        $stmt = $pdo->prepare($sql);
        foreach ($params as $key => $value) {
            $stmt->bindValue($key, $value, is_int($value) ? PDO::PARAM_INT : PDO::PARAM_STR);
        }
        $stmt->bindValue(':limit', $limit, PDO::PARAM_INT);
        $stmt->execute();

        return $stmt->fetchAll();
    }

    /**
     * @return array<int, array{map:string,authid:string,name:string,best_time_ms:int,updated_at:int,mode:int}>
     */
    public static function getBestRecords(?string $map = null, ?string $authid = null, int $limit = 200, ?int $mode = null): array
    {
        $pdo = self::connect();
        if (!$pdo) {
            return [];
        }

        $clauses = [];
        $params = [];

        if ($map !== null && $map !== '') {
            $map = self::normalizeMapName($map);
            if ($map === null) {
                return [];
            }
            $clauses[] = 'map = :map';
            $params[':map'] = $map;
        }

        if ($authid !== null && $authid !== '') {
            $clauses[] = 'authid = :authid';
            $params[':authid'] = $authid;
        }

        if ($mode !== null && isset(MODES[$mode])) {
            $clauses[] = 'mode = :mode';
            $params[':mode'] = $mode;
        }

        $where = $clauses ? 'WHERE ' . implode(' AND ', $clauses) : '';
        $bestTable = self::table('best');
        $sql = "SELECT * FROM {$bestTable} {$where} ORDER BY best_time_ms ASC, updated_at DESC LIMIT :limit";

        $stmt = $pdo->prepare($sql);
        foreach ($params as $key => $value) {
            $stmt->bindValue($key, $value, is_int($value) ? PDO::PARAM_INT : PDO::PARAM_STR);
        }
        $stmt->bindValue(':limit', $limit, PDO::PARAM_INT);
        $stmt->execute();

        return $stmt->fetchAll();
    }

    /**
     * @return array<int, array{map:string,record_count:int,world_record_ms:int|null,wr_holder:string|null}>
     */
    public static function getMaps(): array
    {
        $pdo = self::connect();
        if (!$pdo) {
            return [];
        }

        $bestTable = self::table('best');
        $sql = "SELECT
                    b.map,
                    b.mode,
                    COUNT(*) AS record_count,
                    MIN(b.best_time_ms) AS world_record_ms,
                    (
                        SELECT b2.name FROM {$bestTable} b2
                        WHERE b2.map = b.map AND b2.mode = b.mode
                        ORDER BY b2.best_time_ms ASC, b2.updated_at DESC LIMIT 1
                    ) AS wr_holder
                FROM {$bestTable} b
                GROUP BY b.map, b.mode
                ORDER BY b.map ASC, b.mode ASC";

        $stmt = $pdo->query($sql);
        $rows = $stmt ? $stmt->fetchAll() : [];
        $maps = [];
        foreach ($rows as $row) {
            $map = $row['map'];
            $wrTime = (int) $row['world_record_ms'];
            if (!isset($maps[$map])) {
                $maps[$map] = [
                    'map' => $map,
                    'record_count' => 0,
                    'world_record_ms' => $wrTime,
                    'wr_holder' => $row['wr_holder'],
                    'modes' => [],
                ];
            }
            $maps[$map]['record_count'] += (int) $row['record_count'];
            if ($wrTime < (int) $maps[$map]['world_record_ms']) {
                $maps[$map]['world_record_ms'] = $wrTime;
                $maps[$map]['wr_holder'] = $row['wr_holder'];
            }
            $mode = (int) $row['mode'];
            $maps[$map]['modes'][] = [
                'mode' => $mode,
                'key' => self::getModeKey($mode),
                'label' => self::getModeLabel($mode),
                'record_count' => (int) $row['record_count'],
                'world_record_ms' => $wrTime,
                'wr_holder' => $row['wr_holder'],
            ];
        }

        return array_values($maps);
    }

    /**
     * @return array<int, array{id:int,record_key:string,map:string,authid:string,name:string,mode:int,time_ms:int,created_at:int}>
     */
    public static function getLiveTicker(int $limit = 15): array
    {
        $pdo = self::connect();
        if (!$pdo) {
            return [];
        }

        $bestTable = self::table('best');
        $recordsTable = self::table('records');
        $sql = "SELECT r.*,
                    CASE WHEN r.time_ms = (
                        SELECT MIN(b.best_time_ms) FROM {$bestTable} b
                        WHERE b.map = r.map AND b.mode = r.mode
                    ) THEN 1 ELSE 0 END AS is_wr,
                    CASE WHEN r.time_ms = (
                        SELECT b2.best_time_ms FROM {$bestTable} b2
                        WHERE b2.map = r.map AND b2.mode = r.mode AND b2.authid = r.authid
                        LIMIT 1
                    ) THEN 1 ELSE 0 END AS is_pb
                FROM {$recordsTable} r ORDER BY r.created_at DESC LIMIT :limit";
        $stmt = $pdo->prepare($sql);
        $stmt->bindValue(':limit', $limit, PDO::PARAM_INT);
        $stmt->execute();

        return $stmt->fetchAll();
    }

    /**
     * @return array<string, mixed>|null
     */
    public static function getPlayerProfile(string $authid): ?array
    {
        $pdo = self::connect();
        if (!$pdo) {
            return null;
        }

        $bestTable = self::table('best');
        $recordsTable = self::table('records');
        $bests = $pdo->prepare("SELECT * FROM {$bestTable} WHERE authid = :authid ORDER BY best_time_ms ASC, updated_at DESC");
        $bests->execute([':authid' => $authid]);
        $bestRows = $bests->fetchAll();

        $records = $pdo->prepare("SELECT * FROM {$recordsTable} WHERE authid = :authid ORDER BY created_at DESC LIMIT 500");
        $records->execute([':authid' => $authid]);
        $recordRows = $records->fetchAll();

        $ranking = $pdo->query("
            SELECT authid
            FROM (
                SELECT authid, COUNT(*) AS total_records, MIN(best_time_ms) AS absolute_best_ms
                FROM {$bestTable}
                GROUP BY authid
            ) ranked
            ORDER BY total_records DESC, absolute_best_ms ASC
        ")->fetchAll(PDO::FETCH_COLUMN);

        $rankIndex = array_search($authid, $ranking, true);

        $summary = $pdo->prepare("SELECT COUNT(*) AS total_records, MIN(created_at) AS first_active, MAX(created_at) AS last_run FROM {$recordsTable} WHERE authid = :authid");
        $summary->execute([':authid' => $authid]);
        $recordSummary = $summary->fetch() ?: ['total_records' => 0, 'first_active' => 0, 'last_run' => 0];

        $totalBests = count($bestRows);
        $totalRecords = (int) $recordSummary['total_records'];
        if ($totalBests === 0 && $totalRecords === 0) {
            return null;
        }

        $firstActive = (int) ($recordSummary['first_active'] ?? 0);
        $lastActive = (int) ($recordSummary['last_run'] ?? 0);
        if ($bestRows) {
            $lastActive = max($lastActive, max(array_map(static fn ($r) => (int) $r['updated_at'], $bestRows)));
        }

        return [
            'authid'       => $authid,
            'bests'        => $bestRows,
            'records'      => $recordRows,
            'totalBests'   => $totalBests,
            'totalRecords' => $totalRecords,
            'rank'         => $rankIndex !== false ? $rankIndex + 1 : null,
            'firstActive'  => $firstActive,
            'lastActive'   => $lastActive,
        ];
    }

    /**
     * @return array<int, array{map:string,authid:string,name:string,best_time_ms:int,updated_at:int,mode:int}>
     */
    public static function getPro15ForMap(string $baseMap, int $mode, int $limit = PRO_LIMIT): array
    {
        return self::getBestRecordsForMapMode($baseMap, $mode, $limit);
    }

    /**
     * @return array{name:string,best_time_ms:int}|null
     */
    public static function getWrForMap(string $baseMap, int $mode): ?array
    {
        $rows = self::getBestRecordsForMapMode($baseMap, $mode, 1);
        return $rows[0] ?? null;
    }

    public static function getTotalPlayersCount(): int
    {
        $pdo = self::connect();
        if (!$pdo) {
            return 0;
        }

        $bestTable = self::table('best');
        $stmt = $pdo->query("SELECT COUNT(DISTINCT authid) AS total FROM {$bestTable}");
        if ($stmt && $row = $stmt->fetch()) {
            return (int) $row['total'];
        }

        return 0;
    }

    public static function getModeFromParam(string $param): int
    {
        $param = strtolower(trim($param));

        // Numeric mode IDs
        $num = (int) $param;
        if ((string) $num === $param && isset(MODES[$num])) {
            return $num;
        }

        return match ($param) {
            'normal', 'normal131', 'normal_131', 'normal 131', '131' => 0,
            'lowgrav', 'low_gravity', 'lowgravity' => 1,
            'dbjump', 'doublejump', 'double_jump' => 2,
            'normal200', 'normal_200', 'normal 200', '200' => 3,
            'normal333', 'normal_333', 'normal 333', '333' => 4,
            'normal500', 'normal_500', 'normal 500', '500' => 5,
            'normal1000', 'normal_1000', 'normal 1000', '1000' => 6,
            'simple', 'smp' => 7,
            default => 0,
        };
    }

    public static function normalizeMapName(string $map): ?string
    {
        $map = trim($map);
        return preg_match('/^[A-Za-z0-9_-]{1,64}$/', $map) ? $map : null;
    }

    public static function getModeKey(int $modeId): string
    {
        return MODES[$modeId] ?? 'normal';
    }

    public static function getModeLabel(int $modeId): string
    {
        return MODE_LABELS[self::getModeKey($modeId)] ?? 'Normal';
    }

    public static function getModeFps(int $modeId): int
    {
        return MODE_FPS[self::getModeKey($modeId)] ?? 131;
    }

    public static function isNormalMode(int $modeId): bool
    {
        return in_array($modeId, NORMAL_FPS_MODE_IDS, true);
    }

    /**
     * @return int[]
     */
    public static function getDisplayModeOrder(): array
    {
        return MODE_DISPLAY_ORDER;
    }

    // -----------------------------------------------------------------------
    // Badge helpers
    // -----------------------------------------------------------------------

    /**
     * @return array<int, string> threshold => name
     */
    public static function getBadgeThresholds(): array
    {
        return BADGE_THRESHOLDS;
    }

    /**
     * @return array<int, array{name:string,threshold:int}>
     */
    public static function getPlayerBadges(int $totalCredits): array
    {
        $badges = [];
        foreach (BADGE_THRESHOLDS as $threshold => $name) {
            if ($totalCredits >= $threshold) {
                $badges[] = ['name' => $name, 'threshold' => $threshold];
            }
        }
        return $badges;
    }

    /**
     * @return array{name:string,threshold:int}|null
     */
    public static function getPlayerHighestBadge(int $totalCredits): ?array
    {
        $badges = self::getPlayerBadges($totalCredits);
        return $badges ? end($badges) : null;
    }

    /**
     * @return array{name:string,threshold:int,progressCurrent:int,progressNeeded:int,progressPct:int}|null
     */
    public static function getNextBadge(int $totalCredits): ?array
    {
        $prevThreshold = 0;
        foreach (BADGE_THRESHOLDS as $threshold => $name) {
            if ($totalCredits < $threshold) {
                $progressNeeded = $threshold - $prevThreshold;
                $progressCurrent = $totalCredits - $prevThreshold;
                $progressPct = $progressNeeded > 0
                    ? min(100, max(0, (int) round(($progressCurrent / $progressNeeded) * 100)))
                    : 100;
                return [
                    'name' => $name,
                    'threshold' => $threshold,
                    'progressCurrent' => $progressCurrent,
                    'progressNeeded' => $progressNeeded,
                    'progressPct' => $progressPct,
                ];
            }
            $prevThreshold = $threshold;
        }
        return null;
    }

    // -----------------------------------------------------------------------
    // bhop_players queries
    // -----------------------------------------------------------------------

    /** @return array<string,mixed>|null */
    public static function getPlayerIdentity(string $identifier): ?array
    {
        $pdo = self::connect();
        $identifier = trim($identifier);
        if (!$pdo || $identifier === '' || strlen($identifier) > 96) {
            return null;
        }

        $playersTable = self::table('players');
        $sql = "SELECT player_key, identity_type, steamid64, authid, name,
                       total_credits, spent_credits, hook_reward, custom_prefix,
                       updated_at AS last_seen
                FROM {$playersTable}
                WHERE player_key = :player_key OR steamid64 = :steamid64 OR authid = :authid
                ORDER BY CASE WHEN player_key = :order_key THEN 0
                              WHEN steamid64 = :order_steam THEN 1 ELSE 2 END
                LIMIT 1";

        $stmt = $pdo->prepare($sql);
        $stmt->execute([
            ':player_key' => $identifier, ':steamid64' => $identifier, ':authid' => $identifier,
            ':order_key' => $identifier, ':order_steam' => $identifier,
        ]);
        $row = $stmt->fetch();
        return $row ?: null;
    }

    /** @return array<string,mixed>|null */
    public static function getPlayerCredits(string $identifier): ?array
    {
        return self::getPlayerIdentity($identifier);
    }

    public static function getPlayersCount(): int
    {
        $pdo = self::connect();
        if (!$pdo) {
            return 0;
        }

        $playersTable = self::table('players');
        $sql = "SELECT COUNT(*) AS total FROM {$playersTable}";
        $stmt = $pdo->query($sql);

        if ($stmt && $row = $stmt->fetch()) {
            return (int) $row['total'];
        }

        return 0;
    }

    /**
     * @return array<int, array{steamid64:string,name:string,total_credits:int,spent_credits:int,hook_reward:int}>
     */
    public static function getTopPlayersByCredits(int $limit = 15): array
    {
        $pdo = self::connect();
        if (!$pdo) {
            return [];
        }

        $playersTable = self::table('players');
        $sql = "SELECT player_key, identity_type, steamid64, authid, name, total_credits, spent_credits, hook_reward
                FROM {$playersTable}
                ORDER BY total_credits DESC
                LIMIT :limit";

        $stmt = $pdo->prepare($sql);
        $stmt->bindValue(':limit', $limit, PDO::PARAM_INT);
        $stmt->execute();

        return $stmt->fetchAll();
    }

    // -----------------------------------------------------------------------
    // bhop_inventory + market queries
    // -----------------------------------------------------------------------

    /**
     * @return array<int, array{item_id:int,purchased_at:int,name:string,item_type:string}>
     */
    public static function getPlayerInventory(string $playerKey, string $steamid64 = ''): array
    {
        $pdo = self::connect();
        if (!$pdo) {
            return [];
        }

        $inventoryTable = self::table('inventory');
        $marketTable = self::table('market_items');
        $legacyKey = $steamid64 !== '' ? $steamid64 : $playerKey;
        $sql = "SELECT i.item_id, i.purchased_at, m.name, m.item_type
                FROM {$inventoryTable} i
                LEFT JOIN {$marketTable} m ON i.item_id = m.item_id
                WHERE i.player_key = :player_key OR i.player_key = :legacy_key
                ORDER BY i.purchased_at DESC";

        $stmt = $pdo->prepare($sql);
        $stmt->execute([':player_key' => $playerKey, ':legacy_key' => $legacyKey]);

        return $stmt->fetchAll();
    }

    /**
     * @return array<int, array{item_id:int,name:string,price:int,item_type:string,effect_value:int}>
     */
    public static function getMarketItems(): array
    {
        $pdo = self::connect();
        if (!$pdo) {
            return [];
        }

        $marketTable = self::table('market_items');
        $sql = "SELECT item_id, name, price, item_type, effect_value
                FROM {$marketTable}
                ORDER BY CASE item_type
                    WHEN 'custom_prefix' THEN 1 WHEN 'join_message' THEN 1
                    WHEN 'knife' THEN 2 WHEN 'knife_skin' THEN 2 WHEN 'vip_skin' THEN 3
                    WHEN 'wrsound' THEN 4 WHEN 'wr_sound' THEN 4 WHEN 'trail' THEN 5
                    ELSE 6 END, item_id ASC";

        $stmt = $pdo->query($sql);

        return $stmt ? $stmt->fetchAll() : [];
    }

    public static function getMarketTypeLabel(string $type): string
    {
        return MARKET_TYPE_LABELS[$type] ?? ucwords(str_replace('_', ' ', $type));
    }
}
