/**
 * @file physics.inc
 * @brief Handles geometry calculations and player-zone collision detection.
 *
 * Tracks which zones each player is touching and fires touch events.
 */

#if defined _physics_included
    #endinput
#endif
#define _physics_included

/**
 * @brief Tests if a 2D point is inside a polygon zone using ray casting.
 *
 * Zone-aware wrapper for visual_point_in_polygon_2d that extracts vertex
 * data from zone storage and calls the visual library function.
 *
 * @param[in] test_x X coordinate of the point to test.
 * @param[in] test_y Y coordinate of the point to test.
 * @param[in] zone_index Index of the polygon zone to test against.
 * @return true if point is inside the polygon, false otherwise.
 */
stock bool:point_in_polygon_2d(Float:test_x, Float:test_y, zone_index)
{
    new vertex_count = get_vertex_count(zone_index);
    if (vertex_count < 3)
        return false;
    
    // extract vertices into array for visual library
    new Float:vertices[MAX_POLYGON_VERTICES][3];
    for (new i = 0; i < vertex_count; i++) {
        get_vertex(zone_index, i, vertices[i]);
    }
    
    // use visual library's generic implementation
    return visual_point_in_polygon_2d(test_x, test_y, vertices, vertex_count);
}

/**
 * @brief Tests if a 3D point is inside a polygon zone.
 *
 * Performs both Z bounds check and 2D polygon containment test.
 *
 * @param[in] point 3D point coordinates {x, y, z} to test.
 * @param[in] zone_index Index of the polygon zone to test against.
 * @return true if point is inside the zone, false otherwise.
 */
stock bool:point_in_polygon_zone(const Float:point[3], zone_index)
{
    if (!is_polygon_zone(zone_index))
        return false;
    
    // first check if point is within Z bounds
    new Float:min_z = 999999.0;
    new Float:vertex[3];
    new vertex_count = get_vertex_count(zone_index);
    
    for (new i = 0; i < vertex_count; i++) {
        get_vertex(zone_index, i, vertex);
        min_z = floatmin(min_z, vertex[2]);
    }
    
    new Float:max_z = get_zone_height(zone_index);
    
    if (point[2] < min_z || point[2] > max_z)
        return false;
    
    // then check 2D containment
    return point_in_polygon_2d(point[0], point[1], zone_index);
}

/**
 * @brief Tests if a player's bounding box intersects a polygon zone.
 *
 * Uses a quick AABB rejection test first, then tests center point and
 * corner points against the polygon with ZONE_INTERSECTION_OFFSET applied.
 *
 * @param[in] player_mins Player bounding box minimum coordinates {x, y, z}.
 * @param[in] player_maxs Player bounding box maximum coordinates {x, y, z}.
 * @param[in] zone_index Index of the polygon zone to test against.
 * @return true if player intersects the zone, false otherwise.
 */
stock bool:player_intersects_polygon_zone(const Float:player_mins[3], const Float:player_maxs[3], zone_index)
{
    // get zone bounds for quick AABB rejection test first
    new Float:zone_mins[3], Float:zone_maxs[3];
    if (!calculate_polygon_bounds(zone_index, zone_mins, zone_maxs))
        return false;
    
    // quick AABB rejection
    if (player_maxs[0] < zone_mins[0] || player_mins[0] > zone_maxs[0])
        return false;
    if (player_maxs[1] < zone_mins[1] || player_mins[1] > zone_maxs[1])
        return false;
    if (player_maxs[2] < zone_mins[2] || player_mins[2] > zone_maxs[2])
        return false;
    
    // apply offset (shrink detection area)
    new Float:offset = ZONE_INTERSECTION_OFFSET;
    
    // test center point
    new Float:center[3];
    center[0] = (player_mins[0] + player_maxs[0]) / 2.0;
    center[1] = (player_mins[1] + player_maxs[1]) / 2.0;
    center[2] = (player_mins[2] + player_maxs[2]) / 2.0;
    
    // check if center is in polygon (most common case)
    if (point_in_polygon_2d(center[0], center[1], zone_index)) {
        // also check Z bounds with offset
        new Float:min_z = zone_mins[2] + offset;
        new Float:max_z = zone_maxs[2] - offset;
        if (center[2] >= min_z && center[2] <= max_z)
            return true;
    }
    
    // test corners of player bounds (for edge cases)
    new Float:test_points[4][2];
    test_points[0][0] = player_mins[0] + offset;
    test_points[0][1] = player_mins[1] + offset;
    test_points[1][0] = player_maxs[0] - offset;
    test_points[1][1] = player_mins[1] + offset;
    test_points[2][0] = player_maxs[0] - offset;
    test_points[2][1] = player_maxs[1] - offset;
    test_points[3][0] = player_mins[0] + offset;
    test_points[3][1] = player_maxs[1] - offset;
    
    for (new i = 0; i < 4; i++) {
        if (point_in_polygon_2d(test_points[i][0], test_points[i][1], zone_index))
            return true;
    }
    
    return false;
}

// ============================================================================
// TOUCH TRACKING HELPERS
// ============================================================================

/**
 * @brief Checks if a player is currently touching a specific zone.
 * @param[in] player_id Player index to check.
 * @param[in] ent Zone entity index to check for.
 * @return true if player is touching the zone, false otherwise.
 */
stock bool:is_player_touching_zone(player_id, ent)
{
    for (new i = 0; i < g_player_touch[player_id][m_touch_count]; i++) {
        if (g_player_touch[player_id][m_touch_zones][i] == ent)
            return true;
    }

    return false;
}

/**
 * @brief Removes a zone from a player's touch list by array index.
 *
 * @param[in] player_id Player index.
 * @param[in] index Array index of the zone to remove from touch list.
 */
stock remove_touched_zone_by_index(player_id, index)
{
    if (index < 0 || index >= g_player_touch[player_id][m_touch_count])
        return;

    g_player_touch[player_id][m_touch_count]--;
    if (index < g_player_touch[player_id][m_touch_count]) {
        g_player_touch[player_id][m_touch_zones][index] = g_player_touch[player_id][m_touch_zones][g_player_touch[player_id][m_touch_count]];
    }
}

// ============================================================================
// TOUCH FORWARD EXECUTION
// ============================================================================

/**
 * @brief Fires a touch event for a zone.
 *
 * Calls the type-specific callback first, then the corresponding global forward.
 * Does nothing if editor mode is active.
 *
 * @param[in] zone_ent Zone entity index.
 * @param[in] player_id Player index involved in the touch event.
 * @param[in] cb_type Callback type: CB_ENTER, CB_LEAVE, or CB_TOUCH.
 */
stock fire_touch_event(zone_ent, player_id, cb_type)
{
    if (g_editor_mode_active)
        return;

    new sz_class[32];
    get_entvar(zone_ent, var_netname, sz_class, charsmax(sz_class));

    fire_type_callback(sz_class, cb_type, zone_ent, player_id);

    new ret;
    switch (cb_type) {
        case CB_ENTER: ExecuteForward(g_fw_on_start_touch, ret, zone_ent, player_id, sz_class);
        case CB_LEAVE: ExecuteForward(g_fw_on_stop_touch, ret, zone_ent, player_id, sz_class);
        case CB_TOUCH: ExecuteForward(g_fw_on_touch, ret, zone_ent, player_id, sz_class);
    }
}

