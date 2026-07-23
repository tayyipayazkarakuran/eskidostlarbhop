<?php

declare(strict_types=1);

final class Support
{
    private const MARKET_CATALOG = [
        1 => ['item_id' => 1, 'name' => 'Custom Chat Prefix', 'price' => 1000, 'item_type' => 'custom_prefix', 'effect_value' => 1],
        2 => ['item_id' => 2, 'name' => 'Custom Join Message', 'price' => 500, 'item_type' => 'join_message', 'effect_value' => 1],
        10 => ['item_id' => 10, 'name' => 'Talon Knife Skin', 'price' => 2000, 'item_type' => 'knife', 'effect_value' => 1],
        11 => ['item_id' => 11, 'name' => 'Bayonet Knife Skin', 'price' => 2000, 'item_type' => 'knife', 'effect_value' => 2],
        12 => ['item_id' => 12, 'name' => 'Karambit Knife Skin', 'price' => 2000, 'item_type' => 'knife', 'effect_value' => 3],
        13 => ['item_id' => 13, 'name' => 'Butterfly Knife Skin', 'price' => 2000, 'item_type' => 'knife', 'effect_value' => 4],
        20 => ['item_id' => 20, 'name' => 'VIP Gold Knife', 'price' => 3000, 'item_type' => 'vip_skin', 'effect_value' => 5],
        21 => ['item_id' => 21, 'name' => 'VIP M9 Bayonet', 'price' => 3000, 'item_type' => 'vip_skin', 'effect_value' => 6],
        30 => ['item_id' => 30, 'name' => 'WR Sound 1', 'price' => 1500, 'item_type' => 'wrsound', 'effect_value' => 1],
        31 => ['item_id' => 31, 'name' => 'WR Sound 2', 'price' => 1500, 'item_type' => 'wrsound', 'effect_value' => 2],
        32 => ['item_id' => 32, 'name' => 'WR Sound 3', 'price' => 1500, 'item_type' => 'wrsound', 'effect_value' => 3],
        40 => ['item_id' => 40, 'name' => 'Red Trail', 'price' => 1000, 'item_type' => 'trail', 'effect_value' => 1],
        41 => ['item_id' => 41, 'name' => 'Blue Trail', 'price' => 1000, 'item_type' => 'trail', 'effect_value' => 2],
        42 => ['item_id' => 42, 'name' => 'Green Trail', 'price' => 1000, 'item_type' => 'trail', 'effect_value' => 3],
        43 => ['item_id' => 43, 'name' => 'Yellow Trail', 'price' => 1000, 'item_type' => 'trail', 'effect_value' => 4],
        44 => ['item_id' => 44, 'name' => 'Purple Trail', 'price' => 1000, 'item_type' => 'trail', 'effect_value' => 5],
    ];

    public const MODES = [
        0 => ['key' => 'normal', 'label' => 'Normal 131 FPS', 'short' => '131'],
        3 => ['key' => 'normal200', 'label' => 'Normal 200 FPS', 'short' => '200'],
        4 => ['key' => 'normal333', 'label' => 'Normal 333 FPS', 'short' => '333'],
        5 => ['key' => 'normal500', 'label' => 'Normal 500 FPS', 'short' => '500'],
        6 => ['key' => 'normal1000', 'label' => 'Normal 1000 FPS', 'short' => '1000'],
        1 => ['key' => 'lowgrav', 'label' => 'Low Gravity', 'short' => 'LOW G'],
        2 => ['key' => 'dbjump', 'label' => 'Double Jump', 'short' => 'D-JUMP'],
        7 => ['key' => 'simple', 'label' => 'Simple', 'short' => 'SMP'],
    ];

    public const BADGES = [
        10 => 'Bronze I', 50 => 'Bronze II', 100 => 'Silver I', 250 => 'Silver II',
        500 => 'Gold I', 1000 => 'Gold II', 2000 => 'Platinum I', 5000 => 'Platinum II',
        10000 => 'Diamond I', 20000 => 'Diamond II',
    ];

    public static function e(mixed $value): string
    {
        return htmlspecialchars((string) $value, ENT_QUOTES | ENT_SUBSTITUTE, 'UTF-8');
    }

    public static function url(string $path, array $query = []): string
    {
        global $config;
        $url = $config['base_url'] . '/' . ltrim($path, '/');
        if ($query !== []) {
            $url .= '?' . http_build_query($query, '', '&', PHP_QUERY_RFC3986);
        }
        return $url;
    }

    public static function asset(string $path): string
    {
        $file = dirname(__DIR__) . '/assets/' . ltrim($path, '/');
        $version = is_file($file) ? '?v=' . (string) filemtime($file) : '';
        return self::url('/assets/' . ltrim($path, '/')) . $version;
    }

    public static function number(mixed $value): int
    {
        return is_numeric($value) ? (int) $value : 0;
    }

    public static function bool(mixed $value): bool
    {
        if (is_bool($value)) {
            return $value;
        }
        return self::number($value) !== 0;
    }

    public static function time(mixed $milliseconds): string
    {
        $ms = self::number($milliseconds);
        if ($ms <= 0) {
            return '--:--.---';
        }
        $minutes = intdiv($ms, 60000);
        $seconds = intdiv($ms % 60000, 1000);
        return sprintf('%d:%02d.%03d', $minutes, $seconds, $ms % 1000);
    }

    public static function date(mixed $timestamp): string
    {
        $value = self::number($timestamp);
        return $value > 0 ? date('M j, Y · H:i', $value) : '—';
    }

    public static function relativeTime(mixed $milliseconds): string
    {
        $value = self::number($milliseconds);
        if ($value <= 0) {
            return 'Unknown';
        }
        $seconds = max(0, time() - intdiv($value, 1000));
        if ($seconds < 60) return 'Just now';
        if ($seconds < 3600) return intdiv($seconds, 60) . 'm ago';
        if ($seconds < 86400) return intdiv($seconds, 3600) . 'h ago';
        return intdiv($seconds, 86400) . 'd ago';
    }

    public static function duration(mixed $seconds): string
    {
        $value = max(0, (int) round((float) $seconds));
        if ($value < 60) return $value . 's';
        if ($value < 3600) return intdiv($value, 60) . 'm';
        return intdiv($value, 3600) . 'h ' . intdiv($value % 3600, 60) . 'm';
    }

    public static function modeId(mixed $value): int
    {
        $raw = strtolower(trim((string) $value));
        $aliases = [
            '0' => 0, 'normal' => 0, '131' => 0, 'normal131' => 0,
            '3' => 3, 'normal200' => 3, '200' => 3,
            '4' => 4, 'normal333' => 4, '333' => 4,
            '5' => 5, 'normal500' => 5, '500' => 5,
            '6' => 6, 'normal1000' => 6, '1000' => 6,
            '1' => 1, 'lowgrav' => 1, 'low_gravity' => 1,
            '2' => 2, 'dbjump' => 2, 'double_jump' => 2, 'doublejump' => 2,
            '7' => 7, 'simple' => 7, 'smp' => 7,
        ];
        return $aliases[$raw] ?? 0;
    }

    public static function mode(int $id): array
    {
        return self::MODES[$id] ?? self::MODES[0];
    }

    public static function cleanMap(mixed $value): string
    {
        $map = trim((string) $value);
        return preg_match('/^[A-Za-z0-9_-]{1,64}$/', $map) === 1 ? $map : '';
    }

    public static function initials(mixed $name): string
    {
        $parts = preg_split('/\s+/', trim((string) $name)) ?: [];
        $letters = '';
        foreach (array_slice($parts, 0, 2) as $part) {
            if ($part !== '') $letters .= mb_strtoupper(mb_substr($part, 0, 1));
        }
        return $letters !== '' ? $letters : '?';
    }

    public static function steam2To64(string $steamId): ?string
    {
        if (!preg_match('/^STEAM_[01]:([01]):(\d+)$/i', trim($steamId), $match)) {
            return null;
        }
        return (string) (76561197960265728 + ((int) $match[2] * 2) + (int) $match[1]);
    }

    public static function steam64To2(string $steamId64): ?string
    {
        if (!preg_match('/^\d{17}$/', $steamId64)) return null;
        $account = (int) $steamId64 - 76561197960265728;
        if ($account < 0) return null;
        return 'STEAM_0:' . ($account % 2) . ':' . intdiv($account, 2);
    }

    public static function marketType(mixed $type): string
    {
        return match ((string) $type) {
            'custom_prefix' => 'Chat customization',
            'join_message' => 'Join customization',
            'knife', 'knife_skin' => 'Knife skin',
            'vip_skin' => 'VIP knife skin',
            'wrsound', 'wr_sound' => 'WR sound',
            'trail' => 'Trail',
            default => ucwords(str_replace('_', ' ', (string) $type)),
        };
    }

    /**
     * Merge the plugin-owned catalog with database overrides.
     * Legacy IDs 3-7 are superseded by the current 10-44 catalog.
     *
     * @param array<int, array<string,mixed>> $databaseRows
     * @return array<int, array{item_id:int,name:string,price:int,item_type:string,effect_value:int}>
     */
    public static function marketCatalog(array $databaseRows = []): array
    {
        $items = self::MARKET_CATALOG;
        foreach ($databaseRows as $row) {
            $id = self::number($row['item_id'] ?? 0);
            if ($id <= 0 || in_array($id, [3, 4, 5, 6, 7], true)) continue;
            $items[$id] = [
                'item_id' => $id,
                'name' => (string) ($row['name'] ?? ($items[$id]['name'] ?? 'Unknown item')),
                'price' => self::number($row['price'] ?? ($items[$id]['price'] ?? 0)),
                'item_type' => (string) ($row['item_type'] ?? ($items[$id]['item_type'] ?? 'other')),
                'effect_value' => self::number($row['effect_value'] ?? ($items[$id]['effect_value'] ?? 0)),
            ];
        }

        $typeOrder = ['custom_prefix' => 1, 'join_message' => 1, 'knife' => 2, 'knife_skin' => 2, 'vip_skin' => 3, 'wrsound' => 4, 'wr_sound' => 4, 'trail' => 5];
        uasort($items, static function (array $left, array $right) use ($typeOrder): int {
            $category = ($typeOrder[$left['item_type']] ?? 6) <=> ($typeOrder[$right['item_type']] ?? 6);
            return $category !== 0 ? $category : $left['item_id'] <=> $right['item_id'];
        });
        return array_values($items);
    }

    public static function marketItem(int $itemId, array $databaseRows = []): ?array
    {
        foreach (self::marketCatalog($databaseRows) as $item) {
            if ($item['item_id'] === $itemId) return $item;
        }
        return null;
    }

    public static function badgeProgress(int $credits): array
    {
        $currentName = 'Unranked';
        $previous = 0;
        foreach (self::BADGES as $threshold => $name) {
            if ($credits < $threshold) {
                $span = $threshold - $previous;
                return [
                    'current' => $currentName,
                    'next' => $name,
                    'threshold' => $threshold,
                    'value' => max(0, $credits - $previous),
                    'needed' => $span,
                    'percent' => $span > 0 ? min(100, max(0, (int) round((($credits - $previous) / $span) * 100))) : 100,
                ];
            }
            $currentName = $name;
            $previous = $threshold;
        }
        return ['current' => $currentName, 'next' => null, 'threshold' => $previous, 'value' => $credits, 'needed' => $previous, 'percent' => 100];
    }
}
