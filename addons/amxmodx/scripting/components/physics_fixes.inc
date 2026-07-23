#include <amxmodx>
#include <amxmisc>
#include <fakemeta>
#include <engine>

// Safety limit for array sizes (supports up to 35 slots/entities including HLTV)
#define MAX_SLOTS 36

new g_cvarWaterJumpFix;
new g_cvarEdgebugFix;
new g_cvarKeepTeleportVelocity;

new g_cacheWaterJumpFix;
new g_cacheEdgebugFix;
new g_cacheKeepTeleportVelocity;

new g_prevWaterLevel[MAX_SLOTS];
new Float:g_preThinkVelocity[MAX_SLOTS][3];
new Float:g_preThinkOrigin[MAX_SLOTS][3];
new bool:g_wasTeleported[MAX_SLOTS];

public plugin_init()
{
    g_cvarWaterJumpFix = register_cvar("bhop_waterjump_fix", "1");
    g_cvarEdgebugFix = register_cvar("bhop_edgebug_fix", "0");
    g_cvarKeepTeleportVelocity = register_cvar("bhop_keep_teleport_velocity", "0");

    register_forward(FM_PlayerPostThink, "PhysicsFixesPostThink");

    CacheCvars();
}

public TaskRefreshCvars()
{
    CacheCvars();
}

stock CacheCvars()
{
    g_cacheWaterJumpFix = get_pcvar_num(g_cvarWaterJumpFix);
    g_cacheEdgebugFix = get_pcvar_num(g_cvarEdgebugFix);
    g_cacheKeepTeleportVelocity = get_pcvar_num(g_cvarKeepTeleportVelocity);
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
    g_wasTeleported[id] = false;
}

public client_disconnected(id)
{
    client_putinserver(id);
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

    if (g_cacheWaterJumpFix)
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

    // Edge Bug Fix (Keep speed when landing exactly on outer edges)
    if (g_cacheEdgebugFix)
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

        if (g_cacheKeepTeleportVelocity == 0)
        {
            new Float:zero[3];
            set_pev(id, pev_velocity, zero);
            set_pev(id, pev_basevelocity, zero);
        }
    }

    return FMRES_IGNORED;
}
