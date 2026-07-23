<?php

declare(strict_types=1);

final class LocalDataClient implements DataClient
{
    public function configured(): bool
    {
        return DB_CONFIGURED;
    }

    public function get(string $path, array $query = []): array
    {
        try {
            return $this->dispatch($path, $query);
        } catch (Throwable $error) {
            error_log('Standalone data request failed: ' . $error->getMessage());
            return $this->result(null, 500, 'The local data service failed.');
        }
    }

    public function multi(array $requests): array
    {
        $results = [];
        foreach ($requests as $name => $request) {
            $results[$name] = $this->get($request[0], $request[1] ?? []);
        }
        return $results;
    }

    private function dispatch(string $path, array $query): array
    {
        $parts = explode('/', trim((string) (parse_url($path, PHP_URL_PATH) ?: ''), '/'));
        if (($parts[0] ?? '') !== 'api') return $this->result(null, 404, 'Not found');
        $endpoint = $parts[1] ?? '';

        return match ($endpoint) {
            'status' => $this->status(),
            'pro15' => $this->result($this->pro15($query)),
            'records' => $this->result(Db::getRecords(
                $query['map'] ?? null,
                $query['authid'] ?? null,
                $this->limit($query, 100, 500),
                isset($query['mode']) ? Support::modeId($query['mode']) : null,
            )),
            'best-records' => $this->result($this->bestRecords($query)),
            'maps' => $this->result(Db::getMaps()),
            'live-ticker' => $this->result($this->liveTicker($query)),
            'player' => $this->player(rawurldecode($parts[2] ?? '')),
            'top-credits' => $this->result($this->topCredits($query)),
            'market' => $this->result(Support::marketCatalog(Db::getMarketItems())),
            'badges' => $this->result($this->badges()),
            'steam-profile' => $this->steamProfile($query),
            default => $this->result(null, 404, 'Not found'),
        };
    }

    private function status(): array
    {
        $game = A2S::queryStatus(GAME_HOST, GAME_PORT);
        $schema = Db::schemaStatus();
        return $this->result([
            'connected' => Db::connected(),
            'databaseHost' => null,
            'databaseName' => null,
            'serverName' => $game['name'] ?: 'ESKIDOSTLAR BHOP',
            'errorMessage' => $schema['ok'] ? '' : $schema['message'],
            'bhopSqlEnabled' => Db::connected() ? '1' : '0',
            'schemaCompatible' => $schema['ok'],
            'game' => $game,
        ]);
    }

    private function pro15(array $query): array
    {
        $rows = Db::getPro15Global($this->limit($query, 15, 100));
        return array_map(static fn(array $row): array => [
            'authid' => (string) ($row['authid'] ?? ''),
            'name' => (string) ($row['name'] ?? 'Unknown player'),
            'total_records' => Support::number($row['total_records'] ?? 0),
            'absolute_best_ms' => Support::number($row['absolute_best_ms'] ?? 0),
            'last_active' => Support::number($row['last_active'] ?? 0),
        ], $rows);
    }

    private function bestRecords(array $query): array
    {
        $map = $query['map'] ?? null;
        $mode = isset($query['mode']) ? Support::modeId($query['mode']) : null;
        if (is_string($map) && $map !== '' && $mode !== null) {
            return Db::getPro15ForMap($map, $mode, $this->limit($query, 200, 1000));
        }
        return Db::getBestRecords($map, $query['authid'] ?? null, $this->limit($query, 200, 1000), $mode);
    }

    private function liveTicker(array $query): array
    {
        $rows = Db::getLiveTicker($this->limit($query, 15, 100));
        return array_map(static function (array $row): array {
            $isWr = Support::bool($row['is_wr'] ?? false);
            $isPb = Support::bool($row['is_pb'] ?? false);
            $mode = Support::number($row['mode'] ?? 0);
            return [
                'type' => 'record', 'authid' => (string) ($row['authid'] ?? ''),
                'player' => (string) ($row['name'] ?? 'Unknown player'), 'map' => (string) ($row['map'] ?? ''),
                'mode' => $mode, 'mode_label' => Support::mode($mode)['label'],
                'time' => Support::number($row['time_ms'] ?? 0),
                'change' => $isWr ? 'World record' : ($isPb ? 'Personal best' : 'Finish'),
                'extra' => $isWr ? 'WR' : ($isPb ? 'PB' : 'FINISH'),
                'is_wr' => $isWr, 'is_pb' => $isPb,
                'timestamp' => Support::number($row['created_at'] ?? 0) * 1000,
            ];
        }, $rows);
    }

    private function player(string $authid): array
    {
        $identifier = trim($authid);
        if ($identifier === '' || !preg_match('/^[A-Za-z0-9:_-]{1,96}$/', $identifier)) {
            return $this->result(null, 400, 'A valid player identifier is required');
        }
        if (!Db::tablesExist()) return $this->result(null, 503, Db::schemaStatus()['message']);

        $identity = Db::getPlayerIdentity($identifier);
        $resolvedAuthId = trim((string) ($identity['authid'] ?? ''));
        if ($resolvedAuthId === '' && ctype_digit($identifier) && strlen($identifier) === 17) {
            $resolvedAuthId = Steam::id64toSteam($identifier);
        }
        if ($resolvedAuthId === '') $resolvedAuthId = $identifier;

        $isSteam = Support::number($identity['identity_type'] ?? 0) === 1;
        $steamId64 = $isSteam ? trim((string) ($identity['steamid64'] ?? '')) : '';
        $playerKey = trim((string) ($identity['player_key'] ?? ''));
        $profile = Db::getPlayerProfile($resolvedAuthId);
        $credits = $identity;
        if (!$profile && !$credits) return $this->result(null, 404, 'Player not found');

        $steamProfile = $isSteam && STEAM_ENRICHMENT_ENABLED && preg_match('/^\d{17}$/', $steamId64)
            ? Steam::fetchProfile($steamId64)
            : ['avatar' => null, 'name' => null];
        $latestBest = $profile['bests'][0] ?? null;
        $latestRecord = $profile['records'][0] ?? null;
        $name = $steamProfile['name'] ?: ($latestBest['name'] ?? ($latestRecord['name'] ?? ($credits['name'] ?? 'Unknown player')));
        $inventory = $playerKey !== '' ? Db::getPlayerInventory($playerKey, $steamId64) : [];
        foreach ($inventory as &$inventoryItem) {
            if (!empty($inventoryItem['name']) && !empty($inventoryItem['item_type'])) continue;
            $catalogItem = Support::marketItem(Support::number($inventoryItem['item_id'] ?? 0));
            if ($catalogItem) {
                $inventoryItem['name'] = $catalogItem['name'];
                $inventoryItem['item_type'] = $catalogItem['item_type'];
            }
        }
        unset($inventoryItem);

        return $this->result([
            'authid' => $resolvedAuthId, 'playerKey' => $playerKey,
            'identityType' => Support::number($identity['identity_type'] ?? 0),
            'name' => $name, 'steamId64' => $steamId64,
            'steamProfile' => $steamProfile, 'rank' => $profile['rank'] ?? null,
            'totalRecords' => $profile['totalRecords'] ?? 0, 'totalBests' => $profile['totalBests'] ?? 0,
            'firstActive' => $profile['firstActive'] ?? 0, 'lastActive' => $profile['lastActive'] ?? 0,
            'bests' => $profile['bests'] ?? [], 'records' => $profile['records'] ?? [],
            'credits' => $credits, 'inventory' => $inventory,
            'badge' => $credits ? Db::getPlayerHighestBadge(Support::number($credits['total_credits'] ?? 0)) : null,
        ]);
    }

    private function topCredits(array $query): array
    {
        return array_map(static function (array $row): array {
            $total = Support::number($row['total_credits'] ?? 0);
            $spent = Support::number($row['spent_credits'] ?? 0);
            $badge = Db::getPlayerHighestBadge($total);
            return [
                'player_key' => (string) ($row['player_key'] ?? ''),
                'identity_type' => Support::number($row['identity_type'] ?? 0),
                'steamid64' => (string) ($row['steamid64'] ?? ''),
                'authid' => (string) ($row['authid'] ?? ''),
                'name' => (string) ($row['name'] ?? 'Unknown player'),
                'total_credits' => $total, 'spent_credits' => $spent, 'balance' => $total - $spent,
                'hook_reward' => Support::bool($row['hook_reward'] ?? false), 'badge' => $badge['name'] ?? null,
            ];
        }, Db::getTopPlayersByCredits($this->limit($query, 15, 100)));
    }

    private function badges(): array
    {
        $rows = [];
        foreach (Db::getBadgeThresholds() as $credits => $name) $rows[] = ['name' => $name, 'credits' => $credits, 'tier' => $name];
        return $rows;
    }

    private function steamProfile(array $query): array
    {
        $steamId = trim((string) ($query['steamid'] ?? ''));
        if (!preg_match('/^\d{17}$/', $steamId)) return $this->result(null, 400, 'A valid SteamID64 is required');
        return $this->result(STEAM_ENRICHMENT_ENABLED ? Steam::fetchProfile($steamId) : ['avatar' => null, 'name' => null]);
    }

    private function limit(array $query, int $default, int $maximum): int
    {
        $value = isset($query['limit']) ? (int) $query['limit'] : $default;
        return $value > 0 ? min($value, $maximum) : $default;
    }

    private function result(?array $data, int $status = 200, string $error = ''): array
    {
        return ['ok' => $status >= 200 && $status < 300, 'status' => $status, 'data' => $data, 'error' => $error];
    }
}
