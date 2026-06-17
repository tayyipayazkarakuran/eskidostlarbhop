/**
 * @file storage.inc
 * @brief Manages zone data persistence, type definitions, and the history/undo system.
 *
 * Provides core data structures and storage operations for polygon and AABB zones.
 */

#if defined _storage_included
    #endinput
#endif
#define _storage_included

#include <engine>
#include <json>

// ============================================================================
// CONSTANTS & DEFINES
// ============================================================================

#define ZONE_DEFAULT_CLASSNAME "zone"
#define ANCHOR_CLASSNAME "zone_anchor"
#define HEIGHT_ANCHOR_CLASSNAME "zone_height_anchor"

#define ZONE_MAX_CLASSNAME_LENGTH 64
#define ZONE_MAX_DESCRIPTION_LENGTH 256

// maximum zones a player can touch simultaneously
#define MAX_ZONES_PER_PLAYER 16

// maximum vertices per polygon zone
#define MAX_POLYGON_VERTICES 32

// offset in game units, positive value shrinks the zone's detection area
#define ZONE_INTERSECTION_OFFSET 15.0

// offset in game units to keep anchors from touching walls during move
#define ANCHOR_COLLISION_OFFSET 1.1

#define DEFAULT_MINSIZE { -32.0, -32.0, -32.0 }
#define DEFAULT_MAXSIZE { 32.0, 32.0, 32.0 }

#define EXPAND_MODE_AIMED 0

// face identifiers for aimed expansion
#define FACE_MINUS_X 0  // west wall (-X)
#define FACE_PLUS_X  1  // east wall (+X)
#define FACE_MINUS_Y 2  // south wall (-Y)
#define FACE_PLUS_Y  3  // north wall (+Y)
#define FACE_MINUS_Z 4  // bottom face (-Z)
#define FACE_PLUS_Z  5  // top face (+Z)

// fixed expansion increment (1 unit)
#define EXPAND_INCREMENT 1.0

// seconds to hold +use before action
#define USE_HOLD_DELAY 0.1

// ============================================================================
// DATA STRUCTURES
// ============================================================================

// polygon vertex structure
enum _:vertex_data_t {
    Float:vd_x,
    Float:vd_y,
    Float:vd_z   // bottom Z position (individual per vertex)
};

// zone data structure
enum _:zone_data_t {
    zd_entity,                    // entity index
    Array:zd_vertices,            // array of vertex_data_t (for polygon zones)
    Float:zd_height,              // top Z position (single value for all vertices)
    bool:zd_is_polygon,           // true if polygon, false if legacy AABB
    Array:zd_history              // history for undo
};

// ============================================================================
// GLOBAL VARIABLES
// ============================================================================

new const g_zone_model[] = "sprites/white.spr";
new g_zone_file_path[256];
new g_zone_unique_id = 1;

// zone storage, array of zone_data_t struct
new Array:g_zones;

new g_sprite_line;

// ============================================================================
// ZONE TYPE REGISTRY
// ============================================================================

#define MAX_ZONE_TYPES 64

// Callback type indices
enum {
    CB_ENTER = 0,
    CB_LEAVE,
    CB_TOUCH,
    CB_CREATE, 
    CB_DELETE,
    CB_COUNT
};

/**
 * @brief Zone type definition registered by zone type plugins.
 */
enum _:zone_type_t {
    m_type_class[ZONE_MAX_CLASSNAME_LENGTH],
    m_type_description[ZONE_MAX_DESCRIPTION_LENGTH],
    m_type_color[3],
    m_type_plugin_id,                // Plugin that registered this type
    m_type_callbacks[CB_COUNT],      // Function IDs for callbacks (-1 = none)
    zone_visibility:m_type_visibility  // Current visibility mode
};

new g_zone_types[MAX_ZONE_TYPES][zone_type_t];
new g_zone_types_count = 0;
new Trie:g_zone_types_trie;


// ============================================================================
// PLAYER STATE STRUCTURES
// ============================================================================

/**
 * @brief Per-player editor state.
 */
enum _:player_editor_state_t {
    m_selected_type,              // currently selected zone type (-1 = none)
    m_last_zone,                  // last selected zone index (-1 = none)
    m_catched_anchor,             // anchor entity being dragged (0 = none)
    m_marked_anchor,              // anchor entity being hovered (0 = none)
    m_catched_vertex_index,       // vertex index of dragged anchor (-1 = none)
    Float:m_grab_distance,        // distance to grabbed anchor
    bool:m_in_menu,               // is player in zone menu
    bool:m_holding_use,           // is holding +use while dragging
    Float:m_use_hold_start,       // when +use was pressed
    bool:m_last_aiming_state,     // was aiming at zone last frame
    m_last_menu_hash              // hash for menu refresh detection
};

/**
 * @brief Per-player zone touch tracking.
 */
enum _:player_touch_t {
    m_touch_zones[MAX_ZONES_PER_PLAYER],  // entity indices of touched zones
    m_touch_count                          // number of zones currently touched
};

new g_player_editor[MAX_PLAYERS + 1][player_editor_state_t];
new g_player_touch[MAX_PLAYERS + 1][player_touch_t];

// if player is currently on editor mode
new bool:g_editor_mode_active = false;

// forwards
new g_fw_on_start_touch;
new g_fw_on_stop_touch;
new g_fw_on_touch;
new g_fw_on_create;
new g_fw_on_delete;
new g_fw_on_save;

// ============================================================================
// ZONE ACCESSOR FUNCTIONS
// ============================================================================

/**
 * @brief Returns the total number of zones currently loaded.
 * @return Number of zones in the global zone array.
 */
stock get_zones_count()
{
    return ArraySize(g_zones);
}

/**
 * @brief Gets the entity index for a zone.
 * @param[in] zone_index Index of the zone in the global array.
 * @return Entity index, or 0 if zone_index is invalid.
 */
stock get_zone_entity(zone_index)
{
    if (zone_index < 0 || zone_index >= get_zones_count())
        return 0;
    
    new zone_data[zone_data_t];
    ArrayGetArray(g_zones, zone_index, zone_data);
    return zone_data[zd_entity];
}

/**
 * @brief Finds the zone index for a given entity.
 * @param[in] ent Entity index to search for.
 * @return Zone index, or -1 if not found.
 */
stock get_zone_index_by_entity(ent)
{
    new zone_count = get_zones_count();
    for (new i = 0; i < zone_count; i++) {
        if (get_zone_entity(i) == ent)
            return i;
    }
    return -1;
}

/**
 * @brief Checks if a zone is a polygon zone (vs legacy AABB).
 * @param[in] zone_index Index of the zone.
 * @return true if polygon zone, false if AABB or invalid.
 */
stock bool:is_polygon_zone(zone_index)
{
    if (zone_index < 0 || zone_index >= get_zones_count())
        return false;
    
    new zone_data[zone_data_t];
    ArrayGetArray(g_zones, zone_index, zone_data);
    return zone_data[zd_is_polygon];
}

/**
 * @brief Gets the number of vertices in a polygon zone.
 * @param[in] zone_index Index of the zone.
 * @return Number of vertices, or 0 if invalid or not a polygon.
 */
stock get_vertex_count(zone_index)
{
    if (zone_index < 0 || zone_index >= get_zones_count())
        return 0;
    
    new zone_data[zone_data_t];
    ArrayGetArray(g_zones, zone_index, zone_data);
    
    if (zone_data[zd_vertices] == Invalid_Array)
        return 0;
    
    return ArraySize(zone_data[zd_vertices]);
}

/**
 * @brief Gets the position of a vertex in a polygon zone.
 * @param[in] zone_index Index of the zone.
 * @param[in] vertex_index Index of the vertex.
 * @param[out] vertex Output array for vertex position {x, y, z}.
 * @return true on success, false on failure.
 */
stock bool:get_vertex(zone_index, vertex_index, Float:vertex[3])
{
    if (zone_index < 0 || zone_index >= get_zones_count())
        return false;

    new zone_data[zone_data_t];
    ArrayGetArray(g_zones, zone_index, zone_data);

    if (zone_data[zd_vertices] == Invalid_Array)
        return false;

    if (vertex_index < 0 || vertex_index >= ArraySize(zone_data[zd_vertices]))
        return false;

    new vertex_data[vertex_data_t];
    ArrayGetArray(zone_data[zd_vertices], vertex_index, vertex_data);

    vertex[0] = vertex_data[vd_x];
    vertex[1] = vertex_data[vd_y];
    vertex[2] = vertex_data[vd_z];

    return true;
}

/**
 * @brief Sets the position of a vertex in a polygon zone.
 * @param[in] zone_index Index of the zone.
 * @param[in] vertex_index Index of the vertex.
 * @param[in] vertex New vertex position {x, y, z}.
 * @return true on success, false on failure.
 */
stock bool:set_vertex(zone_index, vertex_index, const Float:vertex[3])
{
    if (zone_index < 0 || zone_index >= get_zones_count())
        return false;

    new zone_data[zone_data_t];
    ArrayGetArray(g_zones, zone_index, zone_data);

    if (zone_data[zd_vertices] == Invalid_Array)
        return false;

    if (vertex_index < 0 || vertex_index >= ArraySize(zone_data[zd_vertices]))
        return false;

    new vertex_data[vertex_data_t];
    vertex_data[vd_x] = vertex[0];
    vertex_data[vd_y] = vertex[1];
    vertex_data[vd_z] = vertex[2];

    ArraySetArray(zone_data[zd_vertices], vertex_index, vertex_data);
    ArraySetArray(g_zones, zone_index, zone_data);

    return true;
}

/**
 * @brief Gets the top Z coordinate of a polygon zone.
 * @param[in] zone_index Index of the zone.
 * @return Zone height (top Z), or 0.0 if invalid.
 */
stock Float:get_zone_height(zone_index)
{
    if (zone_index < 0 || zone_index >= get_zones_count())
        return 0.0;
    
    new zone_data[zone_data_t];
    ArrayGetArray(g_zones, zone_index, zone_data);
    return zone_data[zd_height];
}

/**
 * @brief Sets the top Z coordinate of a polygon zone.
 * @param[in] zone_index Index of the zone.
 * @param[in] height New height value.
 * @return true on success, false on failure.
 */
stock bool:set_zone_height(zone_index, Float:height)
{
    if (zone_index < 0 || zone_index >= get_zones_count())
        return false;

    new zone_data[zone_data_t];
    ArrayGetArray(g_zones, zone_index, zone_data);
    zone_data[zd_height] = height;
    ArraySetArray(g_zones, zone_index, zone_data);

    return true;
}

/**
 * @brief Inserts a new vertex into a polygon zone after the specified index.
 * @param[in] zone_index Index of the zone.
 * @param[in] after_index Index after which to insert the new vertex.
 * @param[in] vertex Position of the new vertex {x, y, z}.
 * @return Index of the new vertex, or -1 on failure.
 */
stock add_vertex_after(zone_index, after_index, const Float:vertex[3])
{
    if (zone_index < 0 || zone_index >= get_zones_count())
        return -1;
    
    new zone_data[zone_data_t];
    ArrayGetArray(g_zones, zone_index, zone_data);
    
    if (zone_data[zd_vertices] == Invalid_Array)
        return -1;
    
    new vertex_count = ArraySize(zone_data[zd_vertices]);
    if (vertex_count >= MAX_POLYGON_VERTICES)
        return -1;  // max vertices reached
    
    new vertex_data[vertex_data_t];
    vertex_data[vd_x] = vertex[0];
    vertex_data[vd_y] = vertex[1];
    vertex_data[vd_z] = vertex[2];
    
    new new_index = after_index + 1;
    if (new_index >= vertex_count) {
        // append at end
        ArrayPushArray(zone_data[zd_vertices], vertex_data);
        new_index = vertex_count;
    } else {
        // insert at position
        ArrayInsertArrayAfter(zone_data[zd_vertices], after_index, vertex_data);
    }
    
    ArraySetArray(g_zones, zone_index, zone_data);
    
    return new_index;
}

/**
 * @brief Calculates the axis-aligned bounding box for a polygon zone.
 * @param[in] zone_index Index of the zone.
 * @param[out] mins Output minimum bounds {x, y, z}.
 * @param[out] maxs Output maximum bounds {x, y, z}.
 * @return true on success, false on failure.
 */
stock bool:calculate_polygon_bounds(zone_index, Float:mins[3], Float:maxs[3])
{
    if (zone_index < 0 || zone_index >= get_zones_count())
        return false;

    new vertex_count = get_vertex_count(zone_index);
    if (vertex_count < 3)
        return false;

    new Float:vertex[3];
    get_vertex(zone_index, 0, vertex);

    mins[0] = maxs[0] = vertex[0];
    mins[1] = maxs[1] = vertex[1];
    mins[2] = vertex[2];  // bottom Z

    for (new i = 1; i < vertex_count; i++) {
        get_vertex(zone_index, i, vertex);

        mins[0] = floatmin(mins[0], vertex[0]);
        mins[1] = floatmin(mins[1], vertex[1]);
        mins[2] = floatmin(mins[2], vertex[2]);

        maxs[0] = floatmax(maxs[0], vertex[0]);
        maxs[1] = floatmax(maxs[1], vertex[1]);
    }

    // top Z is stored separately
    maxs[2] = get_zone_height(zone_index);

    return true;
}

/**
 * @brief Updates the entity bounding box to match the polygon vertices.
 * @param[in] zone_index Index of the zone to update.
 */
stock update_polygon_entity_bounds(zone_index)
{
    new ent = get_zone_entity(zone_index);
    if (!is_valid_ent(ent))
        return;
    
    new Float:mins[3], Float:maxs[3];
    if (!calculate_polygon_bounds(zone_index, mins, maxs))
        return;
    
    // calculate center
    new Float:origin[3];
    origin[0] = (mins[0] + maxs[0]) / 2.0;
    origin[1] = (mins[1] + maxs[1]) / 2.0;
    origin[2] = (mins[2] + maxs[2]) / 2.0;
    
    // calculate relative bounds
    new Float:rel_mins[3], Float:rel_maxs[3];
    xs_vec_sub(mins, origin, rel_mins);
    xs_vec_sub(maxs, origin, rel_maxs);
    
    entity_set_origin(ent, origin);
    entity_set_size(ent, rel_mins, rel_maxs);
    engfunc(EngFunc_SetOrigin, ent, origin);
}

stock get_zone_index_by_class(const class_name[])
{
    new zone_count = get_zones_count();
    for (new i = 0; i < zone_count; i++)
    {
        new ent = get_zone_entity(i);
        if (!is_valid_ent(ent))
            continue;

        new current_class[ZONE_MAX_CLASSNAME_LENGTH];
        get_entvar(ent, var_netname, current_class, charsmax(current_class));
        if (equal(current_class, class_name))
            return i;
    }

    return -1;
}

stock bool:get_zone_bounds(zone_index, Float:mins[3], Float:maxs[3])
{
    if (zone_index < 0 || zone_index >= get_zones_count())
        return false;

    if (is_polygon_zone(zone_index))
        return calculate_polygon_bounds(zone_index, mins, maxs);

    new ent = get_zone_entity(zone_index);
    if (!is_valid_ent(ent))
        return false;

    get_entvar(ent, var_absmin, mins);
    get_entvar(ent, var_absmax, maxs);
    return true;
}

stock bool:get_zone_bounds_by_class(const class_name[], Float:mins[3], Float:maxs[3])
{
    new zone_index = get_zone_index_by_class(class_name);
    if (zone_index == -1)
        return false;

    return get_zone_bounds(zone_index, mins, maxs);
}

stock delete_zones_by_class(const class_name[])
{
    for (new i = get_zones_count() - 1; i >= 0; i--)
    {
        new ent = get_zone_entity(i);
        if (!is_valid_ent(ent))
            continue;

        new current_class[ZONE_MAX_CLASSNAME_LENGTH];
        get_entvar(ent, var_netname, current_class, charsmax(current_class));
        if (equal(current_class, class_name))
            remove_zone(i, 0);
    }
}

stock clear_zones()
{
    for (new i = get_zones_count() - 1; i >= 0; i--)
    {
        remove_zone(i, 0);
    }
}

stock bool:upsert_aabb_zone(const class_name[], const zone_id[], const Float:mins[3], const Float:maxs[3], bool:as_polygon = true)
{
    delete_zones_by_class(class_name);

    new Float:origin[3], Float:rel_mins[3], Float:rel_maxs[3];
    for (new i = 0; i < 3; i++)
    {
        origin[i] = (mins[i] + maxs[i]) / 2.0;
        rel_mins[i] = mins[i] - origin[i];
        rel_maxs[i] = maxs[i] - origin[i];
    }

    create_zone(class_name, zone_id, origin, rel_mins, rel_maxs, 0, as_polygon);
    return true;
}

stock bool:create_polygon_zone_from_vertices(const class_name[], const zone_id[], Array:vertices, Float:height)
{
    if (vertices == Invalid_Array || ArraySize(vertices) < 3)
        return false;

    new Float:mins[3], Float:maxs[3], Float:vertex[3];
    ArrayGetArray(vertices, 0, vertex);
    mins[0] = maxs[0] = vertex[0];
    mins[1] = maxs[1] = vertex[1];
    mins[2] = vertex[2];

    for (new i = 1; i < ArraySize(vertices); i++)
    {
        ArrayGetArray(vertices, i, vertex);
        mins[0] = floatmin(mins[0], vertex[0]);
        mins[1] = floatmin(mins[1], vertex[1]);
        mins[2] = floatmin(mins[2], vertex[2]);
        maxs[0] = floatmax(maxs[0], vertex[0]);
        maxs[1] = floatmax(maxs[1], vertex[1]);
    }

    if (height <= mins[2])
        height = mins[2] + 72.0;
    maxs[2] = height;

    new Float:center[3], Float:rel_mins[3], Float:rel_maxs[3];
    for (new i = 0; i < 3; i++)
    {
        center[i] = (mins[i] + maxs[i]) / 2.0;
        rel_mins[i] = mins[i] - center[i];
        rel_maxs[i] = maxs[i] - center[i];
    }

    delete_zones_by_class(class_name);

    new ent = create_entity("info_target");
    entity_set_string(ent, EV_SZ_classname, ZONE_DEFAULT_CLASSNAME);
    set_entvar(ent, var_netname, class_name);
    set_entvar(ent, var_message, zone_id);

    DispatchSpawn(ent);
    entity_set_model(ent, g_zone_model);
    set_entvar(ent, var_effects, EF_NODRAW);
    set_entvar(ent, var_solid, SOLID_TRIGGER);
    set_entvar(ent, var_movetype, MOVETYPE_NONE);
    set_entvar(ent, var_enemy, 1);
    set_entvar(ent, var_nextthink, get_gametime() + 0.1);

    entity_set_origin(ent, center);
    entity_set_size(ent, rel_mins, rel_maxs);

    new zone_index = add_zone(ent, 0, vertices, height);
    zone_history_push(zone_index);

    new ret;
    fire_type_callback(class_name, CB_CREATE, ent);
    ExecuteForward(g_fw_on_create, ret, ent, class_name);
    return true;
}

stock bool:serialize_zone_shape_json(zone_index, output[], len)
{
    if (len <= 0 || zone_index < 0 || zone_index >= get_zones_count())
        return false;

    output[0] = EOS;
    new used;

    if (is_polygon_zone(zone_index))
    {
        new vertex_count = get_vertex_count(zone_index);
        if (vertex_count < 3)
            return false;

        used += formatex(output[used], len - used, "{^"version^":1,^"polygon^":true,^"height^":%.3f,^"vertices^":[", get_zone_height(zone_index));

        for (new i = 0; i < vertex_count && used < len - 1; i++)
        {
            new Float:vertex[3];
            get_vertex(zone_index, i, vertex);
            used += formatex(output[used], len - used, "%s{^"x^":%.3f,^"y^":%.3f,^"z^":%.3f}", i ? "," : "", vertex[0], vertex[1], vertex[2]);
        }

        if (used < len - 1)
            formatex(output[used], len - used, "]}");

        return true;
    }

    new Float:mins[3], Float:maxs[3];
    if (!get_zone_bounds(zone_index, mins, maxs))
        return false;

    formatex(output, len,
        "{^"version^":1,^"polygon^":false,^"min^":{^"x^":%.3f,^"y^":%.3f,^"z^":%.3f},^"max^":{^"x^":%.3f,^"y^":%.3f,^"z^":%.3f}}",
        mins[0], mins[1], mins[2], maxs[0], maxs[1], maxs[2]);
    return true;
}

stock bool:serialize_zone_shape_json_by_class(const class_name[], output[], len)
{
    new zone_index = get_zone_index_by_class(class_name);
    if (zone_index == -1)
        return false;

    return serialize_zone_shape_json(zone_index, output, len);
}

// ============================================================================
// ZONE MANAGEMENT
// ============================================================================

/**
 * @brief Adds a new zone to the global zone array.
 * @param[in] ent Entity index for the zone.
 * @param[in] player_id Player ID who created the zone.
 * @param[in] vertices Array of vertices for polygon zones (Invalid_Array for AABB).
 * @param[in] height Top Z coordinate for polygon zones.
 * @return Index of the newly created zone.
 */
stock add_zone(ent, player_id, Array:vertices = Invalid_Array, Float:height = 0.0)
{
    new zone_data[zone_data_t];
    zone_data[zd_entity] = ent;
    zone_data[zd_is_polygon] = (vertices != Invalid_Array && ArraySize(vertices) > 0);
    zone_data[zd_history] = ArrayCreate(3);
    
    if (zone_data[zd_is_polygon]) {
        zone_data[zd_vertices] = vertices;
        zone_data[zd_height] = height;
    } else {
        zone_data[zd_vertices] = Invalid_Array;
        zone_data[zd_height] = 0.0;
    }
    
    new index = ArrayPushArray(g_zones, zone_data);
    g_player_editor[player_id][m_last_zone] = index;
    
    return index;
}

/**
 * @brief Removes a zone and cleans up associated resources.
 * @param[in] num Zone index to remove.
 * @param[in] player_id Player ID performing the removal.
 */
stock remove_zone(num, player_id = 0)
{
    if(num < 0 || num >= get_zones_count())
        return;
    
    new zone_data[zone_data_t];
    ArrayGetArray(g_zones, num, zone_data);
    
    new ent = zone_data[zd_entity];
    
    new sz_class[32]; 
    get_entvar(ent, var_netname, sz_class, charsmax(sz_class));
    
    new i_ret;
    fire_type_callback(sz_class, CB_DELETE, ent);
    ExecuteForward(g_fw_on_delete, i_ret, ent, sz_class);
            
    remove_zone_anchors(num);
    
    // clean up arrays
    if (zone_data[zd_vertices] != Invalid_Array)
        ArrayDestroy(zone_data[zd_vertices]);
    if (zone_data[zd_history] != Invalid_Array)
        ArrayDestroy(zone_data[zd_history]);
    
    remove_entity(ent);
    
    // remove from array
    ArrayDeleteItem(g_zones, num);
    
    // update all player references
    for (new i = 1; i <= MAX_PLAYERS; i++) {
        if (g_player_editor[i][m_last_zone] == num)
            g_player_editor[i][m_last_zone] = -1;
        else if (g_player_editor[i][m_last_zone] > num)
            g_player_editor[i][m_last_zone]--;
    }
    
    g_player_editor[player_id][m_marked_anchor] = 0;
    g_player_editor[player_id][m_catched_anchor] = 0;
}

// ============================================================================
// HISTORY SYSTEM
// ============================================================================

/**
 * @brief Pushes the current zone state onto the undo history stack.
 * @param[in] zone_index Index of the zone to save state for.
 */
stock zone_history_push(zone_index)
{
    if (zone_index < 0 || zone_index >= get_zones_count())
        return;
    
    new zone_data[zone_data_t];
    ArrayGetArray(g_zones, zone_index, zone_data);
    
    if (zone_data[zd_history] == Invalid_Array)
        return;
    
    new ent = zone_data[zd_entity];
    new Float:f_vec[3];

    // for polygon zones, save all vertices and height
    if (zone_data[zd_is_polygon]) {
        // save vertex count as first entry
        new vertex_count = get_vertex_count(zone_index);
        f_vec[0] = float(vertex_count);
        f_vec[1] = zone_data[zd_height];
        f_vec[2] = 0.0;
        ArrayPushArray(zone_data[zd_history], f_vec);
        
        // save all vertices
        for (new i = 0; i < vertex_count; i++) {
            get_vertex(zone_index, i, f_vec);
            ArrayPushArray(zone_data[zd_history], f_vec);
        }
    } else {
        // legacy AABB - save absmin and absmax
        get_entvar(ent, var_absmin, f_vec);
        ArrayPushArray(zone_data[zd_history], f_vec);

        get_entvar(ent, var_absmax, f_vec);
        ArrayPushArray(zone_data[zd_history], f_vec);
    }
    
    ArraySetArray(g_zones, zone_index, zone_data);
}

/**
 * @brief Pops the most recent state from history and restores it.
 * @param[in] zone_index Index of the zone to restore.
 * @return true on success, false if history is empty or invalid.
 */
stock bool:zone_history_pop(zone_index)
{
    if (zone_index < 0 || zone_index >= get_zones_count())
        return false;

    new zone_data[zone_data_t];
    ArrayGetArray(g_zones, zone_index, zone_data);

    if (zone_data[zd_history] == Invalid_Array)
        return false;

    new i_size = ArraySize(zone_data[zd_history]);
    if (i_size < 2)
        return false;

    if (zone_data[zd_is_polygon]) {
        // find the start of the last state
        // work backwards: first find how many vertices the last state had
        new Float:header[3];

        // find the last header (entry where [2] == 0 and [0] looks like a count)
        new header_pos = -1;
        for (new i = i_size - 1; i >= 0; i--) {
            ArrayGetArray(zone_data[zd_history], i, header);
            new possible_count = floatround(header[0]);
            // check if this could be a header (has valid vertex count following it)
            if (i + possible_count < i_size && possible_count >= 3 && possible_count <= MAX_POLYGON_VERTICES) {
                header_pos = i;
                break;
            }
        }

        if (header_pos == -1)
            return false;
        
        // get header info
        ArrayGetArray(zone_data[zd_history], header_pos, header);
        new vertex_count = floatround(header[0]);
        new Float:height = header[1];
        
        // restore height
        zone_data[zd_height] = height;
        
        // restore vertices
        new Float:vertex[3];
        for (new i = 0; i < vertex_count; i++) {
            ArrayGetArray(zone_data[zd_history], header_pos + 1 + i, vertex);
            set_vertex(zone_index, i, vertex);
        }

        // trim extra vertices if current count is greater than restored count
        new current_count = ArraySize(zone_data[zd_vertices]);
        for (new i = current_count - 1; i >= vertex_count; i--) {
            ArrayDeleteItem(zone_data[zd_vertices], i);
        }

        // remove popped entries
        for (new i = header_pos + vertex_count; i >= header_pos; i--) {
            ArrayDeleteItem(zone_data[zd_history], i);
        }
        
        ArraySetArray(g_zones, zone_index, zone_data);
        update_polygon_entity_bounds(zone_index);
        
        // recreate anchors
        remove_zone_anchors(zone_index);
        create_zone_anchors(zone_index);
    } else {
        // legacy AABB
        new Float:f_mins[3], Float:f_maxs[3];
        
        ArrayGetArray(zone_data[zd_history], i_size-1, f_maxs);
        ArrayGetArray(zone_data[zd_history], i_size-2, f_mins);
        
        ArrayDeleteItem(zone_data[zd_history], i_size-1);
        ArrayDeleteItem(zone_data[zd_history], i_size-2);
        
        ArraySetArray(g_zones, zone_index, zone_data);
        
        update_zone_size(zone_index, f_maxs, f_mins);
    }

    return true;
}

// ============================================================================
// TYPE SYSTEM
// ============================================================================

/**
 * @brief Initializes the zone type registry (call in plugin_init).
 */
stock types_init()
{
    g_zone_types_trie = TrieCreate();
}

/**
 * @brief Registers a new zone type from an external plugin.
 * @param[in] class_name Zone class identifier.
 * @param[in] description Human-readable description.
 * @param[in] color RGB color array.
 * @param[in] visibility Initial visibility flags.
 * @param[in] plugin_id ID of the registering plugin.
 * @param[in] callbacks Array of callback function IDs.
 * @return Type index on success, -1 if max types reached or duplicate.
 */
stock register_zone_type(const class_name[], const description[], const color[3], zone_visibility:visibility, plugin_id, const callbacks[CB_COUNT])
{
    if (g_zone_types_count >= MAX_ZONE_TYPES)
        return -1;
    
    // Check for duplicate
    if (TrieKeyExists(g_zone_types_trie, class_name))
        return -1;
    
    new type_index = g_zone_types_count;
    
    copy(g_zone_types[type_index][m_type_class], ZONE_MAX_CLASSNAME_LENGTH - 1, class_name);
    copy(g_zone_types[type_index][m_type_description], ZONE_MAX_DESCRIPTION_LENGTH - 1, description);
    g_zone_types[type_index][m_type_color][0] = color[0];
    g_zone_types[type_index][m_type_color][1] = color[1];
    g_zone_types[type_index][m_type_color][2] = color[2];
    g_zone_types[type_index][m_type_plugin_id] = plugin_id;
    g_zone_types[type_index][m_type_visibility] = visibility;
    
    for (new i = 0; i < CB_COUNT; i++)
        g_zone_types[type_index][m_type_callbacks][i] = callbacks[i];
    
    TrieSetCell(g_zone_types_trie, class_name, type_index);
    g_zone_types_count++;
    
    return type_index;
}

/**
 * @brief Fires a callback for a zone type.
 * @param[in] class_name Zone class name.
 * @param[in] cb_type Callback type (CB_ENTER, CB_LEAVE, etc.).
 * @param[in] zd_entity Zone entity index.
 * @param[in] player_id Player ID (0 for create/delete callbacks).
 */
stock fire_type_callback(const class_name[], cb_type, ent, player_id = 0)
{
    new type_index;
    if (!TrieGetCell(g_zone_types_trie, class_name, type_index))
        return;
    
    new func_id = g_zone_types[type_index][m_type_callbacks][cb_type];
    if (func_id == -1)
        return;
    
    new plugin_id = g_zone_types[type_index][m_type_plugin_id];
    
    if (callfunc_begin_i(func_id, plugin_id) == 1)
    {
        callfunc_push_int(ent);
        if (cb_type != CB_CREATE && cb_type != CB_DELETE)
            callfunc_push_int(player_id);
        callfunc_end();
    }
}

/**
 * @brief Gets the type ID for a zone class name.
 * @param[in] sz_net_name Zone class name (e.g. "zone_start").
 * @return Type ID, or -1 if not found.
 */
stock get_type_id(const sz_net_name[])
{
    new i_type = -1;
    TrieGetCell(g_zone_types_trie, sz_net_name, i_type);
    return i_type;
}

/**
 * @brief Gets the display color for a zone entity.
 * @param[in] ent Entity index.
 * @param[out] i_color Output RGB color array {r, g, b}.
 * @return true on success, false if entity is invalid.
 */
stock bool:get_type_color(ent, i_color[3])
{
    if (!is_entity(ent))
        return false;

    new sz_net_name[32];
    get_entvar(ent, var_netname, sz_net_name, charsmax(sz_net_name));

    new i_type;
    if (TrieGetCell(g_zone_types_trie, sz_net_name, i_type)) {
        i_color[0] = g_zone_types[i_type][m_type_color][0];
        i_color[1] = g_zone_types[i_type][m_type_color][1];
        i_color[2] = g_zone_types[i_type][m_type_color][2];
    }
    else {
        // default color for unregistered types
        i_color[0] = 50;
        i_color[1] = 255;
        i_color[2] = 50;
    }

    return true;
}

/**
 * @brief Gets the visibility mode for a zone type.
 * @param[in] type_index Type index.
 * @return Visibility flags, or ZONE_VISIBLE_NONE if invalid.
 */
stock zone_visibility:get_type_visibility(type_index)
{
    if (type_index < 0 || type_index >= g_zone_types_count)
        return ZONE_VISIBLE_NONE;
    return g_zone_types[type_index][m_type_visibility];
}

/**
 * @brief Sets the visibility mode for a zone type.
 * @param[in] type_index Type index.
 * @param[in] visibility Visibility flags.
 */
stock set_type_visibility(type_index, zone_visibility:visibility)
{
    if (type_index < 0 || type_index >= g_zone_types_count)
        return;
    g_zone_types[type_index][m_type_visibility] = visibility;
}

// ============================================================================
// JSON UTILITIES
// ============================================================================

/**
 * @brief Sets a float value as a formatted string on a JSON object.
 * @param[in] json JSON object handle.
 * @param[in] key Key name.
 * @param[in] value Float value.
 * @param[in] precision Decimal precision (default 1).
 */
stock json_object_set_float(JSON:json, const key[], Float:value, precision = 1)
{
    new sz_value[32];
    switch (precision)
    {
        case 0: formatex(sz_value, charsmax(sz_value), "%.0f", value);
        case 1: formatex(sz_value, charsmax(sz_value), "%.1f", value);
        case 2: formatex(sz_value, charsmax(sz_value), "%.2f", value);
        default: formatex(sz_value, charsmax(sz_value), "%.3f", value);
    }
    json_object_set_string(json, key, sz_value);
}

/**
 * @brief Creates a JSON object from a Float[3] vector.
 * @param[in] vec Float vector array.
 * @return JSON object handle, or Invalid_JSON on failure.
 */
stock JSON:json_create_vec3(const Float:vec[3])
{
    new JSON:json = json_init_object();
    if (json == Invalid_JSON)
        return Invalid_JSON;
    
    json_object_set_float(json, "x", vec[0]);
    json_object_set_float(json, "y", vec[1]);
    json_object_set_float(json, "z", vec[2]);
    
    return json;
}

/**
 * @brief Parses a Float[3] vector from a JSON object.
 * @param[in] json JSON object handle.
 * @param[out] vec Output vector array.
 * @return true on success, false on failure.
 */
stock bool:json_parse_vec3(JSON:json, Float:vec[3])
{
    if (json == Invalid_JSON || !json_is_object(json))
        return false;
    
    new sz_value[32];
    
    if (json_object_get_string(json, "x", sz_value, charsmax(sz_value)))
        vec[0] = str_to_float(sz_value);
    
    if (json_object_get_string(json, "y", sz_value, charsmax(sz_value)))
        vec[1] = str_to_float(sz_value);
    
    if (json_object_get_string(json, "z", sz_value, charsmax(sz_value)))
        vec[2] = str_to_float(sz_value);
    
    return true;
}

stock Float:json_object_get_float_any(JSON:json, const key[], Float:default_value = 0.0)
{
    if (json == Invalid_JSON || !json_is_object(json))
        return default_value;

    new value[32];
    if (json_object_get_string(json, key, value, charsmax(value)))
        return str_to_float(value);

    return json_object_get_real(json, key);
}

stock bool:json_parse_vec3_any(JSON:json, Float:vec[3])
{
    if (json == Invalid_JSON || !json_is_object(json))
        return false;

    vec[0] = json_object_get_float_any(json, "x");
    vec[1] = json_object_get_float_any(json, "y");
    vec[2] = json_object_get_float_any(json, "z");
    return true;
}

stock bool:upsert_shape_json_zone(const class_name[], const zone_id[], const shape_json[])
{
    new JSON:root = json_parse(shape_json, false);
    if (root == Invalid_JSON || !json_is_object(root))
        return false;

    new bool:is_polygon = json_object_get_bool(root, "polygon", false);
    if (is_polygon)
    {
        new JSON:json_vertices = json_object_get_value(root, "vertices");
        if (!json_is_array(json_vertices))
        {
            json_free(root);
            return false;
        }

        new vertex_count = json_array_get_count(json_vertices);
        if (vertex_count < 3 || vertex_count > MAX_POLYGON_VERTICES)
        {
            json_free(json_vertices);
            json_free(root);
            return false;
        }

        new Array:vertices = ArrayCreate(vertex_data_t);
        for (new i = 0; i < vertex_count; i++)
        {
            new JSON:json_vertex = json_array_get_value(json_vertices, i);
            new Float:vertex[3];
            if (json_parse_vec3_any(json_vertex, vertex))
            {
                ArrayPushArray(vertices, vertex);
            }
            json_free(json_vertex);
        }

        new Float:height = json_object_get_float_any(root, "height");
        new bool:ok = create_polygon_zone_from_vertices(class_name, zone_id, vertices, height);
        if (!ok)
            ArrayDestroy(vertices);

        json_free(json_vertices);
        json_free(root);
        return ok;
    }

    new JSON:json_min = json_object_get_value(root, "min");
    new JSON:json_max = json_object_get_value(root, "max");
    new Float:mins[3], Float:maxs[3];
    new bool:ok = json_parse_vec3_any(json_min, mins) && json_parse_vec3_any(json_max, maxs);
    json_free(json_min);
    json_free(json_max);
    json_free(root);

    if (!ok)
        return false;

    return upsert_aabb_zone(class_name, zone_id, mins, maxs, true);
}

stock build_legacy_zone_file_path(output[], len)
{
    new map_name[32], data_dir[128];
    get_mapname(map_name, charsmax(map_name));
    get_datadir(data_dir, charsmax(data_dir));
    formatex(output, len, "%s/bhop_timer_%s_zones.ini", data_dir, map_name);
}

stock bool:get_legacy_name_for_class(const class_name[], output[], len)
{
    if (equal(class_name, "zone_start"))
    {
        copy(output, len, "start");
        return true;
    }

    if (equal(class_name, "zone_finish"))
    {
        copy(output, len, "finish");
        return true;
    }

    return false;
}

stock bool:get_class_for_legacy_name(const legacy_name[], output[], len)
{
    if (equal(legacy_name, "start"))
    {
        copy(output, len, "zone_start");
        return true;
    }

    if (equal(legacy_name, "finish"))
    {
        copy(output, len, "zone_finish");
        return true;
    }

    return false;
}

stock save_legacy_zone_mirror()
{
    new path[192];
    build_legacy_zone_file_path(path, charsmax(path));

    new fp = fopen(path, "wt");
    if (!fp)
    {
        log_amx("[speedrun_zone] Could not write legacy zone mirror: %s", path);
        return;
    }

    new zone_count = get_zones_count();
    for (new i = 0; i < zone_count; i++)
    {
        new ent = get_zone_entity(i);
        if (!is_valid_ent(ent))
            continue;

        new class_name[ZONE_MAX_CLASSNAME_LENGTH], legacy_name[16];
        get_entvar(ent, var_netname, class_name, charsmax(class_name));
        if (!get_legacy_name_for_class(class_name, legacy_name, charsmax(legacy_name)))
            continue;

        new Float:mins[3], Float:maxs[3];
        if (!get_zone_bounds(i, mins, maxs))
            continue;

        fprintf(fp, "%s %.3f %.3f %.3f %.3f %.3f %.3f^n",
            legacy_name,
            mins[0], mins[1], mins[2],
            maxs[0], maxs[1], maxs[2]);
    }

    fclose(fp);
}

stock bool:load_legacy_zone_file()
{
    new path[192];
    build_legacy_zone_file_path(path, charsmax(path));

    if (!file_exists(path))
        return false;

    new fp = fopen(path, "rt");
    if (!fp)
        return false;

    new line[192], loaded;
    while (!feof(fp))
    {
        fgets(fp, line, charsmax(line));
        trim(line);

        if (!line[0] || line[0] == ';' || line[0] == '#')
            continue;

        new legacy_name[16], min_x[24], min_y[24], min_z[24], max_x[24], max_y[24], max_z[24];
        parse(line,
            legacy_name, charsmax(legacy_name),
            min_x, charsmax(min_x),
            min_y, charsmax(min_y),
            min_z, charsmax(min_z),
            max_x, charsmax(max_x),
            max_y, charsmax(max_y),
            max_z, charsmax(max_z));

        new class_name[ZONE_MAX_CLASSNAME_LENGTH];
        if (!get_class_for_legacy_name(legacy_name, class_name, charsmax(class_name)))
            continue;

        new Float:mins[3], Float:maxs[3];
        mins[0] = str_to_float(min_x);
        mins[1] = str_to_float(min_y);
        mins[2] = str_to_float(min_z);
        maxs[0] = str_to_float(max_x);
        maxs[1] = str_to_float(max_y);
        maxs[2] = str_to_float(max_z);

        if (upsert_aabb_zone(class_name, legacy_name, mins, maxs, true))
            loaded++;
    }

    fclose(fp);
    return loaded > 0;
}

// ============================================================================
// SAVE / LOAD ZONES
// ============================================================================

/**
 * @brief Saves all zones to the map-specific JSON file.
 */
stock save_zone()
{
    new zone_count = get_zones_count();
    if(zone_count == 0)
    {
        save_legacy_zone_mirror();
        new ret;
        ExecuteForward(g_fw_on_save, ret);
        return;
    }

    new JSON:json_root = json_init_array();
    if (json_root == Invalid_JSON) {
        log_error(AMX_ERR_NATIVE, "Failed to initialize root JSON array for saving.");
        return;
    }

    new sz_type[32];
    new sz_id[32];

    for (new i = 0; i < zone_count; i++)
    {
        new zone_data[zone_data_t];
        ArrayGetArray(g_zones, i, zone_data);
        
        new ent = zone_data[zd_entity];
        if (!is_valid_ent(ent)) continue;

        get_entvar(ent, var_netname, sz_type, charsmax(sz_type));
        get_entvar(ent, var_message, sz_id, charsmax(sz_id));

        if (sz_type[0] == '^0') continue;

        new JSON:json_zone = json_init_object();
        if (json_zone == Invalid_JSON) continue;

        json_object_set_string(json_zone, "type", sz_type);
        json_object_set_string(json_zone, "id", sz_id);
        
        if (zone_data[zd_is_polygon]) {
            // save as polygon zone
            json_object_set_bool(json_zone, "polygon", true);
            
            // save height
            json_object_set_float(json_zone, "height", zone_data[zd_height]);
            
            // save vertices array
            new JSON:json_vertices = json_init_array();
            if (json_vertices != Invalid_JSON) {
                new vertex_count = ArraySize(zone_data[zd_vertices]);

                for (new v = 0; v < vertex_count; v++) {
                    new Float:vertex[3];
                    ArrayGetArray(zone_data[zd_vertices], v, vertex);

                    new JSON:json_vertex = json_create_vec3(vertex);
                    if (json_vertex != Invalid_JSON) {
                        json_array_append_value(json_vertices, json_vertex);
                        json_free(json_vertex);
                    }
                }

                json_object_set_value(json_zone, "vertices", json_vertices);
                json_free(json_vertices);
            }
        } else {
            // save as legacy AABB zone
            new Float:f_origin[3], Float:f_mins[3], Float:f_maxs[3];
            get_entvar(ent, var_origin, f_origin);
            get_entvar(ent, var_mins, f_mins);
            get_entvar(ent, var_maxs, f_maxs);

            // origin
            new JSON:json_origin = json_create_vec3(f_origin);
            if (json_origin != Invalid_JSON) {
                json_object_set_value(json_zone, "origin", json_origin);
                json_free(json_origin);
            }

            // min
            new JSON:json_mins = json_create_vec3(f_mins);
            if (json_mins != Invalid_JSON) {
                json_object_set_value(json_zone, "min", json_mins);
                json_free(json_mins);
            }

            // max
            new JSON:json_maxs = json_create_vec3(f_maxs);
            if (json_maxs != Invalid_JSON) {
                json_object_set_value(json_zone, "max", json_maxs);
                json_free(json_maxs);
            }
        }

        json_array_append_value(json_root, json_zone);
        json_free(json_zone);
    }

    if (!json_serial_to_file(json_root, g_zone_file_path, true))
    {
        log_error(AMX_ERR_NATIVE, "Failed to save zones to file: %s", g_zone_file_path);
    }

    json_free(json_root);
    save_legacy_zone_mirror();

    new ret;
    ExecuteForward(g_fw_on_save, ret);
}

/**
 * @brief Loads all zones from the map-specific JSON file.
 */
stock load_zone()
{
    if (!file_exists(g_zone_file_path))
    {
        if (load_legacy_zone_file())
        {
            log_amx("Loaded legacy bmod zone file and converted to polygon JSON: %s", g_zone_file_path);
            save_zone();
            return;
        }

        log_amx("No zone file found for this map: %s", g_zone_file_path);
        return;
    }

    new JSON:json_root = json_parse(g_zone_file_path, true);

    if (json_root == Invalid_JSON)
    {
        log_error(AMX_ERR_NATIVE, "Failed to parse zone file: %s", g_zone_file_path);
        return;
    }

    if (json_get_type(json_root) != JSONArray)
    {
        log_error(AMX_ERR_NATIVE, "Invalid format: root element in %s is not a JSON array", g_zone_file_path);
        json_free(json_root);
        return;
    }

    new zone_count = json_array_get_count(json_root);
    log_amx("Loading %d zones from %s", zone_count, g_zone_file_path);

    new sz_class[32];
    new sz_id[32];
    for (new i = 0; i < zone_count; i++)
    {
        new JSON:json_zone = json_array_get_value(json_root, i);

        if (!json_is_object(json_zone))
        {
            json_free(json_zone);
            continue;
        }

        json_object_get_string(json_zone, "type", sz_class, charsmax(sz_class));
        json_object_get_string(json_zone, "id", sz_id, charsmax(sz_id));

        if (sz_class[0] == '^0') {
            json_free(json_zone);
            continue;
        }

        // check if this is a polygon zone
        new bool:is_polygon = json_object_get_bool(json_zone, "polygon", false);
        
        if (is_polygon) {
            // load polygon zone
            new Float:height = json_object_get_float_any(json_zone, "height");
            
            new JSON:json_vertices = json_object_get_value(json_zone, "vertices");
            if (json_is_array(json_vertices)) {
                new vertex_count = json_array_get_count(json_vertices);
                
                if (vertex_count >= 3) {
                    new Array:vertices = ArrayCreate(vertex_data_t);
                    new Float:min_x = 999999.0, Float:max_x = -999999.0;
                    new Float:min_y = 999999.0, Float:max_y = -999999.0;
                    new Float:min_z = 999999.0;
                    
                    for (new v = 0; v < vertex_count; v++) {
                        new JSON:json_vertex = json_array_get_value(json_vertices, v);

                        new Float:vertex[3];
                        if (json_parse_vec3(json_vertex, vertex)) {
                            ArrayPushArray(vertices, vertex);

                            min_x = floatmin(min_x, vertex[0]);
                            max_x = floatmax(max_x, vertex[0]);
                            min_y = floatmin(min_y, vertex[1]);
                            max_y = floatmax(max_y, vertex[1]);
                            min_z = floatmin(min_z, vertex[2]);
                        }
                        json_free(json_vertex);
                    }
                    
                    // create entity with calculated bounds
                    new Float:center[3];
                    center[0] = (min_x + max_x) / 2.0;
                    center[1] = (min_y + max_y) / 2.0;
                    center[2] = (min_z + height) / 2.0;
                    
                    new Float:rel_mins[3], Float:rel_maxs[3];
                    rel_mins[0] = min_x - center[0];
                    rel_mins[1] = min_y - center[1];
                    rel_mins[2] = min_z - center[2];
                    rel_maxs[0] = max_x - center[0];
                    rel_maxs[1] = max_y - center[1];
                    rel_maxs[2] = height - center[2];
                    
                    new ent = create_entity("info_target");
                    entity_set_string(ent, EV_SZ_classname, ZONE_DEFAULT_CLASSNAME);
                    set_entvar(ent, var_netname, sz_class);
                    set_entvar(ent, var_message, sz_id);
                    
                    DispatchSpawn(ent);
                    entity_set_model(ent, g_zone_model);
                    
                    set_entvar(ent, var_effects, EF_NODRAW);
                    set_entvar(ent, var_solid, SOLID_TRIGGER);
                    set_entvar(ent, var_movetype, MOVETYPE_NONE);
                    set_entvar(ent, var_enemy, 1);
                    set_entvar(ent, var_nextthink, get_gametime() + 0.1);
                    
                    entity_set_origin(ent, center);
                    entity_set_size(ent, rel_mins, rel_maxs);
                    
                    // create zone data
                    new zone_data[zone_data_t];
                    zone_data[zd_entity] = ent;
                    zone_data[zd_vertices] = vertices;
                    zone_data[zd_height] = height;
                    zone_data[zd_is_polygon] = true;
                    zone_data[zd_history] = ArrayCreate(3);
                    
                    ArrayPushArray(g_zones, zone_data);
                    
                    new i_ret;
                    fire_type_callback(sz_class, CB_CREATE, ent);
                    ExecuteForward(g_fw_on_create, i_ret, ent, sz_class);
                }
            }
            json_free(json_vertices);
        } else {
            // load legacy AABB zone
            new Float:f_origin[3] = {0.0, 0.0, 0.0};
            new Float:f_mins[3] = DEFAULT_MINSIZE;
            new Float:f_maxs[3] = DEFAULT_MAXSIZE;

            // origin
            new JSON:json_origin = json_object_get_value(json_zone, "origin");
            json_parse_vec3(json_origin, f_origin);
            json_free(json_origin);

            // min
            new JSON:json_mins = json_object_get_value(json_zone, "min");
            json_parse_vec3(json_mins, f_mins);
            json_free(json_mins);

            // max
            new JSON:json_maxs = json_object_get_value(json_zone, "max");
            json_parse_vec3(json_maxs, f_maxs);
            json_free(json_maxs);

            // create zone - legacy zones load as AABB (not polygon)
            new ent = create_entity("info_target");
            entity_set_string(ent, EV_SZ_classname, ZONE_DEFAULT_CLASSNAME);
            set_entvar(ent, var_netname, sz_class);
            set_entvar(ent, var_message, sz_id);
            
            DispatchSpawn(ent);
            entity_set_model(ent, g_zone_model);
            
            set_entvar(ent, var_effects, EF_NODRAW);
            set_entvar(ent, var_solid, SOLID_TRIGGER);
            set_entvar(ent, var_movetype, MOVETYPE_NONE);
            set_entvar(ent, var_enemy, 1);
            set_entvar(ent, var_nextthink, get_gametime() + 0.1);
            
            entity_set_origin(ent, f_origin);
            entity_set_size(ent, f_mins, f_maxs);
            
            // create zone data - legacy AABB
            new zone_data[zone_data_t];
            zone_data[zd_entity] = ent;
            zone_data[zd_vertices] = Invalid_Array;
            zone_data[zd_height] = 0.0;
            zone_data[zd_is_polygon] = false;
            zone_data[zd_history] = ArrayCreate(3);
            
            ArrayPushArray(g_zones, zone_data);
            
            new i_ret;
            fire_type_callback(sz_class, CB_CREATE, ent);
            ExecuteForward(g_fw_on_create, i_ret, ent, sz_class);
        }

        json_free(json_zone);
    }

    json_free(json_root);
}
