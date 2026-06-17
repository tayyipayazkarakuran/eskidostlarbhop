/**
 * @brief neumenu - Advanced Menu System for AMX Mod X
 *
 * A modern, feature rich menu system for AMX Mod X with support for pagination,
 * dynamic callbacks, selection markers and flexible item management.
 *
 * Features:
 * - Per-player menu instances with independent state management
 * - Automatic pagination with configurable items per page
 * - Hybrid callback system (item-specific or menu-wide generic callbacks)
 * - Non-selectable labels and separators for visual organization
 * - Custom selection markers for currently selected items
 * - Configurable selection sounds with auto-prevention for already-selected items
 * - Automatic key management and page navigation (keys 8/9 for Back/Next)
 * - Support for menu reopening with preserved state
 * - Data packing utilities for passing multiple values via item data
 * - Auto-exit option with customizable exit callbacks
 *
 * Version: 1.1
 * Author: PWNED
 */

#if defined _neumenu_included
    #endinput
#endif
#define _neumenu_included

#include <amxmodx>

// =============================================================================
// CONSTANTS
// =============================================================================

// maximum length for menu title
#define MAX_MENU_TITLE 256

// maximum length for callback function names
#define MAX_CALLBACK_NAME 64

// default sound played on item selection
#define DEFAULT_SELECTION_SOUND "weapons/dryfire_pistol.wav"

// pagination constants
#define PAGINATED_ITEMS_PER_PAGE 7      // default items per page (keys 1-7)
#define PAGINATED_KEY_BACK 7            // key 8 (array index 7) for "Back" button
#define PAGINATED_KEY_NEXT 8            // key 9 (array index 8) for "Next" button

// =============================================================================
// ENUMS
// =============================================================================

/**
 * @brief Menu item structure
 *
 * Stores all properties of a single menu item, including text, callback,
 * user data, and state flags.
 *
 * @note This structure is stored in a dynamic array for each menu instance
 * @note Labels have item_is_label=true and no callback
 * @note Selected items can have custom visual markers via menu_selection_marker
 */
enum menu_item_info_t
{
    item_text[MAX_MENU_LENGTH],         // displayed text for this item
    item_callback[MAX_CALLBACK_NAME],   // callback function name (empty = use generic callback)
    item_user_data,                     // custom integer data passed to callback (supports packing via neu_pack_data)
    bool:item_enabled,                  // whether item is selectable (disabled items are grayed out)
    bool:item_reopen,                   // whether menu should reopen after this item is selected
    bool:item_is_label,                 // flag indicating this is a non-selectable label/separator
    bool:item_is_selected               // flag indicating this item is currently selected (visual marker)
};

/**
 * @brief Menu structure
 *
 * Stores all configuration and state for a single menu instance.
 * Each player (MAX_PLAYERS + 1) has their own menu instance stored in g_menu_data.
 *
 * Key Design Notes:
 * - menu_keys bitfield is recalculated on every display to match visible items
 * - Pagination state (menu_current_page) is preserved during reopens
 * - Array handle (menu_items_array) must be destroyed when menu is closed
 * - Generic callback applies to all items without specific callbacks
 */
enum menu_info_t
{
    menu_title[MAX_MENU_TITLE],                 // menu title with color codes
    menu_timeout,                               // menu timeout in seconds (-1 = no timeout)
    menu_keys,                                  // bitfield of enabled keys (recalculated on display)
    menu_generic_callback[MAX_CALLBACK_NAME],   // generic callback for all items (optional)
    bool:menu_use_generic_callback,             // whether generic callback is enabled
    bool:menu_auto_exit,                        // whether to show exit option
    menu_reopen_callback[MAX_CALLBACK_NAME],    // callback to rebuild menu on reopen
    menu_exit_callback[MAX_CALLBACK_NAME],      // callback when menu is exited via key 0

    // pagination
    bool:menu_paginated,                        // whether pagination is enabled
    menu_current_page,                          // current page index (0-based)
    menu_items_per_page,                        // items per page (0 = no limit for non-paginated)
    
    Array:menu_items_array,                     // dynamic array storing menu_item_info_t structures
    menu_selection_marker[8],                   // custom marker for selected items (example: "•", "►")
    menu_selection_sound[64]                    // sound file to play on item selection
};

// =============================================================================
// GLOBAL VARIABLES
// =============================================================================

// per-player menu storage
new g_menu_data[MAX_PLAYERS + 1][menu_info_t];

// =============================================================================
// API FUNCTIONS
// =============================================================================

/**
 * @brief Creates a new menu for a specific player
 *
 * Initializes a menu instance with all configuration options. This function
 * creates a dynamic array to store menu items and registers the menu handler.
 * Any existing menu for this player is destroyed first.
 *
 * @param player_id         Player entity index (1-32) for whom menu is created
 * @param title             Menu title (supports color codes: \y, \r, \d, \w)
 * @param timeout           Menu timeout in seconds (-1 for no timeout)
 * @param auto_exit         If true, adds exit option at the bottom
 * @param paginated         If true, enables pagination with Back/Next buttons
 * @param items_per_page    Items per page when paginated (default: 7)
 * @param generic_callback  Optional: callback function for ALL items (signature: func(id, key, data))
 * @param reopen_callback   Optional: callback to rebuild menu on reopen (signature: func(id))
 * @param exit_callback     Optional: callback when menu exits via key 0 (signature: func(id))
 * @param selection_marker  Optional: custom marker for selected items (example: "•", "►")
 * @param selection_sound   Optional: sound to play on selection (default: weapons/dryfire_pistol.wav)
 *
 * @return                  Menu handle (which is the player_id)
 *
 * @note Generic callback is only used for items without a specific callback
 * @note Reopen callback is required if any item uses item_reopen=true
 * @note Selection sound is not played if item is already selected (item_is_selected=true)
 * @note Pagination uses keys 8 and 9 for Back/Next navigation
 */
stock neu_menu_create(player_id, const title[], timeout = -1, bool:auto_exit = true, bool:paginated = false, items_per_page = PAGINATED_ITEMS_PER_PAGE, const generic_callback[] = "", const reopen_callback[] = "", const exit_callback[] = "", const selection_marker[] = "", const selection_sound[] = "")
{
    // ensure we only register the menucmd once per menu id (prevents stacked callbacks)
    static Array:registered_menu_ids = Invalid_Array;
    if (registered_menu_ids == Invalid_Array)
    {
        registered_menu_ids = ArrayCreate(1);
    }

    new menuid = register_menuid(title);
    new bool:menucmd_registered = false;

    for (new i = 0, count = ArraySize(registered_menu_ids); i < count; i++)
    {
        if (ArrayGetCell(registered_menu_ids, i) == menuid)
        {
            menucmd_registered = true;
            break;
        }
    }

    if (!menucmd_registered)
    {
        register_menucmd(menuid, 1023, "neumenu_handler");
        ArrayPushCell(registered_menu_ids, menuid);
    }

    // clean up existing array if one exists (prevents memory leaks)
    if (g_menu_data[player_id][menu_items_array] != Invalid_Array)
    {
        ArrayDestroy(g_menu_data[player_id][menu_items_array]);
    }

    // create new dynamic array for menu items
    g_menu_data[player_id][menu_items_array] = ArrayCreate(menu_item_info_t);

    // store menu configuration
    copy(g_menu_data[player_id][menu_title], MAX_MENU_TITLE, title);
    g_menu_data[player_id][menu_timeout] = timeout;
    g_menu_data[player_id][menu_keys] = 0;  // will be recalculated on display
    g_menu_data[player_id][menu_auto_exit] = auto_exit;

    // set generic callback if provided
    if (generic_callback[0] != EOS)
    {
        copy(g_menu_data[player_id][menu_generic_callback], MAX_CALLBACK_NAME, generic_callback);
        g_menu_data[player_id][menu_use_generic_callback] = true;
    }
    else
    {
        g_menu_data[player_id][menu_use_generic_callback] = false;
        g_menu_data[player_id][menu_generic_callback][0] = EOS;
    }

    // set reopen callback if provided
    copy(g_menu_data[player_id][menu_reopen_callback], MAX_CALLBACK_NAME, reopen_callback);

    // set exit callback if provided
    copy(g_menu_data[player_id][menu_exit_callback], MAX_CALLBACK_NAME, exit_callback);

    // set selection marker if provided
    copy(g_menu_data[player_id][menu_selection_marker], charsmax(g_menu_data[][menu_selection_marker]), selection_marker);

    // set selection sound if provided, otherwise use default
    if (selection_sound[0] != EOS) {
        copy(g_menu_data[player_id][menu_selection_sound], charsmax(g_menu_data[][menu_selection_sound]), selection_sound);
    }
    else {
        copy(g_menu_data[player_id][menu_selection_sound], charsmax(g_menu_data[][menu_selection_sound]), DEFAULT_SELECTION_SOUND);
    }

    // pagination setup
    g_menu_data[player_id][menu_paginated] = paginated;
    g_menu_data[player_id][menu_current_page] = 0;  // start on first page
    g_menu_data[player_id][menu_items_per_page] = paginated ? items_per_page : 0;  // 0 = no limit for non-paginated

    return player_id;
}

/**
 * @brief Adds a selectable item to the menu
 *
 * Adds a new item to the menu's dynamic array. For non-paginated menus,
 * enforces a maximum of 9 selectable items (keys 1-9). For paginated menus,
 * no limit is enforced (pages are automatically created).
 *
 * @param menu_id      Menu handle (player_id returned from neu_menu_create)
 * @param text         Item display text (supports color codes)
 * @param callback     Callback function name (empty = use menu's generic callback)
 * @param data         Custom integer data passed to callback (use neu_pack_data for multiple values)
 * @param enabled      Whether item is selectable (false = grayed out)
 * @param reopen       Whether menu should reopen after selection (requires reopen_callback)
 * @param selected     Whether item is currently selected (shows selection marker)
 *
 * @return             Item index in menu's array, or -1 on failure
 *
 * @note Callback signature: func(id, data) for specific callbacks
 * @note Generic callback signature: func(id, key, data) when no specific callback provided
 * @note Reopen functionality requires menu to have a reopen_callback configured
 * @note Selection marker only shows if menu has menu_selection_marker set
 */
stock neu_menu_add_item(menu_id, const text[], const callback[] = "", data = 0, bool:enabled = true, bool:reopen = false, bool:selected = false)
{
    // validate array exists
    if (g_menu_data[menu_id][menu_items_array] == Invalid_Array)
    {
        log_error(AMX_ERR_BOUNDS, "Menu array not initialized for player %d", menu_id);
        return -1;
    }

    new menu_item_count = ArraySize(g_menu_data[menu_id][menu_items_array]);

    // for non-paginated menus, enforce 9-item limit for selectable items
    if (!g_menu_data[menu_id][menu_paginated])
    {
        new selectable_item_count = 0;
        new item_data[menu_item_info_t];

        // count existing selectable items
        for (new i = 0; i < menu_item_count; i++)
        {
            ArrayGetArray(g_menu_data[menu_id][menu_items_array], i, item_data);
            if (!item_data[item_is_label])
            {
                selectable_item_count++;
            }
        }

        // limit is 9 because keys 1-9 are used for items (key 0 is reserved for Exit)
        if (selectable_item_count >= 9)
        {
            log_error(AMX_ERR_BOUNDS, "Selectable item limit for non-paginated menu exceeded (9 items).");
            return -1;
        }
    }

    // populate item structure
    new item_data[menu_item_info_t];

    copy(item_data[item_text], MAX_MENU_LENGTH, text);
    copy(item_data[item_callback], MAX_CALLBACK_NAME, callback);
    item_data[item_user_data] = data;
    item_data[item_enabled] = enabled;
    item_data[item_reopen] = reopen;
    item_data[item_is_label] = false;  // this is a regular item, not a label
    item_data[item_is_selected] = selected;

    // add to array
    new item_index = ArrayPushArray(g_menu_data[menu_id][menu_items_array], item_data);
    return item_index;
}

/**
 * @brief Adds a non-selectable label to the menu
 *
 * Labels are text-only lines without numbers or callbacks. They are useful
 * for section headers, descriptions, or visual separators. Labels do not
 * consume key slots and are displayed without item numbers.
 *
 * @param menu_id      Menu handle (player_id)
 * @param text         Label text (supports color codes)
 *
 * @return             Item index in array, or -1 on failure
 *
 * @note Labels are displayed without item numbers or brackets
 * @note Labels in paginated menus appear with their following selectable items
 * @note Use neu_menu_add_separator() for empty lines
 */
stock neu_menu_add_label(menu_id, const text[])
{
    // validate array exists
    if (g_menu_data[menu_id][menu_items_array] == Invalid_Array)
    {
        log_error(AMX_ERR_BOUNDS, "Menu array not initialized for player %d", menu_id);
        return -1;
    }

    // populate label structure
    new item_data[menu_item_info_t];

    copy(item_data[item_text], MAX_MENU_LENGTH, text);
    item_data[item_callback][0] = EOS;
    item_data[item_user_data] = 0;
    item_data[item_enabled] = false;
    item_data[item_reopen] = false;
    item_data[item_is_label] = true;  // mark as label
    item_data[item_is_selected] = false;

    new item_index = ArrayPushArray(g_menu_data[menu_id][menu_items_array], item_data);
    return item_index;
}

/**
 * @brief Adds a visual separator (empty line) to the menu
 *
 * This is a convenience function that adds an empty label for spacing.
 *
 * @param menu_id      Menu handle (player_id)
 *
 * @return             Item index of the separator, or -1 on failure
 */
stock neu_menu_add_separator(menu_id)
{
    return neu_menu_add_label(menu_id, "");
}

/**
 * @brief Displays the menu to a player
 *
 * Renders the menu text with proper formatting, key assignments, and pagination
 * controls if enabled. Recalculates the menu_keys bitfield based on visible
 * items for the current page.
 *
 * Rendering Logic:
 * 1. For paginated menus:
 *    - Count total selectable items to determine page count
 *    - Display items for current page only (labels included if adjacent to page items)
 *    - Show Back/Next buttons on keys 8/9 if multiple pages exist
 *    - Display page indicator in title (example: "Menu (Page 2/5)")
 *
 * 2. For non-paginated menus:
 *    - Display all items sequentially
 *    - Labels appear inline without consuming keys
 *    - No page navigation controls
 *
 * 3. Item Rendering:
 *    - Enabled items: \d[\r1\d]\w Item Text
 *    - Disabled items: \d[1] Item Text
 *    - Selected items: \d[\y•\d]\w \yItem Text\w (if selection_marker set)
 *    - Labels: Text without brackets or numbers
 *
 * @param menu_id      Menu handle (player_id)
 * @param player       Player entity index (should match menu_id)
 *
 * @note Always call this after modifying menu items or page state
 * @note Keys are recalculated on every display call
 * @note Page state (menu_current_page) is preserved across displays
 */
stock neu_menu_display(menu_id, player)
{
    new menu_text[1024];  // buffer for menu text
    new len;

    // validate array exists
    if (g_menu_data[menu_id][menu_items_array] == Invalid_Array)
    {
        log_error(AMX_ERR_BOUNDS, "Menu array not initialized for player %d", menu_id);
        return;
    }

    // always clear and recalculate keys on display
    g_menu_data[menu_id][menu_keys] = 0;
    new display_key_counter = 1;  // counter for visible item numbers (1, 2, 3...)
    new menu_item_count = ArraySize(g_menu_data[menu_id][menu_items_array]);

    if (g_menu_data[menu_id][menu_paginated])
    {
        // =============================================================================
        // PAGINATED MENU DISPLAY
        // =============================================================================

        // step 1: count total selectable items to determine pagination bounds
        new total_selectable_items;
        new item_data[menu_item_info_t];

        for (new i = 0; i < menu_item_count; i++)
        {
            ArrayGetArray(g_menu_data[menu_id][menu_items_array], i, item_data);
            if (!item_data[item_is_label])
            {
                total_selectable_items++;
            }
        }

        new items_per_page = g_menu_data[menu_id][menu_items_per_page];
        new current_page = g_menu_data[menu_id][menu_current_page];

        // calculate total pages based on selectable items
        new total_pages = (total_selectable_items + items_per_page - 1) / items_per_page;
        if (total_pages == 0) total_pages = 1;  // avoid division by zero

        // safety check: reset to first page if current page is out of bounds
        if (current_page >= total_pages)
        {
            current_page = 0;
            g_menu_data[menu_id][menu_current_page] = 0;
        }

        // render title with page indicator (only if multiple pages)
        if (total_pages > 1)
        {
            len = formatex(menu_text[len], charsmax(menu_text) - len, "%s \r(Page %d/%d)^n^n",
                           g_menu_data[menu_id][menu_title], current_page + 1, total_pages);
        }
        else
        {
            len = formatex(menu_text[len], charsmax(menu_text) - len, "%s^n^n",
                           g_menu_data[menu_id][menu_title]);
        }

        // step 2: iterate through all items and display those for the current page
        new selectable_items_to_skip = current_page * items_per_page;
        new selectable_item_cursor = 0;  // tracks how many selectable items we've passed
        new items_shown_on_page = 0;     // tracks how many selectable items displayed on this page

        for (new i = 0; i < menu_item_count; i++)
        {
            // stop if we've displayed all items for this page
            if (items_shown_on_page >= items_per_page)
            {
                break;
            }

            ArrayGetArray(g_menu_data[menu_id][menu_items_array], i, item_data);

            // handle labels: display if they appear before an item on the current page
            if (item_data[item_is_label])
            {
                // if the next selectable item belongs on this page, show the label
                if (selectable_item_cursor >= selectable_items_to_skip)
                {
                    len += formatex(menu_text[len], charsmax(menu_text) - len, "%s^n", item_data[item_text]);
                }
                continue;
            }

            // handle selectable items
            if (selectable_item_cursor >= selectable_items_to_skip)
            {
                new display_key = display_key_counter;
                new item_prefix[16];

                // format item prefix based on state
                if (item_data[item_enabled])
                {
                    // selected items show custom marker instead of number
                    if (item_data[item_is_selected] && g_menu_data[menu_id][menu_selection_marker][0] != EOS)
                    {
                        formatex(item_prefix, charsmax(item_prefix), "\d[\y%s\d]\w", g_menu_data[menu_id][menu_selection_marker]);
                    }
                    else
                    {
                        formatex(item_prefix, charsmax(item_prefix), "\d[\r%d\d]\w", display_key);
                    }
                    g_menu_data[menu_id][menu_keys] |= (1 << (display_key - 1));  // enable key
                }
                else
                {
                    formatex(item_prefix, charsmax(item_prefix), "\d[%d]", display_key);  // disabled (grayed)
                }

                // format item text (selected items are yellow)
                if (item_data[item_is_selected])
                {
                    len += formatex(menu_text[len], charsmax(menu_text) - len, "%s \y%s\w^n",
                                   item_prefix, item_data[item_text]);
                }
                else
                {
                    len += formatex(menu_text[len], charsmax(menu_text) - len, "%s %s^n",
                                   item_prefix, item_data[item_text]);
                }

                display_key_counter++;
                items_shown_on_page++;
            }

            // move to next selectable item
            selectable_item_cursor++;
        }

        // step 3: render navigation buttons (Back/Next) if multiple pages exist
        new bool:has_back = current_page > 0;
        new bool:has_next = (current_page + 1) * items_per_page < total_selectable_items;
        new bool:needs_pagination = total_pages > 1;

        // only show navigation if there are multiple pages
        if (needs_pagination)
        {
            len += formatex(menu_text[len], charsmax(menu_text) - len, "^n");

            // Back button (key 8)
            if (has_back)
            {
                len += formatex(menu_text[len], charsmax(menu_text) - len, "\d<< [\r8\d]\w Back^t");
                g_menu_data[menu_id][menu_keys] |= (1 << PAGINATED_KEY_BACK);
            }
            else {
                len += formatex(menu_text[len], charsmax(menu_text) - len, "\d<< [8] Back^t");
            }

            // Next button (key 9)
            if (has_next)
            {
                len += formatex(menu_text[len], charsmax(menu_text) - len, "\d[\r9\d]\w Next >>");
                g_menu_data[menu_id][menu_keys] |= (1 << PAGINATED_KEY_NEXT);
            }
            else {
                len += formatex(menu_text[len], charsmax(menu_text) - len, "\d[9] Next >>");
            }
        }
    }
    else
    {
        // =============================================================================
        // NON-PAGINATED MENU DISPLAY
        // =============================================================================

        len = formatex(menu_text[len], charsmax(menu_text) - len, "%s^n^n", g_menu_data[menu_id][menu_title]);

        new item_data[menu_item_info_t];
        for (new i = 0; i < menu_item_count; i++)
        {
            ArrayGetArray(g_menu_data[menu_id][menu_items_array], i, item_data);

            // handle labels
            if (item_data[item_is_label])
            {
                len += formatex(menu_text[len], charsmax(menu_text) - len, "%s^n", item_data[item_text]);
                continue;
            }

            // handle selectable items
            new item_prefix[12];
            new display_key = display_key_counter;

            if (item_data[item_enabled])
            {
                if (item_data[item_is_selected] && g_menu_data[menu_id][menu_selection_marker][0] != EOS) {
                    formatex(item_prefix, charsmax(item_prefix), "\y[\r%s\y]\w", g_menu_data[menu_id][menu_selection_marker]);
                }
                else {
                    formatex(item_prefix, charsmax(item_prefix), "\d[\r%d\d]\w", display_key);
                }

                g_menu_data[menu_id][menu_keys] |= (1 << (display_key - 1));
            }
            else {
                formatex(item_prefix, charsmax(item_prefix), "\d[%d]", display_key);
            }

            if (item_data[item_is_selected])
            {
                len += formatex(menu_text[len], charsmax(menu_text) - len, "%s \y%s\w^n",
                               item_prefix, item_data[item_text]);
            }
            else
            {
                len += formatex(menu_text[len], charsmax(menu_text) - len, "%s %s^n",
                               item_prefix, item_data[item_text]);
            }

            display_key_counter++;
        }
    }

    // add auto-exit option at bottom
    if (g_menu_data[menu_id][menu_auto_exit])
    {
        len += formatex(menu_text[len], charsmax(menu_text) - len, "^n^n\d[\r0\d]\w Exit");
        g_menu_data[menu_id][menu_keys] |= MENU_KEY_0;
    }

    // display the rendered menu
    show_menu(player, g_menu_data[menu_id][menu_keys], menu_text, g_menu_data[menu_id][menu_timeout]);
}

/**
 * @brief Internal menu handler for all menu interactions
 *
 * Handles all menu key presses including:
 * - Exit key (0)
 * - Navigation keys (8/9 for Back/Next in paginated menus)
 * - Item selection keys (1-7 or 1-9 depending on pagination)
 *
 * Callback Execution Logic:
 * 1. If item has a specific callback, execute it: callback(id, data)
 * 2. Otherwise, if menu has generic callback, execute it: generic_callback(id, key, data)
 * 3. If item has item_reopen=true, call reopen_callback and redisplay menu
 *
 * @param id           Player entity index
 * @param key          Pressed key index (0-9, where 0 = key 1, 9 = key 0)
 *
 * @return             PLUGIN_HANDLED always
 *
 * @note This function is registered via register_menucmd in neu_menu_create
 * @note Selection sound plays only for items that are not already selected
 * @note Page state is preserved during reopens (menu_current_page)
 */
public neumenu_handler(id, key)
{
    // handle exit key (key 9 = keyboard key 0)
    if (key == 9)
    {
        // call exit callback if configured
        if (g_menu_data[id][menu_exit_callback][0] != EOS)
        {
            callfunc_begin(g_menu_data[id][menu_exit_callback]);
            callfunc_push_int(id);
            callfunc_end();
        }

        return PLUGIN_HANDLED;
    }

    // =============================================================================
    // PAGINATION NAVIGATION
    // =============================================================================

    if (g_menu_data[id][menu_paginated])
    {
        // handle Back button (key 8)
        if (key == PAGINATED_KEY_BACK && g_menu_data[id][menu_current_page] > 0)
        {
            g_menu_data[id][menu_current_page]--;
            neu_menu_display(id, id);
            return PLUGIN_HANDLED;
        }

        // handle Next button (key 9)
        if (key == PAGINATED_KEY_NEXT)
        {
            // count total selectable items
            new total_selectable_items;
            new menu_item_count = ArraySize(g_menu_data[id][menu_items_array]);
            new item_data[menu_item_info_t];

            for (new i = 0; i < menu_item_count; i++)
            {
                ArrayGetArray(g_menu_data[id][menu_items_array], i, item_data);
                if (!item_data[item_is_label]) total_selectable_items++;
            }

            // check if next page exists
            if ((g_menu_data[id][menu_current_page] + 1) * g_menu_data[id][menu_items_per_page] < total_selectable_items)
            {
                g_menu_data[id][menu_current_page]++;
                neu_menu_display(id, id);
                return PLUGIN_HANDLED;
            }
        }
    }

    // =============================================================================
    // FIND THE CORRECT ITEM INDEX FROM THE PRESSED KEY
    // =============================================================================

    new item_index = -1;
    new key_to_find = key + 1;  // convert key index to display number (0->1, 1->2 etc)
    new selectable_item_counter = 0;
    new selectable_items_to_skip = 0;
    new menu_item_count = ArraySize(g_menu_data[id][menu_items_array]);
    new item_data[menu_item_info_t];

    // for paginated menus, skip items from previous pages
    if (g_menu_data[id][menu_paginated])
    {
        selectable_items_to_skip = g_menu_data[id][menu_current_page] * g_menu_data[id][menu_items_per_page];
    }

    // iterate through items to find the one matching the pressed key
    for (new i = 0; i < menu_item_count; i++)
    {
        ArrayGetArray(g_menu_data[id][menu_items_array], i, item_data);

        if (item_data[item_is_label])
            continue;  // skip labels

        if (selectable_items_to_skip > 0)
        {
            selectable_items_to_skip--;
            continue;
        }

        selectable_item_counter++;
        
        if (selectable_item_counter == key_to_find)
        {
            item_index = i;
            break;
        }
    }

    // invalid key press
    if (item_index == -1) {
        return PLUGIN_HANDLED;
    }

    // get the selected item data
    ArrayGetArray(g_menu_data[id][menu_items_array], item_index, item_data);
    if (!item_data[item_enabled]) {
        return PLUGIN_HANDLED;  // item is disabled
    }

    // play selection sound if configured and item is not already selected
    if (g_menu_data[id][menu_selection_sound][0] != EOS && !item_data[item_is_selected]) {
        client_cmd(id, "spk %s", g_menu_data[id][menu_selection_sound]);
    }

    // =============================================================================
    // EXECUTE ITEM CALLBACK (HYBRID SYSTEM)
    // =============================================================================

    // priority 1: item-specific callback
    if (item_data[item_callback][0] != EOS)
    {
        // execute item's specific callback: callback(id, data)
        callfunc_begin(item_data[item_callback]);
        callfunc_push_int(id);
        callfunc_push_int(item_data[item_user_data]);
        callfunc_end();
    }
    // priority 2: menu's generic callback (if no specific callback)
    else if (g_menu_data[id][menu_use_generic_callback])
    {
        new generic_callback[MAX_CALLBACK_NAME];
        copy(generic_callback, charsmax(generic_callback), g_menu_data[id][menu_generic_callback]);

        if (generic_callback[0] != EOS)
        {
            // execute generic callback: generic_callback(id, key, data)
            callfunc_begin(generic_callback);
            callfunc_push_int(id);
            callfunc_push_int(key);  // generic callback receives raw key
            callfunc_push_int(item_data[item_user_data]);
            callfunc_end();
        }
    }

    // =============================================================================
    // HANDLE MENU REOPENING
    // =============================================================================

    if (item_data[item_reopen])
    {
        new reopen_callback[MAX_CALLBACK_NAME];
        copy(reopen_callback, charsmax(reopen_callback), g_menu_data[id][menu_reopen_callback]);

        if (reopen_callback[0] != EOS)
        {
            // preserve current page before reopening
            new current_page_before_reopen = g_menu_data[id][menu_current_page];

            // call reopen callback to rebuild menu: reopen_callback(id)
            callfunc_begin(reopen_callback);
            callfunc_push_int(id);
            callfunc_end();

            // restore page state and redisplay
            g_menu_data[id][menu_current_page] = current_page_before_reopen;
            neu_menu_display(id, id);
        }
    }

    return PLUGIN_HANDLED;
}

// =============================================================================
// HELPER FUNCTIONS
// =============================================================================

/**
 * @brief Helper function to create a simple menu with individual item callbacks
 *
 * Creates a menu where each item has its own callback function. This is a
 * convenience function for quickly creating menus without manual item addition.
 *
 * @param player            Player entity index
 * @param title             Menu title
 * @param items             Array of item text strings
 * @param callbacks         Array of callback function names (matching items array)
 * @param item_count        Number of items to add
 * @param paginated         Whether to enable pagination
 * @param items_per_page    Items per page if paginated
 *
 * @return                  Menu handle (player_id)
 *
 * @note Each callback receives: callback(id, data) where data is the item index
 */
stock neu_create_simple_menu(player, const title[], const items[][], const callbacks[][], item_count, bool:paginated = false, items_per_page = PAGINATED_ITEMS_PER_PAGE)
{
    new menu = neu_menu_create(player, title, -1, true, paginated, items_per_page);

    for (new i = 0; i < item_count; i++) {
        neu_menu_add_item(menu, items[i], callbacks[i]);
    }

    neu_menu_display(menu, player);
    return menu;
}

/**
 * @brief Helper function to create a menu with a single generic callback
 *
 * Creates a menu where all items share the same callback function. The callback
 * receives the item index as data to determine which item was selected.
 *
 * @param player            Player entity index
 * @param title             Menu title
 * @param items             Array of item text strings
 * @param item_count        Number of items to add
 * @param generic_callback  Callback function name for all items
 * @param paginated         Whether to enable pagination
 * @param items_per_page    Items per page if paginated
 *
 * @return                  Menu handle (player_id)
 *
 * @note Generic callback receives: callback(id, key, data)
 * @note Each item's data is set to its index (0, 1, 2, ...)
 */
stock neu_create_generic_menu(player, const title[], const items[][], item_count, const generic_callback[], bool:paginated = false, items_per_page = PAGINATED_ITEMS_PER_PAGE)
{
    new menu = neu_menu_create(player, title, -1, true, paginated, items_per_page, generic_callback);

    for (new i = 0; i < item_count; i++) {
        neu_menu_add_item(menu, items[i], "", i);
    }

    neu_menu_display(menu, player);
    return menu;
}

/**
 * @brief Destroys a menu and frees all associated resources
 *
 * Destroys the menu's dynamic array and clears all menu state for the player.
 * Also closes any currently open menu for the player.
 *
 * @param menu_id      Menu handle (player_id)
 *
 * @note Always call this when finished with a menu to prevent memory leaks
 * @note Safe to call multiple times (checks if array is valid before destroying)
 */
stock neu_menu_destroy(menu_id)
{
    // destroy the dynamic array if it exists
    if (g_menu_data[menu_id][menu_items_array] != Invalid_Array)
    {
        ArrayDestroy(g_menu_data[menu_id][menu_items_array]);
        g_menu_data[menu_id][menu_items_array] = Invalid_Array;
    }

    // clear menu data
    g_menu_data[menu_id][menu_title][0] = EOS;
    g_menu_data[menu_id][menu_keys] = 0;
    g_menu_data[menu_id][menu_use_generic_callback] = false;
    g_menu_data[menu_id][menu_generic_callback][0] = EOS;
    g_menu_data[menu_id][menu_exit_callback][0] = EOS;
    g_menu_data[menu_id][menu_paginated] = false;
    g_menu_data[menu_id][menu_current_page] = 0;
    g_menu_data[menu_id][menu_selection_marker][0] = EOS;
    g_menu_data[menu_id][menu_selection_sound][0] = EOS;

    // close any open menu for the player
    show_menu(menu_id, 0, "^n");
}

// =============================================================================
// DATA PACKING UTILITIES
// =============================================================================

/**
 * @brief Packs up to 4 bytes into a single integer for menu item data
 *
 * Allows storing multiple small values (0-255) in a single integer parameter.
 * Useful for passing multiple IDs or values through the item_user_data field.
 *
 * Bit Layout:
 * - Bits 0-7:   byte0
 * - Bits 8-15:  byte1
 * - Bits 16-23: byte2
 * - Bits 24-31: byte3
 *
 * @param byte0     First byte (bits 0-7)
 * @param byte1     Second byte (bits 8-15)
 * @param byte2     Third byte (bits 16-23)
 * @param byte3     Fourth byte (bits 24-31)
 *
 * @return          Packed integer value
 *
 * @note Each byte parameter should be in range 0-255
 * @note Use neu_unpack_byte() to extract individual bytes
 *
 * Example:
 * ```
 * new data = neu_pack_data(weapon_id, ammo_count, team_id);
 * neu_menu_add_item(menu, "Item", .data = data);
 * ```
 */
stock neu_pack_data(byte0 = 0, byte1 = 0, byte2 = 0, byte3 = 0)
{
    return (byte3 << 24) | (byte2 << 16) | (byte1 << 8) | byte0;
}

/**
 * @brief Unpacks a byte from packed menu item data
 *
 * Extracts a single byte value from an integer packed with neu_pack_data().
 *
 * @param data      Packed integer data (from neu_pack_data)
 * @param index     Byte index to extract (0-3)
 *
 * @return          Extracted byte value (0-255)
 *
 * Example:
 * ```
 * @callback(id, data)
 * {
 *     new weapon = neu_unpack_byte(data, 0);
 *     new ammo = neu_unpack_byte(data, 1);
 *     new team = neu_unpack_byte(data, 2);
 * }
 * ```
 */
stock neu_unpack_byte(data, index)
{
    return (data >> (index * 8)) & 0xFF;
}
