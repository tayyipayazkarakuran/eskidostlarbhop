# ESKIDOSTLAR BHOP

Counter-Strike 1.6 / ReHLDS bunny hop server. Timer plugin, economy system, custom maps, knife skins, WR sounds, and a standalone web portal.

This repository consists of three main layers:

| Layer | Description |
|---|---|
| **AMX Mod X plugins** | bhop_timer (physics + zones + strafe + economy), bhop_map_manager (RTV/nominate), bhop_surf_fix |
| **Game assets** | Bhop maps (.bsp/.res), knife skin models (.mdl), WR sound effects (.wav), cubemaps (.tga) |
| **Web portal** | PHP 8.1+ standalone leaderboard; MySQL PDO + GoldSrc A2S UDP; JSON API, MOTD pages |

---

## Table of contents

- [AMX Mod X plugins](#amx-mod-x-plugins)
- [Maps and assets](#maps-and-assets)
- [Web portal](#web-portal)
- [Server setup](#server-setup)
- [Development](#development)
- [License](#license)

---

## AMX Mod X plugins

### bhop_timer (`addons/amxmodx/scripting/bhop_timer.sma`)

Core timer plugin. ReAPI-based, composed of the following include components:

| Component | Purpose |
|---|---|
| `physics.inc` | Jump physics engine, FPS-independent speed calculation, strafe/prestrafe detection |
| `physics_fixes.inc` | Surf fix, bhop difficulty config, anti-prestrafe |
| `zone_embedded.inc` | Start/stop/checkpoint zones, custom zone types |
| `storage.inc` | MySQL PDO connection, best/record/log writes, player profiles |
| `economy.inc` | Credit system, badge/level progression, in-game market, inventory |
| `badges.inc` | Badge thresholds (Bronze I → Diamond II), progress queries |
| `visualization.inc` | HUD displays, center text, spectator info |
| `editor.inc` | In-game zone editor (.res file writer) |
| `strafe_stats.inc` | Strafe statistics, sync percentage, gain/loss |
| `mpbhop.inc` | Multi-player bhop (race) support |

**AMX Mod X version:** 1.9+  
**ReAPI version:** 5.x

### bhop_map_manager (`addons/amxmodx/scripting/bhop_map_manager.sma`)

RTV (Rock the Vote) and /nominate system.

| Command | Action |
|---|---|
| `/rtv` | Starts a map change vote (60% threshold) |
| `/nominate` | Adds a map to the voting pool |
| `/nextmap` | Displays the next map |
| `/timeleft` | Shows remaining time on current map |

- Menu-based interface, compatible with `bmod_menu_style.inc`
- Vote countdown timer (15 seconds)
- Nomination deduplication and disabled-item callbacks
- Mapcycle.txt loader with `cstrike/` and `configs/maps.ini` fallback

### bhop_surf_fix (`addons/amxmodx/scripting/bhop_surf_fix.sma`)

GoldSrc surf physics fix. Repairs surface sliding behavior using ReAPI hooks.

### Configuration files (`addons/amxmodx/configs/`)

| File | Description |
|---|---|
| `bhop_timer.cfg` | Main timer config (speed limits, zone settings, economy values) |
| `bhop_timer_private.cfg.example` | Private server config (MySQL credentials) — never commit |
| `plugins-bhop_timer.ini` | AMX Mod X plugin activation list |
| `modules-bhop_timer.ini` | Required modules (ReAPI, MySQL) |
| `mpbhop.cfg` | Multi-player bhop settings |

### Market item definitions (`addons/amxmodx/data/bhop_timer/market_items.ini`)

Static definition file for the 16-item in-game market catalog. Database overrides take precedence when `bhop_market_items` table is populated.

---

## Maps and assets

### Custom maps (`bhop_maps/maps/`)

17 custom bhop maps across all difficulty levels:

| Map | Difficulty | Notes |
|---|---|---|
| `bhop_m_novice` | Beginner | Short route, wide platforms |
| `bhop_m_novice2` | Beginner | Alternative beginner route |
| `bhop_m_skill` | Intermediate | Standard skill route |
| `bhop_m_skill2` | Intermediate | Second skill route |
| `bhop_m_skill3` | Intermediate-Advanced | Third skill route |
| `bhop_m_skill4` | Intermediate-Advanced | Fourth skill route (custom .res) |
| `bhop_m_skill_pro` | Advanced | Professional skill route |
| `bhop_m_fire` | Intermediate | Fire-themed map |
| `bhop_m_factory` | Intermediate | Factory-themed map |
| `bhop_m_lab` | Intermediate | Laboratory-themed (custom .res) |
| `bhop_m_temple` | Intermediate | Temple-themed (cubemap + custom .res) |
| `bhop_m_wild` | Intermediate | Wild West-themed |
| `bhop_m_ramp` | Beginner | Ramp mechanics training |
| `bhop_m_ramp_old` | Beginner | Legacy ramp route |
| `bhop_m_ramp2` | Beginner | Second ramp route |
| `bhop_m_ramp_pro` | Intermediate | Professional ramp route |
| `bhop_m_target` | Intermediate | Target/aim mechanics |

Each map has a `.txt` file containing map author credits. `.res` files define required custom assets (sounds, models).

### Cubemap (`bhop_maps/gfx/env/`)

Custom 6-face cubemap for `bhop_m_temple`:
- `bhop_m_templebk.tga`, `bhop_m_templedn.tga`, `bhop_m_templeft.tga`
- `bhop_m_templelf.tga`, `bhop_m_templert.tga`, `bhop_m_templeup.tga`

### Map-specific sounds (`bhop_maps/sound/`)

- `bhop_m_skill2/anthemcollides.wav`
- `bhop_m_skill4/rokdahouse.wav`

### Knife skin models (`models/knifes/`)

| Directory | Model | Type |
|---|---|---|
| `talon_ed/` | Talon knife | Standard skin |
| `bayonet_ed/` | Bayonet knife | Standard skin |
| `karambit_ed/` | Karambit knife | Standard skin |
| `butterfly_ed/` | Butterfly knife | Standard skin |
| `vipgold_ed/` | Gold knife | VIP skin |
| `vipm9_ed/` | M9 Bayonet | VIP skin |

Each skin includes `v_knife.mdl` (first-person) and `p_knife.mdl` (world model).

### WR sounds (`sound/ed/`)

Three distinct sound effects played when a world record is broken:
- `wr1.wav`, `wr2.wav`, `wr3.wav`

---

## Web portal

Full documentation: [`website/README.md`](website/README.md)

Snapshot:

```
website/
├── index.php                  # Front controller (route dispatcher)
├── router.php                 # PHP built-in server router
├── config.php                 # Configuration (env + local file override)
├── config.local.example.php   # Example local config (never committed)
├── .htaccess                  # Apache rewrite rules + security headers
├── assets/
│   ├── css/
│   │   ├── style.css          # Main site styles (responsive, 550 lines)
│   │   └── motd.css           # MOTD styles (27 lines)
│   ├── js/
│   │   └── app.js             # Live auto-refresh (20s interval), map filter, clipboard
│   └── fonts/
│       ├── barlow-condensed-semibold.ttf  # Display typeface (OFL-licensed)
│       ├── ibm-plex-mono-regular.ttf      # Monospace typeface (OFL-licensed)
│       └── ibm-plex-mono-semibold.ttf     # Monospace typeface (OFL-licensed)
├── src/
│   ├── DataClient.php         # Data layer interface
│   ├── LocalDataClient.php    # JSON API dispatcher (9 endpoints)
│   ├── Db.php                 # MySQL PDO queries (best, records, player, market)
│   ├── A2S.php                # GoldSrc A2S UDP protocol (socket or stream)
│   ├── Steam.php              # Steam XML profile lookup
│   ├── ApiController.php      # /api/* JSON output
│   ├── Pages.php              # Page renderers (home, profile, badges, market)
│   ├── Motd.php               # In-game MOTD pages (pro15, badges, credits, profile)
│   ├── Layout.php             # HTML layout (header, footer, alert, nav)
│   ├── Support.php            # Utilities (time formatting, modes, market catalog, badges)
│   └── bootstrap.php          # Autoload and initialization
└── README.md                  # Web portal setup documentation
```

### Features

- **Read-only MySQL** — Timer plugin writes data, web layer only reads
- **GoldSrc A2S UDP** — Live server queries (player list, current map, online status)
- **20-second auto-refresh** — Server changes reflect on the web in near real-time
- **JSON API** — `/api/status`, `/api/pro15`, `/api/maps`, `/api/best-records`, `/api/player`, `/api/top-credits`, `/api/market`, `/api/badges`, `/api/live-ticker`
- **Fully responsive** — 560px → 1440px+ viewports
- **In-game MOTD** — `/motd?view=pro15|badges|topcredits|profile`
- **Player economy profiles** — Credit balance, badge progress, inventory view

### Quick start (web)

```bash
cd website
cp config.local.example.php config.local.php
# Edit config.local.php — set MySQL and game server values
php -d extension=sockets -S 127.0.0.1:18082 router.php
```

Open `http://127.0.0.1:18082` in your browser. Health check at `http://127.0.0.1:18082/api/status`.

---

## Server setup

1. A CS 1.6 / ReHLDS server with **AMX Mod X 1.9+** and **ReAPI 5.x**
2. Copy `addons/amxmodx/` to your server's `cstrike/` directory
3. Copy `.bsp` files from `bhop_maps/maps/` to `cstrike/maps/`
4. Copy custom assets (`models/`, `sound/`, `bhop_maps/gfx/`, `bhop_maps/sound/`) to corresponding directories
5. Create a MySQL database and configure credentials in `bhop_timer.cfg`
6. Set up the web portal following the quick start above
7. Create a `mapcycle.txt` with your desired map rotation

### In-game market

The market system is managed by `economy.inc` within the `bhop_timer` plugin. 16 products:

| ID | Product | Price | Type |
|---|---|---|---|
| 1 | Custom Chat Prefix | 1,000 CR | custom_prefix |
| 2 | Custom Join Message | 500 CR | join_message |
| 10 | Talon Knife Skin | 2,000 CR | knife |
| 11 | Bayonet Knife Skin | 2,000 CR | knife |
| 12 | Karambit Knife Skin | 2,000 CR | knife |
| 13 | Butterfly Knife Skin | 2,000 CR | knife |
| 20 | VIP Gold Knife | 3,000 CR | vip_skin |
| 21 | VIP M9 Bayonet | 3,000 CR | vip_skin |
| 30–32 | WR Sound 1–3 | 1,500 CR | wrsound |
| 40–44 | Trail (5 colors) | 1,000 CR | trail |

---

## Development

### Dependencies

- **AMX Mod X 1.9+** — `amxmodx`, `amxmisc`, `fakemeta`, `cstrike`, `hamsandwich`
- **ReAPI 5.x** — `reapi` module (`reapi.inc` and sub-includes)
- **MySQL** — Plugin uses MySQL database (`storage.inc`)
- **PHP 8.1+** — Web portal runtime
- **MySQL 5.7+ / MariaDB 10.3+** — Web portal database

### Compiling AMX Mod X plugins

```bash
amxxpc bhop_timer.sma
amxxpc bhop_map_manager.sma
amxxpc bhop_surf_fix.sma
```

Compiled `.amxx` files go to `addons/amxmodx/plugins/`.

### Web portal lint

```powershell
Get-ChildItem . -Recurse -Filter *.php | ForEach-Object { php -l $_.FullName }
```

### API endpoints

| Method | Endpoint | Description |
|---|---|---|
| GET | `/api/status` | MySQL connection, A2S game status, schema compatibility |
| GET | `/api/maps` | Map list with per-mode WR info |
| GET | `/api/pro15?limit=N` | Top N players by personal best count |
| GET | `/api/best-records?map=X&mode=Y&limit=N` | Per-map, per-mode leaderboard |
| GET | `/api/live-ticker?limit=N` | Last N finishes (WR/PB/Finish) |
| GET | `/api/player/{authid}` | Player profile (bests, records, inventory) |
| GET | `/api/top-credits?limit=N` | Credit ranking |
| GET | `/api/market` | Market catalog |
| GET | `/api/badges` | Badge thresholds |
| GET | `/api/steam-profile?steamid={64}` | Steam XML profile lookup |

---

## License

This project is a private CS 1.6 bunny hop server.

- **Barlow Condensed** font — SIL Open Font License 1.1 (Copyright 2017 The Barlow Project Authors)
- **IBM Plex Mono** font — SIL Open Font License 1.1 (Copyright © 2017 IBM Corp.)
- **Custom maps** — Developed by Zerotech (petersam1980@gmail.com)
- **Bhop timer plugin** — Proprietary development, all rights reserved
- **Knife skin models** — Custom design, all rights reserved
- **WR sound effects** — Custom audio files, all rights reserved
