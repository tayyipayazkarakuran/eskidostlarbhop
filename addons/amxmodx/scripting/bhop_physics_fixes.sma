#include <amxmodx>
#include <amxmisc>
#include <fakemeta>
#include <engine>

#define PLUGIN_NAME    "Bhop Physics Bug Fixes"
#define PLUGIN_VERSION "1.0.3"
#define PLUGIN_AUTHOR  "Codex"

// Safety limit for array sizes (supports up to 35 slots/entities including HLTV)
#define MAX_SLOTS 36

new g_cvarSurfFix;
new g_cvarWaterJumpFix;
new g_cvarEdgebugFix;
new g_cvarKeepTeleportVelocity;
new g_cvarSurfMinSpeed;
new g_cvarSurfRestoreVelocity;
new g_cvarSurfUnstuckHeight;
new g_cvarSurfTraceHeight;

new g_prevWaterLevel[MAX_SLOTS];
new Float:g_preThinkVelocity[MAX_SLOTS][3];
new Float:g_preThinkOrigin[MAX_SLOTS][3];
new Float:g_surfFrameStartVelocity[MAX_SLOTS][3];
new bool:g_wasTeleported[MAX_SLOTS];

public plugin_init()
{
    register_plugin(PLUGIN_NAME, PLUGIN_VERSION, PLUGIN_AUTHOR);

    g_cvarSurfFix = register_cvar("bhop_surf_fix", "1");
    g_cvarWaterJumpFix = register_cvar("bhop_waterjump_fix", "1");
    g_cvarEdgebugFix = register_cvar("bhop_edgebug_fix", "0");
    g_cvarKeepTeleportVelocity = register_cvar("bhop_keep_teleport_velocity", "0");
    g_cvarSurfMinSpeed = register_cvar("bhop_surf_fix_min_speed", "180.0");
    g_cvarSurfRestoreVelocity = register_cvar("bhop_surf_fix_restore_velocity", "0");
    g_cvarSurfUnstuckHeight = register_cvar("bhop_surf_fix_unstuck_height", "0.01");
    g_cvarSurfTraceHeight = register_cvar("bhop_surf_fix_trace_height", "0.01");

    register_forward(FM_CmdStart, "FwCmdStart");
    register_forward(FM_CmdEnd, "FwCmdEnd");
    register_forward(FM_PlayerPreThink, "FwPlayerPreThink");
    register_forward(FM_PlayerPostThink, "FwPlayerPostThink");
    register_touch("trigger_teleport", "player", "FwTeleportTouch");
}

public client_putinserver(id)
{
    if (id < 1 || id >= MAX_SLOTS)
        return;

    g_prevWaterLevel[id] = 0;
    g_preThinkVelocity[id][0] = 0.0;
    g_preThinkVelocity[id][1] = 0.0;
    g_preThinkVelocity[id][2] = 0.0;
    g_preThinkOrigin[id][0] = 0.0;
    g_preThinkOrigin[id][1] = 0.0;
    g_preThinkOrigin[id][2] = 0.0;
    g_surfFrameStartVelocity[id][0] = 0.0;
    g_surfFrameStartVelocity[id][1] = 0.0;
    g_surfFrameStartVelocity[id][2] = 0.0;
    g_wasTeleported[id] = false;
}

public client_disconnected(id)
{
    client_putinserver(id);
}

public FwCmdStart(id)
{
    if (id < 1 || id >= MAX_SLOTS)
        return FMRES_IGNORED;

    if (!get_pcvar_num(g_cvarSurfFix) || !is_user_alive(id) || is_user_bot(id))
        return FMRES_IGNORED;

    pev(id, pev_velocity, g_surfFrameStartVelocity[id]);

    return FMRES_IGNORED;
}

public FwCmdEnd(id)
{
    if (id < 1 || id >= MAX_SLOTS)
        return FMRES_IGNORED;

    if (!get_pcvar_num(g_cvarSurfFix) || !is_user_alive(id) || is_user_bot(id))
        return FMRES_IGNORED;

    FixSurfStop(id);

    return FMRES_IGNORED;
}

public FwPlayerPreThink(id)
{
    if (id < 1 || id >= MAX_SLOTS)
        return FMRES_IGNORED;

    if (!is_user_alive(id) || is_user_bot(id))
        return FMRES_IGNORED;

    pev(id, pev_velocity, g_preThinkVelocity[id]);
    pev(id, pev_origin, g_preThinkOrigin[id]);

    new buttons = pev(id, pev_button);
    new waterlevel = pev(id, pev_waterlevel);

    // 1. Water Jump Fix
    if (get_pcvar_num(g_cvarWaterJumpFix))
    {
        if (waterlevel < 2 && g_prevWaterLevel[id] >= 2 && (buttons & IN_JUMP))
        {
            new Float:vel[3];
            pev(id, pev_velocity, vel);
            if (vel[2] < 200.0)
            {
                vel[2] = 300.0; // Boost them out of water
                set_pev(id, pev_velocity, vel);
            }
        }
        g_prevWaterLevel[id] = waterlevel;
    }

    return FMRES_IGNORED;
}

public FwPlayerPostThink(id)
{
    if (id < 1 || id >= MAX_SLOTS)
        return FMRES_IGNORED;

    if (!is_user_alive(id) || is_user_bot(id))
        return FMRES_IGNORED;

    // Clear accidental ground contact only after engine physics ran. The timer plugin owns autobhop.
    CheckSurf(id);

    // 4. Edge Bug Fix (Keep speed when landing exactly on outer edges)
    if (get_pcvar_num(g_cvarEdgebugFix))
    {
        new Float:currentVelocity[3];
        pev(id, pev_velocity, currentVelocity);

        // If player was falling but vertical speed suddenly dropped to 0 (landed)
        if (g_preThinkVelocity[id][2] < -100.0 && floatabs(currentVelocity[2]) < 5.0)
        {
            new Float:origin[3];
            pev(id, pev_origin, origin);

            // Test if player is standing on an outer edge by tracing down at 4 slightly offset points
            new Float:testOffset = 18.0;
            new Float:downDist = 24.0;
            new edgeHits = 0;

            for (new i = 0; i < 4; i++)
            {
                new Float:start[3], Float:end[3];
                start[0] = origin[0] + ((i == 0) ? testOffset : ((i == 1) ? -testOffset : 0.0));
                start[1] = origin[1] + ((i == 2) ? testOffset : ((i == 3) ? -testOffset : 0.0));
                start[2] = origin[2];

                end[0] = start[0]; end[1] = start[1]; end[2] = start[2] - downDist;

                new trace = create_tr2();
                engfunc(EngFunc_TraceLine, start, end, IGNORE_MONSTERS, id, trace);
                new Float:frac;
                get_tr2(trace, TR_flFraction, frac);
                free_tr2(trace);

                if (frac == 1.0)
                {
                    edgeHits++;
                }
            }

            // If at least 1 or 2 directions find empty space beneath, they landed on an outer edge!
            if (edgeHits >= 1)
            {
                // Restore their pre-think horizontal speed to slide off cleanly
                new Float:newVel[3];
                newVel[0] = g_preThinkVelocity[id][0];
                newVel[1] = g_preThinkVelocity[id][1];
                newVel[2] = 0.0; // negates landing deceleration/damage
                set_pev(id, pev_velocity, newVel);
            }
        }
    }

    // 5. Teleport Velocity Reset (Failsafe displacement check + touch callback)
    new Float:postThinkOrigin[3];
    pev(id, pev_origin, postThinkOrigin);

    new Float:dx = postThinkOrigin[0] - g_preThinkOrigin[id][0];
    new Float:dy = postThinkOrigin[1] - g_preThinkOrigin[id][1];
    new Float:dz = postThinkOrigin[2] - g_preThinkOrigin[id][2];

    if ((dx * dx + dy * dy + dz * dz) > 62500.0) // 250.0^2
    {
        g_wasTeleported[id] = true;
    }

    if (g_wasTeleported[id])
    {
        g_wasTeleported[id] = false;

        if (get_pcvar_num(g_cvarKeepTeleportVelocity) == 0)
        {
            new Float:zero[3];
            set_pev(id, pev_velocity, zero);
            set_pev(id, pev_basevelocity, zero);
        }
    }

    return FMRES_IGNORED;
}

public FwTeleportTouch(teleport, id)
{
    if (id < 1 || id >= MAX_SLOTS)
        return PLUGIN_CONTINUE;

    if (!is_user_alive(id)) 
        return PLUGIN_CONTINUE;

    g_wasTeleported[id] = true;

    return PLUGIN_CONTINUE;
}

stock CheckSurf(id)
{
    if (!get_pcvar_num(g_cvarSurfFix))
        return;

    new flags = pev(id, pev_flags);
    new bool:onGround = (flags & FL_ONGROUND) ? true : false;
    if (!onGround)
        return;
    
    new Float:currentVelocity[3];
    pev(id, pev_velocity, currentVelocity);
    
    new Float:preHorizSpeed = floatsqroot(g_preThinkVelocity[id][0]*g_preThinkVelocity[id][0] + g_preThinkVelocity[id][1]*g_preThinkVelocity[id][1]);
    new Float:postHorizSpeed = floatsqroot(currentVelocity[0]*currentVelocity[0] + currentVelocity[1]*currentVelocity[1]);
    
    if (preHorizSpeed < get_pcvar_float(g_cvarSurfMinSpeed) && postHorizSpeed < get_pcvar_float(g_cvarSurfMinSpeed))
        return;

    new bool:speedDropped = (preHorizSpeed - postHorizSpeed > 15.0);

    new Float:origin[3];
    pev(id, pev_origin, origin);

    new Float:end[3];
    end[0] = origin[0];
    end[1] = origin[1];
    end[2] = origin[2] - 48.0;

    new trace = create_tr2();
    
    // First, try a line trace. Line traces never start solid because the player's origin is in the air.
    engfunc(EngFunc_TraceLine, origin, end, IGNORE_MONSTERS, id, trace);

    new Float:fraction;
    get_tr2(trace, TR_flFraction, fraction);

    new bool:foundSlope = false;
    new Float:normal[3];

    if (fraction < 1.0)
    {
        get_tr2(trace, TR_vecPlaneNormal, normal);
        if (normal[2] > 0.01 && normal[2] <= 0.70)
        {
            foundSlope = true;
        }
    }

    // If line trace didn't find a slope, try a hull trace (sweeping the player's bounding box)
    if (!foundSlope)
    {
        free_tr2(trace);
        trace = create_tr2();
        
        // Start 16 units higher to prevent starting solid due to embedding at high FPS
        new Float:start[3];
        start[0] = origin[0];
        start[1] = origin[1];
        start[2] = origin[2] + 16.0;
        
        end[0] = origin[0];
        end[1] = origin[1];
        end[2] = origin[2] - ((flags & FL_DUCKING) ? 18.0 : 36.0) - 2.0;
        
        new hull = (flags & FL_DUCKING) ? HULL_HEAD : HULL_HUMAN;
        engfunc(EngFunc_TraceHull, start, end, IGNORE_MONSTERS, hull, id, trace);
        
        get_tr2(trace, TR_flFraction, fraction);
        if (fraction < 1.0 && !get_tr2(trace, TR_StartSolid))
        {
            get_tr2(trace, TR_vecPlaneNormal, normal);
            if (normal[2] > 0.01 && normal[2] <= 0.70)
            {
                foundSlope = true;
            }
        }
    }

    if (foundSlope)
    {
        set_pev(id, pev_flags, flags & ~FL_ONGROUND);
        set_pev(id, pev_groundentity, 0);

        if (get_pcvar_num(g_cvarSurfRestoreVelocity) && speedDropped)
        {
            new Float:restoredVelocity[3];
            restoredVelocity[0] = g_preThinkVelocity[id][0];
            restoredVelocity[1] = g_preThinkVelocity[id][1];
            restoredVelocity[2] = currentVelocity[2]; // Preserve vertical velocity computed by engine
            
            set_pev(id, pev_velocity, restoredVelocity);
        }
    }
    
    free_tr2(trace);
}

stock FixSurfStop(id)
{
    new Float:velocity[3];
    new Float:baseVelocity[3];
    new Float:testVelocity[3];

    pev(id, pev_velocity, velocity);
    testVelocity[0] = velocity[0];
    testVelocity[1] = velocity[1];
    testVelocity[2] = velocity[2];

    // trigger_push uses basevelocity; ignore it so push ramps do not hide a zeroed surf frame.
    if (!IsZeroVelocity2D(testVelocity))
    {
        pev(id, pev_basevelocity, baseVelocity);
        if (!IsZeroVelocity2D(baseVelocity))
        {
            testVelocity[0] = floatabs(testVelocity[0]) - floatabs(baseVelocity[0]);
            testVelocity[1] = floatabs(testVelocity[1]) - floatabs(baseVelocity[1]);
        }
    }

    if (IsZeroVelocity2D(g_surfFrameStartVelocity[id]) || !IsZeroVelocity2D(testVelocity))
        return;

    if (!IsPlayerOnAnySlope(id, get_pcvar_float(g_cvarSurfTraceHeight)))
        return;

    new Float:origin[3];
    pev(id, pev_origin, origin);

    new hull = (pev(id, pev_flags) & FL_DUCKING) ? HULL_HEAD : HULL_HUMAN;
    origin[2] += get_pcvar_float(g_cvarSurfUnstuckHeight);

    if (!IsHullVacant(origin, hull, id))
        return;

    set_pev(id, pev_origin, origin);
    set_pev(id, pev_velocity, g_surfFrameStartVelocity[id]);
}

stock bool:IsZeroVelocity2D(const Float:velocity[3])
{
    return velocity[0] == 0.0 && velocity[1] == 0.0;
}

stock bool:IsHullVacant(const Float:origin[3], hull, id)
{
    new trace = create_tr2();
    engfunc(EngFunc_TraceHull, origin, origin, IGNORE_MONSTERS, hull, id, trace);

    new bool:startSolid = get_tr2(trace, TR_StartSolid) ? true : false;
    new bool:allSolid = get_tr2(trace, TR_AllSolid) ? true : false;
    free_tr2(trace);

    return !startSolid && !allSolid;
}

stock bool:IsPlayerOnAnySlope(id, Float:traceHeight)
{
    if (traceHeight < 0.01)
        traceHeight = 0.01;

    new Float:origin[3];
    new Float:end[3];
    new Float:normal[3];

    pev(id, pev_origin, origin);
    end[0] = origin[0];
    end[1] = origin[1];
    end[2] = origin[2] - traceHeight;

    new hull = (pev(id, pev_flags) & FL_DUCKING) ? HULL_HEAD : HULL_HUMAN;
    new trace = create_tr2();
    engfunc(EngFunc_TraceHull, origin, end, IGNORE_MONSTERS, hull, id, trace);
    get_tr2(trace, TR_vecPlaneNormal, normal);
    free_tr2(trace);

    return normal[2] != 0.0 && normal[2] != 1.0;
}
