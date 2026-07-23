<?php

declare(strict_types=1);

final class Steam
{
    private static array $profileCache = [];

    public static function id64toSteam(string $steamId64): string
    {
        return Support::steam64To2($steamId64) ?? '';
    }

    public static function idTo64(string $authid): string
    {
        return Support::steam2To64($authid) ?? '';
    }

    /**
     * @return array{avatar:string|null,name:string|null}
     */
    public static function fetchProfile(string $steamId64): array
    {
        if (!preg_match('/^\d{17}$/', $steamId64)) {
            return ['avatar' => null, 'name' => null];
        }

        if (isset(self::$profileCache[$steamId64])) {
            return self::$profileCache[$steamId64];
        }

        $url = "https://steamcommunity.com/profiles/{$steamId64}?xml=1";
        $xml = self::httpGet($url);

        if (!$xml) {
            self::$profileCache[$steamId64] = ['avatar' => null, 'name' => null];
            return self::$profileCache[$steamId64];
        }

        $avatar = self::extractCdata($xml, 'avatarFull');
        $name = self::extractCdata($xml, 'steamID');

        self::$profileCache[$steamId64] = [
            'avatar' => $avatar ?: null,
            'name'   => $name ?: null,
        ];

        return self::$profileCache[$steamId64];
    }

    public static function fetchProfileForAuthId(string $authid): array
    {
        return self::fetchProfile(self::idTo64($authid));
    }

    private static function httpGet(string $url): string
    {
        $context = stream_context_create([
            'http' => [
                'timeout'           => 2,
                'user_agent'        => 'ESKIDOSTLAR-BHOP-Web/3.0',
                'follow_location'   => true,
                'max_redirects'     => 2,
            ],
            'ssl' => [
                'verify_peer'       => true,
                'verify_peer_name'  => true,
            ],
        ]);

        $response = @file_get_contents($url, false, $context);

        return $response !== false ? $response : '';
    }

    private static function extractCdata(string $xml, string $tag): string
    {
        if (preg_match("/<{$tag}><!\[CDATA\[(.*?)\]\]><\/{$tag}>/", $xml, $matches)) {
            return $matches[1];
        }
        if (preg_match("/<{$tag}>(.*?)<\/{$tag}>/", $xml, $matches)) {
            return $matches[1];
        }
        return '';
    }
}
