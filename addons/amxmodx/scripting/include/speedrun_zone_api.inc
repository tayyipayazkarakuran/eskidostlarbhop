/**
 * @file speedrun_zone_api.inc
 * @brief API for zone type plugins to register with the core zone system.
 * 
 * Zone types are self-contained plugins that register themselves with the core
 * zone system. Each type defines its class name, description, color, and
 * callbacks for zone events.
 * 
 * Example usage:
 * ```pawn
 * new Zone:g_zone;
 * 
 * public plugin_init()
 * {
 *     g_zone = sr_zone_register_type(
 *         .class_name = "zone_start",
 *         .description = "Starting zone",
 *         .color = {0, 255, 0},
 *         .on_enter = "on_enter",
 *         .on_leave = "on_leave"
 *     );
 *     sr_zone_set_visibility(g_zone, ZONE_VISIBLE_FULL);
 * }
 * 
 * public on_enter(zone_entity, player_id) { }
 * public on_leave(zone_entity, player_id) { }
 * ```
 */

#if defined _speedrun_zone_api_included
    #endinput
#endif
#define _speedrun_zone_api_included

// ============================================================================
// ZONE HANDLE
// ============================================================================

/**
 * Zone type handle returned by sr_zone_register_type().
 * Used for all subsequent operations on the registered type.
 */
enum zone {
    invalid_zone = -1
};

// ============================================================================
// VISIBILITY OPTIONS
// ============================================================================

/**
 * Zone visibility flags - can be combined with bitwise OR.
 */
enum zone_visibility (<<= 1) {
    ZONE_VISIBLE_NONE = 0,
    ZONE_VISIBLE_BOTTOM = 1,    // Show bottom wireframe
    ZONE_VISIBLE_TOP,           // Show top wireframe
    ZONE_VISIBLE_WALLS          // Show wall wireframes
};

#define ZONE_VISIBLE_FULL (ZONE_VISIBLE_BOTTOM | ZONE_VISIBLE_TOP | ZONE_VISIBLE_WALLS)

// ============================================================================
// REGISTRATION
// ============================================================================

/**
 * Registers a zone type with the core zone system.
 * 
 * @param class_name    Unique zone class identifier (example: "zone_start")
 * @param description   Human-readable description shown in the editor
 * @param color         RGB color array for zone rendering [r, g, b]
 * @param visibility    Initial visibility flags (default: ZONE_VISIBLE_NONE)
 * @param on_enter      Optional callback function name for when a player enters the zone
 * @param on_leave      Optional callback function name for when a player leaves the zone
 * @param on_touch      Optional callback function name for continuous touch (per frame)
 * @param on_create     Optional callback function name for when a zone is created
 * @param on_delete     Optional callback function name for when a zone is deleted
 * 
 * @return Zone handle on success, invalid_zone on failure
 * 
 * @note Callbacks are called ONLY for zones matching this type's class name.
 * @note Callback signatures:
 *       - on_enter(zone_entity, player_id)
 *       - on_leave(zone_entity, player_id)
 *       - on_touch(zone_entity, player_id)
 *       - on_create(zone_entity)
 *       - on_delete(zone_entity)
 */
native zone:sr_zone_register_type(
    const class_name[],
    const description[],
    const color[3],
    zone_visibility:visibility = ZONE_VISIBLE_NONE,
    const on_enter[] = "",
    const on_leave[] = "",
    const on_touch[] = "",
    const on_create[] = "",
    const on_delete[] = ""
);

// ============================================================================
// VISIBILITY CONTROL
// ============================================================================

/**
 * Sets the visibility mode for a zone type.
 * 
 * @param zone          Zone handle from sr_zone_register_type()
 * @param visibility    Visibility flags (ZONE_VISIBLE_* constants)
 * 
 * @noreturn
 */
native sr_zone_set_visibility(zone:z, zone_visibility:visibility);

/**
 * Gets the current visibility mode for a zone type.
 * 
 * @param zone          Zone handle from sr_zone_register_type()
 * 
 * @return Current visibility flags
 */
native zone_visibility:sr_zone_get_visibility(zone:z);

// ============================================================================
// BMOD INTEGRATION HELPERS
// ============================================================================

/**
 * Gets world-space bounds for the first zone matching class_name.
 */
native bool:sr_zone_get_bounds_by_class(const class_name[], Float:mins[3], Float:maxs[3]);

/**
 * Checks whether a world point is inside any zone matching class_name.
 */
native bool:sr_zone_is_point_in_class(const class_name[], const Float:point[3]);

/**
 * Serializes the first zone matching class_name into compact polygon/AABB JSON.
 */
native bool:sr_zone_get_shape_json_by_class(const class_name[], output[], len);

/**
 * Creates or replaces a zone from legacy min/max bounds.
 */
native bool:sr_zone_upsert_aabb(const class_name[], const zone_id[], const Float:mins[3], const Float:maxs[3], bool:as_polygon = true);

/**
 * Creates or replaces a zone from the compact polygon/AABB JSON used by bmod SQL storage.
 */
native bool:sr_zone_upsert_shape_json(const class_name[], const zone_id[], const shape_json[]);

/**
 * Deletes all zones matching class_name.
 */
native sr_zone_delete_by_class(const class_name[]);

/**
 * Saves currently loaded zones to disk.
 */
native sr_zone_save();

/**
 * Reloads zones from disk, clearing current zones first.
 */
native sr_zone_reload();

// ============================================================================
// GLOBAL FORWARDS
// ============================================================================

/**
 * Called when a player starts touching any zone.
 * 
 * @param zone_entity   Zone entity index
 * @param player_id     Player index
 * @param zone_class    Zone class name (example: "zone_start")
 * 
 * @return PLUGIN_CONTINUE to allow, PLUGIN_HANDLED to block
 */
forward sr_zone_start_touch(zone_entity, player_id, const zone_class[]);

/**
 * Called when a player stops touching any zone.
 * 
 * @param zone_entity   Zone entity index
 * @param player_id     Player index
 * @param zone_class    Zone class name
 * 
 * @return PLUGIN_CONTINUE to allow, PLUGIN_HANDLED to block
 */
forward sr_zone_stop_touch(zone_entity, player_id, const zone_class[]);

/**
 * Called every frame while a player is touching any zone.
 * 
 * @param zone_entity   Zone entity index
 * @param player_id     Player index
 * @param zone_class    Zone class name
 * 
 * @return PLUGIN_CONTINUE to allow, PLUGIN_HANDLED to block
 */
forward sr_zone_touch(zone_entity, player_id, const zone_class[]);

/**
 * Called when a new zone is created.
 * 
 * @param zone_entity   Zone entity index
 * @param zone_class    Zone class name
 * 
 * @return PLUGIN_CONTINUE to allow, PLUGIN_HANDLED to block
 */
forward sr_zone_created(zone_entity, const zone_class[]);

/**
 * Called when a zone is deleted.
 * 
 * @param zone_entity   Zone entity index
 * @param zone_class    Zone class name
 * 
 * @return PLUGIN_CONTINUE to allow, PLUGIN_HANDLED to block
 */
forward sr_zone_deleted(zone_entity, const zone_class[]);

/**
 * Called after zones are saved to disk.
 */
forward sr_zone_saved();
