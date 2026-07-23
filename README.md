# ESKIDOSTLAR BHOP

A standalone bunny hop server mod for Counter-Strike 1.6 — AMX Mod X timer plugin, custom maps, knife skins, WR sound effects, and a PHP 8 leaderboard web portal.

## Features

-   **Complete bhop timer plugin** — FPS-independent physics, start/stop/checkpoint zones, strafe stats, checkpoint teleport
-   **Economy system** — credits, badge progression (Bronze I through Diamond II), in-game market with knife skins, trails, WR sounds
-   **Map manager** — RTV (Rock the Vote) and /nominate with menu interface
-   **Surf fix** — GoldSrc surface sliding physics correction via ReAPI
-   **17 custom bhop maps** — novice through professional difficulty
-   **4 knife skins** — Talon, Bayonet, Karambit, Butterfly (v_knife.mdl + p_knife.mdl)
-   **2 VIP knife skins** — Gold knife, M9 Bayonet
-   **3 WR sound effects** — played on world record
-   **Standalone web portal** — PHP 8.1+ leaderboard with live A2S server status, JSON API, and in-game MOTD pages
-   **Read-only MySQL** — timer plugin writes, web only reads
-   **20-second live refresh** — player list, map, ticker auto-update on the web

## Requirements

-   Counter-Strike 1.6 dedicated server (HLDS or ReHLDS)
-   Metamod
-   AMX Mod X 1.9 or later
-   ReAPI 5.x
-   MySQL 5.7+ / MariaDB 10.3+
-   PHP 8.1+ (web portal only)

## Directory Structure

```
cstrike/
  addons/
    amxmodx/
      configs/
        bhop_timer.cfg                    # Main timer config
        bhop_timer_private.cfg.example    # Private MySQL config template
        plugins-bhop_timer.ini            # Plugin load order
        modules-bhop_timer.ini            # Required modules
        mpbhop.cfg                        # Multi-player bhop config
      data/
        bhop_timer/
          market_items.ini                # In-game market catalog
      plugins/
        bhop_timer.amxx                   # Timer plugin (compiled)
        bhop_map_manager.amxx             # RTV / nominate plugin (compiled)
        bhop_surf_fix.amxx               # Surf fix plugin (compiled)
      scripting/
        bhop_timer.sma                    # Timer source
        bhop_map_manager.sma              # Map manager source
        bhop_surf_fix.sma                # Surf fix source
        components/
          physics.inc                     # Jump physics engine
          physics_fixes.inc              # Surf fix, anti-prestrafe
          zone_embedded.inc             # Start/stop/checkpoint zones
          storage.inc                    # MySQL PDO storage
          economy.inc                    # Credits, market, inventory
          badges.inc                     # Badge thresholds
          visualization.inc             # HUD displays
          editor.inc                     # In-game zone editor
          strafe_stats.inc             # Strafe statistics
          mpbhop.inc                    # Race mode support
        include/
          reapi.inc                     # ReAPI master include
          reapi_engine.inc             # ReAPI engine
          reapi_engine_const.inc       # ReAPI engine constants
          reapi_gamedll.inc           # ReAPI gamedll
          reapi_gamedll_const.inc     # ReAPI gamedll constants
          reapi_rechecker.inc         # ReAPI rechecker
          reapi_reunion.inc          # ReAPI reunion
          reapi_version.inc          # ReAPI version
          reapi_vtc.inc              # ReAPI VTC
          cssdk_const.inc             # CSSDK constants
          bmod_menu_style.inc        # Menu style
          xs.inc                      # Extended math
          visual.inc                 # Visual helpers
          json.inc                   # JSON parser
          neumenu.inc                # Menu extension
          speedrun_zone_api.inc      # Zone API
  bhop_maps/
    maps/                               # 17 .bsp files + .res + .txt
    gfx/env/                            # Cubemap for bhop_m_temple
    sound/                              # Map-specific sounds
  models/
    knifes/
      talon_ed/                         # v_knife.mdl, p_knife.mdl
      bayonet_ed/                       # v_knife.mdl, p_knife.mdl
      karambit_ed/                      # v_knife.mdl, p_knife.mdl
      butterfly_ed/                     # v_knife.mdl, p_knife.mdl
      vipgold_ed/                       # v_knife.mdl, p_knife.mdl
      vipm9_ed/                         # v_knife.mdl, p_knife.mdl
  sound/
    ed/                                 # wr1.wav, wr2.wav, wr3.wav
  website/                              # PHP 8 web portal (see website/README.md)
```

## Installation

1.  Copy the `addons` folder into your `cstrike` directory.
2.  Copy `bhop_maps/maps/*.bsp` into `cstrike/maps/`.
3.  Copy `models/`, `sound/`, `bhop_maps/gfx/`, `bhop_maps/sound/` into `cstrike/` preserving directory structure.
4.  Create a MySQL database. The timer plugin creates tables automatically on first run.
5.  Edit `addons/amxmodx/configs/bhop_timer_private.cfg.example` with your MySQL credentials and rename to `bhop_timer_private.cfg`.
6.  Verify modules in `addons/amxmodx/configs/modules-bhop_timer.ini` are active.
7.  Restart the server or change the map.
8.  Set up the web portal (see [website/README.md](website/README.md)).

## Configuration

### Main Config: bhop_timer.cfg

Located at `addons/amxmodx/configs/bhop_timer.cfg`. Executed automatically by the timer plugin on `plugin_cfg`.

Key cvars:

| Cvar | Default | Description |
|---|---|---|
| `bhop_enable` | `1` | Enable or disable the timer plugin |
| `bhop_chat_prefix` | `[TIMER]` | Colored chat prefix |
| `bhop_speed_limit` | `0.0` | Max speed before reset (0 = disabled) |
| `bhop_prestrafe_limit` | `400.0` | Max prestrafe speed |
| `bhop_gravity` | `800` | Custom gravity (0 = server default) |
| `bhop_autobhop` | `1` | Auto-bhop mode |
| `bhop_checkpoints` | `1` | Enable checkpoint system |
| `bhop_respawn` | `1` | Respawn at start on death |
| `bhop_strafe_stats` | `1` | Enable strafe statistics display |
| `bhop_mode_override` | `0` | Force a specific timer mode |

### Timer Modes

| ID | Mode | FPS | Description |
|---|---|---|---|
| 0 | Normal | 131 | Standard bhop |
| 1 | Low Gravity | 1000 | Reduced gravity |
| 2 | Double Jump | 1000 | Double jump enabled |
| 3 | Normal 200 | 200 | 200 FPS cap |
| 4 | Normal 333 | 333 | 333 FPS cap |
| 5 | Normal 500 | 500 | 500 FPS cap |
| 6 | Normal 1000 | 1000 | 1000 FPS cap |
| 7 | Simple | — | Simplified physics |

### Economy System

The economy system is managed by `economy.inc`. Players earn credits by completing maps, setting personal bests, and world records.

**Badge progression:**

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

**Market catalog (16 items):**

| ID | Item | Price | Type |
|---|---|---|---|
| 1 | Custom Chat Prefix | 1,000 CR | Customization |
| 2 | Custom Join Message | 500 CR | Customization |
| 10 | Talon Knife Skin | 2,000 CR | Knife |
| 11 | Bayonet Knife Skin | 2,000 CR | Knife |
| 12 | Karambit Knife Skin | 2,000 CR | Knife |
| 13 | Butterfly Knife Skin | 2,000 CR | Knife |
| 20 | VIP Gold Knife | 3,000 CR | VIP Knife |
| 21 | VIP M9 Bayonet | 3,000 CR | VIP Knife |
| 30–32 | WR Sound 1–3 | 1,500 CR | WR Sound |
| 40–44 | Trail (5 colors) | 1,000 CR | Trail |

## Player Commands

| Command | Action |
|---|---|
| `/start` or `!start` | Teleport to map start |
| `/stop` or `!stop` | Stop timer |
| `/menu` or `!menu` | Open timer menu |
| `/checkpoint` or `!cp` | Save checkpoint |
| `/teleport` or `!tp` | Teleport to checkpoint |
| `/prev` or `!prev` | Previous checkpoint |
| `/next` or `!next` | Next checkpoint |
| `/rtv` | Rock the Vote — start map change vote |
| `/nominate` | Open map nomination menu |
| `/nextmap` | Show next map |
| `/timeleft` | Show time left on current map |
| `/level` or `/rank` | Show player stats |
| `/top` | Show top players |
| `/help` or `!help` | Show help |

## Admin Commands

All admin commands require `ADMIN_CFG` access (flag `m`).

| Command | Description |
|---|---|
| `amx_bhop_menu` | Open timer admin menu |
| `amx_bhop_reload` | Reload configuration |

## Web Portal

The `website/` directory contains a standalone PHP 8.1+ leaderboard portal. See [website/README.md](website/README.md) for full documentation.

Quick start:

```bash
cd website
cp config.local.example.php config.local.php
# Edit config.local.php with MySQL and game server values
php -d extension=sockets -S 127.0.0.1:18082 router.php
```

Open `http://127.0.0.1:18082`.

### API Endpoints

| Method | Endpoint | Description |
|---|---|---|
| GET | `/api/status` | MySQL connection, A2S game status, schema compatibility |
| GET | `/api/maps` | Map list with per-mode world record info |
| GET | `/api/pro15` | Top 15 players by personal best count |
| GET | `/api/best-records` | Per-map leaderboard |
| GET | `/api/live-ticker` | Recent finishes with WR/PB tags |
| GET | `/api/player/{authid}` | Player profile |
| GET | `/api/top-credits` | Credit ranking |
| GET | `/api/market` | Market catalog |
| GET | `/api/badges` | Badge thresholds |

## Plugin Architecture

| Plugin | File | Role |
|---|---|---|
| BHOP Timer | `bhop_timer.amxx` | Core timer — physics, zones, strafe stats, economy, storage, editor, visualization. Provides 10+ include components |
| BHOP Map Manager | `bhop_map_manager.amxx` | RTV voting, /nominate menu, nextmap/timeleft display. 60% vote threshold, 15-second countdown |
| BHOP Surf Fix | `bhop_surf_fix.amxx` | Surface sliding physics correction using ReAPI hooks |

## Smoke Test

After installation, restart the server or change map and run:

```
amxx plugins
```

Verify three plugins appear as `running`:

```
BHOP Timer            1.2.0
BHOP Map Manager      1.2.1
BHOP Surf Fix         1.0.0
```

Then test in-game:

```
say /menu
say /rtv
say /nominate
say /nextmap
say /timeleft
say /help
```

Gameplay checks:

-   Spawn at map start with timer stopped.
-   Crossing the start zone starts the timer.
-   Crossing the stop zone stops the timer and records the time.
-   `/checkpoint` saves position, `/teleport` restores it.
-   Strafe stats display sync percentage and gain/loss.
-   RTV with enough players starts a vote.
-   Nominate opens the map selection menu.
-   Credits accumulate after completing maps.
-   Market items are purchasable from the in-game menu.

## Compatibility

The plugin uses AMX Mod X, ReAPI, Fakemeta, and MySQL. ReHLDS and ReGameDLL are recommended but not strictly required for basic functionality.

ReAPI provides the native hooks that make FPS-independent physics and zone detection possible.

## Limitations

-   The MySQL connection requires a configured `bhop_timer_private.cfg` file.
-   The weapon-freeze on wrong-weapon kills is handled by the physics component; incorrect weapon kills still award kill credit to the game engine.
-   Map vote results are used to set `amx_nextmap` and trigger `changelevel`.
-   The web portal requires PHP 8.1+ and the `sockets` or `stream_socket_client` extension for A2S UDP queries.
-   MOTD pages are kept under the GoldSrc reliable channel size limit.

## Custom Maps

17 custom bhop maps by Zerotech (petersam1980@gmail.com):

| Map | Difficulty | Features |
|---|---|---|
| bhop_m_novice | Beginner | Short, wide platforms |
| bhop_m_novice2 | Beginner | Alternative beginner route |
| bhop_m_skill | Intermediate | Standard skill |
| bhop_m_skill2 | Intermediate | Second skill |
| bhop_m_skill3 | Intermediate–Advanced | Third skill |
| bhop_m_skill4 | Intermediate–Advanced | Custom .res |
| bhop_m_skill_pro | Advanced | Professional skill |
| bhop_m_fire | Intermediate | Fire theme |
| bhop_m_factory | Intermediate | Factory theme |
| bhop_m_lab | Intermediate | Lab theme, custom .res |
| bhop_m_temple | Intermediate | Temple theme, cubemap, custom .res |
| bhop_m_wild | Intermediate | Wild West theme |
| bhop_m_ramp | Beginner | Ramp training |
| bhop_m_ramp_old | Beginner | Legacy ramp |
| bhop_m_ramp2 | Beginner | Second ramp |
| bhop_m_ramp_pro | Intermediate | Pro ramp |
| bhop_m_target | Intermediate | Target mechanics |

## License

- **Barlow Condensed** font — SIL Open Font License 1.1 (Copyright 2017 The Barlow Project Authors)
- **IBM Plex Mono** font — SIL Open Font License 1.1 (Copyright © 2017 IBM Corp.)
- **Custom maps** — Developed by Zerotech (petersam1980@gmail.com)
- **BHOP timer plugin** — Proprietary development, all rights reserved
- **Knife skin models** — Custom design, all rights reserved
- **WR sound effects** — Custom audio files, all rights reserved
