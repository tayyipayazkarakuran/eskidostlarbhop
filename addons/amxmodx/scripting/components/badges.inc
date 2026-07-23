/**
 * @file badges.inc
 * @brief Badge achievement system and chat prefix helpers for BMOD.
 *
 * Badges are permanent achievements tied to total earned credits. They are
 * shown as a colored prefix in chat next to the player's name.
 */

#if defined _bhop_badges_included
    #endinput
#endif
#define _bhop_badges_included

// ----------------------------------------------------------------------------
// Constants
// ----------------------------------------------------------------------------

#define MAX_BADGES 10
#define MAX_BADGE_NAME_LEN 32

new const g_badgeThresholds[MAX_BADGES] =
{
    10,
    50,
    100,
    250,
    500,
    1000,
    2000,
    5000,
    10000,
    20000
};

new const g_badgeNames[MAX_BADGES][] =
{
    "Bronze I",
    "Bronze II",
    "Silver I",
    "Silver II",
    "Gold I",
    "Gold II",
    "Platinum I",
    "Platinum II",
    "Diamond I",
    "Diamond II"
};

// Color codes used for the badge prefix.
// ^x03 uses team color, ^x04 is green.
new const g_badgeColors[MAX_BADGES][] =
{
    "^x01",
    "^x01",
    "^x03",
    "^x03",
    "^x04",
    "^x04",
    "^x04",
    "^x04",
    "^x04",
    "^x04"
};

// ----------------------------------------------------------------------------
// Badge Helpers
// ----------------------------------------------------------------------------

stock BadgeGetHighestForCredits(credits)
{
    new highest = -1;
    for (new i = 0; i < MAX_BADGES; i++)
    {
        if (credits >= g_badgeThresholds[i])
        {
            highest = i;
        }
    }
    return highest;
}

stock BadgeGetHighestForPlayer(id)
{
    if (!is_user_connected(id))
    {
        return -1;
    }

    return BadgeGetHighestForCredits(EconomyGetTotalCredits(id));
}

stock BadgeGetName(badgeIndex, output[], len)
{
    output[0] = '^0';
    if (0 <= badgeIndex < MAX_BADGES)
    {
        copy(output, len, g_badgeNames[badgeIndex]);
    }
}

stock BadgeGetThreshold(badgeIndex)
{
    if (0 <= badgeIndex < MAX_BADGES)
    {
        return g_badgeThresholds[badgeIndex];
    }
    return 0;
}

stock BadgeGetPrefixForPlayer(id, output[], len)
{
    output[0] = '^0';

    if (!is_user_connected(id))
    {
        return;
    }

    new badge = BadgeGetHighestForPlayer(id);
    if (badge < 0)
    {
        return;
    }

    formatex(output, len, "%s[%s] ", g_badgeColors[badge], g_badgeNames[badge]);
}

stock BadgeFormatChatPrefix(id, const wrPrefix[], output[], len)
{
    output[0] = '^0';

    new badgePrefix[64];
    BadgeGetPrefixForPlayer(id, badgePrefix, charsmax(badgePrefix));

    if (wrPrefix[0])
    {
        formatex(output, len, "%s%s", badgePrefix, wrPrefix);
    }
    else
    {
        copy(output, len, badgePrefix);
    }
}

stock BadgeAnnounceEarned(id, badgeIndex)
{
    if (!is_user_connected(id) || badgeIndex < 0 || badgeIndex >= MAX_BADGES)
    {
        return;
    }

    new name[32];
    get_user_name(id, name, charsmax(name));

    // Forward used from bhop_timer.sma
    TimerChat(0, "^x04%s^x01 earned the ^x04%s^x01 badge! (^x04%d^x01 total credits)", name, g_badgeNames[badgeIndex], g_badgeThresholds[badgeIndex]);
}

stock BadgeCheckProgression(id, previousCredits, newCredits)
{
    if (!is_user_connected(id))
    {
        return;
    }

    new oldBadge = BadgeGetHighestForCredits(previousCredits);
    new newBadge = BadgeGetHighestForCredits(newCredits);

    if (newBadge > oldBadge)
    {
        BadgeAnnounceEarned(id, newBadge);
    }
}
