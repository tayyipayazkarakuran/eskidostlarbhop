/**
 * @file visualization.inc
 * @brief Renders zone wireframes and anchor sprites in the game world.
 *
 * Visibility is determined by editor mode and registered zone type settings.
 */

#if defined _visualization_included
    #endinput
#endif
#define _visualization_included

// ============================================================================
// ZONE VISIBILITY
// ============================================================================

/**
 * @brief Checks if a zone should be displayed and gets its visibility mode.
 *
 * Uses registered zone type visibility. In editor mode, all zones are visible with full wireframe.
 *
 * @param[in] ent Zone entity index.
 * @param[in] sz_class Zone class name (netname).
 * @param[out] visibility Output visibility flags for the zone.
 * @return true if zone should be displayed, false otherwise.
 */
stock bool:_should_display_zone(ent, const sz_class[], &zone_visibility:visibility)
{
    #pragma unused ent  // reserved for future per-entity visibility overrides
    
    // in editor mode, always show all zones with full visibility
    if (g_editor_mode_active)
    {
        visibility = ZONE_VISIBLE_FULL;
        return true;
    }

    // check registered type visibility
    new type_index = get_type_id(sz_class);
    if (type_index != -1)
    {
        visibility = get_type_visibility(type_index);
        return (visibility != ZONE_VISIBLE_NONE);
    }

    // unregistered zone type - hide by default
    return false;
}

// ============================================================================
// ZONE THINK / VISUALIZATION
// ============================================================================

/**
 * @brief Think callback for zone entities, handles visualization updates.
 *
 * Called periodically by the engine. Determines if zone should be rendered
 * and delegates to _zone_think_draw. Think rate is faster in editor mode.
 *
 * @param[in] ent Zone entity index.
 */
public zone_think(ent)
{
    new sz_class[32];
    get_entvar(ent, var_netname, sz_class, charsmax(sz_class));

    new Float:f_next_think_delay;
    if (g_editor_mode_active) {
        f_next_think_delay = 0.1;
    } else {
        f_next_think_delay = 0.1;
    }

    new zone_visibility:visibility = ZONE_VISIBLE_NONE;
    if (_should_display_zone(ent, sz_class, visibility)) {
        _zone_think_draw(ent, visibility);
    }

    set_entvar(ent, var_nextthink, get_gametime() + f_next_think_delay);
}

/**
 * @brief Renders a zone's wireframe visualization.
 *
 * Draws polygon or AABB wireframe based on zone type. In editor mode,
 * also highlights the face the player is aiming at.
 *
 * @param[in] ent Zone entity index.
 * @param[in] visibility Visibility flags determining which faces to draw.
 */
stock _zone_think_draw(ent, zone_visibility:visibility)
{
    new zone_index = get_zone_index_by_entity(ent);
    if (zone_index == -1)
        return;
    
    new i_color[3];
    get_type_color(ent, i_color);
    
    if (is_polygon_zone(zone_index)) {
        // draw polygon zone
        draw_polygon_zone(zone_index, i_color, visibility);
        
        // highlight aimed face in editor mode
        if (g_editor_mode_active) {
            for (new player_id = 1; player_id <= get_maxplayers(); player_id++) {
                if (!is_user_connected(player_id) || !is_user_alive(player_id)) continue;
                if (is_valid_ent(g_player_editor[player_id][m_catched_anchor])) continue;

                new aimed_face = get_aimed_polygon_face(player_id, zone_index);
                if (aimed_face != POLYGON_FACE_NONE) {
                    new highlight_color[3] = {0, 255, 255};  // cyan
                    highlight_polygon_face(zone_index, aimed_face, highlight_color);
                }
            }
        }
    } else {
        // draw legacy AABB zone
        new Float:f_mins[3]; 
        get_entvar(ent, var_absmin, f_mins);
        new Float:f_maxs[3]; 
        get_entvar(ent, var_absmax, f_maxs);
        
        // Convert visibility enum to visual library params
        new bool:show_bottom = bool:(visibility & ZONE_VISIBLE_BOTTOM);
        new bool:show_top = bool:(visibility & ZONE_VISIBLE_TOP);
        new bool:show_walls = bool:(visibility & ZONE_VISIBLE_WALLS);
        
        // Match draw duration to think interval to avoid gaps (flicker) outside editor mode
        new duration = 1;
        
        visual_draw_wireframe_box(f_mins, f_maxs, i_color, duration, 5, show_walls, show_top, show_bottom, ANCHOR_COLLISION_OFFSET);
        
        // highlight aimed face in editor mode
        if (g_editor_mode_active) {
            for (new player_id = 1; player_id <= get_maxplayers(); player_id++) {
                if (!is_user_connected(player_id) || !is_user_alive(player_id)) continue;
                if (is_valid_ent(g_player_editor[player_id][m_catched_anchor])) continue;

                new aimed_face = get_aimed_zone_face(player_id, ent);
                if (aimed_face != -1) {
                    new highlight_color[3] = {0, 255, 255};
                    visual_highlight_face(f_mins, f_maxs, aimed_face, highlight_color, ANCHOR_COLLISION_OFFSET, .draw_center_x = true);
                }
            }
        }
    }
}

/**
 * @brief Draws a polygon zone's wireframe.
 *
 * Renders bottom edges, top edges, and vertical walls based on visibility flags.
 *
 * @param[in] zone_index Index of the polygon zone.
 * @param[in] i_color RGB color array for the wireframe.
 * @param[in] visibility Visibility flags determining which parts to draw.
 */
stock draw_polygon_zone(zone_index, const i_color[3], zone_visibility:visibility)
{
    new vertex_count = get_vertex_count(zone_index);
    if (vertex_count < 3)
        return;
    
    new Float:top_z = get_zone_height(zone_index);
    new duration_byte = g_editor_mode_active ? 1 : 3;
    
    new bool:show_bottom = bool:(visibility & ZONE_VISIBLE_BOTTOM);
    new bool:show_top = bool:(visibility & ZONE_VISIBLE_TOP);
    new bool:show_walls = bool:(visibility & ZONE_VISIBLE_WALLS);
    
    new Float:v1[3], Float:v2[3];
    new Float:v1_top[3], Float:v2_top[3];
    
    // draw edges based on visibility flags
    for (new i = 0; i < vertex_count; i++) {
        new next = (i + 1) % vertex_count;
        
        get_vertex(zone_index, i, v1);
        get_vertex(zone_index, next, v2);
        
        // bottom edge
        if (show_bottom) {
            visual_draw_wireframe_line(v1, v2, i_color, duration_byte);
        }
        
        // top edge
        if (show_top) {
            v1_top[0] = v1[0]; v1_top[1] = v1[1]; v1_top[2] = top_z;
            v2_top[0] = v2[0]; v2_top[1] = v2[1]; v2_top[2] = top_z;
            visual_draw_wireframe_line(v1_top, v2_top, i_color, duration_byte);
        }
        
        // vertical edge (wall)
        if (show_walls) {
            v1_top[0] = v1[0]; v1_top[1] = v1[1]; v1_top[2] = top_z;
            visual_draw_wireframe_line(v1, v1_top, i_color, duration_byte);
        }
    }
}

// ============================================================================
// ANCHOR THINK / ANIMATION
// ============================================================================

/**
 * @brief Think callback for anchor entities, handles scale animation.
 *
 * Called at high frequency (100Hz) to provide smooth anchor scaling animation.
 *
 * @param[in] ent Anchor entity index.
 */
public anchor_think(ent)
{
    if (!is_valid_ent(ent))
        return;

    animate_anchor_scale(ent);
    set_entvar(ent, var_nextthink, get_gametime() + 0.01);
}

/**
 * @brief Animates anchor sprite scale for smooth transitions.
 *
 * Uses entity vars to store animation state:
 * - var_scale: current scale
 * - var_fuser1: target scale
 * - var_fuser2: animation start time
 * - var_fuser3: animation start scale
 *
 * @param[in] ent Anchor entity index.
 */
stock animate_anchor_scale(ent)
{
    new Float:current_scale;
    get_entvar(ent, var_scale, current_scale);

    new Float:target_scale;
    get_entvar(ent, var_fuser1, target_scale);

    new Float:anim_start_time;
    get_entvar(ent, var_fuser2, anim_start_time);

    new Float:start_scale;
    get_entvar(ent, var_fuser3, start_scale);

    if (floatabs(current_scale - target_scale) > 0.001)
    {
        new Float:current_time = get_gametime();
        new Float:anim_duration = 0.1;

        if (anim_start_time == 0.0)
        {
            set_entvar(ent, var_fuser2, current_time);
            set_entvar(ent, var_fuser3, current_scale);
            anim_start_time = current_time;
            start_scale = current_scale;
        }

        new Float:elapsed = current_time - anim_start_time;
        new Float:progress = floatmin(elapsed / anim_duration, 1.0);

        new Float:new_scale = start_scale + (target_scale - start_scale) * progress;
        set_entvar(ent, var_scale, new_scale);

        if (progress >= 1.0)
        {
            set_entvar(ent, var_scale, target_scale);
            set_entvar(ent, var_fuser2, 0.0);
        }
    }
    else {
        set_entvar(ent, var_fuser2, 0.0);
    }
}

// ============================================================================
// POLYGON FACE HIGHLIGHTING
// ============================================================================

/**
 * @brief Highlights a specific face of a polygon zone.
 *
 * Used in editor mode to show which face the player is aiming at.
 *
 * @param[in] zone_index Index of the polygon zone.
 * @param[in] face_id Face identifier: POLYGON_FACE_TOP, POLYGON_FACE_BOTTOM,
 *                    or edge index (0 to vertex_count-1) for walls.
 * @param[in] highlight_color RGB color array for the highlight.
 */
stock highlight_polygon_face(zone_index, face_id, const highlight_color[3])
{
    new vertex_count = get_vertex_count(zone_index);
    if (vertex_count < 3)
        return;
    
    new Float:top_z = get_zone_height(zone_index);
    
    // build vertices array
    new Float:vertices[MAX_POLYGON_VERTICES][3];
    for (new i = 0; i < vertex_count; i++) {
        get_vertex(zone_index, i, vertices[i]);
    }
    
    if (face_id == POLYGON_FACE_TOP) {
        // highlight top face (flat at top_z)
        visual_highlight_polygon_top_face(vertices, vertex_count, top_z, highlight_color, 1, 5, true);
    }
    else if (face_id == POLYGON_FACE_BOTTOM) {
        // highlight bottom face (at actual vertex Z heights)
        visual_highlight_polygon_bottom_face(vertices, vertex_count, highlight_color, 1, 5, true);
    }
    else if (face_id >= 0 && face_id < vertex_count) {
        // highlight wall (edge index)
        new next = (face_id + 1) % vertex_count;
        visual_highlight_polygon_wall(vertices[face_id], vertices[next], top_z, highlight_color, 1, 5, true);
    }
}
