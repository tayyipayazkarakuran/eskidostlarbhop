<?php

declare(strict_types=1);

final class A2S
{
    /**
     * @return array<string, mixed>
     */
    public static function queryStatus(string $host, int $port): array
    {
        $base = [
            'online'       => false,
            'host'         => $host,
            'port'         => $port,
            'name'         => '',
            'map'          => '',
            'players'      => 0,
            'maxPlayers'   => 0,
            'playerList'   => [],
            'errorMessage' => '',
        ];

        if (!function_exists('socket_create') && !function_exists('stream_socket_client')) {
            $base['errorMessage'] = 'A2S UDP support is not available on this host.';
            return $base;
        }

        try {
            $infoPayload = "\xff\xff\xff\xff\x54Source Engine Query\x00";
            $info = self::udpRequest($host, $port, $infoPayload);
            $parsedInfo = self::parseInfoResponse($info);

            $challengePayload = "\xff\xff\xff\xff\x55\xff\xff\xff\xff";
            $challengeResponse = self::udpRequest($host, $port, $challengePayload);
            $players = [];

            if (strlen($challengeResponse) >= 9 && $challengeResponse[4] === "\x41") {
                $challenge = substr($challengeResponse, 5, 4);
                $playerPayload = "\xff\xff\xff\xff\x55" . $challenge;
                $playerResponse = self::udpRequest($host, $port, $playerPayload);
                $players = self::parsePlayerResponse($playerResponse);
            } else {
                $players = self::parsePlayerResponse($challengeResponse);
            }

            return array_merge($base, $parsedInfo, [
                'online'     => true,
                'playerList' => $players,
            ]);
        } catch (Throwable $e) {
            error_log('A2S query failed: ' . $e->getMessage());
            $base['errorMessage'] = 'A2S UDP is unavailable from this host.';
            return $base;
        }
    }

    private static function udpRequest(string $host, int $port, string $payload, int $timeoutMs = 1500): string
    {
        if (function_exists('socket_create')) {
            return self::nativeSocketRequest($host, $port, $payload, $timeoutMs);
        }

        return self::streamSocketRequest($host, $port, $payload, $timeoutMs);
    }

    private static function nativeSocketRequest(string $host, int $port, string $payload, int $timeoutMs): string
    {
        $resolvedHost = filter_var($host, FILTER_VALIDATE_IP) ? $host : gethostbyname($host);
        $family = str_contains($resolvedHost, ':') && defined('AF_INET6') ? AF_INET6 : AF_INET;
        $socket = @socket_create($family, SOCK_DGRAM, SOL_UDP);
        if ($socket === false) {
            throw new RuntimeException('Could not create the A2S UDP socket');
        }

        $timeout = [
            'sec'  => intdiv($timeoutMs, 1000),
            'usec' => ($timeoutMs % 1000) * 1000,
        ];
        @socket_set_option($socket, SOL_SOCKET, SO_RCVTIMEO, $timeout);
        @socket_set_option($socket, SOL_SOCKET, SO_SNDTIMEO, $timeout);

        try {
            $written = @socket_sendto($socket, $payload, strlen($payload), 0, $resolvedHost, $port);
            if ($written === false || $written !== strlen($payload)) {
                throw new RuntimeException('A2S UDP send failed');
            }

            $buffer = '';
            $remoteHost = '';
            $remotePort = 0;
            $received = @socket_recvfrom($socket, $buffer, 8192, 0, $remoteHost, $remotePort);
            if ($received === false || $received === 0) {
                throw new RuntimeException('A2S UDP request timed out');
            }

            return $buffer;
        } finally {
            socket_close($socket);
        }
    }

    private static function streamSocketRequest(string $host, int $port, string $payload, int $timeoutMs): string
    {
        $addressHost = str_contains($host, ':') ? '[' . trim($host, '[]') . ']' : $host;
        $endpoint = sprintf('udp://%s:%d', $addressHost, $port);
        $socket = @stream_socket_client(
            $endpoint,
            $errno,
            $errstr,
            $timeoutMs / 1000,
            STREAM_CLIENT_CONNECT
        );
        if (!$socket) {
            $detail = $errstr ?: ($errno ? "errno $errno" : 'unknown error');
            throw new RuntimeException("UDP connection failed: $detail");
        }

        $seconds = intdiv($timeoutMs, 1000);
        $microseconds = ($timeoutMs % 1000) * 1000;
        stream_set_timeout($socket, $seconds, $microseconds);

        // stream_socket_client already connected this UDP socket to the target.
        // Supplying the destination again fails on some Windows PHP builds.
        $written = @fwrite($socket, $payload);
        if ($written === false || $written !== strlen($payload)) {
            $meta = stream_get_meta_data($socket);
            fclose($socket);
            throw new RuntimeException('A2S send failed: ' . ($meta['timed_out'] ? 'timed out' : 'socket error'));
        }

        $buffer = @fread($socket, 8192);
        $meta = stream_get_meta_data($socket);
        fclose($socket);

        if ($buffer === false || $buffer === '') {
            throw new RuntimeException($meta['timed_out'] ? 'A2S request timed out' : 'Empty A2S response');
        }

        return $buffer;
    }

    /**
     * @return array<string, mixed>
     */
    private static function parseInfoResponse(string $buffer): array
    {
        if (strlen($buffer) < 6) {
            throw new RuntimeException('Invalid A2S info response');
        }

        $offset = 4;
        $type = $buffer[$offset++];

        if ($type === "\x49") {
            $offset++;
            [$name, $offset] = self::readCString($buffer, $offset);
            [$map, $offset] = self::readCString($buffer, $offset);
            [, $offset] = self::readCString($buffer, $offset);
            [, $offset] = self::readCString($buffer, $offset);
            $offset += 2;
            $players = ord($buffer[$offset++] ?? "\x00");
            $maxPlayers = ord($buffer[$offset++] ?? "\x00");
            return ['name' => $name, 'map' => $map, 'players' => $players, 'maxPlayers' => $maxPlayers];
        }

        if ($type === "\x6d") {
            [, $offset] = self::readCString($buffer, $offset);
            [$name, $offset] = self::readCString($buffer, $offset);
            [$map, $offset] = self::readCString($buffer, $offset);
            [, $offset] = self::readCString($buffer, $offset);
            [, $offset] = self::readCString($buffer, $offset);
            $players = ord($buffer[$offset++] ?? "\x00");
            $maxPlayers = ord($buffer[$offset++] ?? "\x00");
            return ['name' => $name, 'map' => $map, 'players' => $players, 'maxPlayers' => $maxPlayers];
        }

        throw new RuntimeException('Unsupported A2S info response type');
    }

    /**
     * @return array<int, array{index:int,name:string,score:int,duration:float}>
     */
    private static function parsePlayerResponse(string $buffer): array
    {
        if (strlen($buffer) < 6 || $buffer[4] !== "\x44") {
            return [];
        }

        $offset = 5;
        $count = ord($buffer[$offset++] ?? "\x00");
        $players = [];

        for ($i = 0; $i < $count && $offset < strlen($buffer); $i++) {
            $index = ord($buffer[$offset++] ?? "\x00");
            [$name, $offset] = self::readCString($buffer, $offset);
            if ($offset + 8 > strlen($buffer)) {
                break;
            }
            $score = self::unpackInt32($buffer, $offset);
            $offset += 4;
            $duration = self::unpackFloat($buffer, $offset);
            $offset += 4;

            $players[] = [
                'index'    => $index,
                'name'     => $name,
                'score'    => $score,
                'duration' => $duration,
            ];
        }

        return $players;
    }

    /**
     * @return array{0:string,1:int}
     */
    private static function readCString(string $buffer, int $offset): array
    {
        $end = $offset;
        while ($end < strlen($buffer) && $buffer[$end] !== "\x00") {
            $end++;
        }
        $value = substr($buffer, $offset, $end - $offset);
        return [$value, min($end + 1, strlen($buffer))];
    }

    private static function unpackInt32(string $buffer, int $offset): int
    {
        $bytes = substr($buffer, $offset, 4);
        $unpacked = unpack('V', $bytes);
        return $unpacked !== false ? (int) $unpacked[1] : 0;
    }

    private static function unpackFloat(string $buffer, int $offset): float
    {
        $bytes = substr($buffer, $offset, 4);
        $unpacked = unpack('f', $bytes);
        return $unpacked !== false ? (float) $unpacked[1] : 0.0;
    }
}
