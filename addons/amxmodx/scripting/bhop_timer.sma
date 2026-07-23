#define MAX_PLAYERS       32
#define MAX_NAME_SQL      96
#define MAX_AUTH_SQL      96
#define MAX_MAP_SQL       160

#include <amxmodx>
#include <sqlx>

new g_mapName[64];
new g_cvarHookSpeed;
new bool:g_dbConfigured;
new bool:g_dbReady;
new Handle:g_sqlTuple = Empty_Handle;

#include <amxmisc>
#include <cstrike>
#include <fakemeta>
#include <hamsandwich>
#include <reapi>
#include <xs>
#include <visual>
#include <bmod_menu_style>
#define BMOD_EMBEDDED_ZONES
#include <speedrun_zone_api>
#include <reapi_reunion>
#include <engine>
#include <fun>

forward bool:sr_has_zone_access(player_id);
forward TimerChat(id, const fmt[], any:...);
forward OnStartZoneEnter(zone_entity, id);
forward OnStartZoneLeave(zone_entity, id);
forward OnFinishZoneEnter(zone_entity, id);
forward OnFinishZoneLeave(zone_entity, id);
#include "components/storage.inc"
#include "components/physics.inc"
#include "components/visualization.inc"
#include "components/editor.inc"
#include "components/zone_embedded.inc"

#define plugin_init PhysicsFixesInit
#define TaskRefreshCvars PhysicsFixesRefreshCvars
#define CacheCvars PhysicsFixesCacheCvars
#define client_putinserver PhysicsFixesClientInit
#define client_disconnected PhysicsFixesClientDisconnect
#define FwPlayerPreThink PhysicsFixesPreThink
#define FwPlayerPostThink PhysicsFixesPostThink
#include "components/physics_fixes.inc"
#undef plugin_init
#undef TaskRefreshCvars
#undef CacheCvars
#undef client_putinserver
#undef client_disconnected
#undef FwPlayerPreThink
#undef FwPlayerPostThink

#define plugin_init MpBhopInit
#define plugin_cfg MpBhopCfg
#define plugin_end MpBhopShutdown
#define client_putinserver MpBhopClientInit
#define client_disconnect MpBhopClientDisconnect
#define SetTouch MpBhopSetTouch
#include "components/mpbhop.inc"
#undef plugin_init
#undef plugin_cfg
#undef plugin_end
#undef client_putinserver
#undef client_disconnect
#undef SetTouch

#include "components/strafe_stats.inc"

// Forward declarations for shared helpers used by component includes.
forward QueueSql(const query[]);
forward MysqlEscape(const input[], output[], len);
forward BuildDbDataPath(output[], len, const fileName[]);
forward EconomyGetTotalCredits(id);

#include "components/economy.inc"
#include "components/badges.inc"

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
#define PLUGIN_VERSION "0.4.0"
#define PLUGIN_AUTHOR  "Codex"

#define TASK_HUD       24001
#define TASK_RENDER    24002
#define TASK_AUTOJOIN  24100
#define TASK_START_TP  24200
#define TASK_SPAWN_CT  24300
#define TASK_LOAD_BEST 24500
#define TASK_DB_RETRY  24700
#define TASK_DB_FLUSH  24701
#define TASK_ADVERTISE 24800
#define TASK_REPLAY_BOT 24900
#define TASK_START_MENU 25000
#define TASK_WR_SAVE 25100
#define TASK_FPS_CHECK 25001
#define TASK_MODE_FPS_MAX 25002
#define TASK_MODE_FPS_RETRY 25003
#define TASK_FPS_VERIFY 25200
#define TASK_SCOREBOARD 25300
#define TASK_SPEC_HUD 25400
#define TASK_JOIN_MESSAGE 25500

#define FPS_QUERY_MAX       (1<<0)
#define FPS_QUERY_OVERRIDE  (1<<1)
#define FPS_QUERY_DEVELOPER (1<<2)
#define FPS_QUERY_FILTER    (1<<3)
#define FPS_QUERY_COMPLETE  (FPS_QUERY_MAX | FPS_QUERY_OVERRIDE | FPS_QUERY_DEVELOPER | FPS_QUERY_FILTER)

#define MAX_SPAWN_RETRIES 10
#define EDIT_POINT_COUNT  4
#define MAX_FILE_RECORDS  256
#define MAX_AD_MESSAGES    11
#define TOP_BADGES_PAGE_SIZE 15
#define MAX_ZONE_SHAPE_JSON 2048
#define MAX_ZONE_SHAPE_SQL  4096
#define DB_FLUSH_DELAY      0.25

// StrafeHack Detector
#define PITCH 0
#define YAW 1
#define LEFT 1
#define RIGHT 2
#define m_pPlayer 41
#define XO_CBASEPLAYER 5
#define XO_CBASEPLAYERWEAPON 4
#define LOGFILE "strafehack_detector.log"
#define MIN_LOG_TIME 3.0
#define MAX_BADFRAMES 5
#define MAX_KEYWARNING 5
#if !defined MAX_STRAFES
#define MAX_STRAFES 16
#endif
#define STRAFE_CHECK_TIME 0.2
#define MAX_ANGLE_CHECK 90.0
#define MIN_STRAFE_ANGLE_DIFF 1.0
#define MAX_STRAFE_ANGLE_WARNINGS 15
#define MIN_STRAFE_ANGLE_WARNINGS_TO_LOG 5
#define IGNORE_TIME 0.5

enum _:PLAYER_DATA
{
    m_BadFrame,
    m_Strafes,
    m_WarningStrafeAngle,
    Float:m_fLastStrafeCheck,
    Float:m_fLastWeaponDeploy
};

enum _:LOG_DATA
{
    Float:m_LastForwardMoveLog,
    Float:m_LastSideMoveLog,
    Float:m_LastValueLog,
    Float:m_LastKeyLog,
    Float:m_LastStrafeAngleLog,
    Float:m_LastChatLog,
    m_CountForwardMoveLog,
    m_CountSideMoveLog,
    m_CountValueLog,
    m_CountKeyLog,
    m_CountStrafeAngleLog,
    m_CountChatLog
};

enum _:KEY_IDS { KEY_W, KEY_S, KEY_A, KEY_D };

enum _:BUTTONS_DATA { BUTTON, KEY };

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

#define MENU_NONE           0
#define MENU_BHOP          0
#define MENU_MAIN          1
#define MENU_MARKET        2
#define MENU_BADGES        3
#define MENU_MODE          4
#define MENU_FPS           5
#define MENU_REPLAY        6
#define MENU_DUEL          7
#define MENU_CHALLENGE     8
#define MENU_MODE_NORMAL_FPS 9
#define MENU_DUEL_MODE     10
#define MENU_DUEL_NORMAL_FPS 11
#define MENU_MARKET_SKINS   12
#define MENU_MARKET_SOUNDS  13
#define MENU_MARKET_MISC    14
#define MENU_MARKET_VIP     15
#define MENU_MARKET_TRAIL   16
#define MENU_TRAIL          17
#define MENU_COUNT          18

#define KEY_ALL_MENU  1023

new g_playerMenuType[MAX_PLAYERS + 1];
new g_playerMenuPage[MAX_PLAYERS + 1];
new g_duelTargets[MAX_PLAYERS + 1][8];
new g_duelPendingTarget[MAX_PLAYERS + 1];

new const g_zoneClasses[ZONE_COUNT][] =
{
    "zone_start",
    "zone_finish"
};

new bool:g_editHasPoint[MAX_PLAYERS + 1][EDIT_POINT_COUNT];
new Float:g_editPoint[MAX_PLAYERS + 1][EDIT_POINT_COUNT][3];

new g_timerState[MAX_PLAYERS + 1];
new bool:g_runRanked[MAX_PLAYERS + 1];
new bool:g_prevInStart[MAX_PLAYERS + 1];
new bool:g_prevInFinish[MAX_PLAYERS + 1];
new Float:g_startGameTime[MAX_PLAYERS + 1];
new g_currentTimeMs[MAX_PLAYERS + 1];
new g_bestTimeMs[MAX_PLAYERS + 1];
new g_lastTimeMs[MAX_PLAYERS + 1];

new g_beamSprite;
new bool:g_playerTrail[MAX_PLAYERS + 1];
new g_playerTrailColor[MAX_PLAYERS + 1][3];
new bool:g_dbTried;
new bool:g_dbInitInFlight;
new bool:g_dbQueueInFlight;
new Float:g_dbRetryBackoff = 1.0;
new g_dbQueueLine = -1;
new g_dbQueueScanLine;
new g_dbSchemaStep;
new g_recordSequence;
new bool:g_internalTeamCommand[MAX_PLAYERS + 1];
new g_spawnRetryCount[MAX_PLAYERS + 1];
new g_fileAuth[MAX_FILE_RECORDS][35];
new g_fileName[MAX_FILE_RECORDS][32];
new g_fileTime[MAX_FILE_RECORDS];
new g_lastPro15File[MAX_PLAYERS + 1][192];

enum
{
    MODE_NORMAL = 0,
    MODE_LOW_GRAVITY,
    MODE_DOUBLE_JUMP,
    MODE_NORMAL_200,
    MODE_NORMAL_333,
    MODE_NORMAL_500,
    MODE_NORMAL_1000,
    MODE_SIMPLE,
    MODE_COUNT
};

new bool:g_bestFileCacheLoaded[MODE_COUNT];
new g_bestFileCacheCount[MODE_COUNT];
new g_bestFileCacheAuth[MODE_COUNT][MAX_FILE_RECORDS][35];
new g_bestFileCacheName[MODE_COUNT][MAX_FILE_RECORDS][32];
new g_bestFileCacheTime[MODE_COUNT][MAX_FILE_RECORDS];

new const g_normalFpsModes[5] =
{
    MODE_NORMAL,
    MODE_NORMAL_200,
    MODE_NORMAL_333,
    MODE_NORMAL_500,
    MODE_NORMAL_1000
};

new const g_displayModeOrder[MODE_COUNT] =
{
    MODE_NORMAL,
    MODE_NORMAL_200,
    MODE_NORMAL_333,
    MODE_NORMAL_500,
    MODE_NORMAL_1000,
    MODE_LOW_GRAVITY,
    MODE_DOUBLE_JUMP,
    MODE_SIMPLE
};

new g_playerMode[MAX_PLAYERS + 1];
new g_playerModeBeforeSimple[MAX_PLAYERS + 1];
new bool:g_doubleJumped[MAX_PLAYERS + 1];
new bool:g_jumpReleased[MAX_PLAYERS + 1];
new bool:g_hookActive[MAX_PLAYERS + 1];
new Float:g_hookTarget[MAX_PLAYERS + 1][3];
new Float:g_hookLastBeamTime[MAX_PLAYERS + 1];

#define MAX_REPLAY_FRAMES 90000
#define RECORD_INTERVAL 0.02
#define TASK_PLAYBACK 24600
#define REPLAY_MAGIC 0x42525032
#define REPLAY_VERSION 3
#define REPLAY_BUTTON_MASK 0xFFFF
#define REPLAY_STATE_ONGROUND (1<<16)
#define REPLAY_STATE_DUCKING (1<<17)

// Replay frames are dynamic.  The old fixed arrays reserved roughly 50 MB in
// every plugin instance even when nobody was running.  This layout follows the
// WRBot Array model and allocates only for active runners / the selected WR.
enum _:ReplayFrame
{
    Float:RF_TIME,
    Float:RF_ORIGIN_X,
    Float:RF_ORIGIN_Y,
    Float:RF_ORIGIN_Z,
    Float:RF_ANGLE_X,
    Float:RF_ANGLE_Y,
    Float:RF_VELOCITY_X,
    Float:RF_VELOCITY_Y,
    Float:RF_VELOCITY_Z,
    RF_STATE
};

new Array:g_replayFrames[MAX_PLAYERS + 1];
new Float:g_lastRecordTime[MAX_PLAYERS + 1];
new g_lastReplayState[MAX_PLAYERS + 1];

// Strafe Sync HUD Stats (Removed)

new g_replayBot;
new g_botReplayMode;
new Array:g_botReplayFrames = Invalid_Array;
new g_botReplayTotalFrames;
new g_botPlaybackFrame;
new Float:g_lastPlaybackTime;
new Float:g_botPlaybackTime;
new g_botReplayDurationMs;
new bool:g_botReplayHasFullState;

new bool:g_pendingWrSave;
new g_pendingWrMode;
new g_pendingWrDurationMs;
new Array:g_pendingWrFrames = Invalid_Array;
new g_pendingWrFile;
new g_pendingWrWriteIndex;
new g_pendingWrTempPath[192];

new bool:g_fpsHidePlayers[MAX_PLAYERS + 1];
new bool:g_fpsHideText[MAX_PLAYERS + 1];
new bool:g_fpsHideWeapon[MAX_PLAYERS + 1];
new bool:g_fpsHideHud[MAX_PLAYERS + 1];
new bool:g_fpsHideWater[MAX_PLAYERS + 1];
new g_fpsBrightnessLevel[MAX_PLAYERS + 1];
new g_fpsSoundLevel[MAX_PLAYERS + 1];
new g_modeFpsFrames[MAX_PLAYERS + 1];
new g_modeFpsValue[MAX_PLAYERS + 1];
new g_fpsMsecSum[MAX_PLAYERS + 1];
new g_fpsMsecSamples[MAX_PLAYERS + 1];
new bool:g_fpsVerified[MAX_PLAYERS + 1];
new g_fpsMismatchSamples[MAX_PLAYERS + 1];
new g_fpsSession[MAX_PLAYERS + 1];
new Float:g_lastFpsQuery[MAX_PLAYERS + 1];
new Float:g_lastNormalFpsWarn[MAX_PLAYERS + 1];
new Float:g_lastModeFpsMaxApply[MAX_PLAYERS + 1];
new g_fpsQueryMask[MAX_PLAYERS + 1];
new g_fpsQueryExpected[MAX_PLAYERS + 1];
new bool:g_fpsMaxMatches[MAX_PLAYERS + 1];
new bool:g_fpsOverrideMatches[MAX_PLAYERS + 1];
new bool:g_fpsDeveloperMatches[MAX_PLAYERS + 1];
new bool:g_fpsCommandsFiltered[MAX_PLAYERS + 1];
new g_fpsQueryGeneration[MAX_PLAYERS + 1];

// Anti-cheat
new g_cheatWarnings[MAX_PLAYERS + 1];
new Float:g_airStuckStart[MAX_PLAYERS + 1];
new bool:g_airStuckFlagged[MAX_PLAYERS + 1];
new Float:g_lastJumpPress[MAX_PLAYERS + 1];
new Float:g_lastSteepSlopeCheck[MAX_PLAYERS + 1];
new g_autoBhopMacroCount[MAX_PLAYERS + 1];
new bool:g_inAirPrev[MAX_PLAYERS + 1];
new g_anticheatSyncWarned[MAX_PLAYERS + 1];

// StrafeHack Detector
new g_ePlayerInfo[33][PLAYER_DATA];
new g_ePlayerLog[33][LOG_DATA];
new g_iKeyFrames[33][KEY_IDS], g_iOldKeyFrames[33][KEY_IDS], g_iKeyWarning[33][KEY_IDS];
new Float:g_fStrafeOldAngles[33][3];
new g_iOldTurning[33];
new Float:g_fOldStrafeAngles[33][3];
new Float:g_fStrafeOldAnglesDiff[33];

new g_ePlayerButtons[][] = 
{
    {IN_FORWARD, KEY_W},
    {IN_BACK, KEY_S},
    {IN_MOVELEFT, KEY_A},
    {IN_MOVERIGHT, KEY_D}
};
// Spectator target cycling
new g_specTarget[MAX_PLAYERS + 1];

new g_wrHolderName[MODE_COUNT][32];
new g_bestCacheGeneration[MODE_COUNT];

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
new g_duelMode[MAX_PLAYERS + 1];

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
forward TaskRetryModeFpsMax(taskid);
forward CmdBhopReplayMenu(id);
forward BhopReplayMenuHandler(id, menu, item);
forward ShowNormalFpsModeMenu(id);
forward ShowDuelModeMenu(id);
forward ShowDuelNormalFpsMenu(id);
forward CmdHookOn(id);
forward CmdHookOff(id);
forward BadgesMenuHandler(id, menu, item);
forward CmdTopBadges(id);

forward FwStartFrame();
forward FwHamTakeDamage(victim, inflictor, attacker, Float:damage, damagebits);
forward FwHamPlayerKilled(victim, attacker, shouldgib);
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
new g_cvarTeleportFix;
new g_cvarAutoBhop;
new g_cvarSpeedometer;
new g_cvarNormalFpsEnforce;
new g_cvarNormalFpsLimit;
new g_cvarNormalFpsMax;
new g_cvarNormalFpsWarnTolerance;
new g_cvarOtherModesFpsMax;
new g_cvarNormalMaxspeed;
new g_cvarOtherModesMaxspeed;
new g_cvarRemoveJumpSlowdown;
new g_cvarApplyServerCvars;
new g_cvarReplayPitchInvert;
new g_cvarHookEnabled;
new g_cvarHookMaxDistance;
new g_cvarHookMinDistance;
new g_cvarParachuteEnabled;
new g_cvarParachuteFallSpeed;
new g_cvarAdminGlow;
new g_cvarAdminGlowColor;
new g_cvarAdminGlowAmount;
new g_cvarStartZoneMaxspeed;
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

new g_cacheEnabled;
new g_cacheHud;
new Float:g_cacheHudUpdate;
new g_cacheSpeedometer;
new g_cacheAutoCt;
new g_cacheGodmode;
new g_cacheAutoBhop;
new g_cacheHookEnabled;
new g_cacheParachuteEnabled;
new g_cacheAdminGlow;
new g_cacheBlockServerCommands;
new g_cacheBlockWeaponPickup;
new g_cacheTeleportFix;
new g_cacheRemoveJumpSlowdown;
new g_cacheResetOnDeath;
new g_cacheResetOnTeamChange;
new g_cacheNormalFpsEnforce;
new g_cacheStartMenuOnJoin;
new g_cacheTeleportOnFinish;
new g_cacheRender;
new g_cacheAdsEnabled;
new Float:g_cacheAdsInterval;
new Float:g_cacheNormalMaxspeed;
new Float:g_cacheOtherModesMaxspeed;
new Float:g_cacheHookMaxDistance;
new Float:g_cacheHookMinDistance;
new Float:g_cacheParachuteFallSpeed;
new Float:g_cacheAdminGlowAmount;
new g_cacheSimpleEnabled;
new g_cacheSimpleDoubleJump;
new g_cacheSimpleLowGravity;
new Float:g_cacheStartZoneMaxspeed;
new Float:g_cacheStartTeleportZOffset;
new g_cacheReplayPitchInvert;
new g_cacheEconomyEnabled;

new Float:g_cacheAdminGlowColor[3];
new bool:g_cacheAdminGlowColorLoaded = false;

new g_nextAdvertisement;
new g_msgSayText;
new g_msgShowMenu;
new g_msgVguiMenu;
new g_msgScoreInfo;
new g_cvarSpectatorHudEnabled;
new g_cvarSpectatorHudInterval;
new g_cvarSimpleEnabled;
new g_cvarSimpleDoubleJump;
new g_cvarSimpleLowGravity;

// Anti-cheat CVars
new g_cvarAntiCheatAirStuck;
new g_cvarAntiCheatStrafeHack;

// Enhanced spectator HUD CVars
new g_cvarSpecHudEnhanced;
new g_cvarSpecHudShowKeys;
new g_cvarSpecHudShowSync;
new g_cvarSpecHudShowWr;

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
    EmbeddedZonesPrecache();
    g_beamSprite = precache_model("sprites/laserbeam.spr");
    precache_sound("ed/wr1.wav");
    precache_sound("ed/wr2.wav");
    precache_sound("ed/wr3.wav");
    precache_model("models/knifes/talon_ed/v_knife.mdl");
    precache_model("models/knifes/bayonet_ed/v_knife.mdl");
    precache_model("models/knifes/bayonet_ed/p_knife.mdl");
    precache_model("models/knifes/karambit_ed/v_knife.mdl");
    precache_model("models/knifes/karambit_ed/p_knife.mdl");
    precache_model("models/knifes/butterfly_ed/v_knife.mdl");
    precache_model("models/knifes/butterfly_ed/p_knife.mdl");
    precache_model("models/knifes/vipgold_ed/v_knife.mdl");
    precache_model("models/knifes/vipgold_ed/p_knife.mdl");
    precache_model("models/knifes/vipm9_ed/v_knife.mdl");
    precache_model("models/knifes/vipm9_ed/p_knife.mdl");
}

public plugin_init()
{
    register_plugin(PLUGIN_NAME, PLUGIN_VERSION, PLUGIN_AUTHOR);
    EmbeddedZonesInit();
    PhysicsFixesInit();
    MpBhopInit();
    StrafeStatsInit();

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
    g_cvarTeleportFix = register_cvar("bhop_teleport_fix", "1");
    g_cvarAutoBhop = register_cvar("bhop_auto_bhop", "1");
    g_cvarSpeedometer = register_cvar("bhop_speedometer", "1");
    g_cvarNormalFpsEnforce = register_cvar("bhop_normal_fps_enforce", "1");
    g_cvarNormalFpsLimit = register_cvar("bhop_normal_fps_limit", "135");
    g_cvarNormalFpsMax = register_cvar("bhop_normal_fps_max", "131");
    g_cvarNormalFpsWarnTolerance = register_cvar("bhop_normal_fps_warn_tolerance", "30");
    g_cvarOtherModesFpsMax = register_cvar("bhop_other_modes_fps_max", "1000");
    g_cvarNormalMaxspeed = register_cvar("bhop_normal_maxspeed", "2000");
    g_cvarOtherModesMaxspeed = register_cvar("bhop_other_modes_maxspeed", "3000");
    g_cvarRemoveJumpSlowdown = register_cvar("bhop_remove_jump_slowdown", "1");
    g_cvarApplyServerCvars = register_cvar("bhop_apply_server_cvars", "1");
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
    g_cvarAdText[3] = register_cvar("bhop_ad_text_4", "Normal FPS kategorileri, Low Gravity ve Double Jump icin /mode yaz.");
    g_cvarAdText[4] = register_cvar("bhop_ad_text_5", "Bir oyuncuya meydan okumak icin /duel yaz.");
    g_cvarAdText[5] = register_cvar("bhop_ad_text_6", "Spend your credits in /market, check your balance with /credits.");
    g_cvarAdText[6] = register_cvar("bhop_ad_text_7", "Your profile is created automatically; use /badges to track achievements.");
    g_cvarAdText[7] = register_cvar("bhop_ad_text_8", "Challenge a friend with /duel, accept with /accept.");
    g_cvarAdText[8] = register_cvar("bhop_ad_text_9", "Use /menu to reach every BMOD feature.");
    g_cvarAdText[9] = register_cvar("bhop_ad_text_10", "Vote to change the map with /rtv, nominate with /nominate.");
    g_cvarAdText[10] = register_cvar("bhop_ad_text_11", "Type /knifes to choose your knife skin.");
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
    g_cvarSpectatorHudEnabled = register_cvar("bhop_spectator_hud_enabled", "1");
    g_cvarSpectatorHudInterval = register_cvar("bhop_spectator_hud_interval", "1.0");
    g_cvarSimpleEnabled = register_cvar("bhop_simple_enabled", "1");
    g_cvarSimpleDoubleJump = register_cvar("bhop_simple_doublejump", "1");
    g_cvarSimpleLowGravity = register_cvar("bhop_simple_lowgravity", "0");
    g_cvarStartZoneMaxspeed = register_cvar("bhop_startzone_maxspeed", "300");

    // Anti-cheat CVars
    g_cvarAntiCheatAirStuck = register_cvar("bhop_anticheat_air_stuck", "1");
    g_cvarAntiCheatStrafeHack = register_cvar("bhop_anticheat_strafehack", "1");

    // Enhanced spectator HUD CVars
    g_cvarSpecHudEnhanced = register_cvar("bhop_spec_hud_enhanced", "1");
    g_cvarSpecHudShowKeys = register_cvar("bhop_spec_hud_show_keys", "1");
    g_cvarSpecHudShowSync = register_cvar("bhop_spec_hud_show_sync", "1");
    g_cvarSpecHudShowWr = register_cvar("bhop_spec_hud_show_wr", "1");

    new startColor[3] = {0, 255, 0};
    new finishColor[3] = {255, 0, 0};
    sr_zone_register_type(
        .class_name = "zone_start",
        .description = "Bhop start zone",
        .color = startColor,
        .visibility = ZONE_VISIBLE_BOTTOM,
        .on_enter = "OnStartZoneEnter",
        .on_leave = "OnStartZoneLeave"
    );
    sr_zone_register_type(
        .class_name = "zone_finish",
        .description = "Bhop finish zone",
        .color = finishColor,
        .visibility = ZONE_VISIBLE_BOTTOM,
        .on_enter = "OnFinishZoneEnter",
        .on_leave = "OnFinishZoneLeave"
    );

    g_msgSayText = get_user_msgid("SayText");
    g_msgShowMenu = get_user_msgid("ShowMenu");
    g_msgVguiMenu = get_user_msgid("VGUIMenu");
    g_msgScoreInfo = get_user_msgid("ScoreInfo");
    register_message(g_msgScoreInfo, "MsgScoreInfoCore");

    register_forward(FM_PlayerPreThink, "FwPlayerPreThink");
    register_forward(FM_CmdStart, "FwCmdStartCore");
    register_forward(FM_Touch, "FwTouch");
    register_forward(FM_StartFrame, "FwStartFrame");
    register_forward(FM_AddToFullPack, "FwAddToFullPack", 1);

    RegisterHam(Ham_TakeDamage, "player", "FwHamTakeDamage");
    RegisterHam(Ham_Killed, "player", "FwHamPlayerKilled");
    RegisterHam(Ham_Item_Deploy, "weapon_knife", "FwHamItemDeploy", false);

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
    register_clcmd("chooseteam", "CmdMainMenu");
    register_clcmd("drop", "CmdModeShortcut");
    register_clcmd("nightvision", "CmdMarket");

    register_menu("BhopTimer", 1023, "BhopMenuCallback");

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
    register_clcmd("say /spec_next", "CmdSpecNext");
    register_clcmd("say_team /spec_next", "CmdSpecNext");
    register_clcmd("say /spec_prev", "CmdSpecPrev");
    register_clcmd("say_team /spec_prev", "CmdSpecPrev");

    register_clcmd("say /noclip", "CmdNoclip");
    register_clcmd("say_team /noclip", "CmdNoclip");
    register_clcmd("say /fps", "CmdFpsMenu");
    register_clcmd("say_team /fps", "CmdFpsMenu");
    register_clcmd("say /binds", "CmdApplyBinds");
    register_clcmd("say_team /binds", "CmdApplyBinds");
    register_clcmd("+hook", "CmdHookOn");
    register_clcmd("-hook", "CmdHookOff");

    register_clcmd("say /market", "CmdMarket");
    register_clcmd("say_team /market", "CmdMarket");
    register_clcmd("say /shop", "CmdMarket");
    register_clcmd("say_team /shop", "CmdMarket");

    register_clcmd("say /buy", "CmdBuy");
    register_clcmd("say_team /buy", "CmdBuy");

    register_clcmd("say /inventory", "CmdInventory");
    register_clcmd("say_team /inventory", "CmdInventory");
    register_clcmd("say /inv", "CmdInventory");
    register_clcmd("say_team /inv", "CmdInventory");

    register_clcmd("say /credits", "CmdCredits");
    register_clcmd("say_team /credits", "CmdCredits");
    register_clcmd("say /points", "CmdCredits");
    register_clcmd("say_team /points", "CmdCredits");
    register_clcmd("say /balance", "CmdCredits");
    register_clcmd("say_team /balance", "CmdCredits");

    register_clcmd("say /badges", "CmdBadges");
    register_clcmd("say_team /badges", "CmdBadges");

    register_clcmd("say /topbadges", "CmdTopBadges");
    register_clcmd("say_team /topbadges", "CmdTopBadges");

    register_clcmd("say /setprefix", "CmdSetPrefix");
    register_clcmd("say_team /setprefix", "CmdSetPrefix");

    register_clcmd("say /trail", "CmdTrail");
    register_clcmd("say_team /trail", "CmdTrail");

    register_clcmd("say /joinmessage", "CmdSetWelcome");
    register_clcmd("say_team /joinmessage", "CmdSetWelcome");
    register_clcmd("say /setwelcome", "CmdSetWelcome");
    register_clcmd("say_team /setwelcome", "CmdSetWelcome");

    register_concmd("amx_bhop_start_a", "ConCmdStartA", ADMIN_RCON, "- set start zone point A");
    register_concmd("amx_bhop_start_b", "ConCmdStartB", ADMIN_RCON, "- set start zone point B");
    register_concmd("amx_bhop_finish_a", "ConCmdFinishA", ADMIN_RCON, "- set finish zone point A");
    register_concmd("amx_bhop_finish_b", "ConCmdFinishB", ADMIN_RCON, "- set finish zone point B");
    register_concmd("amx_bhop_save", "ConCmdSave", ADMIN_RCON, "- save edited zones for current map");
    register_concmd("amx_bhop_reload", "ConCmdReload", ADMIN_RCON, "- reload zones for current map");
    register_concmd("amx_bhop_delete_start", "ConCmdDeleteStart", ADMIN_RCON, "- delete start zone for current map");
    register_concmd("amx_bhop_delete_finish", "ConCmdDeleteFinish", ADMIN_RCON, "- delete finish zone for current map");
    register_concmd("amx_bhop_db_retry", "ConCmdDbRetry", ADMIN_RCON, "- retry remote MySQL connection and pending writes");
    register_concmd("amx_bhop_reset_top15", "ConCmdResetTop15", ADMIN_RCON, "<normal|normal131|normal200|normal333|normal500|normal1000|lowgrav|dbjump|simple|all> - reset current map records");
    register_concmd("amx_bhop_simple", "ConCmdSimple", ADMIN_RCON, "- toggle simple mode on/off");

    RegisterBlockedCommands();

    // Register the generic say handlers last so specific "say /command" hooks
    // take precedence over the chat formatter.
    register_clcmd("say", "CmdSay");
    register_clcmd("say_team", "CmdSayTeam");
    register_clcmd("say /knifes", "CmdKnifeMenuCore");
    register_clcmd("say_team /knifes", "CmdKnifeMenuCore");
    register_clcmd("knife_menu", "CmdKnifeMenuCore");

    EconomyInit();
}

public plugin_natives()
{
    register_library("bhop_timer");
    register_native("EconomyPlayerHasItem", "NativeEconomyPlayerHasItem");
    register_native("bmod_open_main_menu", "NativeOpenMainMenu");
}

public NativeOpenMainMenu(plugin_id, argc)
{
    #pragma unused plugin_id, argc
    new id = get_param(1);
    if (is_user_connected(id)) CmdMainMenu(id);
}

public NativeEconomyPlayerHasItem(plugin_id, argc)
{
    new id = get_param(1);
    new itemId = get_param(2);
    return EconomyPlayerHasItem(id, itemId);
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
    MpBhopCfg();

    EmbeddedZonesCfg();
    LoadZones();
    DbInitialize();

    TimerSetTask(0.1, "TaskHud", TASK_HUD, true);

    // The speedrun-zone renderer is the sole beam path. It caches entity geometry
    // and renders only floor edges outside editor mode.

    // The replay fake-client also keeps the round alive; no second bot slot.

    TimerSetTask(1.0, "TaskNormalFpsCheck", TASK_FPS_CHECK, true);
    TimerSetTask(1.0, "TaskScoreboardFps", TASK_SCOREBOARD, true);
    TimerSetTask(1.0, "TaskSpectatorHud", TASK_SPEC_HUD, true);
    TimerSetTask(2.0, "TaskLoadAllBests");
    TimerSetTask(15.0, "TaskDbRetry", TASK_DB_RETRY, true);
    ScheduleNextAdvertisement();

    g_botReplayMode = MODE_NORMAL;
    LoadReplayFile(g_botReplayMode);
    TimerSetTask(2.0, "TaskCreateReplayBot", TASK_REPLAY_BOT, true);

    CacheCvars();
    if (g_cacheSimpleEnabled)
    {
        SimpleModeApplyToAll();
    }
    TimerSetTask(5.0, "TaskRefreshCvars", 0, true);
}

public TaskRefreshCvars()
{
    new oldSimpleEnabled = g_cacheSimpleEnabled;
    CacheCvars();
    PhysicsFixesCacheCvars();

    if (g_cacheSimpleEnabled != oldSimpleEnabled)
    {
        if (g_cacheSimpleEnabled)
        {
            SimpleModeApplyToAll();
        }
        else
        {
            SimpleModeRestoreAll();
        }
    }
}

stock CacheCvars()
{
    g_cacheEnabled = get_pcvar_num(g_cvarEnabled);
    g_cacheHud = get_pcvar_num(g_cvarHud);
    g_cacheHudUpdate = get_pcvar_float(g_cvarHudUpdate);
    g_cacheSpeedometer = get_pcvar_num(g_cvarSpeedometer);
    g_cacheAutoCt = get_pcvar_num(g_cvarAutoCt);
    g_cacheGodmode = get_pcvar_num(g_cvarGodmode);
    g_cacheAutoBhop = get_pcvar_num(g_cvarAutoBhop);
    g_cacheHookEnabled = get_pcvar_num(g_cvarHookEnabled);
    g_cacheParachuteEnabled = get_pcvar_num(g_cvarParachuteEnabled);
    g_cacheAdminGlow = get_pcvar_num(g_cvarAdminGlow);
    g_cacheBlockServerCommands = get_pcvar_num(g_cvarBlockServerCommands);
    g_cacheBlockWeaponPickup = get_pcvar_num(g_cvarBlockWeaponPickup);
    g_cacheTeleportFix = get_pcvar_num(g_cvarTeleportFix);
    g_cacheRemoveJumpSlowdown = get_pcvar_num(g_cvarRemoveJumpSlowdown);
    g_cacheResetOnDeath = get_pcvar_num(g_cvarResetOnDeath);
    g_cacheResetOnTeamChange = get_pcvar_num(g_cvarResetOnTeamChange);
    g_cacheNormalFpsEnforce = get_pcvar_num(g_cvarNormalFpsEnforce);
    g_cacheStartMenuOnJoin = get_pcvar_num(g_cvarStartMenuOnJoin);
    g_cacheTeleportOnFinish = get_pcvar_num(g_cvarTeleportOnFinish);
    g_cacheRender = get_pcvar_num(g_cvarRender);
    g_cacheAdsEnabled = get_pcvar_num(g_cvarAdsEnabled);
    g_cacheEconomyEnabled = get_pcvar_num(g_cvarEconomyEnabled);
    g_cacheAdsInterval = get_pcvar_float(g_cvarAdsInterval);
    g_cacheNormalMaxspeed = get_pcvar_float(g_cvarNormalMaxspeed);
    g_cacheOtherModesMaxspeed = get_pcvar_float(g_cvarOtherModesMaxspeed);
    g_cacheHookMaxDistance = get_pcvar_float(g_cvarHookMaxDistance);
    g_cacheHookMinDistance = get_pcvar_float(g_cvarHookMinDistance);
    g_cacheParachuteFallSpeed = get_pcvar_float(g_cvarParachuteFallSpeed);
    g_cacheAdminGlowAmount = get_pcvar_float(g_cvarAdminGlowAmount);
    g_cacheStartTeleportZOffset = get_pcvar_float(g_cvarStartTeleportZOffset);
    g_cacheReplayPitchInvert = get_pcvar_num(g_cvarReplayPitchInvert);
    g_cacheSimpleEnabled = get_pcvar_num(g_cvarSimpleEnabled);
    g_cacheSimpleDoubleJump = get_pcvar_num(g_cvarSimpleDoubleJump);
    g_cacheSimpleLowGravity = get_pcvar_num(g_cvarSimpleLowGravity);
    g_cacheStartZoneMaxspeed = get_pcvar_float(g_cvarStartZoneMaxspeed);

    new colorText[32], rText[8], gText[8], bText[8];
    get_pcvar_string(g_cvarAdminGlowColor, colorText, charsmax(colorText));
    parse(colorText, rText, charsmax(rText), gText, charsmax(gText), bText, charsmax(bText));
    g_cacheAdminGlowColor[0] = float(clamp(str_to_num(rText), 0, 255));
    g_cacheAdminGlowColor[1] = float(clamp(str_to_num(gText), 0, 255));
    g_cacheAdminGlowColor[2] = float(clamp(str_to_num(bText), 0, 255));
    g_cacheAdminGlowColorLoaded = true;
}

public plugin_end()
{
    MpBhopShutdown();
    EmbeddedZonesShutdown();
    remove_task(TASK_HUD);
    remove_task(TASK_RENDER);
    remove_task(TASK_DB_RETRY);
    remove_task(TASK_DB_FLUSH);
    remove_task(TASK_ADVERTISE);
    remove_task(TASK_REPLAY_BOT);
    remove_task(TASK_FPS_CHECK);
    remove_task(TASK_SCOREBOARD);
    remove_task(TASK_SPEC_HUD);
    remove_task(TASK_WR_SAVE);

    if (g_pendingWrFile)
    {
        fclose(g_pendingWrFile);
        g_pendingWrFile = 0;
    }
    for (new id = 1; id <= MAX_PLAYERS; id++)
    {
        if (g_replayFrames[id] != Invalid_Array)
        {
            ArrayDestroy(g_replayFrames[id]);
            g_replayFrames[id] = Invalid_Array;
        }
    }
    if (g_botReplayFrames != Invalid_Array)
    {
        ArrayDestroy(g_botReplayFrames);
        g_botReplayFrames = Invalid_Array;
    }
    if (g_pendingWrFrames != Invalid_Array)
    {
        ArrayDestroy(g_pendingWrFrames);
        g_pendingWrFrames = Invalid_Array;
    }

    if (g_replayBot && is_user_connected(g_replayBot))
    {
        server_cmd("kick #%d", get_user_userid(g_replayBot));
    }

    SQL_SetAffinity("mysql");
    if (g_sqlTuple != Empty_Handle)
    {
        SQL_FreeHandle(g_sqlTuple);
        g_sqlTuple = Empty_Handle;
    }
    SQL_SetAffinity("sqlite");
    if (g_localDb != Empty_Handle)
    {
        SQL_FreeHandle(g_localDb);
        g_localDb = Empty_Handle;
    }
    if (g_localTuple != Empty_Handle)
    {
        SQL_FreeHandle(g_localTuple);
        g_localTuple = Empty_Handle;
    }
    SQL_SetAffinity("mysql");
}

public client_putinserver(id)
{
    EmbeddedZonesClientInit(id);
    PhysicsFixesClientInit(id);
    MpBhopClientInit(id);
    StrafeStatsClientInit(id);
    if (g_replayFrames[id] != Invalid_Array)
    {
        ArrayDestroy(g_replayFrames[id]);
    }
    g_replayFrames[id] = ArrayCreate(ReplayFrame);
    g_lastReplayState[id] = 0;
    g_playerMode[id] = MODE_NORMAL;
    g_playerModeBeforeSimple[id] = MODE_NORMAL;
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
    g_fpsMsecSum[id] = 0;
    g_fpsMsecSamples[id] = 0;
    g_fpsVerified[id] = false;
    g_fpsMismatchSamples[id] = 0;
    g_fpsSession[id]++;
    g_lastFpsQuery[id] = 0.0;
    g_lastNormalFpsWarn[id] = 0.0;
    g_lastModeFpsMaxApply[id] = 0.0;
    g_fpsQueryMask[id] = 0;
    g_fpsQueryExpected[id] = 0;
    g_fpsMaxMatches[id] = false;
    g_fpsOverrideMatches[id] = false;
    g_fpsDeveloperMatches[id] = false;
    g_fpsCommandsFiltered[id] = false;
    g_fpsQueryGeneration[id]++;
    g_spawnRetryCount[id] = 0;
    g_duelState[id] = DUEL_STATE_IDLE;
    g_duelPartner[id] = 0;
    g_duelCountdownTime[id] = 0;
    g_duelMode[id] = MODE_NORMAL;
    g_duelPendingTarget[id] = 0;
    
    // Anti-cheat init
    g_cheatWarnings[id] = 0;
    g_airStuckStart[id] = 0.0;
    g_airStuckFlagged[id] = false;
    g_lastJumpPress[id] = 0.0;
    g_lastSteepSlopeCheck[id] = 0.0;
    g_autoBhopMacroCount[id] = 0;
    g_inAirPrev[id] = false;
    g_anticheatSyncWarned[id] = 0;
    
    // Spectator target init
    g_specTarget[id] = 0;
    
    ResetPlayerData(id, true);
    EconomyResetPlayerData(id);
    TimerSetTask(0.8, "TaskAutoJoinCt", id + TASK_AUTOJOIN);
    TimerSetTask(1.4, "TaskApplyModeFpsMax", id + TASK_MODE_FPS_MAX);
    TimerSetTask(2.2, "TaskShowStartMenu", id + TASK_START_MENU);
    TimerSetTask(2.0, "TaskLoadPlayerBest", id + TASK_LOAD_BEST);
    TimerSetTask(3.0, "TaskAnnounceJoin", id + TASK_JOIN_MESSAGE);

    if (g_cacheSimpleEnabled)
    {
        g_playerModeBeforeSimple[id] = MODE_NORMAL;
        ApplyPlayerModeState(id, MODE_SIMPLE, true, true);
    }
}

public client_authorized(id)
{
    LoadPlayerBest(id);
    EconomyLoadPlayerData(id);
    LoadPlayerSelectedSound(id);
    LoadPlayerSelectedKnife(id);
    LoadPlayerSelectedTrail(id);
}

public TaskLoadPlayerBest(taskid)
{
    new id = taskid - TASK_LOAD_BEST;

    if (1 <= id <= MAX_PLAYERS && is_user_connected(id))
    {
        LoadPlayerBest(id);
        EconomyLoadPlayerData(id);
    }
}

public TaskAnnounceJoin(taskid)
{
    new id = taskid - TASK_JOIN_MESSAGE;
    if (!(1 <= id <= MAX_PLAYERS) || !is_user_connected(id) || is_user_bot(id) || is_user_hltv(id)) return;
    new playerName[32], joinMessage[96];
    get_user_name(id, playerName, charsmax(playerName));
    if (EconomyLocalGetSetting(id, "join_message", joinMessage, charsmax(joinMessage)) && joinMessage[0])
        TimerChat(0, "^x04%s^x01: ^x03%s", playerName, joinMessage);
    else
        TimerChat(0, "^x03%s^x01 joined the server.", playerName);
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
    if (!is_user_bot(id) && !is_user_hltv(id))
    {
        new playerName[32]; get_user_name(id, playerName, charsmax(playerName));
        TimerChat(0, "^x03%s^x01 left the server.", playerName);
    }
    remove_task(id + TASK_JOIN_MESSAGE);
    PhysicsFixesClientDisconnect(id);
    MpBhopClientDisconnect(id);
    StrafeStatsClientDisconnect(id);
    remove_task(id + TASK_AUTOJOIN);
    remove_task(id + TASK_SPAWN_CT);
    remove_task(id + TASK_START_TP);
    remove_task(id + TASK_LOAD_BEST);
    remove_task(id + TASK_START_MENU);
    remove_task(id + TASK_MODE_FPS_MAX);
    remove_task(id + TASK_MODE_FPS_RETRY);
    g_internalTeamCommand[id] = false;
    g_spawnRetryCount[id] = 0;
    g_playerMenuType[id] = MENU_NONE;
    g_playerMenuPage[id] = 0;
    g_duelPendingTarget[id] = 0;

    if (g_lastPro15File[id][0] && file_exists(g_lastPro15File[id]))
    {
        delete_file(g_lastPro15File[id]);
    }
    g_lastPro15File[id][0] = '^0';

    g_playerMode[id] = MODE_NORMAL;
    g_playerModeBeforeSimple[id] = MODE_NORMAL;
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
    g_fpsMsecSum[id] = 0;
    g_fpsMsecSamples[id] = 0;
    g_fpsVerified[id] = false;
    g_fpsMismatchSamples[id] = 0;
    g_fpsSession[id]++;
    g_lastFpsQuery[id] = 0.0;
    g_lastNormalFpsWarn[id] = 0.0;
    g_lastModeFpsMaxApply[id] = 0.0;
    g_fpsQueryMask[id] = 0;
    g_fpsQueryExpected[id] = 0;
    g_fpsMaxMatches[id] = false;
    g_fpsOverrideMatches[id] = false;
    g_fpsDeveloperMatches[id] = false;
    g_fpsCommandsFiltered[id] = false;
    g_fpsQueryGeneration[id]++;
    g_duelMode[id] = MODE_NORMAL;

    EconomyResetPlayerData(id);

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
    if (g_replayFrames[id] != Invalid_Array)
    {
        ArrayDestroy(g_replayFrames[id]);
        g_replayFrames[id] = Invalid_Array;
    }
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
        else if (g_cacheResetOnDeath)
        {
            ResetPlayerData(victim, false);
        }
    }
}

public EventTeamInfo()
{
    new id = read_data(1);

    if (!g_cacheResetOnTeamChange)
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
    if (!g_cacheAutoCt || !is_user_connected(id))
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
    if (!g_cacheAutoCt || !is_user_connected(id))
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

public FwCmdStartCore(id, uc_handle, seed)
{
    #pragma unused seed

    if (!is_user_connected(id) || is_user_bot(id))
        return FMRES_IGNORED;

    new msec = get_uc(uc_handle, UC_Msec);
    if (msec > 0 && msec <= 255)
    {
        g_fpsMsecSum[id] += msec;
        g_fpsMsecSamples[id]++;
    }

    if (get_uc(uc_handle, UC_Impulse) == 100)
    {
        set_uc(uc_handle, UC_Impulse, 0);
        CmdFpsMenu(id);
        return FMRES_HANDLED;
    }

    // StrafeHack Detector - CmdStart checks
    if (get_pcvar_num(g_cvarAntiCheatStrafeHack))
    {
        if (!is_user_alive(id))
            return FMRES_IGNORED;

        new Float:fForwardMove; get_uc(uc_handle, UC_ForwardMove, fForwardMove);
        new Float:fSideMove; get_uc(uc_handle, UC_SideMove, fSideMove);

        if (fForwardMove == 0.0 && fSideMove == 0.0)
            return FMRES_IGNORED;

        new Float:fTime = get_gametime();

        if (fTime < _:g_ePlayerInfo[id][m_fLastWeaponDeploy] + IGNORE_TIME)
            return FMRES_IGNORED;

        new bBlockSpeed = false;
        new bButtons = get_uc(uc_handle, UC_Buttons);
        new Float:fAngles[3]; pev(id, pev_angles, fAngles);
        new Float:fAnglesDiff[3];
        fAnglesDiff[0] = fAngles[0] - g_fStrafeOldAngles[id][0];
        fAnglesDiff[1] = fAngles[1] - g_fStrafeOldAngles[id][1];
        fAnglesDiff[2] = fAngles[2] - g_fStrafeOldAngles[id][2];
        new Float:fValue = floatsqroot(fForwardMove * fForwardMove + fSideMove * fSideMove);

        if (!(fAnglesDiff[0] == 0.0 && fAnglesDiff[1] == 0.0 && fValue > 115.0))
        {
            if ((fForwardMove > 0.0 && ~bButtons & IN_FORWARD || fForwardMove < 0.0 && ~bButtons & IN_BACK) && fAnglesDiff[PITCH] != 0.0)
            {
                bBlockSpeed = true;
            }
            if (fSideMove > 0.0 && ~bButtons & IN_MOVERIGHT || fSideMove < 0.0 && ~bButtons & IN_MOVELEFT)
            {
                bBlockSpeed = true;
            }
        }

        new Float:fMaxSpeed = get_user_maxspeed(id);
        if (fValue > fMaxSpeed && fMaxSpeed > 100.0)
        {
            bBlockSpeed = true;
        }

        if (bButtons & (IN_LEFT | IN_RIGHT))
        {
            bBlockSpeed = true;
        }

        fForwardMove = floatabs(fForwardMove);
        fSideMove = floatabs(fSideMove);

        if (fForwardMove && fSideMove && fForwardMove != fSideMove)
        {
            if (++g_ePlayerInfo[id][m_BadFrame] >= MAX_BADFRAMES)
            {
                bBlockSpeed = true;
                g_ePlayerInfo[id][m_BadFrame] = 0;
            }
        }
        else
        {
            g_ePlayerInfo[id][m_BadFrame] = 0;
        }

        new iTurning = 0;
        new Float:fDiff = fAngles[YAW] - g_fStrafeOldAngles[id][YAW];
        if (fDiff >= 180.0) fDiff -= 360.0;
        if (fDiff < -180.0) fDiff += 360.0;

        if (fDiff < 0.0)
        {
            iTurning = RIGHT;
            if (g_iOldTurning[id] == LEFT)
            {
                g_ePlayerInfo[id][m_Strafes]++;
                StrafeForward(id, fAngles);
            }
        }
        else if (fDiff > 0.0)
        {
            iTurning = LEFT;
            if (g_iOldTurning[id] == RIGHT)
            {
                g_ePlayerInfo[id][m_Strafes]++;
                StrafeForward(id, fAngles);
            }
        }

        if (fTime >= _:g_ePlayerInfo[id][m_fLastStrafeCheck])
        {
            if (g_ePlayerInfo[id][m_Strafes] >= MAX_STRAFES)
            {
                bBlockSpeed = true;
            }
            g_ePlayerInfo[id][m_Strafes] = 0;
            g_ePlayerInfo[id][m_fLastStrafeCheck] = _:(fTime + STRAFE_CHECK_TIME);
        }

        g_iOldTurning[id] = iTurning;

        if (bBlockSpeed)
        {
            new Float:fVelocity[3]; pev(id, pev_velocity, fVelocity);
            fVelocity[0] *= 0.2; fVelocity[1] *= 0.2;
            set_pev(id, pev_velocity, fVelocity);
        }

        g_fStrafeOldAngles[id] = fAngles;
    }

    return FMRES_IGNORED;
}

public CmdModeShortcut(id)
{
    return CmdBhopModeMenu(id);
}

public FwPlayerPreThink(id)
{
    if (!g_cacheEnabled)
    {
        return FMRES_IGNORED;
    }

    if (!is_user_alive(id))
    {
        return FMRES_IGNORED;
    }

    hc_cbaseplayer_prethink(id);
    PhysicsFixesPreThink(id);
    StrafeStatsPreThink(id);

    // Replay movement is driven exclusively by PlaybackBotFrame. Do not let
    // timer assists or player protections modify its recorded state.
    if (id == g_replayBot)
    {
        return FMRES_IGNORED;
    }

    if (!is_user_bot(id))
    {
        g_modeFpsFrames[id]++;
    }

    new movetype = pev(id, pev_movetype);
    if (movetype == MOVETYPE_NOCLIP || (is_user_bot(id) && movetype == MOVETYPE_FLY))
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
    ApplyPlayerTrail(id);

    AntiCheatCheck(id);

    // StrafeHack Detector - PreThink keyframe check
    if (get_pcvar_num(g_cvarAntiCheatStrafeHack))
    {
        new bBlockSpeed = false;
        new bButtons = pev(id, pev_button);
        new bOldButton = pev(id, pev_oldbuttons);

        for (new i = 0; i < sizeof(g_ePlayerButtons); i++)
        {
            new CheckButton = g_ePlayerButtons[i][BUTTON];
            new CheckKey = g_ePlayerButtons[i][KEY];

            if (bButtons & CheckButton)
            {
                g_iKeyFrames[id][CheckKey]++;
            }

            if (~bButtons & CheckButton && bOldButton & CheckButton)
            {
                if (g_iKeyFrames[id][CheckKey] == g_iOldKeyFrames[id][CheckKey])
                {
                    if (g_iKeyFrames[id][CheckKey] == 1) g_iKeyWarning[id][CheckKey]++;

                    if (++g_iKeyWarning[id][CheckKey] >= MAX_KEYWARNING)
                    {
                        bBlockSpeed = true;
                        g_iKeyWarning[id][CheckKey] = 0;
                    }
                }
                else if (g_iKeyWarning[id][CheckKey])
                {
                    g_iKeyWarning[id][CheckKey]--;
                }
                g_iOldKeyFrames[id][CheckKey] = g_iKeyFrames[id][CheckKey];
                g_iKeyFrames[id][CheckKey] = 0;
            }
        }

        if (bBlockSpeed)
        {
            new Float:fVelocity[3]; pev(id, pev_velocity, fVelocity);
            fVelocity[0] *= 0.2; fVelocity[1] *= 0.2;
            set_pev(id, pev_velocity, fVelocity);
        }
    }

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
        else if (g_jumpReleased[id] && !g_doubleJumped[id] && (g_playerMode[id] == MODE_DOUBLE_JUMP || (g_cacheSimpleEnabled && g_playerMode[id] == MODE_SIMPLE && g_cacheSimpleDoubleJump)))
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

    // Per-mode velocity clamping
    if (!is_user_bot(id))
    {
        new Float:clampMax = IsNormalMode(g_playerMode[id])
            ? g_cacheNormalMaxspeed
            : g_cacheOtherModesMaxspeed;

        new Float:vel[3];
        pev(id, pev_velocity, vel);
        new Float:speed = vector_length(vel);
        if (speed > clampMax && speed > 0.0)
        {
            new Float:scale = clampMax / speed;
            vel[0] *= scale;
            vel[1] *= scale;
            vel[2] *= scale;
            set_pev(id, pev_velocity, vel);
        }
    }

    // Start zone speed limit (normal modes only)
    if (g_prevInStart[id] && IsNormalMode(g_playerMode[id]) && g_cacheStartZoneMaxspeed > 0.0)
    {
        new Float:vel[3];
        pev(id, pev_velocity, vel);
        new Float:hSpeed = floatsqroot(vel[0] * vel[0] + vel[1] * vel[1]);
        if (hSpeed > g_cacheStartZoneMaxspeed && hSpeed > 0.0)
        {
            new Float:scale = g_cacheStartZoneMaxspeed / hSpeed;
            vel[0] *= scale;
            vel[1] *= scale;
            set_pev(id, pev_velocity, vel);
        }
    }

    if (g_timerState[id] == TIMER_RUNNING)
    {
        RecordReplayFrame(id, get_gametime(), false);
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

    if (!(1 <= id <= MAX_PLAYERS) || !is_user_alive(id))
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

    if (g_timerState[id] == TIMER_IN_START && g_prevInStart[id])
    {
        StartTimer(id);
    }

    g_prevInStart[id] = false;
}

public OnFinishZoneEnter(zone_entity, id)
{
    #pragma unused zone_entity

    if (!(1 <= id <= MAX_PLAYERS) || !is_user_alive(id))
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
    log_amx("[TIMER] Zone data saved locally for %s", g_mapName);
    RefreshZoneCaches();
    SaveZonesFile();
    return PLUGIN_CONTINUE;
}

// FwCmdStart removed

public FwStartFrame()
{
    if (g_replayBot && is_user_connected(g_replayBot) && is_user_alive(g_replayBot) && HasAnySpectator())
    {
        PlaybackBotFrame();
    }
    else if (g_replayBot && is_user_connected(g_replayBot) && g_lastPlaybackTime != 0.0)
    {
        // Pause the replay clock while nobody watches. Resetting the wall-clock
        // anchor prevents a large catch-up jump when a spectator reconnects.
        g_lastPlaybackTime = 0.0;
        set_pev(g_replayBot, pev_movetype, MOVETYPE_FLY);
        new Float:zero[3] = {0.0, 0.0, 0.0};
        set_pev(g_replayBot, pev_velocity, zero);
    }
}

stock bool:HasAnySpectator()
{
    for (new i = 1; i <= MAX_PLAYERS; i++)
    {
        if (is_user_connected(i) && !is_user_alive(i))
        {
            new specMode = pev(i, pev_iuser1);
            if (specMode == 1 || specMode == 2 || specMode == 4)
            {
                new specTarget = pev(i, pev_iuser2);
                if (specTarget == g_replayBot)
                    return true;
            }
        }
    }
    return false;
}

public TaskHud()
{
    if (!g_cacheEnabled || !g_cacheHud)
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
            displayMs = floatround(g_botPlaybackTime * 1000.0);
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

        new hudText[96];
        if (g_cacheSpeedometer)
        {
            formatex(hudText, charsmax(hudText), "%d^n%s (%s)", speed, timeText, modeName);
            set_hudmessage(80, 255, 80, -1.0, 0.82, 0, 0.0, g_cacheHudUpdate + 0.08, 0.0, 0.0, 4);
            show_hudmessage(id, hudText);
        }
        else
        {
            formatex(hudText, charsmax(hudText), "%s (%s)", timeText, modeName);
            set_hudmessage(80, 255, 80, -1.0, 0.85, 0, 0.0, g_cacheHudUpdate + 0.08, 0.0, 0.0, 4);
            show_hudmessage(id, hudText);
        }
    }
}

public TaskRenderZones()
{
    if (!g_cacheEnabled || !g_cacheRender)
    {
        return;
    }

    RefreshZoneCaches();

    for (new zoneIndex = 0; zoneIndex < ZONE_COUNT; zoneIndex++)
    {
        if (g_zoneLoaded[zoneIndex])
        {
            RenderZone(zoneIndex);
        }
    }
}

public MsgScoreInfoCore(msgid, dest, id)
{
    #pragma unused msgid, dest, id
    new player = get_msg_arg_int(1);
    if (1 <= player <= MAX_PLAYERS && is_user_connected(player) && !is_user_bot(player))
        set_msg_arg_int(3, ARG_SHORT, g_modeFpsValue[player]);
}

public TaskScoreboardFps()
{
    if (g_msgScoreInfo <= 0) return;
    for (new player = 1; player <= MAX_PLAYERS; player++)
    {
        if (!is_user_connected(player) || is_user_bot(player)) continue;
        new frags = get_user_frags(player), team = _:cs_get_user_team(player);
        for (new receiver = 1; receiver <= MAX_PLAYERS; receiver++)
        {
            if (!is_user_connected(receiver)) continue;
            message_begin(MSG_ONE_UNRELIABLE, g_msgScoreInfo, _, receiver);
            write_byte(player);
            write_short(frags);
            write_short(g_modeFpsValue[player]);
            write_short(0);
            write_short(team);
            message_end();
        }
    }
}

public TaskSpectatorHud()
{
    if (!get_pcvar_num(g_cvarSpectatorHudEnabled)) return;

    new enhanced = get_pcvar_num(g_cvarSpecHudEnhanced);
    new Float:interval = get_pcvar_float(g_cvarSpectatorHudInterval);
    new specCount;

    for (new id = 1; id <= MAX_PLAYERS; id++)
    {
        if (!is_user_connected(id) || is_user_alive(id) || is_user_bot(id) || is_user_hltv(id))
            continue;

        specCount++;

        if (!enhanced)
        {
            // Legacy mode: just show spectator names
            continue;
        }

        // Enhanced spectator HUD
        new target = GetSpecTarget(id);
        if (!target || !is_user_connected(target) || !is_user_alive(target))
        {
            // Not spectating anyone specific - show info about WR bot or fallback
            if (g_replayBot && is_user_connected(g_replayBot) && is_user_alive(g_replayBot))
                target = g_replayBot;
            else
                continue;
        }

        new targetName[32];
        get_user_name(target, targetName, charsmax(targetName));

        new hudText[512];
        new pos;

        // Line 1: Target name + mode
        new modeName[32];
        if (target == g_replayBot && g_botReplayTotalFrames > 0)
        {
            GetModeName(g_botReplayMode, modeName, charsmax(modeName));
            pos += formatex(hudText[pos], charsmax(hudText) - pos, "-> [WR] %s ^nMode: %s", targetName, modeName);

            // Show replay progress
            new timeText[32];
            FormatTimeMs(g_botReplayDurationMs > 0 ? floatround(g_botPlaybackTime * 1000.0) : 0, timeText, charsmax(timeText));
            new speed = GetReplayBotHorizontalSpeed();
            if (g_cacheSpeedometer)
                pos += formatex(hudText[pos], charsmax(hudText) - pos, "^nSpeed: %d u/s  |  %s", speed, timeText);
            else
                pos += formatex(hudText[pos], charsmax(hudText) - pos, "^n%s", timeText);
        }
        else
        {
            GetModeName(g_playerMode[target], modeName, charsmax(modeName));
            pos += formatex(hudText[pos], charsmax(hudText) - pos, "-> %s ^n%s", targetName, modeName);

            // Speed
            new speed = GetPlayerHorizontalSpeed(target);
            if (g_cacheSpeedometer)
                pos += formatex(hudText[pos], charsmax(hudText) - pos, "^nSpeed: %d u/s", speed);

            // Sync & strafes
            if (get_pcvar_num(g_cvarSpecHudShowSync) && g_iSyncFrames[target] > 0)
            {
                new iSync = floatround(100.0 * g_iGoodSync[target] / g_iSyncFrames[target]);
                pos += formatex(hudText[pos], charsmax(hudText) - pos, "  |  Sync: %d%%  |  Strafes: %d", iSync, g_iStrafes[target]);
            }

            // Timer
            if (g_timerState[target] == TIMER_RUNNING)
            {
                new timeText[32];
                g_currentTimeMs[target] = GetRunningTimeMs(target);
                FormatTimeMs(g_currentTimeMs[target], timeText, charsmax(timeText));
                pos += formatex(hudText[pos], charsmax(hudText) - pos, "^nTime: %s", timeText);

                // PB comparison
                if (g_bestTimeMs[target] > 0)
                {
                    new pbText[32];
                    FormatTimeMs(g_bestTimeMs[target], pbText, charsmax(pbText));
                    pos += formatex(hudText[pos], charsmax(hudText) - pos, "  |  PB: %s", pbText);
                }
            }
            else if (g_timerState[target] == TIMER_FINISHED)
            {
                new timeText[32];
                new finishTime = g_lastTimeMs[target] > 0 ? g_lastTimeMs[target] : g_currentTimeMs[target];
                FormatTimeMs(finishTime, timeText, charsmax(timeText));
                pos += formatex(hudText[pos], charsmax(hudText) - pos, "^nFinished: %s", timeText);
            }

            // Keys display
            if (get_pcvar_num(g_cvarSpecHudShowKeys))
            {
                new buttons = pev(target, pev_button);
                new keys[32];
                keys[0] = 0;

                if (buttons & IN_FORWARD)   add(keys, charsmax(keys), "[W]");
                if (buttons & IN_BACK)      add(keys, charsmax(keys), "[S]");
                if (buttons & IN_MOVELEFT)  add(keys, charsmax(keys), "[A]");
                if (buttons & IN_MOVERIGHT) add(keys, charsmax(keys), "[D]");
                if (buttons & IN_JUMP)      add(keys, charsmax(keys), "[J]");

                new flags = pev(target, pev_flags);
                if (flags & FL_DUCKING)     add(keys, charsmax(keys), "[Crouch]");

                if (keys[0])
                    pos += formatex(hudText[pos], charsmax(hudText) - pos, "^nKeys: %s", keys);
            }

            // WR comparison
            if (get_pcvar_num(g_cvarSpecHudShowWr) && g_timerState[target] == TIMER_RUNNING)
            {
                new wrTime = GetRecordTime(g_playerMode[target]);
                if (wrTime > 0 && g_currentTimeMs[target] > 0)
                {
                    new diffMs = g_currentTimeMs[target] - wrTime;
                    new diffText[32];
                    if (diffMs <= 0)
                    {
                        pos += formatex(hudText[pos], charsmax(hudText) - pos, "^nWR: AHEAD!");
                    }
                    else
                    {
                        FormatTimeMs(diffMs, diffText, charsmax(diffText));
                        new wrName[32];
                        GetRecordHolderName(g_playerMode[target], wrName, charsmax(wrName));
                        pos += formatex(hudText[pos], charsmax(hudText) - pos, "^nWR: +%s (%s)", diffText, wrName);
                    }
                }
            }
        }

        if (pos > 0)
        {
            set_hudmessage(200, 200, 80, 0.70, 0.16, 0, 0.0, interval + 0.2, 0.0, 0.0, 2);
            show_hudmessage(id, hudText);
        }
    }

    // Legacy spectator name list (always show on a different channel for non-enhanced)
    if (!enhanced)
    {
        new names[768], count;
        for (new id = 1; id <= MAX_PLAYERS; id++)
        {
            if (!is_user_connected(id) || is_user_alive(id) || is_user_bot(id) || is_user_hltv(id)) continue;
            new name[32]; get_user_name(id, name, charsmax(name));
            if (names[0]) add(names, charsmax(names), ", ");
            add(names, charsmax(names), name);
            count++;
        }
        if (count)
        {
            new text[896];
            formatex(text, charsmax(text), "Spectators (%d):^n%s", count, names);
            set_hudmessage(200, 200, 200, 0.70, 0.02, 0, 0.0, interval + 0.2, 0.0, 0.0, 2);
            for (new id = 1; id <= MAX_PLAYERS; id++)
                if (is_user_connected(id) && !is_user_alive(id)) show_hudmessage(id, text);
        }
    }
}

public CmdPro15(id)
{
    return ShowPro15Motd(id, 1);
}

stock ShowPro15Motd(id, page)
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

    new topLimit = get_pcvar_num(g_cvarTopLimit);
    if (topLimit < 1)
    {
        topLimit = 15;
    }

    new count = LoadBestFile(mode);
    SortBestCache(count);

    new totalPages = GetPageCount(count, topLimit);
    page = ClampPage(page, totalPages);

    new start = (page - 1) * topLimit;
    new end = start + topLimit;
    if (end > count)
    {
        end = count;
    }

    fprintf(fp, "<!DOCTYPE html><html><head><meta charset=^"utf-8^"><style>");
    fprintf(fp, "body{background:#050505;font:10px Arial,Helvetica,sans-serif;color:#e8e8e8;padding:5px;margin:0}");
    fprintf(fp, ".t{color:#fff;font-size:15px;font-weight:bold;margin:6px 6px 0;text-align:center;text-transform:uppercase}");
    fprintf(fp, ".p{background:#0d0d0d;border:1px solid #333;padding:8px}");
    fprintf(fp, ".nav{margin:0 0 8px;color:#aaa;font-size:9px;text-align:center}");
    fprintf(fp, ".nav b{color:#fff}");
    fprintf(fp, "table{width:100%%;border-collapse:collapse;table-layout:fixed}");
    fprintf(fp, "th{padding:3px 5px;border-top:1px solid #333;border-bottom:1px solid #444;background:#191919;color:#999;font-size:8px;text-align:left;text-transform:uppercase}");
    fprintf(fp, "td{height:17px;padding:1px 5px;overflow:hidden;border-bottom:1px solid #222;color:#ddd;font-size:10px;line-height:15px;text-overflow:ellipsis;white-space:nowrap}");
    fprintf(fp, ".e{background:#111}");
    fprintf(fp, ".r{width:92px;text-align:right;color:#fff;font-family:^"Courier New^",monospace;font-weight:bold}</style></head><body>");
    fprintf(fp, "<div class=^"t^">Pro Records - %s (%s)</div><div class=^"p^">", modeName, g_mapName);
    WriteMotdPageNav(fp, "/pro15", page, totalPages);
    fprintf(fp, "<table><thead><tr><th width=15%%>Rank</th><th>Player Name</th><th width=30%%>Best Time</th></tr></thead><tbody>");

    for (new i = start; i < end; i++)
    {
        new timeText[32], displayName[13];
        FormatTimeMs(g_fileTime[i], timeText, charsmax(timeText));
        copy(displayName, charsmax(displayName), g_fileName[i]);

        fprintf(fp, "<tr%s><td>#%d</td><td>%s</td><td>%s</td></tr>",
            ((i - start) % 2 == 1) ? " class=e" : "", i + 1, displayName, timeText);
    }

    if (count < 1)
    {
        fprintf(fp, "<tr><td colspan=3 align=center style=^"padding:20px^">No Pro records found.</td></tr>");
    }

    fprintf(fp, "</tbody></table>");
    WriteMotdPageNav(fp, "/pro15", page, totalPages);
    fprintf(fp, "</div></body></html>");
    fclose(fp);

    show_motd(id, filePath, "Pro Records");
    return PLUGIN_HANDLED;
}

stock GetPageCount(itemCount, pageSize)
{
    if (pageSize < 1)
    {
        pageSize = 15;
    }

    if (itemCount < 1)
    {
        return 1;
    }

    return (itemCount + pageSize - 1) / pageSize;
}

stock ClampPage(page, totalPages)
{
    if (totalPages < 1)
    {
        totalPages = 1;
    }

    if (page < 1)
    {
        return 1;
    }

    if (page > totalPages)
    {
        return totalPages;
    }

    return page;
}

stock WriteMotdPageNav(fp, const command[], page, totalPages)
{
    fprintf(fp, "<div class=^"nav^"><b>Page %d/%d</b>", page, totalPages);

    if (page > 1)
    {
        fprintf(fp, " | Prev: %s %d", command, page - 1);
    }

    if (page < totalPages)
    {
        fprintf(fp, " | Next: %s %d", command, page + 1);
    }

    fprintf(fp, "</div>");
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
    if (!g_cacheHookEnabled || !is_user_alive(id) || is_user_bot(id))
    {
        return PLUGIN_HANDLED;
    }

    if (IsNormalMode(g_playerMode[id]))
    {
        TimerChat(id, "Hook is disabled in Normal FPS categories.");
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

    TimerChat(id, "Map: ^x03%s ^x01| Storage: ^x04%s ^x01| Start: %s ^x01| Finish: %s",
        g_mapName,
        storage,
        g_zoneLoaded[ZONE_START] ? "^x04OK" : "^x03missing",
        g_zoneLoaded[ZONE_FINISH] ? "^x04OK" : "^x03missing");

    new modeName[32];
    GetModeName(g_playerMode[id], modeName, charsmax(modeName));
    if (g_playerMode[id] == MODE_SIMPLE)
        TimerChat(id, "Mode: ^x04%s^x01 | FPS: ^x04unrestricted^x01", modeName);
    else
        TimerChat(id, "Mode: ^x04%s^x01 | fps_max: ^x04%d^x01 | Legacy cvars: max ^x03%d^x01 / limit ^x03%d",
            modeName,
            GetModeFpsMax(g_playerMode[id]),
            get_pcvar_num(g_cvarNormalFpsMax),
            get_pcvar_num(g_cvarNormalFpsLimit));

    if (get_pcvar_num(g_cvarEconomyEnabled))
    {
        TimerChat(id, "Balance: ^x04%d^x01 | Earned: ^x04%d^x01 | Spent: ^x04%d",
            EconomyGetCredits(id), EconomyGetTotalCredits(id), EconomyGetSpentCredits(id));
    }

    return PLUGIN_HANDLED;
}

new g_marketMenuItems[MAX_PLAYERS + 1][10];
new g_marketMenuCount[MAX_PLAYERS + 1];
new g_marketCategory[MAX_PLAYERS + 1];
new g_playerSelectedSound[MAX_PLAYERS + 1];
new g_playerSelectedKnife[MAX_PLAYERS + 1];
new g_playerSelectedTrail[MAX_PLAYERS + 1];

public CmdKnifeMenuCore(id)
{
    if (!is_user_connected(id)) return PLUGIN_HANDLED;
    g_marketCategory[id] = 1;
    ShowMarketCategory(id, 1);
    return PLUGIN_HANDLED;
}

public CmdMarket(id)
{
    if (!g_cacheEconomyEnabled || !get_pcvar_num(g_cvarMarketEnabled))
    {
        TimerChat(id, "The market is currently disabled.");
        return PLUGIN_HANDLED;
    }

    g_playerMenuType[id] = MENU_MARKET;
    g_marketCategory[id] = 0;

    new menuText[1024], len = 0;

    new playerName[32];
    get_user_name(id, playerName, charsmax(playerName));

    new credits = EconomyGetCredits(id);
    new totalEarned = EconomyGetTotalCredits(id);
    new totalSpent = EconomyGetSpentCredits(id);
    new inventoryCount = g_playerInventoryCount[id];

    new badgeName[32];
    new badge = BadgeGetHighestForPlayer(id);
    if (badge >= 0)
        BadgeGetName(badge, badgeName, charsmax(badgeName));
    else
        copy(badgeName, charsmax(badgeName), "None");

    len += formatex(menuText[len], charsmax(menuText) - len, "\yMarket^n\d%s^n^n", playerName);
    len += formatex(menuText[len], charsmax(menuText) - len, "\wCredits: \y%d^n", credits);
    len += formatex(menuText[len], charsmax(menuText) - len, "\wEarned: \y%d \w| Spent: \y%d^n", totalEarned, totalSpent);
    len += formatex(menuText[len], charsmax(menuText) - len, "\wBadge: \y%s \w| Inventory: \y%d items^n", badgeName, inventoryCount);

    len += formatex(menuText[len], charsmax(menuText) - len, "^n\d[\r1\d]\w Knife Skins \d(4 items)^n");
    len += formatex(menuText[len], charsmax(menuText) - len, "\d[\r2\d]\w Sounds \d(3 items)^n");
    len += formatex(menuText[len], charsmax(menuText) - len, "\d[\r3\d]\w Misc \d(2 items)^n");
    len += formatex(menuText[len], charsmax(menuText) - len, "\d[\r4\d]\w VIP \d(2 items)^n");
    len += formatex(menuText[len], charsmax(menuText) - len, "\d[\r5\d]\w Trails \d(5 items)^n");

    len += formatex(menuText[len], charsmax(menuText) - len, "^n\d[\r6\d]\w My Inventory^n");
    len += formatex(menuText[len], charsmax(menuText) - len, "\d[\r0\d]\w Main Menu");

    show_menu(id, KEY_ALL_MENU, menuText, -1, "BhopTimer");
    return PLUGIN_HANDLED;
}

ShowMarketCategory(id, category)
{
    g_playerMenuType[id] = MENU_MARKET_SKINS + category - 1;
    g_marketMenuCount[id] = 0;

    new menuText[1024], len = 0;

    new credits = EconomyGetCredits(id);
    len += formatex(menuText[len], charsmax(menuText) - len, "\yCredits: \y%d^n^n", credits);

    if (category == 1)
    {
        new knifeIds[4] = {10, 11, 12, 13};
        new knifeNames[4][32] = {"Talon Knife", "Bayonet Knife", "Karambit Knife", "Butterfly Knife"};
        new knifePrices[4] = {2000, 2000, 2000, 2000};

        for (new i = 0; i < 4; i++)
        {
            new owned = EconomyPlayerHasItem(id, knifeIds[i]);
            new selected = (g_playerSelectedKnife[id] == knifeIds[i]);
            g_marketMenuItems[id][g_marketMenuCount[id]] = knifeIds[i];
            g_marketMenuCount[id]++;
            if (owned)
                len += formatex(menuText[len], charsmax(menuText) - len, "\d[\r%d\d]\w %s - \y%d credits%s%s^n",
                    g_marketMenuCount[id], knifeNames[i], knifePrices[i], " \w[OWNED]", selected ? " \y[SELECTED]" : "");
            else
                len += formatex(menuText[len], charsmax(menuText) - len, "\d[\r%d\d]\w %s - \y%d credits^n",
                    g_marketMenuCount[id], knifeNames[i], knifePrices[i]);
        }
    }
    else if (category == 2)
    {
        new soundIds[3] = {30, 31, 32};
        new soundNames[3][32] = {"WR Sound 1", "WR Sound 2", "WR Sound 3"};
        new soundPrices[3] = {1500, 1500, 1500};

        for (new i = 0; i < 3; i++)
        {
            new owned = EconomyPlayerHasItem(id, soundIds[i]);
            new selected = (g_playerSelectedSound[id] == soundIds[i]);
            g_marketMenuItems[id][g_marketMenuCount[id]] = soundIds[i];
            g_marketMenuCount[id]++;
            if (owned)
                len += formatex(menuText[len], charsmax(menuText) - len, "\d[\r%d\d]\w %s - \y%d credits%s%s^n",
                    g_marketMenuCount[id], soundNames[i], soundPrices[i], " \w[OWNED]", selected ? " \y[SELECTED]" : "");
            else
                len += formatex(menuText[len], charsmax(menuText) - len, "\d[\r%d\d]\w %s - \y%d credits^n",
                    g_marketMenuCount[id], soundNames[i], soundPrices[i]);
        }
    }
    else if (category == 3)
    {
        new otherIds[2] = {1, 2};
        new otherNames[2][32] = {"Custom Chat Prefix", "Custom Welcome Message"};
        new otherPrices[2] = {1000, 500};

        for (new i = 0; i < 2; i++)
        {
            new owned = EconomyPlayerHasItem(id, otherIds[i]);
            g_marketMenuItems[id][g_marketMenuCount[id]] = otherIds[i];
            g_marketMenuCount[id]++;
            len += formatex(menuText[len], charsmax(menuText) - len, "\d[\r%d\d]\w %s - \y%d credits%s^n",
                g_marketMenuCount[id], otherNames[i], otherPrices[i], owned ? " \w[OWNED]" : "");
        }
    }
    else if (category == 4)
    {
        new vipIds[2] = {20, 21};
        new vipNames[2][32] = {"VIP Gold Knife", "VIP M9 Bayonet"};
        new vipPrices[2] = {3000, 3000};

        for (new i = 0; i < 2; i++)
        {
            new owned = EconomyPlayerHasItem(id, vipIds[i]);
            new selected = (g_playerSelectedKnife[id] == vipIds[i]);
            g_marketMenuItems[id][g_marketMenuCount[id]] = vipIds[i];
            g_marketMenuCount[id]++;
            if (owned)
                len += formatex(menuText[len], charsmax(menuText) - len, "\d[\r%d\d]\w %s - \y%d credits%s%s^n",
                    g_marketMenuCount[id], vipNames[i], vipPrices[i], " \w[OWNED]", selected ? " \y[SELECTED]" : "");
            else
                len += formatex(menuText[len], charsmax(menuText) - len, "\d[\r%d\d]\w %s - \y%d credits^n",
                    g_marketMenuCount[id], vipNames[i], vipPrices[i]);
        }
    }
    else if (category == 5)
    {
        new trailIds[5] = {40, 41, 42, 43, 44};
        new trailNames[5][32] = {"Red Trail", "Blue Trail", "Green Trail", "Yellow Trail", "Purple Trail"};
        new trailPrices[5] = {1000, 1000, 1000, 1000, 1000};

        for (new i = 0; i < 5; i++)
        {
            new owned = EconomyPlayerHasItem(id, trailIds[i]);
            new selected = (g_playerSelectedTrail[id] == trailIds[i]);
            g_marketMenuItems[id][g_marketMenuCount[id]] = trailIds[i];
            g_marketMenuCount[id]++;
            if (owned)
                len += formatex(menuText[len], charsmax(menuText) - len, "\d[\r%d\d]\w %s - \y%d credits%s%s^n",
                    g_marketMenuCount[id], trailNames[i], trailPrices[i], " \w[OWNED]", selected ? " \y[SELECTED]" : "");
            else
                len += formatex(menuText[len], charsmax(menuText) - len, "\d[\r%d\d]\w %s - \y%d credits^n",
                    g_marketMenuCount[id], trailNames[i], trailPrices[i]);
        }
    }
    else if (category == 6)
    {
        ShowPlayerInventory(id);
        return;
    }

    len += formatex(menuText[len], charsmax(menuText) - len, "^n\d[\r0\d]\w Back");

    show_menu(id, KEY_ALL_MENU, menuText, -1, "BhopTimer");
}

ShowPlayerInventory(id)
{
    g_playerMenuType[id] = MENU_MARKET_SKINS + 3;
    g_marketMenuCount[id] = 0;

    new menuText[1024], len = 0;

    new inventoryCount = g_playerInventoryCount[id];
    if (inventoryCount <= 0)
    {
        len += formatex(menuText[len], charsmax(menuText) - len, "\yYour Inventory^n^n");
        len += formatex(menuText[len], charsmax(menuText) - len, "\dYour inventory is empty^n");
        len += formatex(menuText[len], charsmax(menuText) - len, "\dBrowse the market to buy items^n");
    }
    else
    {
        len += formatex(menuText[len], charsmax(menuText) - len, "\yYour Inventory^n\wItems: \y%d^n^n", inventoryCount);

        for (new i = 0; i < inventoryCount && g_marketMenuCount[id] < 10; i++)
        {
            new itemId = g_playerInventory[id][i][INV_ITEM_ID];
            new slot = EconomyFindMarketItem(itemId);
            if (slot < 0) continue;

            new item[MarketItem];
            if (!EconomyGetMarketItem(slot, item)) continue;

            g_marketMenuItems[id][g_marketMenuCount[id]] = item[MI_ID];
            g_marketMenuCount[id]++;
            len += formatex(menuText[len], charsmax(menuText) - len, "\d[\r%d\d]\w %s \w- \yOwned^n",
                g_marketMenuCount[id], item[MI_NAME]);
        }
    }

    len += formatex(menuText[len], charsmax(menuText) - len, "^n\d[\r0\d]\w Back");
    show_menu(id, KEY_ALL_MENU, menuText, -1, "BhopTimer");
}

public CmdBuy(id)
{
    if (!get_pcvar_num(g_cvarEconomyEnabled) || !get_pcvar_num(g_cvarMarketEnabled))
    {
        TimerChat(id, "The market is currently disabled.");
        return PLUGIN_HANDLED;
    }

    new arg[8];
    read_args(arg, charsmax(arg));
    remove_quotes(arg);
    trim(arg);

    if (!arg[0])
    {
        TimerChat(id, "Usage: ^x04/buy <item_id>");
        return PLUGIN_HANDLED;
    }

    new itemId = str_to_num(arg);
    EconomyBuyItem(id, itemId);
    return PLUGIN_HANDLED;
}

public CmdInventory(id)
{
    if (!get_pcvar_num(g_cvarEconomyEnabled))
    {
        TimerChat(id, "The economy system is currently disabled.");
        return PLUGIN_HANDLED;
    }

    if (g_playerInventoryCount[id] <= 0)
    {
        TimerChat(id, "Your inventory is empty.");
        return PLUGIN_HANDLED;
    }

    TimerChat(id, "Inventory:");
    for (new i = 0; i < g_playerInventoryCount[id]; i++)
    {
        new slot = EconomyFindMarketItem(g_playerInventory[id][i][INV_ITEM_ID]);
        if (slot >= 0)
        {
            TimerChat(id, "- ^x04%s", g_marketItems[slot][MI_NAME]);
        }
    }

    return PLUGIN_HANDLED;
}

public CmdCredits(id)
{
    if (!get_pcvar_num(g_cvarEconomyEnabled))
    {
        TimerChat(id, "The economy system is currently disabled.");
        return PLUGIN_HANDLED;
    }

    TimerChat(id, "Balance: ^x04%d^x01 | Earned: ^x04%d^x01 | Spent: ^x04%d",
        EconomyGetCredits(id), EconomyGetTotalCredits(id), EconomyGetSpentCredits(id));

    if (EconomyHasHookReward(id))
    {
        TimerChat(id, "Hook speed reward is ^x04 active^x01.");
    }
    else
    {
        new required = get_pcvar_num(g_cvarHookRewardCredits);
        if (required < 1) required = 1000;
        new remaining = required - EconomyGetTotalCredits(id);
        if (remaining < 0) remaining = 0;
        TimerChat(id, "Earn more credits to unlock rewards! (Next: ^x04%d^x01 credits)",
            remaining);
    }

    return PLUGIN_HANDLED;
}

public CmdBadges(id)
{
    if (!get_pcvar_num(g_cvarEconomyEnabled))
    {
        TimerChat(id, "The economy system is currently disabled.");
        return PLUGIN_HANDLED;
    }

    g_playerMenuType[id] = MENU_BADGES;
    g_playerMenuPage[id] = 0;

    new menuText[1024], len = 0;

    new playerName[32];
    get_user_name(id, playerName, charsmax(playerName));

    new total = EconomyGetTotalCredits(id);
    new badge = BadgeGetHighestForPlayer(id);
    new badgeName[32];
    if (badge >= 0)
        BadgeGetName(badge, badgeName, charsmax(badgeName));
    else
        copy(badgeName, charsmax(badgeName), "None");

    len += formatex(menuText[len], charsmax(menuText) - len, "\yYour Badges^n\d%s^n^n", playerName);
    len += formatex(menuText[len], charsmax(menuText) - len, "\wTotal Credits: \y%d^n", total);
    len += formatex(menuText[len], charsmax(menuText) - len, "\wCurrent Badge: \y%s^n", badgeName);

    new nextBadge = -1;
    for (new i = 0; i < MAX_BADGES; i++)
    {
        if (total < g_badgeThresholds[i])
        {
            nextBadge = i;
            break;
        }
    }

    if (nextBadge >= 0)
    {
        new prevThreshold = (nextBadge > 0) ? g_badgeThresholds[nextBadge - 1] : 0;
        new progress = total - prevThreshold;
        new needed = g_badgeThresholds[nextBadge] - prevThreshold;

        len += formatex(menuText[len], charsmax(menuText) - len, "^n\wNext: \y%s\w at \y%d credits^n", g_badgeNames[nextBadge], g_badgeThresholds[nextBadge]);
        len += formatex(menuText[len], charsmax(menuText) - len, "\wProgress: \y%d\w/\y%d^n", progress, needed);
    }
    else
    {
        len += formatex(menuText[len], charsmax(menuText) - len, "^n\wNext: \yAll badges earned!^n");
    }

    if (EconomyHasHookReward(id))
    {
        len += formatex(menuText[len], charsmax(menuText) - len, "^n\wHook Speed: \yUnlocked^n");
    }
    else
    {
        new required = get_pcvar_num(g_cvarHookRewardCredits);
        if (required < 1) required = 1000;
        new remaining = required - total;
        if (remaining < 0) remaining = 0;
        len += formatex(menuText[len], charsmax(menuText) - len, "^n\wHook Speed: \rLocked\w (\y%d\w more credits)^n", remaining);
    }

    len += formatex(menuText[len], charsmax(menuText) - len, "^n\d[\r1\d]\w View Top Badges^n");
    len += formatex(menuText[len], charsmax(menuText) - len, "^n\d[\r0\d]\w Main Menu");

    show_menu(id, KEY_ALL_MENU, menuText, -1, "BhopTimer");
    return PLUGIN_HANDLED;
}

public CmdTopBadges(id)
{
    return ShowTopBadgesMotd(id, 1);
}

stock ShowTopBadgesMotd(id, page)
{
    log_amx("[TIMER] CmdTopBadges: id=%d economy=%d", id, get_pcvar_num(g_cvarEconomyEnabled));
    if (!get_pcvar_num(g_cvarEconomyEnabled))
    {
        TimerChat(id, "The economy system is currently disabled.");
        return PLUGIN_HANDLED;
    }

    new dataDir[128], filePath[192];
    get_datadir(dataDir, charsmax(dataDir));
    formatex(filePath, charsmax(filePath), "%s/bhop_topbadges_%d.html", dataDir, id);

    GenerateTopBadgesMotd(filePath, page);
    log_amx("[TIMER] CmdTopBadges: generated %s", filePath);
    show_motd(id, filePath, "Top Badges");
    log_amx("[TIMER] CmdTopBadges: show_motd called");
    return PLUGIN_HANDLED;
}

stock GenerateTopBadgesMotd(filePath[], page)
{
    new entryCount = 0;
    static entryName[MAX_LEADERBOARD_ENTRIES][MAX_PLAYER_NAME_LEN];
    static entryTotal[MAX_LEADERBOARD_ENTRIES];
    static entrySteam64[MAX_LEADERBOARD_ENTRIES][MAX_STEAMID64_LEN + 1];

    // Load local entries first.
    new path[192];
    EconomyBuildPath(path, charsmax(path), ECONOMY_PLAYERS_FILE);

    if (file_exists(path))
    {
        new line[512], lineLen;
        new fileLines = file_size(path, 1);

        for (new i = 0; i < fileLines && entryCount < MAX_LEADERBOARD_ENTRIES; i++)
        {
            if (!read_file(path, i, line, charsmax(line), lineLen) || lineLen <= 0)
            {
                continue;
            }

            trim(line);
            if (!line[0] || line[0] == ';')
            {
                continue;
            }

            new fileSteam64[MAX_STEAMID64_LEN + 1], storedName[32], regStr[4], totalStr[16], spentStr[16], rewardStr[4], prefix[MAX_CUSTOM_PREFIX_LEN + 1];
            if (parse(line, fileSteam64, charsmax(fileSteam64), storedName, charsmax(storedName), regStr, charsmax(regStr), totalStr, charsmax(totalStr), spentStr, charsmax(spentStr), rewardStr, charsmax(rewardStr), prefix, charsmax(prefix)) < 4)
            {
                continue;
            }

            new totalCredits = str_to_num(totalStr);
            if (totalCredits <= 0)
            {
                continue;
            }

            copy(entrySteam64[entryCount], MAX_STEAMID64_LEN, fileSteam64);
            copy(entryName[entryCount], MAX_PLAYER_NAME_LEN - 1, storedName);
            entryTotal[entryCount] = totalCredits;
            entryCount++;
        }
    }

    // MySQL is authoritative: override existing entries and append new ones.
    if (g_dbReady && g_sqlTuple != Empty_Handle)
    {
        new errcode, sqErr[128];
        new Handle:conn = SQL_Connect(g_sqlTuple, errcode, sqErr, charsmax(sqErr));
        if (conn != Empty_Handle)
        {
            new queryText[256], prefixedQuery[256];
            copy(queryText, charsmax(queryText), "SELECT player_key,name,total_credits FROM bhop_players WHERE total_credits > 0;");
            ApplySqlPrefix(queryText, prefixedQuery, charsmax(prefixedQuery));
            new Handle:query = SQL_PrepareQuery(conn, prefixedQuery);
            if (query != Empty_Handle && SQL_Execute(query))
            {
                while (SQL_MoreResults(query) && entryCount < MAX_LEADERBOARD_ENTRIES)
                {
                    new dbSteam64[MAX_STEAMID64_LEN + 1], dbName[MAX_PLAYER_NAME_LEN];
                    SQL_ReadResult(query, 0, dbSteam64, charsmax(dbSteam64));
                    SQL_ReadResult(query, 1, dbName, charsmax(dbName));
                    new dbTotal = SQL_ReadResult(query, 2);

                    new idx = -1;
                    for (new i = 0; i < entryCount; i++)
                    {
                        if (equal(entrySteam64[i], dbSteam64))
                        {
                            idx = i;
                            break;
                        }
                    }

                    if (idx >= 0)
                    {
                        copy(entryName[idx], MAX_PLAYER_NAME_LEN - 1, dbName);
                        entryTotal[idx] = dbTotal;
                    }
                    else
                    {
                        copy(entrySteam64[entryCount], MAX_STEAMID64_LEN, dbSteam64);
                        copy(entryName[entryCount], MAX_PLAYER_NAME_LEN - 1, dbName);
                        entryTotal[entryCount] = dbTotal;
                        entryCount++;
                    }

                    SQL_NextRow(query);
                }
            }
            if (query != Empty_Handle)
            {
                SQL_FreeHandle(query);
            }
            SQL_FreeHandle(conn);
        }
        else
        {
            log_amx("[TIMER] GenerateTopBadgesMotd: DB connect failed (%d): %s", errcode, sqErr);
        }
    }

    if (entryCount < 1)
    {
        new fp = fopen(filePath, "wt");
        if (fp)
        {
            fprintf(fp, "<!DOCTYPE html><html><head><meta charset=^"utf-8^"><style>");
            fprintf(fp, "body{background:#050505;font:10px Arial,Helvetica,sans-serif;color:#e8e8e8;padding:5px;margin:0}");
            fprintf(fp, ".t{color:#fff;font-size:15px;font-weight:bold;margin:6px 6px 0;text-align:center;text-transform:uppercase}");
            fprintf(fp, ".p{background:#0d0d0d;border:1px solid #333;padding:8px;margin-top:6px;text-align:center;color:#777}</style></head><body>");
            fprintf(fp, "<div class=^"t^">Top Badges</div><div class=^"p^">No player profiles yet.</div></body></html>");
            fclose(fp);
        }
        return;
    }

    for (new i = 0; i < entryCount - 1; i++)
    {
        for (new j = i + 1; j < entryCount; j++)
        {
            if (entryTotal[j] > entryTotal[i])
            {
                new tmpTotal = entryTotal[i];
                entryTotal[i] = entryTotal[j];
                entryTotal[j] = tmpTotal;

                new tmpName[MAX_PLAYER_NAME_LEN];
                copy(tmpName, MAX_PLAYER_NAME_LEN - 1, entryName[i]);
                copy(entryName[i], MAX_PLAYER_NAME_LEN - 1, entryName[j]);
                copy(entryName[j], MAX_PLAYER_NAME_LEN - 1, tmpName);

                new tmpSteam64[MAX_STEAMID64_LEN + 1];
                copy(tmpSteam64, MAX_STEAMID64_LEN, entrySteam64[i]);
                copy(entrySteam64[i], MAX_STEAMID64_LEN, entrySteam64[j]);
                copy(entrySteam64[j], MAX_STEAMID64_LEN, tmpSteam64);
            }
        }
    }

    new fp = fopen(filePath, "wt");
    if (!fp)
    {
        return;
    }

    new pageSize = TOP_BADGES_PAGE_SIZE;
    new totalPages = GetPageCount(entryCount, pageSize);
    page = ClampPage(page, totalPages);

    new start = (page - 1) * pageSize;
    new end = start + pageSize;
    if (end > entryCount)
    {
        end = entryCount;
    }

    fprintf(fp, "<!DOCTYPE html><html><head><meta charset=^"utf-8^"><style>");
    fprintf(fp, "body{background:#050505;font:10px Arial,Helvetica,sans-serif;color:#e8e8e8;padding:5px;margin:0}");
    fprintf(fp, ".t{color:#fff;font-size:15px;font-weight:bold;margin:6px 6px 0;text-align:center;text-transform:uppercase}");
    fprintf(fp, ".p{background:#0d0d0d;border:1px solid #333;padding:8px}");
    fprintf(fp, ".nav{margin:0 0 8px;color:#aaa;font-size:9px;text-align:center}");
    fprintf(fp, ".nav b{color:#fff}");
    fprintf(fp, "table{width:100%%;border-collapse:collapse;table-layout:fixed}");
    fprintf(fp, "th{padding:3px 5px;border-top:1px solid #333;border-bottom:1px solid #444;background:#191919;color:#999;font-size:8px;text-align:left;text-transform:uppercase}");
    fprintf(fp, "td{height:17px;padding:1px 5px;overflow:hidden;border-bottom:1px solid #222;color:#ddd;font-size:10px;line-height:15px;text-overflow:ellipsis;white-space:nowrap}");
    fprintf(fp, ".e{background:#111}");
    fprintf(fp, ".r{color:#FF5555;font-weight:bold}");
    fprintf(fp, ".g{color:#55FF55;font-weight:bold}");
    fprintf(fp, ".b{color:#5555FF;font-weight:bold}");
    fprintf(fp, ".w{color:#FFFFFF;font-weight:bold}");
    fprintf(fp, "</style></head><body>");
    fprintf(fp, "<div class=^"t^">Top Badges - All Players</div><div class=^"p^">");
    WriteMotdPageNav(fp, "/topbadges", page, totalPages);
    fprintf(fp, "<table><thead><tr><th width=10%%>#</th><th width=45%%>Player</th><th width=25%%>Total Credits</th><th width=20%%>Badge</th></tr></thead><tbody>");

    for (new i = start; i < end; i++)
    {
        new badgeIdx = BadgeGetHighestForCredits(entryTotal[i]);
        new badgeName[MAX_BADGE_NAME_LEN + 1];

        if (badgeIdx >= 0)
        {
            BadgeGetName(badgeIdx, badgeName, charsmax(badgeName));
        }
        else
        {
            copy(badgeName, charsmax(badgeName), "-");
        }

        new cssClass[8];
        if (badgeIdx >= 8)
            copy(cssClass, charsmax(cssClass), "w");
        else if (badgeIdx >= 6)
            copy(cssClass, charsmax(cssClass), "g");
        else if (badgeIdx >= 4)
            copy(cssClass, charsmax(cssClass), "b");
        else if (badgeIdx >= 0)
            copy(cssClass, charsmax(cssClass), "r");
        else
            copy(cssClass, charsmax(cssClass), "e");

        if ((i - start) % 2 == 0)
        {
            fprintf(fp, "<tr><td>%d</td><td>%s</td><td>%d</td><td class=^"%s^">%s</td></tr>", i + 1, entryName[i], entryTotal[i], cssClass, badgeName);
        }
        else
        {
            fprintf(fp, "<tr class=e><td>%d</td><td>%s</td><td>%d</td><td class=^"%s^">%s</td></tr>", i + 1, entryName[i], entryTotal[i], cssClass, badgeName);
        }
    }

    fprintf(fp, "</tbody></table>");
    WriteMotdPageNav(fp, "/topbadges", page, totalPages);
    fprintf(fp, "</div></body></html>");
    fclose(fp);
}

public CmdTrail(id)
{
    if (!is_user_connected(id))
        return PLUGIN_HANDLED;

    g_playerMenuType[id] = MENU_TRAIL;

    new menuText[1024], len = 0;

    len += formatex(menuText[len], charsmax(menuText) - len, "\yTrail Selection^n^n");

    new bool:hasTrail = g_playerTrail[id];

    if (hasTrail)
    {
        len += formatex(menuText[len], charsmax(menuText) - len, "\wCurrent Trail: \yActive^n");
        len += formatex(menuText[len], charsmax(menuText) - len, "\wColor: \yR:%d G:%d B:%d^n^n", g_playerTrailColor[id][0], g_playerTrailColor[id][1], g_playerTrailColor[id][2]);
    }
    else
    {
        len += formatex(menuText[len], charsmax(menuText) - len, "\wCurrent Trail: \rNone^n^n");
    }

    new trailIds[5] = {40, 41, 42, 43, 44};
    new trailNames[5][32] = {"Red Trail", "Blue Trail", "Green Trail", "Yellow Trail", "Purple Trail"};
    new trailColors[5][3] = {{255,0,0}, {0,100,255}, {0,255,0}, {255,255,0}, {200,0,255}};
    new ownedCount = 0;

    for (new i = 0; i < 5; i++)
    {
        if (EconomyPlayerHasItem(id, trailIds[i]))
        {
            new isActive = (hasTrail && g_playerTrailColor[id][0] == trailColors[i][0] && g_playerTrailColor[id][1] == trailColors[i][1] && g_playerTrailColor[id][2] == trailColors[i][2]);
            g_marketMenuItems[id][ownedCount] = trailIds[i];
            ownedCount++;
            len += formatex(menuText[len], charsmax(menuText) - len, "\d[\r%d\d]\w %s%s^n", ownedCount, trailNames[i], isActive ? " \y[ACTIVE]" : "");
        }
    }

    g_marketMenuCount[id] = ownedCount;

    if (ownedCount == 0)
    {
        len += formatex(menuText[len], charsmax(menuText) - len, "\dYou don't own any trails yet^n");
        len += formatex(menuText[len], charsmax(menuText) - len, "\dBrowse /market to buy trails^n");
    }

    if (hasTrail)
    {
        len += formatex(menuText[len], charsmax(menuText) - len, "^n\d[\r6\d]\w Disable Trail");
    }

    len += formatex(menuText[len], charsmax(menuText) - len, "^n\d[\r0\d]\w Main Menu");

    show_menu(id, KEY_ALL_MENU, menuText, -1, "BhopTimer");
    return PLUGIN_HANDLED;
}

public HandleTrailMenu(id, key)
{
    g_playerMenuType[id] = MENU_NONE;

    if (key == 9)
    {
        CmdMainMenu(id);
        return;
    }

    if (key == 5 && g_playerTrail[id])
    {
        RemovePlayerTrail(id);
        TimerChat(id, "^x04[TRAIL]^x01 Trail disabled.");
        CmdTrail(id);
        return;
    }

    if (key >= 0 && key < g_marketMenuCount[id])
    {
        new trailIds[5] = {40, 41, 42, 43, 44};
        new trailColors[5][3] = {{255,0,0}, {0,100,255}, {0,255,0}, {255,255,0}, {200,0,255}};

        new itemId = g_marketMenuItems[id][key];

        for (new i = 0; i < 5; i++)
        {
            if (trailIds[i] == itemId)
            {
                SetPlayerTrail(id, trailColors[i][0], trailColors[i][1], trailColors[i][2]);
                TimerChat(id, "^x04[TRAIL]^x01 Trail activated!");
                break;
            }
        }

        CmdTrail(id);
    }
}

public CmdSetPrefix(id)
{
    if (!get_pcvar_num(g_cvarEconomyEnabled))
    {
        TimerChat(id, "The economy system is currently disabled.");
        return PLUGIN_HANDLED;
    }

    new arg[96], prefix[48];
    read_args(arg, charsmax(arg));
    remove_quotes(arg);
    trim(arg);
    log_amx("[TIMER] CmdSetPrefix raw: '%s'", arg);

    // register_clcmd("say /setprefix") passes the command in argv(1) and any
    // trailing text in argv(2). read_args() only returns the matched command.
    read_argv(2, prefix, charsmax(prefix));
    remove_quotes(prefix);
    trim(prefix);
    log_amx("[TIMER] CmdSetPrefix argv(2): '%s'", prefix);

    EconomySetCustomPrefix(id, prefix);
    return PLUGIN_HANDLED;
}

// Manual fallback for /setprefix <text> because AMX Mod X sometimes fails to
// route commands with trailing text through the registered say /setprefix hook.
stock HandleSetPrefixFromChat(id, const message[])
{
    if (!get_pcvar_num(g_cvarEconomyEnabled))
    {
        TimerChat(id, "The economy system is currently disabled.");
        return;
    }

    new prefix[48];
    new pos = 10; // length of "/setprefix"
    while (message[pos] == ' ')
    {
        pos++;
    }
    copy(prefix, charsmax(prefix), message[pos]);
    remove_quotes(prefix);
    trim(prefix);
    log_amx("[TIMER] HandleSetPrefixFromChat message='%s' prefix='%s'", message, prefix);
    EconomySetCustomPrefix(id, prefix);
}

public CmdSetWelcome(id)
{
    if (!EconomyPlayerHasItem(id, 2))
    {
        TimerChat(id, "You need to buy ^x04Custom Join Message^x01 from ^x04/market^x01 first.");
        return PLUGIN_HANDLED;
    }

    new arg[128], msg[64];
    read_args(arg, charsmax(arg));
    remove_quotes(arg);
    trim(arg);

    read_argv(2, msg, charsmax(msg));
    remove_quotes(msg);
    trim(msg);

    if (!msg[0])
    {
        TimerChat(id, "Usage: ^x04/setwelcome <text>");
        return PLUGIN_HANDLED;
    }

    SaveJoinMessage(id, msg);
    TimerChat(id, "Your join message is now: ^x04%s", msg);
    return PLUGIN_HANDLED;
}

stock HandleSetWelcomeFromChat(id, const message[])
{
    if (!EconomyPlayerHasItem(id, 2))
    {
        TimerChat(id, "You need to buy ^x04Custom Join Message^x01 from ^x04/market^x01 first.");
        return;
    }

    new msg[64];
    new pos = 0;

    if (equali(message, "/setwelcome", 11))
        pos = 11;
    else if (equali(message, "/joinmessage", 12))
        pos = 12;
    else
        return;

    while (message[pos] == ' ')
    {
        pos++;
    }
    copy(msg, charsmax(msg), message[pos]);
    remove_quotes(msg);
    trim(msg);

    if (!msg[0])
    {
        TimerChat(id, "Usage: ^x04/setwelcome <text>^x01 or ^x04/joinmessage <text>");
        return;
    }

    SaveJoinMessage(id, msg);
    TimerChat(id, "Your join message is now: ^x04%s", msg);
}

stock SaveJoinMessage(id, const msg[])
{
    EconomyLocalSetSetting(id, "join_message", msg);
    new auth[35];
    get_user_authid(id, auth, charsmax(auth));

    new path[192];
    EconomyBuildPath(path, charsmax(path), "bhop_timer/join_messages.ini");

    new line[512], len;
    new lines = file_size(path, 1);
    new found = -1;

    for (new i = 0; i < lines; i++)
    {
        if (!read_file(path, i, line, charsmax(line), len) || len <= 0)
            continue;

        trim(line);
        if (!line[0] || line[0] == ';')
            continue;

        new fileSteam[34];
        parse(line, fileSteam, charsmax(fileSteam));

        if (equal(fileSteam, auth))
        {
            found = i;
            break;
        }
    }

    new data[256];
    formatex(data, charsmax(data), "%s ^"%s^"", auth, msg);

    if (found >= 0)
    {
        write_file(path, data, found);
    }
    else
    {
        write_file(path, data);
    }
}

public CmdBlocked(id)
{
    if (g_cacheBlockServerCommands)
    {
        TimerChat(id, "This command is disabled in bhop mode.");
        return PLUGIN_HANDLED;
    }

    return PLUGIN_CONTINUE;
}

public CmdBlockedTeam(id)
{
    if (g_cacheBlockServerCommands)
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

    if (g_cacheBlockServerCommands)
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

    if (g_cacheBlockServerCommands)
    {
        QueueAutoJoinCt(id, 0.1);
        return PLUGIN_HANDLED;
    }

    return PLUGIN_CONTINUE;
}

public FwTouch(ent, id)
{
    if (!(1 <= id <= MAX_PLAYERS) || !is_user_alive(id) || !pev_valid(ent))
    {
        return FMRES_IGNORED;
    }

    new classname[32];
    pev(ent, pev_classname, classname, charsmax(classname));

    if (g_cacheTeleportFix)
    {
        new bool:bIsTeleport = bool:(equal(classname, "trigger_teleport"));

        if (!bIsTeleport && equal(classname, "trigger_multiple"))
        {
            new szTarget[32];
            pev(ent, pev_target, szTarget, charsmax(szTarget));
            if (szTarget[0])
            {
                new targetEnt = find_ent_by_target(-1, szTarget);
                if (targetEnt)
                {
                    new targetClass[32];
                    pev(targetEnt, pev_classname, targetClass, charsmax(targetClass));
                    bIsTeleport = equal(targetClass, "info_teleport_destination") ||
                                  equal(targetClass, "info_target") ||
                                  containi(targetClass, "teleport") != -1;
                }
            }
        }

        if (bIsTeleport)
        {
            new szTarget[32];
            pev(ent, pev_target, szTarget, charsmax(szTarget));
            if (szTarget[0])
            {
                new targetEnt = find_ent_by_target(-1, szTarget);
                if (targetEnt)
                {
                    new Float:origin[3];
                    pev(targetEnt, pev_origin, origin);
                    engfunc(EngFunc_SetOrigin, id, origin);

                    new Float:angles[3];
                    pev(targetEnt, pev_angles, angles);
                    set_pev(id, pev_angles, angles);
                    set_pev(id, pev_v_angle, angles);
                    set_pev(id, pev_fixangle, 1);

                    if (!g_cacheKeepTeleportVelocity)
                    {
                        new Float:zero[3];
                        set_pev(id, pev_velocity, zero);
                        set_pev(id, pev_basevelocity, zero);
                    }
                }
            }
            return FMRES_SUPERCEDE;
        }
    }

    if (!g_cacheBlockWeaponPickup)
    {
        return FMRES_IGNORED;
    }

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

    log_amx("[TIMER] CmdBhopMenu: opening bhop_timer zone editor for id=%d", id);
    ShowBhopMenu(id);
    return PLUGIN_HANDLED;
}

public TaskShowStartMenu(taskid)
{
    new id = taskid - TASK_START_MENU;

    if (!(1 <= id <= MAX_PLAYERS) || !is_user_connected(id) || is_user_bot(id))
    {
        return;
    }

    if (!g_cacheStartMenuOnJoin)
    {
        return;
    }

    // Don't override a menu the player already opened manually.
    if (g_playerMenuType[id] != MENU_NONE)
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

public TaskRetryModeFpsMax(taskid)
{
    new id = taskid - TASK_MODE_FPS_RETRY;

    if (1 <= id <= MAX_PLAYERS && is_user_connected(id))
    {
        ApplyModeFpsMax(id, false);
    }
}

public TaskNormalFpsCheck()
{
    if (!get_pcvar_num(g_cvarEnabled))
    {
        return;
    }

    new bool:enforce = g_cacheNormalFpsEnforce ? true : false;
    new Float:now = get_gametime();

    for (new id = 1; id <= MAX_PLAYERS; id++)
    {
        if (!is_user_connected(id) || is_user_bot(id))
        {
            g_modeFpsFrames[id] = 0;
            g_modeFpsValue[id] = 0;
            continue;
        }

        if (g_fpsMsecSamples[id] >= 4 && g_fpsMsecSum[id] > 0)
            g_modeFpsValue[id] = floatround(float(g_fpsMsecSamples[id] * 1000) / float(g_fpsMsecSum[id]));
        else
            g_modeFpsValue[id] = g_modeFpsFrames[id];
        g_modeFpsFrames[id] = 0;
        g_fpsMsecSum[id] = 0;
        g_fpsMsecSamples[id] = 0;

        if (is_user_alive(id) && (IsNormalMode(g_playerMode[id])
            || (IsDuelSettingsLocked(id) && g_duelMode[id] != MODE_SIMPLE))
            && now - g_lastFpsQuery[id] >= 3.0)
            QueryPlayerFps(id);

        if (!enforce || !IsNormalMode(g_playerMode[id]) || !is_user_alive(id))
        {
            continue;
        }

        new limit = GetNormalModeFps(g_playerMode[id]);
        new tolerance = get_pcvar_num(g_cvarNormalFpsWarnTolerance);

        if (g_modeFpsValue[id] > limit + tolerance)
        {
            if (g_timerState[id] == TIMER_RUNNING)
            {
                ResetPlayerData(id, false);
                ShowCenterHudMessage(id, "FPS Too High - Timer Reset", 255, 80, 80, 1.2);
            }

            if (now - g_lastNormalFpsWarn[id] >= 10.0)
            {
                TimerChat(id, "Normal mode FPS limit is ^x04%d^x01. Your FPS: ^x03%d^x01. FPS limit reapplied; run will not count until your FPS is within limit.", limit, g_modeFpsValue[id]);
                g_lastNormalFpsWarn[id] = now;
            }
        }
    }
}

stock ApplyModeFpsMax(id, bool:scheduleRetry = true)
{
    if (!is_user_connected(id) || is_user_bot(id))
    {
        return;
    }

    if (g_playerMode[id] == MODE_SIMPLE)
    {
        remove_task(id + TASK_MODE_FPS_RETRY);
        g_fpsVerified[id] = true;
        g_fpsMismatchSamples[id] = 0;
        return;
    }

    new fpsLimit = GetModeFpsMax(g_playerMode[id]);

    new client_auth_type:authType = REU_GetAuthtype(id);
    if (authType == CA_TYPE_STEAM)
    {
        client_cmd(id, "fps_override 1");
    }
    else
    {
        client_cmd(id, "developer 1");
        client_cmd(id, "fps_override 1");
    }
    client_cmd(id, "fps_max %d", fpsLimit);
    g_fpsVerified[id] = false;

    if (scheduleRetry)
    {
        remove_task(id + TASK_MODE_FPS_RETRY);
        TimerSetTask(0.4, "TaskRetryModeFpsMax", id + TASK_MODE_FPS_RETRY);
    }
    else
    {
        QueryPlayerFps(id);
    }

    g_lastModeFpsMaxApply[id] = get_gametime();
}

stock QueryPlayerFps(id)
{
    if (!is_user_connected(id) || is_user_bot(id))
        return;

    if (g_playerMode[id] == MODE_SIMPLE)
    {
        g_fpsVerified[id] = true;
        g_fpsMismatchSamples[id] = 0;
        return;
    }

    g_fpsQueryGeneration[id]++;
    g_fpsQueryMask[id] = 0;
    g_fpsQueryExpected[id] = GetModeFpsMax(g_playerMode[id]);
    g_fpsMaxMatches[id] = false;
    g_fpsOverrideMatches[id] = false;
    g_fpsDeveloperMatches[id] = (REU_GetAuthtype(id) == CA_TYPE_STEAM);
    g_fpsCommandsFiltered[id] = false;

    new data[4];
    data[0] = get_user_userid(id);
    data[1] = g_fpsSession[id];
    data[2] = g_fpsQueryExpected[id];
    data[3] = g_fpsQueryGeneration[id];
    query_client_cvar(id, "fps_max", "OnFpsCvarResult", sizeof(data), data);
    query_client_cvar(id, "fps_override", "OnFpsCapabilityResult", sizeof(data), data);
    query_client_cvar(id, "developer", "OnFpsCapabilityResult", sizeof(data), data);
    query_client_cvar(id, "cl_filterstuffcmd", "OnFpsCapabilityResult", sizeof(data), data);
    g_lastFpsQuery[id] = get_gametime();
}

public OnFpsCapabilityResult(id, const cvar[], const value[], const data[])
{
    if (!IsFpsQueryCurrent(id, data))
        return;

    new bool:unsupported = containi(value, "bad cvar") != -1
        || containi(value, "not found") != -1
        || containi(value, "Bad CVAR request") != -1;

    if (equali(cvar, "fps_override"))
    {
        g_fpsOverrideMatches[id] = unsupported || str_to_num(value) == 1;
        g_fpsQueryMask[id] |= FPS_QUERY_OVERRIDE;
    }
    else if (equali(cvar, "developer"))
    {
        g_fpsDeveloperMatches[id] = REU_GetAuthtype(id) == CA_TYPE_STEAM
            || unsupported
            || str_to_num(value) == 1;
        g_fpsQueryMask[id] |= FPS_QUERY_DEVELOPER;
    }
    else if (equali(cvar, "cl_filterstuffcmd"))
    {
        g_fpsCommandsFiltered[id] = !unsupported && str_to_num(value) > 0;
        g_fpsQueryMask[id] |= FPS_QUERY_FILTER;
    }

    FinalizeFpsQuery(id);
}

stock bool:IsFpsQueryCurrent(id, const data[])
{
    return 1 <= id <= MAX_PLAYERS && is_user_connected(id)
        && get_user_userid(id) == data[0]
        && g_fpsSession[id] == data[1]
        && GetModeFpsMax(g_playerMode[id]) == data[2]
        && g_fpsQueryGeneration[id] == data[3];
}

public OnFpsCvarResult(id, const cvar[], const value[], const data[])
{
    #pragma unused cvar
    if (!IsFpsQueryCurrent(id, data))
        return;

    new expected = data[2];
    new actual = floatround(str_to_float(value));
    new bool:unsupported = containi(value, "bad cvar") != -1 || containi(value, "not found") != -1;
    new tolerance = max(2, get_pcvar_num(g_cvarNormalFpsWarnTolerance));
    g_fpsMaxMatches[id] = unsupported
        ? (g_modeFpsValue[id] > 0 && g_modeFpsValue[id] <= expected + tolerance)
        : (actual >= expected - 1 && actual <= expected + 1);
    g_fpsQueryMask[id] |= FPS_QUERY_MAX;
    FinalizeFpsQuery(id);
}

stock FinalizeFpsQuery(id)
{
    if (g_fpsQueryMask[id] != FPS_QUERY_COMPLETE)
        return;

    new bool:valid = g_fpsMaxMatches[id]
        && g_fpsOverrideMatches[id]
        && g_fpsDeveloperMatches[id];

    if (valid)
    {
        g_fpsVerified[id] = true;
        g_fpsMismatchSamples[id] = 0;
        return;
    }

    g_fpsVerified[id] = false;
    g_fpsMismatchSamples[id]++;
    if (g_fpsMismatchSamples[id] == 1)
    {
        ApplyModeFpsMax(id);
        return;
    }

    if (IsDuelSettingsLocked(id) && g_duelState[id] == DUEL_STATE_RACING)
    {
        EndDuelForFpsViolation(id);
        return;
    }

    if (get_gametime() - g_lastNormalFpsWarn[id] >= 10.0)
    {
        new expected = g_fpsQueryExpected[id];
        if (REU_GetAuthtype(id) == CA_TYPE_STEAM)
            TimerChat(id, "FPS verification failed. Run ^x04fps_override 1; fps_max %d^x01 in console. Ranked runs stay disabled.", expected);
        else
            TimerChat(id, "FPS verification failed. Run ^x04developer 1; fps_override 1; fps_max %d^x01 in console. Ranked runs stay disabled.", expected);

        if (g_fpsCommandsFiltered[id])
            TimerChat(id, "Your client filters server cvar commands, so the FPS values must be applied manually.");
        g_lastNormalFpsWarn[id] = get_gametime();
    }
}

stock EndDuelForFpsViolation(id)
{
    new partner = g_duelPartner[id];
    new name[32], partnerName[32];
    get_user_name(id, name, charsmax(name));
    if (partner && is_user_connected(partner))
    {
        get_user_name(partner, partnerName, charsmax(partnerName));
        TimerChat(0, "^x04[DUEL]^x01 %s failed FPS verification. %s wins.", name, partnerName);
        ResetDuelState(partner);
    }
    ResetDuelState(id);
}

public CmdMainMenu(id)
{
    if (!is_user_connected(id))
    {
        return PLUGIN_HANDLED;
    }

    g_playerMenuType[id] = MENU_MAIN;

    new menuText[512], len = 0;
    new items[][32] = {
        "Teleport to Start",
        "Credits",
        "Top15 / Pro15",
        "Badges",
        "FPS / Client Settings",
        "Market",
        "Mode Selection",
        "WR Replay Bot",
        "Duel Menu",
        "Help / Commands"
    };

    new totalItems = 10;
    new page = g_playerMenuPage[id];
    new start = page * 8;
    new end = start + 8;
    if (end > totalItems) end = totalItems;

    len += formatex(menuText[len], charsmax(menuText) - len, "\yESKIDOSTLAR BHOP^n\dMain Menu (Page %d/%d)^n^n", page + 1, ((totalItems - 1) / 8) + 1);

    for (new i = start; i < end; i++)
    {
        if (IsDuelSettingsLocked(id) && (i == 4 || i == 6))
            len += formatex(menuText[len], charsmax(menuText) - len, "\d[%d] %s [Duel locked]^n", i - start + 1, items[i]);
        else if (g_playerMode[id] == MODE_SIMPLE && i == 6)
            len += formatex(menuText[len], charsmax(menuText) - len, "\d[%d] %s (Closed)^n", i - start + 1, items[i]);
        else
            len += formatex(menuText[len], charsmax(menuText) - len, "\d[\r%d\d]\w %s^n", i - start + 1, items[i]);
    }

    if (page > 0)
    {
        len += formatex(menuText[len], charsmax(menuText) - len, "^n\d[\r9\d]\w Previous Page^n");
    }
    else if (end < totalItems)
    {
        len += formatex(menuText[len], charsmax(menuText) - len, "^n\d[\r9\d]\w Next Page^n");
    }

    len += formatex(menuText[len], charsmax(menuText) - len, "\d[\r0\d]\w Exit");

    show_menu(id, KEY_ALL_MENU, menuText, -1, "BhopTimer");
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
        fprintf(fp, "body{background:#050505;font:10px Arial;color:#e8e8e8;padding:4px;margin:0}");
        fprintf(fp, ".t{color:#fff;font-size:14px;font-weight:bold;margin:4px 0;text-align:center;text-transform:uppercase}");
        fprintf(fp, ".p{background:#0d0d0d;border:1px solid #333;padding:4px;overflow:hidden}");
        fprintf(fp, ".col{width:50%%;float:left}");
        fprintf(fp, "table{width:96%%;margin:0 auto;border-collapse:collapse}");
        fprintf(fp, "th{padding:2px 4px;border-bottom:1px solid #444;background:#191919;color:#999;font-size:7px;text-align:center;text-transform:uppercase}");
        fprintf(fp, "td{padding:1px 4px;border-bottom:1px solid #222;color:#ddd;font-size:9px;line-height:11px;text-align:center}");
        fprintf(fp, ".e{background:#111}");
        fprintf(fp, "</style></head><body>");
        fprintf(fp, "<div class=^"t^">Help</div><div class=^"p^">");

        fprintf(fp, "<div class=^"col^"><table><thead><tr><th>Commands</th></tr></thead><tbody>");
        fprintf(fp, "<tr><td>/menu</td></tr>");
        fprintf(fp, "<tr class=^"e^"><td>/start, /respawn</td></tr>");
        fprintf(fp, "<tr><td>/reset</td></tr>");
        fprintf(fp, "<tr class=^"e^"><td>/pro15, /top15</td></tr>");
        fprintf(fp, "<tr><td>/rank</td></tr>");
        fprintf(fp, "<tr class=^"e^"><td>/best</td></tr>");
        fprintf(fp, "<tr><td>/last</td></tr>");
        fprintf(fp, "<tr class=^"e^"><td>/fps</td></tr>");
        fprintf(fp, "<tr><td>/mode, /mod</td></tr>");
        fprintf(fp, "<tr class=^"e^"><td>/spec</td></tr>");
        fprintf(fp, "<tr><td>/ct</td></tr>");
        fprintf(fp, "<tr class=^"e^"><td>/replay</td></tr>");
        fprintf(fp, "<tr><td>/duel</td></tr>");
        fprintf(fp, "</tbody></table></div>");

        fprintf(fp, "<div class=^"col^"><table><thead><tr><th>Commands</th></tr></thead><tbody>");
        fprintf(fp, "<tr><td>+hook</td></tr>");
        fprintf(fp, "<tr class=^"e^"><td>/bhopstatus</td></tr>");
        fprintf(fp, "<tr><td>/credits, /points</td></tr>");
        fprintf(fp, "<tr class=^"e^"><td>/badges</td></tr>");
        fprintf(fp, "<tr><td>/topbadges</td></tr>");
        fprintf(fp, "<tr class=^"e^"><td>/market, /shop</td></tr>");
        fprintf(fp, "<tr><td>/buy [id]</td></tr>");
        fprintf(fp, "<tr class=^"e^"><td>/inv, /inventory</td></tr>");
        fprintf(fp, "<tr><td>/setprefix [text]</td></tr>");
        fprintf(fp, "<tr class=^"e^"><td>/knifes</td></tr>");
        fprintf(fp, "<tr><td>/trail</td></tr>");
        fprintf(fp, "<tr class=^"e^"><td>/binds</td></tr>");
        fprintf(fp, "<tr><td>/bhopmenu</td></tr>");
        fprintf(fp, "</tbody></table></div>");

        fprintf(fp, "</div></body></html>");
        fclose(fp);
    }

    show_motd(id, filePath, "Help");
    return PLUGIN_HANDLED;
}

public CmdApplyBinds(id)
{
    if (!is_user_connected(id))
        return PLUGIN_HANDLED;

    client_print(id, print_console, "--- ESKIDOSTLAR BHOP Recommended Keybinds ---");
    client_print(id, print_console, "  bind c +hook");
    client_print(id, print_console, "  bind m say /menu");
    client_print(id, print_console, "  bind f say /fps");
    client_print(id, print_console, "  bind b say /market");
    client_print(id, print_console, "  bind n say /mod");
    client_print(id, print_console, "  bind j say /duel");
    client_print(id, print_console, "  bind p say /credits");
    client_print(id, print_console, "----------------------------------------------");
    TimerChat(id, "Keybind suggestions printed to your console (press ~).");
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

    sr_zone_reload();
    LoadZones();
    TimerChat(id, "Zones reloaded for ^x03%s", g_mapName);
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
            TimerChat(id, "Zone preview refreshed.");
        }
        case 5: SaveEditedZones(id);
        case 6:
        {
            LoadZones();
            TimerChat(id, "Zones reloaded for ^x03%s", g_mapName);
        }
        case 7:
        {
            log_amx("[TIMER] BhopMenuHandler: Delete Map Zones selected by id=%d", id);
            DeleteZone(id, ZONE_START);
            DeleteZone(id, ZONE_FINISH);
            log_amx("[TIMER] BhopMenuHandler: Delete Map Zones completed for id=%d", id);
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
    menu_setprop(menu, MPROP_NUMBER_COLOR, "");
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

stock ShowStyledMenu(id, const title[], const body[], keys)
{
    show_menu(id, keys, body, -1, "BhopTimer");
}

stock BhopMenuAddItem(idx, const name[], output[], len, &curLen)
{
    curLen += formatex(output[curLen], len - curLen, "\d[\r%d\d]\w %s^n", idx + 1, name);
}

public BhopMenuCallback(id, key)
{
    if (!is_user_connected(id))
        return PLUGIN_HANDLED;

    switch (g_playerMenuType[id])
    {
        case MENU_MAIN: HandleMainMenu(id, key);
        case MENU_MARKET: HandleMarketMenu(id, key);
        case MENU_MARKET_SKINS: HandleMarketMenu(id, key);
        case MENU_MARKET_SOUNDS: HandleMarketMenu(id, key);
        case MENU_MARKET_MISC: HandleMarketMenu(id, key);
        case MENU_MARKET_VIP: HandleMarketMenu(id, key);
        case MENU_MARKET_TRAIL: HandleMarketMenu(id, key);
        case MENU_BADGES: HandleBadgesMenu(id, key);
        case MENU_MODE: HandleModeMenu(id, key);
        case MENU_FPS: HandleFpsMenu(id, key);
        case MENU_REPLAY: HandleReplayMenu(id, key);
        case MENU_DUEL: HandleDuelMenu(id, key);
        case MENU_CHALLENGE: HandleChallengeMenu(id, key);
        case MENU_MODE_NORMAL_FPS: HandleNormalFpsModeMenu(id, key);
        case MENU_DUEL_MODE: HandleDuelModeMenu(id, key);
        case MENU_DUEL_NORMAL_FPS: HandleDuelNormalFpsMenu(id, key);
        case MENU_TRAIL: HandleTrailMenu(id, key);
    }

    return PLUGIN_HANDLED;
}

public HandleMainMenu(id, key)
{
    new page = g_playerMenuPage[id];
    log_amx("[TIMER] HandleMainMenu: id=%d key=%d page=%d", id, key, page);

    if (key == 9)
    {
        g_playerMenuType[id] = MENU_NONE;
        return;
    }

    if (key == 8)
    {
        // 9 key toggles Next/Previous page.
        if (page > 0)
        {
            g_playerMenuPage[id] = page - 1;
        }
        else
        {
            g_playerMenuPage[id] = page + 1;
        }
        log_amx("[TIMER] HandleMainMenu: page changed to %d", g_playerMenuPage[id]);
        CmdMainMenu(id);
        return;
    }

    g_playerMenuType[id] = MENU_NONE;

    new itemIdx = page * 8 + key;
    log_amx("[TIMER] HandleMainMenu: itemIdx=%d", itemIdx);
    switch (itemIdx)
    {
        case 0: CmdStart(id);
        case 1: CmdCredits(id);
        case 2: CmdPro15(id);
        case 3: CmdBadges(id);
        case 4: CmdFpsMenu(id);
        case 5: CmdMarket(id);
        case 6: CmdBhopModeMenu(id);
        case 7: CmdBhopReplayMenu(id);
        case 8: CmdDuel(id);
        case 9: CmdHelp(id);
    }
}

public HandleMarketMenu(id, key)
{
    new menuType = g_playerMenuType[id];
    g_playerMenuType[id] = MENU_NONE;

    if (menuType == MENU_MARKET)
    {
        if (key == 9)
        {
            CmdMainMenu(id);
            return;
        }
        if (key >= 0 && key <= 5)
        {
            if (key == 5)
            {
                g_marketCategory[id] = 6;
                ShowPlayerInventory(id);
                return;
            }
            g_marketCategory[id] = key + 1;
            ShowMarketCategory(id, key + 1);
        }
        return;
    }

    if (menuType >= MENU_MARKET_SKINS && menuType <= MENU_MARKET_TRAIL)
    {
        if (key == 9)
        {
            CmdMarket(id);
            return;
        }
        if (key >= 0 && key < g_marketMenuCount[id])
        {
            new itemId = g_marketMenuItems[id][key];

            if (menuType == MENU_MARKET_SOUNDS && EconomyPlayerHasItem(id, itemId))
            {
                g_playerSelectedSound[id] = itemId;
                SavePlayerSelectedSound(id);
                TimerChat(id, "WR sound changed to ^x04%s^x01.",
                    itemId == 30 ? "WR Sound 1" : itemId == 31 ? "WR Sound 2" : "WR Sound 3");
            }
            else if ((menuType == MENU_MARKET_SKINS || menuType == MENU_MARKET_VIP) && EconomyPlayerHasItem(id, itemId))
            {
                g_playerSelectedKnife[id] = itemId;
                SavePlayerSelectedKnife(id);

                ApplyKnifeFromMarket(id, itemId);
            }
            else if (menuType == MENU_MARKET_TRAIL && EconomyPlayerHasItem(id, itemId))
            {
                g_playerSelectedTrail[id] = itemId;
                SavePlayerSelectedTrail(id);
                new trailRgb[3];
                if (itemId == 40) { trailRgb[0]=255; trailRgb[1]=0; trailRgb[2]=0; }
                else if (itemId == 41) { trailRgb[0]=0; trailRgb[1]=100; trailRgb[2]=255; }
                else if (itemId == 42) { trailRgb[0]=0; trailRgb[1]=255; trailRgb[2]=0; }
                else if (itemId == 43) { trailRgb[0]=255; trailRgb[1]=255; trailRgb[2]=0; }
                else if (itemId == 44) { trailRgb[0]=200; trailRgb[1]=0; trailRgb[2]=255; }
                SetPlayerTrail(id, trailRgb[0], trailRgb[1], trailRgb[2]);
                TimerChat(id, "Trail changed! Move to see your trail.");
            }
            else
            {
                EconomyBuyItem(id, itemId);
            }
            ShowMarketCategory(id, g_marketCategory[id]);
        }
        return;
    }
}

public HandleBadgesMenu(id, key)
{
    log_amx("[TIMER] HandleBadgesMenu: id=%d key=%d", id, key);
    g_playerMenuType[id] = MENU_NONE;

    if (key == 0)
    {
        CmdTopBadges(id);
    }
    else if (key == 9) CmdMainMenu(id);
}

stock bool:IsDuelSettingsLocked(id)
{
    if (!(1 <= id <= MAX_PLAYERS))
        return false;

    return g_duelState[id] == DUEL_STATE_COUNTDOWN
        || g_duelState[id] == DUEL_STATE_RACING;
}

stock bool:RequireUnlockedSettings(id, const settingName[])
{
    if (!IsDuelSettingsLocked(id))
        return true;

    TimerChat(id, "%s is locked until the duel ends.", settingName);
    return false;
}

stock ApplyPlayerModeState(id, selectedMode, bool:resetRun, bool:loadBest)
{
    if (!IsValidMode(selectedMode))
    {
        selectedMode = MODE_NORMAL;
    }

    g_playerMode[id] = selectedMode;
    g_doubleJumped[id] = false;
    g_jumpReleased[id] = false;
    StopPlayerHook(id, false);
    ApplyModeFpsMax(id);

    if (selectedMode == MODE_LOW_GRAVITY
        || (selectedMode == MODE_SIMPLE && g_cacheSimpleLowGravity))
    {
        set_pev(id, pev_gravity, 0.5);
    }
    else
    {
        set_pev(id, pev_gravity, 1.0);
    }

    if (resetRun)
    {
        ResetPlayerData(id, false);
    }

    if (loadBest)
    {
        LoadPlayerBest(id);
    }
}

stock bool:SwitchPlayerMode(id, selectedMode, bool:teleportStart, bool:announce)
{
    if (g_cacheSimpleEnabled && g_playerMode[id] == MODE_SIMPLE)
    {
        if (announce)
        {
            TimerChat(id, "Mode switching is disabled while ^x04Simple Mode^x01 is active.");
        }
        return false;
    }

    if (!RequireUnlockedSettings(id, "Mode selection"))
        return false;

    if (!IsValidMode(selectedMode))
    {
        return false;
    }

    if (selectedMode == g_playerMode[id])
    {
        new modeName[32];
        GetModeName(selectedMode, modeName, charsmax(modeName));
        if (announce)
        {
            TimerChat(id, "%s is already active.", modeName);
        }
        return false;
    }

    ApplyPlayerModeState(id, selectedMode, true, true);
    if (teleportStart)
    {
        TeleportToStart(id, false);
    }

    if (announce)
    {
        new modeName[32];
        GetModeName(selectedMode, modeName, charsmax(modeName));
        TimerChat(id, "Switched to ^x04%s^x01 mode. Timer reset.", modeName);
    }

    return true;
}

public HandleModeMenu(id, key)
{
    g_playerMenuType[id] = MENU_NONE;

    if (!RequireUnlockedSettings(id, "Mode selection"))
    {
        CmdMainMenu(id);
        return;
    }
    if (key == 9) { CmdMainMenu(id); return; }

    if (key == 0)
    {
        ShowNormalFpsModeMenu(id);
        return;
    }

    new selectedMode = -1;
    if (key == 1)
    {
        selectedMode = MODE_LOW_GRAVITY;
    }
    else if (key == 2)
    {
        selectedMode = MODE_DOUBLE_JUMP;
    }

    SwitchPlayerMode(id, selectedMode, true, true);
}

public HandleNormalFpsModeMenu(id, key)
{
    g_playerMenuType[id] = MENU_NONE;

    if (!RequireUnlockedSettings(id, "FPS category selection"))
    {
        CmdMainMenu(id);
        return;
    }
    if (key == 9) { CmdMainMenu(id); return; }

    new selectedMode = GetNormalFpsModeByKey(key);
    SwitchPlayerMode(id, selectedMode, true, true);
}

public HandleFpsMenu(id, key)
{
    if (!RequireUnlockedSettings(id, "FPS/client settings"))
    {
        g_playerMenuType[id] = MENU_NONE;
        CmdMainMenu(id);
        return;
    }
    if (key == 9)
    {
        g_playerMenuType[id] = MENU_NONE;
        CmdMainMenu(id);
        return;
    }

    g_playerMenuType[id] = MENU_NONE;

    switch (key)
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
            if (g_fpsBrightnessLevel[id] > 2) g_fpsBrightnessLevel[id] = 0;
            ApplyBrightnessProfile(id);
        }
        case 6:
        {
            g_fpsSoundLevel[id]++;
            if (g_fpsSoundLevel[id] > 2) g_fpsSoundLevel[id] = 0;
            ApplySoundProfile(id);
        }
        case 7:
        {
            ResetFpsSettings(id);
        }
    }

    CmdFpsMenu(id);
}

public HandleReplayMenu(id, key)
{
    g_playerMenuType[id] = MENU_NONE;
    if (key == 9) { CmdMainMenu(id); return; }

    new selectedMode;
    if (g_cacheSimpleEnabled)
    {
        selectedMode = MODE_SIMPLE;
    }
    else
    {
        selectedMode = GetDisplayModeByKey(key);
    }
    if (!IsValidMode(selectedMode))
    {
        return;
    }

    if (selectedMode == g_botReplayMode)
    {
        TimerChat(id, "Replay bot is already playing this mode's record.");
        CmdBhopReplayMenu(id);
        return;
    }

    g_botReplayMode = selectedMode;
    LoadReplayFile(selectedMode);
    MaintainReplayBot();

    new modeName[32];
    GetModeName(selectedMode, modeName, charsmax(modeName));

    if (g_botReplayTotalFrames > 0)
        TimerChat(0, "WR Bot changed to play ^x04%s^x01 mode record.", modeName);
    else
        TimerChat(0, "WR Bot mode changed to ^x04%s^x01 (No record exists yet).", modeName);

    CmdBhopReplayMenu(id);
}

public HandleDuelMenu(id, key)
{
    g_playerMenuType[id] = MENU_NONE;
    if (key == 9) { CmdMainMenu(id); return; }

    new target = g_duelTargets[id][key];
    if (!target || !is_user_connected(target) || !is_user_alive(target))
    {
        TimerChat(id, "That player is no longer available.");
        return;
    }
    if (g_duelState[target] != DUEL_STATE_IDLE)
    {
        TimerChat(id, "That player is already in a duel or challenge.");
        return;
    }

    g_duelPendingTarget[id] = target;

    if (g_playerMode[id] == MODE_SIMPLE || g_playerMode[target] == MODE_SIMPLE)
    {
        CreateDuelChallenge(id, target, MODE_SIMPLE);
    }
    else
    {
        ShowDuelModeMenu(id);
    }
}

public HandleDuelModeMenu(id, key)
{
    g_playerMenuType[id] = MENU_NONE;

    new target = g_duelPendingTarget[id];
    if (!target || !is_user_connected(target) || !is_user_alive(target))
    {
        TimerChat(id, "That player is no longer available.");
        g_duelPendingTarget[id] = 0;
        return;
    }

    if (g_duelState[id] != DUEL_STATE_IDLE || g_duelState[target] != DUEL_STATE_IDLE)
    {
        TimerChat(id, "That player is already in a duel or challenge.");
        g_duelPendingTarget[id] = 0;
        return;
    }

    if (key == 0)
    {
        ShowDuelNormalFpsMenu(id);
        return;
    }

    new selectedMode = -1;
    if (key == 1)
    {
        selectedMode = MODE_LOW_GRAVITY;
    }
    else if (key == 2)
    {
        selectedMode = MODE_DOUBLE_JUMP;
    }

    CreateDuelChallenge(id, target, selectedMode);
}

public HandleDuelNormalFpsMenu(id, key)
{
    g_playerMenuType[id] = MENU_NONE;

    new target = g_duelPendingTarget[id];
    new selectedMode = GetNormalFpsModeByKey(key);
    CreateDuelChallenge(id, target, selectedMode);
}

stock CreateDuelChallenge(id, target, selectedMode)
{
    if (!IsValidMode(selectedMode))
    {
        return;
    }

    if (!target || !is_user_connected(target) || !is_user_alive(target))
    {
        TimerChat(id, "That player is no longer available.");
        g_duelPendingTarget[id] = 0;
        return;
    }

    if (g_duelState[id] != DUEL_STATE_IDLE || g_duelState[target] != DUEL_STATE_IDLE)
    {
        TimerChat(id, "That player is already in a duel or challenge.");
        g_duelPendingTarget[id] = 0;
        return;
    }

    g_duelState[id] = DUEL_STATE_WAITING;
    g_duelPartner[id] = target;
    g_duelMode[id] = selectedMode;
    g_duelState[target] = DUEL_STATE_WAITING;
    g_duelPartner[target] = id;
    g_duelMode[target] = selectedMode;
    g_duelPendingTarget[id] = 0;

    new challengerName[32], targetName[32];
    get_user_name(id, challengerName, charsmax(challengerName));
    get_user_name(target, targetName, charsmax(targetName));

    new modeName[32];
    GetModeName(selectedMode, modeName, charsmax(modeName));
    TimerChat(id, "You challenged ^x04%s^x01 to a ^x04%s^x01 duel. Waiting for acceptance...", targetName, modeName);
    ShowChallengeMenu(target, challengerName, selectedMode);
}

public HandleChallengeMenu(id, key)
{
    new partner = g_duelPartner[id];

    if (key == 0)
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
    else if (key == 1)
    {
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
        sr_zone_save();
        TimerChat(id, "Polygon zones saved for ^x03%s", g_mapName);
        return;
    }

    RefreshZoneCaches();
    SaveZonesFromFramework(id);
    sr_zone_save();
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

stock DeleteZone(id, zoneIndex)
{
    log_amx("[TIMER] DeleteZone called for %s/%s by id=%d", g_mapName, g_zoneNames[zoneIndex], id);

    log_amx("[TIMER] DeleteZone: removing framework zone %s", g_zoneClasses[zoneIndex]);
    sr_zone_delete_by_class(g_zoneClasses[zoneIndex]);
    g_zoneLoaded[zoneIndex] = false;

    // Refresh caches from framework to ensure g_zoneMin/g_zoneMax are consistent
    RefreshZoneCaches();

    log_amx("[TIMER] DeleteZone: saving JSON and text files for %s", g_mapName);
    save_legacy_zone_mirror();
    SaveZonesFile();
    log_amx("[TIMER] DeleteZone: local files saved for %s", g_mapName);

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

    if (g_dbSchemaStep < 3 || g_dbSchemaStep > 17)
    {
        g_dbSchemaStep = 3;
    }

    g_dbInitInFlight = true;
    new query[1536], data[1];
    switch (g_dbSchemaStep)
    {
        case 3: copy(query, charsmax(query), "CREATE TABLE IF NOT EXISTS bhop_records (id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,record_key VARCHAR(160) NOT NULL,map VARCHAR(64) NOT NULL,authid VARCHAR(35) NOT NULL,name VARCHAR(32) NOT NULL,mode TINYINT UNSIGNED NOT NULL DEFAULT 0,time_ms INT UNSIGNED NOT NULL,created_at INT UNSIGNED NOT NULL,PRIMARY KEY (id),UNIQUE KEY uq_bhop_records_key (record_key),KEY idx_bhop_records_map_mode_time (map,mode,time_ms)) ENGINE=InnoDB DEFAULT CHARSET=utf8;");
        case 4: copy(query, charsmax(query), "CREATE TABLE IF NOT EXISTS bhop_best (map VARCHAR(64) NOT NULL,authid VARCHAR(35) NOT NULL,name VARCHAR(32) NOT NULL,mode TINYINT UNSIGNED NOT NULL DEFAULT 0,best_time_ms INT UNSIGNED NOT NULL,updated_at INT UNSIGNED NOT NULL,PRIMARY KEY (map,mode,authid),KEY idx_bhop_best_map_time (map,best_time_ms)) ENGINE=InnoDB DEFAULT CHARSET=utf8;");
        case 5: copy(query, charsmax(query), "ALTER TABLE bhop_records ADD COLUMN mode TINYINT UNSIGNED NOT NULL DEFAULT 0 AFTER name;");
        case 6: copy(query, charsmax(query), "ALTER TABLE bhop_best ADD COLUMN mode TINYINT UNSIGNED NOT NULL DEFAULT 0 AFTER name;");
        case 7: copy(query, charsmax(query), "ALTER TABLE bhop_best DROP PRIMARY KEY;");
        case 8: copy(query, charsmax(query), "ALTER TABLE bhop_best ADD PRIMARY KEY (map,mode,authid);");
        case 9: copy(query, charsmax(query), "ALTER TABLE bhop_records ADD KEY idx_bhop_records_map_mode_time (map,mode,time_ms);");
        case 10: copy(query, charsmax(query), "UPDATE IGNORE bhop_records SET mode=1,map=LEFT(map,CHAR_LENGTH(map)-8) WHERE mode=0 AND RIGHT(map,8)='_lowgrav';");
        case 11: copy(query, charsmax(query), "UPDATE IGNORE bhop_best SET mode=1,map=LEFT(map,CHAR_LENGTH(map)-8) WHERE mode=0 AND RIGHT(map,8)='_lowgrav';");
        case 12: copy(query, charsmax(query), "UPDATE IGNORE bhop_records SET mode=2,map=LEFT(map,CHAR_LENGTH(map)-7) WHERE mode=0 AND RIGHT(map,7)='_dbjump';");
        case 13: copy(query, charsmax(query), "UPDATE IGNORE bhop_best SET mode=2,map=LEFT(map,CHAR_LENGTH(map)-7) WHERE mode=0 AND RIGHT(map,7)='_dbjump';");
        case 14: copy(query, charsmax(query), "CREATE TABLE IF NOT EXISTS bhop_players (player_key VARCHAR(96) NOT NULL,identity_type TINYINT UNSIGNED NOT NULL,steamid64 VARCHAR(32) NULL,authid VARCHAR(64) NULL,name VARCHAR(32) NOT NULL,total_credits INT NOT NULL DEFAULT 0,spent_credits INT NOT NULL DEFAULT 0,hook_reward TINYINT UNSIGNED NOT NULL DEFAULT 0,custom_prefix VARCHAR(32) NULL,revision BIGINT UNSIGNED NOT NULL DEFAULT 1,updated_at INT UNSIGNED NOT NULL,PRIMARY KEY(player_key),KEY idx_updated(updated_at),KEY idx_steam(steamid64)) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;");
        case 15: copy(query, charsmax(query), "CREATE TABLE IF NOT EXISTS bhop_credit_history (event_key CHAR(64) NOT NULL,player_key VARCHAR(96) NOT NULL,delta INT NOT NULL,total_after INT NOT NULL,reason VARCHAR(64) NOT NULL,map VARCHAR(64) NOT NULL,is_wr TINYINT UNSIGNED NOT NULL DEFAULT 0,created_at INT UNSIGNED NOT NULL,PRIMARY KEY(event_key),KEY idx_player_time(player_key,created_at)) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;");
        case 16: copy(query, charsmax(query), "CREATE TABLE IF NOT EXISTS bhop_inventory (event_key CHAR(64) NOT NULL,player_key VARCHAR(96) NOT NULL,item_id INT NOT NULL,purchased_at INT UNSIGNED NOT NULL,PRIMARY KEY(event_key),UNIQUE KEY uq_inventory_item(player_key,item_id)) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;");
        case 17: copy(query, charsmax(query), "CREATE TABLE IF NOT EXISTS bhop_market_items (item_id INT NOT NULL PRIMARY KEY,name VARCHAR(64) NOT NULL,price INT NOT NULL,item_type VARCHAR(32) NOT NULL,effect_value INT NOT NULL DEFAULT 0) ENGINE=InnoDB DEFAULT CHARSET=utf8;");
    }
    data[0] = g_dbSchemaStep;
    new prefixedQuery[2048];
    ApplySqlPrefix(query, prefixedQuery, charsmax(prefixedQuery));
    SQL_ThreadQuery(g_sqlTuple, "DbSchemaHandler", prefixedQuery, data, sizeof(data));
}

public DbSchemaHandler(failstate, Handle:query, error[], errnum, data[], size, Float:queueTime)
{
    g_dbInitInFlight = false;

    if (failstate != TQUERY_SUCCESS)
    {
        if (((data[0] == 5 || data[0] == 6) && errnum == 1060) ||
            (data[0] == 7 && errnum == 1091) ||
            (data[0] == 8 && errnum == 1068) ||
            (data[0] == 9 && errnum == 1061))
        {
            g_dbSchemaStep = data[0] + 1;
            DbStartSchemaSetup();
            return;
        }

        g_dbReady = false;
        log_amx("[TIMER] MySQL setup failed (%d): %s", errnum, error);
        return;
    }

    if (data[0] < 17)
    {
        g_dbSchemaStep = data[0] + 1;
        DbStartSchemaSetup();
        return;
    }

    g_dbSchemaStep = 18;
    g_dbReady = true;
    log_amx("[TIMER] Remote MySQL is ready. Flushing pending records.");
    DbLoadRemoteCaches();
    ScheduleDbFlush(DB_FLUSH_DELAY);

    // SQLite remains authoritative for players and inventory. MySQL is an
    // asynchronous mirror consumed by the website.
    EconomyLoadMarketItemsFromDb();
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

    new resetModes[MODE_COUNT], resetCount;
    if (equali(argument, "normal"))
    {
        for (new i = 0; i < sizeof(g_normalFpsModes); i++)
        {
            resetModes[resetCount++] = g_normalFpsModes[i];
        }
    }
    else if (equali(argument, "normal131") || equali(argument, "n131") || equali(argument, "131"))
    {
        resetModes[resetCount++] = MODE_NORMAL;
    }
    else if (equali(argument, "normal200") || equali(argument, "n200") || equali(argument, "200"))
    {
        resetModes[resetCount++] = MODE_NORMAL_200;
    }
    else if (equali(argument, "normal333") || equali(argument, "n333") || equali(argument, "333"))
    {
        resetModes[resetCount++] = MODE_NORMAL_333;
    }
    else if (equali(argument, "normal500") || equali(argument, "n500") || equali(argument, "500"))
    {
        resetModes[resetCount++] = MODE_NORMAL_500;
    }
    else if (equali(argument, "normal1000") || equali(argument, "n1000") || equali(argument, "1000"))
    {
        resetModes[resetCount++] = MODE_NORMAL_1000;
    }
    else if (equali(argument, "lowgrav") || equali(argument, "lg"))
    {
        resetModes[resetCount++] = MODE_LOW_GRAVITY;
    }
    else if (equali(argument, "dbjump") || equali(argument, "dj"))
    {
        resetModes[resetCount++] = MODE_DOUBLE_JUMP;
    }
    else if (equali(argument, "simple") || equali(argument, "smp"))
    {
        resetModes[resetCount++] = MODE_SIMPLE;
    }
    else if (equali(argument, "all"))
    {
        for (new i = 0; i < MODE_COUNT; i++)
        {
            resetModes[resetCount++] = g_displayModeOrder[i];
        }
    }
    else
    {
        console_print(id, "[TIMER] Usage: amx_bhop_reset_top15 <normal|normal131|normal200|normal333|normal500|normal1000|lowgrav|dbjump|simple|all>");
        return PLUGIN_HANDLED;
    }

    for (new i = 0; i < resetCount; i++)
    {
        ResetTop15Mode(resetModes[i]);
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

    if (resetCount == MODE_COUNT)
    {
        copy(modeName, charsmax(modeName), "All Modes");
    }
    else if (resetCount == sizeof(g_normalFpsModes) && equali(argument, "normal"))
    {
        copy(modeName, charsmax(modeName), "Normal Modes");
    }
    else
    {
        GetModeName(resetModes[0], modeName, charsmax(modeName));
    }

    log_amx("[TIMER] %s <%s> reset Top15 for %s [%s].", adminName, adminAuth, g_mapName, modeName);
    console_print(id, "[TIMER] Top15 reset for %s [%s]. MySQL cleanup is queued if remote storage is enabled.", g_mapName, modeName);
    TimerChat(0, "^x04%s^x01 reset Top15 for ^x03%s^x01 [^x04%s^x01].", adminName, g_mapName, modeName);
    return PLUGIN_HANDLED;
}

public ConCmdSimple(id, level, cid)
{
    if (!cmd_access(id, level, cid, 1))
    {
        return PLUGIN_HANDLED;
    }

    new enabled = !g_cacheSimpleEnabled;
    set_pcvar_num(g_cvarSimpleEnabled, enabled);
    g_cacheSimpleEnabled = enabled;

    new adminName[32];
    if (id > 0 && is_user_connected(id))
        get_user_name(id, adminName, charsmax(adminName));
    else
        copy(adminName, charsmax(adminName), "SERVER");

    if (enabled)
    {
        SimpleModeApplyToAll();
        TimerChat(0, "^x04%s^x01 enabled ^x03Simple Mode^x01 for all players.", adminName);
    }
    else
    {
        SimpleModeRestoreAll();
        TimerChat(0, "^x04%s^x01 disabled ^x03Simple Mode^x01. Players restored to their previous modes.", adminName);
    }

    return PLUGIN_HANDLED;
}

stock SimpleModeApplyToAll()
{
    new players[MAX_PLAYERS];
    new pnum;
    get_players(players, pnum);

    for (new i = 0; i < pnum; i++)
    {
        new pid = players[i];
        if (is_user_bot(pid) || is_user_hltv(pid)) continue;

        if (g_playerMode[pid] != MODE_SIMPLE)
            g_playerModeBeforeSimple[pid] = g_playerMode[pid];
        ApplyPlayerModeState(pid, MODE_SIMPLE, true, true);
    }
}

stock SimpleModeRestoreAll()
{
    new players[MAX_PLAYERS];
    new pnum;
    get_players(players, pnum);

    for (new i = 0; i < pnum; i++)
    {
        new pid = players[i];
        if (is_user_bot(pid) || is_user_hltv(pid)) continue;

        if (g_playerMode[pid] == MODE_SIMPLE)
        {
            ApplyPlayerModeState(pid, g_playerModeBeforeSimple[pid], true, true);
        }
        g_playerModeBeforeSimple[pid] = MODE_NORMAL;
    }
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

        formatex(query, charsmax(query), "DELETE FROM bhop_records WHERE map='%s' AND mode=%d;", mapSql, mode);
        QueueSql(query);
        formatex(query, charsmax(query), "DELETE FROM bhop_best WHERE map='%s' AND mode=%d;", mapSql, mode);
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
    if (!query[0])
    {
        return;
    }
    static prefixedQuery[8192];
    ApplySqlPrefix(query, prefixedQuery, charsmax(prefixedQuery));
    EconomyLocalQueueSql(prefixedQuery);
    if (!g_dbConfigured)
        return;

    new path[192];
    BuildDbDataPath(path, charsmax(path), "bhop_timer_mysql_queue.ini");
    write_file(path, prefixedQuery);

    if (g_dbReady)
    {
        ScheduleDbFlush(DB_FLUSH_DELAY);
    }
}

stock ApplySqlPrefix(const input[], output[], len)
{
    copy(output, len, input);
    new prefix[64];
    EconomySqlTable("", prefix, charsmax(prefix));
    if (!equal(prefix, "bhop_"))
        replace_all(output, len, "bhop_", prefix);
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

    new path[192], queuedLen;
    static queuedSql[8192];
    BuildDbDataPath(path, charsmax(path), "bhop_timer_mysql_queue.ini");
    if (size > 0) read_file(path, data[0], queuedSql, charsmax(queuedSql), queuedLen);
    trim(queuedSql);

    if (failstate != TQUERY_SUCCESS)
    {
        if (failstate == TQUERY_CONNECT_FAILED)
        {
            g_dbReady = false;
        }
        EconomyLocalMarkSqlFailed(queuedSql, get_systime() + floatround(g_dbRetryBackoff));
        if (g_dbReady)
        {
            ScheduleDbFlush(g_dbRetryBackoff);
            g_dbRetryBackoff = floatmin(g_dbRetryBackoff * 2.0, 60.0);
        }
        log_amx("[TIMER] Pending MySQL write failed (%d): %s", errnum, error);
        return;
    }

    EconomyLocalMarkSqlSynced(queuedSql);
    g_dbRetryBackoff = 1.0;
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
    for (new mode = MODE_NORMAL; mode < MODE_COUNT; mode++)
    {
        DbRequestBest(mode);
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
    formatex(query, charsmax(query), "SELECT authid,name,best_time_ms FROM bhop_best WHERE map='%s' AND mode=%d ORDER BY best_time_ms ASC LIMIT %d;", mapSql, mode, MAX_FILE_RECORDS);
    data[0] = mode;
    data[1] = g_bestCacheGeneration[mode];
    new prefixedQuery[512];
    ApplySqlPrefix(query, prefixedQuery, charsmax(prefixedQuery));
    SQL_ThreadQuery(g_sqlTuple, "DbBestHandler", prefixedQuery, data, sizeof(data));
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
    if (size < 2 || !IsValidMode(mode) || data[1] != g_bestCacheGeneration[mode])
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

stock BuildBestUpsert(output[], len, const mapSql[], mode, const authSql[], const nameSql[], timeMs, updatedAt)
{
    formatex(output, len,
        "INSERT INTO bhop_best (map,authid,name,mode,best_time_ms,updated_at) VALUES ('%s','%s','%s',%d,%d,%d) ON DUPLICATE KEY UPDATE name=IF(VALUES(best_time_ms)<best_time_ms,VALUES(name),name),updated_at=IF(VALUES(best_time_ms)<best_time_ms,VALUES(updated_at),updated_at),best_time_ms=LEAST(best_time_ms,VALUES(best_time_ms));",
        mapSql, authSql, nameSql, mode, timeMs, updatedAt);
}

stock LoadZones()
{
    for (new zoneIndex = 0; zoneIndex < ZONE_COUNT; zoneIndex++)
    {
        g_zoneLoaded[zoneIndex] = false;
    }

    RefreshZoneCaches();

    new bool:missingLocalZone;
    for (new zoneIndex = 0; zoneIndex < ZONE_COUNT; zoneIndex++)
    {
        if (!g_zoneLoaded[zoneIndex])
        {
            missingLocalZone = true;
        }
    }

    // JSON is authoritative. The old local INI is used only once to migrate a
    // missing zone; no remote database is consulted.
    if (missingLocalZone)
    {
        LoadZonesFile();

        new bool:migrated;
        for (new zoneIndex = 0; zoneIndex < ZONE_COUNT; zoneIndex++)
        {
            if (g_zoneLoaded[zoneIndex] && get_zone_index_by_class(g_zoneClasses[zoneIndex]) == -1)
            {
                sr_zone_upsert_aabb(g_zoneClasses[zoneIndex], g_zoneNames[zoneIndex],
                    g_zoneMin[zoneIndex], g_zoneMax[zoneIndex], true);
                migrated = true;
            }
        }

        if (migrated)
        {
            sr_zone_save();
        }
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
    formatex(recordKey, charsmax(recordKey), "live:%d:%d:%d:%d:%d", mode, createdAt, id, g_recordSequence, random_num(1000, 999999));
    formatex(query, charsmax(query), "INSERT IGNORE INTO bhop_records (record_key,map,authid,name,mode,time_ms,created_at) VALUES ('%s','%s','%s','%s',%d,%d,%d);",
        recordKey, mapSql, authSql, nameSql, mode, timeMs, createdAt);
    QueueSql(query);

    if (isPersonalBest)
    {
        BuildBestUpsert(query, charsmax(query), mapSql, mode, authSql, nameSql, timeMs, createdAt);
        QueueSql(query);
        g_bestTimeMs[id] = timeMs;
    }
}

stock StartTimer(id)
{
    g_runRanked[id] = CanCountRun(id);
    g_timerState[id] = TIMER_RUNNING;
    g_startGameTime[id] = get_gametime();
    g_currentTimeMs[id] = 0;

    if (g_replayFrames[id] == Invalid_Array)
        g_replayFrames[id] = ArrayCreate(ReplayFrame);
    else
        ArrayClear(g_replayFrames[id]);
    g_lastReplayState[id] = -1;
    RecordReplayFrame(id, g_startGameTime[id], true);
    g_lastRecordTime[id] = g_startGameTime[id];

    if (g_runRanked[id])
        ShowCenterHudMessage(id, "Timer Started", 80, 255, 80, 1.0);
    else
        ShowCenterHudMessage(id, "Timer Started (Unranked)", 255, 190, 80, 1.2);
}

stock RecordReplayFrame(id, Float:sampleGameTime, bool:forceFinal)
{
    if (g_replayFrames[id] == Invalid_Array)
        g_replayFrames[id] = ArrayCreate(ReplayFrame);

    new frameCount = ArraySize(g_replayFrames[id]);
    if (frameCount >= MAX_REPLAY_FRAMES)
        return;

    new Float:relativeTime = sampleGameTime - g_startGameTime[id];
    if (relativeTime < 0.0)
        relativeTime = 0.0;

    new flags = pev(id, pev_flags);
    new replayFlags = pev(id, pev_button) & REPLAY_BUTTON_MASK;
    if (flags & FL_ONGROUND)
        replayFlags |= REPLAY_STATE_ONGROUND;
    if (flags & FL_DUCKING)
        replayFlags |= REPLAY_STATE_DUCKING;
    if (!forceFinal && replayFlags == g_lastReplayState[id]
        && sampleGameTime - g_lastRecordTime[id] < RECORD_INTERVAL)
        return;

    new frame[ReplayFrame];
    new Float:origin[3], Float:angles[3], Float:velocity[3];
    pev(id, pev_origin, origin);
    pev(id, pev_v_angle, angles);
    pev(id, pev_velocity, velocity);

    frame[RF_TIME] = relativeTime;
    frame[RF_ORIGIN_X] = origin[0];
    frame[RF_ORIGIN_Y] = origin[1];
    frame[RF_ORIGIN_Z] = origin[2];
    frame[RF_ANGLE_X] = angles[0];
    frame[RF_ANGLE_Y] = angles[1];
    frame[RF_VELOCITY_X] = velocity[0];
    frame[RF_VELOCITY_Y] = velocity[1];
    frame[RF_VELOCITY_Z] = velocity[2];
    frame[RF_STATE] = replayFlags;

    if (forceFinal && frameCount > 0)
    {
        new previous[ReplayFrame];
        ArrayGetArray(g_replayFrames[id], frameCount - 1, previous);
        if (relativeTime <= previous[RF_TIME] + 0.0001)
            ArraySetArray(g_replayFrames[id], frameCount - 1, frame);
        else
            ArrayPushArray(g_replayFrames[id], frame);
    }
    else
    {
        ArrayPushArray(g_replayFrames[id], frame);
    }

    g_lastReplayState[id] = replayFlags;
    g_lastRecordTime[id] = sampleGameTime;
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

            new modeName[32];
            GetModeName(g_playerMode[id], modeName, charsmax(modeName));
            TimerChat(0, "^x04[DUEL]^x01 ^x04%s^x01 won the ^x04%s^x01 duel against ^x04%s^x01 in ^x04%s^x01!", winnerName, modeName, loserName, timeText);

            ResetDuelState(partner);
        }
        ResetDuelState(id);
        return;
    }

    // Capture the exact finish position and timestamp. PreThink sampling may
    // otherwise end up one client command short of the official timer value.
    RecordReplayFrame(id, g_startGameTime[id] + (float(timeMs) / 1000.0), true);

    g_timerState[id] = TIMER_FINISHED;
    g_currentTimeMs[id] = timeMs;
    g_lastTimeMs[id] = timeMs;

    if (!g_runRanked[id])
    {
        new practiceTime[32];
        FormatTimeMs(timeMs, practiceTime, charsmax(practiceTime));
        TimerChat(id, "Unranked finish: ^x04%s^x01. Verify FPS and avoid hook/noclip for ranked records.", practiceTime);
        ShowCenterHudMessage(id, practiceTime, 255, 190, 80, 2.0);
        return;
    }

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

    // Economy: credits for finishing a map. WR grants extra credits.
    if (get_pcvar_num(g_cvarEconomyEnabled))
    {
        new previousTotal = EconomyGetTotalCredits(id);
        new finishRank = isPersonalBest ? GetRankForTime(timeMs, mode) : 0;

        EconomyAddCredits(id, 3, "Map finished", false);

        if (finishRank == 1)
        {
            EconomyAddCredits(id, 10, "World record", true);
        }

        BadgeCheckProgression(id, previousTotal, EconomyGetTotalCredits(id));
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
            if (g_cacheEconomyEnabled && g_playerSelectedSound[id] >= 30 && g_playerSelectedSound[id] <= 32)
            {
                new soundFile[32];
                formatex(soundFile, charsmax(soundFile), "ed/wr%d.wav", g_playerSelectedSound[id] - 29);
                client_cmd(0, "spk %s", soundFile);
            }

            // Transfer the dynamic buffer instead of copying tens of thousands
            // of cells inside the finish touch callback.
            g_pendingWrSave = true;
            g_pendingWrMode = mode;
            g_pendingWrDurationMs = timeMs;
            if (g_pendingWrFrames != Invalid_Array)
            {
                ArrayDestroy(g_pendingWrFrames);
            }
            g_pendingWrFrames = g_replayFrames[id];
            g_replayFrames[id] = ArrayCreate(ReplayFrame);
            g_pendingWrWriteIndex = 0;
            remove_task(TASK_WR_SAVE);
            TimerSetTask(0.01, "TaskWrSave", TASK_WR_SAVE);
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

    if (g_cacheTeleportOnFinish)
    {
        remove_task(id + TASK_START_TP);
        TimerSetTask(0.2, "TaskTeleportStart", id + TASK_START_TP);
    }
}

public TaskWrSave(taskid)
{
    #pragma unused taskid

    if (!g_pendingWrSave || g_pendingWrFrames == Invalid_Array)
        return;

    new frameCount = ArraySize(g_pendingWrFrames);
    if (!g_pendingWrFile)
    {
        new finalPath[192];
        BuildReplayPath(g_pendingWrMode, finalPath, charsmax(finalPath));
        formatex(g_pendingWrTempPath, charsmax(g_pendingWrTempPath), "%s.tmp", finalPath);
        delete_file(g_pendingWrTempPath);
        g_pendingWrFile = fopen(g_pendingWrTempPath, "wb");
        if (!g_pendingWrFile)
        {
            log_amx("[TIMER] Could not open replay temp file: %s", g_pendingWrTempPath);
            g_pendingWrSave = false;
            ArrayDestroy(g_pendingWrFrames);
            g_pendingWrFrames = Invalid_Array;
            return;
        }

        fwrite(g_pendingWrFile, REPLAY_MAGIC, BLOCK_INT);
        fwrite(g_pendingWrFile, REPLAY_VERSION, BLOCK_INT);
        fwrite(g_pendingWrFile, frameCount, BLOCK_INT);
        fwrite(g_pendingWrFile, g_pendingWrDurationMs, BLOCK_INT);
    }

    new stop = min(g_pendingWrWriteIndex + 256, frameCount);
    new frame[ReplayFrame];
    for (new i = g_pendingWrWriteIndex; i < stop; i++)
    {
        ArrayGetArray(g_pendingWrFrames, i, frame);
        for (new cell = 0; cell < ReplayFrame; cell++)
            fwrite(g_pendingWrFile, frame[cell], BLOCK_INT);
    }
    g_pendingWrWriteIndex = stop;

    if (g_pendingWrWriteIndex < frameCount)
    {
        TimerSetTask(0.01, "TaskWrSave", TASK_WR_SAVE);
        return;
    }

    fclose(g_pendingWrFile);
    g_pendingWrFile = 0;

    new finalPath[192];
    BuildReplayPath(g_pendingWrMode, finalPath, charsmax(finalPath));
    delete_file(finalPath);
    if (!rename_file(g_pendingWrTempPath, finalPath, 1))
        log_amx("[TIMER] Could not publish replay file: %s", finalPath);

    g_pendingWrSave = false;
    ArrayDestroy(g_pendingWrFrames);
    g_pendingWrFrames = Invalid_Array;
    g_pendingWrWriteIndex = 0;

    if (g_botReplayMode == g_pendingWrMode)
    {
        LoadReplayFile(g_botReplayMode);
        MaintainReplayBot();
    }
    UpdateWrHolders();
}

stock ResetToStart(id, bool:announce)
{
    g_runRanked[id] = false;
    g_timerState[id] = TIMER_IN_START;
    g_startGameTime[id] = 0.0;
    g_currentTimeMs[id] = 0;

    if (announce)
    {
        ShowCenterHudMessage(id, "Timer Reset", 255, 170, 80, 1.0);
    }
}

stock ResetPlayerData(id, bool:full)
{
    g_runRanked[id] = false;
    g_timerState[id] = TIMER_IDLE;
    g_prevInStart[id] = false;
    g_prevInFinish[id] = false;
    g_startGameTime[id] = 0.0;
    g_currentTimeMs[id] = 0;
    if (g_replayFrames[id] != Invalid_Array)
        ArrayClear(g_replayFrames[id]);
    g_lastReplayState[id] = -1;

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
    #pragma unused id
    RefreshZoneCaches();
    SaveZonesFile();
}

stock GetStartTeleportOrigin(Float:origin[3])
{
    RefreshZoneCache(ZONE_START);

    origin[0] = (g_zoneMin[ZONE_START][0] + g_zoneMax[ZONE_START][0]) / 2.0;
    origin[1] = (g_zoneMin[ZONE_START][1] + g_zoneMax[ZONE_START][1]) / 2.0;
    origin[2] = g_zoneMin[ZONE_START][2] + g_cacheStartTeleportZOffset;
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

    if (g_playerMode[id] == MODE_SIMPLE)
    {
        return true;
    }

    if (!is_user_bot(id) && !g_fpsVerified[id])
    {
        if (get_gametime() - g_lastFpsQuery[id] >= 1.0)
            QueryPlayerFps(id);
        return false;
    }

    if (IsNormalFpsTooHigh(id))
    {
        ApplyModeFpsMax(id);
        return false;
    }

    return true;
}

stock bool:IsNormalFpsTooHigh(id)
{
    if (!g_cacheNormalFpsEnforce || !IsNormalMode(g_playerMode[id]))
    {
        return false;
    }

    if (g_modeFpsValue[id] <= 0)
    {
        return false;
    }

    new tolerance = get_pcvar_num(g_cvarNormalFpsWarnTolerance);
    return (g_modeFpsValue[id] > GetNormalModeFps(g_playerMode[id]) + tolerance) ? true : false;
}

stock ShowCenterHudMessage(id, const message[], r, g, b, Float:holdTime)
{
    if (!is_user_connected(id))
    {
        return;
    }

    set_hudmessage(r, g, b, -1.0, 0.35, 0, 0.0, holdTime, 0.0, 0.0, 3);
    show_hudmessage(id, message);
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
        GetModeDataSuffix(mode, suffix, modeSuffix, charsmax(modeSuffix));
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

        if (g_zoneLoaded[zoneIndex])
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
    return (mode >= MODE_NORMAL && mode < MODE_COUNT) ? true : false;
}

stock bool:IsNormalMode(mode)
{
    return (mode == MODE_NORMAL ||
        mode == MODE_NORMAL_200 ||
        mode == MODE_NORMAL_333 ||
        mode == MODE_NORMAL_500 ||
        mode == MODE_NORMAL_1000) ? true : false;
}

stock GetNormalModeFps(mode)
{
    switch (mode)
    {
        case MODE_NORMAL_200: return 200;
        case MODE_NORMAL_333: return 333;
        case MODE_NORMAL_500: return 500;
        case MODE_NORMAL_1000: return 1000;
    }

    return 131;
}

stock GetModeFpsMax(mode)
{
    if (mode == MODE_SIMPLE)
    {
        return 0;
    }

    if (IsNormalMode(mode))
    {
        return GetNormalModeFps(mode);
    }

    new otherMax = get_pcvar_num(g_cvarOtherModesFpsMax);
    if (otherMax < 20)
    {
        otherMax = 1000;
    }

    return otherMax;
}

stock GetModeDataSuffix(mode, const suffix[], output[], len)
{
    switch (mode)
    {
        case MODE_LOW_GRAVITY: formatex(output, len, "%s_lowgrav", suffix);
        case MODE_DOUBLE_JUMP: formatex(output, len, "%s_dbjump", suffix);
        case MODE_NORMAL_200: formatex(output, len, "%s_normal200", suffix);
        case MODE_NORMAL_333: formatex(output, len, "%s_normal333", suffix);
        case MODE_NORMAL_500: formatex(output, len, "%s_normal500", suffix);
        case MODE_NORMAL_1000: formatex(output, len, "%s_normal1000", suffix);
        case MODE_SIMPLE: formatex(output, len, "%s_simple", suffix);
        default: copy(output, len, suffix);
    }
}

stock GetModeShortLabel(mode, output[], len)
{
    switch (mode)
    {
        case MODE_LOW_GRAVITY: copy(output, len, "LG");
        case MODE_DOUBLE_JUMP: copy(output, len, "DJ");
        case MODE_NORMAL_200: copy(output, len, "N200");
        case MODE_NORMAL_333: copy(output, len, "N333");
        case MODE_NORMAL_500: copy(output, len, "N500");
        case MODE_NORMAL_1000: copy(output, len, "N1000");
        case MODE_SIMPLE: copy(output, len, "SMP");
        default: copy(output, len, "N131");
    }
}

stock GetDisplayModeByKey(key)
{
    if (key < 0 || key >= MODE_COUNT)
    {
        return -1;
    }

    return g_displayModeOrder[key];
}

stock GetNormalFpsModeByKey(key)
{
    if (key < 0 || key >= sizeof(g_normalFpsModes))
    {
        return -1;
    }

    return g_normalFpsModes[key];
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
        new queryText[256];
        copy(queryText, charsmax(queryText), "SELECT map,authid,name,time_ms,created_at FROM bhop_records;");
        new Handle:query = SQL_PrepareQuery(connection, queryText);
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
                QueueLegacyRecord(map, MODE_NORMAL, auth, name, timeMs, createdAt);
                migrated++;
                SQL_NextRow(query);
            }
        }
        if (query != Empty_Handle) SQL_FreeHandle(query);
    }

    if (LegacySqliteTableExists(connection, "bhop_best"))
    {
        new queryText[256];
        copy(queryText, charsmax(queryText), "SELECT map,authid,name,best_time_ms,updated_at FROM bhop_best;");
        new Handle:query = SQL_PrepareQuery(connection, queryText);
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
                QueueLegacyBest(map, MODE_NORMAL, auth, name, timeMs, updatedAt);
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
    new mapName[64], mode = MODE_NORMAL, kind;
    if (ExtractLegacyMap(fileName, "_records_lowgrav.ini", mapName, charsmax(mapName)))
    {
        mode = MODE_LOW_GRAVITY;
        kind = 1;
    }
    else if (ExtractLegacyMap(fileName, "_records_dbjump.ini", mapName, charsmax(mapName)))
    {
        mode = MODE_DOUBLE_JUMP;
        kind = 1;
    }
    else if (ExtractLegacyMap(fileName, "_records.ini", mapName, charsmax(mapName)))
    {
        kind = 1;
    }
    else if (ExtractLegacyMap(fileName, "_best_lowgrav.ini", mapName, charsmax(mapName)))
    {
        mode = MODE_LOW_GRAVITY;
        kind = 2;
    }
    else if (ExtractLegacyMap(fileName, "_best_dbjump.ini", mapName, charsmax(mapName)))
    {
        mode = MODE_DOUBLE_JUMP;
        kind = 2;
    }
    else if (ExtractLegacyMap(fileName, "_best.ini", mapName, charsmax(mapName)))
    {
        kind = 2;
    }
    else
    {
        return 0;
    }

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
                QueueLegacyRecord(mapName, mode, auth, name, timeMs, createdAt);
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
                QueueLegacyBest(mapName, mode, auth, name, timeMs, get_systime());
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

stock NormalizeLegacyRecordMapMode(const inputMap[], outputMap[], len, &mode)
{
    copy(outputMap, len, inputMap);

    if (!IsValidMode(mode))
    {
        mode = MODE_NORMAL;
    }

    if (mode != MODE_NORMAL)
    {
        return;
    }

    new mapLength = strlen(outputMap);
    if (mapLength > 8 && equal(outputMap[mapLength - 8], "_lowgrav"))
    {
        outputMap[mapLength - 8] = '^0';
        mode = MODE_LOW_GRAVITY;
    }
    else if (mapLength > 7 && equal(outputMap[mapLength - 7], "_dbjump"))
    {
        outputMap[mapLength - 7] = '^0';
        mode = MODE_DOUBLE_JUMP;
    }
}

stock QueueLegacyRecord(const mapName[], mode, const auth[], const name[], timeMs, createdAt)
{
    new canonicalMap[64];
    NormalizeLegacyRecordMapMode(mapName, canonicalMap, charsmax(canonicalMap), mode);

    new mapSql[MAX_MAP_SQL], authSql[MAX_AUTH_SQL], nameSql[MAX_NAME_SQL], keyRaw[192], keySql[256], query[1024];
    MysqlEscape(canonicalMap, mapSql, charsmax(mapSql));
    MysqlEscape(auth, authSql, charsmax(authSql));
    MysqlEscape(name, nameSql, charsmax(nameSql));
    formatex(keyRaw, charsmax(keyRaw), "legacy:%s:%d:%s:%d:%d", canonicalMap, mode, auth, createdAt, timeMs);
    MysqlEscape(keyRaw, keySql, charsmax(keySql));
    formatex(query, charsmax(query), "INSERT IGNORE INTO bhop_records (record_key,map,authid,name,mode,time_ms,created_at) VALUES ('%s','%s','%s','%s',%d,%d,%d);", keySql, mapSql, authSql, nameSql, mode, timeMs, createdAt);
    QueueSql(query);
}

stock QueueLegacyBest(const mapName[], mode, const auth[], const name[], timeMs, updatedAt)
{
    new canonicalMap[64];
    NormalizeLegacyRecordMapMode(mapName, canonicalMap, charsmax(canonicalMap), mode);

    new mapSql[MAX_MAP_SQL], authSql[MAX_AUTH_SQL], nameSql[MAX_NAME_SQL], query[1024];
    MysqlEscape(canonicalMap, mapSql, charsmax(mapSql));
    MysqlEscape(auth, authSql, charsmax(authSql));
    MysqlEscape(name, nameSql, charsmax(nameSql));
    BuildBestUpsert(query, charsmax(query), mapSql, mode, authSql, nameSql, timeMs, updatedAt);
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
    if (!g_cacheAutoCt || !is_user_connected(id))
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
    if (!g_cacheAutoCt || !is_user_connected(id))
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
    if (!g_cacheAutoCt || !is_user_connected(id) || !is_user_alive(id))
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
    if (!g_cacheGodmode || !is_user_alive(id))
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

    if (!g_cacheAdminGlow || (get_user_flags(id) & ~ADMIN_USER) == 0)
    {
        ClearPlayerRendering(id);
        return;
    }

    if (!g_cacheAdminGlowColorLoaded)
    {
        return;
    }

    new Float:renderColor[3];
    renderColor[0] = g_cacheAdminGlowColor[0];
    renderColor[1] = g_cacheAdminGlowColor[1];
    renderColor[2] = g_cacheAdminGlowColor[2];

    new Float:amount = g_cacheAdminGlowAmount;
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

stock ApplyPlayerTrail(id)
{
    if (!is_user_alive(id) || is_user_bot(id))
        return;

    if (!g_playerTrail[id])
        return;

    new r = g_playerTrailColor[id][0];
    new g = g_playerTrailColor[id][1];
    new b = g_playerTrailColor[id][2];

    message_begin(MSG_ONE_UNRELIABLE, SVC_TEMPENTITY, _, id);
    write_byte(TE_BEAMFOLLOW);
    write_short(id);
    write_short(g_beamSprite);
    write_byte(10);
    write_byte(4);
    write_byte(r);
    write_byte(g);
    write_byte(b);
    write_byte(200);
    message_end();
}

stock RemovePlayerTrail(id)
{
    g_playerTrail[id] = false;
}

stock SetPlayerTrail(id, r, g, b)
{
    g_playerTrail[id] = true;
    g_playerTrailColor[id][0] = r;
    g_playerTrailColor[id][1] = g;
    g_playerTrailColor[id][2] = b;
}

stock ApplyAutoBhop(id)
{
    if (!g_cacheAutoBhop || is_user_bot(id))
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
        if (get_gametime() - g_lastSteepSlopeCheck[id] > 0.1)
        {
            g_lastSteepSlopeCheck[id] = get_gametime();
            if (IsOnSteepSlope(id))
            {
                return;
            }
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
        ShowCenterHudMessage(id, "Hook Used - Timer Reset", 255, 80, 80, 1.2);
    }
}

stock bool:FindHookTarget(id, Float:target[3])
{
    new Float:start[3], Float:end[3], Float:viewAngles[3], Float:forwardVec[3];
    GetPlayerEyePosition(id, start);
    pev(id, pev_v_angle, viewAngles);

    engfunc(EngFunc_MakeVectors, viewAngles);
    global_get(glb_v_forward, forwardVec);

    new Float:maxDistance = g_cacheHookMaxDistance;
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

    new Float:minDistance = g_cacheHookMinDistance;
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

    if (!g_cacheHookEnabled || IsNormalMode(g_playerMode[id]) || !is_user_alive(id) || is_user_bot(id) ||
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
    new Float:minDistance = g_cacheHookMinDistance;
    if (minDistance < 16.0)
    {
        minDistance = 16.0;
    }

    if (distance <= minDistance)
    {
        StopPlayerHook(id, true);
        return;
    }

    new Float:speed = EconomyGetPlayerHookSpeed(id);
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
    if (!g_cacheParachuteEnabled || g_hookActive[id] || is_user_bot(id))
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

    new Float:fallSpeed = g_cacheParachuteFallSpeed;
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
    else if (IsNormalMode(g_playerMode[id]))
    {
        set_pev(id, pev_maxspeed, g_cacheNormalMaxspeed);
    }
    else
    {
        set_pev(id, pev_maxspeed, g_cacheOtherModesMaxspeed);
    }

    if (g_cacheRemoveJumpSlowdown)
    {
        set_pev(id, pev_fuser2, 0.0);
    }

    if (g_playerMode[id] == MODE_LOW_GRAVITY)
    {
        set_pev(id, pev_gravity, 0.5);
    }
    else if (g_cacheSimpleEnabled && g_playerMode[id] == MODE_SIMPLE && g_cacheSimpleLowGravity)
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
    if (!g_replayBot || !is_user_connected(g_replayBot) || !is_user_alive(g_replayBot))
    {
        return 0;
    }

    // Read actual bot velocity from engine
    new Float:velocity[3];
    pev(g_replayBot, pev_velocity, velocity);

    new Float:speed = floatsqroot((velocity[0] * velocity[0]) + (velocity[1] * velocity[1]));

    // If engine velocity is near zero, fall back to replay data calculation
    if (speed < 1.0 && g_botReplayTotalFrames >= 2)
    {
        new frameIndex = g_botPlaybackFrame;
        if (frameIndex < 0) frameIndex = 0;
        if (frameIndex >= g_botReplayTotalFrames) frameIndex = g_botReplayTotalFrames - 1;

        new nextIndex = frameIndex + 1;
        if (nextIndex >= g_botReplayTotalFrames) nextIndex = frameIndex;

        new frame[ReplayFrame], nextFrame[ReplayFrame];
        ArrayGetArray(g_botReplayFrames, frameIndex, frame);
        ArrayGetArray(g_botReplayFrames, nextIndex, nextFrame);
        new Float:dx = nextFrame[RF_ORIGIN_X] - frame[RF_ORIGIN_X];
        new Float:dy = nextFrame[RF_ORIGIN_Y] - frame[RF_ORIGIN_Y];
        new Float:frameTime = nextFrame[RF_TIME] - frame[RF_TIME];
        if (frameTime > 0.0001)
            speed = floatsqroot((dx * dx) + (dy * dy)) / frameTime;
    }

    return floatround(speed);
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

    new Float:interval = g_cacheAdsInterval;
    if (interval < 30.0)
    {
        interval = 30.0;
    }

    TimerSetTask(interval, "TaskAdvertise", TASK_ADVERTISE);
}

public TaskAdvertise()
{
    if (g_cacheAdsEnabled)
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
    #pragma unused mode
    copy(output, len, g_mapName);
}

stock GetModeName(mode, output[], len)
{
    switch (mode)
    {
        case MODE_LOW_GRAVITY: copy(output, len, "Low Gravity");
        case MODE_DOUBLE_JUMP: copy(output, len, "Double Jump");
        case MODE_NORMAL_200: copy(output, len, "Normal 200 FPS");
        case MODE_NORMAL_333: copy(output, len, "Normal 333 FPS");
        case MODE_NORMAL_500: copy(output, len, "Normal 500 FPS");
        case MODE_NORMAL_1000: copy(output, len, "Normal 1000 FPS");
        case MODE_SIMPLE: copy(output, len, "Simple");
        default: copy(output, len, "Normal 131 FPS");
    }
}

stock GetModeUrlParam(mode, output[], len)
{
    switch (mode)
    {
        case MODE_LOW_GRAVITY: copy(output, len, "lowgrav");
        case MODE_DOUBLE_JUMP: copy(output, len, "dbjump");
        case MODE_NORMAL_200: copy(output, len, "normal200");
        case MODE_NORMAL_333: copy(output, len, "normal333");
        case MODE_NORMAL_500: copy(output, len, "normal500");
        case MODE_NORMAL_1000: copy(output, len, "normal1000");
        case MODE_SIMPLE: copy(output, len, "simple");
        default: copy(output, len, "normal");
    }
}

public CmdBhopModeMenu(id)
{
    if (!is_user_connected(id))
    {
        return PLUGIN_HANDLED;
    }

    if (g_cacheSimpleEnabled && g_playerMode[id] == MODE_SIMPLE)
    {
        TimerChat(id, "^x03Simple Mode^x01 is active. Mode switching is disabled while Simple Mode is enabled.");
        CmdMainMenu(id);
        return PLUGIN_HANDLED;
    }

    if (!RequireUnlockedSettings(id, "Mode selection"))
        return PLUGIN_HANDLED;

    g_playerMenuType[id] = MENU_MODE;
    g_playerMenuPage[id] = g_playerMode[id];

    new menuText[512], len = 0;

    len += formatex(menuText[len], charsmax(menuText) - len, "\yBhop Timer Mode Selection^n^n");

    new normalText[32];
    if (IsNormalMode(g_playerMode[id]))
    {
        formatex(normalText, charsmax(normalText), "\y[%d FPS Active]", GetNormalModeFps(g_playerMode[id]));
    }
    else
    {
        normalText[0] = '^0';
    }

    len += formatex(menuText[len], charsmax(menuText) - len, "\d[\r1\d]\w Normal Mode %s^n", normalText);
    len += formatex(menuText[len], charsmax(menuText) - len, "\d[\r2\d]\w Low Gravity Mode %s^n", (g_playerMode[id] == MODE_LOW_GRAVITY) ? "\y[Active]" : "");
    len += formatex(menuText[len], charsmax(menuText) - len, "\d[\r3\d]\w Double Jump Mode %s^n", (g_playerMode[id] == MODE_DOUBLE_JUMP) ? "\y[Active]" : "");

    len += formatex(menuText[len], charsmax(menuText) - len, "^n\d[\r0\d]\w Main Menu");

    show_menu(id, KEY_ALL_MENU, menuText, -1, "BhopTimer");
    return PLUGIN_HANDLED;
}

public ShowNormalFpsModeMenu(id)
{
    if (!is_user_connected(id))
    {
        return PLUGIN_HANDLED;
    }

    if (g_cacheSimpleEnabled && g_playerMode[id] == MODE_SIMPLE)
    {
        TimerChat(id, "^x03Simple Mode^x01 is active. FPS category selection is disabled while Simple Mode is enabled.");
        CmdMainMenu(id);
        return PLUGIN_HANDLED;
    }

    if (!RequireUnlockedSettings(id, "FPS category selection"))
        return PLUGIN_HANDLED;

    g_playerMenuType[id] = MENU_MODE_NORMAL_FPS;
    g_playerMenuPage[id] = g_playerMode[id];

    new menuText[768], len = 0;
    len += formatex(menuText[len], charsmax(menuText) - len, "\yNormal Mode FPS Category^n^n");

    for (new i = 0; i < sizeof(g_normalFpsModes); i++)
    {
        new mode = g_normalFpsModes[i];
        len += formatex(menuText[len], charsmax(menuText) - len, "\d[\r%d\d]\w Normal %d FPS %s^n",
            i + 1, GetNormalModeFps(mode), (g_playerMode[id] == mode) ? "\y[Active]" : "");
    }

    len += formatex(menuText[len], charsmax(menuText) - len, "^n\d[\r0\d]\w Main Menu");
    show_menu(id, KEY_ALL_MENU, menuText, -1, "BhopTimer");
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
    if (msgSayText <= 0 || msgTeamInfo <= 0)
    {
        client_print(receiver, print_chat, "%s", message);
        return;
    }

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

stock ParseMotdPage(const pageArg[])
{
    if (!pageArg[0])
    {
        return 1;
    }

    new page = str_to_num(pageArg);
    if (page < 1)
    {
        page = 1;
    }

    return page;
}

stock bool:HandlePagedMotdCommand(id, const message[])
{
    if (message[0] != '/' && message[0] != '!')
    {
        return false;
    }

    new commandLine[64], command[24], pageArg[16];
    copy(commandLine, charsmax(commandLine), message[1]);

    if (parse(commandLine, command, charsmax(command), pageArg, charsmax(pageArg)) < 1)
    {
        return false;
    }

    new page = ParseMotdPage(pageArg);

    if (equali(command, "pro15") || equali(command, "top15"))
    {
        ShowPro15Motd(id, page);
        return true;
    }

    if (equali(command, "topbadges"))
    {
        ShowTopBadgesMotd(id, page);
        return true;
    }

    return false;
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
        if (equali(message, "/setprefix", 10) && (message[10] == ' ' || message[10] == '^0'))
        {
            HandleSetPrefixFromChat(id, message);
            return PLUGIN_HANDLED;
        }

        if ((equali(message, "/setwelcome", 11) && (message[11] == ' ' || message[11] == '^0'))
        ||  (equali(message, "/joinmessage", 12) && (message[12] == ' ' || message[12] == '^0')))
        {
            HandleSetWelcomeFromChat(id, message);
            return PLUGIN_HANDLED;
        }

        if (HandlePagedMotdCommand(id, message))
        {
            return PLUGIN_HANDLED;
        }

        return PLUGIN_CONTINUE;
    }

    new name[32], chatMsg[256], prefix[96];
    get_user_name(id, name, charsmax(name));
    GetPlayerFullChatPrefix(id, prefix, charsmax(prefix));

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
        if (equali(message, "/setprefix", 10) && (message[10] == ' ' || message[10] == '^0'))
        {
            HandleSetPrefixFromChat(id, message);
            return PLUGIN_HANDLED;
        }

        if ((equali(message, "/setwelcome", 11) && (message[11] == ' ' || message[11] == '^0'))
        ||  (equali(message, "/joinmessage", 12) && (message[12] == ' ' || message[12] == '^0')))
        {
            HandleSetWelcomeFromChat(id, message);
            return PLUGIN_HANDLED;
        }

        if (HandlePagedMotdCommand(id, message))
        {
            return PLUGIN_HANDLED;
        }

        return PLUGIN_CONTINUE;
    }

    new name[32], chatMsg[256], prefix[96];
    get_user_name(id, name, charsmax(name));
    GetPlayerFullChatPrefix(id, prefix, charsmax(prefix));

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
    for (new mode = MODE_NORMAL; mode < MODE_COUNT; mode++)
    {
        GetRecordHolderName(mode, g_wrHolderName[mode], 31);
    }
}

public GetPlayerWrPrefix(const name[], output[], len)
{
    output[0] = '^0';
    if (!name[0]) return;

    new count = 0;
    new temp[64], label[12];
    temp[0] = '^0';

    for (new i = 0; i < MODE_COUNT; i++)
    {
        new mode = g_displayModeOrder[i];
        if (g_wrHolderName[mode][0] && equal(name, g_wrHolderName[mode]))
        {
            if (count > 0)
            {
                add(temp, charsmax(temp), "/");
            }

            GetModeShortLabel(mode, label, charsmax(label));
            add(temp, charsmax(temp), label);
            count++;
        }
    }

    if (count == MODE_COUNT)
    {
        copy(output, len, "^x04[WR-ALL] ");
    }
    else if (count > 0)
    {
        formatex(output, len, "^x04[WR-%s] ", temp);
    }
}

stock GetPlayerFullChatPrefix(id, output[], len)
{
    output[0] = '^0';
    if (!is_user_connected(id))
    {
        return;
    }

    new name[32];
    get_user_name(id, name, charsmax(name));

    new wrPrefix[64];
    GetPlayerWrPrefix(name, wrPrefix, charsmax(wrPrefix));

    new customPrefix[MAX_CUSTOM_PREFIX_LEN + 1];
    EconomyGetCustomPrefix(id, customPrefix, charsmax(customPrefix));

    if (customPrefix[0])
    {
        formatex(output, len, "%s^x04[%s] ", wrPrefix, customPrefix);
        return;
    }

    new badgePrefix[64];
    BadgeGetPrefixForPlayer(id, badgePrefix, charsmax(badgePrefix));
    formatex(output, len, "%s%s", wrPrefix, badgePrefix);
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

    g_playerMenuType[id] = MENU_DUEL;
    g_playerMenuPage[id] = 0;
    g_duelPendingTarget[id] = 0;

    new menuText[1024], len = 0;
    new playerCount = 0;
    
    len += formatex(menuText[len], charsmax(menuText) - len, "\yBhop Duel Challenge^n^n");
    
    for (new i = 1; i <= MAX_PLAYERS; i++)
    {
        if (is_user_connected(i) && is_user_alive(i) && i != id && !is_user_bot(i))
        {
            new name[32];
            get_user_name(i, name, charsmax(name));
            g_duelTargets[id][playerCount] = i;
            len += formatex(menuText[len], charsmax(menuText) - len, "\d[\r%d\d]\w %s^n", playerCount + 1, name);
            playerCount++;
            if (playerCount >= 8) break;
        }
    }
    
    if (playerCount == 0)
    {
        TimerChat(id, "No active players available to duel.");
        return PLUGIN_HANDLED;
    }
    
    len += formatex(menuText[len], charsmax(menuText) - len, "^n\d[\r0\d]\w Main Menu");
    
    show_menu(id, KEY_ALL_MENU, menuText, -1, "BhopTimer");
    return PLUGIN_HANDLED;
}

public ShowDuelModeMenu(id)
{
    if (!is_user_connected(id))
    {
        return PLUGIN_HANDLED;
    }

    new target = g_duelPendingTarget[id];
    if (!target || !is_user_connected(target) || !is_user_alive(target))
    {
        TimerChat(id, "That player is no longer available.");
        g_duelPendingTarget[id] = 0;
        return PLUGIN_HANDLED;
    }

    g_playerMenuType[id] = MENU_DUEL_MODE;
    g_playerMenuPage[id] = 0;

    new targetName[32], menuText[512], len = 0;
    get_user_name(target, targetName, charsmax(targetName));

    len += formatex(menuText[len], charsmax(menuText) - len, "\yDuel Mode for %s^n^n", targetName);
    len += formatex(menuText[len], charsmax(menuText) - len, "\d[\r1\d]\w Normal Mode^n");
    len += formatex(menuText[len], charsmax(menuText) - len, "\d[\r2\d]\w Low Gravity Mode^n");
    len += formatex(menuText[len], charsmax(menuText) - len, "\d[\r3\d]\w Double Jump Mode^n");
    len += formatex(menuText[len], charsmax(menuText) - len, "^n\d[\r0\d]\w Main Menu");

    show_menu(id, KEY_ALL_MENU, menuText, -1, "BhopTimer");
    return PLUGIN_HANDLED;
}

public ShowDuelNormalFpsMenu(id)
{
    if (!is_user_connected(id))
    {
        return PLUGIN_HANDLED;
    }

    new target = g_duelPendingTarget[id];
    if (!target || !is_user_connected(target) || !is_user_alive(target))
    {
        TimerChat(id, "That player is no longer available.");
        g_duelPendingTarget[id] = 0;
        return PLUGIN_HANDLED;
    }

    g_playerMenuType[id] = MENU_DUEL_NORMAL_FPS;
    g_playerMenuPage[id] = 0;

    new menuText[768], len = 0;
    len += formatex(menuText[len], charsmax(menuText) - len, "\yDuel Normal FPS Category^n^n");

    for (new i = 0; i < sizeof(g_normalFpsModes); i++)
    {
        new mode = g_normalFpsModes[i];
        len += formatex(menuText[len], charsmax(menuText) - len, "\d[\r%d\d]\w Normal %d FPS^n",
            i + 1, GetNormalModeFps(mode));
    }

    len += formatex(menuText[len], charsmax(menuText) - len, "^n\d[\r0\d]\w Main Menu");
    show_menu(id, KEY_ALL_MENU, menuText, -1, "BhopTimer");
    return PLUGIN_HANDLED;
}

stock ShowChallengeMenu(id, const challengerName[], mode)
{
    g_playerMenuType[id] = MENU_CHALLENGE;
    g_playerMenuPage[id] = 0;

    new menuText[512], len = 0;
    new modeName[32];
    GetModeName(mode, modeName, charsmax(modeName));
    
    len += formatex(menuText[len], charsmax(menuText) - len, "\yDuel Challenge from %s^n^n", challengerName);
    len += formatex(menuText[len], charsmax(menuText) - len, "\wMode: \y%s^n^n", modeName);
    len += formatex(menuText[len], charsmax(menuText) - len, "\d[\r1\d]\w Accept Duel^n");
    len += formatex(menuText[len], charsmax(menuText) - len, "\d[\r2\d]\w Decline Duel^n");
    
    show_menu(id, KEY_ALL_MENU, menuText, -1, "BhopTimer");
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

    new selectedMode = g_duelMode[challenger];
    if (!IsValidMode(selectedMode))
    {
        selectedMode = MODE_NORMAL;
    }

    g_duelMode[challenger] = selectedMode;
    g_duelMode[opponent] = selectedMode;
    ApplyPlayerModeState(challenger, selectedMode, true, true);
    ApplyPlayerModeState(opponent, selectedMode, true, true);

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

    g_duelCountdownTime[challenger] = 5;
    g_duelCountdownTime[opponent] = 5;

    new challengerName[32], opponentName[32];
    get_user_name(challenger, challengerName, charsmax(challengerName));
    get_user_name(opponent, opponentName, charsmax(opponentName));

    new modeName[32];
    GetModeName(selectedMode, modeName, charsmax(modeName));
    TimerChat(0, "^x04[DUEL]^x01 ^x04%s^x01 and ^x04%s^x01 are starting a ^x04%s^x01 duel!", challengerName, opponentName, modeName);

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
        new countText[24];
        if (count > 3 && g_duelMode[id] != MODE_SIMPLE)
        {
            copy(countText, charsmax(countText), "FPS CHECK");
            QueryPlayerFps(id);
        }
        else if (count > 3)
        {
            copy(countText, charsmax(countText), "READY");
        }
        else
        {
            num_to_str(count, countText, charsmax(countText));
        }

        set_hudmessage(255, 80, 80, -1.0, 0.35, 0, 0.0, 1.0, 0.0, 0.0, 3);
        show_hudmessage(id, countText);
        client_cmd(id, "spk buttons/lightswitch2");
        
        g_duelCountdownTime[id]--;
        TimerSetTask(1.0, "TaskDuelCountdown", id);
    }
    else
    {
        new partner = g_duelPartner[id];
        if (!partner || !is_user_connected(partner)
            || (g_duelMode[id] != MODE_SIMPLE && (!g_fpsVerified[id] || !g_fpsVerified[partner])))
        {
            TimerChat(id, "Duel cancelled: both players must pass FPS verification.");
            if (partner && is_user_connected(partner))
            {
                TimerChat(partner, "Duel cancelled: both players must pass FPS verification.");
                ResetDuelState(partner);
            }
            ResetDuelState(id);
            return;
        }

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
    g_duelMode[id] = MODE_NORMAL;
    g_duelPendingTarget[id] = 0;
    
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
    switch (mode)
    {
        case MODE_LOW_GRAVITY: copy(modeSuffix, charsmax(modeSuffix), "lowgrav");
        case MODE_DOUBLE_JUMP: copy(modeSuffix, charsmax(modeSuffix), "dbjump");
        case MODE_NORMAL_200: copy(modeSuffix, charsmax(modeSuffix), "normal200");
        case MODE_NORMAL_333: copy(modeSuffix, charsmax(modeSuffix), "normal333");
        case MODE_NORMAL_500: copy(modeSuffix, charsmax(modeSuffix), "normal500");
        case MODE_NORMAL_1000: copy(modeSuffix, charsmax(modeSuffix), "normal1000");
        case MODE_SIMPLE: copy(modeSuffix, charsmax(modeSuffix), "simple");
        default: copy(modeSuffix, charsmax(modeSuffix), "normal");
    }

    formatex(output, len, "%s/bhop_timer_%s_%s_replay.rec", dataDir, g_mapName, modeSuffix);
}

stock bool:LoadReplayFile(mode)
{
    if (g_botReplayFrames == Invalid_Array)
        g_botReplayFrames = ArrayCreate(ReplayFrame);
    else
        ArrayClear(g_botReplayFrames);

    g_botReplayTotalFrames = 0;
    g_botPlaybackFrame = 0;
    g_lastPlaybackTime = 0.0;
    g_botPlaybackTime = 0.0;
    g_botReplayDurationMs = 0;
    g_botReplayHasFullState = false;

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

    new headerValue;
    fread(fp, headerValue, BLOCK_INT);

    new version = 0;
    new bool:hasHeader = (headerValue == REPLAY_MAGIC);
    if (hasHeader)
    {
        fread(fp, version, BLOCK_INT);
        fread(fp, g_botReplayTotalFrames, BLOCK_INT);
        fread(fp, g_botReplayDurationMs, BLOCK_INT);

        if (version != 2 && version != REPLAY_VERSION)
        {
            fclose(fp);
            g_botReplayTotalFrames = 0;
            return false;
        }
    }
    else
    {
        g_botReplayTotalFrames = headerValue;
    }

    if (g_botReplayTotalFrames <= 0 || g_botReplayTotalFrames > MAX_REPLAY_FRAMES)
    {
        fclose(fp);
        g_botReplayTotalFrames = 0;
        return false;
    }

    new expectedSize;
    if (version == REPLAY_VERSION)
        expectedSize = 16 + g_botReplayTotalFrames * ReplayFrame * 4;
    else if (version == 2)
        expectedSize = 16 + g_botReplayTotalFrames * 32;
    else
        expectedSize = 4 + g_botReplayTotalFrames * 24;
    if (fileSize < expectedSize)
    {
        fclose(fp);
        g_botReplayTotalFrames = 0;
        return false;
    }

    new frame[ReplayFrame];
    if (version == REPLAY_VERSION)
    {
        for (new i = 0; i < g_botReplayTotalFrames; i++)
        {
            for (new cell = 0; cell < ReplayFrame; cell++)
                fread(fp, frame[cell], BLOCK_INT);
            ArrayPushArray(g_botReplayFrames, frame);
        }
        g_botReplayHasFullState = true;
    }
    else
    {
        for (new i = 0; i < g_botReplayTotalFrames; i++)
        {
            for (new cell = 0; cell < ReplayFrame; cell++)
                frame[cell] = 0;

            new base = hasHeader ? 16 : 4;
            new originOffset = base + i * 12;
            new angleOffset = base + g_botReplayTotalFrames * 12 + i * 12;
            fseek(fp, originOffset, SEEK_SET);
            fread(fp, frame[RF_ORIGIN_X], BLOCK_INT);
            fread(fp, frame[RF_ORIGIN_Y], BLOCK_INT);
            fread(fp, frame[RF_ORIGIN_Z], BLOCK_INT);
            fseek(fp, angleOffset, SEEK_SET);
            fread(fp, frame[RF_ANGLE_X], BLOCK_INT);
            fread(fp, frame[RF_ANGLE_Y], BLOCK_INT);
            new unusedRoll;
            fread(fp, unusedRoll, BLOCK_INT);

            if (version == 2)
            {
                fseek(fp, base + g_botReplayTotalFrames * 24 + i * 4, SEEK_SET);
                fread(fp, frame[RF_TIME], BLOCK_INT);
                fseek(fp, base + g_botReplayTotalFrames * 28 + i * 4, SEEK_SET);
                fread(fp, frame[RF_STATE], BLOCK_INT);
            }
            else if (fileSize >= base + g_botReplayTotalFrames * 28)
            {
                fseek(fp, base + g_botReplayTotalFrames * 24 + i * 4, SEEK_SET);
                new ducking;
                fread(fp, ducking, BLOCK_INT);
                if (ducking)
                    frame[RF_STATE] = REPLAY_STATE_DUCKING | IN_DUCK;
            }
            ArrayPushArray(g_botReplayFrames, frame);
        }
        g_botReplayHasFullState = (version == 2);
    }

    fclose(fp);

    if (version >= 2)
    {
        new first[ReplayFrame], current[ReplayFrame], previous[ReplayFrame];
        ArrayGetArray(g_botReplayFrames, 0, first);
        previous = first;
        new bool:validTimeline = (g_botReplayDurationMs > 0 && first[RF_TIME] >= 0.0);
        for (new i = 1; i < g_botReplayTotalFrames && validTimeline; i++)
        {
            ArrayGetArray(g_botReplayFrames, i, current);
            if (current[RF_TIME] <= previous[RF_TIME])
                validTimeline = false;
            previous = current;
        }

        if (!validTimeline)
            BuildUniformReplayTimeline(g_botReplayDurationMs);
    }
    else
    {
        // Old files assumed every client produced an exact 10/40 ms command.
        // Stretch them to the stored WR time instead, which fixes accelerated
        // playback without deleting existing records.
        g_botReplayDurationMs = GetRecordTime(mode);
        if (g_botReplayDurationMs <= 0)
        {
            new Float:legacyInterval = 0.01;
            g_botReplayDurationMs = floatround(float(g_botReplayTotalFrames - 1) * legacyInterval * 1000.0);
        }
        BuildUniformReplayTimeline(g_botReplayDurationMs);
    }

    if (g_botReplayDurationMs <= 0 && g_botReplayTotalFrames > 0)
    {
        new last[ReplayFrame];
        ArrayGetArray(g_botReplayFrames, g_botReplayTotalFrames - 1, last);
        g_botReplayDurationMs = floatround(last[RF_TIME] * 1000.0);
    }

    return true;
}

stock BuildUniformReplayTimeline(durationMs)
{
    if (durationMs <= 0)
        durationMs = 1;

    if (g_botReplayTotalFrames <= 1)
    {
        if (g_botReplayTotalFrames == 1)
        {
            new frame[ReplayFrame];
            ArrayGetArray(g_botReplayFrames, 0, frame);
            frame[RF_TIME] = 0.0;
            ArraySetArray(g_botReplayFrames, 0, frame);
        }
        return;
    }

    new Float:duration = float(durationMs) / 1000.0;
    new Float:denominator = float(g_botReplayTotalFrames - 1);
    new frame[ReplayFrame];
    for (new i = 0; i < g_botReplayTotalFrames; i++)
    {
        ArrayGetArray(g_botReplayFrames, i, frame);
        frame[RF_TIME] = duration * (float(i) / denominator);
        ArraySetArray(g_botReplayFrames, i, frame);
    }
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
    GetModeShortLabel(g_botReplayMode, modeLabel, charsmax(modeLabel));
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
        set_pev(g_replayBot, pev_movetype, MOVETYPE_FLY);
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
    set_pev(g_replayBot, pev_movetype, MOVETYPE_FLY);
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
    new Float:elapsed = 0.0;
    if (g_lastPlaybackTime == 0.0)
    {
        g_lastPlaybackTime = currentTime;
    }
    else
    {
        elapsed = currentTime - g_lastPlaybackTime;
        if (elapsed < 0.0 || elapsed > 0.25)
            elapsed = 0.0;
        g_lastPlaybackTime = currentTime;
    }

    new lastFrame[ReplayFrame];
    ArrayGetArray(g_botReplayFrames, g_botReplayTotalFrames - 1, lastFrame);
    new Float:duration = float(g_botReplayDurationMs) / 1000.0;
    if (duration <= 0.0)
        duration = lastFrame[RF_TIME];

    g_botPlaybackTime += elapsed;
    if (duration > 0.0 && g_botPlaybackTime >= duration)
    {
        while (g_botPlaybackTime >= duration)
            g_botPlaybackTime -= duration;
        g_botPlaybackFrame = 0;
    }

    new currentFrame[ReplayFrame], nextFrame[ReplayFrame];
    if (g_botPlaybackFrame >= g_botReplayTotalFrames - 1)
        g_botPlaybackFrame = 0;

    ArrayGetArray(g_botReplayFrames, g_botPlaybackFrame, currentFrame);
    if (currentFrame[RF_TIME] > g_botPlaybackTime)
    {
        g_botPlaybackFrame = 0;
        ArrayGetArray(g_botReplayFrames, 0, currentFrame);
    }

    while (g_botPlaybackFrame + 1 < g_botReplayTotalFrames)
    {
        ArrayGetArray(g_botReplayFrames, g_botPlaybackFrame + 1, nextFrame);
        if (nextFrame[RF_TIME] > g_botPlaybackTime)
            break;
        g_botPlaybackFrame++;
        currentFrame = nextFrame;
    }

    new nextIndex = g_botPlaybackFrame + 1;
    if (nextIndex >= g_botReplayTotalFrames)
        nextIndex = g_botPlaybackFrame;
    ArrayGetArray(g_botReplayFrames, nextIndex, nextFrame);

    new Float:frameDuration = nextFrame[RF_TIME] - currentFrame[RF_TIME];
    new Float:fraction = 0.0;
    if (frameDuration > 0.0001)
        fraction = (g_botPlaybackTime - currentFrame[RF_TIME]) / frameDuration;
    if (fraction < 0.0) fraction = 0.0;
    if (fraction > 1.0) fraction = 1.0;

    // Current and next positions
    new Float:displayOrigin[3];
    displayOrigin[0] = currentFrame[RF_ORIGIN_X] + (nextFrame[RF_ORIGIN_X] - currentFrame[RF_ORIGIN_X]) * fraction;
    displayOrigin[1] = currentFrame[RF_ORIGIN_Y] + (nextFrame[RF_ORIGIN_Y] - currentFrame[RF_ORIGIN_Y]) * fraction;
    displayOrigin[2] = currentFrame[RF_ORIGIN_Z] + (nextFrame[RF_ORIGIN_Z] - currentFrame[RF_ORIGIN_Z]) * fraction;

    new Float:vel[3];
    vel[0] = currentFrame[RF_VELOCITY_X] + (nextFrame[RF_VELOCITY_X] - currentFrame[RF_VELOCITY_X]) * fraction;
    vel[1] = currentFrame[RF_VELOCITY_Y] + (nextFrame[RF_VELOCITY_Y] - currentFrame[RF_VELOCITY_Y]) * fraction;
    vel[2] = currentFrame[RF_VELOCITY_Z] + (nextFrame[RF_VELOCITY_Z] - currentFrame[RF_VELOCITY_Z]) * fraction;
    if (floatabs(vel[0]) + floatabs(vel[1]) + floatabs(vel[2]) < 0.01 && frameDuration > 0.0001)
    {
        vel[0] = (nextFrame[RF_ORIGIN_X] - currentFrame[RF_ORIGIN_X]) / frameDuration;
        vel[1] = (nextFrame[RF_ORIGIN_Y] - currentFrame[RF_ORIGIN_Y]) / frameDuration;
        vel[2] = (nextFrame[RF_ORIGIN_Z] - currentFrame[RF_ORIGIN_Z]) / frameDuration;
    }

    // View angles
    new Float:viewAngles[3];
    viewAngles[0] = InterpolateReplayAngle(currentFrame[RF_ANGLE_X], nextFrame[RF_ANGLE_X], fraction);
    if (g_cacheReplayPitchInvert)
        viewAngles[0] = -viewAngles[0];
    if (viewAngles[0] > 89.0) viewAngles[0] = 89.0;
    if (viewAngles[0] < -89.0) viewAngles[0] = -89.0;
    viewAngles[1] = InterpolateReplayAngle(currentFrame[RF_ANGLE_Y], nextFrame[RF_ANGLE_Y], fraction);
    viewAngles[2] = 0.0;

    new replayState = currentFrame[RF_STATE];
    new replayButtons = replayState & REPLAY_BUTTON_MASK;
    if (replayState & REPLAY_STATE_DUCKING)
        replayButtons |= IN_DUCK;
    if (!g_botReplayHasFullState && vel[2] > 10.0)
        replayButtons |= IN_JUMP;

    new Float:yawRadians = viewAngles[1] * 0.0174532925;
    new Float:yawCos = floatcos(yawRadians);
    new Float:yawSin = floatsin(yawRadians);
    new Float:forwardMove = vel[0] * yawCos + vel[1] * yawSin;
    new Float:sideMove = -vel[0] * yawSin + vel[1] * yawCos;
    new moveMsec = clamp(floatround(elapsed * 1000.0), 1, 255);

    // RunPlayerMove with ZERO velocity — origin is set manually after
    set_pev(g_replayBot, pev_movetype, MOVETYPE_WALK);
    engfunc(EngFunc_RunPlayerMove, g_replayBot, viewAngles, forwardMove, sideMove, 0.0, replayButtons, 0, moveMsec);

    // Teleport to exact recorded position
    engfunc(EngFunc_SetOrigin, g_replayBot, displayOrigin);

    // Set velocity for spectator interpolation only
    set_pev(g_replayBot, pev_velocity, vel);

    // RunPlayerMove already applies the interpolated command angles using
    // GoldSrc's player-specific pitch conversion. Preserve its entity/body
    // angles and only retain the exact recorded view angle for spectators.
    set_pev(g_replayBot, pev_v_angle, viewAngles);
    set_pev(g_replayBot, pev_fixangle, 0);

    new flags = pev(g_replayBot, pev_flags);
    if (g_botReplayHasFullState)
    {
        if (replayState & REPLAY_STATE_ONGROUND)
            flags |= FL_ONGROUND;
        else
            flags &= ~FL_ONGROUND;
    }

    if (replayState & REPLAY_STATE_DUCKING)
    {
        flags |= FL_DUCKING;
        new Float:viewOfs[3] = {0.0, 0.0, 12.0};
        set_pev(g_replayBot, pev_view_ofs, viewOfs);
    }
    else
    {
        flags &= ~FL_DUCKING;
        new Float:viewOfs[3] = {0.0, 0.0, 17.0};
        set_pev(g_replayBot, pev_view_ofs, viewOfs);
    }
    set_pev(g_replayBot, pev_flags, flags);
}

stock Float:InterpolateReplayAngle(Float:startAngle, Float:endAngle, Float:fraction)
{
    startAngle = NormalizeReplayAngle(startAngle);
    endAngle = NormalizeReplayAngle(endAngle);
    new Float:delta = endAngle - startAngle;
    while (delta > 180.0) delta -= 360.0;
    while (delta < -180.0) delta += 360.0;
    return NormalizeReplayAngle(startAngle + delta * fraction);
}

stock Float:NormalizeReplayAngle(Float:angle)
{
    while (angle > 180.0) angle -= 360.0;
    while (angle < -180.0) angle += 360.0;
    return angle;
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
    log_amx("[TIMER] CmdBhopReplayMenu: id=%d", id);
    if (!is_user_connected(id))
    {
        log_amx("[TIMER] CmdBhopReplayMenu: id=%d not connected", id);
        return PLUGIN_HANDLED;
    }

    MaintainReplayBot();
    log_amx("[TIMER] CmdBhopReplayMenu: id=%d bot maintained", id);

    g_playerMenuType[id] = MENU_REPLAY;
    g_playerMenuPage[id] = 0;

    new menuText[1024], len = 0;
    new timeText[32];

    len += formatex(menuText[len], charsmax(menuText) - len, "\yBhop Replay Bot Control^n^n");

    if (g_cacheSimpleEnabled)
    {
        new recordTime = GetRecordTime(MODE_SIMPLE);
        if (recordTime > 0) FormatTimeMs(recordTime, timeText, charsmax(timeText));
        else copy(timeText, charsmax(timeText), "No Record");

        len += formatex(menuText[len], charsmax(menuText) - len, "\d[\r1\d]\w Watch Simple Record [%s] %s^n",
            timeText, (g_botReplayMode == MODE_SIMPLE) ? "\y[Active]" : "");
    }
    else
    {
        for (new i = 0; i < MODE_COUNT; i++)
        {
            new mode = g_displayModeOrder[i];
            new recordTime = GetRecordTime(mode);
            if (recordTime > 0) FormatTimeMs(recordTime, timeText, charsmax(timeText));
            else copy(timeText, charsmax(timeText), "No Record");

            new modeName[32];
            GetModeName(mode, modeName, charsmax(modeName));
            len += formatex(menuText[len], charsmax(menuText) - len, "\d[\r%d\d]\w Watch %s Record [%s] %s^n",
                i + 1, modeName, timeText, (g_botReplayMode == mode) ? "\y[Active]" : "");
        }
    }

    len += formatex(menuText[len], charsmax(menuText) - len, "^n\d[\r0\d]\w Main Menu");

    show_menu(id, KEY_ALL_MENU, menuText, -1, "BhopTimer");
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

public FwHamItemDeploy(weapon)
{
    new id = get_pdata_cbase(weapon, m_pPlayer, XO_CBASEPLAYERWEAPON);
    if (1 <= id <= MAX_PLAYERS)
        g_ePlayerInfo[id][m_fLastWeaponDeploy] = _:get_gametime();
}

public FwHamTakeDamage(victim, inflictor, attacker, Float:damage, damagebits)
{
    return HAM_SUPERCEDE;
}

public FwHamPlayerKilled(victim, attacker, shouldgib)
{
    if (g_replayBot && victim == g_replayBot)
    {
        if (is_user_connected(g_replayBot))
        {
            TimerSetTask(0.0, "TaskRespawnReplayBot", victim);
        }
        return HAM_SUPERCEDE;
    }
    return HAM_IGNORED;
}

public TaskRespawnReplayBot(taskid)
{
    if (g_replayBot && is_user_connected(g_replayBot))
    {
        ExecuteHamB(Ham_CS_RoundRespawn, g_replayBot);
        MaintainReplayBot();
    }
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
    else if (pev_valid(ent))
    {
        if (g_fpsHideWater[host] && IsWaterEntity(ent))
        {
            set_es(es_handle, ES_Effects, get_es(es_handle, ES_Effects) | EF_NODRAW);
            return FMRES_HANDLED;
        }
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
        return;
    }
    if (is_user_alive(id) && read_data(2) == CSW_KNIFE)
        ApplyKnifeFromMarket(id, g_playerSelectedKnife[id]);
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

    new hideWeaponMsg = get_user_msgid("HideWeapon");
    if (hideWeaponMsg <= 0) return;
    message_begin(MSG_ONE_UNRELIABLE, hideWeaponMsg, _, id);
    write_byte(flags);
    message_end();
}

public CmdFpsMenu(id)
{
    if (!is_user_connected(id))
    {
        return PLUGIN_HANDLED;
    }

    if (!RequireUnlockedSettings(id, "FPS/client settings"))
        return PLUGIN_HANDLED;

    g_playerMenuType[id] = MENU_FPS;
    g_playerMenuPage[id] = 0;

    new menuText[1024], len = 0;
    new label[24];

    len += formatex(menuText[len], charsmax(menuText) - len, "\yBhop FPS / Client Settings^n^n");

    len += formatex(menuText[len], charsmax(menuText) - len, "\d[\r1\d]\w Hide Other Players %s^n", g_fpsHidePlayers[id] ? "\y[ON]" : "\d[OFF]");
    len += formatex(menuText[len], charsmax(menuText) - len, "\d[\r2\d]\w Hide Timer Text %s^n", g_fpsHideText[id] ? "\y[ON]" : "\d[OFF]");
    len += formatex(menuText[len], charsmax(menuText) - len, "\d[\r3\d]\w Hide Weapon/Hand Model %s^n", g_fpsHideWeapon[id] ? "\y[ON]" : "\d[OFF]");
    len += formatex(menuText[len], charsmax(menuText) - len, "\d[\r4\d]\w Hide Game HUD Elements %s^n", g_fpsHideHud[id] ? "\y[ON]" : "\d[OFF]");
    len += formatex(menuText[len], charsmax(menuText) - len, "\d[\r5\d]\w Hide Water Entities %s^n", g_fpsHideWater[id] ? "\y[ON]" : "\d[OFF]");

    GetBrightnessLabel(g_fpsBrightnessLevel[id], label, charsmax(label));
    len += formatex(menuText[len], charsmax(menuText) - len, "\d[\r6\d]\w Brightness Profile \y[%s]^n", label);

    GetSoundLabel(g_fpsSoundLevel[id], label, charsmax(label));
    len += formatex(menuText[len], charsmax(menuText) - len, "\d[\r7\d]\w Sound Profile \y[%s]^n", label);

    len += formatex(menuText[len], charsmax(menuText) - len, "\d[\r8\d]\w Reset FPS Settings^n");

    len += formatex(menuText[len], charsmax(menuText) - len, "^n\d[\r0\d]\w Main Menu");

    show_menu(id, KEY_ALL_MENU, menuText, -1, "BhopTimer");
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

stock LoadPlayerSelectedSound(id)
{
    g_playerSelectedSound[id] = 0;

    if (is_user_bot(id) || is_user_hltv(id))
        return;

    new localValue[16];
    if (EconomyLocalGetSetting(id, "selected_sound", localValue, charsmax(localValue)))
    {
        g_playerSelectedSound[id] = str_to_num(localValue);
        return;
    }

    new steamid[34];
    get_user_authid(id, steamid, charsmax(steamid));

    new path[192];
    get_datadir(path, charsmax(path));
    add(path, charsmax(path), "/bhop_timer/sounds.ini");

    if (!file_exists(path))
        return;

    new line[128], len;
    new lines = file_size(path, 1);

    for (new i = 0; i < lines; i++)
    {
        if (!read_file(path, i, line, charsmax(line), len) || len <= 0)
            continue;

        trim(line);
        if (!line[0] || line[0] == ';')
            continue;

        new fileSteam[34], soundId[4];
        if (parse(line, fileSteam, charsmax(fileSteam), soundId, charsmax(soundId)) < 2)
            continue;

        if (equal(fileSteam, steamid))
        {
            g_playerSelectedSound[id] = str_to_num(soundId);
            EconomyLocalSetSetting(id, "selected_sound", soundId);
            return;
        }
    }
}

stock SavePlayerSelectedSound(id)
{
    if (is_user_bot(id) || is_user_hltv(id))
        return;

    new localValue[16]; num_to_str(g_playerSelectedSound[id], localValue, charsmax(localValue));
    EconomyLocalSetSetting(id, "selected_sound", localValue);

    new steamid[34];
    get_user_authid(id, steamid, charsmax(steamid));

    new path[192];
    get_datadir(path, charsmax(path));
    add(path, charsmax(path), "/bhop_timer/sounds.ini");

    new line[128], len;
    new lines = file_exists(path) ? file_size(path, 1) : 0;
    new found = -1;

    for (new i = 0; i < lines; i++)
    {
        if (!read_file(path, i, line, charsmax(line), len) || len <= 0)
            continue;

        trim(line);
        if (!line[0] || line[0] == ';')
            continue;

        new fileSteam[34];
        parse(line, fileSteam, charsmax(fileSteam));

        if (equal(fileSteam, steamid))
        {
            found = i;
            break;
        }
    }

    new data[64];
    formatex(data, charsmax(data), "%s %d", steamid, g_playerSelectedSound[id]);

    if (found >= 0)
        write_file(path, data, found);
    else
        write_file(path, data);
}

stock LoadPlayerSelectedKnife(id)
{
    g_playerSelectedKnife[id] = 0;

    if (is_user_bot(id) || is_user_hltv(id))
        return;

    new localValue[16];
    if (EconomyLocalGetSetting(id, "selected_knife", localValue, charsmax(localValue)))
    {
        g_playerSelectedKnife[id] = str_to_num(localValue);
        return;
    }

    new steamid[34];
    get_user_authid(id, steamid, charsmax(steamid));

    new path[192];
    get_datadir(path, charsmax(path));
    add(path, charsmax(path), "/bhop_timer/knives.ini");

    if (!file_exists(path))
        return;

    new line[128], len;
    new lines = file_size(path, 1);

    for (new i = 0; i < lines; i++)
    {
        if (!read_file(path, i, line, charsmax(line), len) || len <= 0)
            continue;

        trim(line);
        if (!line[0] || line[0] == ';')
            continue;

        new fileSteam[34], knifeNum[4];
        if (parse(line, fileSteam, charsmax(fileSteam), knifeNum, charsmax(knifeNum)) < 2)
            continue;

        if (equal(fileSteam, steamid))
        {
            new idx = str_to_num(knifeNum);
            if (idx == 1) g_playerSelectedKnife[id] = 10;
            else if (idx == 2) g_playerSelectedKnife[id] = 11;
            else if (idx == 3) g_playerSelectedKnife[id] = 12;
            else if (idx == 4) g_playerSelectedKnife[id] = 13;
            else if (idx == 5) g_playerSelectedKnife[id] = 20;
            else if (idx == 6) g_playerSelectedKnife[id] = 21;
            else g_playerSelectedKnife[id] = 0;
            num_to_str(g_playerSelectedKnife[id], localValue, charsmax(localValue));
            EconomyLocalSetSetting(id, "selected_knife", localValue);
            return;
        }
    }
}

stock SavePlayerSelectedKnife(id)
{
    if (is_user_bot(id) || is_user_hltv(id))
        return;

    new localValue[16]; num_to_str(g_playerSelectedKnife[id], localValue, charsmax(localValue));
    EconomyLocalSetSetting(id, "selected_knife", localValue);

    new steamid[34];
    get_user_authid(id, steamid, charsmax(steamid));

    new path[192];
    get_datadir(path, charsmax(path));
    add(path, charsmax(path), "/bhop_timer/knives.ini");

    new line[128], len;
    new lines = file_exists(path) ? file_size(path, 1) : 0;
    new found = -1;

    for (new i = 0; i < lines; i++)
    {
        if (!read_file(path, i, line, charsmax(line), len) || len <= 0)
            continue;

        trim(line);
        if (!line[0] || line[0] == ';')
            continue;

        new fileSteam[34];
        parse(line, fileSteam, charsmax(fileSteam));

        if (equal(fileSteam, steamid))
        {
            found = i;
            break;
        }
    }

    new knifeIdx = 0;
    if (g_playerSelectedKnife[id] == 10) knifeIdx = 1;
    else if (g_playerSelectedKnife[id] == 11) knifeIdx = 2;
    else if (g_playerSelectedKnife[id] == 12) knifeIdx = 3;
    else if (g_playerSelectedKnife[id] == 13) knifeIdx = 4;
    else if (g_playerSelectedKnife[id] == 20) knifeIdx = 5;
    else if (g_playerSelectedKnife[id] == 21) knifeIdx = 6;

    new data[64];
    formatex(data, charsmax(data), "%s %d", steamid, knifeIdx);

    if (found >= 0)
        write_file(path, data, found);
    else
        write_file(path, data);
}

stock LoadPlayerSelectedTrail(id)
{
    g_playerSelectedTrail[id] = 0;

    if (is_user_bot(id) || is_user_hltv(id))
        return;

    new localValue[16];
    if (EconomyLocalGetSetting(id, "selected_trail", localValue, charsmax(localValue)))
    {
        g_playerSelectedTrail[id] = str_to_num(localValue);
        return;
    }

    new steamid[34];
    get_user_authid(id, steamid, charsmax(steamid));

    new path[192];
    get_datadir(path, charsmax(path));
    add(path, charsmax(path), "/bhop_timer/trail_selections.ini");

    if (!file_exists(path))
        return;

    new line[128], len;
    new lines = file_size(path, 1);

    for (new i = 0; i < lines; i++)
    {
        if (!read_file(path, i, line, charsmax(line), len) || len <= 0)
            continue;

        trim(line);
        if (!line[0] || line[0] == ';')
            continue;

        new fileSteam[34], trailId[4];
        if (parse(line, fileSteam, charsmax(fileSteam), trailId, charsmax(trailId)) < 2)
            continue;

        if (equal(fileSteam, steamid))
        {
            g_playerSelectedTrail[id] = str_to_num(trailId);
            EconomyLocalSetSetting(id, "selected_trail", trailId);
            return;
        }
    }
}

stock SavePlayerSelectedTrail(id)
{
    if (is_user_bot(id) || is_user_hltv(id))
        return;

    new localValue[16]; num_to_str(g_playerSelectedTrail[id], localValue, charsmax(localValue));
    EconomyLocalSetSetting(id, "selected_trail", localValue);

    new steamid[34];
    get_user_authid(id, steamid, charsmax(steamid));

    new path[192];
    get_datadir(path, charsmax(path));
    add(path, charsmax(path), "/bhop_timer/trail_selections.ini");

    new line[128], len;
    new lines = file_exists(path) ? file_size(path, 1) : 0;
    new found = -1;

    for (new i = 0; i < lines; i++)
    {
        if (!read_file(path, i, line, charsmax(line), len) || len <= 0)
            continue;

        trim(line);
        if (!line[0] || line[0] == ';')
            continue;

        new fileSteam[34];
        parse(line, fileSteam, charsmax(fileSteam));

        if (equal(fileSteam, steamid))
        {
            found = i;
            break;
        }
    }

    new data[64];
    formatex(data, charsmax(data), "%s %d", steamid, g_playerSelectedTrail[id]);

    if (found >= 0)
        write_file(path, data, found);
    else
        write_file(path, data);
}

stock AntiCheatCheck(id)
{
    if (is_user_bot(id) || is_user_hltv(id))
        return;

    new flags = pev(id, pev_flags);
    new bool:onGround = (flags & FL_ONGROUND) ? true : false;
    new bool:inAir = !onGround;
    new Float:now = get_gametime();

    // 1. Air-Stuck Detection
    if (get_pcvar_num(g_cvarAntiCheatAirStuck))
    {
        new Float:vel[3];
        pev(id, pev_velocity, vel);
        new Float:speed = floatsqroot(vel[0] * vel[0] + vel[1] * vel[1]);

        if (inAir && !g_inAirPrev[id])
        {
            g_airStuckStart[id] = now;
            g_airStuckFlagged[id] = false;
        }

        if (inAir && speed < 10.0)
        {
            if (!g_airStuckFlagged[id] && (now - g_airStuckStart[id]) > 8.0)
            {
                g_airStuckFlagged[id] = true;
                AntiCheatTrigger(id, "Air-Stuck");
            }
        }

        g_inAirPrev[id] = inAir;
    }
}

stock AntiCheatTrigger(id, const reason[])
{
    g_cheatWarnings[id]++;

    new name[32];
    get_user_name(id, name, charsmax(name));

    if (g_cheatWarnings[id] == 1)
    {
        TimerChat(id, "^x04[ANTI-CHEAT]^x01 ^x03%s^x01 detected. Warning 1/3. Play fairly!", reason);
    }
    else if (g_cheatWarnings[id] == 2)
    {
        TimerChat(id, "^x04[ANTI-CHEAT]^x01 ^x03%s^x01 detected again. Warning 2/3. Timer reset!", reason);
        if (g_timerState[id] == TIMER_RUNNING || g_timerState[id] == TIMER_IN_START)
        {
            ResetPlayerData(id, false);
        }
    }
    else if (g_cheatWarnings[id] >= 3)
    {
        TimerChat(0, "^x04[ANTI-CHEAT]^x01 ^x03%s^x01 kicked for: ^x04%s", name, reason);
        server_cmd("kick #%d ^"[ANTI-CHEAT] %s^"", get_user_userid(id), reason);
        g_cheatWarnings[id] = 0;
    }
}

stock StrafeForward(id, Float:angles[3])
{
    new Float:fAnglesDiff[3];
    fAnglesDiff[0] = angles[0] - g_fOldStrafeAngles[id][0];
    fAnglesDiff[1] = angles[1] - g_fOldStrafeAngles[id][1];
    fAnglesDiff[2] = angles[2] - g_fOldStrafeAngles[id][2];

    if (fAnglesDiff[YAW] >= 180) fAnglesDiff[YAW] -= 360.0;
    if (fAnglesDiff[YAW] < -180) fAnglesDiff[YAW] += 360.0;

    fAnglesDiff[YAW] = floatabs(fAnglesDiff[YAW]);

    if (fAnglesDiff[YAW] < MAX_ANGLE_CHECK)
    {
        new Float:fDiff = floatabs(fAnglesDiff[YAW] - g_fStrafeOldAnglesDiff[id]);
        new iOldWarn = g_ePlayerInfo[id][m_WarningStrafeAngle];

        if (fDiff < 0.1)
        {
            g_ePlayerInfo[id][m_WarningStrafeAngle] += 5;
        }
        else if (fDiff < MIN_STRAFE_ANGLE_DIFF)
        {
            g_ePlayerInfo[id][m_WarningStrafeAngle]++;
        }
        else if (g_ePlayerInfo[id][m_WarningStrafeAngle])
        {
            g_ePlayerInfo[id][m_WarningStrafeAngle]--;
        }

        new Float:fTime = get_gametime();

        if (g_ePlayerInfo[id][m_WarningStrafeAngle] > iOldWarn)
        {
            if (fTime <= g_ePlayerLog[id][m_LastStrafeAngleLog] + MIN_LOG_TIME)
            {
                if (++g_ePlayerLog[id][m_CountStrafeAngleLog] >= MIN_STRAFE_ANGLE_WARNINGS_TO_LOG)
                {
                    UTIL_LogUser(id, "CheatStrafes: diff %f, cur angle %f, old angle %f", fDiff, fAnglesDiff[YAW], g_fStrafeOldAnglesDiff[id]);
                }
            }
            else
            {
                g_ePlayerLog[id][m_CountStrafeAngleLog] = 0;
            }
            g_ePlayerLog[id][m_LastStrafeAngleLog] = _:fTime;
        }

        if (g_ePlayerInfo[id][m_WarningStrafeAngle] >= MAX_STRAFE_ANGLE_WARNINGS)
        {
            if (fTime >= g_ePlayerLog[id][m_LastChatLog])
            {
                g_ePlayerLog[id][m_LastChatLog] = _:(fTime + MIN_LOG_TIME);
                AntiCheatTrigger(id, "StrafeMacros");
                g_ePlayerInfo[id][m_WarningStrafeAngle] = 0;
            }
            g_ePlayerLog[id][m_CountChatLog]++;
        }
    }

    g_fStrafeOldAnglesDiff[id] = fAnglesDiff[YAW];
    g_fOldStrafeAngles[id] = angles;
}

stock UTIL_LogUser(const id, const szCvar[], any:...)
{
    static szLogFile[128];
    if (!szLogFile[0])
    {
        get_localinfo("amxx_logs", szLogFile, charsmax(szLogFile));
        format(szLogFile, charsmax(szLogFile), "/%s/%s", szLogFile, LOGFILE);
    }
    new iFile;
    if ((iFile = fopen(szLogFile, "a")))
    {
        new szName[32], szAuthid[32], szIp[32], szTime[22];
        new message[128]; vformat(message, charsmax(message), szCvar, 3);

        get_user_name(id, szName, charsmax(szName));
        get_user_authid(id, szAuthid, charsmax(szAuthid));
        get_user_ip(id, szIp, charsmax(szIp), 1);
        get_time("%m/%d/%Y - %H:%M:%S", szTime, charsmax(szTime));

        fprintf(iFile, "L %s: <%s><%s><%s> %s^n", szTime, szName, szAuthid, szIp, message);
        fclose(iFile);
    }
}

stock GetSpecTarget(id)
{
    new specMode = pev(id, pev_iuser1);
    if (specMode == 1 || specMode == 2 || specMode == 4)
    {
        new specTarget = pev(id, pev_iuser2);
        if (specTarget > 0 && is_user_connected(specTarget))
            return specTarget;
    }
    return 0;
}

public CmdSpecNext(id)
{
    if (!is_user_connected(id) || is_user_alive(id))
    {
        TimerChat(id, "You must be spectating to use this command.");
        return PLUGIN_HANDLED;
    }

    new players[32], pnum;
    get_players(players, pnum, "ae", "CT");

    if (pnum == 0)
    {
        TimerChat(id, "No active players to spectate.");
        return PLUGIN_HANDLED;
    }

    new currentTarget = GetSpecTarget(id);
    new found = -1;

    for (new i = 0; i < pnum; i++)
    {
        if (players[i] == currentTarget)
        {
            found = i;
            break;
        }
    }

    new nextTarget = players[(found + 1) % pnum];
    set_pev(id, pev_iuser1, 4);
    set_pev(id, pev_iuser2, nextTarget);

    new name[32];
    get_user_name(nextTarget, name, charsmax(name));
    TimerChat(id, "Now spectating ^x04%s", name);

    return PLUGIN_HANDLED;
}

public CmdSpecPrev(id)
{
    if (!is_user_connected(id) || is_user_alive(id))
    {
        TimerChat(id, "You must be spectating to use this command.");
        return PLUGIN_HANDLED;
    }

    new players[32], pnum;
    get_players(players, pnum, "ae", "CT");

    if (pnum == 0)
    {
        TimerChat(id, "No active players to spectate.");
        return PLUGIN_HANDLED;
    }

    new currentTarget = GetSpecTarget(id);
    new found = -1;

    for (new i = 0; i < pnum; i++)
    {
        if (players[i] == currentTarget)
        {
            found = i;
            break;
        }
    }

    new prevTarget = players[(found - 1 + pnum) % pnum];
    set_pev(id, pev_iuser1, 4);
    set_pev(id, pev_iuser2, prevTarget);

    new name[32];
    get_user_name(prevTarget, name, charsmax(name));
    TimerChat(id, "Now spectating ^x04%s", name);

    return PLUGIN_HANDLED;
}

stock ApplyKnifeFromMarket(id, itemId)
{
    if (!is_user_alive(id))
        return;

    new vModel[64], pModel[64];
    vModel[0] = 0;
    pModel[0] = 0;

    if (itemId == 0)       { copy(vModel, 63, "models/v_knife.mdl"); copy(pModel, 63, "models/p_knife.mdl"); }
    else if (itemId == 10) { copy(vModel, 63, "models/knifes/talon_ed/v_knife.mdl"); copy(pModel, 63, "models/knifes/karambit_ed/p_knife.mdl"); }
    else if (itemId == 11) { copy(vModel, 63, "models/knifes/bayonet_ed/v_knife.mdl"); copy(pModel, 63, "models/knifes/bayonet_ed/p_knife.mdl"); }
    else if (itemId == 12) { copy(vModel, 63, "models/knifes/karambit_ed/v_knife.mdl"); copy(pModel, 63, "models/knifes/karambit_ed/p_knife.mdl"); }
    else if (itemId == 13) { copy(vModel, 63, "models/knifes/butterfly_ed/v_knife.mdl"); copy(pModel, 63, "models/knifes/butterfly_ed/p_knife.mdl"); }
    else if (itemId == 20) { copy(vModel, 63, "models/knifes/vipgold_ed/v_knife.mdl"); copy(pModel, 63, "models/knifes/vipgold_ed/p_knife.mdl"); }
    else if (itemId == 21) { copy(vModel, 63, "models/knifes/vipm9_ed/v_knife.mdl"); copy(pModel, 63, "models/knifes/vipm9_ed/p_knife.mdl"); }

    if (vModel[0])
        set_pev(id, pev_viewmodel2, vModel);
    if (pModel[0])
        set_pev(id, pev_weaponmodel2, pModel);
}
