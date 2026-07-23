# ESKIDOSTLAR BHOP — Standalone Web Portal

A PHP 8.1+ leaderboard website for the ESKIDOSTLAR BHOP CS 1.6 server. Reads timer data from MySQL over a read-only PDO connection, queries the game server via GoldSrc A2S UDP, and renders the web portal and in-game `/motd` pages.

No separate web3 or Node.js project is required. The timer plugin continues writing to MySQL; this website only reads.

## Features

-   **Read-only MySQL** — safe, non-intrusive data access
-   **GoldSrc A2S UDP** — live server status, player list, current map
-   **20-second auto-refresh** — server changes reflect on the web in near real-time
-   **JSON API** — 10 endpoints for status, maps, records, players, economy, market
-   **Fully responsive** — 560px through 1440px+ viewports
-   **In-game MOTD** — PRO15, badges, credits, and player profile views
-   **Player economy profiles** — credit balance, badge progress, inventory
-   **Dark theme** — monospace + condensed display typefaces, grid layout
-   **No JavaScript framework** — vanilla JS, CSS, PHP

## Requirements

-   PHP 8.1+
-   `pdo_mysql`, `curl`, `json`, `mbstring` PHP extensions
-   PHP `sockets` extension or UDP-capable `stream_socket_client` (for A2S)
-   MySQL 5.7+ / MariaDB 10.3+
-   Apache `mod_rewrite`, Nginx front-controller rule, or PHP built-in development server

## Directory Structure

```
website/
  index.php                           # Front controller — route dispatcher
  router.php                          # PHP built-in server router
  config.php                          # Configuration bootstrap (env + local file)
  config.local.example.php            # Example local config template
  .htaccess                           # Apache rewrite + security headers
  assets/
    css/
      style.css                       # Main site (550 lines, responsive, dark)
      motd.css                        # In-game MOTD styles (27 lines)
    js/
      app.js                          # 20s live refresh, map filter, clipboard
    fonts/
      barlow-condensed-semibold.ttf   # Display typeface (OFL)
      ibm-plex-mono-regular.ttf       # Monospace typeface (OFL)
      ibm-plex-mono-semibold.ttf      # Monospace typeface (OFL)
  src/
    DataClient.php                    # Data layer interface
    LocalDataClient.php               # JSON API dispatcher (9 endpoints)
    Db.php                            # MySQL PDO queries
    A2S.php                           # GoldSrc A2S UDP protocol (socket/stream)
    Steam.php                         # Steam XML profile lookup
    ApiController.php                 # /api/* JSON output
    Pages.php                         # Page renderers
    Motd.php                          # In-game MOTD pages
    Layout.php                        # HTML shell
    Support.php                       # Utilities
    bootstrap.php                     # Autoload
  README.md                           # This file
```

## Installation

### 1. Read-only MySQL User

```sql
CREATE USER 'bhop_web_readonly'@'WEB_SERVER_IP'
IDENTIFIED BY 'A_STRONG_PASSWORD';

GRANT SELECT ON `bhop_timer`.*
TO 'bhop_web_readonly'@'WEB_SERVER_IP';

FLUSH PRIVILEGES;
```

The website expects these tables: `bhop_best`, `bhop_records`, `bhop_players`, `bhop_inventory`, `bhop_market_items`. The website does not create schema — `bhop_timer.amxx` is the schema and data owner.

### 2. Configuration

```bash
cp config.local.example.php config.local.php
```

Edit `config.local.php` with your values. This file is in `.gitignore` and blocked from HTTP access.

### 3. Environment Variables

Environment variables override `config.local.php`:

| Variable | Default | Description |
|---|---|---|
| `BHOP_DB_HOST` | — | MySQL host |
| `BHOP_DB_PORT` | `3306` | MySQL port |
| `BHOP_DB_DB` | — | Database name |
| `BHOP_DB_USER` | — | Read-only MySQL username |
| `BHOP_DB_PASS` | — | MySQL password |
| `BHOP_DB_PREFIX` | `bhop_` | Table prefix |
| `BHOP_GAME_HOST` | `127.0.0.1` | A2S game server host |
| `BHOP_GAME_PORT` | `27016` | A2S UDP port |
| `BHOP_PUBLIC_CONNECT` | — | Public `host:port` for players |
| `WEBSITE_BASE_URL` | — | Optional subdirectory, e.g. `/bhop` |
| `APP_TIMEZONE` | `Europe/Istanbul` | Timezone |
| `BHOP_STEAM_ENRICHMENT` | `false` | Enable Steam profile lookup |

### 4. Local Development

```bash
cp config.local.example.php config.local.php
# Edit config.local.php
php -d extension=sockets -S 127.0.0.1:18082 router.php
```

Open `http://127.0.0.1:18082`. Health check: `http://127.0.0.1:18082/api/status`.

### 5. Production Routing

**Apache:** Point document root to the `website/` directory. `.htaccess` handles rewriting.

**Nginx:**

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

## Configuration Reference

All settings are defined in `config.php` and overrideable via environment variables or `config.local.php`.

### Database

| Constant | Source | Description |
|---|---|---|
| `DB_HOST` | `BHOP_DB_HOST` | MySQL host |
| `DB_PORT` | `BHOP_DB_PORT` | MySQL port |
| `DB_NAME` | `BHOP_DB_DB` | Database name |
| `DB_USER` | `BHOP_DB_USER` | MySQL user |
| `DB_PASS` | `BHOP_DB_PASS` | MySQL password |
| `DB_TABLE_PREFIX` | `BHOP_DB_PREFIX` | Table prefix (default: `bhop_`) |
| `DB_CONFIGURED` | — | True when host, name, and user are all set |

### Timer Modes

| ID | Key | Label | FPS |
|---|---|---|---|
| 0 | normal | Normal 131 FPS | 131 |
| 1 | lowgrav | Low Gravity | 1000 |
| 2 | dbjump | Double Jump | 1000 |
| 3 | normal200 | Normal 200 FPS | 200 |
| 4 | normal333 | Normal 333 FPS | 333 |
| 5 | normal500 | Normal 500 FPS | 500 |
| 6 | normal1000 | Normal 1000 FPS | 1000 |
| 7 | simple | Simple | 0 |

### Badge Thresholds

| Credits | Badge |
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

### Market Catalog

Built-in fallback catalog (16 items). Database rows with matching IDs override name, price, type, and effect:

| ID | Name | Price | Type |
|---|---|---|---|
| 1 | Custom Chat Prefix | 1,000 | custom_prefix |
| 2 | Custom Join Message | 500 | join_message |
| 10 | Talon Knife Skin | 2,000 | knife |
| 11 | Bayonet Knife Skin | 2,000 | knife |
| 12 | Karambit Knife Skin | 2,000 | knife |
| 13 | Butterfly Knife Skin | 2,000 | knife |
| 20 | VIP Gold Knife | 3,000 | vip_skin |
| 21 | VIP M9 Bayonet | 3,000 | vip_skin |
| 30 | WR Sound 1 | 1,500 | wrsound |
| 31 | WR Sound 2 | 1,500 | wrsound |
| 32 | WR Sound 3 | 1,500 | wrsound |
| 40 | Red Trail | 1,000 | trail |
| 41 | Blue Trail | 1,000 | trail |
| 42 | Green Trail | 1,000 | trail |
| 43 | Yellow Trail | 1,000 | trail |
| 44 | Purple Trail | 1,000 | trail |

## API Reference

All API endpoints return `Content-Type: application/json`. CORS headers are set.

### `GET /api/status`

Health check. Returns MySQL connection, game server state, and schema compatibility.

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

List all maps with per-mode world record information.

### `GET /api/pro15?limit=N`

Top N players by personal best count. Default 15, max 100.

### `GET /api/best-records?map=X&mode=Y&limit=N`

Per-map or global best records. Default 200, max 1000.

### `GET /api/live-ticker?limit=N`

Recent finishes with WR/PB/FINISH tags. Default 15, max 100.

### `GET /api/player/{authid}`

Player profile. Accepts SteamID2, SteamID64 (17 digits), or player_key.

Returns bests, recent records, economy data (credits, balance, badge), and inventory.

### `GET /api/top-credits?limit=N`

Players ranked by total credits earned. Default 15, max 100.

### `GET /api/market`

Market catalog. Merges built-in fallback with database overrides.

### `GET /api/badges`

Badge threshold definitions.

### `GET /api/steam-profile?steamid={64}`

Steam profile lookup via Steam community XML. Requires `BHOP_STEAM_ENRICHMENT=true`.

## Routing

| Path | Handler | Description |
|---|---|---|
| `/` | `Pages::home()` | Main timing page |
| `/api/*` | `ApiController::handle()` | JSON API |
| `/profile/{id}` | `Pages::profile()` | Player profile |
| `/badges` | `Pages::badges()` | Badge ladder |
| `/market` | `Pages::market()` | Market catalog |
| `/top-credits` | `Pages::topCredits()` | Credit ranking |
| `/motd` | `Motd::render()` | In-game MOTD |
| `/map/{map}/{mode}` | Redirect | Legacy URL redirect |
| 404 | Layout | Not found page |

## Security

-   Grant website MySQL user **only** `SELECT` privileges
-   Never commit `config.local.php`
-   Do not expose MySQL port 3306 to the internet
-   Keep Steam enrichment disabled unless needed
-   `.htaccess` and `router.php` block direct access to `src/`, `tests/`, config files, and `README.md`
-   Apache sets `X-Content-Type-Options: nosniff` and `Referrer-Policy: strict-origin-when-cross-origin`

## Smoke Test

```powershell
Get-ChildItem . -Recurse -Filter *.php | ForEach-Object { php -l $_.FullName }
```

Minimum smoke test set:

```
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

Verify in `/api/status`:

-   `connected: true` — MySQL connection is working
-   `schemaCompatible: true` — required tables exist
-   `game.online: true` — A2S UDP responded

## Data Flow

```
bhop_timer.amxx  ──writes──►  MySQL Database  ◄──reads──  PHP Website
(CS 1.6 server)                                    │
                                                    │ UDP query
                                                    ▼
                                             CS 1.6 Game Server
                                             (A2S response)
```

## About

Standalone PHP 8 leaderboard and MOTD system for ESKIDOSTLAR BHOP CS 1.6 server. MySQL PDO + GoldSrc A2S UDP with JSON API, responsive dark theme, and in-game MOTD pages.
