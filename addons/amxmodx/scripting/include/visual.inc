/**
 * @brief visual - Visual Library for AMX Mod X
 *
 * A comprehensive visual library providing entity highlighting, bounding box rendering,
 * ray-AABB intersection testing, and wireframe visualization systems.
 *
 * Version: 1.1
 * Author: PWNED
 */

#if defined _visual_included
    #endinput
#endif
#define _visual_included

#include <reapi>
#include <fakemeta>
#include <xs>

#pragma semicolon 1

// =============================================================================
// CONSTANTS
// =============================================================================

// maximum distance for entity highlighting and selection
// note: 4096 is hardcoded (gj valve!)
// see: https://github.com/twhl-community/halflife-updated/issues/182
#define VISUAL_HIGHLIGHT_DISTANCE   4096.0

// standard colors for visual feedback
new VISUAL_COLOR_RED[3]     = {255, 0, 0};
new VISUAL_COLOR_GREEN[3]   = {0, 255, 0};
new VISUAL_COLOR_BLUE[3]    = {0, 0, 255};
new VISUAL_COLOR_YELLOW[3]  = {255, 255, 0};
new VISUAL_COLOR_PINK[3]    = {255, 100, 100};
new VISUAL_COLOR_WHITE[3]   = {255, 255, 255};
new VISUAL_COLOR_CYAN[3]    = {0, 255, 255};

// to make the compiler shut up about unused colors if not used in plugin
#pragma unused VISUAL_COLOR_RED, VISUAL_COLOR_GREEN, VISUAL_COLOR_BLUE, VISUAL_COLOR_YELLOW, VISUAL_COLOR_PINK, VISUAL_COLOR_WHITE, VISUAL_COLOR_CYAN

// face identifiers for aimed expansion
#define FACE_MINUS_X 0  // west wall (-X)
#define FACE_PLUS_X  1  // east wall (+X)
#define FACE_MINUS_Y 2  // south wall (-Y)
#define FACE_PLUS_Y  3  // north wall (+Y)
#define FACE_MINUS_Z 4  // bottom face (-Z)
#define FACE_PLUS_Z  5  // top face (+Z)

// polygon face identifiers
#define POLYGON_FACE_NONE   -1
#define POLYGON_FACE_BOTTOM FACE_MINUS_Z
#define POLYGON_FACE_TOP    FACE_PLUS_Z

// global sprite handle (must be set by calling plugin)
new g_visual_sprite = 0;

// =============================================================================
// INITIALIZATION
// =============================================================================

/**
 * @brief Sets the sprite for all visual beam effects
 *
 * This function must be called during plugin_precache() to initialize the sprite
 * used for rendering all visual effects. Without calling this function, visual
 * rendering functions will not work.
 *
 * @param[in] sprite_index  The precached sprite index from precache_model()
 *
 * @note Must be called in plugin_precache() before using any visual functions
 * @note Typically use "sprites/laserbeam.spr" or similar beam sprite
 *
 * Example:
 * ```
 * public plugin_precache()
 * {
 *     new sprite = precache_model("sprites/laserbeam.spr");
 *     visual_set_sprite(sprite);
 * }
 * ```
 */
stock visual_set_sprite(sprite_index)
{
    g_visual_sprite = sprite_index;
}

// =============================================================================
// ENTITY SELECTION & AIMING
// =============================================================================

/**
 * @brief Gets the entity that the player is aiming at using traceline
 *
 * Performs a traceline from the player's eye position in their view direction
 * up to VISUAL_HIGHLIGHT_DISTANCE units to find the entity they are looking at.
 *
 * @param[in] id            Player entity index
 *
 * @return                  Entity index the player is aiming at, or 0 if none
 *
 * @note Uses DONT_IGNORE_MONSTERS flag to detect all entities
 * @note Maximum detection range is VISUAL_HIGHLIGHT_DISTANCE
 *
 * Example:
 * ```
 * new ent = visual_get_aimed_entity(id);
 * if (is_entity(ent))
 * {
 *     client_print(id, print_chat, "Aiming at entity #%d", ent);
 * }
 * ```
 */
stock visual_get_aimed_entity(id)
{
    new Float:start[3], Float:end[3], Float:v_angle[3], Float:v_forward[3], Float:view_ofs[3];

    get_entvar(id, var_origin, start);
    get_entvar(id, var_view_ofs, view_ofs);
    xs_vec_add(start, view_ofs, start);

    get_entvar(id, var_v_angle, v_angle);
    angle_vector(v_angle, ANGLEVECTOR_FORWARD, v_forward);

    xs_vec_mul_scalar(v_forward, VISUAL_HIGHLIGHT_DISTANCE, end);
    xs_vec_add(start, end, end);

    new tr;
    engfunc(EngFunc_TraceLine, start, end, DONT_IGNORE_MONSTERS, id, tr);

    return get_tr2(tr, TR_pHit);
}

/**
 * @brief Gets the player's aim direction and start position for ray casting
 *
 * Calculates the player's eye position and view direction vector, useful for
 * custom ray casting operations and intersection tests.
 *
 * @param[in] id            Player entity index
 * @param[out] start        Output: ray start position (player's eye position)
 * @param[out] direction    Output: normalized ray direction vector
 *
 * @note Direction vector is automatically normalized by angle_vector
 * @note Start position accounts for player's view offset (eye height)
 *
 * Example:
 * ```
 * new Float:origin[3], Float:dir[3];
 * visual_get_aim_ray(id, origin, dir);
 * // use origin and dir for custom ray casting
 * ```
 */
stock visual_get_aim_ray(id, Float:start[3], Float:direction[3])
{
    new Float:v_angle[3], Float:view_ofs[3];

    get_entvar(id, var_origin, start);
    get_entvar(id, var_view_ofs, view_ofs);
    xs_vec_add(start, view_ofs, start);

    get_entvar(id, var_v_angle, v_angle);
    angle_vector(v_angle, ANGLEVECTOR_FORWARD, direction);
}

// =============================================================================
// BOUNDING BOX RENDERING
// =============================================================================

/**
 * @brief Draws a complete bounding box using 12 beam lines
 *
 * Renders a 3D wireframe box by drawing all 12 edges (4 bottom, 4 top, 4 vertical).
 * The box is drawn using the TE_BEAMPOINTS temporary entity for the specified player.
 *
 * @param[in] id            Player to show the box to
 * @param[in] mins          Minimum coordinates {x, y, z} of the bounding box
 * @param[in] maxs          Maximum coordinates {x, y, z} of the bounding box
 * @param[in] color         RGB color array {r, g, b}
 *
 * @note Requires visual_set_sprite() to have been called first
 * @note Uses visual_draw_line() internally for each edge
 *
 * Example:
 * ```
 * new Float:mins[3] = {-50.0, -50.0, 0.0};
 * new Float:maxs[3] = {50.0, 50.0, 100.0};
 * visual_draw_bounding_box(id, mins, maxs, VISUAL_COLOR_RED);
 * ```
 */
stock visual_draw_bounding_box(id, const Float:mins[3], const Float:maxs[3], const color[3])
{
    // define the 8 corners of the bounding box
    new Float:p0[3], Float:p1[3], Float:p2[3], Float:p3[3], Float:p4[3], Float:p5[3], Float:p6[3], Float:p7[3];

    p0[0] = mins[0]; p0[1] = mins[1]; p0[2] = mins[2];
    p1[0] = maxs[0]; p1[1] = mins[1]; p1[2] = mins[2];
    p2[0] = maxs[0]; p2[1] = maxs[1]; p2[2] = mins[2];
    p3[0] = mins[0]; p3[1] = maxs[1]; p3[2] = mins[2];
    p4[0] = mins[0]; p4[1] = mins[1]; p4[2] = maxs[2];
    p5[0] = maxs[0]; p5[1] = mins[1]; p5[2] = maxs[2];
    p6[0] = maxs[0]; p6[1] = maxs[1]; p6[2] = maxs[2];
    p7[0] = mins[0]; p7[1] = maxs[1]; p7[2] = maxs[2];

    // draw the 12 edges
    visual_draw_line(id, p0, p1, color); visual_draw_line(id, p1, p2, color);
    visual_draw_line(id, p2, p3, color); visual_draw_line(id, p3, p0, color);

    visual_draw_line(id, p4, p5, color); visual_draw_line(id, p5, p6, color);
    visual_draw_line(id, p6, p7, color); visual_draw_line(id, p7, p4, color);

    visual_draw_line(id, p0, p4, color); visual_draw_line(id, p1, p5, color);
    visual_draw_line(id, p2, p6, color); visual_draw_line(id, p3, p7, color);
}

/**
 * @brief Generic beam drawing function (internal use)
 *
 * Core function for drawing beams between two points with full parameter control.
 * Used by all higher-level beam drawing functions.
 *
 * @param[in] start             The starting point {x, y, z} of the beam
 * @param[in] end               The ending point {x, y, z} of the beam
 * @param[in] sprite_index      The sprite to use for the beam
 * @param[in] color             The RGB color for the line, as an array of 3 values {r, g, b}
 * @param[in] duration_tenths   The duration for the line to be visible, in tenths of a second
 * @param[in] line_width        The width of the rendered line
 * @param[in] brightness        The brightness (alpha) of the line, from 0 to 255
 * @param[in] scroll_speed      The scroll speed of the beam's texture
 * @param[in] player_id         Player ID (0 = broadcast to all, >0 = send to specific player)
 *
 * @note This is the lowest-level rendering function
 * @note Sends TE_BEAMPOINTS temporary entity message
 *
 * Example:
 * ```
 * visual_draw_beam_generic(start, end, sprite, color, 10, 5, 255, 0, id);
 * ```
 */
stock visual_draw_beam_generic(const Float:start[3], const Float:end[3], sprite_index, const color[3],
    duration_tenths = 1, line_width = 2, brightness = 255, scroll_speed = 0, player_id = 0)
{
    if (!sprite_index) {
        log_amx("[visual] Warning: Invalid sprite index provided to visual_draw_beam_generic()");
        return;
    }

    // determine message type based on player_id
    if (player_id == 0) {
        message_begin(MSG_BROADCAST, SVC_TEMPENTITY);
    } else {
        message_begin(MSG_ONE_UNRELIABLE, SVC_TEMPENTITY, .player = player_id);
    }

    write_byte(TE_BEAMPOINTS);

    // start position
    write_coord(floatround(start[0]));
    write_coord(floatround(start[1]));
    write_coord(floatround(start[2]));

    // end position
    write_coord(floatround(end[0]));
    write_coord(floatround(end[1]));
    write_coord(floatround(end[2]));

    // sprite configuration
    write_short(sprite_index);
    write_byte(0);  // start frame
    write_byte(0);  // frame rate
    write_byte(duration_tenths);  // life in tenths of seconds
    write_byte(line_width);  // width
    write_byte(0);  // noise amplitude

    // color
    write_byte(color[0]); // r
    write_byte(color[1]); // g
    write_byte(color[2]); // b

    write_byte(brightness);
    write_byte(scroll_speed);

    message_end();
}

/**
 * @brief Draws a line between two 3D points using beams (for single player)
 *
 * Simple wrapper for drawing a single line with default parameters.
 * Uses the global sprite set by visual_set_sprite().
 *
 * @param[in] id            Player to show the line to
 * @param[in] start         Start position {x, y, z}
 * @param[in] end           End position {x, y, z}
 * @param[in] color         RGB color array {r, g, b}
 *
 * @note Requires visual_set_sprite() to have been called first
 * @note Uses default parameters: duration=0.1s, width=2, brightness=200
 *
 * Example:
 * ```
 * new Float:p1[3] = {0.0, 0.0, 0.0};
 * new Float:p2[3] = {100.0, 100.0, 100.0};
 * visual_draw_line(id, p1, p2, VISUAL_COLOR_BLUE);
 * ```
 */
stock visual_draw_line(id, const Float:start[3], const Float:end[3], const color[3])
{
    if (!g_visual_sprite) {
        log_amx("[visual] Warning: Sprite not set! Call visual_set_sprite() first.");
        return;
    }

    visual_draw_beam_generic(start, end, g_visual_sprite, color, 1, 2, 200, 0, id);
}

// =============================================================================
// GEOMETRIC UTILITIES
// =============================================================================

/**
 * @brief Performs a ray-AABB (Axis-Aligned Bounding Box) intersection test
 *
 * This function determines if a given ray intersects with a bounding box using
 * the slab method. If an intersection is found, it calculates the distance from
 * the ray's origin to the point of intersection.
 *
 * Algorithm: Slab Method
 * - Treats the AABB as the intersection of 3 pairs of parallel planes (slabs)
 * - For each axis, calculates where the ray enters and exits the slab
 * - The ray intersects the box if all entry points are before all exit points
 * - Returns the nearest intersection distance in forward direction
 *
 * Reference: https://en.wikipedia.org/wiki/Slab_method
 *
 * @param[in] ray_origin    The starting point {x, y, z} of the ray
 * @param[in] ray_dir       The direction vector {x, y, z} of the ray (should be normalized)
 * @param[in] box_min       The minimum coordinates {x, y, z} of the AABB
 * @param[in] box_max       The maximum coordinates {x, y, z} of the AABB
 * @param[out] hit_distance Output parameter: distance from ray origin to intersection point
 *
 * @return                  Returns `true` if the ray intersects the box in forward direction, `false` otherwise
 *
 * @note Ray direction should be normalized for accurate distance measurements
 * @note Returns false if ray is parallel to box and starts outside it
 *
 * Example:
 * ```
 * new Float:origin[3], Float:dir[3];
 * visual_get_aim_ray(id, origin, dir);
 *
 * new Float:box_min[3] = {0.0, 0.0, 0.0};
 * new Float:box_max[3] = {100.0, 100.0, 100.0};
 * new Float:distance;
 *
 * if (visual_ray_intersects_aabb(origin, dir, box_min, box_max, distance))
 * {
 *     client_print(id, print_chat, "Hit at distance: %.2f", distance);
 * }
 * ```
 */
stock bool:visual_ray_intersects_aabb(const Float:ray_origin[3], const Float:ray_dir[3], const Float:box_min[3], const Float:box_max[3], &Float:hit_distance)
{
    // initialize the intersection distance range - t_min is the closest intersection, t_max is the farthest
    new Float:t_min = 0.0, Float:t_max = VISUAL_HIGHLIGHT_DISTANCE;

    // iterate over each axis (x, y, z)
    for (new i = 0; i < 3; i++)
    {
        // handle the case where the ray is parallel to the slab's planes for this axis
        if (floatabs(ray_dir[i]) < 0.00001)
        {
            // if the ray is parallel and its origin is outside the slab, it can't intersect
            if (ray_origin[i] < box_min[i] || ray_origin[i] > box_max[i])
                return false;
        }
        else
        {
            // the ray is not parallel to the planes on this axis
            // calculate the inverse of the direction component to replace division with multiplication
            new Float:ood = 1.0 / ray_dir[i];

            // calculate the intersection distances ('t' values) with the two slab planes for this axis
            new Float:t1 = (box_min[i] - ray_origin[i]) * ood;
            new Float:t2 = (box_max[i] - ray_origin[i]) * ood;

            // ensure t1 is the smaller distance (entry point) and t2 is the larger (exit point)
            if (t1 > t2) {
                new Float:temp = t1;
                t1 = t2;
                t2 = temp;
            }

            // update the overall nearest intersection point, it's the furthest of all the near plane hits
            t_min = floatmax(t_min, t1);

            // update the overall farthest intersection point, it's the closest of all the far plane hits
            t_max = floatmin(t_max, t2);

            // if the nearest intersection is further than the farthest, the ray misses the box
            if (t_min > t_max)
                return false;
        }
    }

    // if we get here, an intersection occurred - determine the correct hit distance
    // if t_min is > 0, the ray starts outside the box, so that's our hit
    // if t_min is < 0, the ray starts inside, so the first forward hit is at t_max
    hit_distance = t_min > 0.0 ? t_min : t_max;

    // return true only if the intersection is in front of the ray's origin
    return hit_distance > 0.0;
}

/**
 * @brief Calculates an absolute (world-space) bounding box from origin and relative bounds
 *
 * Transforms relative bounding box coordinates (offsets from origin) into absolute
 * world coordinates by adding the origin to both mins and maxs.
 *
 * @param[in] origin        The origin point {x, y, z} in world coordinates
 * @param[in] mins          The relative minimum coordinates {x, y, z}, offset from origin
 * @param[in] maxs          The relative maximum coordinates {x, y, z}, offset from origin
 * @param[out] abs_mins     Output: calculated absolute minimum coordinates {x, y, z}
 * @param[out] abs_maxs     Output: calculated absolute maximum coordinates {x, y, z}
 *
 * @note This is a simple vector addition: abs_mins = origin + mins, abs_maxs = origin + maxs
 *
 * Example:
 * ```
 * new Float:origin[3] = {100.0, 200.0, 50.0};
 * new Float:mins[3] = {-10.0, -10.0, 0.0};
 * new Float:maxs[3] = {10.0, 10.0, 20.0};
 * new Float:abs_mins[3], Float:abs_maxs[3];
 *
 * visual_calculate_abs_bbox(origin, mins, maxs, abs_mins, abs_maxs);
 * ```
 */
stock visual_calculate_abs_bbox(const Float:origin[3], const Float:mins[3], const Float:maxs[3], Float:abs_mins[3], Float:abs_maxs[3])
{
    xs_vec_add(origin, mins, abs_mins);
    xs_vec_add(origin, maxs, abs_maxs);
}

/**
 * @brief Calculates the absolute (world-space) bounding box for a given entity
 *
 * Retrieves the entity's origin and relative bounding box (var_mins, var_maxs),
 * then calculates the absolute world-space bounding box.
 *
 * @param[in] ent           The index of the entity to get the bounding box for
 * @param[out] abs_mins     Output: minimum coordinates {x, y, z} of absolute bounding box
 * @param[out] abs_maxs     Output: maximum coordinates {x, y, z} of absolute bounding box
 *
 * @return                  Returns `true` if the entity is valid and bbox was calculated, `false` otherwise
 *
 * @note Checks if entity is valid using is_entity()
 * @note Uses visual_calculate_abs_bbox() internally
 *
 * Example:
 * ```
 * new ent = visual_get_aimed_entity(id);
 * new Float:mins[3], Float:maxs[3];
 *
 * if (visual_get_entity_bbox(ent, mins, maxs))
 * {
 *     visual_draw_wireframe_box(mins, maxs, VISUAL_COLOR_PINK);
 * }
 * ```
 */
stock bool:visual_get_entity_bbox(ent, Float:abs_mins[3], Float:abs_maxs[3])
{
    if (!is_entity(ent))
        return false;

    new Float:origin[3], Float:mins[3], Float:maxs[3];
    get_entvar(ent, var_origin, origin);
    get_entvar(ent, var_mins, mins);
    get_entvar(ent, var_maxs, maxs);

    visual_calculate_abs_bbox(origin, mins, maxs, abs_mins, abs_maxs);
    return true;
}

/**
 * @brief Checks if two Axis-Aligned Bounding Boxes (AABBs) intersect, considering an optional offset.
 *
 * Uses the Separating Axis Theorem to efficiently test for 3D box intersection.
 * Two AABBs intersect if they overlap on all three axes (X, Y, and Z).
 *
 * Compares `box1` against `box2` after `box2` is adjusted by the `offset`.
 * A positive offset shrinks `box2`, a negative one expands it.
 *
 * @param[in] mins1         Minimum coordinates {x, y, z} of the first AABB
 * @param[in] maxs1         Maximum coordinates {x, y, z} of the first AABB
 * @param[in] mins2         Minimum coordinates {x, y, z} of the second AABB
 * @param[in] maxs2         Maximum coordinates {x, y, z} of the second AABB
 * @param[in] offset        Margin to apply to `box2` before checking intersection (default: 0.0)
 *                          - Positive: shrinks box2 (requires deeper overlap to intersect)
 *                          - Negative: expands box2 (detects near-misses as intersections)
 *
 * @return                  Returns `true` if boxes intersect with offset applied, `false` otherwise
 *
 * @note Uses Separating Axis Theorem for efficient testing
 * @note Returns false if boxes are touching edge-to-edge (no volume overlap)
 * @note Assumes valid AABBs where `mins[axis] <= maxs[axis]` for each axis
 *
 * Example:
 * ```
 * new Float:zone1_mins[3] = {0.0, 0.0, 0.0};
 * new Float:zone1_maxs[3] = {100.0, 100.0, 100.0};
 * new Float:zone2_mins[3] = {90.0, 90.0, 90.0};
 * new Float:zone2_maxs[3] = {200.0, 200.0, 200.0};
 *
 * // Basic intersection test
 * if (visual_aabb_intersects(zone1_mins, zone1_maxs, zone2_mins, zone2_maxs))
 * {
 *     // Zones overlap
 * }
 *
 * // With 10-unit margin (zones must be at least 10 units apart)
 * if (visual_aabb_intersects(zone1_mins, zone1_maxs, zone2_mins, zone2_maxs, 10.0))
 * {
 *     // Zones overlap even with margin
 * }
 * ```
 */
stock bool:visual_aabb_intersects(const Float:mins1[3], const Float:maxs1[3], const Float:mins2[3], const Float:maxs2[3], const Float:offset = 0.0)
{
    // check for separation on each axis, considering the offset
    // if separated on any axis, they don't intersect

    // x-axis separation check
    if (maxs1[0] <= mins2[0] + offset || mins1[0] >= maxs2[0] - offset) {
        return false;
    }

    // y-axis separation check
    if (maxs1[1] <= mins2[1] + offset || mins1[1] >= maxs2[1] - offset) {
        return false;
    }

    // z-axis separation check
    if (maxs1[2] <= mins2[2] + offset || mins1[2] >= maxs2[2] - offset) {
        return false;
    }

    // if no separating axis found, they intersect
    return true;
}

// =============================================================================
// WIREFRAME RENDERING SYSTEM
// =============================================================================

/**
 * @brief Draws a wireframe bounding box with options to render only specific faces
 *
 * @param[in] mins              Minimum coordinates {x, y, z} of the box
 * @param[in] maxs              Maximum coordinates {x, y, z} of the box
 * @param[in] color             RGB color array {r, g, b}
 * @param[in] duration_tenths   Duration in tenths of seconds
 * @param[in] line_width        Width of the lines
 * @param[in] draw_vertical     If true, draw vertical edges
 * @param[in] draw_top          If true, draw top edges
 * @param[in] draw_bottom       If true, draw bottom edges
 * @param[in] visual_offset     Optional inset from edges to avoid z-fighting (default: 0.0)
 */
stock visual_draw_wireframe_box(const Float:mins[3], const Float:maxs[3], const color[3], duration_tenths = 1, line_width = 8, bool:draw_vertical = true, bool:draw_top = true, bool:draw_bottom = true, Float:visual_offset = 0.0, player_id = 0)
{
    if (!g_visual_sprite) {
        log_amx("[visual] WARNING: Sprite not set! Call visual_set_sprite() first.");
        return;
    }

    new Float:mins_v[3], Float:maxs_v[3];

    // apply visual offset if specified
    if (visual_offset > 0.0)
    {
        new Float:size[3];
        xs_vec_sub(maxs, mins, size);

        // calculate visually offset bounds
        for (new i = 0; i < 3; i++)
        {
            // only apply offset if the size is large enough to accommodate it twice
            if (size[i] > (visual_offset * 2.0 + 1.2))
            {
                mins_v[i] = mins[i] + visual_offset;
                maxs_v[i] = maxs[i] - visual_offset;
            }
            else
            {
                // zone too small on this axis, use original bounds
                mins_v[i] = mins[i];
                maxs_v[i] = maxs[i];
            }
        }
    }
    else
    {
        // no offset, use original bounds
        xs_vec_copy(mins, mins_v);
        xs_vec_copy(maxs, maxs_v);
    }

    new Float:p1[3], Float:p2[3];

    // draw vertical lines
    if (draw_vertical)
    {
        xs_vec_set(p1, maxs_v[0], maxs_v[1], maxs_v[2]); xs_vec_set(p2, maxs_v[0], maxs_v[1], mins_v[2]);
        visual_draw_wireframe_line(p1, p2, color, duration_tenths, line_width, 255, 5, player_id);

        xs_vec_set(p1, mins_v[0], maxs_v[1], maxs_v[2]); xs_vec_set(p2, mins_v[0], maxs_v[1], mins_v[2]);
        visual_draw_wireframe_line(p1, p2, color, duration_tenths, line_width, 255, 5, player_id);

        xs_vec_set(p1, maxs_v[0], mins_v[1], maxs_v[2]); xs_vec_set(p2, maxs_v[0], mins_v[1], mins_v[2]);
        visual_draw_wireframe_line(p1, p2, color, duration_tenths, line_width, 255, 5, player_id);

        xs_vec_set(p1, mins_v[0], mins_v[1], maxs_v[2]); xs_vec_set(p2, mins_v[0], mins_v[1], mins_v[2]);
        visual_draw_wireframe_line(p1, p2, color, duration_tenths, line_width, 255, 5, player_id);
    }

    // draw horizontal lines (top square)
    if (draw_top)
    {
        xs_vec_set(p1, maxs_v[0], maxs_v[1], maxs_v[2]); xs_vec_set(p2, mins_v[0], maxs_v[1], maxs_v[2]);
        visual_draw_wireframe_line(p1, p2, color, duration_tenths, line_width, 255, 5, player_id);

        xs_vec_set(p1, maxs_v[0], mins_v[1], maxs_v[2]); xs_vec_set(p2, mins_v[0], mins_v[1], maxs_v[2]);
        visual_draw_wireframe_line(p1, p2, color, duration_tenths, line_width, 255, 5, player_id);

        xs_vec_set(p1, maxs_v[0], maxs_v[1], maxs_v[2]); xs_vec_set(p2, maxs_v[0], mins_v[1], maxs_v[2]);
        visual_draw_wireframe_line(p1, p2, color, duration_tenths, line_width, 255, 5, player_id);

        xs_vec_set(p1, mins_v[0], maxs_v[1], maxs_v[2]); xs_vec_set(p2, mins_v[0], mins_v[1], maxs_v[2]);
        visual_draw_wireframe_line(p1, p2, color, duration_tenths, line_width, 255, 5, player_id);
    }

    // draw horizontal lines (bottom square)
    if (draw_bottom)
    {
        xs_vec_set(p1, maxs_v[0], maxs_v[1], mins_v[2]); xs_vec_set(p2, mins_v[0], maxs_v[1], mins_v[2]);
        visual_draw_wireframe_line(p1, p2, color, duration_tenths, line_width, 255, 5, player_id);

        xs_vec_set(p1, maxs_v[0], mins_v[1], mins_v[2]); xs_vec_set(p2, mins_v[0], mins_v[1], mins_v[2]);
        visual_draw_wireframe_line(p1, p2, color, duration_tenths, line_width, 255, 5, player_id);

        xs_vec_set(p1, maxs_v[0], maxs_v[1], mins_v[2]); xs_vec_set(p2, maxs_v[0], mins_v[1], mins_v[2]);
        visual_draw_wireframe_line(p1, p2, color, duration_tenths, line_width, 255, 5, player_id);

        xs_vec_set(p1, mins_v[0], maxs_v[1], mins_v[2]); xs_vec_set(p2, mins_v[0], mins_v[1], mins_v[2]);
        visual_draw_wireframe_line(p1, p2, color, duration_tenths, line_width, 255, 5, player_id);
    }
}

/**
 * @brief Draws a single visible line between two points in the world using a beam temporary entity
 *
 * @param[in] start             The starting point {x, y, z} of the line
 * @param[in] end               The ending point {x, y, z} of the line
 * @param[in] color             The RGB color for the line, as an array {r, g, b}
 * @param[in] duration_tenths   Optional: The duration for the line to be visible, in tenths of a second (default: 1)
 * @param[in] line_width        Optional: The width of the rendered line (default: 5)
 * @param[in] brightness        Optional: The brightness (alpha) of the line, from 0 to 255 (default: 255)
 * @param[in] scroll_speed      Optional: The scroll speed of the beam's texture (default: 5)
 */
stock visual_draw_wireframe_line(const Float:start[3], const Float:end[3], const color[3], duration_tenths = 1, line_width = 8, brightness = 255, scroll_speed = 5, player_id = 0)
{
    if (!g_visual_sprite) {
        log_amx("[visual] WARNING: Sprite not set! Call visual_set_sprite() first.");
        return;
    }

    visual_draw_beam_generic(start, end, g_visual_sprite, color, duration_tenths, line_width, brightness, scroll_speed, player_id);
}

/**
 * @brief Draws a single line in the world - convenience alias
 *
 * @param[in] start             The starting point {x, y, z} of the line
 * @param[in] end               The ending point {x, y, z} of the line
 * @param[in] color             The RGB color for the line, as an array {r, g, b}
 * @param[in] duration_tenths   Optional: The duration for the line to be visible, in tenths of a second (default: 1)
 */
stock visual_create_zone_line(const Float:start[3], const Float:end[3], const color[3], duration_tenths = 1)
{
    visual_draw_wireframe_line(start, end, color, duration_tenths);
}

/**
 * @brief Draws a wireframe for a zone, with appearance determined by editor mode and specific zone flags
 *
 * @param[in] abs_mins           The minimum coordinates {x, y, z} of the zone's bounding box
 * @param[in] abs_maxs           The maximum coordinates {x, y, z} of the zone's bounding box
 * @param[in] color              The RGB color for the wireframe lines, as an array {r, g, b}
 * @param[in] editor_mode        If true, draw complete wireframe; if false, draw minimal
 * @param[in] always_show_bottom If true and not in editor_mode, draw bottom edges (default: false)
 * @param[in] offset             Optional: The distance to inset lines from edges (default: 1.2)
 */
stock visual_draw_zone_wireframe(const Float:abs_mins[3], const Float:abs_maxs[3], const color[3], bool:editor_mode, bool:always_show_bottom = false, Float:offset = 1.2)
{
    if (editor_mode)
    {
        // edit mode: draw complete wireframe
        visual_draw_wireframe_box(abs_mins, abs_maxs, color, 1, 5, true, true, true, offset);
    }
    else if (always_show_bottom)
    {
        // needed for special zones (start/finish): only bottom lines
        visual_draw_wireframe_box(abs_mins, abs_maxs, color, 3, 5, false, false, true, offset);
    }
}

/**
 * @brief Highlights a specific face of a bounding box with different colored lines
 *
 * @param[in] abs_mins          The minimum coordinates {x, y, z} of the bounding box
 * @param[in] abs_maxs          The maximum coordinates {x, y, z} of the bounding box
 * @param[in] face_id           The identifier for the face to highlight (0-5)
 * @param[in] highlight_color   The RGB color for the highlight lines, as an array {r, g, b}
 * @param[in] offset            Optional: The distance to inset highlight lines from edges (default: 1.2)
 * @param[in] duration_tenths   Optional: The duration for the lines to be visible (default: 1)
 * @param[in] line_width        Optional: The width of the rendered lines (default: 5)
 * @param[in] brightness        Optional: The brightness (alpha) of the lines, 0-255 (default: 255)
 * @param[in] draw_center_x     Optional: If true, draws an "X" marker at the center of the face (default: false)
 */
stock visual_highlight_face(const Float:abs_mins[3], const Float:abs_maxs[3], face_id, const highlight_color[3], Float:offset = 1.2, duration_tenths = 1, line_width = 5, brightness = 255, bool:draw_center_x = false)
{
    if (!g_visual_sprite) {
        log_amx("[visual] WARNING: Sprite not set! Call visual_set_sprite() first.");
        return;
    }

    new Float:fMins_v[3], Float:fMaxs_v[3];

    // apply visual offset if specified
    if (offset > 0.0)
    {
        new Float:fSize[3];
        xs_vec_sub(abs_maxs, abs_mins, fSize);

        for (new i = 0; i < 3; i++)
        {
            if (fSize[i] > (offset * 2.0 + 1.2))
            {
                fMins_v[i] = abs_mins[i] + offset;
                fMaxs_v[i] = abs_maxs[i] - offset;
            }
            else
            {
                fMins_v[i] = abs_mins[i];
                fMaxs_v[i] = abs_maxs[i];
            }
        }
    }
    else
    {
        xs_vec_copy(abs_mins, fMins_v);
        xs_vec_copy(abs_maxs, fMaxs_v);
    }

    new Float:p1[3], Float:p2[3];

    // draw the lines for the specified face
    switch (face_id)
    {
        case FACE_MINUS_X: // west wall (-X)
        {
            xs_vec_set(p1, fMins_v[0], fMins_v[1], fMins_v[2]); xs_vec_set(p2, fMins_v[0], fMaxs_v[1], fMins_v[2]);
            visual_draw_wireframe_line(p1, p2, highlight_color, duration_tenths, line_width, brightness);

            xs_vec_set(p1, fMins_v[0], fMaxs_v[1], fMins_v[2]); xs_vec_set(p2, fMins_v[0], fMaxs_v[1], fMaxs_v[2]);
            visual_draw_wireframe_line(p1, p2, highlight_color, duration_tenths, line_width, brightness);

            xs_vec_set(p1, fMins_v[0], fMaxs_v[1], fMaxs_v[2]); xs_vec_set(p2, fMins_v[0], fMins_v[1], fMaxs_v[2]);
            visual_draw_wireframe_line(p1, p2, highlight_color, duration_tenths, line_width, brightness);

            xs_vec_set(p1, fMins_v[0], fMins_v[1], fMaxs_v[2]); xs_vec_set(p2, fMins_v[0], fMins_v[1], fMins_v[2]);
            visual_draw_wireframe_line(p1, p2, highlight_color, duration_tenths, line_width, brightness);
        }
        case FACE_PLUS_X: // east wall (+X)
        {
            xs_vec_set(p1, fMaxs_v[0], fMins_v[1], fMins_v[2]); xs_vec_set(p2, fMaxs_v[0], fMaxs_v[1], fMins_v[2]);
            visual_draw_wireframe_line(p1, p2, highlight_color, duration_tenths, line_width, brightness);

            xs_vec_set(p1, fMaxs_v[0], fMaxs_v[1], fMins_v[2]); xs_vec_set(p2, fMaxs_v[0], fMaxs_v[1], fMaxs_v[2]);
            visual_draw_wireframe_line(p1, p2, highlight_color, duration_tenths, line_width, brightness);

            xs_vec_set(p1, fMaxs_v[0], fMaxs_v[1], fMaxs_v[2]); xs_vec_set(p2, fMaxs_v[0], fMins_v[1], fMaxs_v[2]);
            visual_draw_wireframe_line(p1, p2, highlight_color, duration_tenths, line_width, brightness);

            xs_vec_set(p1, fMaxs_v[0], fMins_v[1], fMaxs_v[2]); xs_vec_set(p2, fMaxs_v[0], fMins_v[1], fMins_v[2]);
            visual_draw_wireframe_line(p1, p2, highlight_color, duration_tenths, line_width, brightness);
        }
        case FACE_MINUS_Y: // south wall (-Y)
        {
            xs_vec_set(p1, fMins_v[0], fMins_v[1], fMins_v[2]); xs_vec_set(p2, fMaxs_v[0], fMins_v[1], fMins_v[2]);
            visual_draw_wireframe_line(p1, p2, highlight_color, duration_tenths, line_width, brightness);

            xs_vec_set(p1, fMaxs_v[0], fMins_v[1], fMins_v[2]); xs_vec_set(p2, fMaxs_v[0], fMins_v[1], fMaxs_v[2]);
            visual_draw_wireframe_line(p1, p2, highlight_color, duration_tenths, line_width, brightness);

            xs_vec_set(p1, fMaxs_v[0], fMins_v[1], fMaxs_v[2]); xs_vec_set(p2, fMins_v[0], fMins_v[1], fMaxs_v[2]);
            visual_draw_wireframe_line(p1, p2, highlight_color, duration_tenths, line_width, brightness);

            xs_vec_set(p1, fMins_v[0], fMins_v[1], fMaxs_v[2]); xs_vec_set(p2, fMins_v[0], fMins_v[1], fMins_v[2]);
            visual_draw_wireframe_line(p1, p2, highlight_color, duration_tenths, line_width, brightness);
        }
        case FACE_PLUS_Y: // north wall (+Y)
        {
            xs_vec_set(p1, fMins_v[0], fMaxs_v[1], fMins_v[2]); xs_vec_set(p2, fMaxs_v[0], fMaxs_v[1], fMins_v[2]);
            visual_draw_wireframe_line(p1, p2, highlight_color, duration_tenths, line_width, brightness);

            xs_vec_set(p1, fMaxs_v[0], fMaxs_v[1], fMins_v[2]); xs_vec_set(p2, fMaxs_v[0], fMaxs_v[1], fMaxs_v[2]);
            visual_draw_wireframe_line(p1, p2, highlight_color, duration_tenths, line_width, brightness);

            xs_vec_set(p1, fMaxs_v[0], fMaxs_v[1], fMaxs_v[2]); xs_vec_set(p2, fMins_v[0], fMaxs_v[1], fMaxs_v[2]);
            visual_draw_wireframe_line(p1, p2, highlight_color, duration_tenths, line_width, brightness);

            xs_vec_set(p1, fMins_v[0], fMaxs_v[1], fMaxs_v[2]); xs_vec_set(p2, fMins_v[0], fMaxs_v[1], fMins_v[2]);
            visual_draw_wireframe_line(p1, p2, highlight_color, duration_tenths, line_width, brightness);
        }
        case FACE_MINUS_Z: // bottom face (-Z)
        {
            xs_vec_set(p1, fMins_v[0], fMins_v[1], fMins_v[2]); xs_vec_set(p2, fMaxs_v[0], fMins_v[1], fMins_v[2]);
            visual_draw_wireframe_line(p1, p2, highlight_color, duration_tenths, line_width, brightness);

            xs_vec_set(p1, fMaxs_v[0], fMins_v[1], fMins_v[2]); xs_vec_set(p2, fMaxs_v[0], fMaxs_v[1], fMins_v[2]);
            visual_draw_wireframe_line(p1, p2, highlight_color, duration_tenths, line_width, brightness);

            xs_vec_set(p1, fMaxs_v[0], fMaxs_v[1], fMins_v[2]); xs_vec_set(p2, fMins_v[0], fMaxs_v[1], fMins_v[2]);
            visual_draw_wireframe_line(p1, p2, highlight_color, duration_tenths, line_width, brightness);

            xs_vec_set(p1, fMins_v[0], fMaxs_v[1], fMins_v[2]); xs_vec_set(p2, fMins_v[0], fMins_v[1], fMins_v[2]);
            visual_draw_wireframe_line(p1, p2, highlight_color, duration_tenths, line_width, brightness);
        }
        case FACE_PLUS_Z: // top face (+Z)
        {
            xs_vec_set(p1, fMins_v[0], fMins_v[1], fMaxs_v[2]); xs_vec_set(p2, fMaxs_v[0], fMins_v[1], fMaxs_v[2]);
            visual_draw_wireframe_line(p1, p2, highlight_color, duration_tenths, line_width, brightness);

            xs_vec_set(p1, fMaxs_v[0], fMins_v[1], fMaxs_v[2]); xs_vec_set(p2, fMaxs_v[0], fMaxs_v[1], fMaxs_v[2]);
            visual_draw_wireframe_line(p1, p2, highlight_color, duration_tenths, line_width, brightness);

            xs_vec_set(p1, fMaxs_v[0], fMaxs_v[1], fMaxs_v[2]); xs_vec_set(p2, fMins_v[0], fMaxs_v[1], fMaxs_v[2]);
            visual_draw_wireframe_line(p1, p2, highlight_color, duration_tenths, line_width, brightness);

            xs_vec_set(p1, fMins_v[0], fMaxs_v[1], fMaxs_v[2]); xs_vec_set(p2, fMins_v[0], fMins_v[1], fMaxs_v[2]);
            visual_draw_wireframe_line(p1, p2, highlight_color, duration_tenths, line_width, brightness);
        }
    }

    // draw small "X" marker at the center of the face if requested
    if (draw_center_x)
    {
        new Float:center[3];
        new Float:x_size = 2.0;
        new Float:d1[3], Float:d2[3], Float:d3[3], Float:d4[3];

        switch (face_id)
        {
            case FACE_MINUS_X: // west wall (-X)
            {
                xs_vec_set(center, fMins_v[0], (fMins_v[1] + fMaxs_v[1]) / 2.0, (fMins_v[2] + fMaxs_v[2]) / 2.0);
                xs_vec_set(d1, center[0], center[1] - x_size, center[2] - x_size);
                xs_vec_set(d2, center[0], center[1] + x_size, center[2] + x_size);
                xs_vec_set(d3, center[0], center[1] - x_size, center[2] + x_size);
                xs_vec_set(d4, center[0], center[1] + x_size, center[2] - x_size);
            }
            case FACE_PLUS_X: // east wall (+X)
            {
                xs_vec_set(center, fMaxs_v[0], (fMins_v[1] + fMaxs_v[1]) / 2.0, (fMins_v[2] + fMaxs_v[2]) / 2.0);
                xs_vec_set(d1, center[0], center[1] - x_size, center[2] - x_size);
                xs_vec_set(d2, center[0], center[1] + x_size, center[2] + x_size);
                xs_vec_set(d3, center[0], center[1] - x_size, center[2] + x_size);
                xs_vec_set(d4, center[0], center[1] + x_size, center[2] - x_size);
            }
            case FACE_MINUS_Y: // south wall (-Y)
            {
                xs_vec_set(center, (fMins_v[0] + fMaxs_v[0]) / 2.0, fMins_v[1], (fMins_v[2] + fMaxs_v[2]) / 2.0);
                xs_vec_set(d1, center[0] - x_size, center[1], center[2] - x_size);
                xs_vec_set(d2, center[0] + x_size, center[1], center[2] + x_size);
                xs_vec_set(d3, center[0] - x_size, center[1], center[2] + x_size);
                xs_vec_set(d4, center[0] + x_size, center[1], center[2] - x_size);
            }
            case FACE_PLUS_Y: // north wall (+Y)
            {
                xs_vec_set(center, (fMins_v[0] + fMaxs_v[0]) / 2.0, fMaxs_v[1], (fMins_v[2] + fMaxs_v[2]) / 2.0);
                xs_vec_set(d1, center[0] - x_size, center[1], center[2] - x_size);
                xs_vec_set(d2, center[0] + x_size, center[1], center[2] + x_size);
                xs_vec_set(d3, center[0] - x_size, center[1], center[2] + x_size);
                xs_vec_set(d4, center[0] + x_size, center[1], center[2] - x_size);
            }
            case FACE_MINUS_Z: // bottom face (-Z)
            {
                xs_vec_set(center, (fMins_v[0] + fMaxs_v[0]) / 2.0, (fMins_v[1] + fMaxs_v[1]) / 2.0, fMins_v[2]);
                xs_vec_set(d1, center[0] - x_size, center[1] - x_size, center[2]);
                xs_vec_set(d2, center[0] + x_size, center[1] + x_size, center[2]);
                xs_vec_set(d3, center[0] - x_size, center[1] + x_size, center[2]);
                xs_vec_set(d4, center[0] + x_size, center[1] - x_size, center[2]);
            }
            case FACE_PLUS_Z: // top face (+Z)
            {
                xs_vec_set(center, (fMins_v[0] + fMaxs_v[0]) / 2.0, (fMins_v[1] + fMaxs_v[1]) / 2.0, fMaxs_v[2]);
                xs_vec_set(d1, center[0] - x_size, center[1] - x_size, center[2]);
                xs_vec_set(d2, center[0] + x_size, center[1] + x_size, center[2]);
                xs_vec_set(d3, center[0] - x_size, center[1] + x_size, center[2]);
                xs_vec_set(d4, center[0] + x_size, center[1] - x_size, center[2]);
            }
        }

        visual_draw_wireframe_line(d1, d2, highlight_color, duration_tenths, line_width, brightness);
        visual_draw_wireframe_line(d3, d4, highlight_color, duration_tenths, line_width, brightness);
    }
}

// =============================================================================
// POLYGON ZONE RENDERING
// =============================================================================

/**
 * @brief Draws a polygon zone wireframe
 *
 * @param[in] vertices          2D array of vertex positions [vertex_index][0=x, 1=y, 2=z_bottom]
 * @param[in] vertex_count      Number of vertices in the polygon
 * @param[in] top_z             Z coordinate of the top face
 * @param[in] color             RGB color array {r, g, b}
 * @param[in] editor_mode       If true, draw complete wireframe; if false, only bottom (if always_show_bottom)
 * @param[in] always_show_bottom If true and not in editor_mode, draw bottom edges
 * @param[in] duration_tenths   Duration in tenths of seconds
 * @param[in] line_width        Width of the lines
 */
stock visual_draw_polygon_wireframe(const Float:vertices[][3], vertex_count, Float:top_z, const color[3], 
    bool:editor_mode, bool:always_show_bottom = false, duration_tenths = 1, line_width = 5)
{
    if (!g_visual_sprite || vertex_count < 3) {
        return;
    }

    new Float:v1[3], Float:v2[3];
    new Float:v1_top[3], Float:v2_top[3];

    // draw edges
    for (new i = 0; i < vertex_count; i++) {
        new next = (i + 1) % vertex_count;

        // get vertex positions
        v1[0] = vertices[i][0];
        v1[1] = vertices[i][1];
        v1[2] = vertices[i][2];

        v2[0] = vertices[next][0];
        v2[1] = vertices[next][1];
        v2[2] = vertices[next][2];

        // always draw bottom edge if in editor mode or always_show_bottom
        if (editor_mode || always_show_bottom) {
            visual_draw_wireframe_line(v1, v2, color, duration_tenths, line_width);
        }

        // only draw top and vertical edges in editor mode
        if (editor_mode) {
            // top edge
            v1_top[0] = v1[0]; v1_top[1] = v1[1]; v1_top[2] = top_z;
            v2_top[0] = v2[0]; v2_top[1] = v2[1]; v2_top[2] = top_z;
            visual_draw_wireframe_line(v1_top, v2_top, color, duration_tenths, line_width);

            // vertical edge from this vertex
            visual_draw_wireframe_line(v1, v1_top, color, duration_tenths, line_width);
        }
    }
}

/**
 * @brief Highlights a wall (vertical face) of a polygon zone
 *
 * @param[in] v1            First vertex of the wall edge (bottom)
 * @param[in] v2            Second vertex of the wall edge (bottom)
 * @param[in] top_z         Z coordinate of the top of the wall
 * @param[in] highlight_color RGB color array for highlight
 * @param[in] duration_tenths Duration in tenths of seconds
 * @param[in] line_width    Width of the lines
 * @param[in] draw_center_x If true, draw X marker at center of wall
 */
stock visual_highlight_polygon_wall(const Float:v1[3], const Float:v2[3], Float:top_z, 
    const highlight_color[3], duration_tenths = 1, line_width = 5, bool:draw_center_x = false)
{
    if (!g_visual_sprite) {
        return;
    }

    new Float:v1_top[3], Float:v2_top[3];
    v1_top[0] = v1[0]; v1_top[1] = v1[1]; v1_top[2] = top_z;
    v2_top[0] = v2[0]; v2_top[1] = v2[1]; v2_top[2] = top_z;

    // draw all 4 edges of the wall quad
    visual_draw_wireframe_line(v1, v2, highlight_color, duration_tenths, line_width);           // bottom
    visual_draw_wireframe_line(v1_top, v2_top, highlight_color, duration_tenths, line_width);   // top
    visual_draw_wireframe_line(v1, v1_top, highlight_color, duration_tenths, line_width);       // left vertical
    visual_draw_wireframe_line(v2, v2_top, highlight_color, duration_tenths, line_width);       // right vertical

    // draw center X if requested
    if (draw_center_x) {
        new Float:center[3];
        center[0] = (v1[0] + v2[0]) / 2.0;
        center[1] = (v1[1] + v2[1]) / 2.0;
        center[2] = (v1[2] + v2[2] + top_z + top_z) / 4.0;  // average of all 4 corners

        // calculate wall direction for proper X orientation
        new Float:dx = v2[0] - v1[0];
        new Float:dy = v2[1] - v1[1];
        new Float:len = floatsqroot(dx * dx + dy * dy);
        if (len > 0.0) {
            dx /= len;
            dy /= len;
        }

        new Float:x_size = 3.0;
        new Float:d1[3], Float:d2[3], Float:d3[3], Float:d4[3];

        // X marker perpendicular to wall
        d1[0] = center[0] - dx * x_size; d1[1] = center[1] - dy * x_size; d1[2] = center[2] - x_size;
        d2[0] = center[0] + dx * x_size; d2[1] = center[1] + dy * x_size; d2[2] = center[2] + x_size;
        d3[0] = center[0] - dx * x_size; d3[1] = center[1] - dy * x_size; d3[2] = center[2] + x_size;
        d4[0] = center[0] + dx * x_size; d4[1] = center[1] + dy * x_size; d4[2] = center[2] - x_size;

        visual_draw_wireframe_line(d1, d2, highlight_color, duration_tenths, line_width);
        visual_draw_wireframe_line(d3, d4, highlight_color, duration_tenths, line_width);
    }
}

/**
 * @brief Highlights the top face of a polygon zone (flat horizontal)
 *
 * @param[in] vertices          2D array of vertex positions [vertex_index][0=x, 1=y, 2=z_bottom]
 * @param[in] vertex_count      Number of vertices in the polygon
 * @param[in] z_level           Z coordinate for the top face
 * @param[in] highlight_color   RGB color array for highlight
 * @param[in] duration_tenths   Duration in tenths of seconds
 * @param[in] line_width        Width of the lines
 * @param[in] draw_center_x     If true, draw X marker at center of face
 */
stock visual_highlight_polygon_top_face(const Float:vertices[][3], vertex_count, Float:z_level, 
    const highlight_color[3], duration_tenths = 1, line_width = 5, bool:draw_center_x = false)
{
    if (!g_visual_sprite || vertex_count < 3) {
        return;
    }

    new Float:p1[3], Float:p2[3];
    new Float:center_x = 0.0, Float:center_y = 0.0;

    // draw all edges of the face at z_level
    for (new i = 0; i < vertex_count; i++) {
        new next = (i + 1) % vertex_count;

        p1[0] = vertices[i][0];
        p1[1] = vertices[i][1];
        p1[2] = z_level;

        p2[0] = vertices[next][0];
        p2[1] = vertices[next][1];
        p2[2] = z_level;

        visual_draw_wireframe_line(p1, p2, highlight_color, duration_tenths, line_width);

        center_x += vertices[i][0];
        center_y += vertices[i][1];
    }

    // draw center X if requested
    if (draw_center_x) {
        center_x /= float(vertex_count);
        center_y /= float(vertex_count);

        new Float:x_size = 3.0;
        new Float:d1[3], Float:d2[3], Float:d3[3], Float:d4[3];

        xs_vec_set(d1, center_x - x_size, center_y - x_size, z_level);
        xs_vec_set(d2, center_x + x_size, center_y + x_size, z_level);
        xs_vec_set(d3, center_x - x_size, center_y + x_size, z_level);
        xs_vec_set(d4, center_x + x_size, center_y - x_size, z_level);

        visual_draw_wireframe_line(d1, d2, highlight_color, duration_tenths, line_width);
        visual_draw_wireframe_line(d3, d4, highlight_color, duration_tenths, line_width);
    }
}

/**
 * @brief Highlights the bottom face of a polygon zone (at each vertex's actual Z height)
 *
 * @param[in] vertices          2D array of vertex positions [vertex_index][0=x, 1=y, 2=z_bottom]
 * @param[in] vertex_count      Number of vertices in the polygon
 * @param[in] highlight_color   RGB color array for highlight
 * @param[in] duration_tenths   Duration in tenths of seconds
 * @param[in] line_width        Width of the lines
 * @param[in] draw_center_x     If true, draw X marker at center of face
 */
stock visual_highlight_polygon_bottom_face(const Float:vertices[][3], vertex_count,
    const highlight_color[3], duration_tenths = 1, line_width = 5, bool:draw_center_x = false)
{
    if (!g_visual_sprite || vertex_count < 3) {
        return;
    }

    new Float:center_x = 0.0, Float:center_y = 0.0, Float:center_z = 0.0;

    // draw all bottom edges at their actual Z heights
    for (new i = 0; i < vertex_count; i++) {
        new next = (i + 1) % vertex_count;

        visual_draw_wireframe_line(vertices[i], vertices[next], highlight_color, duration_tenths, line_width);

        center_x += vertices[i][0];
        center_y += vertices[i][1];
        center_z += vertices[i][2];
    }

    // draw center X if requested
    if (draw_center_x) {
        center_x /= float(vertex_count);
        center_y /= float(vertex_count);
        center_z /= float(vertex_count);

        new Float:x_size = 3.0;
        new Float:d1[3], Float:d2[3], Float:d3[3], Float:d4[3];

        xs_vec_set(d1, center_x - x_size, center_y - x_size, center_z);
        xs_vec_set(d2, center_x + x_size, center_y + x_size, center_z);
        xs_vec_set(d3, center_x - x_size, center_y + x_size, center_z);
        xs_vec_set(d4, center_x + x_size, center_y - x_size, center_z);

        visual_draw_wireframe_line(d1, d2, highlight_color, duration_tenths, line_width);
        visual_draw_wireframe_line(d3, d4, highlight_color, duration_tenths, line_width);
    }
}

/**
 * @brief Ray-quad intersection test for polygon wall detection
 *
 * Tests if a ray intersects a vertical quad (wall) defined by two bottom vertices and a top Z
 *
 * @param[in] ray_origin    Ray starting point
 * @param[in] ray_dir       Ray direction (normalized)
 * @param[in] v1            First bottom vertex of wall
 * @param[in] v2            Second bottom vertex of wall
 * @param[in] top_z         Top Z coordinate
 * @param[out] hit_distance Output: distance to hit point if intersection occurs
 *
 * @return                  true if ray intersects the wall, false otherwise
 */
stock bool:visual_ray_intersects_quad(const Float:ray_origin[3], const Float:ray_dir[3],
    const Float:v1[3], const Float:v2[3], Float:top_z, &Float:hit_distance)
{
    // calculate wall plane normal (perpendicular to wall edge, horizontal)
    new Float:edge[3];
    edge[0] = v2[0] - v1[0];
    edge[1] = v2[1] - v1[1];
    edge[2] = 0.0;  // wall is vertical

    // normal is perpendicular to edge in XY plane
    new Float:normal[3];
    normal[0] = -edge[1];
    normal[1] = edge[0];
    normal[2] = 0.0;

    // normalize
    new Float:len = floatsqroot(normal[0]*normal[0] + normal[1]*normal[1]);
    if (len < 0.0001)
        return false;

    normal[0] /= len;
    normal[1] /= len;

    // calculate D for plane equation (Ax + By + Cz + D = 0)
    new Float:D = -(normal[0] * v1[0] + normal[1] * v1[1]);

    // calculate denominator for ray-plane intersection
    new Float:denom = normal[0] * ray_dir[0] + normal[1] * ray_dir[1];
    if (floatabs(denom) < 0.0001)
        return false;  // ray parallel to plane

    // calculate t (distance along ray)
    new Float:t = -(normal[0] * ray_origin[0] + normal[1] * ray_origin[1] + D) / denom;
    if (t < 0.0 || t > VISUAL_HIGHLIGHT_DISTANCE)
        return false;  // behind ray or too far

    // calculate intersection point
    new Float:hit[3];
    hit[0] = ray_origin[0] + ray_dir[0] * t;
    hit[1] = ray_origin[1] + ray_dir[1] * t;
    hit[2] = ray_origin[2] + ray_dir[2] * t;

    // check if hit point is within quad bounds
    // z bounds
    new Float:min_z = floatmin(v1[2], v2[2]);
    if (hit[2] < min_z || hit[2] > top_z)
        return false;

    // check if hit is between v1 and v2 along the edge
    new Float:edge_len = floatsqroot(edge[0]*edge[0] + edge[1]*edge[1]);
    if (edge_len < 0.0001)
        return false;

    new Float:to_hit[2];
    to_hit[0] = hit[0] - v1[0];
    to_hit[1] = hit[1] - v1[1];

    // project onto edge
    new Float:proj = (to_hit[0] * edge[0] + to_hit[1] * edge[1]) / (edge_len * edge_len);
    if (proj < 0.0 || proj > 1.0)
        return false;

    // check perpendicular distance (should be very close to 0)
    new Float:perp_dist = floatabs(to_hit[0] * normal[0] + to_hit[1] * normal[1]);
    if (perp_dist > 1.0)
        return false;  // small tolerance

    hit_distance = t;
    return true;
}

/**
 * @brief Finds which face of a polygon zone the player is aiming at
 *
 * @param[in] ray_origin    Player's eye position
 * @param[in] ray_dir       Player's aim direction (normalized)
 * @param[in] vertices      2D array of vertex positions [vertex_index][0=x, 1=y, 2=z_bottom]
 * @param[in] vertex_count  Number of vertices in the polygon
 * @param[in] top_z         Z coordinate of the top face
 * @param[in] mins          Bounding box mins for AABB pre-test
 * @param[in] maxs          Bounding box maxs for AABB pre-test
 *
 * @return                  POLYGON_FACE_TOP, POLYGON_FACE_BOTTOM, wall index (0 to vertex_count-1), 
 *                          or POLYGON_FACE_NONE if not aiming at zone
 */
stock visual_get_aimed_polygon_face(const Float:ray_origin[3], const Float:ray_dir[3],
    const Float:vertices[][3], vertex_count, Float:top_z, const Float:mins[3], const Float:maxs[3])
{
    if (vertex_count < 3)
        return POLYGON_FACE_NONE;

    // quick AABB rejection test first
    new Float:aabb_dist;
    if (!visual_ray_intersects_aabb(ray_origin, ray_dir, mins, maxs, aabb_dist)) {
        return POLYGON_FACE_NONE;
    }

    new best_face = POLYGON_FACE_NONE;
    new Float:best_dist = VISUAL_HIGHLIGHT_DISTANCE;

    // calculate average Z for bottom face plane
    new Float:avg_bottom_z = 0.0;
    for (new i = 0; i < vertex_count; i++) {
        avg_bottom_z += vertices[i][2];
    }
    avg_bottom_z /= float(vertex_count);

    // test top face (horizontal plane at top_z)
    if (floatabs(ray_dir[2]) > 0.0001) {
        new Float:t_top = (top_z - ray_origin[2]) / ray_dir[2];
        if (t_top > 0.0 && t_top < best_dist) {
            new Float:hit_x = ray_origin[0] + ray_dir[0] * t_top;
            new Float:hit_y = ray_origin[1] + ray_dir[1] * t_top;

            // point-in-polygon test for top face
            if (visual_point_in_polygon_2d(hit_x, hit_y, vertices, vertex_count)) {
                best_face = POLYGON_FACE_TOP;
                best_dist = t_top;
            }
        }
    }

    // test bottom face - use average Z for the plane test
    if (floatabs(ray_dir[2]) > 0.0001) {
        new Float:t_bottom = (avg_bottom_z - ray_origin[2]) / ray_dir[2];
        if (t_bottom > 0.0 && t_bottom < best_dist) {
            new Float:hit_x = ray_origin[0] + ray_dir[0] * t_bottom;
            new Float:hit_y = ray_origin[1] + ray_dir[1] * t_bottom;

            if (visual_point_in_polygon_2d(hit_x, hit_y, vertices, vertex_count)) {
                best_face = POLYGON_FACE_BOTTOM;
                best_dist = t_bottom;
            }
        }
    }

    // test each wall
    for (new i = 0; i < vertex_count; i++) {
        new next = (i + 1) % vertex_count;

        new Float:wall_dist;
        if (visual_ray_intersects_quad(ray_origin, ray_dir, vertices[i], vertices[next], top_z, wall_dist)) {
            if (wall_dist < best_dist) {
                best_face = i;  // wall index
                best_dist = wall_dist;
            }
        }
    }

    return best_face;
}

/**
 * @brief 2D point-in-polygon test using ray casting
 *
 * @param[in] test_x        X coordinate to test
 * @param[in] test_y        Y coordinate to test
 * @param[in] vertices      2D array of vertex positions [vertex_index][0=x, 1=y, 2=z]
 * @param[in] vertex_count  Number of vertices in the polygon
 *
 * @return                  true if point is inside polygon, false otherwise
 */
stock bool:visual_point_in_polygon_2d(Float:test_x, Float:test_y, const Float:vertices[][3], vertex_count)
{
    if (vertex_count < 3)
        return false;

    new bool:inside = false;
    new j = vertex_count - 1;

    for (new i = 0; i < vertex_count; i++) {
        new Float:xi = vertices[i][0], Float:yi = vertices[i][1];
        new Float:xj = vertices[j][0], Float:yj = vertices[j][1];

        if (((yi > test_y) != (yj > test_y)) &&
            (test_x < (xj - xi) * (test_y - yi) / (yj - yi) + xi)) {
            inside = !inside;
        }

        j = i;
    }

    return inside;
}
