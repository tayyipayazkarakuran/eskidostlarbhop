# BMOD - CS 1.6 Bhop Timer Pack

A full-featured bunny hop timer and zone system for Counter-Strike 1.6, built as a multi-plugin AMX Mod X package. Includes a polygon zone editor, timer core with Pro15 records, physics fixes, map voting, a block builder, and a web leaderboard integration.

## Features

- **Polygon start/finish zones** with an in-game editor based on ReAPI
- **Timer with millisecond precision** -- start zone enter/leave detection, finish zone, reset on death, team change, and noclip
- **Pro15 leaderboards** -- file-backed best times per map/mode, remote MySQL queue with local fallback
- **Three game modes** -- Normal, Low Gravity, and Double Jump with per-mode FPS limits
- **WR replay bot** -- records and plays back world record runs frame by frame
- **Hook** (`bind c +hook`) -- movement hook that aborts the active timer run
- **Parachute** on `+use` / E key -- works in all modes without changing gravity
- **Surf/ramp physics fixes** -- surf stop fix, water jump fix, edge bug fix, and teleport velocity reset
- **Block builder** (`/build`) -- create, resize, grab, stamp, and delete invisible platform entities with undo support and entity remover (`/remove`)
- **RTV and map nomination** with countdown vote
- **Duel system** -- challenge another player to a head-to-head race
- **FPS enforcement** -- Normal mode caps `fps_max` to prevent high-FPS abuse; other modes allow up to 1000
- **Auto-bhop, godmode, auto-CT, weapon block** -- standard bhop server settings enforced by the plugin
- **Chat advertisements** and configurable round keeper bot name
- **Web leaderboard integration** -- `/pro15` and `/top15` open a Cloudflare Pages MOTD with live records
- **Scoreboard FPS display** -- replaces the deaths column with real-time player FPS

## Requirements

- Counter-Strike 1.6 dedicated server (ReHLDS recommended)
- Metamod
- AMX Mod X 1.8.2 or later
- ReAPI + ReGameDLL (required for polygon zone editor)
- Modules: `fakemeta`, `engine`, `cstrike`, `hamsandwich`, `json`, `mysql`, `sqlite` (migration only)

### ReAPI / ReGameDLL

Polygon zones require ReAPI and ReGameDLL runtime files. Shared hosting providers must allow these.

Windows:
- `addons/amxmodx/modules/reapi_amxx.dll`
- `cstrike/dlls/mp.dll`

Linux:
- `addons/amxmodx/modules/reapi_amxx_i386.so`
- `cstrike/dlls/cs.so`

The release `dist/vendor/` folder contains the required runtime files.

## Directory Structure

```
cstrike/
  addons/
    amxmodx/
      configs/
        plugins-bhop_timer.ini      # Plugin load order reference
        modules-bhop_timer.ini      # Required modules reference
        bhop_timer.cfg              # Main config (safe for public packages)
        bhop_timer_private.example.cfg  # MySQL credentials template
        bhop_timer_private.cfg      # (gitignored) Server-local MySQL creds
      plugins/
        speedrun_zone.amxx          # Polygon zone system and editor
        bhop_timer.amxx             # Timer core, HUD, records, modes, hook
        bhop_map_manager.amxx       # RTV, nomination, map vote
        bhop_physics_fixes.amxx      # Surf/ramp/edge/teleport fixes
        bhop_scoreboard_fps.amxx    # Scoreboard FPS display
        bhop_builder.amxx           # Block smith and entity remover
      scripting/
        speedrun_zone.sma
        bhop_timer.sma
        bhop_map_manager.sma
        bhop_physics_fixes.sma
        bhop_scoreboard_fps.sma
        bhop_builder.sma
        include/
          speedrun_zone_api.inc     # Zone registration API
          neumenu.inc
          json.inc
          visual.inc
          xs.inc
          reapi.inc                  # ReAPI headers (module bundle)
          cssdk_const.inc
          components/
            storage.inc
            physics.inc
            editor.inc
            visualization.inc
```

## Installation

1. Install ReHLDS + ReGameDLL + ReAPI on your server.
2. Copy the `addons` folder into your `cstrike` directory.
3. Add the module lines from `modules-bhop_timer.ini` to `addons/amxmodx/configs/modules.ini`.
4. Add the plugin lines from `plugins-bhop_timer.ini` to `addons/amxmodx/configs/plugins.ini` in this exact order:

   ```ini
   speedrun_zone.amxx
   bhop_timer.amxx
   bhop_map_manager.amxx
   bhop_physics_fixes.amxx
   bhop_scoreboard_fps.amxx
   bhop_builder.amxx
   ```

5. Copy the MySQL credentials template and fill in your database info:

   ```text
   addons/amxmodx/configs/bhop_timer_private.example.cfg
   ```

   rename to:

   ```text
   addons/amxmodx/configs/bhop_timer_private.cfg
   ```

6. Restart the server or change the map.

## Configuration

### Main Config: bhop_timer.cfg

Located at `addons/amxmodx/configs/bhop_timer.cfg`. The private config at `bhop_timer_private.cfg` is executed automatically after the main config when it exists.

#### Core

| Cvar | Default | Description |
|------|---------|-------------|
| `bhop_timer_enabled` | `1` | Master switch |
| `bhop_timer_hud` | `1` | Show timer and speed HUD |
| `bhop_timer_hud_update` | `0.1` | HUD refresh interval in seconds |
| `bhop_chat_prefix` | `[TIMER]` | Colored chat prefix |
| `bhop_records_enabled` | `1` | Enable Pro15 record tracking |
| `bhop_records_pro_limit` | `15` | Maximum Pro15 entries per map/mode |

#### Timer & Zones

| Cvar | Default | Description |
|------|---------|-------------|
| `bhop_reset_on_death` | `1` | Reset timer on player death |
| `bhop_reset_on_teamchange` | `1` | Reset timer on team change |
| `bhop_zone_render` | `1` | Render zone wireframes |
| `bhop_zone_render_interval` | `0.8` | Zone render refresh in seconds |
| `bhop_zone_start_color` | `0 255 0` | Start zone RGB color |
| `bhop_zone_finish_color` | `255 0 0` | Finish zone RGB color |
| `bhop_zone_admin_flag` | `l` | Admin flag for zone editor |
| `bhop_start_teleport_z_offset` | `40.0` | Height offset when teleporting to start |
| `bhop_teleport_on_finish` | `1` | Teleport player back to start after finishing |

#### Gameplay

| Cvar | Default | Description |
|------|---------|-------------|
| `bhop_auto_ct` | `1` | Force all players to CT |
| `bhop_start_menu_on_join` | `1` | Show main menu on connect |
| `bhop_godmode` | `1` | Give players godmode |
| `bhop_block_server_commands` | `1` | Block team change, buy, radio commands |
| `bhop_block_weapon_pickup` | `1` | Block weapon and item pickup |
| `bhop_auto_bhop` | `1` | Auto bunny hop (no scroll needed) |
| `bhop_speedometer` | `1` | Show speed in HUD |
| `bhop_remove_jump_slowdown` | `1` | Remove jump slowdown |
| `bhop_player_maxspeed` | `40000` | Max player speed |
| `bhop_round_keeper_bot` | `1` | Spawn a keeper bot to prevent round ends |
| `bhop_round_keeper_name` | `eskidostlarbhop.pages.dev` | Keeper bot name |

#### Modes & FPS

| Cvar | Default | Description |
|------|---------|-------------|
| `bhop_normal_fps_enforce` | `1` | Enforce FPS limit in Normal mode |
| `bhop_normal_fps_limit` | `135` | FPS threshold above which players are teleported back |
| `bhop_normal_fps_max` | `131` | `fps_max` value forced in Normal mode |
| `bhop_other_modes_fps_max` | `1000` | `fps_max` value forced in Low Gravity and Double Jump |

#### Hook & Parachute

| Cvar | Default | Description |
|------|---------|-------------|
| `bhop_hook_enabled` | `1` | Enable hook movement (`bind c +hook`) |
| `bhop_hook_speed` | `900.0` | Hook pull speed |
| `bhop_hook_max_distance` | `2000.0` | Maximum hook distance |
| `bhop_hook_min_distance` | `64.0` | Minimum hook distance |
| `bhop_parachute_enabled` | `1` | Enable parachute on `+use` |
| `bhop_parachute_fall_speed` | `120.0` | Parachute fall speed |

#### Physics Fixes (bhop_physics_fixes.amxx)

| Cvar | Default | Description |
|------|---------|-------------|
| `bhop_surf_fix` | `1` | Fix surf stop bug (losing speed on ramps) |
| `bhop_surf_fix_min_speed` | `180.0` | Minimum horizontal speed to apply surf fix |
| `bhop_surf_fix_restore_velocity` | `0` | Restore pre-frame velocity after surf fix |
| `bhop_surf_fix_unstuck_height` | `0.01` | Vertical nudge when unsticking from ramp surfaces |
| `bhop_surf_fix_trace_height` | `0.01` | Trace height for surf slope detection |
| `bhop_waterjump_fix` | `1` | Boost players out of water when they press jump |
| `bhop_edgebug_fix` | `0` | Preserve horizontal speed when landing on map edges |
| `bhop_keep_teleport_velocity` | `0` | Keep velocity through trigger_teleport |

#### MySQL (bhop_timer.cfg)

| Cvar | Default | Description |
|------|---------|-------------|
| `bhop_sql_enabled` | `0` | Enable remote MySQL storage (disabled in public package) |
| `bhop_sql_host` | `127.0.0.1:3306` | MySQL host (supports `host:port`) |
| `bhop_sql_user` | `bhop_user` | MySQL user |
| `bhop_sql_pass` | `change_me` | MySQL password |
| `bhop_sql_db` | `bhop_timer` | MySQL database |
| `bhop_sql_timeout` | `5` | Connection timeout in seconds |

#### Web Leaderboard

| Cvar | Default | Description |
|------|---------|-------------|
| `bhop_motd_web_enabled` | `1` | Use web MOTD for `/pro15` and `/top15` |
| `bhop_motd_web_url` | (URL) | Web leaderboard base URL |

#### Server Physics Override

| Cvar | Default | Description |
|------|---------|-------------|
| `bhop_apply_server_cvars` | `1` | Apply bhop server physics cvars on startup |
| `bhop_sv_airaccelerate` | `999999999` | `sv_airaccelerate` |
| `bhop_sv_maxspeed` | `40000` | `sv_maxspeed` |
| `bhop_sv_maxvelocity` | `40000` | `sv_maxvelocity` |
| `bhop_sv_accelerate` | `999999999` | `sv_accelerate` |
| `bhop_sv_friction` | `0` | `sv_friction` |
| `bhop_sv_stopspeed` | `0` | `sv_stopspeed` |
| `bhop_sv_airmove` | `1` | `sv_airmove` |
| `bhop_edgefriction` | `0` | `edgefriction` |
| `bhop_mp_freezetime` | `0` | `mp_freezetime` |
| `bhop_mp_roundtime` | `9` | `mp_roundtime` |

#### Advertisements

| Cvar | Default | Description |
|------|---------|-------------|
| `bhop_ads_enabled` | `1` | Enable rotating chat ads |
| `bhop_ads_interval` | `120` | Seconds between ads (minimum 30) |
| `bhop_ad_text_1` through `bhop_ad_text_5` | (Turkish) | Up to 5 advertisement messages |

#### Admin Glow

| Cvar | Default | Description |
|------|---------|-------------|
| `bhop_admin_glow` | `1` | Give admins a visible glow shell |
| `bhop_admin_glow_color` | `180 180 180` | Glow RGB color |
| `bhop_admin_glow_amount` | `18` | Glow render amount |

## Player Commands

| Command | Description |
|---------|-------------|
| `/menu` | Open main player menu |
| `/start` or `/respawn` | Teleport to start zone |
| `/reset` | Reset timer and teleport to start |
| `/pro15` or `/top15` | Show Pro15 leaderboard (MOTD) |
| `/rank` | Show current rank and best time |
| `/best` | Show personal best time |
| `/last` | Show last finished run time |
| `/mode` or `/mod` | Open mode selection (Normal / Low Gravity / Double Jump) |
| `/fps` | Open FPS and visibility settings menu |
| `/replay` or `/wr` | Watch or change the WR replay bot mode |
| `/spec` or `/bot` or `/wrbot` | Spectate the WR replay bot |
| `/ct` | Return to CT play mode |
| `/duel` | Challenge another player to a race |
| `/accept` | Accept a duel challenge |
| `/bhopstatus` | Show database, zone, and configuration status |
| `/help` | Show help MOTD with all commands |
| `/hook` (`+hook`/`-hook`) | Movement hook (aborts timer run) |
| `/noclip` | Toggle noclip (admin only, resets timer) |

## Admin Commands

| Command | Access | Description |
|---------|--------|-------------|
| `/zone` or `/zonemenu` | `ADMIN_RCON` (flag `l`) | Open zone editor menu |
| `/zundo` | `ADMIN_RCON` | Undo last zone point |
| `zone_save` | `ADMIN_RCON` | Save polygon zones |
| `zone_reload` | `ADMIN_RCON` | Reload polygon zones |
| `amx_bhop_start_a` | `ADMIN_RCON` | Set start zone point A |
| `amx_bhop_start_b` | `ADMIN_RCON` | Set start zone point B |
| `amx_bhop_finish_a` | `ADMIN_RCON` | Set finish zone point A |
| `amx_bhop_finish_b` | `ADMIN_RCON` | Set finish zone point B |
| `amx_bhop_save` | `ADMIN_RCON` | Save edited zones for current map |
| `amx_bhop_reload` | `ADMIN_RCON` | Reload zones for current map |
| `amx_bhop_delete_start` | `ADMIN_RCON` | Delete start zone |
| `amx_bhop_delete_finish` | `ADMIN_RCON` | Delete finish zone |
| `amx_bhop_db_retry` | `ADMIN_RCON` | Retry MySQL connection |
| `amx_bhop_reset_top15 <normal\|lowgrav\|dbjump\|all>` | `ADMIN_RCON` | Reset Pro15 records |
| `/build` | `ADMIN_RCON` | Open block builder menu |
| `/remove` | `ADMIN_RCON` | Hide/remove aimed entity |
| `/undo` | `ADMIN_RCON` | Undo last builder action |

## Map Manager Commands

| Command | Description |
|---------|-------------|
| `/rtv` | Rock the vote |
| `/nominate` | Nominate a map for the next vote |
| `/nextmap` | Show the next map |
| `/timeleft` | Show time remaining |

## Game Modes

### Normal

Standard bhop rules. FPS is enforced at the `bhop_normal_fps_max` value (default 131). Players exceeding `bhop_normal_fps_limit` (default 135) are teleported back to start and warned.

### Low Gravity

`sv_gravity` is reduced. No FPS cap is applied -- `fps_max` is set to `bhop_other_modes_fps_max` (default 1000).

### Double Jump

Players can jump a second time mid-air by pressing jump again while airborne. No FPS cap.

## Zone System

The zone system is provided by `speedrun_zone.amxx` which implements a full polygon editor with visual feedback. Other plugins register zone types through the `speedrun_zone_api.inc` native interface:

```pawn
sr_zone_register_type(
    .class_name = "zone_start",
    .description = "Bhop start zone",
    .color = {0, 255, 0},
    .visibility = ZONE_VISIBLE_FULL,
    .on_enter = "OnStartZoneEnter",
    .on_leave = "OnStartZoneLeave"
);
```

Zones are stored as JSON files per map under `addons/amxmodx/data/bhop_timer/<map>_zones.json`.

## Block Builder

`bhop_builder.amxx` provides an in-game block creation system:

- `/build` opens the builder menu to create horizontal platforms (64x64x16) or vertical walls (16x64x64)
- Grab blocks with E key or from the menu; push/pull with jump/duck; stamp with left click; delete with right click
- 3D corner editor for precise resizing by dragging corner anchors
- Blocks are 8-unit grid snapped (X/Y) and 4-unit snapped (Z)
- Undo support for create, delete, and modify operations
- `/remove` hides any aimed entity by origin
- Block positions and entity removals are saved per map to `addons/amxmodx/configs/bhop_blocks_<map>.cfg` and `bhop_removals_<map>.cfg`

## Physics Fixes

`bhop_physics_fixes.amxx` addresses several Source/GoldSrc engine bugs that affect bhop and surf gameplay:

- **Surf stop fix**: Detects when players lose speed on ramps and removes `FL_ONGROUND` to restore momentum. Uses both line and hull traces for reliable slope detection.
- **Surf stop zero-velocity recovery**: When horizontal velocity drops to exactly zero on a ramp, restores the frame-start velocity to prevent dead stops.
- **Water jump fix**: Boosts players out of water when they press jump at the water surface.
- **Edge bug fix** (optional): Preserves horizontal speed when landing precisely on map edges.
- **Teleport velocity reset**: Clears velocity after `trigger_teleport` touches to prevent speed carry-through bugs.

## Web Leaderboard

When `bhop_motd_web_enabled` is `1`, `/pro15` and `/top15` redirect to the configured web URL using the GoldSrc MOTD panel. The Cloudflare Pages source for the leaderboard can be deployed independently.

Pro15 records are stored locally in `addons/amxmodx/data/bhop_timer/` files and optionally synced to MySQL when `bhop_sql_enabled` is `1`.

## Web Leaderboard

A PHP web leaderboard is included in `web/`. It reads records from the same MySQL database the plugin writes to and serves two views:

- **MOTD view** (`pro15.php?map=<mapname>&mode=<mode>`) -- minimal HTML designed for the CS 1.6 MOTD panel. This is what players see when they type `/pro15` or `/top15` in-game.
- **Full site** (`index.php`) -- all maps organized in a card grid, with mode tabs (Normal / Low Gravity / Double Jump). Players not in the game can browse the full leaderboard from a browser.

The in-game plugin uses `bhop_motd_web_url` to redirect the MOTD to the web URL. When a player types `/pro15`, the plugin generates a meta refresh redirect to:

```
http://YOUR_SERVER_ADDRESS/pro15.php?map=bhop_m_ramp2&mode=normal
```

### Web Setup

1. Copy the `web/` folder to your PHP-enabled web server.
2. Edit `web/db.php` and set your MySQL credentials:

   ```php
   define('DB_HOST', '127.0.0.1');
   define('DB_PORT', 3306);
   define('DB_NAME', 'bhop_timer');
   define('DB_USER', 'bhop_timer');
   define('DB_PASS', 'change_me');
   ```

3. Make sure the MySQL database and tables exist (the plugin creates them automatically, or run `dist/bmod-server/docs/bhop_timer_mysql_setup.sql`).
4. Set `bhop_motd_web_url` in `bhop_timer.cfg` to point to `pro15.php` on your server:

   ```cfg
   bhop_motd_web_url "http://YOUR_SERVER_ADDRESS/pro15.php"
   ```

5. If you want clean URLs, enable `mod_rewrite` and use the included `.htaccess`:

   ```
   /map/bhop_m_ramp2/normal    -> index.php?map=bhop_m_ramp2&mode=normal
   /pro15?map=bhop_m_ramp2&mode=normal  -> pro15.php?map=bhop_m_ramp2&mode=normal
   ```

### CS 1.6 MOTD Compatibility

The MOTD panel in CS 1.6 uses an embedded Internet Explorer (Trident) engine with significant limitations:

- No modern CSS (no flexbox, no grid, no `position: fixed`)
- No JavaScript in many client configurations
- Small viewport (~640x480)
- `meta http-equiv="refresh"` works for redirecting to an external URL

The `pro15.php` template uses only inline CSS, table-based layout, and no JavaScript. All styling is embedded in the HTML response so it renders correctly inside the GoldSrc MOTD panel.

### Database Schema

The plugin creates these tables automatically:

```sql
CREATE TABLE bhop_records (
    id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,
    record_key VARCHAR(160) NOT NULL UNIQUE,
    map VARCHAR(64) NOT NULL,
    authid VARCHAR(35) NOT NULL,
    name VARCHAR(32) NOT NULL,
    mode TINYINT UNSIGNED NOT NULL DEFAULT 0,
    time_ms INT UNSIGNED NOT NULL,
    created_at INT UNSIGNED NOT NULL
);

CREATE TABLE bhop_best (
    map VARCHAR(64) NOT NULL,
    authid VARCHAR(35) NOT NULL,
    name VARCHAR(32) NOT NULL,
    mode TINYINT UNSIGNED NOT NULL DEFAULT 0,
    best_time_ms INT UNSIGNED NOT NULL,
    updated_at INT UNSIGNED NOT NULL,
    PRIMARY KEY (map, mode, authid)
);
```

The `mode` column uses `0` for Normal, `1` for Low Gravity, and `2` for Double Jump.

### Web Directory

```
web/
  .htaccess          Apache mod_rewrite rules for clean URLs
  db.php             MySQL connection, schema, and query helpers
  index.php          Full leaderboard site (all maps, mode tabs, WR banner)
  pro15.php          MOTD-compatible Pro15 view for in-game use
  style.css          Site-wide styles (dark theme, CS 1.6 aesthetic)
```

## Replay Sync

`tools/replay-sync.ps1` watches the AMXX replay directory and uploads changed WR replay files to a compatible API endpoint.

```powershell
powershell -ExecutionPolicy Bypass -File tools\install-replay-sync.ps1
```

The upload endpoint, token, and AMXX data directory are configurable for other hosts.

## Plugin Architecture

| Plugin | File | Role |
|--------|------|------|
| Speedrun Zones | `speedrun_zone.amxx` | Polygon zone editor, storage, rendering, and native API. Must load first. |
| Bhop Timer Core | `bhop_timer.amxx` | Timer lifecycle, HUD, Pro15 records, modes, hook, parachute, duel, FPS enforcement, auto-CT, round keeper bot. Must load after zones. |
| Map Manager | `bhop_map_manager.amxx` | RTV, nomination, map vote countdown |
| Physics Fixes | `bhop_physics_fixes.amxx` | Surf/ramp stop fix, water jump, edge bug, teleport velocity reset |
| Scoreboard FPS | `bhop_scoreboard_fps.amxx` | Displays real-time player FPS in the scoreboard deaths column |
| Block Builder | `bhop_builder.amxx` | In-game platform creation, resizing, entity removal, 3D corner editor |

## Release Layout

```
dist/bmod-server/       Clean game-server package
dist/vendor/            ReAPI/ReGameDLL runtime files
dist/dev/               Debug builds
```

The release excludes local caches, node_modules, Wrangler cache, private credentials, and downloaded source archives.