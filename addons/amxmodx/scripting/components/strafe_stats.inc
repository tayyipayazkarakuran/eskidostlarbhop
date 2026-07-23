#define MAX_STRAFES 32
#define HUD_THROTTLE 0.15

new bool:g_bJumped[MAX_PLAYERS + 1];
new bool:g_bOldOnGround[MAX_PLAYERS + 1];

new bool:g_bStrafingAw[MAX_PLAYERS + 1];
new bool:g_bStrafingSd[MAX_PLAYERS + 1];
new bool:g_bTurningLeft[MAX_PLAYERS + 1];
new bool:g_bTurningRight[MAX_PLAYERS + 1];

new Float:g_fMaxSpeed[MAX_PLAYERS + 1];
new Float:g_fOldAngles[MAX_PLAYERS + 1];
new Float:g_fOldSpeed[MAX_PLAYERS + 1];
new Float:g_fPreStrafe[MAX_PLAYERS + 1];

new g_iGoodSync[MAX_PLAYERS + 1];
new g_iStrafes[MAX_PLAYERS + 1];
new g_iSyncFrames[MAX_PLAYERS + 1];

new g_iStrafeFrames[MAX_PLAYERS + 1][MAX_STRAFES];
new g_iStrafeGoodSync[MAX_PLAYERS + 1][MAX_STRAFES];

new Float:g_fLastHudUpdate[MAX_PLAYERS + 1];

public StrafeStatsInit()
{
}

public StrafeStatsClientInit(id)
{
    ResetPlayerStats(id);
}

public StrafeStatsClientDisconnect(id)
{
    ResetPlayerStats(id);
}

stock ResetPlayerStats(id)
{
    g_bJumped[id] = false;
    g_bOldOnGround[id] = false;

    g_bStrafingAw[id] = false;
    g_bStrafingSd[id] = false;
    g_bTurningLeft[id] = false;
    g_bTurningRight[id] = false;

    g_fMaxSpeed[id] = 0.0;
    g_fOldAngles[id] = 0.0;
    g_fOldSpeed[id] = 0.0;
    g_fPreStrafe[id] = 0.0;

    g_iGoodSync[id] = 0;
    g_iSyncFrames[id] = 0;
    g_iStrafes[id] = 0;

    g_fLastHudUpdate[id] = 0.0;
}

stock StrafeStatsPreThink(id)
{
    new iButtons = pev(id, pev_button);
    new bool:bOnGround = bool:(pev(id, pev_flags) & FL_ONGROUND);

    if (bOnGround && (iButtons & IN_JUMP) && !g_bJumped[id])
    {
        g_bJumped[id] = true;

        new Float:fVelocity[3];
        pev(id, pev_velocity, fVelocity);
        new Float:fSpeed = floatsqroot(fVelocity[0] * fVelocity[0] + fVelocity[1] * fVelocity[1]);

        g_fOldSpeed[id] = g_fMaxSpeed[id] = g_fPreStrafe[id] = fSpeed;

        g_bStrafingAw[id] = false;
        g_bStrafingSd[id] = false;

        g_iGoodSync[id] = 0;
        g_iSyncFrames[id] = 0;
        g_iStrafes[id] = 0;

        for (new i = 0; i < MAX_STRAFES; i++)
        {
            g_iStrafeGoodSync[id][i] = 0;
            g_iStrafeFrames[id][i] = 0;
        }
    }
    else if (bOnGround && g_bJumped[id] && !g_bOldOnGround[id])
    {
        g_bJumped[id] = false;

        ShowJumpStats(id);

        if (iButtons & IN_JUMP)
        {
            StrafeStatsPreThink(id);
        }
    }

    g_bOldOnGround[id] = bOnGround;

    TrackAngles(id);

    if (!bOnGround && g_bJumped[id])
    {
        TrackStrafeAndSync(id);
        ShowLiveHud(id);
    }
}

stock TrackAngles(id)
{
    new Float:fAngles[3];
    pev(id, pev_angles, fAngles);

    g_bTurningRight[id] = false;
    g_bTurningLeft[id] = false;

    if (fAngles[1] < g_fOldAngles[id])
    {
        g_bTurningRight[id] = true;
    }
    else if (fAngles[1] > g_fOldAngles[id])
    {
        g_bTurningLeft[id] = true;
    }

    g_fOldAngles[id] = fAngles[1];
}

stock TrackStrafeAndSync(id)
{
    new iButtons = pev(id, pev_button);
    new Float:fVelocity[3];
    pev(id, pev_velocity, fVelocity);
    new Float:fSpeed = floatsqroot(fVelocity[0] * fVelocity[0] + fVelocity[1] * fVelocity[1]);

    if (g_bTurningLeft[id] || g_bTurningRight[id])
    {
        if (!g_bStrafingAw[id] && ((iButtons & IN_FORWARD) || (iButtons & IN_MOVELEFT))
            && !(iButtons & IN_MOVERIGHT) && !(iButtons & IN_BACK))
        {
            g_bStrafingAw[id] = true;
            g_bStrafingSd[id] = false;

            g_iStrafes[id]++;
        }
        else if (!g_bStrafingSd[id] && ((iButtons & IN_BACK) || (iButtons & IN_MOVERIGHT))
            && !(iButtons & IN_MOVELEFT) && !(iButtons & IN_FORWARD))
        {
            g_bStrafingAw[id] = false;
            g_bStrafingSd[id] = true;

            g_iStrafes[id]++;
        }
    }

    if (g_fMaxSpeed[id] < fSpeed)
        g_fMaxSpeed[id] = fSpeed;

    if (g_fOldSpeed[id] < fSpeed)
    {
        g_iGoodSync[id]++;

        if (g_iStrafes[id] && g_iStrafes[id] <= MAX_STRAFES)
            g_iStrafeGoodSync[id][g_iStrafes[id] - 1]++;
    }

    g_iSyncFrames[id]++;

    if (g_iStrafes[id] && g_iStrafes[id] <= MAX_STRAFES)
        g_iStrafeFrames[id][g_iStrafes[id] - 1]++;

    g_fOldSpeed[id] = fSpeed;
}

stock ShowLiveHud(id)
{
    new Float:now = get_gametime();
    if (now - g_fLastHudUpdate[id] < HUD_THROTTLE)
        return;

    g_fLastHudUpdate[id] = now;

    new iSync = 0;
    if (g_iSyncFrames[id] > 0)
        iSync = floatround(100.0 * g_iGoodSync[id] / g_iSyncFrames[id]);

    set_hudmessage(80, 255, 80, 0.02, 0.72, 0, 0.0, 0.3, 0.0, 0.0, 1);
    show_hudmessage(id, "Sync: %d%% | Strafes: %d", iSync, g_iStrafes[id]);

    // Spectator passthrough - show to anyone spectating this player
    for (new i = 1; i <= MAX_PLAYERS; i++)
    {
        if (!is_user_connected(i) || is_user_alive(i))
            continue;

        new specMode = pev(i, pev_iuser1);
        if ((specMode == 1 || specMode == 2 || specMode == 4) && pev(i, pev_iuser2) == id)
        {
            set_hudmessage(80, 255, 80, 0.02, 0.72, 0, 0.0, 0.3, 0.0, 0.0, 1);
            show_hudmessage(i, "Sync: %d%% | Strafes: %d", iSync, g_iStrafes[id]);
        }
    }
}

stock ShowJumpStats(id)
{
    if (!g_iStrafes[id])
        return;

    for (new i = 1; i <= get_maxplayers(); i++)
    {
        if (!is_user_connected(i) || is_user_alive(i) || pev(i, pev_deadflag) != DEAD_DEAD)
            continue;

        new iSpecmode = pev(i, pev_iuser1);
        if ((iSpecmode == 1 || iSpecmode == 2 || iSpecmode == 4) && pev(i, pev_iuser2) == id)
        {
            new iSync = floatround(100.0 * g_iGoodSync[id] / g_iSyncFrames[id]);

            set_hudmessage(80, 255, 80, 0.02, 0.72, 0, 0.0, 2.0, 0.2, 0.2, 1);
            show_hudmessage(i, "Sync: %d%% | Strafes: %d", iSync, g_iStrafes[id]);
        }
    }
}
