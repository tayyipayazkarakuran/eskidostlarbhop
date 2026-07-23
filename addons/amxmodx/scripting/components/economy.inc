/**
 * @file economy.inc
 * @brief Automatic profiles, credits, market, inventory, and rewards for BMOD.
 *
 * All economy data is tied to SteamID64. Player data is kept locally and
 * mirrored to MySQL through the same queue system used by the timer core.
 */

#if defined _bhop_economy_included
    #endinput
#endif
#define _bhop_economy_included

// ----------------------------------------------------------------------------
// Constants
// ----------------------------------------------------------------------------

#define ECONOMY_DIR             "bhop_timer"
#define ECONOMY_PLAYERS_FILE    "bhop_timer/players.ini"
#define ECONOMY_INVENTORY_FILE  "bhop_timer/inventory.ini"
#define ECONOMY_HISTORY_FILE    "bhop_timer/credits_history.ini"
#define ECONOMY_MARKET_FILE     "bhop_timer/market_items.ini"

#define MAX_CUSTOM_PREFIX_LEN   32
#define MAX_INVENTORY_SLOTS     32
#define MAX_MARKET_ITEMS        64
#define MAX_ITEM_NAME_LEN       64
#define MAX_ITEM_TYPE_LEN       32
#define MAX_REASON_LEN          64
#define MAX_STEAMID64_LEN       80
#define MAX_PLAYER_KEY_LEN      80
#define MAX_PLAYER_NAME_LEN     32
#define MAX_LEADERBOARD_ENTRIES 256

enum _:MarketItem
{
    MI_ID,
    MI_NAME[MAX_ITEM_NAME_LEN + 1],
    MI_PRICE,
    MI_TYPE[MAX_ITEM_TYPE_LEN + 1],
    MI_EFFECT_VALUE,
    MI_ACTIVE
};

#define INV_ITEM_ID     0
#define INV_PURCHASED_AT 1

// ----------------------------------------------------------------------------
// Global Variables
// ----------------------------------------------------------------------------

new g_cvarEconomyEnabled;
new g_cvarHookRewardCredits;
new g_cvarHookRewardSpeed;
new g_cvarMarketEnabled;
new g_cvarIdentitySalt;
new g_cvarSqlPrefix;

new Handle:g_localTuple = Empty_Handle;
new Handle:g_localDb = Empty_Handle;
new g_playerKey[MAX_PLAYERS + 1][MAX_PLAYER_KEY_LEN + 1];
new g_playerIdentityType[MAX_PLAYERS + 1];
new g_playerSessionGeneration[MAX_PLAYERS + 1];

new bool:g_playerDataLoaded[MAX_PLAYERS + 1];
new g_playerCreditsTotal[MAX_PLAYERS + 1];
new g_playerCreditsSpent[MAX_PLAYERS + 1];
new bool:g_playerHookReward[MAX_PLAYERS + 1];
new g_playerCustomPrefix[MAX_PLAYERS + 1][MAX_CUSTOM_PREFIX_LEN + 1];
new g_playerStoredName[MAX_PLAYERS + 1][MAX_PLAYER_NAME_LEN];

new g_playerInventory[MAX_PLAYERS + 1][MAX_INVENTORY_SLOTS][2];
new g_playerInventoryCount[MAX_PLAYERS + 1];

new g_marketItems[MAX_MARKET_ITEMS][MarketItem];
new g_marketItemCount;

new g_economyDataDir[128];

// ----------------------------------------------------------------------------
// Large integer string helpers (for SteamID -> SteamID64 conversion)
// ----------------------------------------------------------------------------

stock LargeAdd(const a[], const b[], output[], len)
{
    new la = strlen(a);
    new lb = strlen(b);
    new maxLen = la > lb ? la : lb;
    new result[40];
    new carry = 0;
    new i = 0;

    while (i < maxLen || carry)
    {
        new da = 0, db = 0;
        new pa = la - 1 - i;
        new pb = lb - 1 - i;

        if (pa >= 0 && a[pa] >= '0' && a[pa] <= '9')
        {
            da = a[pa] - '0';
        }
        if (pb >= 0 && b[pb] >= '0' && b[pb] <= '9')
        {
            db = b[pb] - '0';
        }

        new sum = da + db + carry;
        result[i] = (sum % 10) + '0';
        carry = sum / 10;
        i++;
    }

    new j = 0;
    while (i > 0 && j < len - 1)
    {
        i--;
        output[j++] = result[i];
    }
    output[j] = '^0';
}

stock AuthToSteamId64(const authid[], output[], len)
{
    output[0] = '^0';

    if (strlen(authid) < 8 || authid[0] != 'S')
    {
        copy(output, len, authid);
        return;
    }

    new x = 0, y = 0;

    if (equal(authid, "STEAM_0:", 8) || equal(authid, "STEAM_1:", 8))
    {
        x = authid[8] - '0';
        y = str_to_num(authid[10]);
    }
    else
    {
        copy(output, len, authid);
        return;
    }

    new offset[8];
    num_to_str(y * 2 + x, offset, charsmax(offset));

    LargeAdd("76561197960265728", offset, output, len);
}

enum
{
    IDENTITY_STEAM = 1,
    IDENTITY_REUNION,
    IDENTITY_IP_HASH
};

stock bool:IsUsableAuthId(const authid[])
{
    return authid[0]
        && !equali(authid, "STEAM_ID_PENDING")
        && !equali(authid, "STEAM_ID_LAN")
        && !equali(authid, "VALVE_ID_LAN")
        && !equali(authid, "UNKNOWN");
}

stock bool:IsSteamId64Value(const value[])
{
    if (strlen(value) != 17)
        return false;

    for (new i = 0; value[i]; i++)
    {
        if (value[i] < '0' || value[i] > '9')
            return false;
    }
    return true;
}

stock EconomyBuildPlayerKey(id, output[], len)
{
    new authid[35];
    get_user_authid(id, authid, charsmax(authid));

    if (REU_GetAuthtype(id) == CA_TYPE_STEAM && IsUsableAuthId(authid))
    {
        new steam64[32];
        AuthToSteamId64(authid, steam64, charsmax(steam64));
        if (IsSteamId64Value(steam64))
        {
            formatex(output, len, "steam:%s", steam64);
            g_playerIdentityType[id] = IDENTITY_STEAM;
            copy(g_playerKey[id], MAX_PLAYER_KEY_LEN, output);
            return;
        }
    }

    if (IsUsableAuthId(authid))
    {
        formatex(output, len, "nosteam:%s", authid);
        g_playerIdentityType[id] = IDENTITY_REUNION;
    }
    else
    {
        new ip[48], salt[96], source[160], digest[65];
        get_user_ip(id, ip, charsmax(ip), 1);
        get_pcvar_string(g_cvarIdentitySalt, salt, charsmax(salt));
        if (strlen(salt) < 16)
            copy(salt, charsmax(salt), "bmod-local-fallback-change-me");
        formatex(source, charsmax(source), "%s|%s", salt, ip);
        hash_string(source, Hash_Sha256, digest, charsmax(digest));
        formatex(output, len, "ip:%s", digest);
        g_playerIdentityType[id] = IDENTITY_IP_HASH;
    }

    copy(g_playerKey[id], MAX_PLAYER_KEY_LEN, output);
}

stock EconomyGetPlayerKey(id, output[], len)
{
    if (!g_playerKey[id][0])
        EconomyBuildPlayerKey(id, g_playerKey[id], MAX_PLAYER_KEY_LEN);
    copy(output, len, g_playerKey[id]);
}

stock bool:EconomyLegacyIdentityMatches(id, const legacyKey[])
{
    new playerKey[MAX_PLAYER_KEY_LEN + 1];
    EconomyGetPlayerKey(id, playerKey, charsmax(playerKey));
    if (equal(legacyKey, playerKey))
        return true;
    new unprefixed[MAX_PLAYER_KEY_LEN + 1];
    if (g_playerIdentityType[id] == IDENTITY_STEAM && contain(playerKey, "steam:") == 0)
    {
        for (new i = 6, j = 0; playerKey[i] && j < charsmax(unprefixed); i++, j++)
        {
            unprefixed[j] = playerKey[i];
            unprefixed[j + 1] = '^0';
        }
        return bool:equal(legacyKey, unprefixed);
    }
    if (g_playerIdentityType[id] == IDENTITY_REUNION && contain(playerKey, "nosteam:") == 0)
    {
        for (new i = 8, j = 0; playerKey[i] && j < charsmax(unprefixed); i++, j++)
        {
            unprefixed[j] = playerKey[i];
            unprefixed[j + 1] = '^0';
        }
        return bool:equal(legacyKey, unprefixed);
    }
    return false;
}

// ----------------------------------------------------------------------------
// Economy Initialization
// ----------------------------------------------------------------------------

stock EconomyInit()
{
    g_cvarEconomyEnabled    = register_cvar("bhop_economy_enabled", "1");
    g_cvarHookRewardCredits = register_cvar("bhop_hook_reward_credits", "1000");
    g_cvarHookRewardSpeed   = register_cvar("bhop_hook_reward_speed", "2000.0");
    g_cvarMarketEnabled     = register_cvar("bhop_market_enabled", "1");
    g_cvarIdentitySalt      = register_cvar("bhop_identity_salt", "change-this-private-salt", FCVAR_PROTECTED);
    g_cvarSqlPrefix         = register_cvar("bhop_sql_prefix", "bhop_");

    get_datadir(g_economyDataDir, charsmax(g_economyDataDir));
    add(g_economyDataDir, charsmax(g_economyDataDir), "/bhop_timer");

    if (!dir_exists(g_economyDataDir))
    {
        mkdir(g_economyDataDir);
    }

    LoadMarketItems();
    EconomyLocalInit();
}

stock bool:EconomyLocalExec(const query[])
{
    if (g_localDb == Empty_Handle)
        return false;

    SQL_SetAffinity("sqlite");
    new Handle:statement = SQL_PrepareQuery(g_localDb, query);
    if (statement == Empty_Handle)
    {
        SQL_SetAffinity("mysql");
        return false;
    }

    new bool:ok = SQL_Execute(statement) ? true : false;
    if (!ok)
    {
        new error[192];
        SQL_QueryError(statement, error, charsmax(error));
        log_amx("[LOCALDB] %s", error);
    }
    SQL_FreeHandle(statement);
    SQL_SetAffinity("mysql");
    return ok;
}

stock EconomyLocalInit()
{
    SQL_SetAffinity("sqlite");
    g_localTuple = SQL_MakeDbTuple("", "", "", "bmod_local");
    new errorCode, error[192];
    g_localDb = SQL_Connect(g_localTuple, errorCode, error, charsmax(error));
    SQL_SetAffinity("mysql");

    if (g_localDb == Empty_Handle)
    {
        log_amx("[LOCALDB] SQLite connection failed (%d): %s", errorCode, error);
        return;
    }

    EconomyLocalExec("PRAGMA journal_mode=WAL;");
    EconomyLocalExec("PRAGMA synchronous=NORMAL;");
    EconomyLocalExec("CREATE TABLE IF NOT EXISTS schema_meta (meta_key TEXT PRIMARY KEY,meta_value TEXT NOT NULL);");
    EconomyLocalExec("CREATE TABLE IF NOT EXISTS players (player_key TEXT PRIMARY KEY,identity_type INTEGER NOT NULL,steamid64 TEXT,authid TEXT,name TEXT NOT NULL,total_credits INTEGER NOT NULL DEFAULT 0,spent_credits INTEGER NOT NULL DEFAULT 0,hook_reward INTEGER NOT NULL DEFAULT 0,custom_prefix TEXT,last_seen INTEGER NOT NULL,revision INTEGER NOT NULL DEFAULT 1);");
    EconomyLocalExec("CREATE TABLE IF NOT EXISTS player_aliases (alias_key TEXT PRIMARY KEY,player_key TEXT NOT NULL);");
    EconomyLocalExec("CREATE TABLE IF NOT EXISTS inventory (player_key TEXT NOT NULL,item_id INTEGER NOT NULL,purchased_at INTEGER NOT NULL,PRIMARY KEY(player_key,item_id));");
    EconomyLocalExec("DROP TABLE IF EXISTS player_settings;");
    EconomyLocalExec("CREATE TABLE IF NOT EXISTS player_settings (player_key TEXT NOT NULL,setting_name TEXT NOT NULL,setting_value TEXT,updated_at INTEGER NOT NULL,PRIMARY KEY (player_key,setting_name));");
    EconomyLocalExec("CREATE TABLE IF NOT EXISTS credit_history (event_key TEXT PRIMARY KEY,player_key TEXT NOT NULL,delta INTEGER NOT NULL,total_after INTEGER NOT NULL,reason TEXT NOT NULL,map TEXT NOT NULL,is_wr INTEGER NOT NULL,created_at INTEGER NOT NULL);");
    EconomyLocalExec("CREATE TABLE IF NOT EXISTS sync_outbox (id INTEGER PRIMARY KEY AUTOINCREMENT,event_key TEXT UNIQUE NOT NULL,sql_text TEXT NOT NULL,attempts INTEGER NOT NULL DEFAULT 0,next_attempt INTEGER NOT NULL DEFAULT 0,created_at INTEGER NOT NULL);");
    EconomyLocalExec("INSERT OR REPLACE INTO schema_meta(meta_key,meta_value) VALUES ('schema_version','2');");
}

// ----------------------------------------------------------------------------
// Market Item Registration
// ----------------------------------------------------------------------------

stock EconomyRegisterMarketItem(itemId, const name[], price, const type[], effectValue)
{
    if (g_marketItemCount >= MAX_MARKET_ITEMS)
    {
        log_amx("[ECONOMY] Cannot register market item %d: maximum reached.", itemId);
        return;
    }

    new slot = g_marketItemCount;
    g_marketItems[slot][MI_ID] = itemId;
    copy(g_marketItems[slot][MI_NAME], MAX_ITEM_NAME_LEN, name);
    g_marketItems[slot][MI_PRICE] = price;
    copy(g_marketItems[slot][MI_TYPE], MAX_ITEM_TYPE_LEN, type);
    g_marketItems[slot][MI_EFFECT_VALUE] = effectValue;
    g_marketItems[slot][MI_ACTIVE] = 1;
    g_marketItemCount++;
}

stock EconomyGetMarketItemCount()
{
    return g_marketItemCount;
}

stock EconomyGetMarketItem(slot, item[MarketItem])
{
    if (0 <= slot < g_marketItemCount)
    {
        item = g_marketItems[slot];
        return true;
    }
    return false;
}

stock EconomyFindMarketItem(itemId)
{
    for (new i = 0; i < g_marketItemCount; i++)
    {
        if (g_marketItems[i][MI_ID] == itemId)
        {
            return i;
        }
    }
    return -1;
}

// ----------------------------------------------------------------------------
// Player Data Accessors
// ----------------------------------------------------------------------------

stock EconomyGetCredits(id)
{
    if (!is_user_connected(id))
    {
        return 0;
    }

    return g_playerCreditsTotal[id] - g_playerCreditsSpent[id];
}

stock EconomyGetTotalCredits(id)
{
    if (!is_user_connected(id))
    {
        return 0;
    }

    return g_playerCreditsTotal[id];
}

stock EconomyGetSpentCredits(id)
{
    if (!is_user_connected(id))
    {
        return 0;
    }

    return g_playerCreditsSpent[id];
}

stock bool:EconomyHasHookReward(id)
{
    if (!is_user_connected(id))
    {
        return false;
    }

    return g_playerHookReward[id];
}

stock EconomyGetCustomPrefix(id, output[], len)
{
    output[0] = '^0';
    if (1 <= id <= MAX_PLAYERS && is_user_connected(id))
    {
        copy(output, len, g_playerCustomPrefix[id]);
    }
}

stock bool:EconomyPlayerHasItem(id, itemId)
{
    for (new i = 0; i < g_playerInventoryCount[id]; i++)
    {
        if (g_playerInventory[id][i][INV_ITEM_ID] == itemId)
        {
            return true;
        }
    }
    return false;
}

// ----------------------------------------------------------------------------
// Credit Transactions
// ----------------------------------------------------------------------------

stock EconomyAddCredits(id, amount, const reason[], bool:isWr)
{
    if (!get_pcvar_num(g_cvarEconomyEnabled) || !is_user_connected(id) || amount <= 0)
    {
        return;
    }

    g_playerCreditsTotal[id] += amount;

    EconomyLogHistory(id, amount, g_playerCreditsTotal[id], reason, g_mapName, isWr);
    EconomySavePlayerData(id);
    EconomyQueuePlayerInsert(id);
    EconomyCheckAndApplyRewards(id);

    new display[128];
    formatex(display, charsmax(display), "^x04+%d Credits^x01 (%s). Balance: ^x04%d", amount, reason, EconomyGetCredits(id));
    TimerChat(id, "%s", display);
}

stock bool:EconomySpendCredits(id, amount, const reason[])
{
    if (!get_pcvar_num(g_cvarEconomyEnabled) || !is_user_connected(id) || amount <= 0)
    {
        return false;
    }

    if (EconomyGetCredits(id) < amount)
    {
        TimerChat(id, "You need ^x04%d^x01 more credits.", amount - EconomyGetCredits(id));
        return false;
    }

    g_playerCreditsSpent[id] += amount;

    EconomyLogHistory(id, -amount, EconomyGetCredits(id), reason, g_mapName, false);
    EconomySavePlayerData(id);
    EconomyQueuePlayerInsert(id);

    return true;
}

// ----------------------------------------------------------------------------
// Reward System
// ----------------------------------------------------------------------------

stock EconomyCheckAndApplyRewards(id)
{
    if (!get_pcvar_num(g_cvarEconomyEnabled) || !is_user_connected(id))
    {
        return;
    }

    new required = get_pcvar_num(g_cvarHookRewardCredits);
    if (required < 1)
    {
        required = 1000;
    }

    if (!g_playerHookReward[id] && g_playerCreditsTotal[id] >= required)
    {
        g_playerHookReward[id] = true;
        EconomySavePlayerData(id);
        TimerChat(id, "Congratulations! You earned the ^x04Hook Speed^x01 reward. Your hook speed is now ^x04%d^x01.", floatround(get_pcvar_float(g_cvarHookRewardSpeed)));
    }
}

stock Float:EconomyGetPlayerHookSpeed(id)
{
    if (EconomyHasHookReward(id))
    {
        new Float:speed = get_pcvar_float(g_cvarHookRewardSpeed);
        if (speed < 1.0)
        {
            speed = 2000.0;
        }
        return speed;
    }

    new Float:baseSpeed = get_pcvar_float(g_cvarHookSpeed);
    if (baseSpeed < 1.0)
    {
        baseSpeed = 900.0;
    }
    return baseSpeed;
}

// ----------------------------------------------------------------------------
// Market Purchase
// ----------------------------------------------------------------------------

stock bool:EconomyBuyItem(id, itemId)
{
    if (!get_pcvar_num(g_cvarEconomyEnabled) || !get_pcvar_num(g_cvarMarketEnabled))
    {
        TimerChat(id, "The market is currently disabled.");
        return false;
    }

    if (!is_user_connected(id))
    {
        return false;
    }

    new slot = EconomyFindMarketItem(itemId);
    if (slot < 0)
    {
        TimerChat(id, "That item is not available.");
        return false;
    }

    if (!g_marketItems[slot][MI_ACTIVE])
    {
        TimerChat(id, "That item is not available.");
        return false;
    }

    if (EconomyPlayerHasItem(id, itemId))
    {
        TimerChat(id, "You already own this item.");
        return false;
    }

    if (g_playerInventoryCount[id] >= MAX_INVENTORY_SLOTS)
    {
        TimerChat(id, "Your inventory is full.");
        return false;
    }

    // VIP and Admin get items for free
    new bool:isFree = false;
    new flags = get_user_flags(id);
    if (flags & 512 || flags & 16384)
    {
        isFree = true;
    }

    new price = g_marketItems[slot][MI_PRICE];
    if (!isFree)
    {
        new reason[MAX_REASON_LEN + 1];
        formatex(reason, charsmax(reason), "Purchased %s", g_marketItems[slot][MI_NAME]);

        if (!EconomySpendCredits(id, price, reason))
        {
            return false;
        }
    }
    else
    {
        TimerChat(id, "^x04[MARKET]^x01 VIP/Admin benefit: free purchase!");
    }

    new invSlot = g_playerInventoryCount[id];
    g_playerInventory[id][invSlot][INV_ITEM_ID] = itemId;
    g_playerInventory[id][invSlot][INV_PURCHASED_AT] = get_systime();
    g_playerInventoryCount[id]++;

    EconomyApplyItemEffect(id, itemId);
    EconomySaveInventory(id);
    EconomyQueueInventoryInsert(id, itemId, g_playerInventory[id][invSlot][INV_PURCHASED_AT]);
    EconomyQueuePlayerInsert(id);

    TimerChat(id, "Purchased ^x04%s^x01 for ^x04%d^x01 credits. Balance: ^x04%d", g_marketItems[slot][MI_NAME], isFree ? 0 : price, EconomyGetCredits(id));
    return true;
}

stock EconomyApplyItemEffect(id, itemId)
{
    new slot = EconomyFindMarketItem(itemId);
    if (slot < 0)
    {
        return;
    }

    if (itemId == 1)
    {
        TimerChat(id, "Use ^x04/setprefix <text>^x01 to customize your chat prefix.");
    }
    else if (itemId == 2)
    {
        TimerChat(id, "Use ^x04/setwelcome <text>^x01 or ^x04/joinmessage <text>^x01 to customize your join message.");
    }
    else if (itemId == 3 || (itemId >= 30 && itemId <= 32))
    {
        TimerChat(id, "You purchased a ^x04WR Record Sound^x01. A custom sound will now play when you break a WR!");
    }
    else if (itemId == 40)
    {
        SetPlayerTrail(id, 255, 0, 0);
        TimerChat(id, "Red trail activated! Move to see your trail.");
    }
    else if (itemId == 41)
    {
        SetPlayerTrail(id, 0, 100, 255);
        TimerChat(id, "Blue trail activated! Move to see your trail.");
    }
    else if (itemId == 42)
    {
        SetPlayerTrail(id, 0, 255, 0);
        TimerChat(id, "Green trail activated! Move to see your trail.");
    }
    else if (itemId == 43)
    {
        SetPlayerTrail(id, 255, 255, 0);
        TimerChat(id, "Yellow trail activated! Move to see your trail.");
    }
    else if (itemId == 44)
    {
        SetPlayerTrail(id, 200, 0, 255);
        TimerChat(id, "Purple trail activated! Move to see your trail.");
    }
    else if (itemId >= 4 && itemId <= 7 || itemId == 10 || itemId == 11 || itemId == 12 || itemId == 13 || itemId == 20 || itemId == 21)
    {
        TimerChat(id, "You purchased a ^x04knife skin^x01. Use ^x04/knifes^x01 to select it.");
    }
}

stock EconomySetCustomPrefix(id, const prefix[])
{
    if (!get_pcvar_num(g_cvarEconomyEnabled) || !is_user_connected(id))
    {
        return false;
    }

    // Only players who bought the custom prefix item can set one.
    new prefixItemId = -1;
    for (new i = 0; i < g_marketItemCount; i++)
    {
        if (equal(g_marketItems[i][MI_TYPE], "custom_prefix"))
        {
            prefixItemId = g_marketItems[i][MI_ID];
            break;
        }
    }

    if (prefixItemId < 0 || !EconomyPlayerHasItem(id, prefixItemId))
    {
        TimerChat(id, "You must purchase the ^x04Custom Chat Prefix^x01 item from the market first.");
        return false;
    }

    new cleaned[MAX_CUSTOM_PREFIX_LEN + 1];
    copy(cleaned, MAX_CUSTOM_PREFIX_LEN, prefix);
    trim(cleaned);
    log_amx("[ECONOMY] EconomySetCustomPrefix id=%d raw='%s' cleaned='%s'", id, prefix, cleaned);

    if (!cleaned[0])
    {
        g_playerCustomPrefix[id][0] = '^0';
        TimerChat(id, "Your custom prefix has been cleared.");
    }
    else
    {
        copy(g_playerCustomPrefix[id], MAX_CUSTOM_PREFIX_LEN, cleaned);
        TimerChat(id, "Your custom prefix is now: ^x04[%s]", cleaned);
    }

    EconomySavePlayerData(id);
    EconomyQueuePlayerInsert(id);
    return true;
}

stock EconomyBuildPath(output[], len, const fileName[])
{
    new dataDir[128];
    get_datadir(dataDir, charsmax(dataDir));
    formatex(output, len, "%s/%s", dataDir, fileName);
}

stock EconomySqlTable(const suffix[], output[], len)
{
    new prefix[48];
    get_pcvar_string(g_cvarSqlPrefix, prefix, charsmax(prefix));
    for (new i = 0; prefix[i]; i++)
    {
        if (!((prefix[i] >= 'a' && prefix[i] <= 'z') || (prefix[i] >= 'A' && prefix[i] <= 'Z') || (prefix[i] >= '0' && prefix[i] <= '9') || prefix[i] == '_'))
        {
            copy(prefix, charsmax(prefix), "bhop_");
            break;
        }
    }
    formatex(output, len, "%s%s", prefix, suffix);
}

stock EconomyResetPlayerData(id)
{
    if (!(1 <= id <= MAX_PLAYERS))
    {
        return;
    }

    g_playerDataLoaded[id] = false;
    g_playerCreditsTotal[id] = 0;
    g_playerCreditsSpent[id] = 0;
    g_playerHookReward[id] = false;
    g_playerCustomPrefix[id][0] = '^0';
    g_playerInventoryCount[id] = 0;
    g_playerStoredName[id][0] = '^0';
    g_playerKey[id][0] = '^0';
    g_playerIdentityType[id] = 0;
    g_playerSessionGeneration[id]++;
}

stock EconomyLocalEscape(const input[], output[], len)
{
    if (g_localDb != Empty_Handle)
    {
        SQL_SetAffinity("sqlite");
        SQL_QuoteString(g_localDb, output, len, input);
        SQL_SetAffinity("mysql");
    }
    else
        copy(output, len, input);
}

stock bool:EconomyLocalLoadPlayer(id)
{
    if (g_localDb == Empty_Handle)
        return false;

    new playerKey[MAX_PLAYER_KEY_LEN + 1], keySql[192];
    EconomyGetPlayerKey(id, playerKey, charsmax(playerKey));
    EconomyLocalEscape(playerKey, keySql, charsmax(keySql));

    new query[384];
    formatex(query, charsmax(query), "SELECT name,total_credits,spent_credits,hook_reward,custom_prefix FROM players WHERE player_key='%s' LIMIT 1;", keySql);
    SQL_SetAffinity("sqlite");
    new Handle:statement = SQL_PrepareQuery(g_localDb, query);
    if (statement == Empty_Handle || !SQL_Execute(statement) || !SQL_MoreResults(statement))
    {
        if (statement != Empty_Handle) SQL_FreeHandle(statement);
        SQL_SetAffinity("mysql");
        return false;
    }

    SQL_ReadResult(statement, 0, g_playerStoredName[id], MAX_PLAYER_NAME_LEN);
    g_playerCreditsTotal[id] = SQL_ReadResult(statement, 1);
    g_playerCreditsSpent[id] = SQL_ReadResult(statement, 2);
    g_playerHookReward[id] = SQL_ReadResult(statement, 3) ? true : false;
    SQL_ReadResult(statement, 4, g_playerCustomPrefix[id], MAX_CUSTOM_PREFIX_LEN);
    SQL_FreeHandle(statement);
    SQL_SetAffinity("mysql");
    g_playerDataLoaded[id] = true;
    return true;
}

stock EconomyLocalSavePlayer(id)
{
    if (g_localDb == Empty_Handle || !is_user_connected(id))
        return;

    new playerKey[MAX_PLAYER_KEY_LEN + 1], keySql[192], name[32], nameSql[96];
    new authid[35], authSql[96], steam64[32], steamSql[64], prefixSql[96];
    EconomyGetPlayerKey(id, playerKey, charsmax(playerKey));
    get_user_name(id, name, charsmax(name));
    get_user_authid(id, authid, charsmax(authid));
    steam64[0] = '^0';
    if (g_playerIdentityType[id] == IDENTITY_STEAM)
        AuthToSteamId64(authid, steam64, charsmax(steam64));

    EconomyLocalEscape(playerKey, keySql, charsmax(keySql));
    EconomyLocalEscape(name, nameSql, charsmax(nameSql));
    EconomyLocalEscape(authid, authSql, charsmax(authSql));
    EconomyLocalEscape(steam64, steamSql, charsmax(steamSql));
    EconomyLocalEscape(g_playerCustomPrefix[id], prefixSql, charsmax(prefixSql));

    new query[1024];
    formatex(query, charsmax(query),
        "INSERT INTO players(player_key,identity_type,steamid64,authid,name,total_credits,spent_credits,hook_reward,custom_prefix,last_seen,revision) VALUES('%s',%d,'%s','%s','%s',%d,%d,%d,'%s',%d,1) ON CONFLICT(player_key) DO UPDATE SET identity_type=excluded.identity_type,steamid64=excluded.steamid64,authid=excluded.authid,name=excluded.name,total_credits=excluded.total_credits,spent_credits=excluded.spent_credits,hook_reward=excluded.hook_reward,custom_prefix=excluded.custom_prefix,last_seen=excluded.last_seen,revision=players.revision+1;",
        keySql, g_playerIdentityType[id], steamSql, authSql, nameSql,
        g_playerCreditsTotal[id], g_playerCreditsSpent[id], g_playerHookReward[id] ? 1 : 0,
        prefixSql, get_systime());
    EconomyLocalExec("BEGIN IMMEDIATE;");
    EconomyLocalExec(query);
    EconomyLocalExec("COMMIT;");
}

stock EconomyLocalLoadInventory(id)
{
    if (g_localDb == Empty_Handle)
        return;

    new playerKey[MAX_PLAYER_KEY_LEN + 1], keySql[192], query[320];
    EconomyGetPlayerKey(id, playerKey, charsmax(playerKey));
    EconomyLocalEscape(playerKey, keySql, charsmax(keySql));
    formatex(query, charsmax(query), "SELECT item_id,purchased_at FROM inventory WHERE player_key='%s' ORDER BY purchased_at;", keySql);
    SQL_SetAffinity("sqlite");
    new Handle:statement = SQL_PrepareQuery(g_localDb, query);
    if (statement == Empty_Handle || !SQL_Execute(statement))
    {
        if (statement != Empty_Handle) SQL_FreeHandle(statement);
        SQL_SetAffinity("mysql");
        return;
    }
    while (SQL_MoreResults(statement))
    {
        EconomyAddInventorySlot(id, SQL_ReadResult(statement, 0), SQL_ReadResult(statement, 1));
        SQL_NextRow(statement);
    }
    SQL_FreeHandle(statement);
    SQL_SetAffinity("mysql");
}

stock EconomyLocalSaveInventory(id)
{
    if (g_localDb == Empty_Handle || !is_user_connected(id))
        return;

    new playerKey[MAX_PLAYER_KEY_LEN + 1], keySql[192], query[384];
    EconomyGetPlayerKey(id, playerKey, charsmax(playerKey));
    EconomyLocalEscape(playerKey, keySql, charsmax(keySql));
    EconomyLocalExec("BEGIN IMMEDIATE;");
    formatex(query, charsmax(query), "DELETE FROM inventory WHERE player_key='%s';", keySql);
    EconomyLocalExec(query);
    for (new i = 0; i < g_playerInventoryCount[id]; i++)
    {
        formatex(query, charsmax(query), "INSERT OR REPLACE INTO inventory(player_key,item_id,purchased_at) VALUES('%s',%d,%d);",
            keySql, g_playerInventory[id][i][INV_ITEM_ID], g_playerInventory[id][i][INV_PURCHASED_AT]);
        EconomyLocalExec(query);
    }
    EconomyLocalExec("COMMIT;");
}

stock EconomyLocalQueueSql(const mysqlQuery[])
{
    if (g_localDb == Empty_Handle || !mysqlQuery[0])
        return;

    static eventKey[65], querySql[8192], query[8704];
    hash_string(mysqlQuery, Hash_Sha256, eventKey, charsmax(eventKey));
    EconomyLocalEscape(mysqlQuery, querySql, charsmax(querySql));
    formatex(query, charsmax(query), "INSERT OR IGNORE INTO sync_outbox(event_key,sql_text,created_at) VALUES('%s','%s',%d);", eventKey, querySql, get_systime());
    EconomyLocalExec(query);
}

stock EconomyLocalMarkSqlSynced(const mysqlQuery[])
{
    if (g_localDb == Empty_Handle || !mysqlQuery[0]) return;
    new eventKey[65], query[192];
    hash_string(mysqlQuery, Hash_Sha256, eventKey, charsmax(eventKey));
    formatex(query, charsmax(query), "DELETE FROM sync_outbox WHERE event_key='%s';", eventKey);
    EconomyLocalExec(query);
}

stock EconomyLocalMarkSqlFailed(const mysqlQuery[], retryAt)
{
    if (g_localDb == Empty_Handle || !mysqlQuery[0]) return;
    new eventKey[65], query[256];
    hash_string(mysqlQuery, Hash_Sha256, eventKey, charsmax(eventKey));
    formatex(query, charsmax(query), "UPDATE sync_outbox SET attempts=attempts+1,next_attempt=%d WHERE event_key='%s';", retryAt, eventKey);
    EconomyLocalExec(query);
}

stock EconomyLocalLogHistory(id, delta, totalAfter, const reason[], const mapName[], bool:isWr)
{
    if (g_localDb == Empty_Handle)
        return;
    new playerKey[MAX_PLAYER_KEY_LEN + 1], keySql[192], reasonSql[160], mapSql[160], query[768];
    EconomyGetPlayerKey(id, playerKey, charsmax(playerKey));
    EconomyLocalEscape(playerKey, keySql, charsmax(keySql));
    EconomyLocalEscape(reason, reasonSql, charsmax(reasonSql));
    EconomyLocalEscape(mapName, mapSql, charsmax(mapSql));
    formatex(query, charsmax(query), "INSERT INTO credit_history(player_key,delta,total_after,reason,map,is_wr,created_at) VALUES('%s',%d,%d,'%s','%s',%d,%d);",
        keySql, delta, totalAfter, reasonSql, mapSql, isWr ? 1 : 0, get_systime());
    EconomyLocalExec(query);
}

stock bool:EconomyLocalGetSetting(id, const settingName[], output[], len)
{
    output[0] = '^0';
    if (g_localDb == Empty_Handle) return false;
    new key[MAX_PLAYER_KEY_LEN + 1], keySql[192], nameSql[96], query[384];
    EconomyGetPlayerKey(id, key, charsmax(key));
    EconomyLocalEscape(key, keySql, charsmax(keySql));
    EconomyLocalEscape(settingName, nameSql, charsmax(nameSql));
    formatex(query, charsmax(query), "SELECT setting_value FROM player_settings WHERE player_key='%s' AND setting_name='%s' LIMIT 1;", keySql, nameSql);
    SQL_SetAffinity("sqlite");
    new Handle:statement = SQL_PrepareQuery(g_localDb, query);
    if (statement == Empty_Handle || !SQL_Execute(statement) || !SQL_MoreResults(statement))
    {
        if (statement != Empty_Handle) SQL_FreeHandle(statement);
        SQL_SetAffinity("mysql");
        return false;
    }
    SQL_ReadResult(statement, 0, output, len);
    SQL_FreeHandle(statement);
    SQL_SetAffinity("mysql");
    return true;
}

stock EconomyLocalSetSetting(id, const settingName[], const settingValue[])
{
    if (g_localDb == Empty_Handle || !is_user_connected(id)) return;
    new key[MAX_PLAYER_KEY_LEN + 1], keySql[192], nameSql[96], valueSql[512], query[1024];
    EconomyGetPlayerKey(id, key, charsmax(key));
    EconomyLocalEscape(key, keySql, charsmax(keySql));
    EconomyLocalEscape(settingName, nameSql, charsmax(nameSql));
    EconomyLocalEscape(settingValue, valueSql, charsmax(valueSql));
    formatex(query, charsmax(query), "INSERT INTO player_settings(player_key,setting_name,setting_value,updated_at) VALUES('%s','%s','%s',%d) ON CONFLICT(player_key,setting_name) DO UPDATE SET setting_value=excluded.setting_value,updated_at=excluded.updated_at;",
        keySql, nameSql, valueSql, get_systime());
    EconomyLocalExec(query);
}

stock EconomyLoadPlayerData(id)
{
    if (!is_user_connected(id))
    {
        return;
    }

    EconomyResetPlayerData(id);

    EconomyBuildPlayerKey(id, g_playerKey[id], MAX_PLAYER_KEY_LEN);
    new bool:loadedLocal = EconomyLocalLoadPlayer(id);

    new path[192];
    EconomyBuildPath(path, charsmax(path), ECONOMY_PLAYERS_FILE);

    if (!loadedLocal && file_exists(path))
    {
        new line[512], len;
        new fileLines = file_size(path, 1);

        for (new i = 0; i < fileLines; i++)
        {
            if (!read_file(path, i, line, charsmax(line), len) || len <= 0)
            {
                continue;
            }

            trim(line);
            if (!line[0] || line[0] == ';')
            {
                continue;
            }

            new fileSteam64[MAX_STEAMID64_LEN + 1], storedName[32], legacyFlag[4], totalStr[16], spentStr[16], rewardStr[4], prefix[MAX_CUSTOM_PREFIX_LEN + 1];
            parse(line, fileSteam64, charsmax(fileSteam64), storedName, charsmax(storedName), legacyFlag, charsmax(legacyFlag), totalStr, charsmax(totalStr), spentStr, charsmax(spentStr), rewardStr, charsmax(rewardStr), prefix, charsmax(prefix));

            if (!EconomyLegacyIdentityMatches(id, fileSteam64))
            {
                continue;
            }

            g_playerCreditsTotal[id] = str_to_num(totalStr);
            g_playerCreditsSpent[id] = str_to_num(spentStr);
            g_playerHookReward[id] = (str_to_num(rewardStr) != 0);
            copy(g_playerCustomPrefix[id], MAX_CUSTOM_PREFIX_LEN, prefix);
            copy(g_playerStoredName[id], MAX_PLAYER_NAME_LEN, storedName);
            g_playerDataLoaded[id] = true;
            break;
        }
    }

    EconomyLoadInventory(id);

    if (!g_playerDataLoaded[id])
        g_playerDataLoaded[id] = true;
    EconomyLocalSavePlayer(id);
    EconomyLocalSaveInventory(id);
    EconomyCheckAndApplyRewards(id);
}

stock EconomySavePlayerData(id)
{
    if (!is_user_connected(id))
    {
        return;
    }

    new steam64[MAX_PLAYER_KEY_LEN + 1];
    EconomyGetPlayerKey(id, steam64, charsmax(steam64));

    new playerName[32];
    get_user_name(id, playerName, charsmax(playerName));
    copy(g_playerStoredName[id], MAX_PLAYER_NAME_LEN, playerName);
    EconomyLocalSavePlayer(id);

    new path[192];
    EconomyBuildPath(path, charsmax(path), ECONOMY_PLAYERS_FILE);

    new tempPath[192];
    formatex(tempPath, charsmax(tempPath), "%s.tmp", path);

    new input = fopen(path, "rt");
    new output = fopen(tempPath, "wt");

    new found = false;
    new line[512];

    if (input)
    {
        while (!feof(input))
        {
            if (!fgets(input, line, charsmax(line)))
            {
                continue;
            }

            trim(line);
            if (!line[0])
            {
                continue;
            }

            new fileSteam64[MAX_STEAMID64_LEN + 1], rest[256];
            parse(line, fileSteam64, charsmax(fileSteam64), rest, charsmax(rest));

            if (equal(fileSteam64, steam64))
            {
                fprintf(output, "%s ^"%s^" 1 %d %d %d ^"%s^"^n", steam64, playerName, g_playerCreditsTotal[id], g_playerCreditsSpent[id], g_playerHookReward[id] ? 1 : 0, g_playerCustomPrefix[id]);
                found = true;
            }
            else
            {
                fprintf(output, "%s^n", line);
            }
        }
        fclose(input);
    }

    if (!found)
    {
        fprintf(output, "%s ^"%s^" 1 %d %d %d ^"%s^"^n", steam64, playerName, g_playerCreditsTotal[id], g_playerCreditsSpent[id], g_playerHookReward[id] ? 1 : 0, g_playerCustomPrefix[id]);
    }

    if (output)
    {
        fclose(output);
    }

    delete_file(path);
    rename_file(tempPath, path, 1);

    EconomyQueuePlayerInsert(id);
}

stock EconomyLoadInventory(id)
{
    g_playerInventoryCount[id] = 0;
    EconomyLocalLoadInventory(id);

    new path[192];
    EconomyBuildPath(path, charsmax(path), ECONOMY_INVENTORY_FILE);

    if (g_playerInventoryCount[id] == 0 && file_exists(path))
    {
        new line[256], len;
        new fileLines = file_size(path, 1);

        for (new i = 0; i < fileLines && g_playerInventoryCount[id] < MAX_INVENTORY_SLOTS; i++)
        {
            if (!read_file(path, i, line, charsmax(line), len) || len <= 0)
            {
                continue;
            }

            trim(line);
            if (!line[0] || line[0] == ';')
            {
                continue;
            }

            new fileSteam64[MAX_STEAMID64_LEN + 1], itemIdStr[8], purchasedStr[16];
            parse(line, fileSteam64, charsmax(fileSteam64), itemIdStr, charsmax(itemIdStr), purchasedStr, charsmax(purchasedStr));

            if (!EconomyLegacyIdentityMatches(id, fileSteam64))
            {
                continue;
            }

            EconomyAddInventorySlot(id, str_to_num(itemIdStr), str_to_num(purchasedStr));
        }
    }

}

stock EconomyAddInventorySlot(id, itemId, purchasedAt)
{
    if (itemId <= 0 || g_playerInventoryCount[id] >= MAX_INVENTORY_SLOTS)
    {
        return;
    }

    for (new i = 0; i < g_playerInventoryCount[id]; i++)
    {
        if (g_playerInventory[id][i][INV_ITEM_ID] == itemId)
        {
            return;
        }
    }

    new slot = g_playerInventoryCount[id];
    g_playerInventory[id][slot][INV_ITEM_ID] = itemId;
    g_playerInventory[id][slot][INV_PURCHASED_AT] = purchasedAt;
    g_playerInventoryCount[id]++;
}

stock EconomySaveInventory(id)
{
    if (!is_user_connected(id))
    {
        return;
    }

    new steam64[MAX_PLAYER_KEY_LEN + 1];
    EconomyGetPlayerKey(id, steam64, charsmax(steam64));
    EconomyLocalSaveInventory(id);

    new path[192];
    EconomyBuildPath(path, charsmax(path), ECONOMY_INVENTORY_FILE);

    new tempPath[192];
    formatex(tempPath, charsmax(tempPath), "%s.tmp", path);

    new input = fopen(path, "rt");
    new output = fopen(tempPath, "wt");

    if (input)
    {
        new line[256], len;
        new fileLines = file_size(path, 1);

        for (new i = 0; i < fileLines; i++)
        {
            if (!read_file(path, i, line, charsmax(line), len) || len <= 0)
            {
                continue;
            }

            trim(line);
            if (!line[0])
            {
                continue;
            }

            new fileSteam64[MAX_STEAMID64_LEN + 1];
            parse(line, fileSteam64, charsmax(fileSteam64));

            if (!equal(fileSteam64, steam64))
            {
                fprintf(output, "%s^n", line);
            }
        }
        fclose(input);
    }

    for (new i = 0; i < g_playerInventoryCount[id]; i++)
    {
        fprintf(output, "%s %d %d^n", steam64, g_playerInventory[id][i][INV_ITEM_ID], g_playerInventory[id][i][INV_PURCHASED_AT]);
    }

    if (output)
    {
        fclose(output);
    }

    delete_file(path);
    rename_file(tempPath, path, 1);
}

stock EconomyLogHistory(id, delta, totalAfter, const reason[], const map[], bool:isWr)
{
    if (!is_user_connected(id))
    {
        return;
    }

    new steam64[MAX_PLAYER_KEY_LEN + 1];
    EconomyGetPlayerKey(id, steam64, charsmax(steam64));

    EconomyLocalLogHistory(id, delta, totalAfter, reason, map, isWr);

    new path[192];
    EconomyBuildPath(path, charsmax(path), ECONOMY_HISTORY_FILE);

    new fp = fopen(path, "at");
    if (fp)
    {
        new timestamp = get_systime();
        fprintf(fp, "%s %d %d ^"%s^" ^"%s^" %d %d^n", steam64, delta, totalAfter, reason, map, isWr ? 1 : 0, timestamp);
        fclose(fp);
    }

    EconomyQueueCreditHistory(id, delta, totalAfter, reason, map, isWr);
}

stock LoadMarketItems()
{
    g_marketItemCount = 0;

    new path[192];
    EconomyBuildPath(path, charsmax(path), ECONOMY_MARKET_FILE);

    if (file_exists(path))
    {
        new line[256], len;
        new fileLines = file_size(path, 1);

        for (new i = 0; i < fileLines && g_marketItemCount < MAX_MARKET_ITEMS; i++)
        {
            if (!read_file(path, i, line, charsmax(line), len) || len <= 0)
            {
                continue;
            }

            trim(line);
            if (!line[0] || line[0] == ';')
            {
                continue;
            }

            new itemIdStr[8], priceStr[16], type[MAX_ITEM_TYPE_LEN + 1], effectStr[16], name[MAX_ITEM_NAME_LEN + 1];
            if (parse(line, itemIdStr, charsmax(itemIdStr), priceStr, charsmax(priceStr), type, charsmax(type), effectStr, charsmax(effectStr), name, charsmax(name)) < 5)
            {
                continue;
            }

            EconomyUpsertMarketItem(str_to_num(itemIdStr), name, str_to_num(priceStr), type, str_to_num(effectStr));
        }
    }

    EconomyUpsertMarketItem(1, "Custom Chat Prefix", 1000, "custom_prefix", 1);
    EconomyUpsertMarketItem(2, "Custom Join Message", 500, "join_message", 1);
    EconomyUpsertMarketItem(3, "WR Record Sound", 1000, "wr_sound", 1);
    EconomyUpsertMarketItem(4, "Talon Knife Skin", 2000, "knife_skin", 1);
    EconomyUpsertMarketItem(5, "Bayonet Knife Skin", 2000, "knife_skin", 1);
    EconomyUpsertMarketItem(6, "Karambit Knife Skin", 3000, "knife_skin", 1);
    EconomyUpsertMarketItem(7, "Butterfly Knife Skin", 3500, "knife_skin", 1);
    EconomySaveMarketItems();

    // MySQL is authoritative for market items.
    if (g_dbReady && g_sqlTuple != Empty_Handle)
    {
        EconomyLoadMarketItemsFromDb();
    }
}

stock EconomyUpsertMarketItem(itemId, const name[], price, const type[], effectValue)
{
    if (itemId <= 0)
    {
        return;
    }

    new slot = EconomyFindMarketItem(itemId);
    if (slot < 0)
    {
        if (g_marketItemCount >= MAX_MARKET_ITEMS)
        {
            log_amx("[ECONOMY] Cannot upsert market item %d: maximum reached.", itemId);
            return;
        }
        slot = g_marketItemCount;
        g_marketItemCount++;
    }

    g_marketItems[slot][MI_ID] = itemId;
    copy(g_marketItems[slot][MI_NAME], MAX_ITEM_NAME_LEN, name);
    g_marketItems[slot][MI_PRICE] = price;
    copy(g_marketItems[slot][MI_TYPE], MAX_ITEM_TYPE_LEN, type);
    g_marketItems[slot][MI_EFFECT_VALUE] = effectValue;
    g_marketItems[slot][MI_ACTIVE] = 1;
}

stock EconomyLoadMarketItemsFromDb()
{
    if (g_sqlTuple == Empty_Handle)
    {
        return;
    }

    new table[96], query[192];
    EconomySqlTable("market_items", table, charsmax(table));
    formatex(query, charsmax(query), "SELECT item_id,name,price,item_type,effect_value FROM %s;", table);
    SQL_ThreadQuery(g_sqlTuple, "EconomyDbMarketHandler", query);
}

public EconomyDbMarketHandler(failstate, Handle:query, error[], errnum, data[], size, Float:queueTime)
{
    #pragma unused data, size, queueTime

    if (failstate != TQUERY_SUCCESS)
    {
        log_amx("[ECONOMY] Could not load market items from MySQL (%d): %s", errnum, error);
        return;
    }

    while (SQL_MoreResults(query))
    {
        new itemId, price, effectValue;
        new name[MAX_ITEM_NAME_LEN + 1];
        new type[MAX_ITEM_TYPE_LEN + 1];

        itemId = SQL_ReadResult(query, 0);
        SQL_ReadResult(query, 1, name, charsmax(name));
        price = SQL_ReadResult(query, 2);
        SQL_ReadResult(query, 3, type, charsmax(type));
        effectValue = SQL_ReadResult(query, 4);

        EconomyUpsertMarketItem(itemId, name, price, type, effectValue);
        SQL_NextRow(query);
    }
}

stock EconomySaveMarketItems()
{
    new path[192];
    EconomyBuildPath(path, charsmax(path), ECONOMY_MARKET_FILE);

    new fp = fopen(path, "wt");
    if (!fp)
    {
        return;
    }

    fprintf(fp, "; Market items: item_id price type effect_value name^n");
    for (new i = 0; i < g_marketItemCount; i++)
    {
        fprintf(fp, "%d %d %s %d ^"%s^"^n", g_marketItems[i][MI_ID], g_marketItems[i][MI_PRICE], g_marketItems[i][MI_TYPE], g_marketItems[i][MI_EFFECT_VALUE], g_marketItems[i][MI_NAME]);
    }
    fclose(fp);
}

// ----------------------------------------------------------------------------
// MySQL Queue Integration
// ----------------------------------------------------------------------------

stock EconomyQueuePlayerInsert(id)
{
    if (!is_user_connected(id))
    {
        return;
    }

    new name[32], auth[35], playerKey[MAX_PLAYER_KEY_LEN + 1], steam64[32];
    get_user_name(id, name, charsmax(name));
    get_user_authid(id, auth, charsmax(auth));
    EconomyGetPlayerKey(id, playerKey, charsmax(playerKey));
    steam64[0] = '^0';
    if (g_playerIdentityType[id] == IDENTITY_STEAM)
        AuthToSteamId64(auth, steam64, charsmax(steam64));

    new nameSql[MAX_NAME_SQL], keySql[192], steam64Sql[64], authSql[96], prefixSql[(MAX_CUSTOM_PREFIX_LEN * 2) + 1], table[96];
    MysqlEscape(name, nameSql, charsmax(nameSql));
    MysqlEscape(playerKey, keySql, charsmax(keySql));
    MysqlEscape(steam64, steam64Sql, charsmax(steam64Sql));
    MysqlEscape(auth, authSql, charsmax(authSql));
    MysqlEscape(g_playerCustomPrefix[id], prefixSql, charsmax(prefixSql));
    EconomySqlTable("players", table, charsmax(table));

    new query[1536];
    formatex(query, charsmax(query),
        "INSERT INTO %s (player_key,identity_type,steamid64,authid,name,total_credits,spent_credits,hook_reward,custom_prefix,revision,updated_at) VALUES ('%s',%d,NULLIF('%s',''),'%s','%s',%d,%d,%d,'%s',1,%d) ON DUPLICATE KEY UPDATE identity_type=VALUES(identity_type),steamid64=VALUES(steamid64),authid=VALUES(authid),name=VALUES(name),total_credits=VALUES(total_credits),spent_credits=VALUES(spent_credits),hook_reward=VALUES(hook_reward),custom_prefix=VALUES(custom_prefix),revision=revision+1,updated_at=VALUES(updated_at);",
        table, keySql, g_playerIdentityType[id], steam64Sql, authSql, nameSql, g_playerCreditsTotal[id], g_playerCreditsSpent[id], g_playerHookReward[id] ? 1 : 0, prefixSql, get_systime());
    QueueSql(query);
}

stock EconomyQueueCreditHistory(id, delta, totalAfter, const reason[], const mapName[], bool:isWr)
{
    if (!is_user_connected(id))
    {
        return;
    }

    new steam64[MAX_PLAYER_KEY_LEN + 1];
    EconomyGetPlayerKey(id, steam64, charsmax(steam64));

    new steam64Sql[MAX_STEAMID64_LEN + 16], reasonSql[MAX_REASON_LEN * 2 + 1], mapSql[MAX_MAP_SQL];
    MysqlEscape(steam64, steam64Sql, charsmax(steam64Sql));
    MysqlEscape(reason, reasonSql, charsmax(reasonSql));
    MysqlEscape(mapName, mapSql, charsmax(mapSql));

    new query[1024], table[96], eventKey[65], eventSource[512];
    EconomySqlTable("credit_history", table, charsmax(table));
    formatex(eventSource, charsmax(eventSource), "%s|%d|%d|%s|%s|%d", steam64, delta, totalAfter, reason, mapName, isWr ? 1 : 0);
    hash_string(eventSource, Hash_Sha256, eventKey, charsmax(eventKey));
    formatex(query, charsmax(query),
        "INSERT IGNORE INTO %s (event_key,player_key,delta,total_after,reason,map,is_wr,created_at) VALUES ('%s','%s',%d,%d,'%s','%s',%d,%d);",
        table, eventKey, steam64Sql, delta, totalAfter, reasonSql, mapSql, isWr ? 1 : 0, get_systime());
    QueueSql(query);
}

stock EconomyQueueInventoryInsert(id, itemId, purchasedAt)
{
    if (!is_user_connected(id))
    {
        return;
    }

    new steam64[MAX_PLAYER_KEY_LEN + 1];
    EconomyGetPlayerKey(id, steam64, charsmax(steam64));

    new steam64Sql[MAX_STEAMID64_LEN + 16];
    MysqlEscape(steam64, steam64Sql, charsmax(steam64Sql));

    new query[384], table[96], eventKey[65], eventSource[256];
    EconomySqlTable("inventory", table, charsmax(table));
    formatex(eventSource, charsmax(eventSource), "%s|%d|%d", steam64, itemId, purchasedAt);
    hash_string(eventSource, Hash_Sha256, eventKey, charsmax(eventKey));
    formatex(query, charsmax(query),
        "INSERT INTO %s (event_key,player_key,item_id,purchased_at) VALUES ('%s','%s',%d,%d) ON DUPLICATE KEY UPDATE purchased_at=LEAST(purchased_at,VALUES(purchased_at));",
        table, eventKey, steam64Sql, itemId, purchasedAt);
    QueueSql(query);
}
