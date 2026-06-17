#include <amxmodx>
#include <amxmisc>

#define PLUGIN_NAME    "Bhop Map Manager"
#define PLUGIN_VERSION "1.2.0"
#define PLUGIN_AUTHOR  "Codex"

#define MAX_PLAYERS 32
#define MAX_MAPS 128

new g_maps[MAX_MAPS][32];
new g_mapCount;

new bool:g_nominated[MAX_MAPS];
new g_nominateCount;
new g_nominations[MAX_PLAYERS + 1] = {-1, ...}; // map index nominated by player

new bool:g_rtvVoted[MAX_PLAYERS + 1];
new g_rtvVotes;

new g_voteMaps[5];
new g_voteMapCount;
new g_voteCounts[5];
new bool:g_voteActive;
new g_voteTimer;

new bool:g_rtvChangeDecided = false;
new g_nextMapName[32] = "";
new g_cvarChatPrefix;

public plugin_init()
{
    register_plugin(PLUGIN_NAME, PLUGIN_VERSION, PLUGIN_AUTHOR);

    register_clcmd("say", "HookSay");
    register_clcmd("say_team", "HookSay");

    g_cvarChatPrefix = register_cvar("bhop_chat_prefix", "[TIMER]");
    register_cvar("amx_nextmap", "");

    LoadMapcycle();
}

public client_putinserver(id)
{
    g_rtvVoted[id] = false;
    g_nominations[id] = -1;
}

public client_disconnected(id)
{
    if (g_rtvVoted[id])
    {
        g_rtvVoted[id] = false;
        g_rtvVotes--;
        CheckRtvThreshold();
    }
    
    new nom = g_nominations[id];
    if (nom != -1)
    {
        g_nominated[nom] = false;
        g_nominateCount--;
        g_nominations[id] = -1;
    }
}

LoadMapcycle()
{
    g_mapCount = 0;
    new path[128];
    get_configsdir(path, charsmax(path));
    // Check in cstrike/ first
    formatex(path, charsmax(path), "mapcycle.txt");
    if (!file_exists(path))
    {
        // Try configs/maps.ini as fallback
        get_configsdir(path, charsmax(path));
        add(path, charsmax(path), "/maps.ini");
    }

    if (!file_exists(path))
    {
        log_amx("[MAP MANAGER] Map file not found: %s", path);
        return;
    }

    new fp = fopen(path, "rt");
    if (!fp) return;

    new line[64], currentMap[32];
    get_mapname(currentMap, charsmax(currentMap));

    while (!feof(fp) && g_mapCount < MAX_MAPS)
    {
        fgets(fp, line, charsmax(line));
        trim(line);

        if (!line[0] || line[0] == ';' || line[0] == '#')
            continue;

        // Skip current map
        if (equal(line, currentMap))
            continue;

        copy(g_maps[g_mapCount], 31, line);
        g_nominated[g_mapCount] = false;
        g_mapCount++;
    }
    fclose(fp);
    log_amx("[MAP MANAGER] Loaded %d maps from %s", g_mapCount, path);
}

public HookSay(id)
{
    new args[128];
    read_args(args, charsmax(args));
    remove_quotes(args);
    trim(args);

    if (equali(args, "rtv") || equali(args, "/rtv"))
    {
        CmdRtv(id);
        return PLUGIN_HANDLED;
    }
    else if (equali(args, "nominate") || equali(args, "/nominate"))
    {
        CmdNominate(id);
        return PLUGIN_HANDLED;
    }
    else if (equali(args, "nextmap") || equali(args, "/nextmap"))
    {
        CmdNextmap(id);
        return PLUGIN_HANDLED;
    }
    else if (equali(args, "timeleft") || equali(args, "/timeleft"))
    {
        CmdTimeleft(id);
        return PLUGIN_HANDLED;
    }

    return PLUGIN_CONTINUE;
}

public CmdRtv(id)
{
    if (g_voteActive)
    {
        ManagerChat(id, "A map vote is already in progress.");
        return PLUGIN_HANDLED;
    }

    if (g_rtvChangeDecided)
    {
        new nextMap[32];
        get_cvar_string("amx_nextmap", nextMap, charsmax(nextMap));
        ManagerChat(id, "Next map is already decided: ^x04%s", nextMap);
        return PLUGIN_HANDLED;
    }

    if (g_rtvVoted[id])
    {
        ManagerChat(id, "You have already voted for RTV.");
        return PLUGIN_HANDLED;
    }

    g_rtvVoted[id] = true;
    g_rtvVotes++;

    new activePlayers = GetActivePlayerCount();
    new reqVotes = GetRequiredRtvVotes(activePlayers);

    new name[32];
    get_user_name(id, name, charsmax(name));
    ManagerChat(0, "^x04%s^x01 wants to rock the vote! (^x04%d^x01/^x04%d^x01 votes needed)", name, g_rtvVotes, reqVotes);

    CheckRtvThreshold();
    return PLUGIN_HANDLED;
}

GetRequiredRtvVotes(activePlayers)
{
    if (activePlayers <= 2)
    {
        return 1;
    }
    return (activePlayers / 2) + 1;
}

CheckRtvThreshold()
{
    new activePlayers = GetActivePlayerCount();
    if (activePlayers == 0) return;

    new reqVotes = GetRequiredRtvVotes(activePlayers);

    if (g_rtvVotes >= reqVotes)
    {
        StartMapVote();
    }
}

public CmdNominate(id)
{
    if (g_voteActive)
    {
        ManagerChat(id, "Nominations are closed. A vote is active.");
        return PLUGIN_HANDLED;
    }

    if (g_nominations[id] != -1)
    {
        new prevMapName[32];
        copy(prevMapName, charsmax(prevMapName), g_maps[g_nominations[id]]);
        ManagerChat(id, "You already nominated ^x04%s^x01. Type /rtv or wait for the vote.", prevMapName);
        return PLUGIN_HANDLED;
    }

    new menu = menu_create("Bhop Nominate a Map", "NominateMenuHandler");
    new count = 0;

    for (new i = 0; i < g_mapCount; i++)
    {
        new itemText[64], info[6];
        num_to_str(i, info, charsmax(info));
        
        if (g_nominated[i])
        {
            formatex(itemText, charsmax(itemText), "\d%s [Nominated]", g_maps[i]);
            menu_additem(menu, itemText, info, _, menu_makecallback("DisabledItemCallback"));
        }
        else
        {
            formatex(itemText, charsmax(itemText), "%s", g_maps[i]);
            menu_additem(menu, itemText, info);
            count++;
        }
    }

    if (count == 0 && g_mapCount == 0)
    {
        ManagerChat(id, "No maps found in mapcycle.");
        menu_destroy(menu);
        return PLUGIN_HANDLED;
    }

    menu_setprop(menu, MPROP_EXIT, MEXIT_ALL);
    menu_display(id, menu, 0);
    return PLUGIN_HANDLED;
}

public DisabledItemCallback(id, menu, item)
{
    return ITEM_DISABLED;
}

public NominateMenuHandler(id, menu, item)
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

    new mapIdx = str_to_num(info);
    if (g_nominated[mapIdx])
    {
        ManagerChat(id, "This map is already nominated.");
        return PLUGIN_HANDLED;
    }

    g_nominations[id] = mapIdx;
    g_nominated[mapIdx] = true;
    g_nominateCount++;

    new playerName[32];
    get_user_name(id, playerName, charsmax(playerName));
    ManagerChat(0, "^x04%s^x01 nominated map: ^x04%s", playerName, g_maps[mapIdx]);

    return PLUGIN_HANDLED;
}

StartMapVote()
{
    if (g_voteActive) return;

    g_voteActive = true;
    g_voteMapCount = 0;

    // 1. Gather all nominated maps
    for (new i = 0; i < g_mapCount && g_voteMapCount < 5; i++)
    {
        if (g_nominated[i])
        {
            g_voteMaps[g_voteMapCount++] = i;
        }
    }

    // 2. Fill rest with random maps from mapcycle
    new safety = 0;
    while (g_voteMapCount < 5 && g_voteMapCount < g_mapCount && safety < 500)
    {
        safety++;
        new randIdx = random_num(0, g_mapCount - 1);
        
        // Check if already in vote
        new bool:dup = false;
        for (new j = 0; j < g_voteMapCount; j++)
        {
            if (g_voteMaps[j] == randIdx)
            {
                dup = true;
                break;
            }
        }
        if (!dup)
        {
            g_voteMaps[g_voteMapCount++] = randIdx;
        }
    }

    for (new i = 0; i < g_voteMapCount; i++)
    {
        g_voteCounts[i] = 0;
    }

    g_voteTimer = 15;
    ManagerChat(0, "RTV voting has started! Choose next map.");

    // Display vote menu to all players
    for (new i = 1; i <= MAX_PLAYERS; i++)
    {
        if (is_user_connected(i) && !is_user_bot(i))
        {
            ShowVoteMenu(i);
        }
    }

    set_task(1.0, "TaskVoteCountdown", 9999);
}

ShowVoteMenu(id)
{
    new menu = menu_create("Bhop RTV Next Map Vote", "VoteMenuHandler");
    
    for (new i = 0; i < g_voteMapCount; i++)
    {
        new itemText[64], info[6];
        num_to_str(i, info, charsmax(info));
        formatex(itemText, charsmax(itemText), "%s \y[%d votes]", g_maps[g_voteMaps[i]], g_voteCounts[i]);
        menu_additem(menu, itemText, info);
    }

    menu_setprop(menu, MPROP_EXIT, MEXIT_NEVER);
    menu_display(id, menu, 0);
}

public VoteMenuHandler(id, menu, item)
{
    if (!g_voteActive)
    {
        menu_destroy(menu);
        return PLUGIN_HANDLED;
    }

    if (item == MENU_EXIT)
    {
        menu_destroy(menu);
        return PLUGIN_HANDLED;
    }

    new info[6];
    new access, callback;
    menu_item_getinfo(menu, item, access, info, charsmax(info), _, _, callback);
    menu_destroy(menu);

    new choice = str_to_num(info);
    g_voteCounts[choice]++;

    new name[32];
    get_user_name(id, name, charsmax(name));
    client_print(id, print_chat, "[RTV] You voted for %s.", g_maps[g_voteMaps[choice]]);

    new activePlayers = GetActivePlayerCount();
    if (activePlayers <= 1)
    {
        EndVote();
    }

    return PLUGIN_HANDLED;
}

public TaskVoteCountdown()
{
    if (!g_voteActive) return;

    g_voteTimer--;

    if (g_voteTimer > 0)
    {
        if (g_voteTimer == 10 || g_voteTimer == 5)
        {
            ManagerChat(0, "RTV voting ends in ^x04%d^x01 seconds...", g_voteTimer);
        }
        set_task(1.0, "TaskVoteCountdown", 9999);
    }
    else
    {
        EndVote();
    }
}

EndVote()
{
    g_voteActive = false;
    remove_task(9999);

    // Force close menus for everyone
    for (new i = 1; i <= MAX_PLAYERS; i++)
    {
        if (is_user_connected(i))
        {
            menu_cancel(i);
        }
    }

    new winnerIdx = 0;
    new maxVotes = g_voteCounts[0];

    for (new i = 1; i < g_voteMapCount; i++)
    {
        if (g_voteCounts[i] > maxVotes)
        {
            maxVotes = g_voteCounts[i];
            winnerIdx = i;
        }
    }

    new winnerMap[32];
    copy(winnerMap, charsmax(winnerMap), g_maps[g_voteMaps[winnerIdx]]);

    copy(g_nextMapName, charsmax(g_nextMapName), winnerMap);
    set_cvar_string("amx_nextmap", winnerMap);
    g_rtvChangeDecided = true;
    
    new activePlayers = GetActivePlayerCount();
    if (activePlayers <= 1)
    {
        ManagerChat(0, "RTV Vote finished! Winner: ^x04%s^x01 with ^x04%d^x01 votes.", winnerMap, maxVotes);
        ManagerChat(0, "Changing map to ^x04%s^x01 in 1 second...", winnerMap);
        set_task(1.0, "TaskChangeMap", 8888);
    }
    else
    {
        ManagerChat(0, "RTV Vote finished! Winner: ^x04%s^x01 with ^x04%d^x01 votes.", winnerMap, maxVotes);
        ManagerChat(0, "Changing map to ^x04%s^x01 in 3 seconds...", winnerMap);
        set_task(3.0, "TaskChangeMap", 8888);
    }
}

public TaskChangeMap()
{
    new nextMap[32];
    if (g_nextMapName[0])
    {
        copy(nextMap, charsmax(nextMap), g_nextMapName);
    }
    else
    {
        get_cvar_string("amx_nextmap", nextMap, charsmax(nextMap));
    }

    if (nextMap[0])
    {
        server_cmd("changelevel %s", nextMap);
    }
}

public CmdNextmap(id)
{
    new nextMap[32];
    get_cvar_string("amx_nextmap", nextMap, charsmax(nextMap));
    if (nextMap[0])
    {
        ManagerChat(id, "Next map will be: ^x04%s", nextMap);
    }
    else
    {
        ManagerChat(id, "Next map is not decided yet. Nominate with /nominate or RTV.");
    }
    return PLUGIN_HANDLED;
}

public CmdTimeleft(id)
{
    new timeleft = get_timeleft();
    new minutes = timeleft / 60;
    new seconds = timeleft % 60;

    if (timeleft > 0)
    {
        ManagerChat(id, "Time remaining on map: ^x04%02d:%02d", minutes, seconds);
    }
    else
    {
        ManagerChat(id, "No time limit on this map.");
    }
    return PLUGIN_HANDLED;
}

GetActivePlayerCount()
{
    new count = 0;
    for (new i = 1; i <= MAX_PLAYERS; i++)
    {
        if (is_user_connected(i) && !is_user_bot(i) && !is_user_hltv(i))
        {
            count++;
        }
    }
    return count;
}

ManagerChat(id, const fmt[], any:...)
{
    new message[192], finalMessage[192], prefix[32];
    vformat(message, charsmax(message), fmt, 3);
    get_pcvar_string(g_cvarChatPrefix, prefix, charsmax(prefix));
    formatex(finalMessage, charsmax(finalMessage), "^x04%s^x01 %s", prefix, message);

    new msgSayText = get_user_msgid("SayText");
    new msgTeamInfo = get_user_msgid("TeamInfo");

    if (id)
    {
        if (is_user_connected(id))
        {
            message_begin(MSG_ONE_UNRELIABLE, msgTeamInfo, _, id);
            write_byte(id);
            write_string("TERRORIST");
            message_end();

            message_begin(MSG_ONE_UNRELIABLE, msgSayText, _, id);
            write_byte(id);
            write_string(finalMessage);
            message_end();
        }
        return;
    }

    for (new player = 1; player <= MAX_PLAYERS; player++)
    {
        if (is_user_connected(player))
        {
            message_begin(MSG_ONE_UNRELIABLE, msgTeamInfo, _, player);
            write_byte(player);
            write_string("TERRORIST");
            message_end();

            message_begin(MSG_ONE_UNRELIABLE, msgSayText, _, player);
            write_byte(player);
            write_string(finalMessage);
            message_end();
        }
    }
}
