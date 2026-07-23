/**
 * @file editor.inc
 * @brief Provides the in-game zone editor with menu controls and anchor manipulation.
 *
 * Handles zone creation, resizing, vertex editing, and expand/shrink operations.
 */

#if defined _editor_included
    #endinput
#endif
#define _editor_included

#include <amxmisc>
#include <neumenu>

#define TASK_ZONE_MENU_UPDATE 28100
#define ZONE_MENU_UPDATE_INTERVAL 0.2

// ============================================================================
// MENU SYSTEM
// ============================================================================

/**
 * @brief Refreshes the zone editor menu for a player.
 *
 * @param[in] player_id Player index.
 */
stock refresh_menu(player_id)
{
    show_zone_menu(player_id);
}

/**
 * @brief Console command handler for opening the zone editor.
 *
 * @param[in] player_id Player index.
 * @param[in] level     Required admin access level.
 * @param[in] cid       Command ID.
 * @return              PLUGIN_HANDLED on success.
 */
public command_zone(player_id, level, cid)
{
    #pragma unused level, cid

    if(!sr_has_zone_access(player_id))
    {
        TimerChat(player_id, "You do not have access to the zone editor.");
        return PLUGIN_HANDLED;
    }

    show_zone_menu(player_id);
    return PLUGIN_HANDLED;
}

/**
 * @brief Displays the main zone editor menu.
 *
 * Activates editor mode, auto-selects zones based on player aim,
 * and builds a dynamic menu with context-sensitive options.
 *
 * @param[in] player_id Player index.
 */
public show_zone_menu(player_id)
{
    // ensure editor mode visuals are active
    zone_editor_mode(true);

    // auto-select zone based on where player is looking
    if (get_zones_count() > 0) {
        select_zone_by_look(player_id);
    }

    // mark player as being in the menu
    g_player_editor[player_id][m_in_menu] = true;
    ensure_menu_update_task();

    new bool:b_zone_selected = (g_player_editor[player_id][m_last_zone] != -1 && get_zones_count() > 0);
    new bool:b_aiming_at_zone = is_player_aiming_at_zone(player_id);

    // initialize menu state tracking
    g_player_editor[player_id][m_last_aiming_state] = b_aiming_at_zone;
    g_player_editor[player_id][m_last_menu_hash] = calculate_menu_hash(player_id);

    new title[128];
    formatex(title, charsmax(title), "\ySpeedrun: Zones^n\dCreate and manage map zones");

    new menu = neu_menu_create(
        .player_id = player_id,
        .title = title,
        .auto_exit = true,
        .reopen_callback = "show_zone_menu",
        .exit_callback = "handle_zone_menu_exit"
    );

    // zone creation
    neu_menu_add_item(menu, "\wCreate Zone", .callback = "@zone_create", .reopen = true);

    // zone removal
    neu_menu_add_item(menu, fmt("%sRemove Zone", b_zone_selected ? "\w" : "\d"),
        .callback = "@zone_remove", .enabled = b_zone_selected, .reopen = true);

    neu_menu_add_item(menu, "\wSave Zones", .callback = "@zone_save", .reopen = true);
    neu_menu_add_item(menu, "\wReload Zones", .callback = "@zone_reload", .reopen = true);

    neu_menu_add_separator(menu);

    // zone function info and change
    new zone_func_text[64];
    new type_idx = g_player_editor[player_id][m_selected_type];
    if (type_idx == -1)
        formatex(zone_func_text, charsmax(zone_func_text), "Zone Type: \rNo function");
    else
        formatex(zone_func_text, charsmax(zone_func_text), "Zone Type: \r%s", g_zone_types[type_idx][m_type_class]);
    neu_menu_add_item(menu, zone_func_text, .callback = "@zone_change_function", .reopen = true);

    // description as a label (non-selectable)
    new description_text[128];
    if (type_idx == -1)
        formatex(description_text, charsmax(description_text), "\yDescription: \dDefault Type");
    else
        formatex(description_text, charsmax(description_text), "\yDescription: \d%s", g_zone_types[type_idx][m_type_description]);
    neu_menu_add_label(menu, description_text);

    neu_menu_add_separator(menu);

    // navigation
    neu_menu_add_item(menu, fmt("%sGo to Selected Zone", b_zone_selected ? "\w" : "\d"),
        .callback = "@zone_goto", .enabled = b_zone_selected);

    // noclip toggle
    new noclip_text[32];
    formatex(noclip_text, charsmax(noclip_text), "No Clip: %s",
        (get_entvar(player_id, var_movetype) == MOVETYPE_NOCLIP) ? "\yEnabled" : "\rDisabled");
    neu_menu_add_item(menu, noclip_text, .callback = "@zone_toggle_noclip", .reopen = true);

    neu_menu_add_separator(menu);

    // 2-point corner marking mode
    new corner_mode = g_player_editor[player_id][m_corner_mode];
    new corner_a_set = g_player_editor[player_id][m_corner_a_set];
    new corner_text[64];
    formatex(corner_text, charsmax(corner_text), "2-Point Mode: %s",
        corner_mode ? "\yEnabled" : "\rDisabled");
    neu_menu_add_item(menu, corner_text, .callback = "@zone_corner_mode", .reopen = true);

    if (corner_mode)
    {
        if (corner_a_set)
        {
            neu_menu_add_item(menu, "\wMark Corner B (here) \r→ \yCreate Zone",
                .callback = "@zone_mark_corner", .reopen = false);
        }
        else
        {
            neu_menu_add_item(menu, "\wMark Corner A (here)",
                .callback = "@zone_mark_corner", .reopen = true);
        }
    }

    neu_menu_add_separator(menu);

    // zone editing
    neu_menu_add_item(menu, fmt("%sExpand Aimed Wall (+1)", b_aiming_at_zone ? "\w" : "\d"),
        .callback = "@zone_expand", .enabled = b_aiming_at_zone, .reopen = true);

    neu_menu_add_item(menu, fmt("%sShrink Aimed Wall (-1)", b_aiming_at_zone ? "\w" : "\d"),
        .callback = "@zone_shrink", .enabled = b_aiming_at_zone, .reopen = true);

    neu_menu_add_separator(menu);

    // show zone info if selected
    if (b_zone_selected) {
        new zone_index = g_player_editor[player_id][m_last_zone];
        new bool:is_poly = is_polygon_zone(zone_index);
        new vertex_count = is_poly ? get_vertex_count(zone_index) : 4;
        
        new info_text[64];
        formatex(info_text, charsmax(info_text), "\d《i》 type: \d%s (%d corners)", 
            is_poly ? "Polygon" : "Box", vertex_count);
        neu_menu_add_label(menu, info_text);
    }
    
    // polygon editing hints
    neu_menu_add_label(menu, "\d《i》 to add new corner, grab one and hold +use or +reload");

    neu_menu_display(menu, player_id);
}

/**
 * @brief Menu callback: Creates a new zone at the player's position.
 *
 * @param[in] player_id Player index.
 */
@zone_create(player_id)
{
    new Float:f_origin[3];
    get_entvar(player_id, var_origin, f_origin);
    new type_idx = g_player_editor[player_id][m_selected_type];
    new sz_class[ZONE_MAX_CLASSNAME_LENGTH];
    if (type_idx == -1)
        copy(sz_class, charsmax(sz_class), ZONE_DEFAULT_CLASSNAME);
    else
        copy(sz_class, charsmax(sz_class), g_zone_types[type_idx][m_type_class]);
    new zone_index = create_zone(sz_class, "", f_origin, _, _, player_id);
    create_zone_anchors(zone_index);
}

/**
 * @brief Menu callback: Removes the currently selected zone.
 *
 * @param[in] player_id Player index.
 */
@zone_remove(player_id)
{
    new bool:b_zone_selected = (g_player_editor[player_id][m_last_zone] != -1 && get_zones_count() > 0);
    if (!b_zone_selected)
        return;

    new zoneIndex = g_player_editor[player_id][m_last_zone];
    new bool:wasStartOrFinish = false;

    // Check if removing a start/finish zone to update timer cache
    new ent = get_zone_entity(zoneIndex);
    if (is_valid_ent(ent))
    {
        new szClass[32];
        get_entvar(ent, var_netname, szClass, charsmax(szClass));
        if (equal(szClass, "zone_start") || equal(szClass, "zone_finish"))
            wasStartOrFinish = true;
    }

    remove_zone(zoneIndex, player_id);

    // Persist the deletion to disk
    save_zone();
    save_legacy_zone_mirror();

    // Update timer zone caches
    if (wasStartOrFinish)
    {
        RefreshZoneCaches();
    }
}

@zone_save(player_id)
{
    save_zone();
    save_legacy_zone_mirror();
    RefreshZoneCaches();
    SaveZonesFile();
    TimerChat(player_id, "Polygon zones ^x04saved^x01.");
}

@zone_reload(player_id)
{
    clear_zones();
    load_zone();
    g_player_editor[player_id][m_last_zone] = -1;
    RefreshZoneCaches();
    TimerChat(player_id, "Polygon zones ^x04reloaded^x01.");
}

/**
 * @brief Menu callback: Cycles through available zone types.
 *
 * Updates the selected zone's class name and fires appropriate callbacks.
 *
 * @param[in] player_id Player index.
 */
@zone_change_function(player_id)
{
    if(g_zone_types_count > 0)
    {
        g_player_editor[player_id][m_selected_type]++;

        if(g_player_editor[player_id][m_selected_type] >= g_zone_types_count)
            g_player_editor[player_id][m_selected_type] = -1;

        new bool:b_zone_selected = (g_player_editor[player_id][m_last_zone] != -1 && get_zones_count() > 0);
        if(b_zone_selected)
        {
            new ent = get_zone_entity(g_player_editor[player_id][m_last_zone]);
            if(is_valid_ent(ent))
            {
                new i_ret;
                new sz_class[32];
                get_entvar(ent, var_netname, sz_class, charsmax(sz_class));
                fire_type_callback(sz_class, CB_DELETE, ent);
                ExecuteForward(g_fw_on_delete, i_ret, ent, sz_class);

                new type_idx = g_player_editor[player_id][m_selected_type];
                if (type_idx == -1)
                    set_entvar(ent, var_netname, ZONE_DEFAULT_CLASSNAME);
                else
                    set_entvar(ent, var_netname, g_zone_types[type_idx][m_type_class]);

                get_entvar(ent, var_netname, sz_class, charsmax(sz_class));
                fire_type_callback(sz_class, CB_CREATE, ent);
                ExecuteForward(g_fw_on_create, i_ret, ent, sz_class);
            }
            else
            {
                g_player_editor[player_id][m_last_zone] = -1;
                TimerChat(player_id, "Selected zone is no longer valid.");
            }
        }
    }
}

/**
 * @brief Menu callback: Teleports the player to the selected zone's origin.
 *
 * @param[in] player_id Player index.
 */
@zone_goto(player_id)
{
    new bool:b_zone_selected = (g_player_editor[player_id][m_last_zone] != -1 && get_zones_count() > 0);
    if(b_zone_selected)
    {
        new ent = get_zone_entity(g_player_editor[player_id][m_last_zone]);
        if(is_valid_ent(ent))
        {
            new Float:f_origin[3];
            get_entvar(ent, var_origin, f_origin);
            set_entvar(player_id, var_origin, f_origin);
        }
        else
        {
            g_player_editor[player_id][m_last_zone] = -1;
            TimerChat(player_id, "Selected zone is no longer valid.");
        }
    }
}

/**
 * @brief Menu callback: Toggles noclip mode for the player.
 *
 * @param[in] player_id Player index.
 */
@zone_toggle_noclip(player_id)
{
    set_entvar(player_id, var_movetype, (get_entvar(player_id, var_movetype) == MOVETYPE_NOCLIP) ? MOVETYPE_WALK : MOVETYPE_NOCLIP);
}

/**
 * @brief Menu callback: Expands the aimed zone face by EXPAND_INCREMENT.
 *
 * @param[in] player_id Player index.
 */
@zone_expand(player_id)
{
    expand_zone(player_id, EXPAND_INCREMENT, false);
}

/**
 * @brief Menu callback: Shrinks the aimed zone face by EXPAND_INCREMENT.
 *
 * @param[in] player_id Player index.
 */
@zone_shrink(player_id)
{
    expand_zone(player_id, EXPAND_INCREMENT, true);
}

/**
 * @brief Callback when player exits the zone editor menu.
 *
 * Disables editor mode and resets player editor state.
 *
 * @param[in] player_id Player index.
 */
public handle_zone_menu_exit(player_id)
{
    zone_editor_mode(false);
    g_player_editor[player_id][m_in_menu] = false;
    g_player_editor[player_id][m_last_aiming_state] = false;
    g_player_editor[player_id][m_last_menu_hash] = 0;
    g_player_editor[player_id][m_corner_mode] = false;
    g_player_editor[player_id][m_corner_a_set] = false;

    if (!any_editor_menu_open())
    {
        remove_task(TASK_ZONE_MENU_UPDATE);
    }
}

/**
 * @brief Periodic task to check for menu state changes.
 *
 * Automatically refreshes menus when player aim state or context changes.
 */
public task_check_menu_updates()
{
    if (!any_editor_menu_open())
    {
        remove_task(TASK_ZONE_MENU_UPDATE);
        return;
    }

    static players[MAX_PLAYERS], player_count;
    get_players(players, player_count, "ch");

    for (new i = 0; i < player_count; i++) {
        new player_id = players[i];

        if (!g_player_editor[player_id][m_in_menu]) continue;

        new bool:current_aiming = is_player_aiming_at_zone(player_id);
        new current_hash = calculate_menu_hash(player_id);

        if (current_aiming != g_player_editor[player_id][m_last_aiming_state] || current_hash != g_player_editor[player_id][m_last_menu_hash]) {
            g_player_editor[player_id][m_last_aiming_state] = current_aiming;
            g_player_editor[player_id][m_last_menu_hash] = current_hash;
            show_zone_menu(player_id);
        }
    }

    ensure_menu_update_task();
}

stock ensure_menu_update_task()
{
    if (!task_exists(TASK_ZONE_MENU_UPDATE))
    {
        set_task(ZONE_MENU_UPDATE_INTERVAL, "task_check_menu_updates", TASK_ZONE_MENU_UPDATE);
    }
}

stock bool:any_editor_menu_open()
{
    for (new player_id = 1; player_id <= MAX_PLAYERS; player_id++)
    {
        if (g_player_editor[player_id][m_in_menu])
        {
            return true;
        }
    }

    return false;
}

/**
 * @brief Calculates a hash representing current menu state.
 *
 * Used to detect when the menu needs refreshing due to state changes.
 *
 * @param[in] player_id Player index.
 * @return              Hash value representing current editor state.
 */
stock calculate_menu_hash(player_id)
{
    new hash = 0;
    hash += (g_player_editor[player_id][m_last_zone] != -1 && get_zones_count() > 0) ? 100 : 0;
    hash += is_player_aiming_at_zone(player_id) ? 10 : 0;
    hash += (get_entvar(player_id, var_movetype) == MOVETYPE_NOCLIP) ? 1 : 0;
    hash += g_player_editor[player_id][m_selected_type] * 1000;
    hash += g_player_editor[player_id][m_corner_mode] ? 10000 : 0;
    hash += g_player_editor[player_id][m_corner_a_set] ? 20000 : 0;
    return hash;
}

/**
 * @brief Console command handler for undo functionality.
 *
 * Reverts the last zone modification when player is crouched in editor mode.
 *
 * @param[in] player_id Player index.
 * @param[in] level     Required admin access level.
 * @param[in] cid       Command ID.
 * @return              PLUGIN_CONTINUE or PLUGIN_HANDLED.
 */
public cmd_undo(player_id, level, cid)
{
    #pragma unused level, cid

    if(!sr_has_zone_access(player_id))
        return PLUGIN_HANDLED;

    if(!g_editor_mode_active || g_player_editor[player_id][m_last_zone] == -1)
        return PLUGIN_CONTINUE;
        
    zone_history_pop(g_player_editor[player_id][m_last_zone]);
    client_cmd(player_id, "spk buttons/latchlocked2.wav");
        
    return PLUGIN_HANDLED;
}

// ============================================================================
// ZONE EDITOR MODE
// ============================================================================

/**
 * @brief Toggles zone editor mode on or off.
 *
 * When enabled, creates visual anchors for all zones.
 * When disabled, removes all anchors.
 *
 * @param[in] status true to enable editor mode, false to disable.
 */
stock zone_editor_mode(bool:status = true)
{
    if(status)
    {
        if(g_editor_mode_active) 
            return;
        
        new zone_count = get_zones_count();
        for(new i = 0; i < zone_count; i++)
            create_zone_anchors(i);
    }
    else
    {
        if(!g_editor_mode_active)
            return;

        new zone_count = get_zones_count();
        for(new i = 0; i < zone_count; i++)
            remove_zone_anchors(i);
    }

    g_editor_mode_active = status;
}

// ============================================================================
// ZONE CREATION
// ============================================================================

/**
 * @brief Creates a new zone entity at the specified position.
 *
 * @param[in] sz_class   Zone class name (type identifier).
 * @param[in] sz_id      Unique zone ID (auto-generated if empty).
 * @param[in] f_origin   World position for the zone center.
 * @param[in] f_mins     Relative minimum bounds (default: DEFAULT_MINSIZE).
 * @param[in] f_maxs     Relative maximum bounds (default: DEFAULT_MAXSIZE).
 * @param[in] editor     Player ID who created the zone (0 if loaded from file).
 * @param[in] as_polygon If true, creates a polygon zone; otherwise creates legacy AABB.
 * @return               Zone index in the zones array.
 */
stock create_zone(const sz_class[], const sz_id[], const Float:f_origin[3], const Float:f_mins[3] = DEFAULT_MINSIZE, const Float:f_maxs[3] = DEFAULT_MAXSIZE, editor = 0, bool:as_polygon = true)
{
    new ent = create_entity("info_target");

    entity_set_string(ent, EV_SZ_classname, ZONE_DEFAULT_CLASSNAME);
    set_entvar(ent, var_netname, sz_class);

    new sz_actual_id[32];
    if(sz_id[0] == '^0')
    {
        formatex(sz_actual_id, 31, "ZONE#%d", g_zone_unique_id);
        set_entvar(ent, var_message, sz_actual_id);
    }
    else
        set_entvar(ent, var_message, sz_id);

    g_zone_unique_id++;

    DispatchSpawn(ent);
    entity_set_model(ent, g_zone_model);

    set_entvar(ent, var_effects, EF_NODRAW);
    set_entvar(ent, var_solid, SOLID_TRIGGER);
    set_entvar(ent, var_movetype, MOVETYPE_NONE);
    set_entvar(ent, var_enemy, 1);
    set_entvar(ent, var_nextthink, get_gametime() + 0.1);

    // set initial position and size
    entity_set_origin(ent, f_origin);
    entity_set_size(ent, f_mins, f_maxs);

    new zone_index;
    
    if (as_polygon) {
        // create polygon zone with 4 vertices (rectangle)
        new Array:vertices = ArrayCreate(vertex_data_t);
        
        new Float:abs_min[3], Float:abs_max[3];
        xs_vec_add(f_origin, f_mins, abs_min);
        xs_vec_add(f_origin, f_maxs, abs_max);
        
        new vertex_data[vertex_data_t];
        
        // bottom-left
        vertex_data[vd_x] = abs_min[0];
        vertex_data[vd_y] = abs_min[1];
        vertex_data[vd_z] = abs_min[2];
        ArrayPushArray(vertices, vertex_data);
        
        // bottom-right
        vertex_data[vd_x] = abs_max[0];
        vertex_data[vd_y] = abs_min[1];
        vertex_data[vd_z] = abs_min[2];
        ArrayPushArray(vertices, vertex_data);
        
        // top-right
        vertex_data[vd_x] = abs_max[0];
        vertex_data[vd_y] = abs_max[1];
        vertex_data[vd_z] = abs_min[2];
        ArrayPushArray(vertices, vertex_data);
        
        // top-left
        vertex_data[vd_x] = abs_min[0];
        vertex_data[vd_y] = abs_max[1];
        vertex_data[vd_z] = abs_min[2];
        ArrayPushArray(vertices, vertex_data);
        
        zone_index = add_zone(ent, editor, vertices, abs_max[2]);
    } else {
        // legacy AABB zone
        zone_index = add_zone(ent, editor);
    }

    // push initial state
    zone_history_push(zone_index);

    new i_ret;
    fire_type_callback(sz_class, CB_CREATE, ent);
    ExecuteForward(g_fw_on_create, i_ret, ent, sz_class);

    return zone_index;
}

// ============================================================================
// ANCHOR SYSTEM
// ============================================================================

/**
 * @brief Creates visual anchor entities for a zone.
 *
 * For polygon zones, creates vertex anchors and a height anchor.
 * For legacy AABB zones, creates 8 corner anchors.
 *
 * @param[in] zone_index Index of the zone in the zones array.
 */
stock create_zone_anchors(zone_index)
{
    if (zone_index < 0 || zone_index >= get_zones_count())
        return;

    new zone_ent = get_zone_entity(zone_index);
    if (!is_valid_ent(zone_ent))
        return;
    
    if (is_polygon_zone(zone_index)) {
        // create anchors for each polygon vertex
        new vertex_count = get_vertex_count(zone_index);
        new Float:vertex[3];

        for (new i = 0; i < vertex_count; i++) {
            get_vertex(zone_index, i, vertex);
            create_polygon_anchor(zone_ent, i, vertex[0], vertex[1], vertex[2]);
        }

        // create height anchor at center top
        new Float:mins[3], Float:maxs[3];
        calculate_polygon_bounds(zone_index, mins, maxs);

        new Float:center_x = (mins[0] + maxs[0]) / 2.0;
        new Float:center_y = (mins[1] + maxs[1]) / 2.0;
        new Float:top_z = get_zone_height(zone_index);

        create_height_anchor(zone_ent, center_x, center_y, top_z);
    } else {
        // legacy AABB anchors
        new Float:f_mins[3];
        get_entvar(zone_ent, var_absmin, f_mins);
        new Float:f_maxs[3];
        get_entvar(zone_ent, var_absmax, f_maxs);

        create_zone_anchor_entity(zone_ent, 0b000, f_mins[0], f_mins[1], f_mins[2]);
        create_zone_anchor_entity(zone_ent, 0b001, f_mins[0], f_maxs[1], f_mins[2]);
        create_zone_anchor_entity(zone_ent, 0b010, f_maxs[0], f_mins[1], f_mins[2]);
        create_zone_anchor_entity(zone_ent, 0b011, f_maxs[0], f_maxs[1], f_mins[2]);
        create_zone_anchor_entity(zone_ent, 0b100, f_mins[0], f_mins[1], f_maxs[2]);
        create_zone_anchor_entity(zone_ent, 0b101, f_mins[0], f_maxs[1], f_maxs[2]);
        create_zone_anchor_entity(zone_ent, 0b110, f_maxs[0], f_mins[1], f_maxs[2]);
        create_zone_anchor_entity(zone_ent, 0b111, f_maxs[0], f_maxs[1], f_maxs[2]);
    }
}

/**
 * @brief Creates an anchor entity for a polygon vertex.
 *
 * @param[in] zone_ent     Parent zone entity.
 * @param[in] vertex_index Index of the vertex this anchor represents.
 * @param[in] x            World X coordinate.
 * @param[in] y            World Y coordinate.
 * @param[in] z            World Z coordinate.
 * @return                 Created anchor entity index.
 */
stock create_polygon_anchor(zone_ent, vertex_index, Float:x, Float:y, Float:z)
{
    new Float:f_origin[3];
    f_origin[0] = x;
    f_origin[1] = y;
    f_origin[2] = z;

    new ent = create_entity("info_target");

    entity_set_string(ent, EV_SZ_classname, ANCHOR_CLASSNAME);
    entity_set_model(ent, g_zone_model);
    entity_set_origin(ent, f_origin);
    entity_set_size(ent, Float:{-2.0, -2.0, -2.0}, Float:{2.0, 2.0, 2.0});

    set_entvar(ent, var_solid, SOLID_BBOX);
    set_entvar(ent, var_movetype, MOVETYPE_NOCLIP);
    set_entvar(ent, var_owner, zone_ent);
    set_entvar(ent, var_iuser4, vertex_index);  // store vertex index
    set_entvar(ent, var_scale, 0.30);

    set_entvar(ent, var_fuser1, 0.30);
    set_entvar(ent, var_fuser2, 0.0);
    set_entvar(ent, var_fuser3, 0.30);
    set_entvar(ent, var_nextthink, get_gametime() + 0.01);

    set_rendering(ent, kRenderFxPulseFast, 0, 200, 50, kRenderTransAdd, 255);

    return ent;
}

/**
 * @brief Creates a height anchor entity for adjusting zone top height.
 *
 * @param[in] zone_ent Parent zone entity.
 * @param[in] x        World X coordinate (center of zone).
 * @param[in] y        World Y coordinate (center of zone).
 * @param[in] z        World Z coordinate (top of zone).
 * @return             Created anchor entity index.
 */
stock create_height_anchor(zone_ent, Float:x, Float:y, Float:z)
{
    new Float:f_origin[3];
    f_origin[0] = x;
    f_origin[1] = y;
    f_origin[2] = z;

    new ent = create_entity("info_target");

    entity_set_string(ent, EV_SZ_classname, HEIGHT_ANCHOR_CLASSNAME);
    entity_set_model(ent, g_zone_model);
    entity_set_origin(ent, f_origin);
    entity_set_size(ent, Float:{-5.0, -5.0, -5.0}, Float:{5.0, 5.0, 5.0});

    set_entvar(ent, var_solid, SOLID_BBOX);
    set_entvar(ent, var_movetype, MOVETYPE_NOCLIP);
    set_entvar(ent, var_owner, zone_ent);
    set_entvar(ent, var_iuser4, -1);  // -1 indicates height anchor
    set_entvar(ent, var_scale, 0.35);

    set_entvar(ent, var_fuser1, 0.35);
    set_entvar(ent, var_fuser2, 0.0);
    set_entvar(ent, var_fuser3, 0.35);
    set_entvar(ent, var_nextthink, get_gametime() + 0.01);

    // yellow color for height anchor
    set_rendering(ent, kRenderFxPulseFast, 255, 200, 0, kRenderTransAdd, 255);

    return ent;
}

/**
 * @brief Creates a corner anchor entity for legacy AABB zones.
 *
 * @param[in] zone_ent Parent zone entity.
 * @param[in] num      Corner identifier (3-bit bitmask: XYZ).
 * @param[in] x        World X coordinate.
 * @param[in] y        World Y coordinate.
 * @param[in] z        World Z coordinate.
 */
stock create_zone_anchor_entity(zone_ent, num, Float:x, Float:y, Float:z)
{
    new Float:f_origin[3];
    f_origin[0] = x;
    f_origin[1] = y; 
    f_origin[2] = z;

    new ent = create_entity("info_target");

    entity_set_string(ent, EV_SZ_classname, ANCHOR_CLASSNAME);
    entity_set_model(ent, g_zone_model);
    entity_set_origin(ent, f_origin);
    entity_set_size(ent, Float:{-3.0, -3.0, -3.0}, Float:{3.0, 3.0, 3.0});

    set_entvar(ent, var_solid, SOLID_BBOX);
    set_entvar(ent, var_movetype, MOVETYPE_NOCLIP);
    set_entvar(ent, var_owner, zone_ent);
    set_entvar(ent, var_iuser4, num);
    set_entvar(ent, var_scale, 0.25);

    set_entvar(ent, var_fuser1, 0.25);
    set_entvar(ent, var_fuser2, 0.0);
    set_entvar(ent, var_fuser3, 0.25);
    set_entvar(ent, var_nextthink, get_gametime() + 0.01);

    set_rendering(ent, kRenderFxPulseFast, 0, 150, 0, kRenderTransAdd, 255);
}

/**
 * @brief Finds an anchor entity by its identifier.
 *
 * @param[in] zone_ent Parent zone entity.
 * @param[in] num      Anchor identifier (vertex index or corner bitmask).
 * @return             Anchor entity index, or 0 if not found.
 */
stock get_zone_anchor(zone_ent, num)
{
    new ent = 0;
    new a = -1;

    while ((a = find_ent_by_owner(a, ANCHOR_CLASSNAME, zone_ent))) {
        if (get_entvar(a, var_iuser4) == num) {
            ent = a;
            break;
        }
    }
    return ent;
}

/**
 * @brief Finds a polygon vertex anchor by vertex index.
 *
 * @param[in] zone_ent     Parent zone entity.
 * @param[in] vertex_index Vertex index.
 * @return                 Anchor entity index, or 0 if not found.
 */
stock get_polygon_anchor(zone_ent, vertex_index)
{
    return get_zone_anchor(zone_ent, vertex_index);
}

/**
 * @brief Finds the height anchor for a zone.
 *
 * @param[in] zone_ent Parent zone entity.
 * @return             Height anchor entity index, or 0 if not found.
 */
stock get_height_anchor(zone_ent)
{
    new a = -1;
    while ((a = find_ent_by_owner(a, HEIGHT_ANCHOR_CLASSNAME, zone_ent))) {
        return a;
    }
    return 0;
}

/**
 * @brief Updates the position of an anchor entity.
 *
 * @param[in] zone_ent Parent zone entity.
 * @param[in] num      Anchor identifier.
 * @param[in] x        New world X coordinate.
 * @param[in] y        New world Y coordinate.
 * @param[in] z        New world Z coordinate.
 */
stock update_zone_anchor_entity(zone_ent, num, Float:x, Float:y, Float:z)
{
    new ent = get_zone_anchor(zone_ent, num);

    if (is_valid_ent(ent)) {
        new Float:f_origin[3];
        f_origin[0] = x;
        f_origin[1] = y;
        f_origin[2] = z;
        entity_set_origin(ent, f_origin);
    }
}

/**
 * @brief Removes all anchor entities for a zone.
 *
 * @param[in] zone_index Index of the zone in the zones array.
 */
stock remove_zone_anchors(zone_index)
{
    new zone_ent = get_zone_entity(zone_index);
    if (!is_valid_ent(zone_ent))
        return;

    new ent = -1;
    while ((ent = find_ent_by_owner(ent, ANCHOR_CLASSNAME, zone_ent)))
        remove_entity(ent);

    ent = -1;
    while ((ent = find_ent_by_owner(ent, HEIGHT_ANCHOR_CLASSNAME, zone_ent)))
        remove_entity(ent);
}

/**
 * @brief Recreates all anchors for a polygon zone.
 *
 * Called after vertex positions change to update anchor positions.
 *
 * @param[in] zone_index Index of the zone in the zones array.
 */
stock recreate_polygon_anchors(zone_index)
{
    new zone_ent = get_zone_entity(zone_index);
    if (!is_valid_ent(zone_ent) || !is_polygon_zone(zone_index))
        return;

    // remove existing anchors
    remove_zone_anchors(zone_index);

    // create new vertex anchors
    new vertex_count = get_vertex_count(zone_index);
    new Float:vertex[3];
    for (new i = 0; i < vertex_count; i++) {
        get_vertex(zone_index, i, vertex);
        create_polygon_anchor(zone_ent, i, vertex[0], vertex[1], vertex[2]);
    }

    // create height anchor at center top
    new Float:mins[3], Float:maxs[3];
    calculate_polygon_bounds(zone_index, mins, maxs);
    new Float:center_x = (mins[0] + maxs[0]) / 2.0;
    new Float:center_y = (mins[1] + maxs[1]) / 2.0;
    new Float:top_z = get_zone_height(zone_index);
    create_height_anchor(zone_ent, center_x, center_y, top_z);
}

// ============================================================================
// ANCHOR MOVEMENT
// ============================================================================

/**
 * @brief Processes anchor movement during player drag operation.
 *
 * Updates anchor position based on player aim, handles collision detection,
 * and updates the associated zone geometry accordingly.
 *
 * @param[in] player_id Player index performing the drag.
 * @param[in] ent       Anchor entity being dragged.
 */
stock zone_anchor_move_process(player_id, ent)
{
    if(g_player_editor[player_id][m_catched_anchor] != ent) {
        zone_anchor_move_init(player_id, ent);
        if (g_player_editor[player_id][m_catched_anchor] != ent) return;
    }

    // calculate target position
    new Float:f_player_angles[3]; 
    get_entvar(player_id, var_v_angle, f_player_angles);
    new Float:f_forward_vec[3]; 
    angle_vector(f_player_angles, ANGLEVECTOR_FORWARD, f_forward_vec);
    xs_vec_mul_scalar(f_forward_vec, g_player_editor[player_id][m_grab_distance], f_forward_vec);

    new Float:f_player_origin[3]; 
    get_entvar(player_id, var_origin, f_player_origin);
    new Float:f_player_view_offset[3]; 
    get_entvar(player_id, var_view_ofs, f_player_view_offset);
    new Float:f_eye_position[3]; 
    xs_vec_add(f_player_origin, f_player_view_offset, f_eye_position);

    new Float:f_target_pos[3]; 
    xs_vec_add(f_eye_position, f_forward_vec, f_target_pos);

    // trace for collisions
    new trace_result;
    new Float:f_final_pos[3];
    new Float:f_impact_pos[3];
    new Float:f_normal_vec[3];
    
    engfunc(EngFunc_TraceLine, f_eye_position, f_target_pos, 1, player_id, trace_result);
    new Float:f_fraction;
    get_tr2(trace_result, TR_flFraction, f_fraction);

    if (f_fraction < 1.0) {
        get_tr2(trace_result, TR_vecEndPos, f_impact_pos);
        get_tr2(trace_result, TR_vecPlaneNormal, f_normal_vec);
        xs_vec_mul_scalar(f_normal_vec, ANCHOR_COLLISION_OFFSET, f_normal_vec);
        xs_vec_add(f_impact_pos, f_normal_vec, f_final_pos);
    } else {
        get_tr2(trace_result, TR_vecEndPos, f_final_pos);
    }

    set_entvar(ent, var_origin, f_final_pos);

    new zone_index = get_zone_index_by_entity(get_entvar(ent, var_owner));

    if (zone_index == -1)
        return;
    
    new sz_class[32];
    get_entvar(ent, var_classname, sz_class, charsmax(sz_class));
    
    if (equal(sz_class, HEIGHT_ANCHOR_CLASSNAME)) {
        // height anchor - only adjust Z
        new Float:min_z = 999999.0;
        
        // get minimum Z from vertices
        new vertex_count = get_vertex_count(zone_index);
        new Float:vertex[3];
        for (new i = 0; i < vertex_count; i++) {
            get_vertex(zone_index, i, vertex);
            min_z = floatmin(min_z, vertex[2]);
        }
        
        // ensure height stays above minimum
        new Float:new_height = floatmax(f_final_pos[2], min_z + 1.0);
        set_zone_height(zone_index, new_height);
        update_polygon_entity_bounds(zone_index);
        
        // keep anchor at center
        new Float:mins[3], Float:maxs[3];
        calculate_polygon_bounds(zone_index, mins, maxs);
        new Float:anchor_pos[3];
        anchor_pos[0] = (mins[0] + maxs[0]) / 2.0;
        anchor_pos[1] = (mins[1] + maxs[1]) / 2.0;
        anchor_pos[2] = new_height;
        set_entvar(ent, var_origin, anchor_pos);
        
    } else if (is_polygon_zone(zone_index)) {
        // polygon vertex anchor
        new vertex_index = get_entvar(ent, var_iuser4);
        if (vertex_index >= 0 && vertex_index < get_vertex_count(zone_index)) {
            set_vertex(zone_index, vertex_index, f_final_pos);
            update_polygon_entity_bounds(zone_index);
        }
    } else {
        // legacy AABB anchor
        new num1 = get_entvar(ent, var_iuser4);
        new num2 = (~num1) & 0b111;
        new ent2 = get_zone_anchor(zone, num2);

        if(is_valid_ent(ent2)) {
            new Float:f_vec2[3]; 
            get_entvar(ent2, var_origin, f_vec2);
            update_zone_size(zone_index, f_final_pos, f_vec2, num1);
        }
    }
}

/**
 * @brief Updates a legacy AABB zone size based on two corner positions.
 *
 * Recalculates zone bounds and repositions all anchors accordingly.
 *
 * @param[in] zone_index Index of the zone in the zones array.
 * @param[in] f_vec      First corner position.
 * @param[in] f_vec2     Opposite corner position.
 * @param[in] anchor     Anchor identifier being moved (-1 to update all).
 */
stock update_zone_size(zone_index, const Float:f_vec[3], const Float:f_vec2[3], anchor = -1)
{
    new zone_ent = get_zone_entity(zone_index);
    if (!is_valid_ent(zone_ent))
        return;

    new Float:f_mins[3];
    f_mins[0] = floatmin(f_vec[0], f_vec2[0]);
    f_mins[1] = floatmin(f_vec[1], f_vec2[1]);
    f_mins[2] = floatmin(f_vec[2], f_vec2[2]);

    new Float:f_maxs[3];
    f_maxs[0] = floatmax(f_vec[0], f_vec2[0]);
    f_maxs[1] = floatmax(f_vec[1], f_vec2[1]);
    f_maxs[2] = floatmax(f_vec[2], f_vec2[2]);

    // update other anchors
    anchor != 0b000 && update_zone_anchor_entity(zone_ent, 0b000, f_mins[0], f_mins[1], f_mins[2]);
    anchor != 0b001 && update_zone_anchor_entity(zone_ent, 0b001, f_mins[0], f_maxs[1], f_mins[2]);
    anchor != 0b010 && update_zone_anchor_entity(zone_ent, 0b010, f_maxs[0], f_mins[1], f_mins[2]);
    anchor != 0b011 && update_zone_anchor_entity(zone_ent, 0b011, f_maxs[0], f_maxs[1], f_mins[2]);
    anchor != 0b100 && update_zone_anchor_entity(zone_ent, 0b100, f_mins[0], f_mins[1], f_maxs[2]);
    anchor != 0b101 && update_zone_anchor_entity(zone_ent, 0b101, f_mins[0], f_maxs[1], f_maxs[2]);
    anchor != 0b110 && update_zone_anchor_entity(zone_ent, 0b110, f_maxs[0], f_mins[1], f_maxs[2]);
    anchor != 0b111 && update_zone_anchor_entity(zone_ent, 0b111, f_maxs[0], f_maxs[1], f_maxs[2]);

    new Float:f_origin[3];
    xs_vec_add(f_maxs, f_mins, f_origin);
    xs_vec_mul_scalar(f_origin, 0.5, f_origin);

    new Float:f_relative_mins[3];
    xs_vec_sub(f_mins, f_origin, f_relative_mins);
    new Float:f_relative_maxs[3];
    xs_vec_sub(f_maxs, f_origin, f_relative_maxs);

    entity_set_origin(zone_ent, f_origin);
    entity_set_size(zone_ent, f_relative_mins, f_relative_maxs);
    engfunc(EngFunc_SetOrigin, zone_ent, f_origin);
}

/**
 * @brief Marks an anchor as highlighted (player is aiming at it).
 *
 * @param[in] player_id Player index.
 * @param[in] ent       Anchor entity to mark.
 */
stock zone_anchor_move_mark(player_id, ent)
{
    g_player_editor[player_id][m_marked_anchor] = ent;
    set_entvar(ent, var_fuser1, 0.45);
}

/**
 * @brief Removes highlight from an anchor.
 *
 * @param[in] player_id Player index.
 * @param[in] ent       Anchor entity to unmark.
 */
stock zone_anchor_move_unmark(player_id, ent)
{
    if (!is_valid_ent(ent))
        return;

    g_player_editor[player_id][m_marked_anchor] = 0;
    set_entvar(ent, var_fuser1, 0.30);
}

/**
 * @brief Initializes anchor grab operation.
 *
 * Called when player starts dragging an anchor. Stores grab distance,
 * sets visual feedback, and pushes history state.
 *
 * @param[in] player_id Player index.
 * @param[in] ent       Anchor entity being grabbed.
 */
stock zone_anchor_move_init(player_id, ent)
{
    static sz_class[32];
    
    g_player_editor[player_id][m_grab_distance] = entity_range(player_id, ent);
    g_player_editor[player_id][m_catched_anchor] = ent;
    
    // store vertex index if it's a polygon anchor
    g_player_editor[player_id][m_catched_vertex_index] = get_entvar(ent, var_iuser4);

    set_rendering(ent, kRenderFxGlowShell, 255, 0, 0, kRenderTransAdd, 255);

    new zone_ent = get_entvar(ent, var_owner);
    new zone_count = get_zones_count();

    for (new i = 0; i < zone_count; i++)
    {
        if (get_zone_entity(i) == zone_ent)
        {
            g_player_editor[player_id][m_last_zone] = i;

            get_entvar(zone_ent, var_netname, sz_class, charsmax(sz_class));
            g_player_editor[player_id][m_selected_type] = get_type_id(sz_class);
            refresh_menu(player_id);
            break;
        }
    }

    zone_history_push(get_zone_index_by_entity(zone_ent));
}

/**
 * @brief Finalizes anchor grab operation.
 *
 * Called when player releases an anchor. Resets grab state and
 * restores anchor visual appearance.
 *
 * @param[in] player_id Player index.
 * @param[in] ent       Anchor entity being released.
 */
stock zone_anchor_move_uninit(player_id, ent)
{
    if (!is_valid_ent(ent))
        return;

    g_player_editor[player_id][m_grab_distance] = 0.0;
    g_player_editor[player_id][m_catched_anchor] = 0;
    g_player_editor[player_id][m_catched_vertex_index] = -1;
    g_player_editor[player_id][m_holding_use] = false;
    
    new sz_class[32];
    get_entvar(ent, var_classname, sz_class, charsmax(sz_class));
    
    if (equal(sz_class, HEIGHT_ANCHOR_CLASSNAME)) {
        set_rendering(ent, kRenderFxNone, 255, 200, 0, kRenderTransAdd, 255);
    } else {
        set_rendering(ent, kRenderFxNone, 0, 200, 50, kRenderTransAdd, 255);
    }
}

// ============================================================================
// PLAYER PRETHINK / INPUT HANDLING
// ============================================================================

/**
 * @brief Player prethink hook for editor input and zone touch detection.
 *
 * Handles anchor dragging, USE+ATTACK vertex duplication,
 * and player-zone intersection checks for touch events.
 *
 * @param[in] player_id Player index.
 */
public hc_cbaseplayer_prethink(player_id)
{
    if (g_player_editor[player_id][m_in_menu]) {
        set_member(player_id, m_flNextAttack, 1.0);

        new buttons = get_entvar(player_id, var_button);
        
        if (is_valid_ent(g_player_editor[player_id][m_catched_anchor])) {
            if (buttons & IN_ATTACK) {
                // check for USE key (E) or RELOAD key (r) while holding anchor
                if (buttons & IN_USE || buttons & IN_RELOAD) {
                    if (!g_player_editor[player_id][m_holding_use]) {
                        g_player_editor[player_id][m_holding_use] = true;
                        g_player_editor[player_id][m_use_hold_start] = get_gametime();
                    } else if (get_gametime() - g_player_editor[player_id][m_use_hold_start] >= USE_HOLD_DELAY) {
                        // handle USE+ATTACK action
                        handle_use_on_anchor(player_id, g_player_editor[player_id][m_catched_anchor]);
                        g_player_editor[player_id][m_use_hold_start] = get_gametime() + 999.0;  // prevent repeated triggers
                    }
                } else {
                    g_player_editor[player_id][m_holding_use] = false;
                }
                
                zone_anchor_move_process(player_id, g_player_editor[player_id][m_catched_anchor]);
            } else {
                zone_anchor_move_uninit(player_id, g_player_editor[player_id][m_catched_anchor]);
                g_player_editor[player_id][m_holding_use] = false;
            }
        } else {
            g_player_editor[player_id][m_holding_use] = false;
        }
    }

    // touch logic
    if (!is_user_alive(player_id) || g_player_editor[player_id][m_in_menu]) {
        if (g_player_touch[player_id][m_touch_count] > 0) g_player_touch[player_id][m_touch_count] = 0;
        return;
    }

    new bool:should_process_touches = is_user_alive(player_id) && !g_player_editor[player_id][m_in_menu];

    static Float:player_mins[3], Float:player_maxs[3];
    if (should_process_touches) {
        get_entvar(player_id, var_absmin, player_mins);
        get_entvar(player_id, var_absmax, player_maxs);
    }

    // exit check
    for (new i = g_player_touch[player_id][m_touch_count] - 1; i >= 0; i--)
    {
        new zone_ent = g_player_touch[player_id][m_touch_zones][i];

        if (!is_valid_ent(zone_ent)) {
            remove_touched_zone_by_index(player_id, i);
            continue;
        }

        new bool:still_intersects = false;
        if (should_process_touches) {
            new zone_index = get_zone_index_by_entity(zone_ent);
            if (zone_index != -1 && is_polygon_zone(zone_index)) {
                still_intersects = player_intersects_polygon_zone(player_mins, player_maxs, zone_index);
            } else {
                static Float:zone_mins[3], Float:zone_maxs[3];
                get_entvar(zone_ent, var_absmin, zone_mins);
                get_entvar(zone_ent, var_absmax, zone_maxs);
                still_intersects = visual_aabb_intersects(player_mins, player_maxs, zone_mins, zone_maxs, ZONE_INTERSECTION_OFFSET);
            }
        }

        if (!still_intersects)
        {
            fire_touch_event(zone_ent, player_id, CB_LEAVE);
            remove_touched_zone_by_index(player_id, i);
        }
    }

    // entry & ongoing check
    if (should_process_touches)
    {
        new zone_count = get_zones_count();
        for (new zone_idx = 0; zone_idx < zone_count; zone_idx++)
        {
            new zone_ent = get_zone_entity(zone_idx);

            if (!is_valid_ent(zone_ent))
                continue;

            new bool:intersects = false;

            if (is_polygon_zone(zone_idx)) {
                intersects = player_intersects_polygon_zone(player_mins, player_maxs, zone_idx);
            } else {
                static Float:zone_mins[3], Float:zone_maxs[3];
                get_entvar(zone_ent, var_absmin, zone_mins);
                get_entvar(zone_ent, var_absmax, zone_maxs);
                intersects = visual_aabb_intersects(player_mins, player_maxs, zone_mins, zone_maxs, ZONE_INTERSECTION_OFFSET);
            }

            if (intersects)
            {
                if (!is_player_touching_zone(player_id, zone_ent))
                {
                    if (g_player_touch[player_id][m_touch_count] < MAX_ZONES_PER_PLAYER)
                    {
                        g_player_touch[player_id][m_touch_zones][g_player_touch[player_id][m_touch_count]] = zone_ent;
                        g_player_touch[player_id][m_touch_count]++;
                        fire_touch_event(zone_ent, player_id, CB_ENTER);
                    }
                }
                fire_touch_event(zone_ent, player_id, CB_TOUCH);
            }
        }
    }
}

/**
 * @brief Handles USE key action while dragging an anchor.
 *
 * Duplicates the current vertex, creating a new corner in the polygon zone.
 *
 * @param[in] player_id  Player index.
 * @param[in] anchor_ent Anchor entity being held.
 */
stock handle_use_on_anchor(player_id, anchor_ent)
{
    // regular vertex anchor - duplicate corner
    new zone_index = get_zone_index_by_entity(get_entvar(anchor_ent, var_owner));

    if (zone_index == -1 || !is_polygon_zone(zone_index))
        return;
    
    new vertex_index = get_entvar(anchor_ent, var_iuser4);
    new vertex_count = get_vertex_count(zone_index);
    
    if (vertex_count >= MAX_POLYGON_VERTICES) {
        TimerChat(player_id, "Maximum vertices reached: ^x04%d", MAX_POLYGON_VERTICES);
        return;
    }
    
    // push history before modification
    zone_history_push(zone_index);
    
    // get current vertex position
    new Float:vertex[3];
    get_vertex(zone_index, vertex_index, vertex);
    
    // add slight offset so the new vertex is visible
    vertex[0] += 8.0;
    vertex[1] += 8.0;
    
    // insert new vertex after current one
    new new_index = add_vertex_after(zone_index, vertex_index, vertex);
    
    if (new_index != -1) {
        // recreate anchors
        remove_zone_anchors(zone_index);
        create_zone_anchors(zone_index);
        update_polygon_entity_bounds(zone_index);
        
        TimerChat(player_id, "Added new corner. Total: ^x04%d", get_vertex_count(zone_index));
        client_cmd(player_id, "spk buttons/blip1.wav");
        
        // find and grab the new anchor
        new new_anchor = get_polygon_anchor(get_zone_entity(zone_index), new_index);
        if (is_valid_ent(new_anchor)) {
            zone_anchor_move_uninit(player_id, g_player_editor[player_id][m_catched_anchor]);
            zone_anchor_move_init(player_id, new_anchor);
            g_player_editor[player_id][m_catched_vertex_index] = new_index;
        }
    }
}

// ============================================================================
// TRACE LINE HANDLING
// ============================================================================

/**
 * @brief Forward hook for trace line operations.
 *
 * Detects when player is aiming at anchors and handles
 * marking/grabbing logic for the zone editor.
 *
 * @param[in] v1             Trace start position.
 * @param[in] v2             Trace end position.
 * @param[in] f_no_monsters  Trace flags.
 * @param[in] pent_to_skip   Entity to ignore (usually the player).
 * @param[in] ptr            Trace result handle.
 * @return                   FMRES_IGNORED to allow normal processing.
 */
public fw_trace_line(const Float:v1[], const Float:v2[], f_no_monsters, pent_to_skip, ptr)
{
    if(is_user_alive(pent_to_skip))
    {
        if(g_player_editor[pent_to_skip][m_in_menu])
        {
            new ent = get_tr2(ptr, TR_pHit);
            
            if(!is_valid_ent(ent)) 
            {
                zone_anchor_move_unmark(pent_to_skip, g_player_editor[pent_to_skip][m_marked_anchor]);
                return FMRES_IGNORED;
            }
                
            if(g_player_editor[pent_to_skip][m_catched_anchor])
            {
                if(get_entvar(pent_to_skip, var_button)&IN_ATTACK)
                    zone_anchor_move_process(pent_to_skip, g_player_editor[pent_to_skip][m_catched_anchor]);
                else
                    zone_anchor_move_uninit(pent_to_skip, g_player_editor[pent_to_skip][m_catched_anchor]);
            }
            else
            {
                new sz_class[32]; 
                get_entvar(ent, var_classname, sz_class, charsmax(sz_class));

                if(equal(sz_class, ANCHOR_CLASSNAME) || equal(sz_class, HEIGHT_ANCHOR_CLASSNAME))
                {
                    if(get_entvar(pent_to_skip, var_button)&IN_ATTACK)                    
                        zone_anchor_move_init(pent_to_skip, ent);
                    else
                        zone_anchor_move_mark(pent_to_skip, ent);
                }
                else
                    zone_anchor_move_unmark(pent_to_skip, g_player_editor[pent_to_skip][m_marked_anchor]);
            }
        }
    }

    return FMRES_IGNORED;
}

// ============================================================================
// ZONE AIMING / SELECTION
// ============================================================================

/**
 * @brief Determines which face of an AABB zone the player is aiming at.
 *
 * Uses ray-AABB intersection to find the closest face hit.
 *
 * @param[in] player_id Player index.
 * @param[in] ent       Zone entity.
 * @return              Face identifier (FACE_MINUS_X, etc.) or -1 if not aiming at zone.
 */
stock get_aimed_zone_face(player_id, ent)
{
    if (!is_valid_ent(ent) || !is_user_alive(player_id))
        return -1;

    new Float:eye_pos[3], Float:aim_dir[3], Float:v_angle[3], Float:view_ofs[3];
    pev(player_id, pev_origin, eye_pos);
    pev(player_id, pev_view_ofs, view_ofs);
    xs_vec_add(eye_pos, view_ofs, eye_pos);

    pev(player_id, pev_v_angle, v_angle);
    angle_vector(v_angle, ANGLEVECTOR_FORWARD, aim_dir);

    new Float:zone_mins[3], Float:zone_maxs[3];
    pev(ent, pev_absmin, zone_mins);
    pev(ent, pev_absmax, zone_maxs);

    new Float:hit_distance;
    if (!visual_ray_intersects_aabb(eye_pos, aim_dir, zone_mins, zone_maxs, hit_distance))
        return -1;

    new Float:intersection[3];
    xs_vec_mul_scalar(aim_dir, hit_distance, intersection);
    xs_vec_add(eye_pos, intersection, intersection);

    new Float:tolerance = 1.0;

    if (floatabs(intersection[0] - zone_mins[0]) < tolerance) return FACE_MINUS_X;
    if (floatabs(intersection[0] - zone_maxs[0]) < tolerance) return FACE_PLUS_X;
    if (floatabs(intersection[1] - zone_mins[1]) < tolerance) return FACE_MINUS_Y;
    if (floatabs(intersection[1] - zone_maxs[1]) < tolerance) return FACE_PLUS_Y;
    if (floatabs(intersection[2] - zone_mins[2]) < tolerance) return FACE_MINUS_Z;
    if (floatabs(intersection[2] - zone_maxs[2]) < tolerance) return FACE_PLUS_Z;

    new Float:dist_x_min = floatabs(intersection[0] - zone_mins[0]);
    new Float:dist_x_max = floatabs(intersection[0] - zone_maxs[0]);
    new Float:dist_y_min = floatabs(intersection[1] - zone_mins[1]);
    new Float:dist_y_max = floatabs(intersection[1] - zone_maxs[1]);
    new Float:dist_z_min = floatabs(intersection[2] - zone_mins[2]);
    new Float:dist_z_max = floatabs(intersection[2] - zone_maxs[2]);

    new Float:min_dist = floatmin(dist_x_min, floatmin(dist_x_max, floatmin(dist_y_min, floatmin(dist_y_max, floatmin(dist_z_min, dist_z_max)))));

    if (min_dist == dist_x_min) return FACE_MINUS_X;
    if (min_dist == dist_x_max) return FACE_PLUS_X;
    if (min_dist == dist_y_min) return FACE_MINUS_Y;
    if (min_dist == dist_y_max) return FACE_PLUS_Y;
    if (min_dist == dist_z_min) return FACE_MINUS_Z;
    if (min_dist == dist_z_max) return FACE_PLUS_Z;

    return -1;
}

/**
 * @brief Determines which face of a polygon zone the player is aiming at.
 *
 * Uses ray-polygon intersection to find walls, top, or bottom faces.
 *
 * @param[in] player_id  Player index.
 * @param[in] zone_index Index of the zone in the zones array.
 * @return               Face identifier (POLYGON_FACE_TOP, wall index, etc.)
 *                       or POLYGON_FACE_NONE if not aiming at zone.
 */
stock get_aimed_polygon_face(player_id, zone_index)
{
    if (!is_user_alive(player_id) || zone_index < 0 || zone_index >= get_zones_count())
        return POLYGON_FACE_NONE;
    
    if (!is_polygon_zone(zone_index))
        return POLYGON_FACE_NONE;
    
    // get player aim ray
    new Float:eye_pos[3], Float:aim_dir[3], Float:v_angle[3], Float:view_ofs[3];
    pev(player_id, pev_origin, eye_pos);
    pev(player_id, pev_view_ofs, view_ofs);
    xs_vec_add(eye_pos, view_ofs, eye_pos);
    pev(player_id, pev_v_angle, v_angle);
    angle_vector(v_angle, ANGLEVECTOR_FORWARD, aim_dir);
    
    // get zone data
    new vertex_count = get_vertex_count(zone_index);
    if (vertex_count < 3)
        return POLYGON_FACE_NONE;
    
    new Float:top_z = get_zone_height(zone_index);
    
    // build vertices array for visual library
    new Float:vertices[MAX_POLYGON_VERTICES][3];
    for (new i = 0; i < vertex_count; i++) {
        get_vertex(zone_index, i, vertices[i]);
    }
    
    // get bounding box for quick rejection
    new Float:mins[3], Float:maxs[3];
    calculate_polygon_bounds(zone_index, mins, maxs);
    
    // use visual library function
    return visual_get_aimed_polygon_face(eye_pos, aim_dir, vertices, vertex_count, top_z, mins, maxs);
}

/**
 * @brief Checks if the player is aiming at any zone.
 *
 * @param[in] player_id Player index.
 * @return              true if aiming at a zone face, false otherwise.
 */
stock bool:is_player_aiming_at_zone(player_id)
{
    if (!is_user_alive(player_id)) return false;

    new zone_count = get_zones_count();
    for (new i = 0; i < zone_count; i++) {
        new ent = get_zone_entity(i);
        if (!is_valid_ent(ent)) continue;

        if (is_polygon_zone(i)) {
            new aimed_face = get_aimed_polygon_face(player_id, i);
            if (aimed_face != POLYGON_FACE_NONE) {
                return true;
            }
        } else {
            new aimed_face = get_aimed_zone_face(player_id, ent);
            if (aimed_face != -1) {
                return true;
            }
        }
    }

    return false;
}

/**
 * @brief Auto-selects a zone based on player aim or proximity.
 *
 * First tries to select a zone the player is aiming at.
 * Falls back to the nearest zone if not aiming at any.
 *
 * @param[in] player_id Player index.
 */
stock select_zone_by_look(player_id)
{
    if (!is_user_alive(player_id) || get_zones_count() == 0) return;

    new selected_zone = -1;
    new zone_count = get_zones_count();

    // first try to find a zone the player is aiming at
    for (new i = 0; i < zone_count; i++) {
        new ent = get_zone_entity(i);
        if (!is_valid_ent(ent)) continue;

        if (is_polygon_zone(i)) {
            new aimed_face = get_aimed_polygon_face(player_id, i);
            if (aimed_face != POLYGON_FACE_NONE) {
                selected_zone = i;
                break;
            }
        } else {
            new aimed_face = get_aimed_zone_face(player_id, ent);
            if (aimed_face != -1) {
                selected_zone = i;
                break;
            }
        }
    }

    // if not aiming at any zone, find the nearest one
    if (selected_zone == -1) {
        new Float:player_origin[3];
        get_entvar(player_id, var_origin, player_origin);

        new Float:nearest_distance = 999999.0;

        for (new i = 0; i < zone_count; i++) {
            new ent = get_zone_entity(i);
            if (!is_valid_ent(ent)) continue;

            new Float:zone_origin[3];
            get_entvar(ent, var_origin, zone_origin);

            new Float:distance = get_distance_f(player_origin, zone_origin);
            if (distance < nearest_distance) {
                nearest_distance = distance;
                selected_zone = i;
            }
        }
    }

    if (selected_zone != -1) {
        g_player_editor[player_id][m_last_zone] = selected_zone;

        new sz_class[32];
        new ent = get_zone_entity(selected_zone);
        get_entvar(ent, var_netname, sz_class, charsmax(sz_class));
        g_player_editor[player_id][m_selected_type] = get_type_id(sz_class);
    }
}

// ============================================================================
// EXPAND/SHRINK ZONE
// ============================================================================

/**
 * @brief Expands or shrinks the aimed zone face.
 *
 * For polygon zones: adjusts height or moves wall vertices.
 * For AABB zones: adjusts the corresponding face boundary.
 *
 * @param[in] player_id Player index.
 * @param[in] f_amount  Amount to expand/shrink in units.
 * @param[in] b_shrink  true to shrink, false to expand.
 */
stock expand_zone(player_id, Float:f_amount, bool:b_shrink)
{
    if (!g_player_editor[player_id][m_in_menu])
        return;

    new ent = -1;
    new aimed_face = -1;
    new zone_index = -1;

    new zone_count = get_zones_count();
    for (new i = 0; i < zone_count; i++) {
        new zone_ent = get_zone_entity(i);
        if (!is_valid_ent(zone_ent)) continue;

        if (is_polygon_zone(i)) {
            aimed_face = get_aimed_polygon_face(player_id, i);
            if (aimed_face != POLYGON_FACE_NONE) {
                ent = zone_ent;
                zone_index = i;
                g_player_editor[player_id][m_last_zone] = i;
                break;
            }
        } else {
            aimed_face = get_aimed_zone_face(player_id, zone_ent);
            if (aimed_face != -1) {
                ent = zone_ent;
                zone_index = i;
                g_player_editor[player_id][m_last_zone] = i;
                break;
            }
        }
    }

    if (ent == -1 || aimed_face == -1 || zone_index == -1)
    {
        TimerChat(player_id, "Could not determine aimed zone/face. Aim at a zone and try again.");
        return;
    }

    zone_history_push(zone_index);

    if (is_polygon_zone(zone_index)) {
        new Float:current_height = get_zone_height(zone_index);
        
        if (aimed_face == POLYGON_FACE_TOP) {
            // expand/shrink top face (change height)
            new Float:new_height = b_shrink ? (current_height - f_amount) : (current_height + f_amount);
            
            // get minimum Z from vertices
            new Float:min_z = 999999.0;
            new Float:vertex[3];
            new vertex_count = get_vertex_count(zone_index);
            for (new i = 0; i < vertex_count; i++) {
                get_vertex(zone_index, i, vertex);
                min_z = floatmin(min_z, vertex[2]);
            }
            
            if (new_height <= min_z + 1.0) {
                TimerChat(player_id, "Zone cannot shrink further; minimum height reached.");
                zone_history_pop(zone_index);
                return;
            }
            
            set_zone_height(zone_index, new_height);
            update_polygon_entity_bounds(zone_index);
            
            // update height anchor position
            new height_anchor = get_height_anchor(ent);
            if (is_valid_ent(height_anchor)) {
                new Float:anchor_pos[3];
                get_entvar(height_anchor, var_origin, anchor_pos);
                anchor_pos[2] = new_height;
                set_entvar(height_anchor, var_origin, anchor_pos);
            }
        } 
        else if (aimed_face == POLYGON_FACE_BOTTOM) {
            // expand/shrink bottom face (move all vertices up/down)
            new Float:vertex[3];
            new vertex_count = get_vertex_count(zone_index);
            
            // calculate new Z offset
            new Float:z_offset = b_shrink ? f_amount : -f_amount;
            
            // check if shrinking would make zone too small
            new Float:max_vertex_z = -999999.0;
            for (new i = 0; i < vertex_count; i++) {
                get_vertex(zone_index, i, vertex);
                max_vertex_z = floatmax(max_vertex_z, vertex[2]);
            }
            
            if (max_vertex_z + z_offset >= current_height - 1.0) {
                TimerChat(player_id, "Zone cannot shrink further; minimum height reached.");
                zone_history_pop(zone_index);
                return;
            }
            
            // move all vertices
            for (new i = 0; i < vertex_count; i++) {
                get_vertex(zone_index, i, vertex);
                vertex[2] += z_offset;
                set_vertex(zone_index, i, vertex);
            }
            
            update_polygon_entity_bounds(zone_index);
            recreate_polygon_anchors(zone_index);
        }
        else if (aimed_face >= 0) {
            // expand/shrink a wall - move both vertices along the wall's outward normal
            new vertex_count = get_vertex_count(zone_index);
            new v1_idx = aimed_face;
            new v2_idx = (aimed_face + 1) % vertex_count;
            
            new Float:v1[3], Float:v2[3];
            get_vertex(zone_index, v1_idx, v1);
            get_vertex(zone_index, v2_idx, v2);
            
            // calculate wall direction
            new Float:dx = v2[0] - v1[0];
            new Float:dy = v2[1] - v1[1];
            new Float:len = floatsqroot(dx*dx + dy*dy);
            
            if (len < 0.001) {
                TimerChat(player_id, "Wall is too small to expand.");
                zone_history_pop(zone_index);
                return;
            }
            
            // normalize
            dx /= len;
            dy /= len;
            
            // outward normal (perpendicular to wall, pointing outward)
            new Float:nx = -dy;
            new Float:ny = dx;
            
            // calculate polygon centroid
            new Float:cx = 0.0, Float:cy = 0.0;
            new Float:temp_v[3];
            for (new i = 0; i < vertex_count; i++) {
                get_vertex(zone_index, i, temp_v);
                cx += temp_v[0];
                cy += temp_v[1];
            }
            cx /= float(vertex_count);
            cy /= float(vertex_count);
            
            // wall midpoint
            new Float:mx = (v1[0] + v2[0]) / 2.0;
            new Float:my = (v1[1] + v2[1]) / 2.0;
            
            // vector from centroid to wall midpoint
            new Float:to_center_x = cx - mx;
            new Float:to_center_y = cy - my;
            
            // if normal points toward center, flip it
            if (nx * to_center_x + ny * to_center_y > 0) {
                nx = -nx;
                ny = -ny;
            }
            
            // calculate movement amount
            new Float:move_amount = b_shrink ? -f_amount : f_amount;
            
            // move both vertices along the normal
            v1[0] += nx * move_amount;
            v1[1] += ny * move_amount;
            v2[0] += nx * move_amount;
            v2[1] += ny * move_amount;
            
            set_vertex(zone_index, v1_idx, v1);
            set_vertex(zone_index, v2_idx, v2);
            
            update_polygon_entity_bounds(zone_index);
            recreate_polygon_anchors(zone_index);
        }
        else {
            TimerChat(player_id, "Could not determine aimed face.");
            zone_history_pop(zone_index);
            return;
        }
    } else {
        // legacy AABB expansion
        new Float:f_origin[3]; 
        get_entvar(ent, var_origin, f_origin);
        new Float:f_old_mins[3]; 
        get_entvar(ent, var_mins, f_old_mins);
        new Float:f_old_maxs[3]; 
        get_entvar(ent, var_maxs, f_old_maxs);

        new Float:f_new_mins[3]; 
        f_new_mins = f_old_mins;
        new Float:f_new_maxs[3]; 
        f_new_maxs = f_old_maxs;
        new bool:b_check_x = false, bool:b_check_y = false, bool:b_check_z = false;

        new Float:face_change = b_shrink ? -f_amount : f_amount;
        switch (aimed_face)
        {
            case FACE_MINUS_X: { f_new_mins[0] -= face_change; b_check_x = true; }
            case FACE_PLUS_X:  { f_new_maxs[0] += face_change; b_check_x = true; }
            case FACE_MINUS_Y: { f_new_mins[1] -= face_change; b_check_y = true; }
            case FACE_PLUS_Y:  { f_new_maxs[1] += face_change; b_check_y = true; }
            case FACE_MINUS_Z: { f_new_mins[2] -= face_change; b_check_z = true; }
            case FACE_PLUS_Z:  { f_new_maxs[2] += face_change; b_check_z = true; }
        }

        if (b_shrink)
        {
            new bool:b_too_small = false;
            if (b_check_x && (f_new_maxs[0] - f_new_mins[0]) < 1.0) b_too_small = true;
            if (!b_too_small && b_check_y && (f_new_maxs[1] - f_new_mins[1]) < 1.0) b_too_small = true;
            if (!b_too_small && b_check_z && (f_new_maxs[2] - f_new_mins[2]) < 1.0) b_too_small = true;

            if (b_too_small)
            {
                TimerChat(player_id, "Zone cannot shrink further; minimum size reached.");
                zone_history_pop(zone_index);
                return;
            }
        }

        entity_set_size(ent, f_new_mins, f_new_maxs);

        new Float:f_new_abs_mins[3], Float:f_new_abs_maxs[3];
        xs_vec_add(f_origin, f_new_mins, f_new_abs_mins);
        xs_vec_add(f_origin, f_new_maxs, f_new_abs_maxs);

        reposition_all_anchors(ent, f_new_abs_mins, f_new_abs_maxs);
    }

    client_cmd(player_id, "spk buttons/blip1.wav");
}

/**
 * @brief Repositions all 8 corner anchors for a legacy AABB zone.
 *
 * @param[in] zone_ent    Zone entity.
 * @param[in] f_abs_mins  Absolute minimum coordinates.
 * @param[in] f_abs_maxs  Absolute maximum coordinates.
 */
stock reposition_all_anchors(zone_ent, const Float:f_abs_mins[3], const Float:f_abs_maxs[3])
{
    if (!is_valid_ent(zone_ent))
        return;

    update_zone_anchor_entity(zone_ent, 0b000, f_abs_mins[0], f_abs_mins[1], f_abs_mins[2]);
    update_zone_anchor_entity(zone_ent, 0b001, f_abs_mins[0], f_abs_maxs[1], f_abs_mins[2]);
    update_zone_anchor_entity(zone_ent, 0b010, f_abs_maxs[0], f_abs_mins[1], f_abs_mins[2]);
    update_zone_anchor_entity(zone_ent, 0b011, f_abs_maxs[0], f_abs_maxs[1], f_abs_mins[2]);
    update_zone_anchor_entity(zone_ent, 0b100, f_abs_mins[0], f_abs_mins[1], f_abs_maxs[2]);
    update_zone_anchor_entity(zone_ent, 0b101, f_abs_mins[0], f_abs_maxs[1], f_abs_maxs[2]);
    update_zone_anchor_entity(zone_ent, 0b110, f_abs_maxs[0], f_abs_mins[1], f_abs_maxs[2]);
    update_zone_anchor_entity(zone_ent, 0b111, f_abs_maxs[0], f_abs_maxs[1], f_abs_maxs[2]);
}

/**
 * @brief Menu callback: Toggles 2-point corner marking mode.
 *
 * When enabled, player can mark two corners in the world
 * and a zone is created between them.
 *
 * @param[in] player_id Player index.
 */
@zone_corner_mode(player_id)
{
    g_player_editor[player_id][m_corner_mode] = !g_player_editor[player_id][m_corner_mode];
    if (!g_player_editor[player_id][m_corner_mode])
    {
        g_player_editor[player_id][m_corner_a_set] = false;
    }
}

/**
 * @brief Menu callback: Marks current position as a zone corner.
 *
 * First call marks corner A, second call marks corner B and creates the zone.
 * The zone is created using the currently selected zone type.
 *
 * @param[in] player_id Player index.
 */
@zone_mark_corner(player_id)
{
    if (!g_player_editor[player_id][m_corner_a_set])
    {
        // Mark corner A
        get_entvar(player_id, var_origin, g_player_editor[player_id][m_corner_a]);
        g_player_editor[player_id][m_corner_a_set] = true;
        TimerChat(player_id, "Corner A marked. Now go to the opposite corner and select ^x04Mark Corner B^x01.");
        client_cmd(player_id, "spk buttons/blip1.wav");
        show_zone_menu(player_id);
    }
    else
    {
        // Mark corner B
        get_entvar(player_id, var_origin, g_player_editor[player_id][m_corner_b]);

        // Compute absolute mins/maxs from the two corners directly from global state
        new Float:abs_mins[3], Float:abs_maxs[3];
        for (new i = 0; i < 2; i++)
        {
            abs_mins[i] = floatmin(g_player_editor[player_id][m_corner_a][i], g_player_editor[player_id][m_corner_b][i]);
            abs_maxs[i] = floatmax(g_player_editor[player_id][m_corner_a][i], g_player_editor[player_id][m_corner_b][i]);
        }
        // Z: convert from player center to feet level, 72 units tall
        abs_mins[2] = floatmin(g_player_editor[player_id][m_corner_a][2], g_player_editor[player_id][m_corner_b][2]) - 36.0;
        abs_maxs[2] = abs_mins[2] + 72.0;

        // Reset corner state
        g_player_editor[player_id][m_corner_a_set] = false;
        g_player_editor[player_id][m_corner_mode] = false;

        // Center point
        new Float:origin[3];
        for (new i = 0; i < 3; i++)
            origin[i] = (abs_mins[i] + abs_maxs[i]) / 2.0;

        // Relative mins/maxs from center
        new Float:rel_mins[3], Float:rel_maxs[3];
        for (new i = 0; i < 3; i++)
        {
            rel_mins[i] = abs_mins[i] - origin[i];
            rel_maxs[i] = abs_maxs[i] - origin[i];
        }

        // Determine zone class from selected type
        new type_idx = g_player_editor[player_id][m_selected_type];
        new sz_class[ZONE_MAX_CLASSNAME_LENGTH];
        if (type_idx == -1)
            copy(sz_class, charsmax(sz_class), ZONE_DEFAULT_CLASSNAME);
        else
            copy(sz_class, charsmax(sz_class), g_zone_types[type_idx][m_type_class]);

        new zone_index = create_zone(sz_class, "", origin, rel_mins, rel_maxs, player_id);

        if (zone_index != -1)
        {
            create_zone_anchors(zone_index);
            TimerChat(player_id, "Zone ^x04%s^x01 created from 2 points.", sz_class);
            client_cmd(player_id, "spk buttons/button9.wav");
        }
    }
}
