/*	Copyright © 2008, ConnorMcLeod

	func_door is free software;
	you can redistribute it and/or modify it under the terms of the
	GNU General Public License as published by the Free Software Foundation.

	This program is distributed in the hope that it will be useful,
	but WITHOUT ANY WARRANTY; without even the implied warranty of
	MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
	GNU General Public License for more details.

	You should have received a copy of the GNU General Public License
	along with func_door; if not, write to the
	Free Software Foundation, Inc., 59 Temple Place - Suite 330,
	Boston, MA 02111-1307, USA.
*/

// #define CHATCOLOR
#define MAKE_DOORS_SILENT

#include <amxmodx>
#include <amxmisc>
#include <engine>
#include <fakemeta>
#include <hamsandwich>
#include <xs>

#if defined CHATCOLOR
#include <chatcolor>
#endif

new const VERSION[] = "1.1.2";

#pragma semicolon 1

#define SetIdBits(%1,%2)		%1 |= 1<<(%2 & 31)
#define ClearIdBits(%1,%2)	%1 &= ~( 1<<(%2 & 31) )
#define GetIdBits(%1,%2)		%1 &  1<<(%2 & 31)

#define SetEntBits(%1,%2)	if(%2>=0 && (%2>>5)<MAX_ENTSARRAYS_SIZE) %1[%2>>5] |=  1<<(%2 & 31)
#define ClearEntBits(%1,%2)	if(%2>=0 && (%2>>5)<MAX_ENTSARRAYS_SIZE) %1[%2>>5] &= ~( 1 << (%2 & 31) )
#define GetEntBits(%1,%2)	((%2>=0 && (%2>>5)<MAX_ENTSARRAYS_SIZE) ? (%1[%2>>5] & 1<<(%2 & 31)) : 0)

enum _:BlocksClasses
{
	FUNC_DOOR,
	FUNC_WALL_TOGGLE,
	FUNC_BUTTON,
	TRIGGER_MULTIPLE
}

new const Float:VEC_DUCK_HULL_MIN[3]	= {-16.0, -16.0, -18.0 };
new const Float:VEC_DUCK_HULL_MAX[3]	= { 16.0,  16.0,  32.0 };
new const Float:VEC_DUCK_VIEW[3]		= {  0.0,   0.0,  12.0 };

new const Float:VEC_HULL_MIN[3]		= {-16.0, -16.0, -36.0 };
new const Float:VEC_HULL_MAX[3]		= { 16.0,  16.0,  36.0 };
new const Float:VEC_VIEW[3]			= {  0.0,   0.0,  17.0 };

new const Float:VEC_NULL[3]	= { 0.0, 0.0, 0.0 };

const PLAYERS_ARRAY_SIZE = 33;
const MAX_ENTSARRAYS_SIZE = 128; // x * 32 // 4096

new g_bitPresentClass;

const KEYS = ((1<<0)|(1<<1)|(1<<9));

new g_iBlock[ PLAYERS_ARRAY_SIZE ];
new Float:g_flFirstTouch[ PLAYERS_ARRAY_SIZE ];

new Float:g_flJumpOrigin[ PLAYERS_ARRAY_SIZE ][3];
new Float:g_flJumpAngles[ PLAYERS_ARRAY_SIZE ][3];
new Float:g_flJumpGravity[ PLAYERS_ARRAY_SIZE ];
new bool:g_bJumpedDucking[ PLAYERS_ARRAY_SIZE ];

new g_bBlocks[MAX_ENTSARRAYS_SIZE], g_bBlocksByPlugin[MAX_ENTSARRAYS_SIZE];
new g_bOnGround, g_bTeleported, g_bAdmin;

new bool:g_bBlockEntityTouch;
new bool:g_bActive;
new bool:g_bSafeInform = true;

new g_iAdminDoor[PLAYERS_ARRAY_SIZE];
new szConfigFile[64];

new Trie:g_iBlocksClass;

new g_iMaxPlayers, g_iMaxEnts;
#define IsPlayer(%1)	( 1 <= %1 <= g_iMaxPlayers )

public plugin_init()
{
	new pCvar = register_cvar("mp_bhop_version", VERSION, FCVAR_SERVER|FCVAR_EXTDLL|FCVAR_SPONLY);
	set_pcvar_string(pCvar, VERSION);

	new const szPossibleBlockClass[][] = {"func_door", "func_wall_toggle", "func_button", "trigger_multiple"};
	g_iBlocksClass = TrieCreate();
	for(new i; i<sizeof(szPossibleBlockClass); i++)
	{
		TrieSetCell(g_iBlocksClass, szPossibleBlockClass[i], i);
	}

	register_concmd("kz_mpbhop", "ConCmd_MpBhop", ADMIN_CFG, "<0/1> set blocks so they can't move when players touch them");
	register_concmd("kz_mpbhop_entitytouch", "ConCmd_EntityTouch", ADMIN_CFG, "<0/1> set blocks so they can't move when other entities than players touch them");
	register_concmd("kz_safe_inform", "ClCmd_SafeInform", ADMIN_CFG, "<0/1> Inform recorders that their demo will be safe or not safe according to plugin state");

	register_clcmd("kz_mpbhopmenu", "ClCmd_BhopMenu", ADMIN_CFG);
	register_clcmd("kz_showblocks", "ClCmd_ShowBlocks", ADMIN_CFG);

	register_clcmd("fullupdate", "ClCmd_FullUpdate");

	register_menucmd(register_menuid("MpBhop Menu"), KEYS ,"MpBhopMenuAction");

	g_iMaxPlayers = get_maxplayers();
	g_iMaxEnts = global_get(glb_maxEntities);

	new iCount;

	iCount += Set_Doors();
	iCount += Set_Wall_Toggle();
	iCount += Set_Buttons();

	iCount += SetBlocksByFile();

	server_print("[MPBHOP] %d bhop blocks detected", iCount);

	SetTriggerMultiple();
}

public plugin_cfg()
{
	new szConfigPath[96];
	get_localinfo("amxx_configsdir", szConfigPath, charsmax(szConfigPath));
	format(szConfigPath, charsmax(szConfigPath), "%s/mpbhop.cfg", szConfigPath);

	new bool:bForceWrite = !file_exists(szConfigPath);
	if( file_exists(szConfigPath) )
	{
		new buffer[2], n;
		read_file(szConfigPath, 0, buffer, charsmax(buffer), n);
		if( buffer[0] == ';' )
		{
			bForceWrite = true;
		}
		else
		{
			server_cmd("exec %s", szConfigPath);
			server_exec();
		}
	}

	if( bForceWrite )
	{
		new fp = fopen(szConfigPath, "wt");
		if( !fp )
		{
			return;
		}
		new szPluginFileName[96], szPluginName[64], szAuthor[32], szVersion[32], szStatus[2];
		new iPlugin = get_plugin(-1,
					szPluginFileName, charsmax(szPluginFileName),
					szPluginName, charsmax(szPluginName),
					szVersion, charsmax(szVersion),
					szAuthor, charsmax(szAuthor),
					szStatus, charsmax(szStatus) );

		fprintf(fp, "// ^"%s^" configuration file^n", szPluginName);
		fprintf(fp, "// Author : ^"%s^"^n", szAuthor);
		fprintf(fp, "// Version : ^"%s^"^n", szVersion);
		fprintf(fp, "// File : ^"%s^"^n", szPluginFileName);

		new iMax, i, szCommand[64], iCommandAccess, szCmdInfo[128], szFlags[32];
		iMax = get_concmdsnum(-1, -1);
		fprintf(fp, "^n// Console Commands :^n");
		for(i=0; i<iMax; i++)
		{
			if( get_concmd_plid(i, -1, -1) == iPlugin )
			{
				get_concmd(i,
						szCommand, charsmax(szCommand),
						iCommandAccess,
						szCmdInfo, charsmax(szCmdInfo),
						-1, -1);
				get_flags(iCommandAccess, szFlags, charsmax(szFlags));
				fprintf(fp, "// %s | Access:^"%s^" | ^"%s^"^n", szCommand, szFlags, szCmdInfo);
			}
		}

		iMax = get_plugins_cvarsnum();
		new iTempId, iPcvar, szCvarName[256], szCvarValue[128];
		fprintf(fp, "^n// Cvars :^n");
		for(new i; i<iMax; i++)
		{
			get_plugins_cvar(i, szCvarName, charsmax(szCvarName), _, iTempId, iPcvar);
			if( iTempId == iPlugin )
			{
				get_pcvar_string(iPcvar, szCvarValue, charsmax(szCvarValue));
				fprintf(fp, "// %s ^"%s^"^n", szCvarName, szCvarValue);
			}
		}

		fclose(fp);
	}

	if( !g_bActive )
	{
		g_bActive = true;
		SetTouch(true);
		server_print("[MPBHOP] Plugin auto-activated");
	}
}

public ClCmd_FullUpdate( id )
{
	if( g_bSafeInform )
	{
		if( g_bActive )
		{
			client_print(id, print_console, "MpBhop is Activated, recording is NOT SAFE");
#if defined CHATCOLOR
			client_print_color(id, Red, "^1 * ^4[MpBhop] ^1MpBhop is ^4Activated^1, recording is ^3NOT SAFE");
#else
			client_print(id, print_chat, "MpBhop is Activated, recording is NOT SAFE");
#endif
		}
		else
		{
			client_print(id, print_console, "MpBhop is De-Activated, recording is SAFE");
#if defined CHATCOLOR
			client_print_color(id, Red, "^1 * ^4[MpBhop] ^1MpBhop is ^3De-Activated^1, recording is ^4SAFE");
#else
			client_print(id, print_chat, "MpBhop is De-Activated, recording is SAFE");
#endif
		}
	}
}

public ClCmd_SafeInform(id, lvl, cid)
{
	if( cmd_access(id, lvl, cid, 2) )
	{
		new szStatus[2];
		read_argv(1, szStatus, charsmax(szStatus));
		g_bSafeInform = !!str_to_num(szStatus);
	}
	return PLUGIN_HANDLED;
}

public client_putinserver(id)
{
	if( get_user_flags(id) & ADMIN_CFG )
	{
		SetIdBits(g_bAdmin, id);
	}
	else
	{
		ClearIdBits(g_bAdmin, id);
	}
	ClearIdBits(g_bOnGround, id);
	ClearIdBits(g_bTeleported, id);
}

public client_disconnect(id)
{
	ClearIdBits(g_bAdmin, id);
	ClearIdBits(g_bOnGround, id);
	ClearIdBits(g_bTeleported, id);
}

public ClCmd_ShowBlocks(id, level, cid)
{
	client_print(id, print_console, "[MPBHOP] Block visualization disabled for compatibility with timer.");
	return PLUGIN_HANDLED;
}

public MpBhopMenuAction(id, iKey)
{
	new iEnt = g_iAdminDoor[id];

	switch( iKey )
	{
		case 0:
		{
			if( GetEntBits(g_bBlocks, iEnt) )
			{
				ClearEntBits(g_bBlocks, iEnt);
#if defined CHATCOLOR
				client_print_color(id, id, "^1 * ^4[MpBhop] ^1Block has been set ^4movable^1.");
#else
				client_print(id, print_chat, " * [MpBhop] Block has been set movable.");
#endif
			}
			else
			{
#if defined CHATCOLOR
				client_print_color(id, id, "^1 * ^4[MpBhop] ^1Block is already ^4movable^1.");
#else
				client_print(id, print_chat, " * [MpBhop] Block is already movable.");
#endif
			}
		}
		case 1:
		{
			if( GetEntBits(g_bBlocks, iEnt) )
			{
#if defined CHATCOLOR
				client_print_color(id, Red, "^1 * ^4[MpBhop] ^1Block is already ^3unmovable^1.");
#else
				client_print(id, print_chat, " * [MpBhop] Block is already unmovable.");
#endif
			}
			else
			{
				SetEntBits(g_bBlocks, iEnt);
#if defined CHATCOLOR
				client_print_color(id, Red, "^1 * ^4[MpBhop] ^1Block has been set ^3unmovable^1.");
#else
				client_print(id, print_chat, " * [MpBhop] Block has been set unmovable.");
#endif
				if( g_bActive )
				{
					SetTouch(true);
				}
			}
		}
	}
	return PLUGIN_HANDLED;
}

ShowMpBhopMenu(id, bIsBlocked)
{
	new szMenuBody[150];

	formatex(szMenuBody, charsmax(szMenuBody), "\rMpBhop Menu^n\dThis block is actually \
		\y%smovable \d:^n^n\r1\w. Mark this block as movable^n\r2\w. Mark this block as \
		unmovable^n^n\r0\w. Exit", bIsBlocked ? "un" : "");

	show_menu(id, KEYS, szMenuBody, _, "MpBhop Menu");
}

public ClCmd_BhopMenu(id, level, cid)
{
	if( cmd_access(id, level, cid, 1) )
	{
		new iEnt, crap, iClassType;
		get_user_aiming(id, iEnt, crap);
		if( iEnt && pev_valid(iEnt) )
		{
			new szClassName[32];
			pev(iEnt, pev_classname, szClassName, charsmax(szClassName));
			if( TrieGetCell(g_iBlocksClass, szClassName, iClassType) )
			{
				g_bitPresentClass |= 1<<iClassType;
				g_iAdminDoor[id] = iEnt;
				ShowMpBhopMenu(id, !!(GetEntBits(g_bBlocks, iEnt)));
			}
		}
	}
	return PLUGIN_HANDLED;
}

stock FindGroundEnt(id)
{
	new Float:flStart[3], Float:flEnd[3];
	pev(id, pev_origin, flStart);
	flStart[2] -= 4.0;
	xs_vec_copy(flStart, flEnd);
	flEnd[2] -= 64.0;

	new ptr = create_tr2();
	engfunc(EngFunc_TraceHull, flStart, flEnd, IGNORE_MONSTERS, HULL_HUMAN, id, ptr);
	new iEnt = get_tr2(ptr, TR_pHit);
	free_tr2(ptr);
	if( iEnt && !pev_valid(iEnt) )
		return 0;
	return iEnt;
}

public CBasePlayer_PreThink(id)
{
	if( is_user_alive(id) )
	{
		if( GetIdBits(g_bTeleported, id) )
		{
			ClearIdBits(g_bTeleported, id);
			set_pev(id, pev_velocity, VEC_NULL);
			return;
		}

		static iEnt, Float:flVelocity[3], Float:flVecOrigin[3];
		iEnt = pev(id, pev_groundentity);

		if( !iEnt )
		{
			iEnt = FindGroundEnt(id);
		}

		if( iEnt && iEnt < g_iMaxEnts && GetEntBits(g_bBlocks, iEnt) )
		{
			ClearIdBits(g_bOnGround, id);
		}
		else if( iEnt && pev_valid(iEnt) )
		{
			pev(iEnt, pev_velocity, flVelocity);
			if( flVelocity[0] || flVelocity[1] || flVelocity[2] )
			{
				ClearIdBits(g_bOnGround, id);
				return;
			}

			if( pev(id, pev_flags) & FL_DUCKING )
			{
				pev(id, pev_origin, flVecOrigin);
				flVecOrigin[2] += 18.0;
				if( !trace_hull(flVecOrigin, HULL_HUMAN, id, IGNORE_MONSTERS) )
				{
					flVecOrigin[2] -= 18.0;
					xs_vec_copy(flVecOrigin, g_flJumpOrigin[id]);
					SetIdBits(g_bOnGround, id);
				}
				else
				{
					ClearIdBits(g_bOnGround, id);
					return;
				}
			}
			else
			{
				pev(id, pev_origin, g_flJumpOrigin[id]);
				SetIdBits(g_bOnGround, id);
			}
		}
		else if( GetIdBits(g_bOnGround, id) )
		{
			ClearIdBits(g_bOnGround, id);
			pev(id, pev_v_angle, g_flJumpAngles[id]);
			pev(id, pev_gravity, g_flJumpGravity[id]);
			g_bJumpedDucking[id] = (pev(id, pev_flags) & FL_DUCKING) ? true : false;
		}
	}
}

public TriggerMultiple_Touch(iEnt, id)
{
	if( iEnt < 0 || iEnt >= g_iMaxEnts )
	{
		return HAM_IGNORED;
	}

	if( (IsPlayer(id) || g_bBlockEntityTouch) && GetEntBits(g_bBlocks, iEnt) )
	{
		return HAM_SUPERCEDE;
	}
	return HAM_IGNORED;
}

public Touch_Block(iBlock, id)
{
	if( iBlock < 0 || iBlock >= g_iMaxEnts )
	{
		return HAM_IGNORED;
	}

	if( !(GetEntBits(g_bBlocks, iBlock)) )
	{
		return HAM_IGNORED;
	}

	if( IsPlayer(id) )
	{
		if( !is_user_alive(id) )
		{
			return HAM_SUPERCEDE;
		}
	}
	else
	{
		return g_bBlockEntityTouch ? HAM_SUPERCEDE : HAM_IGNORED;
	}

	if( pev(id, pev_groundentity) != iBlock )
	{
		if( pev(id, pev_groundentity) || FindGroundEnt(id) != iBlock )
		{
			return HAM_SUPERCEDE;
		}
	}

	if( g_iBlock[id] != iBlock )
	{
		g_iBlock[id] = iBlock;
		g_flFirstTouch[id] = get_gametime();
		return HAM_SUPERCEDE;
	}

	static Float:flTime;
	flTime = get_gametime();

	if( flTime - g_flFirstTouch[id] > 1.5 )
	{
		g_iBlock[id] = 0;
		g_flFirstTouch[id] = flTime;
		return HAM_SUPERCEDE;
	}

	if( flTime - g_flFirstTouch[id] > 0.25 ) // 0.3 == exploit on cg_cbblebhop oO
	{
		if( flTime - g_flFirstTouch[id] > 0.7 )
		{
			g_flFirstTouch[id] = flTime;
			return HAM_SUPERCEDE;
		}

		Util_TeleportPlayerBack( id );
	}
	return HAM_SUPERCEDE;
}

Util_TeleportPlayerBack(id)
{
	if( g_flJumpOrigin[id][0] == 0.0 && g_flJumpOrigin[id][1] == 0.0 && g_flJumpOrigin[id][2] == 0.0 )
	{
		g_iBlock[id] = 0;
		g_flFirstTouch[id] = get_gametime();
		return;
	}

	if( g_flJumpOrigin[id][2] < -5000.0 || g_flJumpOrigin[id][2] > 5000.0 )
	{
		g_iBlock[id] = 0;
		g_flFirstTouch[id] = get_gametime();
		return;
	}

	SetIdBits(g_bTeleported, id); // apply null velocity on next PreThink()

	new flags = pev(id, pev_flags);
	if( flags & FL_BASEVELOCITY )
	{
		flags &= ~FL_BASEVELOCITY;
		set_pev(id, pev_basevelocity, VEC_NULL);
	}
	set_pev(id, pev_velocity, VEC_NULL);

	if( g_bJumpedDucking[id] )
	{
		set_pev(id, pev_flags, flags | FL_DUCKING);
		engfunc(EngFunc_SetSize, id, VEC_DUCK_HULL_MIN, VEC_DUCK_HULL_MAX);
		engfunc(EngFunc_SetOrigin, id, g_flJumpOrigin[id]);
		set_pev(id, pev_view_ofs, VEC_DUCK_VIEW);
	}
	else
	{
		set_pev(id, pev_flags, flags & ~FL_DUCKING);
		engfunc(EngFunc_SetSize, id, VEC_HULL_MIN, VEC_HULL_MAX);
		engfunc(EngFunc_SetOrigin, id, g_flJumpOrigin[id]);
		set_pev(id, pev_view_ofs, VEC_VIEW);
	}

	set_pev(id, pev_v_angle, VEC_NULL);
	set_pev(id, pev_angles, g_flJumpAngles[id]);
	set_pev(id, pev_punchangle, VEC_NULL);
	set_pev(id, pev_fixangle, 1);

	set_pev(id, pev_gravity, g_flJumpGravity[id]);

	set_pev(id, pev_fuser2, 0.0);
}

public ConCmd_MpBhop(id, lvl, cid)
{
	if( cmd_access(id, lvl, cid, 2) )
	{
		new szStatus[2];
		read_argv(1, szStatus, charsmax(szStatus));
		static HamHook:iHhPlayerPreThink;
		switch( szStatus[0] )
		{
			case '0':
			{
				if( !g_bActive )
				{
					return PLUGIN_HANDLED;
				}
				if( iHhPlayerPreThink )
				{
					DisableHamForward( iHhPlayerPreThink );
				}
				SetTouch( false );
				g_bActive = false;

				if( g_bSafeInform )
				{
					client_print(0, print_console, "MpBhop has been De-Activated, recording is now SAFE");
#if defined CHATCOLOR
					client_print_color(0, Red, "^1 * ^4[MpBhop] ^1MpBhop has been ^3De-Activated^1, recording is now ^4SAFE");
#else
					client_print(id, print_chat, " * [MpBhop] MpBhop has been De-Activated, recording is now SAFE");
#endif
				}
			}
			case '1':
			{
				if( g_bActive )
				{
					return PLUGIN_HANDLED;
				}
				if( !iHhPlayerPreThink )
				{
					iHhPlayerPreThink = RegisterHam(Ham_Player_PreThink, "player", "CBasePlayer_PreThink");
				}
				else
				{
					EnableHamForward( iHhPlayerPreThink );
				}
				SetTouch( true );
				g_bActive = true;
				if( g_bSafeInform )
				{
					client_print(0, print_console, "MpBhop has been Activated, recording is now NOT SAFE");
#if defined CHATCOLOR
					client_print_color(0, Red, "^1 * ^4[MpBhop] ^1MpBhop has been ^4Activated^1, recording is now ^3NOT SAFE");
#else
					client_print(id, print_chat, " * MpBhop has been Activated, recording is now NOT SAFE");
#endif
				}
			}
			default:
			{
				client_print(id, print_console, "Usage: kz_mpbhop <0/1>");
			}
		}
	}
	return PLUGIN_HANDLED;
}

public ConCmd_EntityTouch(id, lvl, cid)
{
	if( cmd_access(id, lvl, cid, 2) )
	{
		new szStatus[2];
		read_argv(1, szStatus, charsmax(szStatus));
		g_bBlockEntityTouch = !!str_to_num(szStatus);
	}
	return PLUGIN_HANDLED;
}

Set_Doors()
{
	new iDoor = FM_NULLENT, i;
	new Float:flMovedir[3], Float:flDmg, Float:flSpeed;
	new const szNull[] = "common/null.wav";
	while( (iDoor = find_ent_by_class( iDoor, "func_door")) )
	{
		// definitely not a bhop block if it deals damage
		pev(iDoor, pev_dmg, flDmg);
		if( flDmg )
		{
#if defined MAKE_DOORS_SILENT
			set_pev(iDoor, pev_noise1, szNull);
			set_pev(iDoor, pev_noise2, szNull);
			set_pev(iDoor, pev_noise3, szNull);
#endif
			continue;
		}

		// this func_door goes UP, not a bhop block ?
		pev(iDoor, pev_movedir, flMovedir);
		if( flMovedir[2] > 0.0 )
		{
			continue;
		}

		// skip very slow platforms
		pev(iDoor, pev_speed, flSpeed);
		if( flSpeed < 20.0 )
		{
			continue;
		}

		// Set as bhop block
		SetEntBits(g_bBlocksByPlugin, iDoor);
		SetEntBits(g_bBlocks, iDoor);
		g_bitPresentClass |= 1<<FUNC_DOOR;
		i++;
	}
	return i;
}

Set_Wall_Toggle()
{
	new iEnt = FM_NULLENT, i;
	while( (iEnt = find_ent_by_class(iEnt,"func_wall_toggle")) )
	{
		g_bitPresentClass |= 1<<FUNC_WALL_TOGGLE;
		SetEntBits(g_bBlocksByPlugin, iEnt);
		SetEntBits(g_bBlocks, iEnt);
		i++;
	}
	return i;
}

Set_Buttons()
{
	new const szStartStopButtons[][] = {
		"counter_start", "clockstartbutton", "firsttimerelay", "gogogo", "multi_start","counter_start_button", "startcounter", 
		"counter_off", "clockstop", "clockstopbutton", "multi_stop", "stop_counter", "stopcounter" };

	new Trie:tButtons = TrieCreate();

	for(new i; i<sizeof(szStartStopButtons); i++)
	{
		TrieSetCell(tButtons, szStartStopButtons[i], 1);
	}

	new iEnt = FM_NULLENT, i, szTarget[32], spawnflags;
	while( (iEnt = find_ent_by_class(iEnt,"func_button")) )
	{
		
		spawnflags = pev(iEnt, pev_spawnflags);
		if( spawnflags & (SF_BUTTON_DONTMOVE|SF_BUTTON_TOGGLE|SF_BUTTON_TOUCH_ONLY) == SF_BUTTON_TOUCH_ONLY )
		{
			pev(iEnt, pev_target, szTarget, charsmax(szTarget));
			if( !szTarget[0] || !TrieKeyExists(tButtons, szTarget))
			{
				pev(iEnt, pev_targetname, szTarget, charsmax(szTarget));
				if( !szTarget[0] || !TrieKeyExists(tButtons, szTarget))
				{
					g_bitPresentClass |= 1<<FUNC_BUTTON;
					SetEntBits(g_bBlocksByPlugin, iEnt);
					SetEntBits(g_bBlocks, iEnt);
					i++;
				}
			}
		}
#if defined MAKE_DOORS_SILENT
		if( spawnflags & SF_BUTTON_SPARK_IF_OFF )
		{
			set_pev(iEnt, pev_spawnflags, spawnflags & ~SF_BUTTON_SPARK_IF_OFF);
		}
#endif
	}
	TrieDestroy(tButtons);
	return i;
}

SetTouch(bool:bActive)
{
	static HamHook:iHhBlockTouch[BlocksClasses];
	if( bActive )
	{
		static const szClassesAndHandlers[BlocksClasses][][] = {
			{"func_door", "Touch_Block"},
			{"func_wall_toggle", "Touch_Block"},
			{"func_button", "Touch_Block"},
			{"trigger_multiple", "TriggerMultiple_Touch"}
		};
		for(new i; i<sizeof(iHhBlockTouch); i++)
		{
			if( g_bitPresentClass & (1<<i) )
			{
				if( iHhBlockTouch[i] )
				{
					EnableHamForward( iHhBlockTouch[i] );
				}
				else
				{
					iHhBlockTouch[i] = RegisterHam(Ham_Touch, szClassesAndHandlers[i][0], szClassesAndHandlers[i][1]);
				}
			}
		}
	}
	else
	{
		for(new i; i<sizeof(iHhBlockTouch); i++)
		{
			if( g_bitPresentClass & (1<<i) && iHhBlockTouch[i] )
			{
				DisableHamForward( iHhBlockTouch[i] );
			}
		}
	}
}

SetBlocksByFile()
{
	get_localinfo("amxx_datadir", szConfigFile, charsmax(szConfigFile));
	format(szConfigFile, charsmax(szConfigFile), "%s/mpbhop", szConfigFile);
	if( !dir_exists(szConfigFile) )
	{
		mkdir(szConfigFile);
	}

	new szMapName[32];
	get_mapname(szMapName, charsmax(szMapName));
	format(szConfigFile, charsmax(szConfigFile), "%s/%s.dat", szConfigFile, szMapName);

	new iFile = fopen(szConfigFile, "rt"), i;
	if( iFile )
	{
		new szDatas[48], szBrushOrigin[3][13], szType[2], Float:flBrushOrigin[3], i, iEnt;
		new szClassName[32], iClassType;
		while( !feof(iFile) )
		{
			fgets(iFile, szDatas, charsmax(szDatas));
			trim(szDatas);
			if(!szDatas[0] || szDatas[0] == ';' || szDatas[0] == '#' || (szDatas[0] == '/' && szDatas[1] == '/'))
			{
				continue;
			}

			parse(szDatas, szBrushOrigin[0], 12, szBrushOrigin[1], 12, szBrushOrigin[2], 12, szType, charsmax(szType));
			for(i=0; i<3; i++)
			{
				flBrushOrigin[i] = str_to_float( szBrushOrigin[i] );
			}

			iEnt = FindEntByBrushOrigin( flBrushOrigin );
			if( iEnt )
			{
				if( szType[0] == '1' )
				{
					pev(iEnt, pev_classname, szClassName, charsmax(szClassName));
					if( TrieGetCell(g_iBlocksClass, szClassName, iClassType) )
					{
						g_bitPresentClass |= 1<<iClassType;
					}
					if( ~GetEntBits(g_bBlocks, iEnt) )
					{
						i++;
					}
					SetEntBits(g_bBlocks, iEnt);
				}
				else
				{
					if( GetEntBits(g_bBlocks, iEnt) )
					{
						i--;
					}
					ClearEntBits(g_bBlocks, iEnt);
				}
			}
		}
		fclose(iFile);
	}
	return i;
}

FindEntByBrushOrigin(Float:flOrigin[3])
{
	new Float:flBrushOrigin[3];
	for( new iEnt=g_iMaxPlayers+1; iEnt<=g_iMaxEnts; iEnt++ )
	{
		if( pev_valid(iEnt) )
		{
			fm_get_brush_entity_origin(iEnt, flBrushOrigin);
			if( xs_vec_nearlyequal(flBrushOrigin, flOrigin) )
			{
				return iEnt;
			}
		}
	}
	return 0;
}

fm_get_brush_entity_origin(ent, Float:orig[3])
{
	new Float:Min[3], Float:Max[3];

	pev(ent, pev_origin, orig);
	pev(ent, pev_mins, Min);
	pev(ent, pev_maxs, Max);

	orig[0] += (Min[0] + Max[0]) * 0.5;
	orig[1] += (Min[1] + Max[1]) * 0.5;
	orig[2] += (Min[2] + Max[2]) * 0.5;

	return 1;
}

SetTriggerMultiple()
{
	new iEnt = FM_NULLENT, szTarget[32], iBlock;
	while( (iEnt = find_ent_by_class(iEnt,"trigger_multiple")) )
	{
		pev(iEnt, pev_target, szTarget, charsmax(szTarget));
		iBlock = find_ent_by_tname(FM_NULLENT, szTarget);
		if( iBlock && GetEntBits(g_bBlocks, iBlock) )
		{
			g_bitPresentClass |= 1<<TRIGGER_MULTIPLE;
			SetEntBits(g_bBlocksByPlugin, iEnt);
			SetEntBits(g_bBlocks, iEnt);
		}
	}
}

public plugin_end()
{
	TrieDestroy(g_iBlocksClass);
	delete_file(szConfigFile);

	new iFile;

	new Float:flBrushOrigin[3], bool:bUnMovable;
	for(new iEnt=g_iMaxPlayers+1; iEnt<=g_iMaxEnts; iEnt++)
	{
		if( pev_valid(iEnt) )
		{
			bUnMovable = !!( GetEntBits(g_bBlocks, iEnt) );
			if(	bUnMovable
			!=	!!( GetEntBits(g_bBlocksByPlugin, iEnt) )	)
			{
				if( !iFile )
				{
					iFile = fopen(szConfigFile, "wt");
				}
				fm_get_brush_entity_origin(iEnt, flBrushOrigin);
				fprintf(iFile, "%f %f %f %d^n",
				flBrushOrigin[0], flBrushOrigin[1], flBrushOrigin[2], bUnMovable);
			}
		}
	}
	if( iFile )
	{
		fclose( iFile );
	}
}
