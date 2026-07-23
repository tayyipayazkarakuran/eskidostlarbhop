/*
    Thanks to everyone here: 
        https://dev-cs.ru/resources/1051/
        found errors:             p1oneer, fantom
        optimization:             Xelson, Mistrick

    description:
        This plugin prevents surf bug. 
        What's surf bug? When player sliding or surfing and instantly unintentionally stops.
        The plugin is very useful for jump or surf servers.
        Tested at 1000 FPS surfing.

    How it works:
        1. Detect if player stands or slides on a slope of any angle.
        2. Detect speed is 0 and set speed from start of the frame if not zero.

    version 1.1
        fix: 'prevSpeed' is now saved per player.
        fix: 'lastGoodVelocity' is now saved per player. Some players was getting foreign speed on unstuck.
    version 1.2
        improve source code comments
        changed trace height from 0.01 to 0.5
        deleted notification functionality
    version 1.3
        fix: trace height from 0.5 to 0.01 - Player get speed that he had before teleport onto slope. 
                Since after teleport for one frame he have 0 speed, its detected as surf bug and fixed.
    version 1.4
        fix: surf bug not detected on ramps with trigger_push on them. 
                Because trigger_push changes velocity even if player not move visually.
    version 1.5
        optimization: first check if speed is 0.0 and then if player is on slope. 
                Because second check is expensive since it uses trace_hull.
    version 1.6
        rename: from 'surffix' to 'Surf Fix'    
        optimization: 
            1. is_user_alive cached
            2. removed expensive calculations like vector_length
    version 1.7
        removed is_user_alive caching (was not give better performance)
    version 1.8
        Now surf bug detected during one frame with CmdStart and CmdEnd.
        Previously using only CmdStart was allow 1 frame of player speed=0 (im not sure if its true, but by theory should be)
    version 1.9
        fix: If surfing directly below ceiling, plugin will make you stuck in it.
*/

#include <amxmodx>
#include <fakemeta>

#define AUTHOR "Lopol2010"
#define PLUGIN "Surf Fix"
#define VERSION "1.9"

/*
    How high to teleport player after surf bug. 
    Set more or lower than this have no advantage.
    Set more than 1 will make teleportation noticeable and ruin surfing mechanics, 
    also potentially speed loss on fast moves etc.
*/
#define UNSTUCK_HEIGHT 0.01

/*
    Hull tracing distance below player. 
    Set bigger than 0.01 will introduce bug with teleporting on slopes. Player get speed that he had before teleport.
*/
#define TRACE_HULL_HEIGHT 0.01

new Float:startVelocity[33][3]

public plugin_init()
{
    register_plugin ( PLUGIN, VERSION, AUTHOR )

    register_forward( FM_CmdStart, "OnCmdStart" )
    register_forward( FM_CmdEnd, "OnCmdEnd" )
}

public OnCmdStart(id) 
{
    if(!is_user_alive(id))
    {
        return
    }

    pev(id, pev_velocity, startVelocity[id])
}


public OnCmdEnd(id) 
{

    if(!is_user_alive(id))
    {
        return
    }

    static Float:velocity[3], Float:basevelocity[3]

    pev(id, pev_velocity, velocity)

    //subtract basevelocity from velocity (basically we ignore trigger_push)
    if(!is_vector_zero(velocity))
    {
        pev(id, pev_basevelocity, basevelocity)
        if (!is_vector_zero(basevelocity)) 
        {        
            velocity[0] = floatabs(velocity[0]) - floatabs(basevelocity[0])
            velocity[1] = floatabs(velocity[1]) - floatabs(basevelocity[1])
        }
    }    
    
    // Player might got surf bug
    if(!is_vector_zero(startVelocity[id]) && is_vector_zero(velocity))
    {
        if(is_player_on_slope(id))
        {
            static Float:playerOrigin[3]
            static hull

            hull = pev(id, pev_flags) & FL_DUCKING ? HULL_HEAD : HULL_HUMAN
            pev(id, pev_origin, playerOrigin)
            playerOrigin[2] = playerOrigin[2] + UNSTUCK_HEIGHT

            // Check if position above player isn't a wall, we dont want to teleport into and stuck.
            if(is_hull_vacant(playerOrigin, hull, id)) 
            {
                set_pev(id, pev_origin, playerOrigin)
                set_pev(id, pev_velocity, startVelocity[id])
            }
        }
    }
}

public bool:is_vector_zero(const Float:v[3])
{
    return v[0] == 0.0 && v[1] == 0.0
}

stock bool:is_hull_vacant(const Float:origin[3], hull, id) {
    static tr
    engfunc(EngFunc_TraceHull, origin, origin, 0, hull, id, tr)
    if (!get_tr2(tr, TR_StartSolid) || !get_tr2(tr, TR_AllSolid)) //get_tr2(tr, TR_InOpen))
        return true
    
    return false
}

// Slope with any angle
stock bool:is_player_on_slope(id) 
{
    static Float:planeNormal[3], Float:traceHullEnd[3], Float:playerOrigin[3]
    static Float:rampAngle, hull

    pev(id, pev_origin, playerOrigin)

    traceHullEnd[0] = playerOrigin[0]
    traceHullEnd[1] = playerOrigin[1]
    traceHullEnd[2] = playerOrigin[2] - TRACE_HULL_HEIGHT

    hull = pev(id, pev_flags) & FL_DUCKING ? HULL_HEAD : HULL_HUMAN

    engfunc(EngFunc_TraceHull, playerOrigin, traceHullEnd, IGNORE_MONSTERS | IGNORE_MISSILE, hull, id, 0)
    get_tr2(0, TR_vecPlaneNormal, planeNormal)

    rampAngle = planeNormal[2]

    return rampAngle != 0.0 && rampAngle != 1.0
}
