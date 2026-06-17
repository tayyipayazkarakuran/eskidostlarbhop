#include <amxmodx>
#include <amxmisc>
#include <cstrike>
#include <fakemeta>
#include <hamsandwich>
#include <sqlx>
#include <speedrun_zone_api>

#if !defined TE_BEAMPOINTS
    #define TE_BEAMPOINTS 0
#endif

#if !defined kRenderFxNone
    #define kRenderFxNone 0
#endif

#if !defined kRenderFxGlowShell
    #define kRenderFxGlowShell 3
#endif

#if !defined kRenderNormal
    #define kRenderNormal 0
#endif

#define PLUGIN_NAME    "Bhop Timer Core"
#define PLUGIN_VERSION "0.3.16"
#define PLUGIN_AUTHOR  "Codex"

#define TASK_HUD       24001
#define TASK_RENDER    24002
#define TASK_AUTOJOIN  24100
#define TASK_START_TP  24200
#define TASK_SPAWN_CT  24300
#define TASK_KEEPER    24400
#define TASK_LOAD_BEST 24500
#define TASK_DB_RETRY  24700
#define TASK_DB_FLUSH  24701
#define TASK_ADVERTISE 24800
#define TASK_REPLAY_BOT 24900
#define TASK_START_MENU 25000
#define TASK_FPS_CHECK 25001
#define TASK_MODE_FPS_MAX 25002

#define MAX_PLAYERS       32
#define MAX_SPAWN_RETRIES 10
#define MAX_NAME_SQL      96
#define MAX_AUTH_SQL      96
#define MAX_MAP_SQL       160
#define EDIT_POINT_COUNT  4
#define MAX_FILE_RECORDS  256
#define MAX_AD_MESSAGES    5
#define MAX_ZONE_SHAPE_JSON 2048
#define MAX_ZONE_SHAPE_SQL  4096
#define DB_FLUSH_DELAY      0.25

enum _:ZoneType
{
    ZONE_START = 0,
    ZONE_FINISH,
    ZONE_COUNT
};

enum _:TimerState
{
    TIMER_IDLE = 0,
    TIMER_IN_START,
    TIMER_RUNNING,
    TIMER_FINISHED
};

new const g_zoneNames[ZONE_COUNT][] =
{
    "start",
    "finish"
};

new const g_zoneLabels[ZONE_COUNT][] =
{
    "Start",
    "Finish"
};

new bool:g_zoneLoaded[ZONE_COUNT];
new Float:g_zoneMin[ZONE_COUNT][3];
new Float:g_zoneMax[ZONE_COUNT][3];
new bool:g_zoneSyncBlocked;

new const g_zoneClasses[ZONE_COUNT][] =
{
    "zone_start",
    "zone_finish"
};

new bool:g_editHasPoint[MAX_PLAYERS + 1][EDIT_POINT_COUNT];
new Float:g_editPoint[MAX_PLAYERS + 1][EDIT_POINT_COUNT][3];

new g_timerState[MAX_PLAYERS + 1];
new bool:g_prevInStart[MAX_PLAYERS + 1];
new bool:g_prevInFinish[MAX_PLAYERS + 1];
new Float:g_startGameTime[MAX_PLAYERS + 1];
new g_currentTimeMs[MAX_PLAYERS + 1];
new g_bestTimeMs[MAX_PLAYERS + 1];
new g_lastTimeMs[MAX_PLAYERS + 1];

new g_mapName[64];
new g_beamSprite;
new bool:g_dbTried;
new bool:g_dbConfigured;
new bool:g_dbReady;
new bool:g_dbInitInFlight;
new bool:g_dbQueueInFlight;
new g_dbQueueLine = -1;
new g_dbQueueScanLine;
new g_dbSchemaStep;
new g_recordSequence;
new bool:g_internalTeamCommand[MAX_PLAYERS + 1];
new g_spawnRetryCount[MAX_PLAYERS + 1];
new g_fileAuth[MAX_FILE_RECORDS][35];
new g_fileName[MAX_FILE_RECORDS][32];
new g_fileTime[MAX_FILE_RECORDS];
new bool:g_bestFileCacheLoaded[3];
new g_bestFileCacheCount[3];
new g_bestFileCacheAuth[3][MAX_FILE_RECORDS][35];
new g_bestFileCacheName[3][MAX_FILE_RECORDS][32];
new g_bestFileCacheTime[3][MAX_FILE_RECORDS];
new g_lastPro15File[MAX_PLAYERS + 1][192];

enum
{
    MODE_NORMAL = 0,
    MODE_LOW_GRAVITY,
    MODE_DOUBLE_JUMP
};

new g_playerMode[MAX_PLAYERS + 1];
new bool:g_doubleJumped[MAX_PLAYERS + 1];
new bool:g_jumpReleased[MAX_PLAYERS + 1];
new bool:g_hookActive[MAX_PLAYERS + 1];
new Float:g_hookTarget[MAX_PLAYERS + 1][3];
new Float:g_hookLastBeamTime[MAX_PLAYERS + 1];

#define MAX_REPLAY_FRAMES 35000
#define RECORD_INTERVAL 0.01
#define TASK_PLAYBACK 24600

new Float:g_replayOrigin[MAX_PLAYERS + 1][MAX_REPLAY_FRAMES][3];
new Float:g_replayAngles[MAX_PLAYERS + 1][MAX_REPLAY_FRAMES][3];
new bool:g_replayDucking[MAX_PLAYERS + 1][MAX_REPLAY_FRAMES];
new g_replayFrameCount[MAX_PLAYERS + 1];
new Float:g_lastRecordTime[MAX_PLAYERS + 1];

// Strafe Sync HUD Stats (Removed)

new g_replayBot;
new g_botReplayMode;
new Float:g_botReplayOrigin[MAX_REPLAY_FRAMES][3];
new Float:g_botReplayAngles[MAX_REPLAY_FRAMES][3];
new bool:g_botReplayDucking[MAX_REPLAY_FRAMES];
new g_botReplayTotalFrames;
new g_botPlaybackFrame;
new Float:g_lastPlaybackTime;
new Float:g_botPlaybackInterval = 0.01;

new bool:g_fpsHidePlayers[MAX_PLAYERS + 1];
new bool:g_fpsHideText[MAX_PLAYERS + 1];
new bool:g_fpsHideWeapon[MAX_PLAYERS + 1];
new bool:g_fpsHideHud[MAX_PLAYERS + 1];
new bool:g_fpsHideWater[MAX_PLAYERS + 1];
new g_fpsBrightnessLevel[MAX_PLAYERS + 1];
new g_fpsSoundLevel[MAX_PLAYERS + 1];
new g_modeFpsFrames[MAX_PLAYERS + 1];
new g_modeFpsValue[MAX_PLAYERS + 1];
new Float:g_lastNormalFpsWarn[MAX_PLAYERS + 1];
new Float:g_lastModeFpsMaxApply[MAX_PLAYERS + 1];

new g_wrHolderName[3][32];
new g_bestCacheGeneration[3];

enum
{
    DUEL_STATE_IDLE = 0,
    DUEL_STATE_WAITING,
    DUEL_STATE_COUNTDOWN,
    DUEL_STATE_RACING
};

new g_duelState[MAX_PLAYERS + 1];
new g_duelPartner[MAX_PLAYERS + 1];
new g_duelCountdownTime[MAX_PLAYERS + 1];

forward BuildReplayPath(mode, output[], len);
forward bool:LoadReplayFile(mode);
forward GetRecordHolderName(mode, outputName[], len);
forward GetRecordTime(mode);
forward MaintainReplayBot();
forward KickReplayBot();
forward TaskCreateReplayBot(taskid);
forward PlaybackBotFrame();
forward CmdSpec(id);
forward TaskForceSpectateBot(id);
forward CmdCt(id);
forward TaskSpawnAndTeleport(id);
forward CmdMainMenu(id);
forward MainMenuHandler(id, menu, item);
forward TaskShowStartMenu(taskid);
forward TaskNormalFpsCheck();
forward TaskApplyModeFpsMax(taskid);
forward CmdBhopReplayMenu(id);
forward BhopReplayMenuHandler(id, menu, item);
forward CmdHookOn(id);
forward CmdHookOff(id);

forward FwStartFrame();
forward FwHamTakeDamage(victim, inflictor, attacker, Float:damage, damagebits);
forward FwAddToFullPack(es_handle, e, ent, host, hostflags, player, pSet);
forward MsgHideWeapon(msgid, dest, id);
forward EventCurWeapon(id);
forward CmdNoclip(id);
forward CmdFpsMenu(id);
forward FpsMenuHandler(id, menu, item);
forward UpdatePlayerHudVisibility(id);
forward ApplyAdminGlow(id);

forward UpdateWrHolders();
forward GetPlayerWrPrefix(const name[], output[], len);
forward GetPlayerTeamColorString(id, output[], len);
forward CmdDuel(id);
forward CmdAccept(id);
forward DuelMenuHandler(id, menu, item);
forward ChallengeMenuHandler(id, menu, item);
forward TaskDuelCountdown(taskid);
// forward ResetDuelState(id);

stock bool:TimerSetTask(Float:delay, const callback[], taskid = 0, bool:repeat = false)
{
    if (!callback[0])
    {
        log_amx("[TIMER] Refused empty task callback (task id %d).", taskid);
        return false;
    }

    if (get_func_id(callback) == -1)
    {
        log_amx("[TIMER] Missing task callback '%s' (task id %d).", callback, taskid);
        return false;
    }

    if (repeat)
    {
        set_task(delay, callback, taskid, "", 0, "b");
    }
    else
    {
        set_task(delay, callback, taskid);
    }

    return true;
}


new g_cvarEnabled;
new g_cvarHud;
new g_cvarHudUpdate;
new g_cvarRender;
new g_cvarRenderInterval;
new g_cvarStartColor;
new g_cvarFinishColor;
new g_cvarRecords;
new g_cvarTopLimit;
new g_cvarAdminFlag;
new g_cvarChatPrefix;
new g_cvarResetOnDeath;
new g_cvarResetOnTeamChange;
// new g_cvarCountAdminNoclip;
new g_cvarZoneZPadding;
new g_cvarZoneFloorOffset;
new g_cvarZoneRenderZOffset;
new g_cvarZoneSnapToFloor;
new g_cvarStartTeleportZOffset;
new g_cvarTeleportOnFinish;
new g_cvarAutoCt;
new g_cvarStartMenuOnJoin;
new g_cvarGodmode;
new g_cvarBlockServerCommands;
new g_cvarBlockWeaponPickup;
new g_cvarAutoBhop;
new g_cvarSpeedometer;
new g_cvarNormalFpsEnforce;
new g_cvarNormalFpsLimit;
new g_cvarNormalFpsMax;
new g_cvarOtherModesFpsMax;
new g_cvarPlayerMaxspeed;
new g_cvarRemoveJumpSlowdown;
new g_cvarApplyServerCvars;
new g_cvarRoundKeeperBot;
new g_cvarRoundKeeperName;
new g_cvarReplayPitchInvert;
new g_cvarHookEnabled;
new g_cvarHookSpeed;
new g_cvarHookMaxDistance;
new g_cvarHookMinDistance;
new g_cvarParachuteEnabled;
new g_cvarParachuteFallSpeed;
new g_cvarAdminGlow;
new g_cvarAdminGlowColor;
new g_cvarAdminGlowAmount;
new g_cvarAdsEnabled;
new g_cvarAdsInterval;
new g_cvarAdText[MAX_AD_MESSAGES];
new g_cvarSvAiraccelerate;
new g_cvarSvMaxspeed;
new g_cvarSvMaxvelocity;
new g_cvarSvAccelerate;
new g_cvarSvFriction;
new g_cvarSvStopspeed;
new g_cvarSvAirmove;
new g_cvarEdgeFriction;
new g_cvarMpFreezetime;
new g_cvarMpRoundtime;
new g_cvarSqlEnabled;
new g_cvarSqlHost;
new g_cvarSqlUser;
new g_cvarSqlPass;
new g_cvarSqlDb;
new g_cvarSqlTimeout;
new g_cvarMotdWebEnabled;
new g_cvarMotdWebUrl;

new Handle:g_sqlTuple = Empty_Handle;
new g_keeperBot;
new g_nextAdvertisement;
new g_msgSayText;
new g_msgShowMenu;
new g_msgVguiMenu;

new const g_radioCommands[][] =
{
    "radio1", "radio2", "radio3",
    "coverme", "takepoint", "holdpos", "regroup", "followme", "takingfire",
    "go", "fallback", "sticktog", "getinpos", "stormfront", "report",
    "roger", "enemyspot", "needbackup", "sectorclear", "inposition",
    "reportingin", "getout", "negative", "enemydown"
};

public plugin_precache()
{
    g_beamSprite = precache_model("sprites/laserbeam.spr");
}

public plugin_init()
{
    register_plugin(PLUGIN_NAME, PLUGIN_VERSION, PLUGIN_AUTHOR);

    g_cvarEnabled = register_cvar("bhop_timer_enabled", "1");
    g_cvarHud = register_cvar("bhop_timer_hud", "1");
    g_cvarHudUpdate = register_cvar("bhop_timer_hud_update", "0.1");
    g_cvarRender = register_cvar("bhop_zone_render", "1");
    g_cvarRenderInterval = register_cvar("bhop_zone_render_interval", "0.8");
    g_cvarStartColor = register_cvar("bhop_zone_start_color", "0 255 0");
    g_cvarFinishColor = register_cvar("bhop_zone_finish_color", "255 0 0");
    g_cvarRecords = register_cvar("bhop_records_enabled", "1");
    g_cvarTopLimit = register_cvar("bhop_records_pro_limit", "15");
    g_cvarAdminFlag = register_cvar("bhop_zone_admin_flag", "l");
    g_cvarChatPrefix = register_cvar("bhop_chat_prefix", "[TIMER]");
    g_cvarResetOnDeath = register_cvar("bhop_reset_on_death", "1");
    g_cvarResetOnTeamChange = register_cvar("bhop_reset_on_teamchange", "1");
    // g_cvarCountAdminNoclip = register_cvar("bhop_count_admin_noclip", "0");
    g_cvarZoneZPadding = register_cvar("bhop_zone_z_padding", "72.0");
    g_cvarZoneFloorOffset = register_cvar("bhop_zone_floor_offset", "-36.0");
    g_cvarZoneRenderZOffset = register_cvar("bhop_zone_render_z_offset", "1.0");
    g_cvarZoneSnapToFloor = register_cvar("bhop_zone_snap_to_floor", "1");
    g_cvarStartTeleportZOffset = register_cvar("bhop_start_teleport_z_offset", "40.0");
    g_cvarTeleportOnFinish = register_cvar("bhop_teleport_on_finish", "1");
    g_cvarAutoCt = register_cvar("bhop_auto_ct", "1");
    g_cvarStartMenuOnJoin = register_cvar("bhop_start_menu_on_join", "1");
    g_cvarGodmode = register_cvar("bhop_godmode", "1");
    g_cvarBlockServerCommands = register_cvar("bhop_block_server_commands", "1");
    g_cvarBlockWeaponPickup = register_cvar("bhop_block_weapon_pickup", "1");
    g_cvarAutoBhop = register_cvar("bhop_auto_bhop", "1");
    g_cvarSpeedometer = register_cvar("bhop_speedometer", "1");
    g_cvarNormalFpsEnforce = register_cvar("bhop_normal_fps_enforce", "1");
    g_cvarNormalFpsLimit = register_cvar("bhop_normal_fps_limit", "135");
    g_cvarNormalFpsMax = register_cvar("bhop_normal_fps_max", "131");
    g_cvarOtherModesFpsMax = register_cvar("bhop_other_modes_fps_max", "1000");
    g_cvarPlayerMaxspeed = register_cvar("bhop_player_maxspeed", "40000");
    g_cvarRemoveJumpSlowdown = register_cvar("bhop_remove_jump_slowdown", "1");
    g_cvarApplyServerCvars = register_cvar("bhop_apply_server_cvars", "1");
    g_cvarRoundKeeperBot = register_cvar("bhop_round_keeper_bot", "1");
    g_cvarRoundKeeperName = register_cvar("bhop_round_keeper_name", "eskidostlarbhop.pages.dev");
    g_cvarReplayPitchInvert = register_cvar("bhop_replay_pitch_invert", "0");
    g_cvarHookEnabled = register_cvar("bhop_hook_enabled", "1");
    g_cvarHookSpeed = register_cvar("bhop_hook_speed", "900.0");
    g_cvarHookMaxDistance = register_cvar("bhop_hook_max_distance", "2000.0");
    g_cvarHookMinDistance = register_cvar("bhop_hook_min_distance", "64.0");
    g_cvarParachuteEnabled = register_cvar("bhop_parachute_enabled", "1");
    g_cvarParachuteFallSpeed = register_cvar("bhop_parachute_fall_speed", "120.0");
    g_cvarAdminGlow = register_cvar("bhop_admin_glow", "1");
    g_cvarAdminGlowColor = register_cvar("bhop_admin_glow_color", "180 180 180");
    g_cvarAdminGlowAmount = register_cvar("bhop_admin_glow_amount", "18");
    g_cvarAdsEnabled = register_cvar("bhop_ads_enabled", "1");
    g_cvarAdsInterval = register_cvar("bhop_ads_interval", "120");
    g_cvarAdText[0] = register_cvar("bhop_ad_text_1", "Pro15 siralamasini eskidostlarbhop.pages.dev adresinden takip edebilirsin.");
    g_cvarAdText[1] = register_cvar("bhop_ad_text_2", "Haritanin en iyi 15 derecesi icin /pro15 yaz.");
    g_cvarAdText[2] = register_cvar("bhop_ad_text_3", "Dunya rekoru botunu izlemek icin /replay yaz.");
    g_cvarAdText[3] = register_cvar("bhop_ad_text_4", "Normal, Low Gravity ve Double Jump modlari icin /mode yaz.");
    g_cvarAdText[4] = register_cvar("bhop_ad_text_5", "Bir oyuncuya meydan okumak icin /duel yaz.");
    g_cvarSvAiraccelerate = register_cvar("bhop_sv_airaccelerate", "999999999");
    g_cvarSvMaxspeed = register_cvar("bhop_sv_maxspeed", "40000");
    g_cvarSvMaxvelocity = register_cvar("bhop_sv_maxvelocity", "40000");
    g_cvarSvAccelerate = register_cvar("bhop_sv_accelerate", "999999999");
    g_cvarSvFriction = register_cvar("bhop_sv_friction", "0");
    g_cvarSvStopspeed = register_cvar("bhop_sv_stopspeed", "0");
    g_cvarSvAirmove = register_cvar("bhop_sv_airmove", "1");
    g_cvarEdgeFriction = register_cvar("bhop_edgefriction", "0");
    g_cvarMpFreezetime = register_cvar("bhop_mp_freezetime", "0");
    g_cvarMpRoundtime = register_cvar("bhop_mp_roundtime", "9");
    g_cvarSqlEnabled = register_cvar("bhop_sql_enabled", "0");
    g_cvarSqlHost = register_cvar("bhop_sql_host", "127.0.0.1:3306");
    g_cvarSqlUser = register_cvar("bhop_sql_user", "bhop_user");
    g_cvarSqlPass = register_cvar("bhop_sql_pass", "change_me", FCVAR_PROTECTED);
    g_cvarSqlDb = register_cvar("bhop_sql_db", "bhop_timer");
    g_cvarSqlTimeout = register_cvar("bhop_sql_timeout", "5");
    g_cvarMotdWebEnabled = register_cvar("bhop_motd_web_enabled", "1");
    g_cvarMotdWebUrl = register_cvar("bhop_motd_web_url", "https://eskidostlarbhop.pages.dev/motd");

    new startColor[3] = {0, 255, 0};
    new finishColor[3] = {255, 0, 0};
    sr_zone_register_type(
        .class_name = "zone_start",
        .description = "Bhop start zone",
        .color = startColor,
        .visibility = ZONE_VISIBLE_FULL,
        .on_enter = "OnStartZoneEnter",
        .on_leave = "OnStartZoneLeave"
    );
    sr_zone_register_type(
        .class_name = "zone_finish",
        .description = "Bhop finish zone",
        .color = finishColor,
        .visibility = ZONE_VISIBLE_FULL,
        .on_enter = "OnFinishZoneEnter",
        .on_leave = "OnFinishZoneLeave"
    );

    g_msgSayText = get_user_msgid("SayText");
    g_msgShowMenu = get_user_msgid("ShowMenu");
    g_msgVguiMenu = get_user_msgid("VGUIMenu");

    register_forward(FM_PlayerPreThink, "FwPlayerPreThink");
    register_forward(FM_Touch, "FwTouch");
    register_forward(FM_StartFrame, "FwStartFrame");
    register_forward(FM_AddToFullPack, "FwAddToFullPack", 1);

    RegisterHam(Ham_TakeDamage, "player", "FwHamTakeDamage");
    register_message(get_user_msgid("HideWeapon"), "MsgHideWeapon");
    register_event("CurWeapon", "EventCurWeapon", "be", "1=1");

    register_message(g_msgShowMenu, "MsgShowMenu");
    register_message(g_msgVguiMenu, "MsgVguiMenu");

    register_event("DeathMsg", "EventDeathMsg", "a");
    register_event("TeamInfo", "EventTeamInfo", "a");

    register_clcmd("say /pro15", "CmdPro15");
    register_clcmd("say_team /pro15", "CmdPro15");
    register_clcmd("say /top15", "CmdPro15");
    register_clcmd("say_team /top15", "CmdPro15");
    register_clcmd("say /rank", "CmdRank");
    register_clcmd("say_team /rank", "CmdRank");
    register_clcmd("say /best", "CmdBest");
    register_clcmd("say_team /best", "CmdBest");
    register_clcmd("say /last", "CmdLast");
    register_clcmd("say_team /last", "CmdLast");
    register_clcmd("say /reset", "CmdReset");
    register_clcmd("say_team /reset", "CmdReset");
    register_clcmd("say /start", "CmdStart");
    register_clcmd("say_team /start", "CmdStart");
    register_clcmd("say /respawn", "CmdStart");
    register_clcmd("say_team /respawn", "CmdStart");
    register_clcmd("say /bhopstatus", "CmdBhopStatus");
    register_clcmd("say_team /bhopstatus", "CmdBhopStatus");

    register_clcmd("say /bhopmenu", "CmdBhopMenu");
    register_clcmd("say_team /bhopmenu", "CmdBhopMenu");
    register_clcmd("say /zonemenu", "CmdBhopMenu");
    register_clcmd("say_team /zonemenu", "CmdBhopMenu");
    register_clcmd("say /menu", "CmdMainMenu");
    register_clcmd("say_team /menu", "CmdMainMenu");
    register_clcmd("say /mainmenu", "CmdMainMenu");
    register_clcmd("say_team /mainmenu", "CmdMainMenu");

    register_clcmd("say /mode", "CmdBhopModeMenu");
    register_clcmd("say_team /mode", "CmdBhopModeMenu");
    register_clcmd("say /mod", "CmdBhopModeMenu");
    register_clcmd("say_team /mod", "CmdBhopModeMenu");

    register_clcmd("say /help", "CmdHelp");
    register_clcmd("say_team /help", "CmdHelp");

    register_clcmd("say /duel", "CmdDuel");
    register_clcmd("say_team /duel", "CmdDuel");
    register_clcmd("say /accept", "CmdAccept");
    register_clcmd("say_team /accept", "CmdAccept");

    register_clcmd("say", "CmdSay");
    register_clcmd("say_team", "CmdSayTeam");

    register_clcmd("say /spec", "CmdSpec");
    register_clcmd("say_team /spec", "CmdSpec");
    register_clcmd("say /ct", "CmdCt");
    register_clcmd("say_team /ct", "CmdCt");
    register_clcmd("say /replay", "CmdBhopReplayMenu");
    register_clcmd("say_team /replay", "CmdBhopReplayMenu");
    register_clcmd("say /wr", "CmdBhopReplayMenu");
    register_clcmd("say_team /wr", "CmdBhopReplayMenu");
    register_clcmd("say /bot", "CmdSpec");
    register_clcmd("say_team /bot", "CmdSpec");
    register_clcmd("say /wrbot", "CmdSpec");
    register_clcmd("say_team /wrbot", "CmdSpec");

    register_clcmd("say /noclip", "CmdNoclip");
    register_clcmd("say_team /noclip", "CmdNoclip");
    register_clcmd("say /fps", "CmdFpsMenu");
    register_clcmd("say_team /fps", "CmdFpsMenu");
    register_clcmd("+hook", "CmdHookOn");
    register_clcmd("-hook", "CmdHookOff");

    register_concmd("amx_bhop_start_a", "ConCmdStartA", ADMIN_RCON, "- set start zone point A");
    register_concmd("amx_bhop_start_b", "ConCmdStartB", ADMIN_RCON, "- set start zone point B");
    register_concmd("amx_bhop_finish_a", "ConCmdFinishA", ADMIN_RCON, "- set finish zone point A");
    register_concmd("amx_bhop_finish_b", "ConCmdFinishB", ADMIN_RCON, "- set finish zone point B");
    register_concmd("amx_bhop_save", "ConCmdSave", ADMIN_RCON, "- save edited zones for current map");
    register_concmd("amx_bhop_reload", "ConCmdReload", ADMIN_RCON, "- reload zones for current map");
    register_concmd("amx_bhop_delete_start", "ConCmdDeleteStart", ADMIN_RCON, "- delete start zone for current map");
    register_concmd("amx_bhop_delete_finish", "ConCmdDeleteFinish", ADMIN_RCON, "- delete finish zone for current map");
    register_concmd("amx_bhop_db_retry", "ConCmdDbRetry", ADMIN_RCON, "- retry remote MySQL connection and pending writes");
    register_concmd("amx_bhop_reset_top15", "ConCmdResetTop15", ADMIN_RCON, "<normal|lowgrav|dbjump|all> - reset current map records");

    RegisterBlockedCommands();
}

public plugin_cfg()
{
    get_mapname(g_mapName, charsmax(g_mapName));

    server_cmd("exec addons/amxmodx/configs/bhop_timer.cfg");
    server_exec();

    new privateCfg[128];
    copy(privateCfg, charsmax(privateCfg), "addons/amxmodx/configs/bhop_timer_private.cfg");
    if (file_exists(privateCfg))
    {
        server_cmd("exec %s", privateCfg);
        server_exec();
    }

    server_cmd("mp_limitteams 0");
    server_cmd("mp_autoteambalance 0");
    server_cmd("humans_join_team CT");
    ApplyBhopServerCvars();

    LoadZones();
    DbInitialize();

    TimerSetTask(0.1, "TaskHud", TASK_HUD, true);

    new Float:renderInterval = get_pcvar_float(g_cvarRenderInterval);
    if (renderInterval < 0.2)
    {
        renderInterval = 0.2;
    }
    TimerSetTask(renderInterval, "TaskRenderZones", TASK_RENDER, true);

    if (get_pcvar_num(g_cvarRoundKeeperBot))
    {
        TimerSetTask(1.5, "TaskCreateRoundKeeper");
    }

    TimerSetTask(1.0, "TaskNormalFpsCheck", TASK_FPS_CHECK, true);
    TimerSetTask(2.0, "TaskLoadAllBests");
    TimerSetTask(15.0, "TaskDbRetry", TASK_DB_RETRY, true);
    ScheduleNextAdvertisement();

    g_botReplayMode = MODE_NORMAL;
    LoadReplayFile(g_botReplayMode);
    TimerSetTask(2.0, "TaskCreateReplayBot", TASK_REPLAY_BOT, true);
}

public plugin_end()
{
    remove_task(TASK_HUD);
    remove_task(TASK_RENDER);
    remove_task(TASK_DB_RETRY);
    remove_task(TASK_DB_FLUSH);
    remove_task(TASK_KEEPER);
    remove_task(TASK_ADVERTISE);
    remove_task(TASK_REPLAY_BOT);
    remove_task(TASK_FPS_CHECK);

    if (g_keeperBot && is_user_connected(g_keeperBot))
    {
        server_cmd("kick #%d", get_user_userid(g_keeperBot));
    }

    if (g_replayBot && is_user_connected(g_replayBot))
    {
        server_cmd("kick #%d", get_user_userid(g_replayBot));
    }

    if (g_sqlTuple != Empty_Handle)
    {
        SQL_FreeHandle(g_sqlTuple);
        g_sqlTuple = Empty_Handle;
    }
}

public client_putinserver(id)
{
    g_playerMode[id] = MODE_NORMAL;
    g_doubleJumped[id] = false;
    g_jumpReleased[id] = false;
    ClearHookState(id);
    g_fpsHidePlayers[id] = false;
    g_fpsHideText[id] = false;
    g_fpsHideWeapon[id] = false;
    g_fpsHideHud[id] = false;
    g_fpsHideWater[id] = false;
    g_fpsBrightnessLevel[id] = 0;
    g_fpsSoundLevel[id] = 0;
    g_modeFpsFrames[id] = 0;
    g_modeFpsValue[id] = 0;
    g_lastNormalFpsWarn[id] = 0.0;
    g_lastModeFpsMaxApply[id] = 0.0;
    g_spawnRetryCount[id] = 0;
    g_duelState[id] = DUEL_STATE_IDLE;
    g_duelPartner[id] = 0;
    g_duelCountdownTime[id] = 0;
    
    // Strafe stats reset removed
    
    ResetPlayerData(id, true);
    TimerSetTask(0.8, "TaskAutoJoinCt", id + TASK_AUTOJOIN);
    TimerSetTask(1.4, "TaskApplyModeFpsMax", id + TASK_MODE_FPS_MAX);
    TimerSetTask(2.2, "TaskShowStartMenu", id + TASK_START_MENU);
    TimerSetTask(2.0, "TaskLoadPlayerBest", id + TASK_LOAD_BEST);
}

public client_authorized(id)
{
    LoadPlayerBest(id);
}

public TaskLoadPlayerBest(taskid)
{
    new id = taskid - TASK_LOAD_BEST;

    if (1 <= id <= MAX_PLAYERS && is_user_connected(id))
    {
        LoadPlayerBest(id);
    }
}

public TaskLoadAllBests()
{
    for (new id = 1; id <= MAX_PLAYERS; id++)
    {
        if (is_user_connected(id))
        {
            LoadPlayerBest(id);
        }
    }
    UpdateWrHolders();
}

public client_disconnected(id)
{
    remove_task(id + TASK_AUTOJOIN);
    remove_task(id + TASK_SPAWN_CT);
    remove_task(id + TASK_START_TP);
    remove_task(id + TASK_LOAD_BEST);
    remove_task(id + TASK_START_MENU);
    remove_task(id + TASK_MODE_FPS_MAX);
    g_internalTeamCommand[id] = false;
    g_spawnRetryCount[id] = 0;

    if (g_lastPro15File[id][0] && file_exists(g_lastPro15File[id]))
    {
        delete_file(g_lastPro15File[id]);
    }
    g_lastPro15File[id][0] = '^0';

    g_playerMode[id] = MODE_NORMAL;
    g_doubleJumped[id] = false;
    g_jumpReleased[id] = false;
    ClearHookState(id);
    g_fpsHidePlayers[id] = false;
    g_fpsHideText[id] = false;
    g_fpsHideWeapon[id] = false;
    g_fpsHideHud[id] = false;
    g_fpsHideWater[id] = false;
    g_fpsBrightnessLevel[id] = 0;
    g_fpsSoundLevel[id] = 0;
    g_modeFpsFrames[id] = 0;
    g_modeFpsValue[id] = 0;
    g_lastNormalFpsWarn[id] = 0.0;
    g_lastModeFpsMaxApply[id] = 0.0;
    
    if (g_duelState[id] != DUEL_STATE_IDLE)
    {
        new partner = g_duelPartner[id];
        if (partner && is_user_connected(partner))
        {
            new name[32];
            get_user_name(id, name, charsmax(name));
            TimerChat(partner, "^x04%s^x01 disconnected. You win the duel by default!", name);
            ResetDuelState(partner);
        }
        ResetDuelState(id);
    }
    
    ResetPlayerData(id, true);
}

public EventDeathMsg()
{
    new victim = read_data(2);
    if (1 <= victim <= MAX_PLAYERS)
    {
        ClearHookState(victim);

        if (g_duelState[victim] != DUEL_STATE_IDLE)
        {
            new partner = g_duelPartner[victim];
            if (partner && is_user_connected(partner) && is_user_alive(partner))
            {
                new name[32], partnerName[32];
                get_user_name(victim, name, charsmax(name));
                get_user_name(partner, partnerName, charsmax(partnerName));
                TimerChat(0, "^x04%s^x01 died! ^x04%s^x01 wins the duel!", name, partnerName);
                ResetDuelState(partner);
            }
            ResetDuelState(victim);
        }
        else if (get_pcvar_num(g_cvarResetOnDeath))
        {
            ResetPlayerData(victim, false);
        }
    }
}

public EventTeamInfo()
{
    new id = read_data(1);

    if (!get_pcvar_num(g_cvarResetOnTeamChange))
    {
        return;
    }

    if (1 <= id <= MAX_PLAYERS)
    {
        ResetPlayerData(id, false);
    }
}

public MsgShowMenu(msgid, dest, id)
{
    if (!get_pcvar_num(g_cvarAutoCt) || !is_user_connected(id))
    {
        return PLUGIN_CONTINUE;
    }

    new menuText[64];
    get_msg_arg_string(4, menuText, charsmax(menuText));

    if (contain(menuText, "Team_Select") != -1 ||
        contain(menuText, "Team_Select_Spect") != -1 ||
        contain(menuText, "IG_Team_Select") != -1 ||
        contain(menuText, "CT_Select") != -1 ||
        contain(menuText, "Terrorist_Select") != -1 ||
        contain(menuText, "Class_Select") != -1)
    {
        QueueAutoJoinCt(id, 0.1);
        return PLUGIN_HANDLED;
    }

    return PLUGIN_CONTINUE;
}

public MsgVguiMenu(msgid, dest, id)
{
    if (!get_pcvar_num(g_cvarAutoCt) || !is_user_connected(id))
    {
        return PLUGIN_CONTINUE;
    }

    new menu = get_msg_arg_int(1);
    if (menu == 2 || menu == 26 || menu == 27)
    {
        QueueAutoJoinCt(id, 0.1);
        return PLUGIN_HANDLED;
    }

    return PLUGIN_CONTINUE;
}

public FwPlayerPreThink(id)
{
    if (!get_pcvar_num(g_cvarEnabled))
    {
        return FMRES_IGNORED;
    }

    if (!is_user_alive(id))
    {
        return FMRES_IGNORED;
    }

    if (!is_user_bot(id))
    {
        g_modeFpsFrames[id]++;
    }

    if (pev(id, pev_movetype) == MOVETYPE_NOCLIP)
    {
        if (g_timerState[id] == TIMER_RUNNING || g_timerState[id] == TIMER_IN_START)
        {
            ResetPlayerData(id, false);
        }
        return FMRES_IGNORED;
    }

    // Strafe statistics calculation removed

    KeepAlivePlayerCt(id);
    ApplyPlayerProtections(id);
    ApplyAdminGlow(id);

    new buttons = pev(id, pev_button);
    new flags = pev(id, pev_flags);
    if (flags & FL_ONGROUND)
    {
        g_doubleJumped[id] = false;
        g_jumpReleased[id] = false;
    }
    else
    {
        if (!(buttons & IN_JUMP))
        {
            g_jumpReleased[id] = true;
        }
        else if (g_jumpReleased[id] && !g_doubleJumped[id] && g_playerMode[id] == MODE_DOUBLE_JUMP)
        {
            g_doubleJumped[id] = true;
            g_jumpReleased[id] = false;

            new Float:velocity[3];
            pev(id, pev_velocity, velocity);
            velocity[2] = 268.328157;
            set_pev(id, pev_velocity, velocity);
        }
    }

    ApplyMovementSettings(id);
    ApplyAutoBhop(id);
    ApplyPlayerHook(id);
    ApplyPlayerParachute(id);

    if (g_timerState[id] == TIMER_RUNNING && g_replayFrameCount[id] < MAX_REPLAY_FRAMES)
    {
        new Float:currentTime = get_gametime();
        if (currentTime - g_lastRecordTime[id] >= RECORD_INTERVAL)
        {
            pev(id, pev_origin, g_replayOrigin[id][g_replayFrameCount[id]]);
            pev(id, pev_v_angle, g_replayAngles[id][g_replayFrameCount[id]]);
            g_replayDucking[id][g_replayFrameCount[id]] = (pev(id, pev_flags) & FL_DUCKING) ? true : false;
            g_replayFrameCount[id]++;
            g_lastRecordTime[id] = currentTime;
        }
    }

    if (g_timerState[id] == TIMER_RUNNING)
    {
        g_currentTimeMs[id] = GetRunningTimeMs(id);
    }

    return FMRES_IGNORED;
}

public OnStartZoneEnter(zone_entity, id)
{
    #pragma unused zone_entity

    if (!(1 <= id <= MAX_PLAYERS) || !is_user_alive(id) || !CanCountRun(id))
        return;

    RefreshZoneCaches();

    if (g_timerState[id] == TIMER_RUNNING)
    {
        ResetToStart(id, true);
    }
    else if (g_timerState[id] == TIMER_IDLE || g_timerState[id] == TIMER_FINISHED)
    {
        g_timerState[id] = TIMER_IN_START;
        g_currentTimeMs[id] = 0;
    }

    g_prevInStart[id] = true;
}

public OnStartZoneLeave(zone_entity, id)
{
    #pragma unused zone_entity

    if (!(1 <= id <= MAX_PLAYERS) || !is_user_alive(id))
        return;

    if (g_timerState[id] == TIMER_IN_START && g_prevInStart[id] && CanCountRun(id))
    {
        StartTimer(id);
    }

    g_prevInStart[id] = false;
}

public OnFinishZoneEnter(zone_entity, id)
{
    #pragma unused zone_entity

    if (!(1 <= id <= MAX_PLAYERS) || !is_user_alive(id) || !CanCountRun(id))
        return;

    g_prevInFinish[id] = true;

    if (g_timerState[id] == TIMER_RUNNING)
    {
        FinishTimer(id);
    }
}

public OnFinishZoneLeave(zone_entity, id)
{
    #pragma unused zone_entity

    if (!(1 <= id <= MAX_PLAYERS))
        return;

    g_prevInFinish[id] = false;
}

public sr_zone_created(zone_entity, const zone_class[])
{
    #pragma unused zone_entity, zone_class
    RefreshZoneCaches();
    return PLUGIN_CONTINUE;
}

public sr_zone_deleted(zone_entity, const zone_class[])
{
    #pragma unused zone_entity, zone_class
    RefreshZoneCaches();
    return PLUGIN_CONTINUE;
}

public sr_zone_saved()
{
    if (g_zoneSyncBlocked)
        return PLUGIN_CONTINUE;

    RefreshZoneCaches();
    SaveZonesFromFramework(0);
    return PLUGIN_CONTINUE;
}

// FwCmdStart removed

public FwStartFrame()
{
    if (g_replayBot && is_user_connected(g_replayBot) && is_user_alive(g_replayBot))
    {
        PlaybackBotFrame();
    }
}

public TaskHud()
{
    if (!get_pcvar_num(g_cvarEnabled) || !get_pcvar_num(g_cvarHud))
    {
        return;
    }

    for (new id = 1; id <= MAX_PLAYERS; id++)
    {
        if (!is_user_connected(id) || g_fpsHideText[id])
        {
            continue;
        }

        new target = id;
        if (!is_user_alive(id))
        {
            new specMode = pev(id, pev_iuser1);
            if (specMode == 1 || specMode == 2 || specMode == 4)
            {
                new specTarget = pev(id, pev_iuser2);
                if (specTarget > 0 && is_user_connected(specTarget) && is_user_alive(specTarget))
                {
                    target = specTarget;
                }
                else
                {
                    continue;
                }
            }
            else
            {
                continue;
            }
        }

        new displayMs = 0;
        new speed = 0;
        new mode = g_playerMode[target];

        if (target == g_replayBot && g_botReplayTotalFrames > 0)
        {
            displayMs = floatround(float(g_botPlaybackFrame) * g_botPlaybackInterval * 1000.0);
            speed = GetReplayBotHorizontalSpeed();
            mode = g_botReplayMode;
        }
        else if (g_timerState[target] == TIMER_RUNNING)
        {
            g_currentTimeMs[target] = GetRunningTimeMs(target);
            displayMs = g_currentTimeMs[target];
            speed = GetPlayerHorizontalSpeed(target);
        }
        else if (g_timerState[target] == TIMER_FINISHED)
        {
            displayMs = g_lastTimeMs[target] > 0 ? g_lastTimeMs[target] : g_currentTimeMs[target];
            speed = GetPlayerHorizontalSpeed(target);
        }
        else
        {
            speed = GetPlayerHorizontalSpeed(target);
        }

        new timeText[32];
        FormatTimeMs(displayMs, timeText, charsmax(timeText));

        new modeName[32];
        GetModeName(mode, modeName, charsmax(modeName));

        if (get_pcvar_num(g_cvarSpeedometer))
        {
            set_hudmessage(80, 255, 80, -1.0, 0.82, 0, 0.0, get_pcvar_float(g_cvarHudUpdate) + 0.08, 0.0, 0.0, 4);
            show_hudmessage(id, "%d^n%s (%s)", speed, timeText, modeName);
        }
        else
        {
            set_hudmessage(80, 255, 80, -1.0, 0.85, 0, 0.0, get_pcvar_float(g_cvarHudUpdate) + 0.08, 0.0, 0.0, 4);
            show_hudmessage(id, "%s (%s)", timeText, modeName);
        }
    }
}

public TaskRenderZones()
{
    if (!get_pcvar_num(g_cvarEnabled) || !get_pcvar_num(g_cvarRender))
    {
        return;
    }

    RefreshZoneCaches();
}

public CmdPro15(id)
{
    new mode = g_playerMode[id];
    new modeName[32];
    GetModeName(mode, modeName, charsmax(modeName));

    new dataDir[128], filePath[192];
    get_datadir(dataDir, charsmax(dataDir));

    if (!dir_exists(dataDir))
    {
        mkdir(dataDir);
    }

    if (g_lastPro15File[id][0] && file_exists(g_lastPro15File[id]))
    {
        delete_file(g_lastPro15File[id]);
    }

    formatex(filePath, charsmax(filePath), "%s/bhop_pro15_%d_%d.html", dataDir, id, get_systime());
    copy(g_lastPro15File[id], charsmax(g_lastPro15File[]), filePath);

    new fp = fopen(filePath, "wt");
    if (!fp)
    {
        TimerChat(id, "Could not open MOTD temporary file.");
        return PLUGIN_HANDLED;
    }

    if (get_pcvar_num(g_cvarMotdWebEnabled))
    {
        new url[512], modeParam[16];
        GetModeUrlParam(mode, modeParam, charsmax(modeParam));

        new baseUrl[256];
        get_pcvar_string(g_cvarMotdWebUrl, baseUrl, charsmax(baseUrl));

        formatex(url, charsmax(url), "%s?map=%s&mode=%s", baseUrl, g_mapName, modeParam);
        fprintf(fp, "<html><head><meta http-equiv=^"refresh^" content=^"0;url=%s^"></head><body></body></html>", url);
        fclose(fp);
        show_motd(id, filePath, "Pro Records");
        return PLUGIN_HANDLED;
    }

    fprintf(fp, "<!DOCTYPE html><html><head><meta charset=^"utf-8^"><style>");
    fprintf(fp, "body{background:#4C5844;font:11px Tahoma;color:#EFF6EE;padding:10px;margin:0}");
    fprintf(fp, ".t{font-weight:bold;margin:0 0 8px;text-transform:uppercase}");
    fprintf(fp, ".p{background:#384030;border:1px solid #1C2118;padding:8px}");
    fprintf(fp, "table{width:100%%;border-collapse:collapse}");
    fprintf(fp, "th{background:#4C5844;border:1px solid #7C8E74;color:#EFF6EE;text-align:left;padding:4px}");
    fprintf(fp, "td{border-bottom:1px solid #2E3529;padding:4px;color:#FFF}.e{background:#333B2C}</style></head><body>");
    fprintf(fp, "<div class=^"t^">Pro Records - %s (%s)</div><div class=^"p^"><table><thead><tr><th width=15%%>Rank</th><th>Player Name</th><th width=30%%>Best Time</th></tr></thead><tbody>", modeName, g_mapName);

    new topLimit = get_pcvar_num(g_cvarTopLimit);
    if (topLimit < 1)
    {
        topLimit = 15;
    }

    new rank = 1;

    new count = LoadBestFile(mode);
    SortBestCache(count);

    new limit = topLimit;
    if (limit > count)
    {
        limit = count;
    }

    for (new i = 0; i < limit; i++)
    {
        new timeText[32], displayName[13];
        FormatTimeMs(g_fileTime[i], timeText, charsmax(timeText));
        copy(displayName, charsmax(displayName), g_fileName[i]);

        fprintf(fp, "<tr%s><td>#%d</td><td>%s</td><td>%s</td></tr>",
            (rank % 2 == 0) ? " class=e" : "", rank, displayName, timeText);
        rank++;
    }

    if (rank == 1)
    {
        fprintf(fp, "<tr><td colspan=3 align=center style=^"padding:20px^">No Pro records found.</td></tr>");
    }

    fprintf(fp, "</tbody></table></div></body></html>");
    fclose(fp);

    show_motd(id, filePath, "Pro Records");
    return PLUGIN_HANDLED;
}

public CmdRank(id)
{
    new mode = g_playerMode[id];
    if (g_bestTimeMs[id] <= 0)
    {
        new modeName[32];
        GetModeName(mode, modeName, charsmax(modeName));
        TimerChat(id, "No record in ^x03[%s]^x01 mode yet.", modeName);
        return PLUGIN_HANDLED;
    }

    new rank = GetRankForTime(g_bestTimeMs[id], mode);
    new total = GetRecordCount(mode);
    new bestText[32];
    FormatTimeMs(g_bestTimeMs[id], bestText, charsmax(bestText));

    new modeName[32];
    GetModeName(mode, modeName, charsmax(modeName));
    TimerChat(id, "^x03[%s]^x01 Map rank: ^x04#%d^x01 / ^x04%d^x01. Best: ^x04%s", modeName, rank, total, bestText);
    return PLUGIN_HANDLED;
}

public CmdBest(id)
{
    new mode = g_playerMode[id];
    if (g_bestTimeMs[id] <= 0)
    {
        new modeName[32];
        GetModeName(mode, modeName, charsmax(modeName));
        TimerChat(id, "No personal best in ^x03[%s]^x01 mode yet.", modeName);
        return PLUGIN_HANDLED;
    }

    new bestText[32];
    FormatTimeMs(g_bestTimeMs[id], bestText, charsmax(bestText));
    new modeName[32];
    GetModeName(mode, modeName, charsmax(modeName));
    TimerChat(id, "^x03[%s]^x01 Personal best: ^x04%s", modeName, bestText);
    return PLUGIN_HANDLED;
}

public CmdLast(id)
{
    new mode = g_playerMode[id];
    if (g_lastTimeMs[id] <= 0)
    {
        new modeName[32];
        GetModeName(mode, modeName, charsmax(modeName));
        TimerChat(id, "No finished run in ^x03[%s]^x01 mode yet.", modeName);
        return PLUGIN_HANDLED;
    }

    new lastText[32];
    FormatTimeMs(g_lastTimeMs[id], lastText, charsmax(lastText));
    new modeName[32];
    GetModeName(mode, modeName, charsmax(modeName));
    TimerChat(id, "^x03[%s]^x01 Last finished time: ^x04%s", modeName, lastText);
    return PLUGIN_HANDLED;
}

public CmdReset(id)
{
    ResetPlayerData(id, false);

    new Float:origin[3];
    pev(id, pev_origin, origin);

    if (g_zoneLoaded[ZONE_START] && IsPointInZone(origin, ZONE_START))
    {
        g_timerState[id] = TIMER_IN_START;
        g_prevInStart[id] = true;
    }

    new modeName[32];
    GetModeName(g_playerMode[id], modeName, charsmax(modeName));
    TimerChat(id, "^x03[%s]^x01 Timer Reset.", modeName);
    return PLUGIN_HANDLED;
}

public CmdStart(id)
{
    CmdCt(id);
    return PLUGIN_HANDLED;
}

public CmdHookOn(id)
{
    if (!get_pcvar_num(g_cvarHookEnabled) || !is_user_alive(id) || is_user_bot(id))
    {
        return PLUGIN_HANDLED;
    }

    if (g_duelState[id] != DUEL_STATE_IDLE)
    {
        TimerChat(id, "Hook is disabled during a duel.");
        return PLUGIN_HANDLED;
    }

    if (pev(id, pev_movetype) == MOVETYPE_NOCLIP)
    {
        return PLUGIN_HANDLED;
    }

    new Float:target[3];
    if (!FindHookTarget(id, target))
    {
        return PLUGIN_HANDLED;
    }

    g_hookActive[id] = true;
    g_hookTarget[id][0] = target[0];
    g_hookTarget[id][1] = target[1];
    g_hookTarget[id][2] = target[2];
    g_hookLastBeamTime[id] = 0.0;

    AbortTimerForHook(id);
    return PLUGIN_HANDLED;
}

public CmdHookOff(id)
{
    StopPlayerHook(id, true);
    return PLUGIN_HANDLED;
}

public CmdBhopStatus(id)
{
    RefreshZoneCaches();

    new storage[32];
    if (g_dbReady)
    {
        copy(storage, charsmax(storage), "MySQL + local queue");
    }
    else if (g_dbConfigured)
    {
        copy(storage, charsmax(storage), "local queue (MySQL offline)");
    }
    else
    {
        copy(storage, charsmax(storage), "local files");
    }

    TimerChat(id, "^x01Map: ^x03%s ^x01| Storage: ^x04%s ^x01| Start: %s ^x01| Finish: %s",
        g_mapName,
        storage,
        g_zoneLoaded[ZONE_START] ? "^x04OK" : "^x03missing",
        g_zoneLoaded[ZONE_FINISH] ? "^x04OK" : "^x03missing");

    return PLUGIN_HANDLED;
}

public CmdBlocked(id)
{
    if (get_pcvar_num(g_cvarBlockServerCommands))
    {
        TimerChat(id, "This command is disabled in bhop mode.");
        return PLUGIN_HANDLED;
    }

    return PLUGIN_CONTINUE;
}

public CmdBlockedTeam(id)
{
    if (get_pcvar_num(g_cvarBlockServerCommands))
    {
        QueueAutoJoinCt(id, 0.1);
        TimerChat(id, "Team selection is disabled. Everyone plays CT.");
        return PLUGIN_HANDLED;
    }

    return PLUGIN_CONTINUE;
}

public CmdJoinTeam(id)
{
    if (g_internalTeamCommand[id])
    {
        return PLUGIN_CONTINUE;
    }

    new teamArg[8];
    read_argv(1, teamArg, charsmax(teamArg));

    if (equal(teamArg, "2"))
    {
        return PLUGIN_CONTINUE;
    }

    if (get_pcvar_num(g_cvarBlockServerCommands))
    {
        QueueAutoJoinCt(id, 0.1);
        TimerChat(id, "Only CT team is allowed.");
        return PLUGIN_HANDLED;
    }

    return PLUGIN_CONTINUE;
}

public CmdJoinClass(id)
{
    if (g_internalTeamCommand[id])
    {
        return PLUGIN_CONTINUE;
    }

    if (get_pcvar_num(g_cvarBlockServerCommands))
    {
        QueueAutoJoinCt(id, 0.1);
        return PLUGIN_HANDLED;
    }

    return PLUGIN_CONTINUE;
}

public FwTouch(ent, id)
{
    if (!get_pcvar_num(g_cvarBlockWeaponPickup))
    {
        return FMRES_IGNORED;
    }

    if (!(1 <= id <= MAX_PLAYERS) || !is_user_alive(id) || !pev_valid(ent))
    {
        return FMRES_IGNORED;
    }

    new classname[32];
    pev(ent, pev_classname, classname, charsmax(classname));

    if (equal(classname, "weaponbox") ||
        equal(classname, "armoury_entity") ||
        equal(classname, "weapon_shield") ||
        contain(classname, "weapon_") == 0)
    {
        return FMRES_SUPERCEDE;
    }

    return FMRES_IGNORED;
}

public CmdBhopMenu(id)
{
    if (!HasZoneAccess(id))
    {
        TimerChat(id, "You do not have access to the zone editor.");
        return PLUGIN_HANDLED;
    }

    client_cmd(id, "zone");
    return PLUGIN_HANDLED;
}

public TaskShowStartMenu(taskid)
{
    new id = taskid - TASK_START_MENU;

    if (!(1 <= id <= MAX_PLAYERS) || !is_user_connected(id) || is_user_bot(id))
    {
        return;
    }

    if (!get_pcvar_num(g_cvarStartMenuOnJoin))
    {
        return;
    }

    if (!is_user_alive(id))
    {
        AutoJoinCt(id);
        if (g_spawnRetryCount[id] < MAX_SPAWN_RETRIES)
        {
            TimerSetTask(1.0, "TaskShowStartMenu", id + TASK_START_MENU);
        }
        return;
    }

    CmdMainMenu(id);
}

public TaskApplyModeFpsMax(taskid)
{
    new id = taskid - TASK_MODE_FPS_MAX;

    if (1 <= id <= MAX_PLAYERS && is_user_connected(id))
    {
        ApplyModeFpsMax(id);
    }
}

public TaskNormalFpsCheck()
{
    if (!get_pcvar_num(g_cvarEnabled))
    {
        return;
    }

    new limit = get_pcvar_num(g_cvarNormalFpsLimit);
    if (limit < 1)
    {
        limit = 135;
    }

    new bool:enforce = get_pcvar_num(g_cvarNormalFpsEnforce) ? true : false;
    new Float:now = get_gametime();

    for (new id = 1; id <= MAX_PLAYERS; id++)
    {
        if (!is_user_connected(id) || is_user_bot(id))
        {
            g_modeFpsFrames[id] = 0;
            g_modeFpsValue[id] = 0;
            continue;
        }

        g_modeFpsValue[id] = g_modeFpsFrames[id];
        g_modeFpsFrames[id] = 0;

        if (!enforce || g_playerMode[id] != MODE_NORMAL || !is_user_alive(id))
        {
            continue;
        }

        if (now - g_lastModeFpsMaxApply[id] >= 5.0)
        {
            ApplyModeFpsMax(id);
        }

        if (g_modeFpsValue[id] > limit)
        {
            ApplyModeFpsMax(id);
            TeleportToStart(id, false);

            if (now - g_lastNormalFpsWarn[id] >= 3.0)
            {
                TimerChat(id, "Normal mode FPS limit is ^x04%d^x01. Your FPS: ^x03%d^x01. Teleported to start.", limit, g_modeFpsValue[id]);
                g_lastNormalFpsWarn[id] = now;
            }
        }
    }
}

stock ApplyModeFpsMax(id)
{
    if (!is_user_connected(id) || is_user_bot(id))
    {
        return;
    }

    if (g_playerMode[id] == MODE_NORMAL)
    {
        new normalMax = get_pcvar_num(g_cvarNormalFpsMax);
        if (normalMax < 20)
        {
            normalMax = 131;
        }
        client_cmd(id, "fps_max %d", normalMax);
    }
    else
    {
        new otherMax = get_pcvar_num(g_cvarOtherModesFpsMax);
        if (otherMax < 20)
        {
            otherMax = 1000;
        }
        client_cmd(id, "fps_max %d", otherMax);
    }

    g_lastModeFpsMaxApply[id] = get_gametime();
}

public CmdMainMenu(id)
{
    if (!is_user_connected(id))
    {
        return PLUGIN_HANDLED;
    }

    new menu = menu_create("ESKIDOSTLAR BHOP Main Menu", "MainMenuHandler");

    menu_additem(menu, "Teleport to Start");
    menu_additem(menu, "Top15 / Pro15");
    menu_additem(menu, "FPS / Client Settings");
    menu_additem(menu, "Mode Selection");
    menu_additem(menu, "WR Replay Bot");
    menu_additem(menu, "Duel Menu");
    menu_additem(menu, "Help / Commands");

    menu_setprop(menu, MPROP_EXIT, MEXIT_ALL);
    menu_display(id, menu, 0);

    return PLUGIN_HANDLED;
}

public MainMenuHandler(id, menu, item)
{
    if (item == MENU_EXIT)
    {
        menu_destroy(menu);
        return PLUGIN_HANDLED;
    }

    if (!is_user_connected(id))
    {
        menu_destroy(menu);
        return PLUGIN_HANDLED;
    }

    switch (item)
    {
        case 0: CmdStart(id);
        case 1: CmdPro15(id);
        case 2: CmdFpsMenu(id);
        case 3: CmdBhopModeMenu(id);
        case 4: CmdBhopReplayMenu(id);
        case 5: CmdDuel(id);
        case 6: CmdHelp(id);
    }

    menu_destroy(menu);
    return PLUGIN_HANDLED;
}

public CmdHelp(id)
{
    new dataDir[128], filePath[192];
    get_datadir(dataDir, charsmax(dataDir));

    if (!dir_exists(dataDir))
    {
        mkdir(dataDir);
    }

    formatex(filePath, charsmax(filePath), "%s/bhop_help.html", dataDir);

    new fp = fopen(filePath, "wt");
    if (fp)
    {
        fprintf(fp, "<!DOCTYPE html><html><head><meta charset=^"utf-8^"><style>");
        fprintf(fp, "body{background:#4C5844;font:11px Tahoma;color:#EFF6EE;padding:10px;margin:0}");
        fprintf(fp, ".t{font-weight:bold;margin:0 0 8px;text-transform:uppercase}");
        fprintf(fp, ".p{background:#384030;border:1px solid #1C2118;padding:8px}");
        fprintf(fp, "table{width:100%%;border-collapse:collapse}");
        fprintf(fp, "th{background:#4C5844;border:1px solid #7C8E74;color:#EFF6EE;text-align:left;padding:4px}");
        fprintf(fp, "td{border-bottom:1px solid #2E3529;padding:4px;color:#FFF}.e{background:#333B2C}</style></head><body>");
        fprintf(fp, "<div class=^"t^">Help</div><div class=^"p^"><table><thead><tr><th width=35%%>Command</th><th>Description</th></tr></thead><tbody>");
        
        fprintf(fp, "<tr><td>/menu</td><td>Open the main player menu</td></tr>");
        fprintf(fp, "<tr><td>/start, /respawn</td><td>Teleport to start zone</td></tr>");
        fprintf(fp, "<tr class=e><td>/reset</td><td>Reset timer and teleport to start</td></tr>");
        fprintf(fp, "<tr><td>/pro15, /top15</td><td>Show top 15 records on this map</td></tr>");
        fprintf(fp, "<tr class=e><td>/rank</td><td>Show your current rank and best time</td></tr>");
        fprintf(fp, "<tr><td>/best</td><td>Show your personal best time</td></tr>");
        fprintf(fp, "<tr class=e><td>/last</td><td>Show your last finished run time</td></tr>");
        fprintf(fp, "<tr><td>/fps</td><td>Open FPS and client visibility settings</td></tr>");
        fprintf(fp, "<tr class=e><td>/mode, /mod</td><td>Open mode selection menu</td></tr>");
        fprintf(fp, "<tr><td>/spec</td><td>Spectate the WR Replay Bot</td></tr>");
        fprintf(fp, "<tr class=e><td>/ct</td><td>Return to CT play mode</td></tr>");
        fprintf(fp, "<tr><td>/replay</td><td>Change WR Replay Bot mode</td></tr>");
        fprintf(fp, "<tr class=e><td>/bhopstatus</td><td>Check database and configurations</td></tr>");
        fprintf(fp, "<tr><td>/bhopmenu</td><td>Open zone editor (Admin)</td></tr>");
        
        fprintf(fp, "</tbody></table></div></body></html>");
        fclose(fp);
    }

    show_motd(id, filePath, "Help");
    return PLUGIN_HANDLED;
}

public ConCmdStartA(id, level, cid)
{
    if (!cmd_access(id, level, cid, 1))
    {
        return PLUGIN_HANDLED;
    }

    SetEditPoint(id, ZONE_START, 0);
    return PLUGIN_HANDLED;
}

public ConCmdStartB(id, level, cid)
{
    if (!cmd_access(id, level, cid, 1))
    {
        return PLUGIN_HANDLED;
    }

    SetEditPoint(id, ZONE_START, 1);
    return PLUGIN_HANDLED;
}

public ConCmdFinishA(id, level, cid)
{
    if (!cmd_access(id, level, cid, 1))
    {
        return PLUGIN_HANDLED;
    }

    SetEditPoint(id, ZONE_FINISH, 0);
    return PLUGIN_HANDLED;
}

public ConCmdFinishB(id, level, cid)
{
    if (!cmd_access(id, level, cid, 1))
    {
        return PLUGIN_HANDLED;
    }

    SetEditPoint(id, ZONE_FINISH, 1);
    return PLUGIN_HANDLED;
}

public ConCmdSave(id, level, cid)
{
    if (!cmd_access(id, level, cid, 1))
    {
        return PLUGIN_HANDLED;
    }

    SaveEditedZones(id);
    return PLUGIN_HANDLED;
}

public ConCmdReload(id, level, cid)
{
    if (!cmd_access(id, level, cid, 1))
    {
        return PLUGIN_HANDLED;
    }

    g_zoneSyncBlocked = true;
    sr_zone_reload();
    g_zoneSyncBlocked = false;
    LoadZones();
    TimerChat(id, "^x01Zones reloaded for ^x03%s", g_mapName);
    return PLUGIN_HANDLED;
}

public ConCmdDeleteStart(id, level, cid)
{
    if (!cmd_access(id, level, cid, 1))
    {
        return PLUGIN_HANDLED;
    }

    DeleteZone(id, ZONE_START);
    return PLUGIN_HANDLED;
}

public ConCmdDeleteFinish(id, level, cid)
{
    if (!cmd_access(id, level, cid, 1))
    {
        return PLUGIN_HANDLED;
    }

    DeleteZone(id, ZONE_FINISH);
    return PLUGIN_HANDLED;
}

public BhopMenuHandler(id, menu, item)
{
    if (item == MENU_EXIT)
    {
        menu_destroy(menu);
        return PLUGIN_HANDLED;
    }

    if (!HasZoneAccess(id))
    {
        menu_destroy(menu);
        return PLUGIN_HANDLED;
    }

    switch (item)
    {
        case 0: SetEditPoint(id, ZONE_START, 0);
        case 1: SetEditPoint(id, ZONE_START, 1);
        case 2: SetEditPoint(id, ZONE_FINISH, 0);
        case 3: SetEditPoint(id, ZONE_FINISH, 1);
        case 4:
        {
            TaskRenderZones();
            TimerChat(id, "^x01Zone preview refreshed.");
        }
        case 5: SaveEditedZones(id);
        case 6:
        {
            LoadZones();
            TimerChat(id, "^x01Zones reloaded for ^x03%s", g_mapName);
        }
        case 7:
        {
            DeleteZone(id, ZONE_START);
            DeleteZone(id, ZONE_FINISH);
        }
    }

    menu_destroy(menu);

    if (is_user_connected(id))
    {
        ShowBhopMenu(id);
    }

    return PLUGIN_HANDLED;
}



stock ShowBhopMenu(id)
{
    new menu = menu_create("Bhop Timer Zone Editor", "BhopMenuHandler");
    new itemText[96];

    formatex(itemText, charsmax(itemText), "Set Start Zone Point A %s", g_editHasPoint[id][GetEditPointSlot(ZONE_START, 0)] ? "\y[Set]" : "");
    menu_additem(menu, itemText);

    formatex(itemText, charsmax(itemText), "Set Start Zone Point B %s", g_editHasPoint[id][GetEditPointSlot(ZONE_START, 1)] ? "\y[Set]" : "");
    menu_additem(menu, itemText);

    formatex(itemText, charsmax(itemText), "Set Finish Zone Point A %s", g_editHasPoint[id][GetEditPointSlot(ZONE_FINISH, 0)] ? "\y[Set]" : "");
    menu_additem(menu, itemText);

    formatex(itemText, charsmax(itemText), "Set Finish Zone Point B %s", g_editHasPoint[id][GetEditPointSlot(ZONE_FINISH, 1)] ? "\y[Set]" : "");
    menu_additem(menu, itemText);

    menu_additem(menu, "Preview Zones");
    menu_additem(menu, "Save Edited Zones");
    menu_additem(menu, "Reload Map Zones");
    menu_additem(menu, "Delete Map Zones");

    menu_setprop(menu, MPROP_EXIT, MEXIT_ALL);
    menu_display(id, menu, 0);
}

stock SetEditPoint(id, zoneIndex, point)
{
    if (!id || !is_user_alive(id))
    {
        if (id)
        {
        TimerChat(id, "You must be alive to set a zone point.");
        }
        else
        {
            console_print(id, "[TIMER] You must be alive in-game to set a zone point.");
        }
        return;
    }

    new slot = GetEditPointSlot(zoneIndex, point);
    pev(id, pev_origin, g_editPoint[id][slot]);
    g_editHasPoint[id][slot] = true;

    TimerChat(id, "^x03%s^x01 zone point ^x04%c^x01 set.", g_zoneLabels[zoneIndex], point == 0 ? 'A' : 'B');

    if (HasEditZone(id, zoneIndex))
    {
        ApplyEditedZone(id, zoneIndex);
        RenderZone(zoneIndex);
        TimerChat(id, "%s zone preview active. Save it to keep it after map change.", g_zoneLabels[zoneIndex]);
    }
}

stock SaveEditedZones(id)
{
    new saved;

    if (HasEditZone(id, ZONE_START))
    {
        ApplyEditedZone(id, ZONE_START);
        sr_zone_upsert_aabb(g_zoneClasses[ZONE_START], g_zoneNames[ZONE_START], g_zoneMin[ZONE_START], g_zoneMax[ZONE_START], true);
        saved++;
    }

    if (HasEditZone(id, ZONE_FINISH))
    {
        ApplyEditedZone(id, ZONE_FINISH);
        sr_zone_upsert_aabb(g_zoneClasses[ZONE_FINISH], g_zoneNames[ZONE_FINISH], g_zoneMin[ZONE_FINISH], g_zoneMax[ZONE_FINISH], true);
        saved++;
    }

    if (!saved)
    {
        SaveZonesFromFramework(id);
        g_zoneSyncBlocked = true;
        sr_zone_save();
        g_zoneSyncBlocked = false;
        TimerChat(id, "Polygon zones saved for ^x03%s", g_mapName);
        return;
    }

    RefreshZoneCaches();
    SaveZonesFromFramework(id);
    g_zoneSyncBlocked = true;
    sr_zone_save();
    g_zoneSyncBlocked = false;
    TimerChat(id, "^x04%d^x01 zone saved for ^x03%s", saved, g_mapName);
}

stock ApplyEditedZone(id, zoneIndex)
{
    new Float:mins[3], Float:maxs[3];
    BuildBoxFromPoints(g_editPoint[id][GetEditPointSlot(zoneIndex, 0)], g_editPoint[id][GetEditPointSlot(zoneIndex, 1)], mins, maxs);

    for (new i = 0; i < 3; i++)
    {
        g_zoneMin[zoneIndex][i] = mins[i];
        g_zoneMax[zoneIndex][i] = maxs[i];
    }

    g_zoneLoaded[zoneIndex] = true;
}

stock SaveZone(id, zoneIndex)
{
    if (!g_dbConfigured)
    {
        return;
    }

    RefreshZoneCache(zoneIndex);
    if (!g_zoneLoaded[zoneIndex])
    {
        return;
    }

    new mapSql[MAX_MAP_SQL], auth[35], authSql[MAX_AUTH_SQL], shapeType[16];
    static query[6144], shapeJson[MAX_ZONE_SHAPE_JSON], shapeSql[MAX_ZONE_SHAPE_SQL];
    MysqlEscape(g_mapName, mapSql, charsmax(mapSql));

    if (id > 0 && is_user_connected(id))
    {
        get_user_authid(id, auth, charsmax(auth));
    }
    else
    {
        copy(auth, charsmax(auth), "SERVER");
    }

    MysqlEscape(auth, authSql, charsmax(authSql));

    if (sr_zone_get_shape_json_by_class(g_zoneClasses[zoneIndex], shapeJson, charsmax(shapeJson)))
    {
        MysqlEscape(shapeJson, shapeSql, charsmax(shapeSql));
        if (contain(shapeJson, "^"polygon^":true") != -1)
        {
            copy(shapeType, charsmax(shapeType), "polygon");
        }
        else
        {
            copy(shapeType, charsmax(shapeType), "aabb");
        }
    }
    else
    {
        shapeSql[0] = '^0';
        copy(shapeType, charsmax(shapeType), "aabb");
    }

    formatex(query, charsmax(query),
        "INSERT INTO bhop_zones (map,zone_type,min_x,min_y,min_z,max_x,max_y,max_z,shape_type,shape_json,updated_at,updated_by) VALUES ('%s','%s',%.3f,%.3f,%.3f,%.3f,%.3f,%.3f,'%s','%s',%d,'%s') ON DUPLICATE KEY UPDATE min_x=VALUES(min_x),min_y=VALUES(min_y),min_z=VALUES(min_z),max_x=VALUES(max_x),max_y=VALUES(max_y),max_z=VALUES(max_z),shape_type=VALUES(shape_type),shape_json=VALUES(shape_json),updated_at=VALUES(updated_at),updated_by=VALUES(updated_by);",
        mapSql, g_zoneNames[zoneIndex],
        g_zoneMin[zoneIndex][0], g_zoneMin[zoneIndex][1], g_zoneMin[zoneIndex][2],
        g_zoneMax[zoneIndex][0], g_zoneMax[zoneIndex][1], g_zoneMax[zoneIndex][2],
        shapeType, shapeSql, get_systime(), authSql);

    QueueSql(query);
}

stock DeleteZone(id, zoneIndex)
{
    if (g_dbConfigured)
    {
        new mapSql[MAX_MAP_SQL], query[256];
        MysqlEscape(g_mapName, mapSql, charsmax(mapSql));

        formatex(query, charsmax(query), "DELETE FROM bhop_zones WHERE map='%s' AND zone_type='%s';", mapSql, g_zoneNames[zoneIndex]);
        QueueSql(query);
    }

    sr_zone_delete_by_class(g_zoneClasses[zoneIndex]);
    g_zoneLoaded[zoneIndex] = false;
    g_zoneSyncBlocked = true;
    sr_zone_save();
    g_zoneSyncBlocked = false;
    SaveZonesFile();

    // Clear player's temporary edit points for this zone to avoid using stale coordinates as a reference
    if (1 <= id <= MAX_PLAYERS)
    {
        new slotA = GetEditPointSlot(zoneIndex, 0);
        new slotB = GetEditPointSlot(zoneIndex, 1);

        g_editHasPoint[id][slotA] = false;
        g_editHasPoint[id][slotB] = false;

        g_editPoint[id][slotA][0] = 0.0;
        g_editPoint[id][slotA][1] = 0.0;
        g_editPoint[id][slotA][2] = 0.0;

        g_editPoint[id][slotB][0] = 0.0;
        g_editPoint[id][slotB][1] = 0.0;
        g_editPoint[id][slotB][2] = 0.0;
    }

    TimerChat(id, "^x03%s^x01 zone deleted for ^x03%s", g_zoneLabels[zoneIndex], g_mapName);
}

stock BuildBoxFromPoints(const Float:a[3], const Float:b[3], Float:mins[3], Float:maxs[3])
{
    for (new i = 0; i < 3; i++)
    {
        if (a[i] < b[i])
        {
            mins[i] = a[i];
            maxs[i] = b[i];
        }
        else
        {
            mins[i] = b[i];
            maxs[i] = a[i];
        }
    }

    if ((maxs[2] - mins[2]) < 16.0)
    {
        new Float:baseZ = mins[2] + get_pcvar_float(g_cvarZoneFloorOffset);
        new Float:topZ = mins[2] + get_pcvar_float(g_cvarZoneZPadding);
        mins[2] = baseZ;
        maxs[2] = topZ;
    }
}

stock DbInitialize()
{
    if (g_dbTried)
    {
        return;
    }
    g_dbTried = true;

    if (!get_pcvar_num(g_cvarSqlEnabled))
    {
        log_amx("[TIMER] Remote MySQL is disabled; using local files.");
        return;
    }

    g_dbConfigured = true;
    MigrateLegacyStorage();

    if (!SQL_SetAffinity("mysql"))
    {
        log_amx("[TIMER] MySQL SQLx driver is unavailable. Pending data will remain local.");
        return;
    }

    new host[128], user[64], pass[96], database[64];
    get_pcvar_string(g_cvarSqlHost, host, charsmax(host));
    get_pcvar_string(g_cvarSqlUser, user, charsmax(user));
    get_pcvar_string(g_cvarSqlPass, pass, charsmax(pass));
    get_pcvar_string(g_cvarSqlDb, database, charsmax(database));

    if (!host[0] || !user[0] || !database[0])
    {
        log_amx("[TIMER] MySQL configuration is incomplete. Check bhop_sql_host/user/db.");
        return;
    }

    new timeout = clamp(get_pcvar_num(g_cvarSqlTimeout), 2, 30);
    g_sqlTuple = SQL_MakeDbTuple(host, user, pass, database, timeout);
#if AMXX_VERSION_NUM >= 183
    SQL_SetCharset(g_sqlTuple, "utf8");
#endif
    DbStartSchemaSetup();
}

stock DbStartSchemaSetup()
{
    if (!g_dbConfigured || g_sqlTuple == Empty_Handle || g_dbInitInFlight)
    {
        return;
    }

    if (g_dbSchemaStep < 0 || g_dbSchemaStep > 4)
    {
        g_dbSchemaStep = 0;
    }

    g_dbInitInFlight = true;
    new query[1024], data[1];
    switch (g_dbSchemaStep)
    {
        case 0: copy(query, charsmax(query), "CREATE TABLE IF NOT EXISTS bhop_zones (map VARCHAR(64) NOT NULL,zone_type VARCHAR(16) NOT NULL,min_x FLOAT NOT NULL,min_y FLOAT NOT NULL,min_z FLOAT NOT NULL,max_x FLOAT NOT NULL,max_y FLOAT NOT NULL,max_z FLOAT NOT NULL,shape_type VARCHAR(16) NOT NULL DEFAULT 'aabb',shape_json MEDIUMTEXT NULL,updated_at INT UNSIGNED NOT NULL,updated_by VARCHAR(35) NOT NULL,PRIMARY KEY (map,zone_type)) ENGINE=InnoDB DEFAULT CHARSET=utf8;");
        case 1: copy(query, charsmax(query), "ALTER TABLE bhop_zones ADD COLUMN shape_type VARCHAR(16) NOT NULL DEFAULT 'aabb' AFTER max_z;");
        case 2: copy(query, charsmax(query), "ALTER TABLE bhop_zones ADD COLUMN shape_json MEDIUMTEXT NULL AFTER shape_type;");
        case 3: copy(query, charsmax(query), "CREATE TABLE IF NOT EXISTS bhop_records (id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,record_key VARCHAR(160) NOT NULL,map VARCHAR(64) NOT NULL,authid VARCHAR(35) NOT NULL,name VARCHAR(32) NOT NULL,time_ms INT UNSIGNED NOT NULL,created_at INT UNSIGNED NOT NULL,PRIMARY KEY (id),UNIQUE KEY uq_bhop_records_key (record_key),KEY idx_bhop_records_map_time (map,time_ms)) ENGINE=InnoDB DEFAULT CHARSET=utf8;");
        case 4: copy(query, charsmax(query), "CREATE TABLE IF NOT EXISTS bhop_best (map VARCHAR(64) NOT NULL,authid VARCHAR(35) NOT NULL,name VARCHAR(32) NOT NULL,best_time_ms INT UNSIGNED NOT NULL,updated_at INT UNSIGNED NOT NULL,PRIMARY KEY (map,authid),KEY idx_bhop_best_map_time (map,best_time_ms)) ENGINE=InnoDB DEFAULT CHARSET=utf8;");
    }
    data[0] = g_dbSchemaStep;
    SQL_ThreadQuery(g_sqlTuple, "DbSchemaHandler", query, data, sizeof(data));
}

public DbSchemaHandler(failstate, Handle:query, error[], errnum, data[], size, Float:queueTime)
{
    g_dbInitInFlight = false;

    if (failstate != TQUERY_SUCCESS)
    {
        if ((data[0] == 1 || data[0] == 2) && errnum == 1060)
        {
            g_dbSchemaStep = data[0] + 1;
            DbStartSchemaSetup();
            return;
        }

        g_dbReady = false;
        log_amx("[TIMER] MySQL setup failed (%d): %s", errnum, error);
        return;
    }

    if (data[0] < 4)
    {
        g_dbSchemaStep = data[0] + 1;
        DbStartSchemaSetup();
        return;
    }

    g_dbSchemaStep = 5;
    g_dbReady = true;
    log_amx("[TIMER] Remote MySQL is ready. Flushing pending records.");
    DbLoadRemoteCaches();
    ScheduleDbFlush(DB_FLUSH_DELAY);
}

public TaskDbRetry()
{
    if (!g_dbConfigured)
    {
        return;
    }

    if (!g_dbReady)
    {
        DbStartSchemaSetup();
        return;
    }

    ScheduleDbFlush(DB_FLUSH_DELAY);
}

public ConCmdDbRetry(id, level, cid)
{
    if (!cmd_access(id, level, cid, 1))
    {
        return PLUGIN_HANDLED;
    }

    if (!g_dbConfigured)
    {
        console_print(id, "[TIMER] MySQL is disabled in bhop_timer.cfg.");
        return PLUGIN_HANDLED;
    }

    g_dbReady = false;
    DbStartSchemaSetup();
    console_print(id, "[TIMER] MySQL retry requested.");
    return PLUGIN_HANDLED;
}

public ConCmdResetTop15(id, level, cid)
{
    if (!cmd_access(id, level, cid, 1))
    {
        return PLUGIN_HANDLED;
    }

    new argument[24];
    read_argv(1, argument, charsmax(argument));
    trim(argument);

    new firstMode, lastMode;
    if (equali(argument, "normal"))
    {
        firstMode = MODE_NORMAL;
        lastMode = MODE_NORMAL;
    }
    else if (equali(argument, "lowgrav") || equali(argument, "lg"))
    {
        firstMode = MODE_LOW_GRAVITY;
        lastMode = MODE_LOW_GRAVITY;
    }
    else if (equali(argument, "dbjump") || equali(argument, "dj"))
    {
        firstMode = MODE_DOUBLE_JUMP;
        lastMode = MODE_DOUBLE_JUMP;
    }
    else if (equali(argument, "all"))
    {
        firstMode = MODE_NORMAL;
        lastMode = MODE_DOUBLE_JUMP;
    }
    else
    {
        console_print(id, "[TIMER] Usage: amx_bhop_reset_top15 <normal|lowgrav|dbjump|all>");
        return PLUGIN_HANDLED;
    }

    for (new mode = firstMode; mode <= lastMode; mode++)
    {
        ResetTop15Mode(mode);
    }

    UpdateWrHolders();

    new adminName[32], adminAuth[35], modeName[32];
    if (id > 0 && is_user_connected(id))
    {
        get_user_name(id, adminName, charsmax(adminName));
        get_user_authid(id, adminAuth, charsmax(adminAuth));
    }
    else
    {
        copy(adminName, charsmax(adminName), "SERVER");
        copy(adminAuth, charsmax(adminAuth), "SERVER");
    }

    if (firstMode == MODE_NORMAL && lastMode == MODE_DOUBLE_JUMP)
    {
        copy(modeName, charsmax(modeName), "All Modes");
    }
    else
    {
        GetModeName(firstMode, modeName, charsmax(modeName));
    }

    log_amx("[TIMER] %s <%s> reset Top15 for %s [%s].", adminName, adminAuth, g_mapName, modeName);
    console_print(id, "[TIMER] Top15 reset for %s [%s]. MySQL cleanup is queued if remote storage is enabled.", g_mapName, modeName);
    TimerChat(0, "^x04%s^x01 reset Top15 for ^x03%s^x01 [^x04%s^x01].", adminName, g_mapName, modeName);
    return PLUGIN_HANDLED;
}

stock ResetTop15Mode(mode)
{
    g_bestCacheGeneration[mode]++;

    new path[192];
    BuildMapDataPath(path, charsmax(path), "best", mode);
    if (file_exists(path))
    {
        delete_file(path);
    }

    BuildMapDataPath(path, charsmax(path), "records", mode);
    if (file_exists(path))
    {
        delete_file(path);
    }

    BuildReplayPath(mode, path, charsmax(path));
    if (file_exists(path))
    {
        delete_file(path);
    }

    for (new player = 1; player <= MAX_PLAYERS; player++)
    {
        if (is_user_connected(player) && g_playerMode[player] == mode)
        {
            g_bestTimeMs[player] = 0;
        }
    }

    if (g_dbConfigured)
    {
        new modeMapName[64], mapSql[MAX_MAP_SQL], query[384];
        GetMapNameForMode(mode, modeMapName, charsmax(modeMapName));
        MysqlEscape(modeMapName, mapSql, charsmax(mapSql));

        formatex(query, charsmax(query), "DELETE FROM bhop_records WHERE map='%s';", mapSql);
        QueueSql(query);
        formatex(query, charsmax(query), "DELETE FROM bhop_best WHERE map='%s';", mapSql);
        QueueSql(query);
    }

    if (g_botReplayMode == mode)
    {
        LoadReplayFile(mode);
        MaintainReplayBot();
    }
}

stock BuildDbDataPath(output[], len, const fileName[])
{
    new dataDir[128];
    get_datadir(dataDir, charsmax(dataDir));
    formatex(output, len, "%s/%s", dataDir, fileName);
}

stock QueueSql(const query[])
{
    if (!g_dbConfigured || !query[0])
    {
        return;
    }

    new path[192];
    BuildDbDataPath(path, charsmax(path), "bhop_timer_mysql_queue.ini");
    write_file(path, query);

    if (g_dbReady)
    {
        ScheduleDbFlush(DB_FLUSH_DELAY);
    }
}

stock ScheduleDbFlush(Float:delay)
{
    if (!g_dbReady || g_sqlTuple == Empty_Handle)
    {
        return;
    }

    remove_task(TASK_DB_FLUSH);
    TimerSetTask(delay, "TaskFlushDbQueue", TASK_DB_FLUSH);
}

stock DbFlushQueue()
{
    if (!g_dbReady || g_sqlTuple == Empty_Handle || g_dbQueueInFlight)
    {
        return;
    }

    new path[192];
    BuildDbDataPath(path, charsmax(path), "bhop_timer_mysql_queue.ini");
    if (!file_exists(path))
    {
        return;
    }

    new lineCount = file_size(path, 1);
    if (g_dbQueueScanLine >= lineCount)
    {
        delete_file(path);
        g_dbQueueScanLine = 0;
        DbLoadRemoteCaches();
        return;
    }

    static query[8192];
    new textLength;
    g_dbQueueLine = -1;

    for (new line = g_dbQueueScanLine; line < lineCount; line++)
    {
        if (read_file(path, line, query, charsmax(query), textLength) && textLength > 0)
        {
            trim(query);
            if (query[0])
            {
                g_dbQueueLine = line;
                g_dbQueueScanLine = line;
                break;
            }
        }
    }

    if (g_dbQueueLine == -1)
    {
        delete_file(path);
        g_dbQueueScanLine = 0;
        DbLoadRemoteCaches();
        return;
    }

    new data[1];
    data[0] = g_dbQueueLine;
    g_dbQueueInFlight = true;
    SQL_ThreadQuery(g_sqlTuple, "DbQueueHandler", query, data, sizeof(data));
}

public DbQueueHandler(failstate, Handle:query, error[], errnum, data[], size, Float:queueTime)
{
    g_dbQueueInFlight = false;

    if (failstate != TQUERY_SUCCESS)
    {
        if (failstate == TQUERY_CONNECT_FAILED)
        {
            g_dbReady = false;
        }
        log_amx("[TIMER] Pending MySQL write failed (%d): %s", errnum, error);
        return;
    }

    new path[192];
    BuildDbDataPath(path, charsmax(path), "bhop_timer_mysql_queue.ini");
    write_file(path, "", data[0]);
    if (g_dbQueueScanLine <= data[0])
    {
        g_dbQueueScanLine = data[0] + 1;
    }
    ScheduleDbFlush(DB_FLUSH_DELAY);
}

public TaskFlushDbQueue(taskid)
{
    #pragma unused taskid
    DbFlushQueue();
}

stock DbLoadRemoteCaches()
{
    DbRequestZones();
    for (new mode = MODE_NORMAL; mode <= MODE_DOUBLE_JUMP; mode++)
    {
        DbRequestBest(mode);
    }
}

stock DbRequestZones()
{
    if (!g_dbReady)
    {
        return;
    }

    new mapSql[MAX_MAP_SQL], query[512];
    MysqlEscape(g_mapName, mapSql, charsmax(mapSql));
    formatex(query, charsmax(query), "SELECT zone_type,min_x,min_y,min_z,max_x,max_y,max_z,shape_type,shape_json FROM bhop_zones WHERE map='%s';", mapSql);
    SQL_ThreadQuery(g_sqlTuple, "DbZonesHandler", query);
}

public DbZonesHandler(failstate, Handle:query, error[], errnum, data[], size, Float:queueTime)
{
    if (failstate != TQUERY_SUCCESS)
    {
        if (failstate == TQUERY_CONNECT_FAILED)
        {
            g_dbReady = false;
        }
        log_amx("[TIMER] Could not load remote zones (%d): %s", errnum, error);
        return;
    }

    new loaded;
    static shapeJson[MAX_ZONE_SHAPE_JSON];
    while (SQL_MoreResults(query))
    {
        new zoneType[16], zoneIndex = -1;
        shapeJson[0] = '^0';
        SQL_ReadResult(query, 0, zoneType, charsmax(zoneType));
        if (equal(zoneType, "start")) zoneIndex = ZONE_START;
        else if (equal(zoneType, "finish")) zoneIndex = ZONE_FINISH;

        if (zoneIndex != -1)
        {
            new Float:mins[3], Float:maxs[3];
            SQL_ReadResult(query, 1, mins[0]);
            SQL_ReadResult(query, 2, mins[1]);
            SQL_ReadResult(query, 3, mins[2]);
            SQL_ReadResult(query, 4, maxs[0]);
            SQL_ReadResult(query, 5, maxs[1]);
            SQL_ReadResult(query, 6, maxs[2]);
            SQL_ReadResult(query, 8, shapeJson, charsmax(shapeJson));

            if (shapeJson[0] && !sr_zone_upsert_shape_json(g_zoneClasses[zoneIndex], g_zoneNames[zoneIndex], shapeJson))
            {
                log_amx("[TIMER] Remote polygon zone for %s could not be parsed; falling back to min/max.", g_zoneNames[zoneIndex]);
                sr_zone_upsert_aabb(g_zoneClasses[zoneIndex], g_zoneNames[zoneIndex], mins, maxs, true);
            }
            else if (!shapeJson[0])
            {
                sr_zone_upsert_aabb(g_zoneClasses[zoneIndex], g_zoneNames[zoneIndex], mins, maxs, true);
            }

            if (RefreshZoneCache(zoneIndex))
            {
                loaded++;
            }
        }
        SQL_NextRow(query);
    }

    if (loaded)
    {
        g_zoneSyncBlocked = true;
        sr_zone_save();
        g_zoneSyncBlocked = false;
        SaveZonesFile();
    }
}

stock DbRequestBest(mode)
{
    if (!g_dbReady)
    {
        return;
    }

    new modeMapName[64], mapSql[MAX_MAP_SQL], query[512], data[2];
    GetMapNameForMode(mode, modeMapName, charsmax(modeMapName));
    MysqlEscape(modeMapName, mapSql, charsmax(mapSql));
    formatex(query, charsmax(query), "SELECT authid,name,best_time_ms FROM bhop_best WHERE map='%s' ORDER BY best_time_ms ASC LIMIT %d;", mapSql, MAX_FILE_RECORDS);
    data[0] = mode;
    data[1] = g_bestCacheGeneration[mode];
    SQL_ThreadQuery(g_sqlTuple, "DbBestHandler", query, data, sizeof(data));
}

public DbBestHandler(failstate, Handle:query, error[], errnum, data[], size, Float:queueTime)
{
    if (failstate != TQUERY_SUCCESS)
    {
        if (failstate == TQUERY_CONNECT_FAILED)
        {
            g_dbReady = false;
        }
        log_amx("[TIMER] Could not load remote best records (%d): %s", errnum, error);
        return;
    }

    new mode = data[0];
    if (size < 2 || mode < MODE_NORMAL || mode > MODE_DOUBLE_JUMP || data[1] != g_bestCacheGeneration[mode])
    {
        return;
    }

    new count = LoadBestFile(mode);
    while (SQL_MoreResults(query))
    {
        new auth[35], name[32], timeMs;
        SQL_ReadResult(query, 0, auth, charsmax(auth));
        SQL_ReadResult(query, 1, name, charsmax(name));
        timeMs = SQL_ReadResult(query, 2);
        SanitizeFileToken(name, charsmax(name));
        MergeBestCacheRow(count, auth, name, timeMs);
        SQL_NextRow(query);
    }

    SortBestCache(count);
    SaveBestFile(count, mode);

    for (new id = 1; id <= MAX_PLAYERS; id++)
    {
        if (is_user_connected(id) && g_playerMode[id] == mode)
        {
            LoadPlayerBest(id);
        }
    }
    UpdateWrHolders();
}

stock MergeBestCacheRow(&count, const auth[], const name[], timeMs)
{
    if (!auth[0] || timeMs <= 0)
    {
        return;
    }

    new found = -1;
    for (new i = 0; i < count; i++)
    {
        if (equal(g_fileAuth[i], auth))
        {
            found = i;
            break;
        }
    }

    if (found == -1)
    {
        if (count >= MAX_FILE_RECORDS)
        {
            return;
        }
        found = count++;
    }
    else if (g_fileTime[found] > 0 && g_fileTime[found] <= timeMs)
    {
        return;
    }

    copy(g_fileAuth[found], charsmax(g_fileAuth[]), auth);
    copy(g_fileName[found], charsmax(g_fileName[]), name);
    g_fileTime[found] = timeMs;
}

stock MysqlEscape(const input[], output[], len)
{
    new outPos;
    for (new i = 0; input[i] && outPos < len; i++)
    {
        new ch = input[i];
        if (ch == 39)
        {
            if (outPos + 1 >= len) break;
            output[outPos++] = 39;
            output[outPos++] = 39;
        }
        else if (ch == 92)
        {
            if (outPos + 1 >= len) break;
            output[outPos++] = 92;
            output[outPos++] = 92;
        }
        else if (ch == 10 || ch == 13 || ch == 9)
        {
            output[outPos++] = ' ';
        }
        else
        {
            output[outPos++] = ch;
        }
    }
    output[outPos] = '^0';
}

stock BuildBestUpsert(output[], len, const mapSql[], const authSql[], const nameSql[], timeMs, updatedAt)
{
    formatex(output, len,
        "INSERT INTO bhop_best (map,authid,name,best_time_ms,updated_at) VALUES ('%s','%s','%s',%d,%d) ON DUPLICATE KEY UPDATE name=IF(VALUES(best_time_ms)<best_time_ms,VALUES(name),name),updated_at=IF(VALUES(best_time_ms)<best_time_ms,VALUES(updated_at),updated_at),best_time_ms=LEAST(best_time_ms,VALUES(best_time_ms));",
        mapSql, authSql, nameSql, timeMs, updatedAt);
}

stock LoadZones()
{
    for (new zoneIndex = 0; zoneIndex < ZONE_COUNT; zoneIndex++)
    {
        g_zoneLoaded[zoneIndex] = false;
    }

    RefreshZoneCaches();

    if (g_dbReady)
    {
        DbRequestZones();
    }
}

stock LoadPlayerBest(id)
{
    g_bestTimeMs[id] = 0;

    if (!is_user_connected(id))
    {
        return;
    }

    if (!g_mapName[0])
    {
        get_mapname(g_mapName, charsmax(g_mapName));
    }

    g_bestTimeMs[id] = LoadPlayerBestFile(id, g_playerMode[id]);
}

stock SaveRun(id, timeMs, bool:isPersonalBest)
{
    new mode = g_playerMode[id];
    SaveRunFile(id, timeMs, isPersonalBest, mode);

    if (!g_dbConfigured)
    {
        return;
    }

    new auth[35], name[32], authSql[MAX_AUTH_SQL], nameSql[MAX_NAME_SQL], mapSql[MAX_MAP_SQL], query[1024], modeMapName[64], recordKey[96];
    get_user_authid(id, auth, charsmax(auth));
    get_user_name(id, name, charsmax(name));
    GetMapNameForMode(mode, modeMapName, charsmax(modeMapName));

    MysqlEscape(auth, authSql, charsmax(authSql));
    MysqlEscape(name, nameSql, charsmax(nameSql));
    MysqlEscape(modeMapName, mapSql, charsmax(mapSql));

    new createdAt = get_systime();
    g_recordSequence++;
    formatex(recordKey, charsmax(recordKey), "live:%d:%d:%d:%d", createdAt, id, g_recordSequence, random_num(1000, 999999));
    formatex(query, charsmax(query), "INSERT IGNORE INTO bhop_records (record_key,map,authid,name,time_ms,created_at) VALUES ('%s','%s','%s','%s',%d,%d);",
        recordKey, mapSql, authSql, nameSql, timeMs, createdAt);
    QueueSql(query);

    if (isPersonalBest)
    {
        BuildBestUpsert(query, charsmax(query), mapSql, authSql, nameSql, timeMs, createdAt);
        QueueSql(query);
        g_bestTimeMs[id] = timeMs;
    }
}

stock StartTimer(id)
{
    g_timerState[id] = TIMER_RUNNING;
    g_startGameTime[id] = get_gametime();
    g_currentTimeMs[id] = 0;

    g_replayFrameCount[id] = 0;
    pev(id, pev_origin, g_replayOrigin[id][0]);
    pev(id, pev_v_angle, g_replayAngles[id][0]);
    g_replayFrameCount[id] = 1;
    g_lastRecordTime[id] = get_gametime();

    client_print(id, print_center, "Timer Started");
}

stock FinishTimer(id)
{
    new timeMs = GetRunningTimeMs(id);
    if (timeMs <= 0)
    {
        return;
    }

    if (g_duelState[id] == DUEL_STATE_RACING)
    {
        new partner = g_duelPartner[id];
        if (partner && is_user_connected(partner))
        {
            new winnerName[32], loserName[32];
            get_user_name(id, winnerName, charsmax(winnerName));
            get_user_name(partner, loserName, charsmax(loserName));

            new timeText[32];
            FormatTimeMs(timeMs, timeText, charsmax(timeText));

            TimerChat(0, "^x04[DUEL]^x01 ^x04%s^x01 won the duel against ^x04%s^x01 in ^x04%s^x01!", winnerName, loserName, timeText);

            ResetDuelState(partner);
        }
        ResetDuelState(id);
        return;
    }

    g_timerState[id] = TIMER_FINISHED;
    g_currentTimeMs[id] = timeMs;
    g_lastTimeMs[id] = timeMs;

    new mode = g_playerMode[id];
    new bool:isPersonalBest = (g_bestTimeMs[id] <= 0 || timeMs < g_bestTimeMs[id]);

    if (isPersonalBest)
    {
        g_bestTimeMs[id] = timeMs;
    }

    if (get_pcvar_num(g_cvarRecords))
    {
        SaveRun(id, timeMs, isPersonalBest);
    }

    new timeText[32], bestText[32], name[32], modeName[32];
    FormatTimeMs(timeMs, timeText, charsmax(timeText));
    get_user_name(id, name, charsmax(name));
    GetModeName(mode, modeName, charsmax(modeName));

    if (isPersonalBest)
    {
        new rank = GetRankForTime(timeMs, mode);

        if (rank == 1)
        {
            new path[192];
            BuildReplayPath(mode, path, charsmax(path));
            new fp = fopen(path, "wb");
            if (fp)
            {
                fwrite(fp, g_replayFrameCount[id], BLOCK_INT);

                static Float:tempBuf[MAX_REPLAY_FRAMES * 3];
                new idx = 0;
                for (new i = 0; i < g_replayFrameCount[id]; i++)
                {
                    tempBuf[idx++] = g_replayOrigin[id][i][0];
                    tempBuf[idx++] = g_replayOrigin[id][i][1];
                    tempBuf[idx++] = g_replayOrigin[id][i][2];
                }
                fwrite_blocks(fp, any:tempBuf, g_replayFrameCount[id] * 3, BLOCK_INT);

                idx = 0;
                for (new i = 0; i < g_replayFrameCount[id]; i++)
                {
                    tempBuf[idx++] = g_replayAngles[id][i][0];
                    tempBuf[idx++] = g_replayAngles[id][i][1];
                    tempBuf[idx++] = g_replayAngles[id][i][2];
                }
                fwrite_blocks(fp, any:tempBuf, g_replayFrameCount[id] * 3, BLOCK_INT);

                // Write ducking flags
                static tempDuckingBuf[MAX_REPLAY_FRAMES];
                for (new i = 0; i < g_replayFrameCount[id]; i++)
                {
                    tempDuckingBuf[i] = g_replayDucking[id][i] ? 1 : 0;
                }
                fwrite_blocks(fp, tempDuckingBuf, g_replayFrameCount[id], BLOCK_INT);

                fclose(fp);
            }

            if (g_botReplayMode == mode)
            {
                LoadReplayFile(g_botReplayMode);
                MaintainReplayBot();
            }
            UpdateWrHolders();
        }

        if (rank > 0)
        {
            TimerChat(id, "^x03[%s]^x01 Finished: ^x04%s^x01. Personal Best! Rank: ^x04#%d", modeName, timeText, rank);
            TimerChat(0, "^x04%s^x01 finished ^x04%s^x01 ^x03[%s]^x01 in ^x04%s^x01 - New ^x04#%d", name, g_mapName, modeName, timeText, rank);
        }
        else
        {
            TimerChat(id, "^x03[%s]^x01 Finished: ^x04%s^x01. Personal Best!", modeName, timeText);
            TimerChat(0, "^x04%s^x01 finished ^x04%s^x01 ^x03[%s]^x01 in ^x04%s^x01 - Personal Best!", name, g_mapName, modeName, timeText);
        }
    }
    else
    {
        FormatTimeMs(g_bestTimeMs[id], bestText, charsmax(bestText));
        TimerChat(id, "^x03[%s]^x01 Finished: ^x04%s^x01. Personal Best: ^x04%s", modeName, timeText, bestText);
    }

    if (get_pcvar_num(g_cvarTeleportOnFinish))
    {
        remove_task(id + TASK_START_TP);
        TimerSetTask(0.2, "TaskTeleportStart", id + TASK_START_TP);
    }
}

stock ResetToStart(id, bool:announce)
{
    g_timerState[id] = TIMER_IN_START;
    g_startGameTime[id] = 0.0;
    g_currentTimeMs[id] = 0;

    if (announce)
    {
        client_print(id, print_center, "Timer Reset");
    }
}

stock ResetPlayerData(id, bool:full)
{
    g_timerState[id] = TIMER_IDLE;
    g_prevInStart[id] = false;
    g_prevInFinish[id] = false;
    g_startGameTime[id] = 0.0;
    g_currentTimeMs[id] = 0;

    // Strafe statistics reset removed

    if (full)
    {
        g_bestTimeMs[id] = 0;
        g_lastTimeMs[id] = 0;

        for (new slot = 0; slot < EDIT_POINT_COUNT; slot++)
        {
            g_editHasPoint[id][slot] = false;
        }
    }
}

stock GetEditPointSlot(zoneIndex, point)
{
    return (zoneIndex * 2) + point;
}

stock bool:RefreshZoneCache(zoneIndex)
{
    if (!(0 <= zoneIndex < ZONE_COUNT))
        return false;

    new Float:mins[3], Float:maxs[3];
    if (!sr_zone_get_bounds_by_class(g_zoneClasses[zoneIndex], mins, maxs))
    {
        g_zoneLoaded[zoneIndex] = false;
        return false;
    }

    for (new i = 0; i < 3; i++)
    {
        g_zoneMin[zoneIndex][i] = mins[i];
        g_zoneMax[zoneIndex][i] = maxs[i];
    }

    g_zoneLoaded[zoneIndex] = true;
    return true;
}

stock RefreshZoneCaches()
{
    for (new zoneIndex = 0; zoneIndex < ZONE_COUNT; zoneIndex++)
    {
        RefreshZoneCache(zoneIndex);
    }
}

stock SaveZonesFromFramework(id)
{
    RefreshZoneCaches();
    for (new zoneIndex = 0; zoneIndex < ZONE_COUNT; zoneIndex++)
    {
        if (g_zoneLoaded[zoneIndex])
        {
            SaveZone(id, zoneIndex);
        }
    }

    SaveZonesFile();
}

stock GetStartTeleportOrigin(Float:origin[3])
{
    RefreshZoneCache(ZONE_START);

    origin[0] = (g_zoneMin[ZONE_START][0] + g_zoneMax[ZONE_START][0]) / 2.0;
    origin[1] = (g_zoneMin[ZONE_START][1] + g_zoneMax[ZONE_START][1]) / 2.0;
    origin[2] = g_zoneMin[ZONE_START][2] + get_pcvar_float(g_cvarStartTeleportZOffset);
}

stock bool:HasEditZone(id, zoneIndex)
{
    return g_editHasPoint[id][GetEditPointSlot(zoneIndex, 0)] && g_editHasPoint[id][GetEditPointSlot(zoneIndex, 1)];
}

stock GetRunningTimeMs(id)
{
    return floatround((get_gametime() - g_startGameTime[id]) * 1000.0, floatround_floor);
}

stock bool:CanCountRun(id)
{
    if (g_hookActive[id])
    {
        return false;
    }

    if (pev(id, pev_movetype) == MOVETYPE_NOCLIP)
    {
        return false;
    }

    return true;
}

stock bool:IsPointInZone(const Float:point[3], zoneIndex)
{
    if (!g_zoneLoaded[zoneIndex])
    {
        return false;
    }

    return sr_zone_is_point_in_class(g_zoneClasses[zoneIndex], point);
}

stock RenderZone(zoneIndex)
{
    new r, g, b;
    if (zoneIndex == ZONE_START)
    {
        GetCvarColor(g_cvarStartColor, r, g, b);
    }
    else
    {
        GetCvarColor(g_cvarFinishColor, r, g, b);
    }

    new Float:z = g_zoneMin[zoneIndex][2] + get_pcvar_float(g_cvarZoneRenderZOffset);

    new Float:p1[3], Float:p2[3], Float:p3[3], Float:p4[3];
    p1[0] = g_zoneMin[zoneIndex][0]; p1[1] = g_zoneMin[zoneIndex][1]; p1[2] = z;
    p2[0] = g_zoneMax[zoneIndex][0]; p2[1] = g_zoneMin[zoneIndex][1]; p2[2] = z;
    p3[0] = g_zoneMax[zoneIndex][0]; p3[1] = g_zoneMax[zoneIndex][1]; p3[2] = z;
    p4[0] = g_zoneMin[zoneIndex][0]; p4[1] = g_zoneMax[zoneIndex][1]; p4[2] = z;

    if (get_pcvar_num(g_cvarZoneSnapToFloor))
    {
        SnapPointToFloor(zoneIndex, p1);
        SnapPointToFloor(zoneIndex, p2);
        SnapPointToFloor(zoneIndex, p3);
        SnapPointToFloor(zoneIndex, p4);
    }

    DrawBeam(p1, p2, r, g, b);
    DrawBeam(p2, p3, r, g, b);
    DrawBeam(p3, p4, r, g, b);
    DrawBeam(p4, p1, r, g, b);
}

stock DrawBeam(const Float:start[3], const Float:end[3], r, g, b)
{
    if (!g_beamSprite)
    {
        return;
    }

    new life = floatround(get_pcvar_float(g_cvarRenderInterval) * 10.0) + 2;
    if (life < 2)
    {
        life = 2;
    }
    else if (life > 255)
    {
        life = 255;
    }

    message_begin(MSG_BROADCAST, SVC_TEMPENTITY);
    write_byte(TE_BEAMPOINTS);
    write_coord(floatround(start[0]));
    write_coord(floatround(start[1]));
    write_coord(floatround(start[2]));
    write_coord(floatround(end[0]));
    write_coord(floatround(end[1]));
    write_coord(floatround(end[2]));
    write_short(g_beamSprite);
    write_byte(0);
    write_byte(0);
    write_byte(life);
    write_byte(8);
    write_byte(0);
    write_byte(r);
    write_byte(g);
    write_byte(b);
    write_byte(220);
    write_byte(0);
    message_end();
}

stock DrawShortBeam(const Float:start[3], const Float:end[3], r, g, b, width = 5)
{
    if (!g_beamSprite)
    {
        return;
    }

    message_begin(MSG_BROADCAST, SVC_TEMPENTITY);
    write_byte(TE_BEAMPOINTS);
    write_coord(floatround(start[0]));
    write_coord(floatround(start[1]));
    write_coord(floatround(start[2]));
    write_coord(floatround(end[0]));
    write_coord(floatround(end[1]));
    write_coord(floatround(end[2]));
    write_short(g_beamSprite);
    write_byte(0);
    write_byte(0);
    write_byte(2);
    write_byte(width);
    write_byte(0);
    write_byte(r);
    write_byte(g);
    write_byte(b);
    write_byte(220);
    write_byte(0);
    message_end();
}

stock SnapPointToFloor(zoneIndex, Float:point[3])
{
    new Float:start[3], Float:end[3], Float:hit[3];
    start[0] = point[0];
    start[1] = point[1];
    start[2] = g_zoneMax[zoneIndex][2] + 64.0;

    end[0] = point[0];
    end[1] = point[1];
    end[2] = g_zoneMin[zoneIndex][2] - 160.0;

    new trace = create_tr2();
    engfunc(EngFunc_TraceLine, start, end, IGNORE_MONSTERS, 0, trace);
    new Float:fraction;
    get_tr2(trace, TR_flFraction, fraction);
    get_tr2(trace, TR_vecEndPos, hit);
    free_tr2(trace);

    if (fraction < 1.0)
    {
        point[2] = hit[2] + get_pcvar_float(g_cvarZoneRenderZOffset);
    }
}

stock GetCvarColor(cvar, &r, &g, &b)
{
    new value[32], red[8], green[8], blue[8];
    get_pcvar_string(cvar, value, charsmax(value));
    parse(value, red, charsmax(red), green, charsmax(green), blue, charsmax(blue));

    r = clamp(str_to_num(red), 0, 255);
    g = clamp(str_to_num(green), 0, 255);
    b = clamp(str_to_num(blue), 0, 255);
}



stock GetRankForTime(timeMs, mode)
{
    return GetRankForTimeFile(timeMs, mode);
}

stock GetRecordCount(mode)
{
    return GetRecordCountFile(mode);
}

stock BuildMapDataPath(output[], len, const suffix[], mode)
{
    if (!g_mapName[0])
    {
        get_mapname(g_mapName, charsmax(g_mapName));
    }

    new dataDir[128];
    get_datadir(dataDir, charsmax(dataDir));
    
    if (equal(suffix, "zones"))
    {
        formatex(output, len, "%s/bhop_timer_%s_%s.ini", dataDir, g_mapName, suffix);
    }
    else
    {
        new modeSuffix[32];
        if (mode == 1) // Low Gravity
        {
            formatex(modeSuffix, charsmax(modeSuffix), "%s_lowgrav", suffix);
        }
        else if (mode == 2) // Double Jump
        {
            formatex(modeSuffix, charsmax(modeSuffix), "%s_dbjump", suffix);
        }
        else
        {
            copy(modeSuffix, charsmax(modeSuffix), suffix);
        }
        formatex(output, len, "%s/bhop_timer_%s_%s.ini", dataDir, g_mapName, modeSuffix);
    }
}

stock LoadZonesFile()
{
    new path[192];
    BuildMapDataPath(path, charsmax(path), "zones", 0);

    if (!file_exists(path))
    {
        return;
    }

    new fp = fopen(path, "rt");
    if (!fp)
    {
        return;
    }

    new line[192];
    while (!feof(fp))
    {
        fgets(fp, line, charsmax(line));
        trim(line);

        if (!line[0] || line[0] == ';' || line[0] == '#')
        {
            continue;
        }

        new zoneType[16], minX[24], minY[24], minZ[24], maxX[24], maxY[24], maxZ[24];
        parse(line,
            zoneType, charsmax(zoneType),
            minX, charsmax(minX),
            minY, charsmax(minY),
            minZ, charsmax(minZ),
            maxX, charsmax(maxX),
            maxY, charsmax(maxY),
            maxZ, charsmax(maxZ));

        new zoneIndex = -1;
        if (equal(zoneType, "start"))
        {
            zoneIndex = ZONE_START;
        }
        else if (equal(zoneType, "finish"))
        {
            zoneIndex = ZONE_FINISH;
        }

        if (zoneIndex == -1)
        {
            continue;
        }

        g_zoneMin[zoneIndex][0] = str_to_float(minX);
        g_zoneMin[zoneIndex][1] = str_to_float(minY);
        g_zoneMin[zoneIndex][2] = str_to_float(minZ);
        g_zoneMax[zoneIndex][0] = str_to_float(maxX);
        g_zoneMax[zoneIndex][1] = str_to_float(maxY);
        g_zoneMax[zoneIndex][2] = str_to_float(maxZ);
        g_zoneLoaded[zoneIndex] = true;
    }

    fclose(fp);
}

stock bool:SaveZonesFile()
{
    new path[192];
    BuildMapDataPath(path, charsmax(path), "zones", 0);

    new fp = fopen(path, "wt");
    if (!fp)
    {
        log_amx("[TIMER] Could not write zone file: %s", path);
        return false;
    }

    for (new zoneIndex = 0; zoneIndex < ZONE_COUNT; zoneIndex++)
    {
        if (!g_zoneLoaded[zoneIndex])
        {
            continue;
        }

        fprintf(fp, "%s %.3f %.3f %.3f %.3f %.3f %.3f^n",
            g_zoneNames[zoneIndex],
            g_zoneMin[zoneIndex][0], g_zoneMin[zoneIndex][1], g_zoneMin[zoneIndex][2],
            g_zoneMax[zoneIndex][0], g_zoneMax[zoneIndex][1], g_zoneMax[zoneIndex][2]);
    }

    fclose(fp);
    return true;
}

stock LoadBestFile(mode)
{
    if (IsValidMode(mode) && g_bestFileCacheLoaded[mode])
    {
        CopyBestCacheToWorking(mode);
        return g_bestFileCacheCount[mode];
    }

    new path[192];
    BuildMapDataPath(path, charsmax(path), "best", mode);

    if (!file_exists(path))
    {
        if (IsValidMode(mode))
        {
            ClearBestCache(mode);
        }
        return 0;
    }

    new fp = fopen(path, "rt");
    if (!fp)
    {
        return 0;
    }

    new count, line[192];
    while (!feof(fp) && count < MAX_FILE_RECORDS)
    {
        fgets(fp, line, charsmax(line));
        trim(line);

        if (!line[0] || line[0] == ';' || line[0] == '#')
        {
            continue;
        }

        new auth[35], timeText[16], name[32];
        parse(line,
            auth, charsmax(auth),
            timeText, charsmax(timeText),
            name, charsmax(name));

        new timeMs = str_to_num(timeText);
        if (!auth[0] || timeMs <= 0)
        {
            continue;
        }

        copy(g_fileAuth[count], charsmax(g_fileAuth[]), auth);
        copy(g_fileName[count], charsmax(g_fileName[]), name);
        g_fileTime[count] = timeMs;
        count++;
    }

    fclose(fp);
    SaveWorkingBestCache(mode, count);
    return count;
}

stock bool:SaveBestFile(count, mode)
{
    new path[192];
    BuildMapDataPath(path, charsmax(path), "best", mode);

    new fp = fopen(path, "wt");
    if (!fp)
    {
        log_amx("[TIMER] Could not write best file: %s", path);
        return false;
    }

    for (new i = 0; i < count; i++)
    {
        fprintf(fp, "%s %d %s^n", g_fileAuth[i], g_fileTime[i], g_fileName[i]);
    }

    fclose(fp);
    SaveWorkingBestCache(mode, count);
    return true;
}

stock SaveRunFile(id, timeMs, bool:isPersonalBest, mode)
{
    new auth[35], name[32], path[192];
    get_user_authid(id, auth, charsmax(auth));
    get_user_name(id, name, charsmax(name));
    SanitizeFileToken(name, charsmax(name));

    BuildMapDataPath(path, charsmax(path), "records", mode);
    new line[160];
    formatex(line, charsmax(line), "%d %s %d %s", get_systime(), auth, timeMs, name);
    write_file(path, line);

    if (!isPersonalBest)
    {
        return;
    }

    new count = LoadBestFile(mode);
    new found = -1;

    for (new i = 0; i < count; i++)
    {
        if (equal(g_fileAuth[i], auth))
        {
            found = i;
            break;
        }
    }

    if (found == -1 && count < MAX_FILE_RECORDS)
    {
        found = count;
        count++;
    }

    if (found != -1)
    {
        copy(g_fileAuth[found], charsmax(g_fileAuth[]), auth);
        copy(g_fileName[found], charsmax(g_fileName[]), name);
        g_fileTime[found] = timeMs;
        SortBestCache(count);
        SaveBestFile(count, mode);
    }
}

stock LoadPlayerBestFile(id, mode)
{
    new auth[35];
    get_user_authid(id, auth, charsmax(auth));

    new count = LoadBestFile(mode);
    for (new i = 0; i < count; i++)
    {
        if (equal(g_fileAuth[i], auth))
        {
            return g_fileTime[i];
        }
    }

    return 0;
}

stock GetRankForTimeFile(timeMs, mode)
{
    new count = LoadBestFile(mode);
    new rank = 1;

    for (new i = 0; i < count; i++)
    {
        if (g_fileTime[i] < timeMs)
        {
            rank++;
        }
    }

    return rank;
}

stock GetRecordCountFile(mode)
{
    return LoadBestFile(mode);
}

stock bool:IsValidMode(mode)
{
    return (mode >= MODE_NORMAL && mode <= MODE_DOUBLE_JUMP) ? true : false;
}

stock ClearBestCache(mode)
{
    if (!IsValidMode(mode))
    {
        return;
    }

    g_bestFileCacheLoaded[mode] = true;
    g_bestFileCacheCount[mode] = 0;
}

stock CopyBestCacheToWorking(mode)
{
    if (!IsValidMode(mode))
    {
        return;
    }

    new count = g_bestFileCacheCount[mode];
    for (new i = 0; i < count; i++)
    {
        copy(g_fileAuth[i], charsmax(g_fileAuth[]), g_bestFileCacheAuth[mode][i]);
        copy(g_fileName[i], charsmax(g_fileName[]), g_bestFileCacheName[mode][i]);
        g_fileTime[i] = g_bestFileCacheTime[mode][i];
    }
}

stock SaveWorkingBestCache(mode, count)
{
    if (!IsValidMode(mode))
    {
        return;
    }

    if (count < 0)
    {
        count = 0;
    }
    else if (count > MAX_FILE_RECORDS)
    {
        count = MAX_FILE_RECORDS;
    }

    g_bestFileCacheLoaded[mode] = true;
    g_bestFileCacheCount[mode] = count;

    for (new i = 0; i < count; i++)
    {
        copy(g_bestFileCacheAuth[mode][i], charsmax(g_bestFileCacheAuth[][]), g_fileAuth[i]);
        copy(g_bestFileCacheName[mode][i], charsmax(g_bestFileCacheName[][]), g_fileName[i]);
        g_bestFileCacheTime[mode][i] = g_fileTime[i];
    }
}

stock SortBestCache(count)
{
    for (new i = 0; i < count; i++)
    {
        new best = i;
        for (new j = i + 1; j < count; j++)
        {
            if (g_fileTime[j] < g_fileTime[best])
            {
                best = j;
            }
        }

        if (best != i)
        {
            SwapBestRows(i, best);
        }
    }
}

stock SwapBestRows(a, b)
{
    new tempTime = g_fileTime[a];
    new tempAuth[35], tempName[32];

    copy(tempAuth, charsmax(tempAuth), g_fileAuth[a]);
    copy(tempName, charsmax(tempName), g_fileName[a]);

    g_fileTime[a] = g_fileTime[b];
    copy(g_fileAuth[a], charsmax(g_fileAuth[]), g_fileAuth[b]);
    copy(g_fileName[a], charsmax(g_fileName[]), g_fileName[b]);

    g_fileTime[b] = tempTime;
    copy(g_fileAuth[b], charsmax(g_fileAuth[]), tempAuth);
    copy(g_fileName[b], charsmax(g_fileName[]), tempName);
}

stock SanitizeFileToken(value[], len)
{
    replace_all(value, len, " ", "_");
    replace_all(value, len, "^t", "_");
}

stock MigrateLegacyStorage()
{
    new marker[192];
    BuildDbDataPath(marker, charsmax(marker), "bhop_timer_mysql_migration_v1.done");
    if (file_exists(marker))
    {
        return;
    }

    new sqliteRows = MigrateLegacySqlite();
    new fileRows = MigrateLegacyFiles();

    new status[128];
    formatex(status, charsmax(status), "queued_at=%d sqlite_rows=%d file_rows=%d", get_systime(), sqliteRows, fileRows);
    write_file(marker, status);
    log_amx("[TIMER] Legacy migration queued: %d SQLite rows, %d file rows.", sqliteRows, fileRows);
}

stock bool:LegacySqliteTableExists(Handle:connection, const tableName[])
{
    new queryText[256];
    formatex(queryText, charsmax(queryText), "SELECT name FROM sqlite_master WHERE type='table' AND name='%s' LIMIT 1;", tableName);
    new Handle:query = SQL_PrepareQuery(connection, queryText);
    if (query == Empty_Handle)
    {
        return false;
    }

    new bool:exists = false;
    if (SQL_Execute(query) && SQL_NumResults(query) > 0)
    {
        exists = true;
    }
    SQL_FreeHandle(query);
    return exists;
}

stock MigrateLegacySqlite()
{
    if (!SQL_SetAffinity("sqlite"))
    {
        log_amx("[TIMER] SQLite module unavailable; legacy file migration will still run.");
        return 0;
    }

    new Handle:tuple = SQL_MakeDbTuple("", "", "", "bhop_timer");
    new error[256], errorCode;
    new Handle:connection = SQL_Connect(tuple, errorCode, error, charsmax(error));
    if (connection == Empty_Handle)
    {
        SQL_FreeHandle(tuple);
        log_amx("[TIMER] Legacy SQLite migration skipped (%d): %s", errorCode, error);
        return 0;
    }

    new migrated;
    if (LegacySqliteTableExists(connection, "bhop_records"))
    {
        new Handle:query = SQL_PrepareQuery(connection, "SELECT map,authid,name,time_ms,created_at FROM bhop_records;");
        if (query != Empty_Handle && SQL_Execute(query))
        {
            while (SQL_MoreResults(query))
            {
                new map[64], auth[35], name[32], timeMs, createdAt;
                SQL_ReadResult(query, 0, map, charsmax(map));
                SQL_ReadResult(query, 1, auth, charsmax(auth));
                SQL_ReadResult(query, 2, name, charsmax(name));
                timeMs = SQL_ReadResult(query, 3);
                createdAt = SQL_ReadResult(query, 4);
                QueueLegacyRecord(map, auth, name, timeMs, createdAt);
                migrated++;
                SQL_NextRow(query);
            }
        }
        if (query != Empty_Handle) SQL_FreeHandle(query);
    }

    if (LegacySqliteTableExists(connection, "bhop_best"))
    {
        new Handle:query = SQL_PrepareQuery(connection, "SELECT map,authid,name,best_time_ms,updated_at FROM bhop_best;");
        if (query != Empty_Handle && SQL_Execute(query))
        {
            while (SQL_MoreResults(query))
            {
                new map[64], auth[35], name[32], timeMs, updatedAt;
                SQL_ReadResult(query, 0, map, charsmax(map));
                SQL_ReadResult(query, 1, auth, charsmax(auth));
                SQL_ReadResult(query, 2, name, charsmax(name));
                timeMs = SQL_ReadResult(query, 3);
                updatedAt = SQL_ReadResult(query, 4);
                QueueLegacyBest(map, auth, name, timeMs, updatedAt);
                migrated++;
                SQL_NextRow(query);
            }
        }
        if (query != Empty_Handle) SQL_FreeHandle(query);
    }

    if (LegacySqliteTableExists(connection, "bhop_zones"))
    {
        new Handle:query = SQL_PrepareQuery(connection, "SELECT map,zone_type,min_x,min_y,min_z,max_x,max_y,max_z,updated_at,updated_by FROM bhop_zones;");
        if (query != Empty_Handle && SQL_Execute(query))
        {
            while (SQL_MoreResults(query))
            {
                new map[64], zoneType[16], updatedBy[35], updatedAt;
                new Float:mins[3], Float:maxs[3];
                SQL_ReadResult(query, 0, map, charsmax(map));
                SQL_ReadResult(query, 1, zoneType, charsmax(zoneType));
                SQL_ReadResult(query, 2, mins[0]);
                SQL_ReadResult(query, 3, mins[1]);
                SQL_ReadResult(query, 4, mins[2]);
                SQL_ReadResult(query, 5, maxs[0]);
                SQL_ReadResult(query, 6, maxs[1]);
                SQL_ReadResult(query, 7, maxs[2]);
                updatedAt = SQL_ReadResult(query, 8);
                SQL_ReadResult(query, 9, updatedBy, charsmax(updatedBy));
                QueueLegacyZone(map, zoneType, mins, maxs, updatedAt, updatedBy);
                migrated++;
                SQL_NextRow(query);
            }
        }
        if (query != Empty_Handle) SQL_FreeHandle(query);
    }

    SQL_FreeHandle(connection);
    SQL_FreeHandle(tuple);
    return migrated;
}

stock MigrateLegacyFiles()
{
    new dataDir[128], fileName[160];
    get_datadir(dataDir, charsmax(dataDir));
    new dir = open_dir(dataDir, fileName, charsmax(fileName));
    if (!dir)
    {
        return 0;
    }

    new migrated;
    do
    {
        if (containi(fileName, "bhop_timer_") == 0)
        {
            migrated += MigrateLegacyFile(dataDir, fileName);
        }
    }
    while (next_file(dir, fileName, charsmax(fileName)));

    close_dir(dir);
    return migrated;
}

stock MigrateLegacyFile(const dataDir[], const fileName[])
{
    new mapName[64], modeSuffix[16], kind;
    if (ExtractLegacyMap(fileName, "_records_lowgrav.ini", mapName, charsmax(mapName)))
    {
        copy(modeSuffix, charsmax(modeSuffix), "_lowgrav");
        kind = 1;
    }
    else if (ExtractLegacyMap(fileName, "_records_dbjump.ini", mapName, charsmax(mapName)))
    {
        copy(modeSuffix, charsmax(modeSuffix), "_dbjump");
        kind = 1;
    }
    else if (ExtractLegacyMap(fileName, "_records.ini", mapName, charsmax(mapName)))
    {
        kind = 1;
    }
    else if (ExtractLegacyMap(fileName, "_best_lowgrav.ini", mapName, charsmax(mapName)))
    {
        copy(modeSuffix, charsmax(modeSuffix), "_lowgrav");
        kind = 2;
    }
    else if (ExtractLegacyMap(fileName, "_best_dbjump.ini", mapName, charsmax(mapName)))
    {
        copy(modeSuffix, charsmax(modeSuffix), "_dbjump");
        kind = 2;
    }
    else if (ExtractLegacyMap(fileName, "_best.ini", mapName, charsmax(mapName)))
    {
        kind = 2;
    }
    else if (ExtractLegacyMap(fileName, "_zones.ini", mapName, charsmax(mapName)))
    {
        kind = 3;
    }
    else
    {
        return 0;
    }

    new remoteMap[64];
    formatex(remoteMap, charsmax(remoteMap), "%s%s", mapName, modeSuffix);
    new path[256];
    formatex(path, charsmax(path), "%s/%s", dataDir, fileName);
    new fp = fopen(path, "rt");
    if (!fp)
    {
        return 0;
    }

    new migrated, line[256];
    while (!feof(fp))
    {
        fgets(fp, line, charsmax(line));
        trim(line);
        if (!line[0] || line[0] == ';' || line[0] == '#') continue;

        if (kind == 1)
        {
            new createdText[16], auth[35], timeText[16], name[32];
            parse(line, createdText, charsmax(createdText), auth, charsmax(auth), timeText, charsmax(timeText), name, charsmax(name));
            new createdAt = str_to_num(createdText), timeMs = str_to_num(timeText);
            if (auth[0] && createdAt > 0 && timeMs > 0)
            {
                QueueLegacyRecord(remoteMap, auth, name, timeMs, createdAt);
                migrated++;
            }
        }
        else if (kind == 2)
        {
            new auth[35], timeText[16], name[32];
            parse(line, auth, charsmax(auth), timeText, charsmax(timeText), name, charsmax(name));
            new timeMs = str_to_num(timeText);
            if (auth[0] && timeMs > 0)
            {
                QueueLegacyBest(remoteMap, auth, name, timeMs, get_systime());
                migrated++;
            }
        }
        else
        {
            new zoneType[16], minX[24], minY[24], minZ[24], maxX[24], maxY[24], maxZ[24];
            parse(line, zoneType, charsmax(zoneType), minX, charsmax(minX), minY, charsmax(minY), minZ, charsmax(minZ), maxX, charsmax(maxX), maxY, charsmax(maxY), maxZ, charsmax(maxZ));
            if (equal(zoneType, "start") || equal(zoneType, "finish"))
            {
                new Float:mins[3], Float:maxs[3];
                mins[0] = str_to_float(minX); mins[1] = str_to_float(minY); mins[2] = str_to_float(minZ);
                maxs[0] = str_to_float(maxX); maxs[1] = str_to_float(maxY); maxs[2] = str_to_float(maxZ);
                QueueLegacyZone(remoteMap, zoneType, mins, maxs, get_systime(), "file_migration");
                migrated++;
            }
        }
    }

    fclose(fp);
    return migrated;
}

stock bool:ExtractLegacyMap(const fileName[], const suffix[], output[], len)
{
    new fileLength = strlen(fileName), suffixLength = strlen(suffix);
    if (fileLength <= 11 + suffixLength || !equal(fileName[fileLength - suffixLength], suffix))
    {
        return false;
    }

    copy(output, len, fileName[11]);
    output[strlen(output) - suffixLength] = '^0';
    return output[0] != '^0';
}

stock QueueLegacyRecord(const mapName[], const auth[], const name[], timeMs, createdAt)
{
    new mapSql[MAX_MAP_SQL], authSql[MAX_AUTH_SQL], nameSql[MAX_NAME_SQL], keyRaw[192], keySql[256], query[1024];
    MysqlEscape(mapName, mapSql, charsmax(mapSql));
    MysqlEscape(auth, authSql, charsmax(authSql));
    MysqlEscape(name, nameSql, charsmax(nameSql));
    formatex(keyRaw, charsmax(keyRaw), "legacy:%s:%s:%d:%d", mapName, auth, createdAt, timeMs);
    MysqlEscape(keyRaw, keySql, charsmax(keySql));
    formatex(query, charsmax(query), "INSERT IGNORE INTO bhop_records (record_key,map,authid,name,time_ms,created_at) VALUES ('%s','%s','%s','%s',%d,%d);", keySql, mapSql, authSql, nameSql, timeMs, createdAt);
    QueueSql(query);
}

stock QueueLegacyBest(const mapName[], const auth[], const name[], timeMs, updatedAt)
{
    new mapSql[MAX_MAP_SQL], authSql[MAX_AUTH_SQL], nameSql[MAX_NAME_SQL], query[1024];
    MysqlEscape(mapName, mapSql, charsmax(mapSql));
    MysqlEscape(auth, authSql, charsmax(authSql));
    MysqlEscape(name, nameSql, charsmax(nameSql));
    BuildBestUpsert(query, charsmax(query), mapSql, authSql, nameSql, timeMs, updatedAt);
    QueueSql(query);
}

stock QueueLegacyZone(const mapName[], const zoneType[], const Float:mins[3], const Float:maxs[3], updatedAt, const updatedBy[])
{
    new mapSql[MAX_MAP_SQL], updatedBySql[MAX_AUTH_SQL], query[1024];
    MysqlEscape(mapName, mapSql, charsmax(mapSql));
    MysqlEscape(updatedBy, updatedBySql, charsmax(updatedBySql));
    formatex(query, charsmax(query),
        "INSERT INTO bhop_zones (map,zone_type,min_x,min_y,min_z,max_x,max_y,max_z,updated_at,updated_by) VALUES ('%s','%s',%.3f,%.3f,%.3f,%.3f,%.3f,%.3f,%d,'%s') ON DUPLICATE KEY UPDATE min_x=VALUES(min_x),min_y=VALUES(min_y),min_z=VALUES(min_z),max_x=VALUES(max_x),max_y=VALUES(max_y),max_z=VALUES(max_z),updated_at=VALUES(updated_at),updated_by=VALUES(updated_by);",
        mapSql, zoneType, mins[0], mins[1], mins[2], maxs[0], maxs[1], maxs[2], updatedAt, updatedBySql);
    QueueSql(query);
}

stock RegisterBlockedCommands()
{
    register_clcmd("drop", "CmdBlocked");
    register_clcmd("kill", "CmdBlocked");
    register_clcmd("explode", "CmdBlocked");

    register_clcmd("vote", "CmdBlocked");
    register_clcmd("votemap", "CmdBlocked");
    register_clcmd("listmaps", "CmdBlocked");

    register_clcmd("chooseteam", "CmdBlockedTeam");
    register_clcmd("jointeam", "CmdJoinTeam");
    register_clcmd("joinclass", "CmdJoinClass");

    for (new i = 0; i < sizeof(g_radioCommands); i++)
    {
        register_clcmd(g_radioCommands[i], "CmdBlocked");
    }
}

public TaskAutoJoinCt(taskid)
{
    new id = taskid - TASK_AUTOJOIN;

    if (!(1 <= id <= MAX_PLAYERS) || !is_user_connected(id))
    {
        return;
    }

    AutoJoinCt(id);
}

public TaskTeleportStart(taskid)
{
    new id = taskid - TASK_START_TP;

    if (1 <= id <= MAX_PLAYERS && is_user_connected(id))
    {
        TeleportToStart(id, false);
    }
}

stock QueueAutoJoinCt(id, Float:delay)
{
    if (!get_pcvar_num(g_cvarAutoCt) || !is_user_connected(id))
    {
        return;
    }

    remove_task(id + TASK_AUTOJOIN);
    TimerSetTask(delay, "TaskAutoJoinCt", id + TASK_AUTOJOIN);
}

stock ScheduleEnsureCtSpawn(id, Float:delay, bool:resetRetry)
{
    if (!is_user_connected(id))
    {
        return;
    }

    if (resetRetry)
    {
        g_spawnRetryCount[id] = 0;
    }

    remove_task(id + TASK_SPAWN_CT);
    TimerSetTask(delay, "TaskEnsureCtSpawn", id + TASK_SPAWN_CT);
}

stock ForcePlayerCtClass(id)
{
    if (!is_user_connected(id))
    {
        return;
    }

    cs_set_user_team(id, CS_TEAM_CT, CS_CT_SAS);

    g_internalTeamCommand[id] = true;
    engclient_cmd(id, "jointeam", "2");
    engclient_cmd(id, "joinclass", "3");
    g_internalTeamCommand[id] = false;
}

stock AutoJoinCt(id)
{
    if (!get_pcvar_num(g_cvarAutoCt) || !is_user_connected(id))
    {
        return;
    }

    if (cs_get_user_team(id) == CS_TEAM_CT && is_user_alive(id))
    {
        return;
    }

    if (cs_get_user_team(id) == CS_TEAM_CT && !is_user_alive(id))
    {
        ForcePlayerCtClass(id);
        ScheduleEnsureCtSpawn(id, 0.3, true);
        return;
    }

    ForcePlayerCtClass(id);
    ScheduleEnsureCtSpawn(id, 0.3, true);
}

public TaskEnsureCtSpawn(taskid)
{
    new id = taskid - TASK_SPAWN_CT;

    if (!(1 <= id <= MAX_PLAYERS) || !is_user_connected(id))
    {
        return;
    }

    if (is_user_alive(id))
    {
        g_spawnRetryCount[id] = 0;
        ApplyPlayerProtections(id);
        UpdatePlayerHudVisibility(id);
        ApplyAdminGlow(id);
        ApplyModeFpsMax(id);
        return;
    }

    ForcePlayerCtClass(id);

    if (ForceRespawnPlayer(id))
    {
        g_spawnRetryCount[id] = 0;
        ApplyModeFpsMax(id);

        if (g_zoneLoaded[ZONE_START])
        {
            TeleportToStart(id, false);
        }
        return;
    }

    g_spawnRetryCount[id]++;
    if (g_spawnRetryCount[id] < MAX_SPAWN_RETRIES)
    {
        ScheduleEnsureCtSpawn(id, 0.5, false);
        return;
    }

    TimerChat(id, "Could not spawn you automatically. Press OK, then type /ct.");
}

stock KeepAlivePlayerCt(id)
{
    if (!get_pcvar_num(g_cvarAutoCt) || !is_user_connected(id) || !is_user_alive(id))
    {
        return;
    }

    if (cs_get_user_team(id) != CS_TEAM_CT)
    {
        cs_set_user_team(id, CS_TEAM_CT, CS_CT_SAS);
    }
}

stock ApplyPlayerProtections(id)
{
    if (!get_pcvar_num(g_cvarGodmode) || !is_user_alive(id))
    {
        return;
    }

    set_pev(id, pev_takedamage, DAMAGE_NO);
    set_pev(id, pev_health, 100.0);
    set_pev(id, pev_armorvalue, 100.0);
}

public ApplyAdminGlow(id)
{
    if (!is_user_alive(id) || is_user_bot(id))
    {
        return;
    }

    if (!get_pcvar_num(g_cvarAdminGlow) || (get_user_flags(id) & ~ADMIN_USER) == 0)
    {
        ClearPlayerRendering(id);
        return;
    }

    new colorText[32], rText[8], gText[8], bText[8];
    get_pcvar_string(g_cvarAdminGlowColor, colorText, charsmax(colorText));
    parse(colorText, rText, charsmax(rText), gText, charsmax(gText), bText, charsmax(bText));

    new Float:renderColor[3];
    renderColor[0] = float(clamp(str_to_num(rText), 0, 255));
    renderColor[1] = float(clamp(str_to_num(gText), 0, 255));
    renderColor[2] = float(clamp(str_to_num(bText), 0, 255));

    new Float:amount = get_pcvar_float(g_cvarAdminGlowAmount);
    if (amount < 1.0)
    {
        amount = 18.0;
    }

    set_pev(id, pev_renderfx, kRenderFxGlowShell);
    set_pev(id, pev_rendermode, kRenderNormal);
    set_pev(id, pev_renderamt, amount);
    set_pev(id, pev_rendercolor, renderColor);
}

stock ClearPlayerRendering(id)
{
    new Float:renderColor[3];
    renderColor[0] = 0.0;
    renderColor[1] = 0.0;
    renderColor[2] = 0.0;

    set_pev(id, pev_renderfx, kRenderFxNone);
    set_pev(id, pev_rendermode, kRenderNormal);
    set_pev(id, pev_renderamt, 0.0);
    set_pev(id, pev_rendercolor, renderColor);
}

stock ApplyAutoBhop(id)
{
    if (!get_pcvar_num(g_cvarAutoBhop) || is_user_bot(id))
    {
        return;
    }

    new buttons = pev(id, pev_button);
    if (!(buttons & IN_JUMP))
    {
        return;
    }

    if (pev(id, pev_waterlevel) >= 2)
    {
        return;
    }

    new flags = pev(id, pev_flags);
    if (flags & FL_ONGROUND)
    {
        if (IsOnSteepSlope(id))
        {
            return;
        }

        // Force jump instantly on the server to bypass ground friction (keeps 100% horizontal velocity even with 100ms+ ping)
        set_pev(id, pev_flags, flags & ~FL_ONGROUND);
        set_pev(id, pev_groundentity, 0);

        new Float:vel[3];
        pev(id, pev_velocity, vel);
        vel[2] = 268.328157; // exact CS 1.6 jump velocity
        set_pev(id, pev_velocity, vel);

        set_pev(id, pev_fuser2, 0.0);
    }

    set_pev(id, pev_oldbuttons, pev(id, pev_oldbuttons) & ~IN_JUMP);
}

stock ClearHookState(id)
{
    g_hookActive[id] = false;
    g_hookTarget[id][0] = 0.0;
    g_hookTarget[id][1] = 0.0;
    g_hookTarget[id][2] = 0.0;
    g_hookLastBeamTime[id] = 0.0;
}

stock StopPlayerHook(id, bool:restoreStart)
{
    new bool:wasActive = g_hookActive[id];
    ClearHookState(id);

    if (wasActive && restoreStart)
    {
        RestoreStartStateAfterHook(id);
    }
}

stock RestoreStartStateAfterHook(id)
{
    if (!is_user_alive(id) || pev(id, pev_movetype) == MOVETYPE_NOCLIP)
    {
        return;
    }

    RefreshZoneCache(ZONE_START);

    new Float:origin[3];
    pev(id, pev_origin, origin);

    if (IsPointInZone(origin, ZONE_START))
    {
        g_timerState[id] = TIMER_IN_START;
        g_currentTimeMs[id] = 0;
        g_prevInStart[id] = true;
    }
    else
    {
        g_prevInStart[id] = false;
    }
}

stock AbortTimerForHook(id)
{
    if (g_timerState[id] == TIMER_RUNNING || g_timerState[id] == TIMER_IN_START)
    {
        ResetPlayerData(id, false);
        client_print(id, print_center, "Hook Used - Timer Reset");
    }
}

stock bool:FindHookTarget(id, Float:target[3])
{
    new Float:start[3], Float:end[3], Float:viewAngles[3], Float:forwardVec[3];
    GetPlayerEyePosition(id, start);
    pev(id, pev_v_angle, viewAngles);

    engfunc(EngFunc_MakeVectors, viewAngles);
    global_get(glb_v_forward, forwardVec);

    new Float:maxDistance = get_pcvar_float(g_cvarHookMaxDistance);
    if (maxDistance < 128.0)
    {
        maxDistance = 128.0;
    }

    end[0] = start[0] + forwardVec[0] * maxDistance;
    end[1] = start[1] + forwardVec[1] * maxDistance;
    end[2] = start[2] + forwardVec[2] * maxDistance;

    new trace = create_tr2();
    engfunc(EngFunc_TraceLine, start, end, IGNORE_MONSTERS, id, trace);

    new Float:fraction;
    get_tr2(trace, TR_flFraction, fraction);

    if (get_tr2(trace, TR_StartSolid) || get_tr2(trace, TR_AllSolid) || fraction >= 1.0)
    {
        free_tr2(trace);
        return false;
    }

    get_tr2(trace, TR_vecEndPos, target);
    free_tr2(trace);

    new Float:origin[3];
    pev(id, pev_origin, origin);

    new Float:minDistance = get_pcvar_float(g_cvarHookMinDistance);
    if (minDistance < 16.0)
    {
        minDistance = 16.0;
    }

    return (GetVectorDistance(origin, target) >= minDistance) ? true : false;
}

stock ApplyPlayerHook(id)
{
    if (!g_hookActive[id])
    {
        return;
    }

    if (!get_pcvar_num(g_cvarHookEnabled) || !is_user_alive(id) || is_user_bot(id) ||
        pev(id, pev_movetype) == MOVETYPE_NOCLIP || g_duelState[id] != DUEL_STATE_IDLE)
    {
        StopPlayerHook(id, false);
        return;
    }

    AbortTimerForHook(id);

    new Float:origin[3], Float:direction[3], Float:velocity[3];
    pev(id, pev_origin, origin);

    direction[0] = g_hookTarget[id][0] - origin[0];
    direction[1] = g_hookTarget[id][1] - origin[1];
    direction[2] = g_hookTarget[id][2] - origin[2];

    new Float:distance = GetVectorLength(direction);
    new Float:minDistance = get_pcvar_float(g_cvarHookMinDistance);
    if (minDistance < 16.0)
    {
        minDistance = 16.0;
    }

    if (distance <= minDistance)
    {
        StopPlayerHook(id, true);
        return;
    }

    new Float:speed = get_pcvar_float(g_cvarHookSpeed);
    if (speed < 1.0)
    {
        speed = 900.0;
    }

    velocity[0] = direction[0] / distance * speed;
    velocity[1] = direction[1] / distance * speed;
    velocity[2] = direction[2] / distance * speed;
    set_pev(id, pev_velocity, velocity);

    new Float:now = get_gametime();
    if (now - g_hookLastBeamTime[id] >= 0.05)
    {
        new Float:start[3];
        GetPlayerEyePosition(id, start);
        DrawShortBeam(start, g_hookTarget[id], 80, 160, 255, 5);
        g_hookLastBeamTime[id] = now;
    }
}

stock ApplyPlayerParachute(id)
{
    if (!get_pcvar_num(g_cvarParachuteEnabled) || g_hookActive[id] || is_user_bot(id))
    {
        return;
    }

    if (pev(id, pev_movetype) == MOVETYPE_NOCLIP || pev(id, pev_waterlevel) >= 2)
    {
        return;
    }

    new buttons = pev(id, pev_button);
    new flags = pev(id, pev_flags);
    if (!(buttons & IN_USE) || (flags & FL_ONGROUND))
    {
        return;
    }

    new Float:fallSpeed = get_pcvar_float(g_cvarParachuteFallSpeed);
    if (fallSpeed < 1.0)
    {
        fallSpeed = 120.0;
    }

    new Float:velocity[3];
    pev(id, pev_velocity, velocity);

    if (velocity[2] < -fallSpeed)
    {
        velocity[2] = -fallSpeed;
        set_pev(id, pev_velocity, velocity);
    }
}

stock GetPlayerEyePosition(id, Float:origin[3])
{
    new Float:viewOfs[3];
    pev(id, pev_origin, origin);
    pev(id, pev_view_ofs, viewOfs);

    origin[0] += viewOfs[0];
    origin[1] += viewOfs[1];
    origin[2] += viewOfs[2];
}

stock Float:GetVectorLength(const Float:vector[3])
{
    return floatsqroot((vector[0] * vector[0]) + (vector[1] * vector[1]) + (vector[2] * vector[2]));
}

stock Float:GetVectorDistance(const Float:a[3], const Float:b[3])
{
    new Float:diff[3];
    diff[0] = a[0] - b[0];
    diff[1] = a[1] - b[1];
    diff[2] = a[2] - b[2];

    return GetVectorLength(diff);
}

stock bool:IsOnSteepSlope(id)
{
    new Float:origin[3], Float:end[3], Float:normal[3];
    pev(id, pev_origin, origin);

    end[0] = origin[0];
    end[1] = origin[1];
    end[2] = origin[2] - 48.0;

    new trace = create_tr2();
    engfunc(EngFunc_TraceLine, origin, end, IGNORE_MONSTERS, id, trace);

    new Float:fraction;
    get_tr2(trace, TR_flFraction, fraction);
    if (fraction < 1.0 && !get_tr2(trace, TR_StartSolid))
    {
        get_tr2(trace, TR_vecPlaneNormal, normal);
        free_tr2(trace);
        return (normal[2] > 0.01 && normal[2] <= 0.70) ? true : false;
    }

    free_tr2(trace);
    return false;
}

stock ApplyMovementSettings(id)
{
    if (is_user_bot(id))
    {
        return;
    }

    if (pev(id, pev_movetype) == MOVETYPE_NOCLIP)
    {
        set_pev(id, pev_maxspeed, 1500.0);
    }
    else
    {
        set_pev(id, pev_maxspeed, get_pcvar_float(g_cvarPlayerMaxspeed));
    }

    if (get_pcvar_num(g_cvarRemoveJumpSlowdown))
    {
        set_pev(id, pev_fuser2, 0.0);
    }

    if (g_playerMode[id] == MODE_LOW_GRAVITY)
    {
        set_pev(id, pev_gravity, 0.5);
    }
    else
    {
        set_pev(id, pev_gravity, 1.0);
    }
}

stock GetPlayerHorizontalSpeed(id)
{
    new Float:velocity[3];
    pev(id, pev_velocity, velocity);

    return floatround(floatsqroot((velocity[0] * velocity[0]) + (velocity[1] * velocity[1])));
}

stock GetReplayBotHorizontalSpeed()
{
    if (g_botReplayTotalFrames < 2 || g_botPlaybackInterval <= 0.0)
    {
        return 0;
    }

    new frame = g_botPlaybackFrame;
    if (frame < 0)
    {
        frame = 0;
    }
    if (frame >= g_botReplayTotalFrames)
    {
        frame = g_botReplayTotalFrames - 1;
    }

    new nextFrame = frame + 1;
    if (nextFrame >= g_botReplayTotalFrames)
    {
        nextFrame = 0;
    }

    new Float:dx = g_botReplayOrigin[nextFrame][0] - g_botReplayOrigin[frame][0];
    new Float:dy = g_botReplayOrigin[nextFrame][1] - g_botReplayOrigin[frame][1];
    new Float:distance = floatsqroot((dx * dx) + (dy * dy));

    return floatround(distance / g_botPlaybackInterval);
}

stock ApplyBhopServerCvars()
{
    if (!get_pcvar_num(g_cvarApplyServerCvars))
    {
        return;
    }

    ApplyServerCvar("sv_airaccelerate", g_cvarSvAiraccelerate);
    ApplyServerCvar("sv_maxspeed", g_cvarSvMaxspeed);
    ApplyServerCvar("sv_maxvelocity", g_cvarSvMaxvelocity);
    ApplyServerCvar("sv_accelerate", g_cvarSvAccelerate);
    ApplyServerCvar("sv_friction", g_cvarSvFriction);
    ApplyServerCvar("sv_stopspeed", g_cvarSvStopspeed);
    ApplyServerCvar("sv_airmove", g_cvarSvAirmove);
    ApplyServerCvar("edgefriction", g_cvarEdgeFriction);
    ApplyServerCvar("mp_freezetime", g_cvarMpFreezetime);
    ApplyServerCvar("mp_roundtime", g_cvarMpRoundtime);

    server_cmd("mp_limitteams 0");
    server_cmd("mp_autoteambalance 0");
    server_cmd("humans_join_team CT");
}

stock ApplyServerCvar(const serverCvar[], pluginCvar)
{
    new value[32];
    get_pcvar_string(pluginCvar, value, charsmax(value));
    server_cmd("%s %s", serverCvar, value);
}

public TaskCreateRoundKeeper()
{
    if (!get_pcvar_num(g_cvarRoundKeeperBot))
    {
        return;
    }

    if (g_keeperBot && is_user_connected(g_keeperBot))
    {
        SyncRoundKeeperName();
        HideRoundKeeper();
        return;
    }

    new keeperName[32];
    GetRoundKeeperName(keeperName, charsmax(keeperName));

    g_keeperBot = engfunc(EngFunc_CreateFakeClient, keeperName);
    if (!g_keeperBot)
    {
        log_amx("[TIMER] Could not create round keeper bot.");
        return;
    }

    new rejectReason[128];
    dllfunc(DLLFunc_ClientConnect, g_keeperBot, keeperName, "127.0.0.1", rejectReason);
    dllfunc(DLLFunc_ClientPutInServer, g_keeperBot);

    set_pev(g_keeperBot, pev_flags, pev(g_keeperBot, pev_flags) | FL_FAKECLIENT);
    cs_set_user_team(g_keeperBot, CS_TEAM_CT, CS_CT_SAS);
    ExecuteHamB(Ham_CS_RoundRespawn, g_keeperBot);
    HideRoundKeeper();

    TimerSetTask(2.0, "TaskMaintainRoundKeeper", TASK_KEEPER, true);
}

public TaskMaintainRoundKeeper()
{
    if (!get_pcvar_num(g_cvarRoundKeeperBot))
    {
        return;
    }

    if (!g_keeperBot || !is_user_connected(g_keeperBot))
    {
        remove_task(TASK_KEEPER);
        TimerSetTask(1.0, "TaskCreateRoundKeeper");
        return;
    }

    if (cs_get_user_team(g_keeperBot) != CS_TEAM_CT)
    {
        cs_set_user_team(g_keeperBot, CS_TEAM_CT, CS_CT_SAS);
    }

    if (!is_user_alive(g_keeperBot))
    {
        ExecuteHamB(Ham_CS_RoundRespawn, g_keeperBot);
    }

    SyncRoundKeeperName();
    HideRoundKeeper();
}

stock GetRoundKeeperName(output[], len)
{
    get_pcvar_string(g_cvarRoundKeeperName, output, len);
    trim(output);
    if (!output[0])
    {
        copy(output, len, "Bhop Keeper");
    }
}

stock SyncRoundKeeperName()
{
    if (!g_keeperBot || !is_user_connected(g_keeperBot))
    {
        return;
    }

    new keeperName[32], currentName[32];
    GetRoundKeeperName(keeperName, charsmax(keeperName));
    get_user_name(g_keeperBot, currentName, charsmax(currentName));
    if (!equal(currentName, keeperName))
    {
        set_user_info(g_keeperBot, "name", keeperName);
    }
}

stock HideRoundKeeper()
{
    if (!g_keeperBot || !is_user_connected(g_keeperBot))
    {
        return;
    }

    new Float:origin[3];
    origin[0] = 8192.0;
    origin[1] = 8192.0;
    origin[2] = -8192.0;

    engfunc(EngFunc_SetOrigin, g_keeperBot, origin);
    set_pev(g_keeperBot, pev_effects, pev(g_keeperBot, pev_effects) | EF_NODRAW);
    set_pev(g_keeperBot, pev_solid, SOLID_NOT);
    set_pev(g_keeperBot, pev_movetype, MOVETYPE_NOCLIP);
    set_pev(g_keeperBot, pev_takedamage, DAMAGE_NO);
    set_pev(g_keeperBot, pev_health, 9999.0);
}

stock RespawnPlayerIfNeeded(id)
{
    if (!is_user_connected(id) || cs_get_user_team(id) != CS_TEAM_CT || is_user_alive(id))
    {
        return;
    }

    ForceRespawnPlayer(id);
}

stock bool:ForceRespawnPlayer(id)
{
    if (!is_user_connected(id))
    {
        return false;
    }

    ForcePlayerCtClass(id);

    set_pev(id, pev_iuser1, 0);
    set_pev(id, pev_iuser2, 0);
    set_pev(id, pev_iuser3, 0);
    set_pev(id, pev_deadflag, DEAD_RESPAWNABLE);
    set_pev(id, pev_movetype, MOVETYPE_WALK);

    ExecuteHamB(Ham_CS_RoundRespawn, id);

    if (!is_user_alive(id))
    {
        dllfunc(DLLFunc_Spawn, id);
    }

    if (!is_user_alive(id))
    {
        return false;
    }

    set_pev(id, pev_deadflag, DEAD_NO);
    set_pev(id, pev_movetype, MOVETYPE_WALK);
    set_pev(id, pev_solid, SOLID_SLIDEBOX);
    set_pev(id, pev_effects, pev(id, pev_effects) & ~EF_NODRAW);

    ApplyPlayerProtections(id);
    UpdatePlayerHudVisibility(id);
    ApplyAdminGlow(id);
    return true;
}

stock bool:EnsurePlayerAliveForTeleport(id)
{
    if (!is_user_connected(id))
    {
        return false;
    }

    if (is_user_alive(id))
    {
        return true;
    }

    AutoJoinCt(id);
    return ForceRespawnPlayer(id);
}

stock bool:TeleportToStart(id, bool:announce)
{
    if (!g_zoneLoaded[ZONE_START])
    {
        TimerChat(id, "Start zone is not configured.");
        return false;
    }

    if (!is_user_alive(id))
    {
        EnsurePlayerAliveForTeleport(id);
    }

    if (!is_user_alive(id))
    {
        TimerChat(id, "You are not alive. Could not teleport to start.");
        return false;
    }

    new Float:origin[3];
    GetStartTeleportOrigin(origin);

    new Float:zero[3];
    set_pev(id, pev_velocity, zero);
    set_pev(id, pev_basevelocity, zero);
    engfunc(EngFunc_SetOrigin, id, origin);
    ApplyPlayerProtections(id);

    ResetToStart(id, false);
    g_prevInStart[id] = true;
    g_prevInFinish[id] = false;

    if (announce)
    {
        TimerChat(id, "Teleported to start.");
    }

    return true;
}

stock GetTimerStateText(id, output[], len)
{
    switch (g_timerState[id])
    {
        case TIMER_IN_START:
        {
            copy(output, len, "State: Ready");
        }
        case TIMER_RUNNING:
        {
            copy(output, len, "State: Running");
        }
        case TIMER_FINISHED:
        {
            copy(output, len, "State: Finished");
        }
        default:
        {
            copy(output, len, "State: Go /start");
        }
    }
}

stock TimerChat(id, const fmt[], any:...)
{
    new message[192], finalMessage[192], prefix[32];
    vformat(message, charsmax(message), fmt, 3);
    get_pcvar_string(g_cvarChatPrefix, prefix, charsmax(prefix));
    formatex(finalMessage, charsmax(finalMessage), "^x04%s^x01 %s", prefix, message);

    if (id)
    {
        SendCustomColorChat(id, id, finalMessage, "TERRORIST");
        return;
    }

    for (new player = 1; player <= MAX_PLAYERS; player++)
    {
        if (is_user_connected(player))
        {
            SendCustomColorChat(player, player, finalMessage, "TERRORIST");
        }
    }
}

stock ScheduleNextAdvertisement()
{
    remove_task(TASK_ADVERTISE);

    new Float:interval = get_pcvar_float(g_cvarAdsInterval);
    if (interval < 30.0)
    {
        interval = 30.0;
    }

    TimerSetTask(interval, "TaskAdvertise", TASK_ADVERTISE);
}

public TaskAdvertise()
{
    if (get_pcvar_num(g_cvarAdsEnabled))
    {
        new message[160];
        for (new attempt = 0; attempt < MAX_AD_MESSAGES; attempt++)
        {
            new index = (g_nextAdvertisement + attempt) % MAX_AD_MESSAGES;
            get_pcvar_string(g_cvarAdText[index], message, charsmax(message));
            trim(message);
            if (message[0])
            {
                TimerChat(0, "%s", message);
                g_nextAdvertisement = (index + 1) % MAX_AD_MESSAGES;
                break;
            }
        }
    }

    ScheduleNextAdvertisement();
}

stock SendColorMessage(id, const message[])
{
    if (!g_msgSayText || !is_user_connected(id))
    {
        return;
    }

    message_begin(MSG_ONE_UNRELIABLE, g_msgSayText, _, id);
    write_byte(id);
    write_string(message);
    message_end();
}

stock bool:HasZoneAccess(id)
{
    if (!id)
    {
        return true;
    }

    new flagText[16];
    get_pcvar_string(g_cvarAdminFlag, flagText, charsmax(flagText));

    new flags = read_flags(flagText);
    if (!flags)
    {
        return true;
    }

    return (get_user_flags(id) & flags) != 0;
}

stock FormatTimeMs(timeMs, output[], len)
{
    if (timeMs < 0)
    {
        timeMs = 0;
    }

    new minutes = timeMs / 60000;
    new seconds = (timeMs / 1000) % 60;
    new millis = timeMs % 1000;

    formatex(output, len, "%02d:%02d.%03d", minutes, seconds, millis);
}

stock GetMapNameForMode(mode, output[], len)
{
    if (mode == 1) // Low Gravity
    {
        formatex(output, len, "%s_lowgrav", g_mapName);
    }
    else if (mode == 2) // Double Jump
    {
        formatex(output, len, "%s_dbjump", g_mapName);
    }
    else
    {
        copy(output, len, g_mapName);
    }
}

stock GetModeName(mode, output[], len)
{
    switch (mode)
    {
        case 1: copy(output, len, "Low Gravity");
        case 2: copy(output, len, "Double Jump");
        default: copy(output, len, "Normal");
    }
}

stock GetModeUrlParam(mode, output[], len)
{
    switch (mode)
    {
        case 1: copy(output, len, "lowgrav");
        case 2: copy(output, len, "dbjump");
        default: copy(output, len, "normal");
    }
}

public CmdBhopModeMenu(id)
{
    if (!is_user_connected(id))
    {
        return PLUGIN_HANDLED;
    }

    new menu = menu_create("Bhop Timer Mode Selection", "BhopModeMenuHandler");

    new itemText[64];
    formatex(itemText, charsmax(itemText), "Normal Mode %s", (g_playerMode[id] == MODE_NORMAL) ? "\y[Active]" : "");
    menu_additem(menu, itemText);

    formatex(itemText, charsmax(itemText), "Low Gravity Mode %s", (g_playerMode[id] == MODE_LOW_GRAVITY) ? "\y[Active]" : "");
    menu_additem(menu, itemText);

    formatex(itemText, charsmax(itemText), "Double Jump Mode %s", (g_playerMode[id] == MODE_DOUBLE_JUMP) ? "\y[Active]" : "");
    menu_additem(menu, itemText);

    menu_setprop(menu, MPROP_EXIT, MEXIT_ALL);
    menu_display(id, menu, 0);

    return PLUGIN_HANDLED;
}

public BhopModeMenuHandler(id, menu, item)
{
    if (item == MENU_EXIT)
    {
        menu_destroy(menu);
        return PLUGIN_HANDLED;
    }

    if (!is_user_connected(id))
    {
        menu_destroy(menu);
        return PLUGIN_HANDLED;
    }

    new selectedMode = item;
    if (selectedMode == g_playerMode[id])
    {
        new modeName[32];
        GetModeName(selectedMode, modeName, charsmax(modeName));
        TimerChat(id, "%s is already active.", modeName);
        menu_destroy(menu);
        return PLUGIN_HANDLED;
    }

    g_playerMode[id] = selectedMode;
    g_doubleJumped[id] = false;
    g_jumpReleased[id] = false;
    StopPlayerHook(id, false);
    ApplyModeFpsMax(id);

    if (selectedMode == MODE_LOW_GRAVITY)
    {
        set_pev(id, pev_gravity, 0.5);
    }
    else
    {
        set_pev(id, pev_gravity, 1.0);
    }

    ResetPlayerData(id, false);
    LoadPlayerBest(id);
    TeleportToStart(id, false);

    new modeName[32];
    GetModeName(selectedMode, modeName, charsmax(modeName));
    TimerChat(id, "Switched to ^x04%s^x01 mode. Timer reset.", modeName);

    menu_destroy(menu);
    return PLUGIN_HANDLED;
}

stock bool:IsPlayerAdmin(id)
{
    if (!is_user_connected(id))
    {
        return false;
    }
    return (get_user_flags(id) & ~ADMIN_USER) != 0;
}

stock SendCustomColorChat(receiver, sender, const message[], const teamColor[])
{
    if (!is_user_connected(receiver))
    {
        return;
    }

    new msgSayText = get_user_msgid("SayText");
    new msgTeamInfo = get_user_msgid("TeamInfo");

    // 1. Fake the team to the receiver
    message_begin(MSG_ONE_UNRELIABLE, msgTeamInfo, _, receiver);
    write_byte(sender);
    write_string(teamColor);
    message_end();

    // 2. Send the SayText
    message_begin(MSG_ONE_UNRELIABLE, msgSayText, _, receiver);
    write_byte(sender);
    write_string(message);
    message_end();

    // 3. Restore the actual team
    new actualTeam[16];
    new CsTeams:t = cs_get_user_team(sender);
    if (t == CS_TEAM_T)
    {
        copy(actualTeam, charsmax(actualTeam), "TERRORIST");
    }
    else if (t == CS_TEAM_CT)
    {
        copy(actualTeam, charsmax(actualTeam), "CT");
    }
    else if (t == CS_TEAM_SPECTATOR)
    {
        copy(actualTeam, charsmax(actualTeam), "SPECTATOR");
    }
    else
    {
        copy(actualTeam, charsmax(actualTeam), "UNASSIGNED");
    }

    message_begin(MSG_ONE_UNRELIABLE, msgTeamInfo, _, receiver);
    write_byte(sender);
    write_string(actualTeam);
    message_end();
}

public CmdSay(id)
{
    new message[192];
    read_args(message, charsmax(message));
    remove_quotes(message);
    trim(message);

    if (!message[0])
    {
        return PLUGIN_HANDLED;
    }

    if (message[0] == '/' || message[0] == '!')
    {
        return PLUGIN_CONTINUE;
    }

    new name[32], chatMsg[256], prefix[64];
    get_user_name(id, name, charsmax(name));
    GetPlayerWrPrefix(name, prefix, charsmax(prefix));

    new teamColor[16];
    if (IsPlayerAdmin(id))
    {
        formatex(chatMsg, charsmax(chatMsg), "%s^x04%s^x01 :  ^x03%s", prefix, name, message);
        copy(teamColor, charsmax(teamColor), "TERRORIST");
    }
    else
    {
        formatex(chatMsg, charsmax(chatMsg), "%s^x03%s^x01 :  %s", prefix, name, message);
        GetPlayerTeamColorString(id, teamColor, charsmax(teamColor));
    }

    for (new player = 1; player <= MAX_PLAYERS; player++)
    {
        if (is_user_connected(player))
        {
            SendCustomColorChat(player, id, chatMsg, teamColor);
        }
    }
    return PLUGIN_HANDLED;
}

public CmdSayTeam(id)
{
    new message[192];
    read_args(message, charsmax(message));
    remove_quotes(message);
    trim(message);

    if (!message[0])
    {
        return PLUGIN_HANDLED;
    }

    if (message[0] == '/' || message[0] == '!')
    {
        return PLUGIN_CONTINUE;
    }

    new name[32], chatMsg[256], prefix[64];
    get_user_name(id, name, charsmax(name));
    GetPlayerWrPrefix(name, prefix, charsmax(prefix));

    new teamColor[16];
    if (IsPlayerAdmin(id))
    {
        formatex(chatMsg, charsmax(chatMsg), "^x01(TEAM) %s^x04%s^x01 :  ^x03%s", prefix, name, message);
        copy(teamColor, charsmax(teamColor), "TERRORIST");
    }
    else
    {
        formatex(chatMsg, charsmax(chatMsg), "^x01(TEAM) %s^x03%s^x01 :  %s", prefix, name, message);
        GetPlayerTeamColorString(id, teamColor, charsmax(teamColor));
    }

    new CsTeams:senderTeam = cs_get_user_team(id);
    for (new player = 1; player <= MAX_PLAYERS; player++)
    {
        if (is_user_connected(player) && cs_get_user_team(player) == senderTeam)
        {
            SendCustomColorChat(player, id, chatMsg, teamColor);
        }
    }
    return PLUGIN_HANDLED;
}

public UpdateWrHolders()
{
    GetRecordHolderName(MODE_NORMAL, g_wrHolderName[MODE_NORMAL], 31);
    GetRecordHolderName(MODE_LOW_GRAVITY, g_wrHolderName[MODE_LOW_GRAVITY], 31);
    GetRecordHolderName(MODE_DOUBLE_JUMP, g_wrHolderName[MODE_DOUBLE_JUMP], 31);
}

public GetPlayerWrPrefix(const name[], output[], len)
{
    output[0] = '^0';
    if (!name[0]) return;

    new bool:isNormal = (g_wrHolderName[MODE_NORMAL][0] && equal(name, g_wrHolderName[MODE_NORMAL]));
    new bool:isLowGrav = (g_wrHolderName[MODE_LOW_GRAVITY][0] && equal(name, g_wrHolderName[MODE_LOW_GRAVITY]));
    new bool:isDbJump = (g_wrHolderName[MODE_DOUBLE_JUMP][0] && equal(name, g_wrHolderName[MODE_DOUBLE_JUMP]));

    if (isNormal && isLowGrav && isDbJump)
    {
        copy(output, len, "^x04[WR-ALL] ");
    }
    else if (isNormal || isLowGrav || isDbJump)
    {
        new temp[48];
        temp[0] = '^0';
        new count = 0;
        
        if (isNormal)
        {
            add(temp, charsmax(temp), "Normal");
            count++;
        }
        if (isLowGrav)
        {
            if (count > 0) add(temp, charsmax(temp), "/");
            add(temp, charsmax(temp), "LG");
            count++;
        }
        if (isDbJump)
        {
            if (count > 0) add(temp, charsmax(temp), "/");
            add(temp, charsmax(temp), "DJ");
            count++;
        }
        
        formatex(output, len, "^x04[WR-%s] ", temp);
    }
}

public GetPlayerTeamColorString(id, output[], len)
{
    new CsTeams:t = cs_get_user_team(id);
    if (t == CS_TEAM_T) copy(output, len, "TERRORIST");
    else if (t == CS_TEAM_CT) copy(output, len, "CT");
    else if (t == CS_TEAM_SPECTATOR) copy(output, len, "SPECTATOR");
    else copy(output, len, "UNASSIGNED");
}

public CmdDuel(id)
{
    if (!is_user_connected(id)) return PLUGIN_HANDLED;
    
    if (g_duelState[id] != DUEL_STATE_IDLE)
    {
        TimerChat(id, "You are already in a duel or waiting for one.");
        return PLUGIN_HANDLED;
    }

    new menu = menu_create("Bhop Duel Challenge", "DuelMenuHandler");
    new playerCount = 0;
    
    for (new i = 1; i <= MAX_PLAYERS; i++)
    {
        if (is_user_connected(i) && is_user_alive(i) && i != id && !is_user_bot(i))
        {
            new name[32], info[6];
            get_user_name(i, name, charsmax(name));
            num_to_str(i, info, charsmax(info));
            menu_additem(menu, name, info);
            playerCount++;
        }
    }
    
    if (playerCount == 0)
    {
        TimerChat(id, "No active players available to duel.");
        menu_destroy(menu);
        return PLUGIN_HANDLED;
    }
    
    menu_setprop(menu, MPROP_EXIT, MEXIT_ALL);
    menu_display(id, menu, 0);
    return PLUGIN_HANDLED;
}

public DuelMenuHandler(id, menu, item)
{
    if (item == MENU_EXIT)
    {
        menu_destroy(menu);
        return PLUGIN_HANDLED;
    }
    
    new info[6], name[32];
    new access, callback;
    menu_item_getinfo(menu, item, access, info, charsmax(info), name, charsmax(name), callback);
    menu_destroy(menu);
    
    new target = str_to_num(info);
    if (!is_user_connected(target) || !is_user_alive(target))
    {
        TimerChat(id, "The challenged player is no longer available.");
        return PLUGIN_HANDLED;
    }
    
    if (g_duelState[target] != DUEL_STATE_IDLE)
    {
        TimerChat(id, "That player is already in a duel or challenge.");
        return PLUGIN_HANDLED;
    }
    
    g_duelState[id] = DUEL_STATE_WAITING;
    g_duelPartner[id] = target;
    
    g_duelState[target] = DUEL_STATE_WAITING;
    g_duelPartner[target] = id;
    
    new challengerName[32];
    get_user_name(id, challengerName, charsmax(challengerName));
    
    TimerChat(id, "You challenged ^x04%s^x01 to a duel. Waiting for acceptance...", name);
    
    ShowChallengeMenu(target, challengerName);
    return PLUGIN_HANDLED;
}

stock ShowChallengeMenu(id, const challengerName[])
{
    new menuText[96];
    formatex(menuText, charsmax(menuText), "Duel Challenge from %s", challengerName);
    new menu = menu_create(menuText, "ChallengeMenuHandler");
    
    menu_additem(menu, "\yAccept Duel", "1");
    menu_additem(menu, "\rDecline Duel", "2");
    
    menu_setprop(menu, MPROP_EXIT, MEXIT_NEVER);
    menu_display(id, menu, 0);
}

public ChallengeMenuHandler(id, menu, item)
{
    new partner = g_duelPartner[id];
    if (item == 0) // Accept
    {
        menu_destroy(menu);
        if (is_user_connected(partner) && is_user_alive(partner) && is_user_alive(id))
        {
            StartDuel(partner, id);
        }
        else
        {
            TimerChat(id, "Challenger is no longer available.");
            ResetDuelState(id);
            ResetDuelState(partner);
        }
    }
    else // Decline
    {
        menu_destroy(menu);
        TimerChat(id, "You declined the duel.");
        if (is_user_connected(partner))
        {
            new name[32];
            get_user_name(id, name, charsmax(name));
            TimerChat(partner, "^x04%s^x01 declined your duel challenge.", name);
        }
        ResetDuelState(id);
        ResetDuelState(partner);
    }
    return PLUGIN_HANDLED;
}

public CmdAccept(id)
{
    new partner = g_duelPartner[id];
    if (g_duelState[id] == DUEL_STATE_WAITING && g_duelPartner[id] > 0)
    {
        if (is_user_connected(partner) && is_user_alive(partner) && is_user_alive(id))
        {
            StartDuel(partner, id);
        }
        else
        {
            TimerChat(id, "Challenger is no longer available.");
            ResetDuelState(id);
            ResetDuelState(partner);
        }
    }
    else
    {
        TimerChat(id, "You do not have any pending duel challenges.");
    }
    return PLUGIN_HANDLED;
}

stock StartDuel(challenger, opponent)
{
    if (!g_zoneLoaded[ZONE_START])
    {
        TimerChat(challenger, "Start zone is not configured. Cannot start duel.");
        TimerChat(opponent, "Start zone is not configured. Cannot start duel.");
        ResetDuelState(challenger);
        ResetDuelState(opponent);
        return;
    }

    g_duelState[challenger] = DUEL_STATE_COUNTDOWN;
    g_duelState[opponent] = DUEL_STATE_COUNTDOWN;

    StopPlayerHook(challenger, false);
    StopPlayerHook(opponent, false);

    ResetPlayerData(challenger, false);
    ResetPlayerData(opponent, false);

    new Float:origin[3];
    GetStartTeleportOrigin(origin);

    new Float:zero[3];
    set_pev(challenger, pev_velocity, zero);
    set_pev(challenger, pev_basevelocity, zero);
    set_pev(opponent, pev_velocity, zero);
    set_pev(opponent, pev_basevelocity, zero);

    engfunc(EngFunc_SetOrigin, challenger, origin);
    engfunc(EngFunc_SetOrigin, opponent, origin);

    set_pev(challenger, pev_flags, pev(challenger, pev_flags) | FL_FROZEN);
    set_pev(opponent, pev_flags, pev(opponent, pev_flags) | FL_FROZEN);

    g_duelCountdownTime[challenger] = 3;
    g_duelCountdownTime[opponent] = 3;

    new challengerName[32], opponentName[32];
    get_user_name(challenger, challengerName, charsmax(challengerName));
    get_user_name(opponent, opponentName, charsmax(opponentName));

    TimerChat(0, "^x04[DUEL]^x01 ^x04%s^x01 and ^x04%s^x01 are starting a BHOP DUEL!", challengerName, opponentName);

    TimerSetTask(1.0, "TaskDuelCountdown", challenger);
    TimerSetTask(1.0, "TaskDuelCountdown", opponent);
}

public TaskDuelCountdown(taskid)
{
    new id = taskid;
    if (!is_user_connected(id) || !is_user_alive(id) || g_duelState[id] != DUEL_STATE_COUNTDOWN)
    {
        return;
    }

    new count = g_duelCountdownTime[id];

    if (count > 0)
    {
        set_hudmessage(255, 80, 80, -1.0, 0.35, 0, 0.0, 1.0, 0.0, 0.0, 3);
        show_hudmessage(id, "%d", count);
        client_cmd(id, "spk buttons/lightswitch2");
        
        g_duelCountdownTime[id]--;
        TimerSetTask(1.0, "TaskDuelCountdown", id);
    }
    else
    {
        set_hudmessage(80, 255, 80, -1.0, 0.35, 0, 0.0, 1.5, 0.0, 0.0, 3);
        show_hudmessage(id, "GO!");
        client_cmd(id, "spk buttons/bell1");

        set_pev(id, pev_flags, pev(id, pev_flags) & ~FL_FROZEN);

        g_duelState[id] = DUEL_STATE_RACING;
        StartTimer(id);
    }
}

stock ResetDuelState(id)
{
    g_duelState[id] = DUEL_STATE_IDLE;
    g_duelPartner[id] = 0;
    g_duelCountdownTime[id] = 0;
    
    if (is_user_connected(id))
    {
        set_pev(id, pev_flags, pev(id, pev_flags) & ~FL_FROZEN);
        ResetPlayerData(id, false);
    }
}

stock BuildReplayPath(mode, output[], len)
{
    new dataDir[128];
    get_datadir(dataDir, charsmax(dataDir));

    new modeSuffix[32];
    if (mode == 1) // Low Gravity
    {
        copy(modeSuffix, charsmax(modeSuffix), "lowgrav");
    }
    else if (mode == 2) // Double Jump
    {
        copy(modeSuffix, charsmax(modeSuffix), "dbjump");
    }
    else
    {
        copy(modeSuffix, charsmax(modeSuffix), "normal");
    }

    formatex(output, len, "%s/bhop_timer_%s_%s_replay.rec", dataDir, g_mapName, modeSuffix);
}

stock bool:LoadReplayFile(mode)
{
    g_botReplayTotalFrames = 0;
    g_botPlaybackFrame = 0;
    g_lastPlaybackTime = 0.0;

    new path[192];
    BuildReplayPath(mode, path, charsmax(path));

    if (!file_exists(path))
    {
        return false;
    }

    new fileSize = file_size(path);

    new fp = fopen(path, "rb");
    if (!fp)
    {
        return false;
    }

    fread(fp, g_botReplayTotalFrames, BLOCK_INT);

    if (g_botReplayTotalFrames <= 0 || g_botReplayTotalFrames > MAX_REPLAY_FRAMES)
    {
        fclose(fp);
        g_botReplayTotalFrames = 0;
        return false;
    }

    static Float:tempBuf[MAX_REPLAY_FRAMES * 3];
    fread_blocks(fp, any:tempBuf, g_botReplayTotalFrames * 3, BLOCK_INT);
    new idx = 0;
    for (new i = 0; i < g_botReplayTotalFrames; i++)
    {
        g_botReplayOrigin[i][0] = tempBuf[idx++];
        g_botReplayOrigin[i][1] = tempBuf[idx++];
        g_botReplayOrigin[i][2] = tempBuf[idx++];
    }

    fread_blocks(fp, any:tempBuf, g_botReplayTotalFrames * 3, BLOCK_INT);
    idx = 0;
    for (new i = 0; i < g_botReplayTotalFrames; i++)
    {
        g_botReplayAngles[i][0] = tempBuf[idx++];
        g_botReplayAngles[i][1] = tempBuf[idx++];
        g_botReplayAngles[i][2] = tempBuf[idx++];
    }

    // Load ducking flags with backward compatibility
    static tempDuckingBuf[MAX_REPLAY_FRAMES];
    for (new i = 0; i < g_botReplayTotalFrames; i++)
    {
        tempDuckingBuf[i] = 0;
    }
    new readCount = fread_blocks(fp, tempDuckingBuf, g_botReplayTotalFrames, BLOCK_INT);
    for (new i = 0; i < g_botReplayTotalFrames; i++)
    {
        g_botReplayDucking[i] = (readCount > 0 && tempDuckingBuf[i] == 1) ? true : false;
    }

    fclose(fp);

    // Detect recording interval from file size:
    // Old file: 4 (frameCount) + frameCount * 24 (origin(12) + angles(12)) bytes
    // New file: 4 (frameCount) + frameCount * 28 (origin(12) + angles(12) + ducking(4)) bytes
    if (fileSize == 4 + g_botReplayTotalFrames * 24)
    {
        g_botPlaybackInterval = 0.04;
    }
    else
    {
        g_botPlaybackInterval = 0.01;
    }

    return true;
}

stock GetRecordHolderName(mode, outputName[], len)
{
    copy(outputName, len, "No Record");

    new count = LoadBestFile(mode);
    if (count > 0)
    {
        SortBestCache(count);
        copy(outputName, len, g_fileName[0]);
    }
}

stock GetRecordTime(mode)
{
    new timeMs = 0;

    new count = LoadBestFile(mode);
    if (count > 0)
    {
        SortBestCache(count);
        timeMs = g_fileTime[0];
    }

    return timeMs;
}

stock MaintainReplayBot()
{
    new holderName[32], botName[32];
    GetRecordHolderName(g_botReplayMode, holderName, charsmax(holderName));
    new modeLabel[16];
    if (g_botReplayMode == 1) copy(modeLabel, charsmax(modeLabel), "LG");
    else if (g_botReplayMode == 2) copy(modeLabel, charsmax(modeLabel), "DJ");
    else copy(modeLabel, charsmax(modeLabel), "Normal");
    formatex(botName, charsmax(botName), "[WR-%s] %s", modeLabel, holderName);

    if (g_replayBot && is_user_connected(g_replayBot))
    {
        new currentName[32];
        get_user_name(g_replayBot, currentName, charsmax(currentName));
        if (!equal(currentName, botName))
        {
            set_user_info(g_replayBot, "name", botName);
        }

        if (!is_user_alive(g_replayBot))
        {
            ExecuteHamB(Ham_CS_RoundRespawn, g_replayBot);
        }

        set_pev(g_replayBot, pev_effects, 0);
        set_pev(g_replayBot, pev_solid, SOLID_NOT);
        set_pev(g_replayBot, pev_movetype, MOVETYPE_NOCLIP);
        set_pev(g_replayBot, pev_takedamage, DAMAGE_NO);
        set_pev(g_replayBot, pev_health, 99999.0);

        if (cs_get_user_team(g_replayBot) != CS_TEAM_CT)
        {
            cs_set_user_team(g_replayBot, CS_TEAM_CT, CS_CT_SAS);
        }
        return;
    }

    g_replayBot = engfunc(EngFunc_CreateFakeClient, botName);
    if (!g_replayBot)
    {
        log_amx("[TIMER] Could not create WR bot.");
        return;
    }

    new rejectReason[128];
    dllfunc(DLLFunc_ClientConnect, g_replayBot, botName, "127.0.0.1", rejectReason);
    dllfunc(DLLFunc_ClientPutInServer, g_replayBot);

    set_pev(g_replayBot, pev_flags, pev(g_replayBot, pev_flags) | FL_FAKECLIENT);
    cs_set_user_team(g_replayBot, CS_TEAM_CT, CS_CT_SAS);
    ExecuteHamB(Ham_CS_RoundRespawn, g_replayBot);

    set_pev(g_replayBot, pev_solid, SOLID_NOT);
    set_pev(g_replayBot, pev_movetype, MOVETYPE_NOCLIP);
    set_pev(g_replayBot, pev_takedamage, DAMAGE_NO);
    set_pev(g_replayBot, pev_health, 99999.0);
}

stock KickReplayBot()
{
    if (g_replayBot && is_user_connected(g_replayBot))
    {
        server_cmd("kick #%d", get_user_userid(g_replayBot));
        g_replayBot = 0;
    }
}

public TaskCreateReplayBot(taskid)
{
    #pragma unused taskid

    MaintainReplayBot();
}

public PlaybackBotFrame()
{
    if (!g_replayBot || !is_user_connected(g_replayBot) || !is_user_alive(g_replayBot))
    {
        return;
    }

    if (g_botReplayTotalFrames <= 0)
    {
        if (g_zoneLoaded[ZONE_START])
        {
            new Float:origin[3];
            GetStartTeleportOrigin(origin);
            engfunc(EngFunc_SetOrigin, g_replayBot, origin);
        }
        return;
    }

    new Float:currentTime = get_gametime();
    new Float:elapsedTime = currentTime - g_lastPlaybackTime;

    // Check if we need to advance to the next frame
    if (elapsedTime >= g_botPlaybackInterval)
    {
        g_botPlaybackFrame++;
        if (g_botPlaybackFrame >= g_botReplayTotalFrames)
        {
            g_botPlaybackFrame = 0;
        }
        g_lastPlaybackTime = currentTime;
        elapsedTime = 0.0;
    }

    // Determine current and next frame indices
    new currentFrame = g_botPlaybackFrame;
    new nextFrame = currentFrame + 1;
    if (nextFrame >= g_botReplayTotalFrames)
    {
        nextFrame = 0;
    }

    // Calculate interpolation factor t (clamped to [0.0, 1.0])
    new Float:t = elapsedTime / g_botPlaybackInterval;
    if (t < 0.0) t = 0.0;
    if (t > 1.0) t = 1.0;

    // Interpolated origin
    new Float:origin[3];
    origin[0] = g_botReplayOrigin[currentFrame][0] + t * (g_botReplayOrigin[nextFrame][0] - g_botReplayOrigin[currentFrame][0]);
    origin[1] = g_botReplayOrigin[currentFrame][1] + t * (g_botReplayOrigin[nextFrame][1] - g_botReplayOrigin[currentFrame][1]);
    origin[2] = g_botReplayOrigin[currentFrame][2] + t * (g_botReplayOrigin[nextFrame][2] - g_botReplayOrigin[currentFrame][2]);

    // Interpolated view angles
    new Float:angles[3];
    // Pitch (no wrap-around, range is -90 to 90)
    angles[0] = g_botReplayAngles[currentFrame][0] + t * (g_botReplayAngles[nextFrame][0] - g_botReplayAngles[currentFrame][0]);
    
    // Yaw (wrap-around handling)
    new Float:diffYaw = g_botReplayAngles[nextFrame][1] - g_botReplayAngles[currentFrame][1];
    while (diffYaw < -180.0) diffYaw += 360.0;
    while (diffYaw > 180.0) diffYaw -= 360.0;
    angles[1] = g_botReplayAngles[currentFrame][1] + t * diffYaw;
    
    // Roll (no wrap-around)
    angles[2] = g_botReplayAngles[currentFrame][2] + t * (g_botReplayAngles[nextFrame][2] - g_botReplayAngles[currentFrame][2]);

    // Update bot location
    engfunc(EngFunc_SetOrigin, g_replayBot, origin);

    new Float:viewAngles[3];
    viewAngles[0] = get_pcvar_num(g_cvarReplayPitchInvert) ? -angles[0] : angles[0];
    if (viewAngles[0] > 89.0) viewAngles[0] = 89.0;
    if (viewAngles[0] < -89.0) viewAngles[0] = -89.0;
    viewAngles[1] = angles[1];
    viewAngles[2] = 0.0;

    new replayButtons = g_botReplayDucking[currentFrame] ? IN_DUCK : 0;

    // Feed the recorded view through the same path as a real player's usercmd.
    // Directly forcing pev_angles makes GoldSrc spectators over/under-shoot pitch.
    engfunc(EngFunc_RunPlayerMove, g_replayBot, viewAngles, 0.0, 0.0, 0.0, replayButtons, 0, 1);
    engfunc(EngFunc_SetOrigin, g_replayBot, origin);
    set_pev(g_replayBot, pev_v_angle, viewAngles);
    set_pev(g_replayBot, pev_fixangle, 0);

    // Visually update the bot's head pitch (controller 1) in 3rd person
    set_pev(g_replayBot, pev_controller_1, clamp(floatround(((viewAngles[0] + 90.0) / 180.0) * 255.0), 0, 255));

    // Update bot crouching/ducking state
    if (g_botReplayDucking[currentFrame])
    {
        set_pev(g_replayBot, pev_flags, pev(g_replayBot, pev_flags) | FL_DUCKING);
        set_pev(g_replayBot, pev_button, pev(g_replayBot, pev_button) | IN_DUCK);
        
        new Float:viewOfs[3];
        viewOfs[0] = 0.0;
        viewOfs[1] = 0.0;
        viewOfs[2] = 12.0;
        set_pev(g_replayBot, pev_view_ofs, viewOfs);
    }
    else
    {
        set_pev(g_replayBot, pev_flags, pev(g_replayBot, pev_flags) & ~FL_DUCKING);
        set_pev(g_replayBot, pev_button, pev(g_replayBot, pev_button) & ~IN_DUCK);
        
        new Float:viewOfs[3];
        viewOfs[0] = 0.0;
        viewOfs[1] = 0.0;
        viewOfs[2] = 17.0;
        set_pev(g_replayBot, pev_view_ofs, viewOfs);
    }
}

public CmdSpec(id)
{
    if (!is_user_connected(id))
    {
        return PLUGIN_HANDLED;
    }

    if (!g_replayBot || !is_user_connected(g_replayBot))
    {
        MaintainReplayBot();
    }

    if (!g_replayBot || !is_user_connected(g_replayBot))
    {
        TimerChat(id, "No WR Bot is active on the server.");
        return PLUGIN_HANDLED;
    }

    if (cs_get_user_team(id) != CS_TEAM_SPECTATOR)
    {
        StopPlayerHook(id, false);
        ResetPlayerData(id, false);
        cs_set_user_team(id, CS_TEAM_SPECTATOR);
        user_silentkill(id);
        set_pev(id, pev_deadflag, DEAD_DEAD); // Bypass tilted head death animation
        TimerSetTask(0.1, "TaskForceSpectateBot", id);
    }
    else
    {
        TaskForceSpectateBot(id);
    }

    TimerChat(id, "Spectating WR Bot. Type ^x04/ct^x01 or ^x04/start^x01 to play again.");
    return PLUGIN_HANDLED;
}

public TaskForceSpectateBot(id)
{
    if (is_user_connected(id) && cs_get_user_team(id) == CS_TEAM_SPECTATOR)
    {
        set_pev(id, pev_deadflag, DEAD_DEAD); // Ensure DEAD_DEAD is set so spectatorship initializes instantly
        if (g_replayBot && is_user_connected(g_replayBot))
        {
            set_pev(id, pev_iuser1, 4);
            set_pev(id, pev_iuser2, g_replayBot);
        }
    }
}

public CmdCt(id)
{
    if (!is_user_connected(id))
    {
        return PLUGIN_HANDLED;
    }

    if (cs_get_user_team(id) == CS_TEAM_SPECTATOR)
    {
        StopPlayerHook(id, false);
        ForcePlayerCtClass(id);
        ScheduleEnsureCtSpawn(id, 0.1, true);
        TimerSetTask(0.4, "TaskSpawnAndTeleport", id);
    }
    else
    {
        StopPlayerHook(id, false);
        TeleportToStart(id, true);
    }

    return PLUGIN_HANDLED;
}

public TaskSpawnAndTeleport(id)
{
    if (is_user_connected(id))
    {
        if (EnsurePlayerAliveForTeleport(id))
        {
            TeleportToStart(id, true);
            return;
        }

        ScheduleEnsureCtSpawn(id, 0.5, false);
    }
}

public CmdBhopReplayMenu(id)
{
    if (!is_user_connected(id))
    {
        return PLUGIN_HANDLED;
    }

    MaintainReplayBot();

    new menu = menu_create("Bhop Replay Bot Control", "BhopReplayMenuHandler");

    new itemText[96], timeText[32];

    // Normal Mode
    new normalTime = GetRecordTime(MODE_NORMAL);
    if (normalTime > 0) FormatTimeMs(normalTime, timeText, charsmax(timeText));
    else copy(timeText, charsmax(timeText), "No Record");
    formatex(itemText, charsmax(itemText), "Watch Normal Mode Record [%s] %s", timeText, (g_botReplayMode == MODE_NORMAL) ? "\y[Active]" : "");
    menu_additem(menu, itemText);

    // Low Gravity Mode
    new lowgravTime = GetRecordTime(MODE_LOW_GRAVITY);
    if (lowgravTime > 0) FormatTimeMs(lowgravTime, timeText, charsmax(timeText));
    else copy(timeText, charsmax(timeText), "No Record");
    formatex(itemText, charsmax(itemText), "Watch Low Gravity Record [%s] %s", timeText, (g_botReplayMode == MODE_LOW_GRAVITY) ? "\y[Active]" : "");
    menu_additem(menu, itemText);

    // Double Jump Mode
    new dbjumpTime = GetRecordTime(MODE_DOUBLE_JUMP);
    if (dbjumpTime > 0) FormatTimeMs(dbjumpTime, timeText, charsmax(timeText));
    else copy(timeText, charsmax(timeText), "No Record");
    formatex(itemText, charsmax(itemText), "Watch Double Jump Record [%s] %s", timeText, (g_botReplayMode == MODE_DOUBLE_JUMP) ? "\y[Active]" : "");
    menu_additem(menu, itemText);

    menu_setprop(menu, MPROP_EXIT, MEXIT_ALL);
    menu_display(id, menu, 0);

    return PLUGIN_HANDLED;
}

public BhopReplayMenuHandler(id, menu, item)
{
    if (item == MENU_EXIT)
    {
        menu_destroy(menu);
        return PLUGIN_HANDLED;
    }

    if (!is_user_connected(id))
    {
        menu_destroy(menu);
        return PLUGIN_HANDLED;
    }

    new selectedMode = item;
    if (selectedMode == g_botReplayMode)
    {
        TimerChat(id, "Replay bot is already playing this mode's record.");
        menu_destroy(menu);
        if (is_user_connected(id))
        {
            CmdBhopReplayMenu(id);
        }
        return PLUGIN_HANDLED;
    }

    g_botReplayMode = selectedMode;
    LoadReplayFile(selectedMode);
    MaintainReplayBot();

    new modeName[32];
    GetModeName(selectedMode, modeName, charsmax(modeName));

    if (g_botReplayTotalFrames > 0)
    {
        TimerChat(0, "WR Bot changed to play ^x04%s^x01 mode record.", modeName);
    }
    else
    {
        TimerChat(0, "WR Bot mode changed to ^x04%s^x01 (No record exists yet).", modeName);
    }

    menu_destroy(menu);
    if (is_user_connected(id))
    {
        CmdBhopReplayMenu(id);
    }
    return PLUGIN_HANDLED;
}

public CmdNoclip(id)
{
    if (!is_user_connected(id))
    {
        return PLUGIN_HANDLED;
    }

    if (g_duelState[id] != DUEL_STATE_IDLE)
    {
        TimerChat(id, "Noclip is disabled during a duel.");
        return PLUGIN_HANDLED;
    }

    if (!HasZoneAccess(id))
    {
        TimerChat(id, "You do not have access to noclip.");
        return PLUGIN_HANDLED;
    }

    new movetype = pev(id, pev_movetype);
    StopPlayerHook(id, false);

    if (movetype == MOVETYPE_NOCLIP)
    {
        set_pev(id, pev_movetype, MOVETYPE_WALK);
        TimerChat(id, "Noclip disabled.");
    }
    else
    {
        set_pev(id, pev_movetype, MOVETYPE_NOCLIP);
        ResetPlayerData(id, false); // Instantly abort run and timer
        TimerChat(id, "Noclip enabled. Timer disabled.");
    }

    return PLUGIN_HANDLED;
}

public FwHamTakeDamage(victim, inflictor, attacker, Float:damage, damagebits)
{
    // Supercede all damage to prevent any injury, including fall damage!
    return HAM_SUPERCEDE;
}

public FwAddToFullPack(es_handle, e, ent, host, hostflags, player, pSet)
{
    if (!(1 <= host <= MAX_PLAYERS) || !is_user_connected(host))
    {
        return FMRES_IGNORED;
    }

    if (player)
    {
        if (ent != host && ent <= MAX_PLAYERS && g_fpsHidePlayers[host])
        {
            set_es(es_handle, ES_Effects, get_es(es_handle, ES_Effects) | EF_NODRAW);
            return FMRES_HANDLED;
        }
    }
    else if (g_fpsHideWater[host] && pev_valid(ent) && IsWaterEntity(ent))
    {
        set_es(es_handle, ES_Effects, get_es(es_handle, ES_Effects) | EF_NODRAW);
        return FMRES_HANDLED;
    }

    return FMRES_IGNORED;
}

public MsgHideWeapon(msgid, dest, id)
{
    if (is_user_connected(id) && g_fpsHideHud[id])
    {
        set_msg_arg_int(1, ARG_BYTE, (1<<0) | (1<<2) | (1<<3) | (1<<4) | (1<<5));
    }
}

public EventCurWeapon(id)
{
    if (is_user_alive(id) && g_fpsHideWeapon[id])
    {
        set_pev(id, pev_viewmodel2, "");
        set_pev(id, pev_weaponmodel2, "");
    }
}

public UpdatePlayerHudVisibility(id)
{
    if (!is_user_connected(id))
    {
        return;
    }

    new flags = 0;
    if (g_fpsHideHud[id])
    {
        flags = (1<<0) | (1<<2) | (1<<3) | (1<<4) | (1<<5);
    }

    message_begin(MSG_ONE_UNRELIABLE, get_user_msgid("HideWeapon"), _, id);
    write_byte(flags);
    message_end();
}

public CmdFpsMenu(id)
{
    if (!is_user_connected(id))
    {
        return PLUGIN_HANDLED;
    }

    new menu = menu_create("Bhop FPS / Client Settings", "FpsMenuHandler");
    new itemText[96];
    new label[24];

    formatex(itemText, charsmax(itemText), "Hide Other Players %s", g_fpsHidePlayers[id] ? "\y[ON]" : "\d[OFF]");
    menu_additem(menu, itemText);

    formatex(itemText, charsmax(itemText), "Hide Timer Text %s", g_fpsHideText[id] ? "\y[ON]" : "\d[OFF]");
    menu_additem(menu, itemText);

    formatex(itemText, charsmax(itemText), "Hide Weapon/Hand Model %s", g_fpsHideWeapon[id] ? "\y[ON]" : "\d[OFF]");
    menu_additem(menu, itemText);

    formatex(itemText, charsmax(itemText), "Hide Game HUD Elements %s", g_fpsHideHud[id] ? "\y[ON]" : "\d[OFF]");
    menu_additem(menu, itemText);

    formatex(itemText, charsmax(itemText), "Hide Water Entities %s", g_fpsHideWater[id] ? "\y[ON]" : "\d[OFF]");
    menu_additem(menu, itemText);

    GetBrightnessLabel(g_fpsBrightnessLevel[id], label, charsmax(label));
    formatex(itemText, charsmax(itemText), "Brightness Profile \y[%s]", label);
    menu_additem(menu, itemText);

    GetSoundLabel(g_fpsSoundLevel[id], label, charsmax(label));
    formatex(itemText, charsmax(itemText), "Sound Profile \y[%s]", label);
    menu_additem(menu, itemText);

    menu_additem(menu, "Reset FPS Settings");

    menu_setprop(menu, MPROP_EXIT, MEXIT_ALL);
    menu_display(id, menu, 0);

    return PLUGIN_HANDLED;
}

public FpsMenuHandler(id, menu, item)
{
    if (item == MENU_EXIT)
    {
        menu_destroy(menu);
        return PLUGIN_HANDLED;
    }

    if (!is_user_connected(id))
    {
        menu_destroy(menu);
        return PLUGIN_HANDLED;
    }

    switch (item)
    {
        case 0:
        {
            g_fpsHidePlayers[id] = !g_fpsHidePlayers[id];
        }
        case 1:
        {
            g_fpsHideText[id] = !g_fpsHideText[id];
        }
        case 2:
        {
            g_fpsHideWeapon[id] = !g_fpsHideWeapon[id];
            if (is_user_alive(id))
            {
                if (g_fpsHideWeapon[id])
                {
                    set_pev(id, pev_viewmodel2, "");
                    set_pev(id, pev_weaponmodel2, "");
                }
                else
                {
                    client_cmd(id, "weapon_knife; lastinv");
                }
            }
        }
        case 3:
        {
            g_fpsHideHud[id] = !g_fpsHideHud[id];
            UpdatePlayerHudVisibility(id);
        }
        case 4:
        {
            g_fpsHideWater[id] = !g_fpsHideWater[id];
        }
        case 5:
        {
            g_fpsBrightnessLevel[id]++;
            if (g_fpsBrightnessLevel[id] > 2)
            {
                g_fpsBrightnessLevel[id] = 0;
            }
            ApplyBrightnessProfile(id);
        }
        case 6:
        {
            g_fpsSoundLevel[id]++;
            if (g_fpsSoundLevel[id] > 2)
            {
                g_fpsSoundLevel[id] = 0;
            }
            ApplySoundProfile(id);
        }
        case 7:
        {
            ResetFpsSettings(id);
        }
    }

    menu_destroy(menu);
    if (is_user_connected(id))
    {
        CmdFpsMenu(id);
    }
    return PLUGIN_HANDLED;
}

stock bool:IsWaterEntity(ent)
{
    new classname[32];
    pev(ent, pev_classname, classname, charsmax(classname));

    return equal(classname, "func_water") ||
        equal(classname, "env_bubbles") ||
        contain(classname, "water") != -1;
}

stock GetBrightnessLabel(level, output[], len)
{
    switch (level)
    {
        case 1: copy(output, len, "Bright");
        case 2: copy(output, len, "Very Bright");
        default: copy(output, len, "Normal");
    }
}

stock GetSoundLabel(level, output[], len)
{
    switch (level)
    {
        case 1: copy(output, len, "Quiet");
        case 2: copy(output, len, "Mute");
        default: copy(output, len, "Normal");
    }
}

stock ApplyBrightnessProfile(id)
{
    switch (g_fpsBrightnessLevel[id])
    {
        case 1: client_cmd(id, "brightness 2; gamma 3");
        case 2: client_cmd(id, "brightness 3; gamma 4");
        default: client_cmd(id, "brightness 1; gamma 2.5");
    }
}

stock ApplySoundProfile(id)
{
    switch (g_fpsSoundLevel[id])
    {
        case 1: client_cmd(id, "volume 0.25; suitvolume 0; bgmvolume 0");
        case 2: client_cmd(id, "volume 0; suitvolume 0; bgmvolume 0");
        default: client_cmd(id, "volume 0.8; suitvolume 0.25; bgmvolume 1");
    }
}

stock ResetFpsSettings(id)
{
    g_fpsHidePlayers[id] = false;
    g_fpsHideText[id] = false;
    g_fpsHideWeapon[id] = false;
    g_fpsHideHud[id] = false;
    g_fpsHideWater[id] = false;
    g_fpsBrightnessLevel[id] = 0;
    g_fpsSoundLevel[id] = 0;

    UpdatePlayerHudVisibility(id);
    ApplyBrightnessProfile(id);
    ApplySoundProfile(id);

    if (is_user_alive(id))
    {
        client_cmd(id, "weapon_knife; lastinv");
    }
}
