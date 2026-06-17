#include <amxmodx>
#include <cstrike>
#include <fakemeta>

#define PLUGIN_NAME    "Scoreboard FPS Display"
#define PLUGIN_VERSION "1.0.0"
#define PLUGIN_AUTHOR  "Codex"

new g_fpsCount[33];
new g_fpsValue[33];
new g_msgScoreInfo;

public plugin_init()
{
    register_plugin(PLUGIN_NAME, PLUGIN_VERSION, PLUGIN_AUTHOR);

    register_forward(FM_PlayerPreThink, "FwPlayerPreThink");

    g_msgScoreInfo = get_user_msgid("ScoreInfo");
    register_message(g_msgScoreInfo, "MsgScoreInfo");

    set_task(1.0, "TaskUpdateFps", 10001, _, _, "b");
}

public client_putinserver(id)
{
    g_fpsCount[id] = 0;
    g_fpsValue[id] = 0;
}

public client_disconnected(id)
{
    g_fpsCount[id] = 0;
    g_fpsValue[id] = 0;
}

public FwPlayerPreThink(id)
{
    if (is_user_connected(id))
    {
        g_fpsCount[id]++;
    }
    return FMRES_IGNORED;
}

public TaskUpdateFps()
{
    for (new id = 1; id <= 32; id++)
    {
        if (is_user_connected(id) && !is_user_bot(id))
        {
            g_fpsValue[id] = g_fpsCount[id];
            g_fpsCount[id] = 0;

            // Broadcast the scoreboard update to all clients
            UpdateScoreboard(id);
        }
    }
}

public MsgScoreInfo(msgid, dest, id)
{
    new player = get_msg_arg_int(1);
    if (1 <= player <= 32 && is_user_connected(player) && !is_user_bot(player))
    {
        // Replace deaths (arg 3) with player's active FPS value
        set_msg_arg_int(3, ARG_SHORT, g_fpsValue[player]);
    }
}

UpdateScoreboard(id)
{
    if (!is_user_connected(id)) return;

    new frags = get_user_frags(id);
    new team = _:cs_get_user_team(id);

    message_begin(MSG_ALL, g_msgScoreInfo);
    write_byte(id);
    write_short(frags);
    write_short(g_fpsValue[id]); // Custom value (FPS) in the deaths column
    write_short(0);
    write_short(team);
    message_end();
}
