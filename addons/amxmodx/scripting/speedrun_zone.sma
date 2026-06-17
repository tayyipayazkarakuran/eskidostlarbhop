#include <amxmodx>
#include <reapi>
#include <fakemeta>
#include <xs>

#include <visual>
#include <speedrun_zone_api>

#define PLUGIN "Speedrun: Zones"
#define VERSION "1.1-bmod"
#define AUTHOR "PWNED"  

#pragma semicolon 1
#pragma compress 1

// ============================================================================
// COMPONENTS (order matters, deps first)
// ============================================================================

#include "components/storage.inc"
#include "components/physics.inc"
#include "components/visualization.inc"
#include "components/editor.inc"

// ============================================================================
// PLUGIN LIFECYCLE
// ============================================================================

/**
 * @brief Registers native functions exposed to other plugins.
 */
public plugin_natives()
{
    register_library("speedrun_zone");

    register_native("sr_zone_register_type", "native_register_type");
    register_native("sr_zone_set_visibility", "native_set_visibility");
    register_native("sr_zone_get_visibility", "native_get_visibility");
    register_native("sr_zone_get_bounds_by_class", "native_get_bounds_by_class");
    register_native("sr_zone_is_point_in_class", "native_is_point_in_class");
    register_native("sr_zone_get_shape_json_by_class", "native_get_shape_json_by_class");
    register_native("sr_zone_upsert_aabb", "native_upsert_aabb");
    register_native("sr_zone_upsert_shape_json", "native_upsert_shape_json");
    register_native("sr_zone_delete_by_class", "native_delete_by_class");
    register_native("sr_zone_save", "native_save");
    register_native("sr_zone_reload", "native_reload");
}

/**
 * @brief Initializes the plugin, registers commands, hooks, and forwards.
 */
public plugin_init()
{
    register_plugin(PLUGIN, VERSION, AUTHOR);

    types_init();

    register_clcmd("say /zone", "command_zone");
    register_clcmd("say_team /zone", "command_zone");
    register_clcmd("zone", "command_zone");
    register_clcmd("box", "command_zone");

    register_think("zone", "zone_think");
    register_think(ANCHOR_CLASSNAME, "anchor_think");
    register_think(HEIGHT_ANCHOR_CLASSNAME, "anchor_think");

    register_forward(FM_TraceLine, "fw_trace_line", true);
    RegisterHookChain(RG_CBasePlayer_PreThink, "hc_cbaseplayer_prethink", true);

    g_fw_on_start_touch = CreateMultiForward("sr_zone_start_touch", ET_STOP, FP_CELL, FP_CELL, FP_STRING);
    g_fw_on_stop_touch = CreateMultiForward("sr_zone_stop_touch", ET_STOP, FP_CELL, FP_CELL, FP_STRING);
    g_fw_on_touch = CreateMultiForward("sr_zone_touch", ET_STOP, FP_CELL, FP_CELL, FP_STRING);
    g_fw_on_create = CreateMultiForward("sr_zone_created", ET_STOP, FP_CELL, FP_STRING);
    g_fw_on_delete = CreateMultiForward("sr_zone_deleted", ET_STOP, FP_CELL, FP_STRING);
    g_fw_on_save = CreateMultiForward("sr_zone_saved", ET_IGNORE);

    register_clcmd("say /zundo", "cmd_undo");
    register_clcmd("say_team /zundo", "cmd_undo");
    register_clcmd("zone_undo", "cmd_undo");
    register_clcmd("zone_save", "cmd_zone_save");
    register_clcmd("zone_reload", "cmd_zone_reload");

    g_zones = ArrayCreate(zone_data_t);
}

/**
 * @brief Precaches models and sprites required by the zone system.
 */
public plugin_precache()
{
    precache_model(g_zone_model);
    g_sprite_line = precache_model("sprites/white.spr");
    visual_set_sprite(g_sprite_line);
}

/**
 * @brief Loads zone data from the map data file.
 */
public plugin_cfg()
{
    create_zone_directories();

    new sz_map_name[32];
    get_mapname(sz_map_name, charsmax(sz_map_name));

    new sz_data_dir[256];
    get_datadir(sz_data_dir, charsmax(sz_data_dir));
    formatex(g_zone_file_path, charsmax(g_zone_file_path), "%s/bhop_timer/%s_zones.json", sz_data_dir, sz_map_name);

    load_zone();
}

/**
 * @brief Creates all necessary directories for the zone plugin.
 */
stock create_zone_directories()
{
    new const sz_required_dirs[][] = {
        "bhop_timer"
    };

    new sz_base_data_dir[128];
    get_datadir(sz_base_data_dir, charsmax(sz_base_data_dir));

    for (new i = 0; i < sizeof(sz_required_dirs); i++)
    {
        new sz_full_path[256];
        formatex(sz_full_path, charsmax(sz_full_path), "%s/%s", sz_base_data_dir, sz_required_dirs[i]);

        if (!dir_exists(sz_full_path))
        {
            if (!mkdir(sz_full_path)) {
                log_amx("Failed to create required directory: %s", sz_full_path);
            }
        }
    }
}

/**
 * @brief Saves zone data and cleans up resources on plugin unload.
 */
public plugin_end()
{
    save_zone();

    new zone_count = ArraySize(g_zones);
    for (new i = 0; i < zone_count; i++) {
        new zone_data[zone_data_t];
        ArrayGetArray(g_zones, i, zone_data);

        if (zone_data[zd_vertices] != Invalid_Array) {
            ArrayDestroy(zone_data[zd_vertices]);
        }
        if (zone_data[zd_history] != Invalid_Array) {
            ArrayDestroy(zone_data[zd_history]);
        }
    }

    ArrayDestroy(g_zones);
}

/**
 * @brief Resets player editor and touch state when they join the server.
 *
 * @param[in] player_id Player index.
 */
public client_putinserver(player_id)
{
    g_player_editor[player_id][m_in_menu] = false;
    g_player_editor[player_id][m_catched_anchor] = 0;
    g_player_editor[player_id][m_marked_anchor] = 0;
    g_player_editor[player_id][m_last_zone] = -1;
    g_player_editor[player_id][m_selected_type] = -1;
    g_player_editor[player_id][m_grab_distance] = 0.0;
    g_player_editor[player_id][m_catched_vertex_index] = -1;
    g_player_editor[player_id][m_holding_use] = false;
    g_player_editor[player_id][m_use_hold_start] = 0.0;
    g_player_editor[player_id][m_last_aiming_state] = false;
    g_player_editor[player_id][m_last_menu_hash] = 0;

    g_player_touch[player_id][m_touch_count] = 0;
}

// ============================================================================
// NATIVE IMPLEMENTATIONS
// ============================================================================

/**
 * @brief Native: Registers a zone type with callbacks.
 *
 * @native zone:sr_zone_register_type(const class_name[], const description[],
 *     const color[3], zone_visibility:visibility, const on_enter[],
 *     const on_leave[], const on_touch[], const on_create[], const on_delete[]);
 *
 * @param[in] plugin_id Calling plugin ID.
 * @param[in] num_params Number of parameters passed.
 * @return Zone type handle on success, -1 on failure.
 */
public native_register_type(plugin_id, num_params)
{
    new class_name[ZONE_MAX_CLASSNAME_LENGTH];
    new description[ZONE_MAX_DESCRIPTION_LENGTH];
    new color[3];
    new zone_visibility:visibility;
    new callback_names[CB_COUNT][64];
    new callbacks[CB_COUNT];

    get_string(1, class_name, charsmax(class_name));
    get_string(2, description, charsmax(description));
    get_array(3, color, 3);
    visibility = zone_visibility:get_param(4);
    get_string(5, callback_names[CB_ENTER], charsmax(callback_names[]));
    get_string(6, callback_names[CB_LEAVE], charsmax(callback_names[]));
    get_string(7, callback_names[CB_TOUCH], charsmax(callback_names[]));
    get_string(8, callback_names[CB_CREATE], charsmax(callback_names[]));
    get_string(9, callback_names[CB_DELETE], charsmax(callback_names[]));

    for (new i = 0; i < CB_COUNT; i++)
    {
        if (callback_names[i][0] != EOS)
            callbacks[i] = get_func_id(callback_names[i], plugin_id);
        else
            callbacks[i] = -1;
    }

    return register_zone_type(class_name, description, color, visibility, plugin_id, callbacks);
}

/**
 * @brief Native: Sets visibility mode for a zone type.
 *
 * @native sr_zone_set_visibility(zone:z, zone_visibility:visibility);
 *
 * @param[in] plugin_id Calling plugin ID.
 * @param[in] num_params Number of parameters passed.
 */
public native_set_visibility(plugin_id, num_params)
{
    new type_index = get_param(1);
    new zone_visibility:visibility = zone_visibility:get_param(2);
    set_type_visibility(type_index, visibility);
}

/**
 * @brief Native: Gets visibility mode for a zone type.
 *
 * @native zone_visibility:sr_zone_get_visibility(zone:z);
 *
 * @param[in] plugin_id Calling plugin ID.
 * @param[in] num_params Number of parameters passed.
 * @return Current visibility flags for the zone type.
 */
public native_get_visibility(plugin_id, num_params)
{
    new type_index = get_param(1);
    return _:get_type_visibility(type_index);
}

public native_get_bounds_by_class(plugin_id, num_params)
{
    #pragma unused plugin_id, num_params

    new class_name[ZONE_MAX_CLASSNAME_LENGTH];
    new Float:mins[3], Float:maxs[3];
    get_string(1, class_name, charsmax(class_name));

    if (!get_zone_bounds_by_class(class_name, mins, maxs))
        return false;

    set_array_f(2, mins, 3);
    set_array_f(3, maxs, 3);
    return true;
}

public native_get_shape_json_by_class(plugin_id, num_params)
{
    #pragma unused plugin_id

    new class_name[ZONE_MAX_CLASSNAME_LENGTH];
    new output[2048];
    get_string(1, class_name, charsmax(class_name));

    if (!serialize_zone_shape_json_by_class(class_name, output, charsmax(output)))
        return false;

    set_string(2, output, get_param(3));
    return true;
}

public native_is_point_in_class(plugin_id, num_params)
{
    #pragma unused plugin_id, num_params

    new class_name[ZONE_MAX_CLASSNAME_LENGTH];
    new Float:point[3];
    get_string(1, class_name, charsmax(class_name));
    get_array_f(2, point, 3);

    new zone_count = get_zones_count();
    for (new i = 0; i < zone_count; i++)
    {
        new ent = get_zone_entity(i);
        if (!is_valid_ent(ent))
            continue;

        new current_class[ZONE_MAX_CLASSNAME_LENGTH];
        get_entvar(ent, var_netname, current_class, charsmax(current_class));
        if (!equal(current_class, class_name))
            continue;

        if (is_polygon_zone(i))
        {
            if (point_in_polygon_zone(point, i))
                return true;
        }
        else
        {
            new Float:mins[3], Float:maxs[3];
            if (get_zone_bounds(i, mins, maxs) &&
                point[0] >= mins[0] && point[0] <= maxs[0] &&
                point[1] >= mins[1] && point[1] <= maxs[1] &&
                point[2] >= mins[2] && point[2] <= maxs[2])
            {
                return true;
            }
        }
    }

    return false;
}

public native_upsert_aabb(plugin_id, num_params)
{
    #pragma unused plugin_id, num_params

    new class_name[ZONE_MAX_CLASSNAME_LENGTH], zone_id[32];
    new Float:mins[3], Float:maxs[3];
    get_string(1, class_name, charsmax(class_name));
    get_string(2, zone_id, charsmax(zone_id));
    get_array_f(3, mins, 3);
    get_array_f(4, maxs, 3);

    return upsert_aabb_zone(class_name, zone_id, mins, maxs, bool:get_param(5));
}

public native_upsert_shape_json(plugin_id, num_params)
{
    #pragma unused plugin_id, num_params

    new class_name[ZONE_MAX_CLASSNAME_LENGTH], zone_id[32], shape_json[2048];
    get_string(1, class_name, charsmax(class_name));
    get_string(2, zone_id, charsmax(zone_id));
    get_string(3, shape_json, charsmax(shape_json));

    return upsert_shape_json_zone(class_name, zone_id, shape_json);
}

public native_delete_by_class(plugin_id, num_params)
{
    #pragma unused plugin_id, num_params

    new class_name[ZONE_MAX_CLASSNAME_LENGTH];
    get_string(1, class_name, charsmax(class_name));
    delete_zones_by_class(class_name);
}

public native_save(plugin_id, num_params)
{
    #pragma unused plugin_id, num_params
    save_zone();
}

public native_reload(plugin_id, num_params)
{
    #pragma unused plugin_id, num_params
    clear_zones();
    load_zone();
}

public cmd_zone_save(player_id)
{
    if (!sr_has_zone_access(player_id))
        return PLUGIN_HANDLED;

    save_zone();
    client_print(player_id, print_chat, "[TIMER] Polygon zones saved.");
    return PLUGIN_HANDLED;
}

public cmd_zone_reload(player_id)
{
    if (!sr_has_zone_access(player_id))
        return PLUGIN_HANDLED;

    clear_zones();
    load_zone();
    client_print(player_id, print_chat, "[TIMER] Polygon zones reloaded.");
    return PLUGIN_HANDLED;
}

stock bool:sr_has_zone_access(player_id)
{
    if (player_id == 0)
        return true;

    if (!is_user_connected(player_id))
        return false;

    new flag_text[8];
    new cvar = get_cvar_pointer("bhop_zone_admin_flag");
    if (cvar)
    {
        get_pcvar_string(cvar, flag_text, charsmax(flag_text));
    }

    if (!flag_text[0])
        copy(flag_text, charsmax(flag_text), "l");

    return (get_user_flags(player_id) & read_flags(flag_text)) ? true : false;
}
