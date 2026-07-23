# ESKIDOSTLAR BHOP — standalone website

Standalone PHP 8 leaderboard portal for the ESKIDOSTLAR BHOP CS 1.6 server. Reads timer data from a MySQL database over read-only PDO connections, queries the game server via the GoldSrc A2S UDP protocol, and renders both the web portal and legacy in-game `/motd` pages.

No separate web3 or Node.js project needed. The timer plugin continues writing to the existing MySQL tables; this website only reads.

---

## Table of contents

- [Requirements](#requirements)
- [1. Read-only MySQL user](#1-read-only-mysql-user)
- [2. Configuration](#2-configuration)
- [3. Local development](#3-local-development)
- [4. Production routing](#4-production-routing)
- [5. Health checks and smoke tests](#5-health-checks-and-smoke-tests)
- [Architecture](#architecture)
- [API reference](#api-reference)
- [Security](#security)
- [Market catalog](#market-catalog)

---

## Requirements

- **PHP 8.1+**
- `pdo_mysql`, `curl`, `json`, `mbstring` PHP extensions
- PHP `sockets` extension or UDP-capable `stream_socket_client` (for A2S)
- **MySQL 5.7+ / MariaDB 10.3+**
- Apache `mod_rewrite`, Nginx front-controller rule, or PHP built-in development server

---

## 1. Read-only MySQL user

Create a MySQL account with only `SELECT` privileges. Replace `WEB_SERVER_IP` with the IP your website connects from. Use `localhost` if the database and website run on the same machine.

```sql
CREATE USER 'bhop_web_readonly'@'WEB_SERVER_IP'
IDENTIFIED BY 'A_STRONG_PASSWORD';

GRANT SELECT ON `bhop_timer`.*
TO 'bhop_web_readonly'@'WEB_SERVER_IP';

FLUSH PRIVILEGES;
```

The website expects these tables: `bhop_best`, `bhop_records`, `bhop_players`, `bhop_inventory`, `bhop_market_items`. The website does **not** create schema — `bhop_timer.amxx` is the schema and data owner.

If MySQL is on a remote server, also verify:

- MySQL `bind-address` permits the web server's IP
- Port 3306/TCP is firewalled to the web server's IP only
- The MySQL user's host portion is correct

---

## 2. Configuration

### Local config file

The easiest method:

```bash
cp config.local.example.php config.local.php
```

Then edit `config.local.php` with your values. This file is in `.gitignore` and blocked from direct HTTP access.

### Environment variables

Environment variables override `config.local.php` values:

| Variable | Description |
|---|---|
| `BHOP_DB_HOST` | MySQL host address |
| `BHOP_DB_PORT` | MySQL port, default `3306` |
| `BHOP_DB_DB` | Database name |
| `BHOP_DB_USER` | Read-only MySQL username |
| `BHOP_DB_PASS` | MySQL password |
| `BHOP_DB_PREFIX` | Table prefix — production `bhop_`, test `bmod_test_27016_` |
| `BHOP_GAME_HOST` | CS 1.6 server hostname/IP for A2S queries |
| `BHOP_GAME_PORT` | Game/A2S UDP port, default `27016` |
| `BHOP_PUBLIC_CONNECT` | Public `host:port` string shown to players |
| `WEBSITE_BASE_URL` | Optional subdirectory, e.g. `/bhop` |
| `APP_TIMEZONE` | Default `Europe/Istanbul` |
| `BHOP_STEAM_ENRICHMENT` | Enable Steam profile name/avatar lookup; default off |

Note: `BHOP_GAME_HOST` can be an internal IP used for A2S. The connection address shown to players is always the separate `BHOP_PUBLIC_CONNECT` value.

---

## 3. Local development

```bash
cp config.local.example.php config.local.php
# Edit config.local.php
php -d extension=sockets -S 127.0.0.1:18082 router.php
```

Then open `http://127.0.0.1:18082` and the health check at `http://127.0.0.1:18082/api/status`.

---

## 4. Production routing

### Apache

Point the document root to the `website/` directory. The `.htaccess` file handles rewriting and security.

### Nginx

```nginx
location / {
    try_files $uri $uri/ /index.php?$query_string;
}

location ~ ^/(?:src|tests)/ {
    deny all;
}

location ~ /(?:config(?:\.local)?(?:\.example)?\.php|router\.php)$ {
    deny all;
}

location ~ \.php$ {
    include fastcgi_params;
    fastcgi_param SCRIPT_FILENAME $document_root$fastcgi_script_name;
    fastcgi_pass unix:/run/php/php8.3-fpm.sock;
}
```

---

## 5. Health checks and smoke tests

```powershell
Get-ChildItem . -Recurse -Filter *.php | ForEach-Object { php -l $_.FullName }
php tests/run.php
```

Minimum smoke test set:

```text
GET /
GET /api/status
GET /api/maps
GET /api/pro15
GET /profile/<encoded-SteamID2>
GET /badges
GET /market
GET /top-credits
GET /motd
GET /motd?map=<map>&mode=normal
```

`/api/status` response includes:

- `connected: true` — MySQL connection is working
- `schemaCompatible: true` — Required tables and columns exist
- `game.online: true` — A2S UDP query received a response

---

## Architecture

### File structure

```
website/
├── index.php                  # Front controller — route dispatcher
├── router.php                 # PHP built-in server router (asset passthrough)
├── config.php                 # Configuration bootstrap (env + local file)
├── config.local.example.php   # Example local config template
├── .htaccess                  # Apache rewrite rules + security
├── assets/
│   ├── css/
│   │   ├── style.css          # Main site — 550 lines, dark theme, responsive
│   │   └── motd.css           # In-game MOTD styles — 27 lines
│   ├── js/
│   │   └── app.js             # 20s live refresh, map search filter, clipboard
│   └── fonts/
│       ├── barlow-condensed-semibold.ttf  # Display headings (OFL)
│       ├── ibm-plex-mono-regular.ttf      # Body text (OFL)
│       └── ibm-plex-mono-semibold.ttf     # Emphasized text (OFL)
├── src/
│   ├── DataClient.php         # Data layer interface
│   ├── LocalDataClient.php    # JSON API dispatcher — 9 endpoints
│   ├── Db.php                 # MySQL PDO queries — best, records, player, market
│   ├── A2S.php                # GoldSrc A2S UDP protocol (socket or stream)
│   ├── Steam.php              # Steam XML profile enrichment
│   ├── ApiController.php      # /api/* JSON response handler
│   ├── Pages.php              # Page renderers — home, profile, badges, market, credits
│   ├── Motd.php               # In-game MOTD — pro15, badges, credits, profile views
│   ├── Layout.php             # HTML shell — header, footer, alert, nav
│   ├── Support.php            # Utilities — time formatting, modes, market catalog, badges
│   └── bootstrap.php          # Autoload and initialization
└── README.md                  # This file
```

### Data flow

```
┌──────────────────────┐
│   bhop_timer.amxx    │  Writes to MySQL
│   (CS 1.6 server)    │
└────────┬─────────────┘
         │ writes
         ▼
┌──────────────────────┐         ┌─────────────────────┐
│    MySQL Database    │◄────────│  Website (PHP 8.1+) │
│  bhop_best           │  reads  │                     │
│  bhop_records        │         │  /api/*  ──► JSON   │
│  bhop_players        │         │  /       ──► HTML   │
│  bhop_inventory      │         │  /motd   ──► HTML   │
│  bhop_market_items   │         │                     │
└──────────────────────┘         └─────────┬───────────┘
                                           │ UDP query
                                           ▼
                                    ┌──────────────┐
                                    │  CS 1.6      │
                                    │  Game Server │
                                    │  (A2S)       │
                                    └──────────────┘
```

### Routing

`index.php` acts as the front controller:

| Path | Handler | Description |
|---|---|---|
| `/` (root) | `Pages::home()` | Main timing page — map grid, pro15, live ticker |
| `/api/*` | `ApiController::handle()` | JSON API responses |
| `/profile/{id}` | `Pages::profile()` | Player profile page |
| `/badges` | `Pages::badges()` | Badge progression ladder |
| `/market` | `Pages::market()` | Read-only market catalog |
| `/top-credits` | `Pages::topCredits()` | Credit ranking |
| `/motd` | `Motd::render()` | In-game MOTD (pro15, badges, topcredits, profile views) |
| `/map/{map}/{mode}` | Redirect to `/motd?map=...&mode=...` | Legacy URL redirect |
| 404 fallback | Layout renders 404 page | Unknown routes |

### Responsive breakpoints

| Breakpoint | Adjustments |
|---|---|
| Default (>1100px) | Full 4-column layout, side-by-side hero |
| 1100px | 3-column map grid, header state hidden |
| 820px | Single-column hero, 2-column map grid, stacked dual-grid |
| 560px | 1-column everything, compact padding and font sizes |

---

## API reference

All API endpoints return `Content-Type: application/json`. CORS headers are set for cross-origin requests.

### `GET /api/status`

Health check. Returns MySQL connection state, game server state, and schema compatibility.

```json
{
  "connected": true,
  "schemaCompatible": true,
  "game": {
    "online": true,
    "name": "ESKIDOSTLAR BHOP",
    "map": "bhop_m_skill",
    "players": 12,
    "maxPlayers": 32,
    "playerList": [
      { "name": "Player1", "score": 0, "duration": 342.5 }
    ]
  }
}
```

### `GET /api/maps`

List of all maps with per-mode world record information.

**Query parameters:** none

### `GET /api/pro15?limit={n}`

Global record holders ranked by personal best count.

| Parameter | Type | Default | Max |
|---|---|---|---|
| `limit` | int | 15 | 100 |

### `GET /api/best-records?map={x}&mode={y}&limit={n}`

Per-map or global best records.

| Parameter | Type | Default | Max |
|---|---|---|---|
| `map` | string | — | — |
| `mode` | string | — | — |
| `limit` | int | 200 | 1000 |

Omitting `map` returns records across all maps.

### `GET /api/live-ticker?limit={n}`

Recent finishes with WR/PB tags.

| Parameter | Type | Default | Max |
|---|---|---|---|
| `limit` | int | 15 | 100 |

### `GET /api/player/{authid}`

Player profile including personal bests, recent records, economy data, and inventory.

**Path parameter:** SteamID2 (`STEAM_0:1:12345`), SteamID64 (17 digits), or player_key

### `GET /api/top-credits?limit={n}`

Players ranked by total credits earned.

| Parameter | Type | Default | Max |
|---|---|---|---|
| `limit` | int | 15 | 100 |

### `GET /api/market`

Market catalog. Returns the merged result of the built-in fallback catalog and database overrides from `bhop_market_items`.

### `GET /api/badges`

Badge threshold definitions.

### `GET /api/steam-profile?steamid={64}`

Steam profile lookup via Steam community XML. Requires `BHOP_STEAM_ENRICHMENT=true`.

| Parameter | Type | Required |
|---|---|---|
| `steamid` | string (17 digits) | Yes |

---

## Security

- Grant the website's MySQL user **only** `SELECT` privileges — no `INSERT`, `UPDATE`, `DELETE`, or `DROP`
- Never write the real password into source code or `config.local.example.php`
- Never commit or share `config.local.php`
- Do not expose MySQL port 3306 to the internet — allow only the web server's IP
- Keep Steam enrichment disabled unless needed; MOTD pages never expect Steam profiles
- `.htaccess` and `router.php` block direct access to `src/`, `tests/`, config files, `router.php`, and `README.md`
- Apache: `Header always set X-Content-Type-Options "nosniff"` and `Referrer-Policy "strict-origin-when-cross-origin"` are applied

---

## Market catalog

The website includes a read-only fallback of the plugin's current 16-item catalog. Rows from the `bhop_market_items` table with matching IDs override name, price, type, and effect values.

Built-in catalog (fallback):

| ID | Name | Price | Type | Effect |
|---|---|---|---|---|
| 1 | Custom Chat Prefix | 1,000 | custom_prefix | 1 |
| 2 | Custom Join Message | 500 | join_message | 1 |
| 10 | Talon Knife Skin | 2,000 | knife | 1 |
| 11 | Bayonet Knife Skin | 2,000 | knife | 2 |
| 12 | Karambit Knife Skin | 2,000 | knife | 3 |
| 13 | Butterfly Knife Skin | 2,000 | knife | 4 |
| 20 | VIP Gold Knife | 3,000 | vip_skin | 5 |
| 21 | VIP M9 Bayonet | 3,000 | vip_skin | 6 |
| 30 | WR Sound 1 | 1,500 | wrsound | 1 |
| 31 | WR Sound 2 | 1,500 | wrsound | 2 |
| 32 | WR Sound 3 | 1,500 | wrsound | 3 |
| 40 | Red Trail | 1,000 | trail | 1 |
| 41 | Blue Trail | 1,000 | trail | 2 |
| 42 | Green Trail | 1,000 | trail | 3 |
| 43 | Yellow Trail | 1,000 | trail | 4 |
| 44 | Purple Trail | 1,000 | trail | 5 |

Legacy IDs 3–7 were superseded by the current 10–44 catalog and are excluded from the web market display.

---

## Badge progression

| Threshold (credits) | Badge |
|---|---|
| 10 | Bronze I |
| 50 | Bronze II |
| 100 | Silver I |
| 250 | Silver II |
| 500 | Gold I |
| 1,000 | Gold II |
| 2,000 | Platinum I |
| 5,000 | Platinum II |
| 10,000 | Diamond I |
| 20,000 | Diamond II |

Badges track total credits earned. Spending credits never reduces badge progress.

---

## Timer modes

| ID | Key | Label | FPS |
|---|---|---|---|
| 0 | normal | Normal | 131 |
| 3 | normal200 | Normal | 200 |
| 4 | normal333 | Normal | 333 |
| 5 | normal500 | Normal | 500 |
| 6 | normal1000 | Normal | 1000 |
| 1 | lowgrav | Low Gravity | 1000 |
| 2 | dbjump | Double Jump | 1000 |
| 7 | simple | Simple | — |
