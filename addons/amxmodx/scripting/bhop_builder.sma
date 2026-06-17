#include <amxmodx>
#include <amxmisc>
#include <fakemeta>
#include <engine>

#define PLUGIN_NAME    "Bhop Block Smith & Remover"
#define PLUGIN_VERSION "2.1.0"
#define PLUGIN_AUTHOR  "Codex"

#define MAX_PLAYERS 32
#define MAX_BLOCKS 256
#define TASK_RENDER_BLOCKS 25000
#define BLOCK_ANCHOR_COUNT 8
#define BLOCK_ANCHOR_CLASSNAME "bhop_block_anchor"

new g_beamSprite;
new g_cvarChatPrefix;

new g_grabbedBlock[MAX_PLAYERS + 1];
new bool:g_grabbedViaUse[MAX_PLAYERS + 1];
new Float:g_grabDist[MAX_PLAYERS + 1];

new g_editingBlock[MAX_PLAYERS + 1];
new bool:g_anchorMode[MAX_PLAYERS + 1];
new g_blockAnchors[MAX_PLAYERS + 1][BLOCK_ANCHOR_COUNT];
new g_draggedAnchor[MAX_PLAYERS + 1];
new g_markedAnchor[MAX_PLAYERS + 1];
new Float:g_anchorGrabDist[MAX_PLAYERS + 1];
new g_anchorDragCount[MAX_PLAYERS + 1];

// Undo variables
new Float:g_undoOrigin[MAX_PLAYERS + 1][3];
new Float:g_undoMins[MAX_PLAYERS + 1][3];
new Float:g_undoMaxs[MAX_PLAYERS + 1][3];
new Float:g_undoAngles[MAX_PLAYERS + 1][3];
new g_undoAction[MAX_PLAYERS + 1]; // 0: none, 1: created, 2: deleted, 3: modified
new g_undoEnt[MAX_PLAYERS + 1];
new g_undoSolid[MAX_PLAYERS + 1];
new g_undoEffects[MAX_PLAYERS + 1];
new g_undoRenderMode[MAX_PLAYERS + 1];
new Float:g_undoRenderAmt[MAX_PLAYERS + 1];
new g_undoRemovalIdx[MAX_PLAYERS + 1];

// Removals variables
new Float:g_removedOrigins[256][3];
new g_removedCount;

public plugin_precache()
{
    g_beamSprite = precache_model("sprites/laserbeam.spr");
}

public plugin_init()
{
    register_plugin(PLUGIN_NAME, PLUGIN_VERSION, PLUGIN_AUTHOR);

    register_clcmd("say /build", "CmdBuildMenu");
    register_clcmd("say_team /build", "CmdBuildMenu");
    register_clcmd("say /blocks", "CmdBuildMenu");
    register_clcmd("say_team /blocks", "CmdBuildMenu");

    register_clcmd("say /remove", "CmdRemoveAim");
    register_clcmd("say_team /remove", "CmdRemoveAim");
    register_clcmd("say /undo", "CmdUndo");
    register_clcmd("say_team /undo", "CmdUndo");

    register_clcmd("say /grab", "CmdGrabMenu");
    register_clcmd("say_team /grab", "CmdGrabMenu");
    register_clcmd("say /move", "CmdGrabMenu");
    register_clcmd("say_team /move", "CmdGrabMenu");
    register_clcmd("say /release", "CmdReleaseMenu");
    register_clcmd("say_team /release", "CmdReleaseMenu");
    register_clcmd("say /lock", "CmdReleaseMenu");
    register_clcmd("say_team /lock", "CmdReleaseMenu");

    register_forward(FM_PlayerPreThink, "FwPlayerPreThink");

    g_cvarChatPrefix = register_cvar("bhop_chat_prefix", "[TIMER]");

    set_task(1.5, "TaskRenderBlocks", TASK_RENDER_BLOCKS, _, _, "b");
}

public plugin_cfg()
{
    set_task(2.0, "LoadBlocks");
}

public client_putinserver(id)
{
    g_grabbedBlock[id] = 0;
    g_grabbedViaUse[id] = false;
    g_editingBlock[id] = 0;
    g_anchorMode[id] = false;
    g_draggedAnchor[id] = 0;
    g_markedAnchor[id] = 0;
    g_anchorGrabDist[id] = 0.0;
    g_anchorDragCount[id] = 0;
    g_grabDist[id] = 200.0;
    g_undoAction[id] = 0;
    g_undoEnt[id] = 0;
}

public client_disconnected(id)
{
    ExitBlockAnchorEditor(id, false);
    g_grabbedBlock[id] = 0;
    g_grabbedViaUse[id] = false;
    g_editingBlock[id] = 0;
    g_undoAction[id] = 0;
    g_undoEnt[id] = 0;
}

public CmdGrabMenu(id)
{
    if (!HasAdminAccess(id)) return PLUGIN_HANDLED;
    ExitBlockAnchorEditor(id, false);
    GrabAimedBlock(id);
    return PLUGIN_HANDLED;
}

public CmdReleaseMenu(id)
{
    if (!HasAdminAccess(id)) return PLUGIN_HANDLED;
    ReleaseGrabbedBlock(id);
    return PLUGIN_HANDLED;
}

public CmdBuildMenu(id)
{
    if (!HasAdminAccess(id))
    {
        BuilderChat(id, "You do not have access to the builder menu.");
        return PLUGIN_HANDLED;
    }

    ExitBlockAnchorEditor(id, false);

    new menu = menu_create("Bhop Block Smith Menu", "BuildMenuHandler");

    menu_additem(menu, "Create Horizontal Platform (64x64x16)", "1");
    menu_additem(menu, "Create Vertical Wall (16x64x64)", "2");
    menu_additem(menu, "Edit Aimed Block \y[Precise Menu]", "3");
    menu_additem(menu, "Grab / Move Aimed Block", "4");
    menu_additem(menu, "Release / Lock Block", "5");
    menu_additem(menu, "Delete Aimed Block", "6");
    
    new undoText[64];
    formatex(undoText, charsmax(undoText), "Undo Last Action %s", (g_undoAction[id] > 0) ? "\y[Available]" : "\d[None]");
    menu_additem(menu, undoText, "7");
    
    menu_additem(menu, "Save Platforms & Removals", "8");
    menu_additem(menu, "Reload All Platforms", "9");

    menu_setprop(menu, MPROP_EXIT, MEXIT_ALL);
    menu_display(id, menu, 0);
    return PLUGIN_HANDLED;
}

public BuildMenuHandler(id, menu, item)
{
    if (item == MENU_EXIT)
    {
        menu_destroy(menu);
        return PLUGIN_HANDLED;
    }

    new info[6];
    new access, callback;
    menu_item_getinfo(menu, item, access, info, charsmax(info), _, _, callback);
    menu_destroy(menu);

    new choice = str_to_num(info);
    switch (choice)
    {
        case 1: CreateBhopBlock(id, 0); // Horizontal
        case 2: CreateBhopBlock(id, 1); // Vertical
        case 3:
        {
            new ent, body;
            get_user_aiming(id, ent, body);
            if (pev_valid(ent))
            {
                new classname[32];
                pev(ent, pev_classname, classname, charsmax(classname));
                if (equal(classname, "bhop_block"))
                {
                    CmdEditMenu(id, ent);
                    return PLUGIN_HANDLED;
                }
            }
            BuilderChat(id, "No custom block aimed at.");
        }
        case 4: GrabAimedBlock(id);
        case 5: ReleaseGrabbedBlock(id);
        case 6: DeleteAimedBlock(id);
        case 7: CmdUndo(id);
        case 8: SaveBlocks(id);
        case 9:
        {
            LoadBlocks();
            BuilderChat(id, "All platforms and removals reloaded.");
        }
    }

    if (is_user_connected(id) && choice != 3)
    {
        CmdBuildMenu(id);
    }
    return PLUGIN_HANDLED;
}

stock CreateBhopBlock(id, type)
{
    new Float:origin[3], Float:vAngle[3], Float:forwardVec[3];
    pev(id, pev_origin, origin);
    pev(id, pev_v_angle, vAngle);
    angle_vector(vAngle, ANGLEVECTOR_FORWARD, forwardVec);

    origin[0] += forwardVec[0] * 120.0;
    origin[1] += forwardVec[1] * 120.0;
    origin[2] += forwardVec[2] * 120.0 + 16.0;

    new ent = engfunc(EngFunc_CreateNamedEntity, engfunc(EngFunc_AllocString, "info_target"));
    if (!ent)
    {
        BuilderChat(id, "Could not create block entity.");
        return;
    }

    set_pev(ent, pev_classname, "bhop_block");
    engfunc(EngFunc_SetModel, ent, "sprites/laserbeam.spr");

    set_pev(ent, pev_solid, SOLID_BBOX);
    set_pev(ent, pev_movetype, MOVETYPE_NONE);
    
    set_pev(ent, pev_rendermode, kRenderTransTexture);
    set_pev(ent, pev_renderamt, 0.0);

    new Float:mins[3], Float:maxs[3];
    if (type == 0) // Horizontal
    {
        mins[0] = -32.0; mins[1] = -32.0; mins[2] = -8.0;
        maxs[0] = 32.0;  maxs[1] = 32.0;  maxs[2] = 8.0;
    }
    else // Vertical
    {
        mins[0] = -8.0;  mins[1] = -32.0; mins[2] = -32.0;
        maxs[0] = 8.0;   maxs[1] = 32.0;  maxs[2] = 32.0;
    }

    new Float:angles[3] = {0.0, 0.0, 0.0};
    set_pev(ent, pev_angles, angles);

    engfunc(EngFunc_SetOrigin, ent, origin);
    engfunc(EngFunc_SetSize, ent, mins, maxs);

    g_grabbedBlock[id] = ent;
    g_grabbedViaUse[id] = false;
    g_grabDist[id] = 120.0;

    // Save undo state for creation
    SaveUndoState(id, ent, 1);

    BuilderChat(id, "Block created! Space/Ctrl = Dist, Left Click = Clone Stamp, Right Click = Delete.");
}

stock GrabAimedBlock(id)
{
    new ent, body;
    get_user_aiming(id, ent, body);

    if (pev_valid(ent))
    {
        new classname[32];
        pev(ent, pev_classname, classname, charsmax(classname));

        if (equal(classname, "bhop_block"))
        {
            SaveUndoState(id, ent, 3);
            g_grabbedBlock[id] = ent;
            g_grabbedViaUse[id] = false;
            
            new Float:playerOrigin[3], Float:blockOrigin[3];
            pev(id, pev_origin, playerOrigin);
            pev(ent, pev_origin, blockOrigin);
            
            g_grabDist[id] = get_distance_f(playerOrigin, blockOrigin);
            if (g_grabDist[id] < 60.0) g_grabDist[id] = 60.0;

            BuilderChat(id, "Block grabbed! Space/Ctrl = Dist, Left Click = Clone Stamp, Right Click = Delete.");
            return;
        }
    }
    BuilderChat(id, "No custom block aimed at.");
}

stock ReleaseGrabbedBlock(id)
{
    if (g_grabbedBlock[id])
    {
        g_grabbedBlock[id] = 0;
        g_grabbedViaUse[id] = false;
        BuilderChat(id, "Block locked in place.");
    }
    else
    {
        BuilderChat(id, "You are not holding any blocks.");
    }
}

stock DeleteAimedBlock(id)
{
    new ent, body;
    get_user_aiming(id, ent, body);
    if (pev_valid(ent))
    {
        new classname[32];
        pev(ent, pev_classname, classname, charsmax(classname));
        if (equal(classname, "bhop_block"))
        {
            DeleteGrabbedBlock(id, ent);
            return;
        }
    }
    BuilderChat(id, "No custom block aimed at.");
}

stock DeleteGrabbedBlock(id, ent)
{
    if (!pev_valid(ent)) return;
    
    SaveUndoState(id, ent, 2);

    if (g_grabbedBlock[id] == ent)
    {
        g_grabbedBlock[id] = 0;
        g_grabbedViaUse[id] = false;
    }

    for (new player = 1; player <= MAX_PLAYERS; player++)
    {
        if (g_editingBlock[player] == ent)
        {
            ExitBlockAnchorEditor(player, false);
        }
    }

    set_pev(ent, pev_solid, SOLID_NOT);
    set_pev(ent, pev_effects, pev(ent, pev_effects) | EF_NODRAW);
    set_pev(ent, pev_rendermode, kRenderTransTexture);
    set_pev(ent, pev_renderamt, 0.0);

    BuilderChat(id, "Block deleted.");
}

public CmdRemoveAim(id)
{
    if (!HasAdminAccess(id))
    {
        BuilderChat(id, "You do not have access to the entity remover.");
        return PLUGIN_HANDLED;
    }

    new ent, body;
    get_user_aiming(id, ent, body);

    if (pev_valid(ent))
    {
        new classname[32];
        pev(ent, pev_classname, classname, charsmax(classname));

        if (equal(classname, "worldspawn") || equal(classname, "player") || equal(classname, BLOCK_ANCHOR_CLASSNAME) || ent <= MAX_PLAYERS)
        {
            BuilderChat(id, "You cannot remove this entity.");
            return PLUGIN_HANDLED;
        }

        new Float:origin[3];
        pev(ent, pev_origin, origin);

        SaveUndoState(id, ent, 2);

        if (equal(classname, "bhop_block"))
        {
            g_undoRemovalIdx[id] = -1;
        }
        else
        {
            if (g_removedCount < 256)
            {
                g_removedOrigins[g_removedCount][0] = origin[0];
                g_removedOrigins[g_removedCount][1] = origin[1];
                g_removedOrigins[g_removedCount][2] = origin[2];
                g_undoRemovalIdx[id] = g_removedCount;
                g_removedCount++;
            }
        }

        for (new i = 1; i <= MAX_PLAYERS; i++)
        {
            if (g_grabbedBlock[i] == ent) g_grabbedBlock[i] = 0;
            if (g_editingBlock[i] == ent) ExitBlockAnchorEditor(i, false);
        }

        set_pev(ent, pev_solid, SOLID_NOT);
        set_pev(ent, pev_effects, pev(ent, pev_effects) | EF_NODRAW);
        set_pev(ent, pev_rendermode, kRenderTransTexture);
        set_pev(ent, pev_renderamt, 0.0);

        BuilderChat(id, "Entity %d (%s) hidden/removed.", ent, classname);
    }
    else
    {
        BuilderChat(id, "Aim at an entity to remove it.");
    }
    return PLUGIN_HANDLED;
}

stock SaveUndoState(id, ent, action)
{
    g_undoAction[id] = action;
    g_undoEnt[id] = ent;
    
    if (pev_valid(ent))
    {
        pev(ent, pev_origin, g_undoOrigin[id]);
        pev(ent, pev_mins, g_undoMins[id]);
        pev(ent, pev_maxs, g_undoMaxs[id]);
        pev(ent, pev_angles, g_undoAngles[id]);

        g_undoSolid[id] = pev(ent, pev_solid);
        g_undoEffects[id] = pev(ent, pev_effects);
        g_undoRenderMode[id] = pev(ent, pev_rendermode);
        pev(ent, pev_renderamt, g_undoRenderAmt[id]);
    }
}

public CmdUndo(id)
{
    if (!HasAdminAccess(id)) return PLUGIN_HANDLED;
    if (g_anchorMode[id]) ExitBlockAnchorEditor(id, false);
    
    new action = g_undoAction[id];
    new ent = g_undoEnt[id];
    
    if (action == 0)
    {
        BuilderChat(id, "Nothing to undo.");
        return PLUGIN_HANDLED;
    }
    
    switch (action)
    {
        case 1: // Undo Create -> Hide block
        {
            if (pev_valid(ent))
            {
                set_pev(ent, pev_solid, SOLID_NOT);
                set_pev(ent, pev_effects, pev(ent, pev_effects) | EF_NODRAW);
                set_pev(ent, pev_rendermode, kRenderTransTexture);
                set_pev(ent, pev_renderamt, 0.0);
                BuilderChat(id, "Undo: Created block deleted.");
            }
        }
        case 2: // Undo Delete -> Restore block/entity
        {
            if (pev_valid(ent))
            {
                set_pev(ent, pev_solid, g_undoSolid[id]);
                set_pev(ent, pev_effects, g_undoEffects[id]);
                set_pev(ent, pev_rendermode, g_undoRenderMode[id]);
                set_pev(ent, pev_renderamt, g_undoRenderAmt[id]);

                new idx = g_undoRemovalIdx[id];
                if (idx >= 0 && idx < g_removedCount)
                {
                    if (idx == g_removedCount - 1)
                    {
                        g_removedCount--;
                    }
                    else
                    {
                        for (new i = idx; i < g_removedCount - 1; i++)
                        {
                            g_removedOrigins[i][0] = g_removedOrigins[i+1][0];
                            g_removedOrigins[i][1] = g_removedOrigins[i+1][1];
                            g_removedOrigins[i][2] = g_removedOrigins[i+1][2];
                        }
                        g_removedCount--;
                    }
                }
                BuilderChat(id, "Undo: Entity deletion reverted.");
            }
        }
        case 3: // Undo Modify -> Restore position/size
        {
            if (pev_valid(ent))
            {
                engfunc(EngFunc_SetOrigin, ent, g_undoOrigin[id]);
                set_pev(ent, pev_angles, g_undoAngles[id]);
                engfunc(EngFunc_SetSize, ent, g_undoMins[id], g_undoMaxs[id]);
                if (g_anchorMode[id] && g_editingBlock[id] == ent)
                {
                    CreateBlockAnchors(id, ent);
                }
                BuilderChat(id, "Undo: Platform modification reverted.");
            }
        }
    }
    
    g_undoAction[id] = 0;
    g_undoEnt[id] = 0;
    return PLUGIN_HANDLED;
}

stock bool:IsOwnedBlockAnchor(id, ent)
{
    if (!pev_valid(ent)) return false;

    new classname[32];
    pev(ent, pev_classname, classname, charsmax(classname));
    return equal(classname, BLOCK_ANCHOR_CLASSNAME) && pev(ent, pev_iuser3) == id;
}

stock RemoveBlockAnchors(id)
{
    for (new i = 0; i < BLOCK_ANCHOR_COUNT; i++)
    {
        new anchor = g_blockAnchors[id][i];
        if (pev_valid(anchor))
        {
            engfunc(EngFunc_RemoveEntity, anchor);
        }
        g_blockAnchors[id][i] = 0;
    }

    g_draggedAnchor[id] = 0;
    g_markedAnchor[id] = 0;
    g_anchorGrabDist[id] = 0.0;
}

stock PositionBlockAnchors(id, ent)
{
    if (!pev_valid(ent)) return;

    new Float:origin[3], Float:mins[3], Float:maxs[3], Float:position[3];
    pev(ent, pev_origin, origin);
    pev(ent, pev_mins, mins);
    pev(ent, pev_maxs, maxs);

    for (new corner = 0; corner < BLOCK_ANCHOR_COUNT; corner++)
    {
        new anchor = g_blockAnchors[id][corner];
        if (!pev_valid(anchor)) continue;

        position[0] = origin[0] + ((corner & 1) ? maxs[0] : mins[0]);
        position[1] = origin[1] + ((corner & 2) ? maxs[1] : mins[1]);
        position[2] = origin[2] + ((corner & 4) ? maxs[2] : mins[2]);
        engfunc(EngFunc_SetOrigin, anchor, position);
    }
}

stock CreateBlockAnchors(id, ent)
{
    RemoveBlockAnchors(id);
    if (!pev_valid(ent)) return;

    new Float:origin[3], Float:mins[3], Float:maxs[3], Float:position[3];
    pev(ent, pev_origin, origin);
    pev(ent, pev_mins, mins);
    pev(ent, pev_maxs, maxs);

    for (new corner = 0; corner < BLOCK_ANCHOR_COUNT; corner++)
    {
        position[0] = origin[0] + ((corner & 1) ? maxs[0] : mins[0]);
        position[1] = origin[1] + ((corner & 2) ? maxs[1] : mins[1]);
        position[2] = origin[2] + ((corner & 4) ? maxs[2] : mins[2]);

        new anchor = engfunc(EngFunc_CreateNamedEntity, engfunc(EngFunc_AllocString, "info_target"));
        if (!anchor) continue;

        set_pev(anchor, pev_classname, BLOCK_ANCHOR_CLASSNAME);
        engfunc(EngFunc_SetModel, anchor, "sprites/laserbeam.spr");
        engfunc(EngFunc_SetOrigin, anchor, position);
        engfunc(EngFunc_SetSize, anchor, Float:{-5.0, -5.0, -5.0}, Float:{5.0, 5.0, 5.0});
        set_pev(anchor, pev_solid, SOLID_BBOX);
        set_pev(anchor, pev_movetype, MOVETYPE_NOCLIP);
        set_pev(anchor, pev_iuser1, ent);
        set_pev(anchor, pev_iuser2, corner);
        set_pev(anchor, pev_iuser3, id);
        set_pev(anchor, pev_scale, 0.18);
        set_rendering(anchor, kRenderFxGlowShell, 0, 220, 80, kRenderTransAdd, 255);

        g_blockAnchors[id][corner] = anchor;
    }
}

stock EnterBlockAnchorEditor(id, ent)
{
    if (!pev_valid(ent)) return;

    for (new player = 1; player <= MAX_PLAYERS; player++)
    {
        if (player != id && g_anchorMode[player] && g_editingBlock[player] == ent)
        {
            BuilderChat(id, "This block is already being edited by another admin.");
            CmdEditMenu(id, ent);
            return;
        }
    }

    ExitBlockAnchorEditor(id, false);
    SaveUndoState(id, ent, 3);

    new Float:angles[3] = {0.0, 0.0, 0.0};
    set_pev(ent, pev_angles, angles);

    g_anchorMode[id] = true;
    g_editingBlock[id] = ent;
    g_anchorDragCount[id] = 0;
    CreateBlockAnchors(id, ent);

    BuilderChat(id, "3D editor: hold left click on a corner to resize. Right click exits.");
}

stock ExitBlockAnchorEditor(id, bool:openMenu)
{
    new ent = g_editingBlock[id];
    RemoveBlockAnchors(id);
    g_anchorMode[id] = false;
    g_anchorDragCount[id] = 0;
    g_editingBlock[id] = 0;

    if (openMenu && is_user_connected(id) && pev_valid(ent))
    {
        CmdEditMenu(id, ent);
    }
}

stock BeginBlockAnchorDrag(id, anchor)
{
    if (!IsOwnedBlockAnchor(id, anchor)) return;

    if (g_anchorDragCount[id] > 0)
    {
        new ent = pev(anchor, pev_iuser1);
        if (pev_valid(ent)) SaveUndoState(id, ent, 3);
    }

    g_anchorDragCount[id]++;
    g_draggedAnchor[id] = anchor;

    new Float:eye[3], Float:viewOffset[3], Float:anchorOrigin[3];
    pev(id, pev_origin, eye);
    pev(id, pev_view_ofs, viewOffset);
    eye[0] += viewOffset[0];
    eye[1] += viewOffset[1];
    eye[2] += viewOffset[2];
    pev(anchor, pev_origin, anchorOrigin);
    g_anchorGrabDist[id] = get_distance_f(eye, anchorOrigin);
    if (g_anchorGrabDist[id] < 32.0) g_anchorGrabDist[id] = 32.0;

    set_rendering(anchor, kRenderFxGlowShell, 255, 40, 40, kRenderTransAdd, 255);
}

stock EndBlockAnchorDrag(id)
{
    new anchor = g_draggedAnchor[id];
    if (IsOwnedBlockAnchor(id, anchor))
    {
        set_rendering(anchor, kRenderFxGlowShell, 0, 220, 80, kRenderTransAdd, 255);
    }
    g_draggedAnchor[id] = 0;
    g_anchorGrabDist[id] = 0.0;
}

stock MoveBlockAnchor(id, anchor)
{
    if (!IsOwnedBlockAnchor(id, anchor)) return;

    new ent = pev(anchor, pev_iuser1);
    new corner = pev(anchor, pev_iuser2);
    if (!pev_valid(ent) || ent != g_editingBlock[id] || corner < 0 || corner >= BLOCK_ANCHOR_COUNT)
    {
        ExitBlockAnchorEditor(id, false);
        return;
    }

    new opposite = g_blockAnchors[id][corner ^ 7];
    if (!IsOwnedBlockAnchor(id, opposite)) return;

    new Float:eye[3], Float:viewOffset[3], Float:viewAngles[3], Float:forwardVec[3], Float:target[3];
    pev(id, pev_origin, eye);
    pev(id, pev_view_ofs, viewOffset);
    eye[0] += viewOffset[0];
    eye[1] += viewOffset[1];
    eye[2] += viewOffset[2];
    pev(id, pev_v_angle, viewAngles);
    angle_vector(viewAngles, ANGLEVECTOR_FORWARD, forwardVec);

    target[0] = eye[0] + forwardVec[0] * g_anchorGrabDist[id];
    target[1] = eye[1] + forwardVec[1] * g_anchorGrabDist[id];
    target[2] = eye[2] + forwardVec[2] * g_anchorGrabDist[id];

    new trace = create_tr2();
    engfunc(EngFunc_TraceLine, eye, target, IGNORE_MONSTERS, id, trace);
    new Float:fraction;
    get_tr2(trace, TR_flFraction, fraction);
    if (fraction < 1.0)
    {
        new Float:normal[3];
        get_tr2(trace, TR_vecEndPos, target);
        get_tr2(trace, TR_vecPlaneNormal, normal);
        target[0] += normal[0] * 4.0;
        target[1] += normal[1] * 4.0;
        target[2] += normal[2] * 4.0;
    }
    free_tr2(trace);

    target[0] = floatround(target[0] / 8.0) * 8.0;
    target[1] = floatround(target[1] / 8.0) * 8.0;
    target[2] = floatround(target[2] / 4.0) * 4.0;

    new Float:fixed[3];
    pev(opposite, pev_origin, fixed);

    if (corner & 1) target[0] = floatmax(target[0], fixed[0] + 16.0);
    else target[0] = floatmin(target[0], fixed[0] - 16.0);

    if (corner & 2) target[1] = floatmax(target[1], fixed[1] + 16.0);
    else target[1] = floatmin(target[1], fixed[1] - 16.0);

    if (corner & 4) target[2] = floatmax(target[2], fixed[2] + 8.0);
    else target[2] = floatmin(target[2], fixed[2] - 8.0);

    new Float:absoluteMins[3], Float:absoluteMaxs[3];
    for (new axis = 0; axis < 3; axis++)
    {
        absoluteMins[axis] = floatmin(target[axis], fixed[axis]);
        absoluteMaxs[axis] = floatmax(target[axis], fixed[axis]);
    }

    new Float:origin[3], Float:mins[3], Float:maxs[3];
    for (new axis = 0; axis < 3; axis++)
    {
        origin[axis] = (absoluteMins[axis] + absoluteMaxs[axis]) * 0.5;
        mins[axis] = absoluteMins[axis] - origin[axis];
        maxs[axis] = absoluteMaxs[axis] - origin[axis];
    }

    engfunc(EngFunc_SetOrigin, ent, origin);
    engfunc(EngFunc_SetSize, ent, mins, maxs);
    PositionBlockAnchors(id, ent);
}

stock HandleBlockAnchorEditor(id)
{
    new ent = g_editingBlock[id];
    if (!pev_valid(ent))
    {
        ExitBlockAnchorEditor(id, false);
        return;
    }

    new buttons = pev(id, pev_button);
    new oldbuttons = pev(id, pev_oldbuttons);

    if ((buttons & IN_ATTACK2) && !(oldbuttons & IN_ATTACK2))
    {
        buttons &= ~IN_ATTACK2;
        set_pev(id, pev_button, buttons);
        ExitBlockAnchorEditor(id, true);
        return;
    }

    if (g_draggedAnchor[id])
    {
        if (buttons & IN_ATTACK)
        {
            MoveBlockAnchor(id, g_draggedAnchor[id]);
            buttons &= ~IN_ATTACK;
            set_pev(id, pev_button, buttons);
        }
        else
        {
            EndBlockAnchorDrag(id);
        }
        return;
    }

    new aimed, body;
    get_user_aiming(id, aimed, body, 2048);
    if (!IsOwnedBlockAnchor(id, aimed)) aimed = 0;

    if (g_markedAnchor[id] != aimed)
    {
        if (IsOwnedBlockAnchor(id, g_markedAnchor[id]))
        {
            set_rendering(g_markedAnchor[id], kRenderFxGlowShell, 0, 220, 80, kRenderTransAdd, 255);
        }
        g_markedAnchor[id] = aimed;
        if (aimed)
        {
            set_rendering(aimed, kRenderFxGlowShell, 255, 220, 0, kRenderTransAdd, 255);
        }
    }

    if (aimed && (buttons & IN_ATTACK) && !(oldbuttons & IN_ATTACK))
    {
        BeginBlockAnchorDrag(id, aimed);
        MoveBlockAnchor(id, aimed);
        buttons &= ~IN_ATTACK;
        set_pev(id, pev_button, buttons);
    }
}

public FwPlayerPreThink(id)
{
    if (!is_user_alive(id) || !HasAdminAccess(id))
    {
        if (g_anchorMode[id]) ExitBlockAnchorEditor(id, false);
        return FMRES_IGNORED;
    }

    if (g_anchorMode[id])
    {
        HandleBlockAnchorEditor(id);
        return FMRES_IGNORED;
    }

    new buttons = pev(id, pev_button);
    new oldbuttons = pev(id, pev_oldbuttons);
    new grabbed = g_grabbedBlock[id];

    // E (USE) key grab behavior
    if (buttons & IN_USE)
    {
        if (!grabbed)
        {
            if (!(oldbuttons & IN_USE))
            {
                new ent, body;
                get_user_aiming(id, ent, body);
                if (pev_valid(ent))
                {
                    new classname[32];
                    pev(ent, pev_classname, classname, charsmax(classname));
                    if (equal(classname, "bhop_block"))
                    {
                        new Float:playerOrigin[3], Float:blockOrigin[3];
                        pev(id, pev_origin, playerOrigin);
                        pev(ent, pev_origin, blockOrigin);
                        new Float:dist = get_distance_f(playerOrigin, blockOrigin);
                        if (dist <= 500.0)
                        {
                            SaveUndoState(id, ent, 3);
                            g_grabbedBlock[id] = ent;
                            g_grabbedViaUse[id] = true;
                            g_grabDist[id] = dist;
                            if (g_grabDist[id] < 60.0) g_grabDist[id] = 60.0;
                            client_print(id, print_center, "Block grabbed!");
                        }
                    }
                }
            }
        }
    }
    else
    {
        if (grabbed && g_grabbedViaUse[id])
        {
            g_grabbedBlock[id] = 0;
            g_grabbedViaUse[id] = false;
            client_print(id, print_center, "Block locked.");
        }
    }

    grabbed = g_grabbedBlock[id];

    if (grabbed && pev_valid(grabbed))
    {
        // Push / Pull block using Jump / Duck keys
        if (buttons & IN_JUMP)
        {
            g_grabDist[id] += 4.0;
            if (g_grabDist[id] > 1000.0) g_grabDist[id] = 1000.0;
            buttons &= ~IN_JUMP;
        }
        else if (buttons & IN_DUCK)
        {
            g_grabDist[id] -= 4.0;
            if (g_grabDist[id] < 60.0) g_grabDist[id] = 60.0;
            buttons &= ~IN_DUCK;
        }

        // Left Click -> Stamp block
        if ((buttons & IN_ATTACK) && !(oldbuttons & IN_ATTACK))
        {
            StampBlock(id, grabbed);
            buttons &= ~IN_ATTACK;
        }
        // Right Click -> Delete block
        else if ((buttons & IN_ATTACK2) && !(oldbuttons & IN_ATTACK2))
        {
            DeleteGrabbedBlock(id, grabbed);
            buttons &= ~IN_ATTACK2;
        }

        set_pev(id, pev_button, buttons);

        // Move the block in front of the player
        grabbed = g_grabbedBlock[id];
        if (grabbed && pev_valid(grabbed))
        {
            new Float:origin[3], Float:vAngle[3], Float:forwardVec[3], Float:targetOrigin[3];
            pev(id, pev_origin, origin);
            pev(id, pev_v_angle, vAngle);
            angle_vector(vAngle, ANGLEVECTOR_FORWARD, forwardVec);

            new Float:eyes[3];
            pev(id, pev_view_ofs, eyes);
            origin[0] += eyes[0];
            origin[1] += eyes[1];
            origin[2] += eyes[2];

            targetOrigin[0] = origin[0] + forwardVec[0] * g_grabDist[id];
            targetOrigin[1] = origin[1] + forwardVec[1] * g_grabDist[id];
            targetOrigin[2] = origin[2] + forwardVec[2] * g_grabDist[id];

            // Snapping to grid (X/Y: 8 units, Z: 4 units)
            targetOrigin[0] = floatround(targetOrigin[0] / 8.0) * 8.0;
            targetOrigin[1] = floatround(targetOrigin[1] / 8.0) * 8.0;
            targetOrigin[2] = floatround(targetOrigin[2] / 4.0) * 4.0;

            engfunc(EngFunc_SetOrigin, grabbed, targetOrigin);
        }
    }

    return FMRES_IGNORED;
}

stock StampBlock(id, ent)
{
    if (!pev_valid(ent)) return;

    new Float:origin[3], Float:vAngle[3], Float:forwardVec[3];
    pev(id, pev_origin, origin);
    pev(id, pev_v_angle, vAngle);
    angle_vector(vAngle, ANGLEVECTOR_FORWARD, forwardVec);

    new Float:blockOrigin[3], Float:angles[3], Float:mins[3], Float:maxs[3];
    pev(ent, pev_origin, blockOrigin);
    pev(ent, pev_angles, angles);
    pev(ent, pev_mins, mins);
    pev(ent, pev_maxs, maxs);

    // Lock current block
    g_grabbedBlock[id] = 0;
    g_grabbedViaUse[id] = false;
    client_print(id, print_center, "Block placed!");

    // Spawn clone at current position and grab it!
    new newEnt = engfunc(EngFunc_CreateNamedEntity, engfunc(EngFunc_AllocString, "info_target"));
    if (newEnt)
    {
        set_pev(newEnt, pev_classname, "bhop_block");
        engfunc(EngFunc_SetModel, newEnt, "sprites/laserbeam.spr");
        set_pev(newEnt, pev_solid, SOLID_BBOX);
        set_pev(newEnt, pev_movetype, MOVETYPE_NONE);
        set_pev(newEnt, pev_rendermode, kRenderTransTexture);
        set_pev(newEnt, pev_renderamt, 0.0);

        engfunc(EngFunc_SetOrigin, newEnt, blockOrigin);
        set_pev(newEnt, pev_angles, angles);
        engfunc(EngFunc_SetSize, newEnt, mins, maxs);

        SaveUndoState(id, newEnt, 1);
        
        g_grabbedBlock[id] = newEnt;
        g_grabbedViaUse[id] = false;
    }
}

stock CloneBlock(id, ent)
{
    if (!pev_valid(ent)) return 0;

    new Float:origin[3], Float:angles[3], Float:mins[3], Float:maxs[3];
    pev(ent, pev_origin, origin);
    pev(ent, pev_angles, angles);
    pev(ent, pev_mins, mins);
    pev(ent, pev_maxs, maxs);

    origin[0] += 32.0;
    origin[1] += 32.0;

    new newEnt = engfunc(EngFunc_CreateNamedEntity, engfunc(EngFunc_AllocString, "info_target"));
    if (newEnt)
    {
        set_pev(newEnt, pev_classname, "bhop_block");
        engfunc(EngFunc_SetModel, newEnt, "sprites/laserbeam.spr");
        set_pev(newEnt, pev_solid, SOLID_BBOX);
        set_pev(newEnt, pev_movetype, MOVETYPE_NONE);
        set_pev(newEnt, pev_rendermode, kRenderTransTexture);
        set_pev(newEnt, pev_renderamt, 0.0);

        engfunc(EngFunc_SetOrigin, newEnt, origin);
        set_pev(newEnt, pev_angles, angles);
        engfunc(EngFunc_SetSize, newEnt, mins, maxs);

        SaveUndoState(id, newEnt, 1);
        BuilderChat(id, "Block cloned!");
        return newEnt;
    }
    return 0;
}

public CmdEditMenu(id, ent)
{
    if (!HasAdminAccess(id)) return;
    if (!pev_valid(ent)) return;

    g_editingBlock[id] = ent;

    new Float:mins[3], Float:maxs[3], Float:origin[3], Float:angles[3];
    pev(ent, pev_mins, mins);
    pev(ent, pev_maxs, maxs);
    pev(ent, pev_origin, origin);
    pev(ent, pev_angles, angles);

    new Float:sizeX = maxs[0] - mins[0];
    new Float:sizeY = maxs[1] - mins[1];
    new Float:sizeZ = maxs[2] - mins[2];

    new menuTitle[128];
    formatex(menuTitle, charsmax(menuTitle), "Bhop Block Editor - [Block %d]^nOrigin: %.0f, %.0f, %.0f", ent, origin[0], origin[1], origin[2]);
    new menu = menu_create(menuTitle, "EditMenuHandler");

    new itemText[96];
    formatex(itemText, charsmax(itemText), "Width (X): %.0f \y[+16]", sizeX);
    menu_additem(menu, itemText, "1");

    formatex(itemText, charsmax(itemText), "Width (X): %.0f \r[-16]", sizeX);
    menu_additem(menu, itemText, "2");

    formatex(itemText, charsmax(itemText), "Length (Y): %.0f \y[+16]", sizeY);
    menu_additem(menu, itemText, "3");

    formatex(itemText, charsmax(itemText), "Length (Y): %.0f \r[-16]", sizeY);
    menu_additem(menu, itemText, "4");

    formatex(itemText, charsmax(itemText), "Height (Z): %.0f \y[+8]", sizeZ);
    menu_additem(menu, itemText, "5");

    formatex(itemText, charsmax(itemText), "Height (Z): %.0f \r[-8]", sizeZ);
    menu_additem(menu, itemText, "6");

    formatex(itemText, charsmax(itemText), "Rotate Yaw: %.0f° \y[+15°]", angles[1]);
    menu_additem(menu, itemText, "7");

    menu_additem(menu, "Snap to Grid", "8");
    menu_additem(menu, "Snap/Drop to Ground", "9");
    menu_additem(menu, "Clone / Copy Block", "10");
    menu_additem(menu, "Grab Block", "11");
    menu_additem(menu, "Delete Block", "12");
    menu_additem(menu, "3D Corner Editor", "13");

    menu_setprop(menu, MPROP_EXIT, MEXIT_ALL);
    menu_display(id, menu, 0);
}

public EditMenuHandler(id, menu, item)
{
    if (item == MENU_EXIT)
    {
        g_editingBlock[id] = 0;
        menu_destroy(menu);
        if (is_user_connected(id))
        {
            CmdBuildMenu(id);
        }
        return PLUGIN_HANDLED;
    }

    new info[6];
    new access, callback;
    menu_item_getinfo(menu, item, access, info, charsmax(info), _, _, callback);
    menu_destroy(menu);

    new ent = g_editingBlock[id];
    if (!pev_valid(ent))
    {
        g_editingBlock[id] = 0;
        if (is_user_connected(id))
        {
            CmdBuildMenu(id);
        }
        return PLUGIN_HANDLED;
    }

    new choice = str_to_num(info);
    new Float:mins[3], Float:maxs[3], Float:origin[3], Float:angles[3];
    pev(ent, pev_mins, mins);
    pev(ent, pev_maxs, maxs);
    pev(ent, pev_origin, origin);
    pev(ent, pev_angles, angles);

    switch (choice)
    {
        case 1: // Width (X) +16
        {
            SaveUndoState(id, ent, 3);
            maxs[0] += 8.0; mins[0] -= 8.0;
            engfunc(EngFunc_SetSize, ent, mins, maxs);
        }
        case 2: // Width (X) -16
        {
            new Float:sizeX = maxs[0] - mins[0];
            if (sizeX > 16.0)
            {
                SaveUndoState(id, ent, 3);
                maxs[0] -= 8.0; mins[0] += 8.0;
                engfunc(EngFunc_SetSize, ent, mins, maxs);
            }
            else
            {
                client_print(id, print_center, "Minimum size reached!");
            }
        }
        case 3: // Length (Y) +16
        {
            SaveUndoState(id, ent, 3);
            maxs[1] += 8.0; mins[1] -= 8.0;
            engfunc(EngFunc_SetSize, ent, mins, maxs);
        }
        case 4: // Length (Y) -16
        {
            new Float:sizeY = maxs[1] - mins[1];
            if (sizeY > 16.0)
            {
                SaveUndoState(id, ent, 3);
                maxs[1] -= 8.0; mins[1] += 8.0;
                engfunc(EngFunc_SetSize, ent, mins, maxs);
            }
            else
            {
                client_print(id, print_center, "Minimum size reached!");
            }
        }
        case 5: // Height (Z) +8
        {
            SaveUndoState(id, ent, 3);
            maxs[2] += 4.0; mins[2] -= 4.0;
            engfunc(EngFunc_SetSize, ent, mins, maxs);
        }
        case 6: // Height (Z) -8
        {
            new Float:sizeZ = maxs[2] - mins[2];
            if (sizeZ > 8.0)
            {
                SaveUndoState(id, ent, 3);
                maxs[2] -= 4.0; mins[2] += 4.0;
                engfunc(EngFunc_SetSize, ent, mins, maxs);
            }
            else
            {
                client_print(id, print_center, "Minimum size reached!");
            }
        }
        case 7: // Rotate Yaw +15°
        {
            SaveUndoState(id, ent, 3);
            angles[1] += 15.0;
            if (angles[1] >= 360.0) angles[1] -= 360.0;
            set_pev(ent, pev_angles, angles);
        }
        case 8: // Snap to Grid
        {
            SaveUndoState(id, ent, 3);
            origin[0] = floatround(origin[0] / 8.0) * 8.0;
            origin[1] = floatround(origin[1] / 8.0) * 8.0;
            origin[2] = floatround(origin[2] / 4.0) * 4.0;
            engfunc(EngFunc_SetOrigin, ent, origin);
        }
        case 9: // Snap to Ground
        {
            SaveUndoState(id, ent, 3);
            new Float:end[3];
            end[0] = origin[0]; end[1] = origin[1]; end[2] = origin[2] - 1000.0;
            new trace = create_tr2();
            engfunc(EngFunc_TraceLine, origin, end, IGNORE_MONSTERS, ent, trace);
            new Float:hit[3];
            get_tr2(trace, TR_vecEndPos, hit);
            free_tr2(trace);
            origin[2] = hit[2] - mins[2];
            engfunc(EngFunc_SetOrigin, ent, origin);
        }
        case 10: // Clone Block
        {
            new clone = CloneBlock(id, ent);
            if (clone)
            {
                g_editingBlock[id] = clone;
                ent = clone;
            }
        }
        case 11: // Grab Block
        {
            g_grabbedBlock[id] = ent;
            g_grabbedViaUse[id] = false;
            new Float:playerOrigin[3];
            pev(id, pev_origin, playerOrigin);
            g_grabDist[id] = get_distance_f(playerOrigin, origin);
            if (g_grabDist[id] < 60.0) g_grabDist[id] = 60.0;
            
            g_editingBlock[id] = 0;
            menu_destroy(menu);
            BuilderChat(id, "Block grabbed! Release from main menu or E key.");
            return PLUGIN_HANDLED;
        }
        case 12: // Delete Block
        {
            DeleteGrabbedBlock(id, ent);
            g_editingBlock[id] = 0;
            menu_destroy(menu);
            if (is_user_connected(id))
            {
                CmdBuildMenu(id);
            }
            return PLUGIN_HANDLED;
        }
        case 13: // 3D corner editor
        {
            EnterBlockAnchorEditor(id, ent);
            return PLUGIN_HANDLED;
        }
    }

    if (is_user_connected(id) && g_editingBlock[id] == ent)
    {
        CmdEditMenu(id, ent);
    }
    return PLUGIN_HANDLED;
}

public TaskRenderBlocks()
{
    new Float:playerOrigin[3];
    new Float:blockOrigin[3];

    for (new i = 1; i <= MAX_PLAYERS; i++)
    {
        if (is_user_connected(i) && !is_user_bot(i))
        {
            pev(i, pev_origin, playerOrigin);

            new ent = -1;
            while ((ent = engfunc(EngFunc_FindEntityByString, ent, "classname", "bhop_block")) != 0)
            {
                if (pev_valid(ent))
                {
                    new effects = pev(ent, pev_effects);
                    if (!(effects & EF_NODRAW))
                    {
                        pev(ent, pev_origin, blockOrigin);

                        new Float:dx = playerOrigin[0] - blockOrigin[0];
                        new Float:dy = playerOrigin[1] - blockOrigin[1];
                        new Float:dz = playerOrigin[2] - blockOrigin[2];

                        // Only render the block if within 1200 units of the player, or if the player is actively grabbing/editing it
                        if (ent == g_grabbedBlock[i] || ent == g_editingBlock[i] || (dx * dx + dy * dy + dz * dz) <= 1440000.0)
                        {
                            RenderLaserBox(i, ent);
                        }
                    }
                }
            }
        }
    }
}

stock RenderLaserBox(id, ent)
{
    new Float:origin[3], Float:mins[3], Float:maxs[3], Float:angles[3];
    pev(ent, pev_origin, origin);
    pev(ent, pev_mins, mins);
    pev(ent, pev_maxs, maxs);
    pev(ent, pev_angles, angles);

    new Float:v[8][3];
    new Float:yawRad = angles[1] * (3.14159265 / 180.0);
    new Float:cosY = floatcos(yawRad);
    new Float:sinY = floatsin(yawRad);

    new idx = 0;
    for (new x = 0; x < 2; x++)
    {
        for (new y = 0; y < 2; y++)
        {
            for (new z = 0; z < 2; z++)
            {
                new Float:localX = (x == 0) ? mins[0] : maxs[0];
                new Float:localY = (y == 0) ? mins[1] : maxs[1];
                new Float:localZ = (z == 0) ? mins[2] : maxs[2];

                v[idx][0] = origin[0] + (localX * cosY - localY * sinY);
                v[idx][1] = origin[1] + (localX * sinY + localY * cosY);
                v[idx][2] = origin[2] + localZ;
                idx++;
            }
        }
    }

    DrawBlockBeam(id, v[0], v[1]);
    DrawBlockBeam(id, v[2], v[3]);
    DrawBlockBeam(id, v[4], v[5]);
    DrawBlockBeam(id, v[6], v[7]);

    DrawBlockBeam(id, v[0], v[2]);
    DrawBlockBeam(id, v[1], v[3]);
    DrawBlockBeam(id, v[4], v[6]);
    DrawBlockBeam(id, v[5], v[7]);

    DrawBlockBeam(id, v[0], v[4]);
    DrawBlockBeam(id, v[1], v[5]);
    DrawBlockBeam(id, v[2], v[6]);
    DrawBlockBeam(id, v[3], v[7]);
}

stock DrawBlockBeam(id, const Float:start[3], const Float:end[3])
{
    if (!g_beamSprite) return;

    message_begin(MSG_ONE_UNRELIABLE, SVC_TEMPENTITY, _, id);
    write_byte(0); // TE_BEAMPOINTS
    write_coord(floatround(start[0]));
    write_coord(floatround(start[1]));
    write_coord(floatround(start[2]));
    write_coord(floatround(end[0]));
    write_coord(floatround(end[1]));
    write_coord(floatround(end[2]));
    write_short(g_beamSprite);
    write_byte(0);
    write_byte(0);
    write_byte(18); // Life in 0.1s (1.8s) - matches the 1.5s task frequency with buffer overlap
    write_byte(4);  // Width
    write_byte(0);
    write_byte(0);
    write_byte(240);
    write_byte(255);
    write_byte(180);
    write_byte(0);
    message_end();
}

public SaveBlocks(id)
{
    new mapName[32], path[128], configDir[128];
    get_mapname(mapName, charsmax(mapName));
    get_configsdir(configDir, charsmax(configDir));
    
    // 1. Save custom blocks
    format(path, charsmax(path), "%s/bhop_blocks_%s.cfg", configDir, mapName);
    new fp = fopen(path, "wt");
    if (!fp)
    {
        BuilderChat(id, "Could not save custom blocks.");
        return;
    }
    
    new ent = -1, blockCount = 0;
    while ((ent = engfunc(EngFunc_FindEntityByString, ent, "classname", "bhop_block")) != 0)
    {
        if (pev_valid(ent))
        {
            new effects = pev(ent, pev_effects);
            if (effects & EF_NODRAW) continue; // Skip hidden/deleted blocks!

            new Float:origin[3], Float:angles[3], Float:mins[3], Float:maxs[3];
            pev(ent, pev_origin, origin);
            pev(ent, pev_angles, angles);
            pev(ent, pev_mins, mins);
            pev(ent, pev_maxs, maxs);

            fprintf(fp, "%.2f %.2f %.2f %.2f %.2f %.2f %.2f %.2f %.2f %.2f %.2f %.2f^n",
                origin[0], origin[1], origin[2],
                angles[0], angles[1], angles[2],
                mins[0], mins[1], mins[2],
                maxs[0], maxs[1], maxs[2]);
            blockCount++;
        }
    }
    fclose(fp);

    // 2. Save removed entities
    format(path, charsmax(path), "%s/bhop_removals_%s.cfg", configDir, mapName);
    fp = fopen(path, "wt");
    if (fp)
    {
        for (new i = 0; i < g_removedCount; i++)
        {
            fprintf(fp, "%.2f %.2f %.2f^n", g_removedOrigins[i][0], g_removedOrigins[i][1], g_removedOrigins[i][2]);
        }
        fclose(fp);
    }
    
    BuilderChat(id, "Saved: %d blocks, %d removed entities.", blockCount, g_removedCount);
}

public LoadBlocks()
{
    for (new player = 1; player <= MAX_PLAYERS; player++)
    {
        ExitBlockAnchorEditor(player, false);
        g_grabbedBlock[player] = 0;
        g_grabbedViaUse[player] = false;
    }

    // Clean custom blocks
    new ent = -1;
    while ((ent = engfunc(EngFunc_FindEntityByString, ent, "classname", "bhop_block")) != 0)
    {
        if (pev_valid(ent))
        {
            engfunc(EngFunc_RemoveEntity, ent);
        }
    }

    new mapName[32], path[128], configDir[128];
    get_mapname(mapName, charsmax(mapName));
    get_configsdir(configDir, charsmax(configDir));
    
    // Load blocks
    format(path, charsmax(path), "%s/bhop_blocks_%s.cfg", configDir, mapName);
    if (file_exists(path))
    {
        new fp = fopen(path, "rt");
        if (fp)
        {
            new line[256];
            while (!feof(fp))
            {
                fgets(fp, line, charsmax(line));
                trim(line);

                if (!line[0]) continue;

                new sOriginX[16], sOriginY[16], sOriginZ[16];
                new sAngleX[16], sAngleY[16], sAngleZ[16];
                new sMinsX[16], sMinsY[16], sMinsZ[16];
                new sMaxsX[16], sMaxsY[16], sMaxsZ[16];

                parse(line,
                    sOriginX, charsmax(sOriginX), sOriginY, charsmax(sOriginY), sOriginZ, charsmax(sOriginZ),
                    sAngleX, charsmax(sAngleX), sAngleY, charsmax(sAngleY), sAngleZ, charsmax(sAngleZ),
                    sMinsX, charsmax(sMinsX), sMinsY, charsmax(sMinsY), sMinsZ, charsmax(sMinsZ),
                    sMaxsX, charsmax(sMaxsX), sMaxsY, charsmax(sMaxsY), sMaxsZ, charsmax(sMaxsZ));

                new Float:origin[3], Float:angles[3], Float:mins[3], Float:maxs[3];
                origin[0] = str_to_float(sOriginX); origin[1] = str_to_float(sOriginY); origin[2] = str_to_float(sOriginZ);
                angles[0] = str_to_float(sAngleX); angles[1] = str_to_float(sAngleY); angles[2] = str_to_float(sAngleZ);
                mins[0] = str_to_float(sMinsX); mins[1] = str_to_float(sMinsY); mins[2] = str_to_float(sMinsZ);
                maxs[0] = str_to_float(sMaxsX); maxs[1] = str_to_float(sMaxsY); maxs[2] = str_to_float(sMaxsZ);

                new block = engfunc(EngFunc_CreateNamedEntity, engfunc(EngFunc_AllocString, "info_target"));
                if (block)
                {
                    set_pev(block, pev_classname, "bhop_block");
                    engfunc(EngFunc_SetModel, block, "sprites/laserbeam.spr");
                    set_pev(block, pev_solid, SOLID_BBOX);
                    set_pev(block, pev_movetype, MOVETYPE_NONE);
                    set_pev(block, pev_rendermode, kRenderTransTexture);
                    set_pev(block, pev_renderamt, 0.0);

                    engfunc(EngFunc_SetOrigin, block, origin);
                    set_pev(block, pev_angles, angles);
                    engfunc(EngFunc_SetSize, block, mins, maxs);
                }
            }
            fclose(fp);
        }
    }

    // Load and apply entity removals
    g_removedCount = 0;
    format(path, charsmax(path), "%s/bhop_removals_%s.cfg", configDir, mapName);
    if (file_exists(path))
    {
        new fp = fopen(path, "rt");
        if (fp)
        {
            new line[128];
            while (!feof(fp))
            {
                fgets(fp, line, charsmax(line));
                trim(line);

                if (!line[0]) continue;

                new sX[16], sY[16], sZ[16];
                parse(line, sX, charsmax(sX), sY, charsmax(sY), sZ, charsmax(sZ));

                new Float:origin[3];
                origin[0] = str_to_float(sX);
                origin[1] = str_to_float(sY);
                origin[2] = str_to_float(sZ);

                if (g_removedCount < 256)
                {
                    g_removedOrigins[g_removedCount][0] = origin[0];
                    g_removedOrigins[g_removedCount][1] = origin[1];
                    g_removedOrigins[g_removedCount][2] = origin[2];
                    g_removedCount++;
                }

                new removeEnt = -1;
                while ((removeEnt = engfunc(EngFunc_FindEntityInSphere, removeEnt, origin, 8.0)) != 0)
                {
                    if (pev_valid(removeEnt) && removeEnt > 32)
                    {
                        new classname[32];
                        pev(removeEnt, pev_classname, classname, charsmax(classname));
                        if (!equal(classname, "bhop_block") && !equal(classname, "worldspawn") && !equal(classname, "player"))
                        {
                            engfunc(EngFunc_RemoveEntity, removeEnt);
                        }
                    }
                }
            }
            fclose(fp);
        }
    }
}

bool:HasAdminAccess(id)
{
    return (get_user_flags(id) & ADMIN_RCON) != 0;
}

BuilderChat(id, const fmt[], any:...)
{
    new message[192], finalMessage[192], prefix[32];
    vformat(message, charsmax(message), fmt, 3);
    get_pcvar_string(g_cvarChatPrefix, prefix, charsmax(prefix));
    formatex(finalMessage, charsmax(finalMessage), "^x04%s^x01 %s", prefix, message);

    new msgSayText = get_user_msgid("SayText");
    new msgTeamInfo = get_user_msgid("TeamInfo");

    if (id)
    {
        if (is_user_connected(id))
        {
            message_begin(MSG_ONE_UNRELIABLE, msgTeamInfo, _, id);
            write_byte(id);
            write_string("TERRORIST");
            message_end();

            message_begin(MSG_ONE_UNRELIABLE, msgSayText, _, id);
            write_byte(id);
            write_string(finalMessage);
            message_end();
        }
        return;
    }

    for (new player = 1; player <= MAX_PLAYERS; player++)
    {
        if (is_user_connected(player))
        {
            message_begin(MSG_ONE_UNRELIABLE, msgTeamInfo, _, player);
            write_byte(player);
            write_string("TERRORIST");
            message_end();

            message_begin(MSG_ONE_UNRELIABLE, msgSayText, _, player);
            write_byte(player);
            write_string(finalMessage);
            message_end();
        }
    }
}
