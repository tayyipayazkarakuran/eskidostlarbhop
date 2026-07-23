#if defined _bmod_zone_embedded_included
    #endinput
#endif
#define _bmod_zone_embedded_included

new g_embeddedZonePluginId = -1;

stock EmbeddedZonesPrecache()
{
    precache_model(g_zone_model);
    g_sprite_line = precache_model("sprites/white.spr");
    visual_set_sprite(g_sprite_line);
}

stock EmbeddedZonesInit()
{
    new fileName[2], pluginName[2], version[2], author[2], status[2];
    g_embeddedZonePluginId = get_plugin(-1,
        fileName, charsmax(fileName), pluginName, charsmax(pluginName),
        version, charsmax(version), author, charsmax(author), status, charsmax(status));
    types_init();
    register_clcmd("say /zone", "command_zone");
    register_clcmd("say_team /zone", "command_zone");
    register_clcmd("zone", "command_zone");
    register_clcmd("box", "command_zone");
    register_clcmd("say /zundo", "cmd_undo");
    register_clcmd("say_team /zundo", "cmd_undo");
    register_clcmd("zone_undo", "cmd_undo");
    register_clcmd("zone_save", "cmd_zone_save");
    register_clcmd("zone_reload", "cmd_zone_reload");
    register_think("zone", "zone_think");
    register_think("zone_anchor", "anchor_think");
    register_think("zone_height_anchor", "anchor_think");
    register_forward(FM_TraceLine, "fw_trace_line", true);

    g_fw_on_create = CreateMultiForward("sr_zone_created", ET_STOP, FP_CELL, FP_STRING);
    g_fw_on_delete = CreateMultiForward("sr_zone_deleted", ET_STOP, FP_CELL, FP_STRING);
    g_fw_on_save = CreateMultiForward("sr_zone_saved", ET_IGNORE);
    g_zones = ArrayCreate(zone_data_t);
}

stock EmbeddedZonesCfg()
{
    new dataDir[128];
    get_datadir(dataDir, charsmax(dataDir));
    formatex(g_zone_file_path, charsmax(g_zone_file_path), "%s/bhop_timer/%s_zones.json", dataDir, g_mapName);
    load_zone();
}

stock EmbeddedZonesClientInit(id)
{
    g_player_editor[id][m_in_menu] = false;
    g_player_editor[id][m_catched_anchor] = 0;
    g_player_editor[id][m_marked_anchor] = 0;
    g_player_editor[id][m_last_zone] = -1;
    g_player_editor[id][m_selected_type] = -1;
    g_player_editor[id][m_grab_distance] = 0.0;
    g_player_editor[id][m_catched_vertex_index] = -1;
    g_player_editor[id][m_holding_use] = false;
    g_player_editor[id][m_use_hold_start] = 0.0;
    g_player_editor[id][m_last_aiming_state] = false;
    g_player_editor[id][m_last_menu_hash] = 0;
    g_player_editor[id][m_corner_mode] = false;
    g_player_editor[id][m_corner_a_set] = false;
    g_player_editor[id][m_corner_a][0] = 0.0;
    g_player_editor[id][m_corner_a][1] = 0.0;
    g_player_editor[id][m_corner_a][2] = 0.0;
    g_player_editor[id][m_corner_b][0] = 0.0;
    g_player_editor[id][m_corner_b][1] = 0.0;
    g_player_editor[id][m_corner_b][2] = 0.0;
    g_player_touch[id][m_touch_count] = 0;
}

stock EmbeddedZonesShutdown()
{
    if (g_zones == Invalid_Array)
        return;
    save_zone();
    new count = ArraySize(g_zones);
    for (new i = 0; i < count; i++)
    {
        new zoneData[zone_data_t];
        ArrayGetArray(g_zones, i, zoneData);
        if (zoneData[zd_vertices] != Invalid_Array) ArrayDestroy(zoneData[zd_vertices]);
        if (zoneData[zd_history] != Invalid_Array) ArrayDestroy(zoneData[zd_history]);
    }
    ArrayDestroy(g_zones);
    g_zones = Invalid_Array;
}

stock zone:sr_zone_register_type(const class_name[], const description[], const color[3], zone_visibility:visibility = ZONE_VISIBLE_NONE,
    const on_enter[] = "", const on_leave[] = "", const on_touch[] = "", const on_create[] = "", const on_delete[] = "")
{
    new callbackNames[CB_COUNT][64], callbacks[CB_COUNT];
    copy(callbackNames[CB_ENTER], charsmax(callbackNames[]), on_enter);
    copy(callbackNames[CB_LEAVE], charsmax(callbackNames[]), on_leave);
    copy(callbackNames[CB_TOUCH], charsmax(callbackNames[]), on_touch);
    copy(callbackNames[CB_CREATE], charsmax(callbackNames[]), on_create);
    copy(callbackNames[CB_DELETE], charsmax(callbackNames[]), on_delete);
    for (new i = 0; i < CB_COUNT; i++)
        callbacks[i] = callbackNames[i][0] ? get_func_id(callbackNames[i], g_embeddedZonePluginId) : -1;
    return zone:register_zone_type(class_name, description, color, visibility, g_embeddedZonePluginId, callbacks);
}

stock sr_zone_set_visibility(zone:z, zone_visibility:visibility) { set_type_visibility(_:z, visibility); }
stock zone_visibility:sr_zone_get_visibility(zone:z) { return get_type_visibility(_:z); }
stock bool:sr_zone_get_bounds_by_class(const className[], Float:mins[3], Float:maxs[3]) { return get_zone_bounds_by_class(className, mins, maxs); }

stock bool:sr_zone_is_point_in_class(const className[], const Float:point[3])
{
    new count = get_zones_count();
    for (new i = 0; i < count; i++)
    {
        new ent = get_zone_entity(i), currentClass[ZONE_MAX_CLASSNAME_LENGTH];
        if (!is_valid_ent(ent)) continue;
        get_entvar(ent, var_netname, currentClass, charsmax(currentClass));
        if (!equal(currentClass, className)) continue;
        if (is_polygon_zone(i) && point_in_polygon_zone(point, i)) return true;
        new Float:mins[3], Float:maxs[3];
        if (!is_polygon_zone(i) && get_zone_bounds(i, mins, maxs)
            && point[0] >= mins[0] && point[0] <= maxs[0]
            && point[1] >= mins[1] && point[1] <= maxs[1]
            && point[2] >= mins[2] && point[2] <= maxs[2]) return true;
    }
    return false;
}

stock bool:sr_zone_get_shape_json_by_class(const className[], output[], len) { return serialize_zone_shape_json_by_class(className, output, len); }
stock bool:sr_zone_upsert_aabb(const className[], const zoneId[], const Float:mins[3], const Float:maxs[3], bool:asPolygon = true) { return upsert_aabb_zone(className, zoneId, mins, maxs, asPolygon); }
stock bool:sr_zone_upsert_shape_json(const className[], const zoneId[], const shapeJson[]) { return upsert_shape_json_zone(className, zoneId, shapeJson); }
stock sr_zone_delete_by_class(const className[]) { delete_zones_by_class(className); }
stock sr_zone_save() { save_zone(); }
stock sr_zone_reload() { clear_zones(); load_zone(); }

public cmd_zone_save(player_id)
{
    if (!sr_has_zone_access(player_id)) return PLUGIN_HANDLED;
    save_zone();
    TimerChat(player_id, "Polygon zones ^x04saved^x01.");
    if (player_id > 0 && g_player_editor[player_id][m_in_menu]) handle_zone_menu_exit(player_id);
    return PLUGIN_HANDLED;
}

public cmd_zone_reload(player_id)
{
    if (!sr_has_zone_access(player_id)) return PLUGIN_HANDLED;
    clear_zones();
    load_zone();
    TimerChat(player_id, "Polygon zones ^x04reloaded^x01.");
    return PLUGIN_HANDLED;
}

public bool:sr_has_zone_access(player_id)
{
    if (player_id == 0) return true;
    if (!is_user_connected(player_id)) return false;
    new flagText[8], cvar = get_cvar_pointer("bhop_zone_admin_flag");
    if (cvar) get_pcvar_string(cvar, flagText, charsmax(flagText));
    if (!flagText[0]) copy(flagText, charsmax(flagText), "l");
    return (get_user_flags(player_id) & read_flags(flagText)) ? true : false;
}
