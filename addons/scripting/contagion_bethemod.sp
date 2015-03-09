/*
	╔════════════ INFORMATION ══════════════════════════════════════════════════════════════════════════════════════════╗
	║	As of V1.8, i will now have "Survivor Selection Menu". The idea is from L4D/L4D2 CSM mod where you write csm	║
	║	, !csm or /csm to activate the menu. This will however not change the Carrier settings on the zombie team.		║
	╟───────────────────────────────────────────────────────────────────────────────────────────────────────────────────╢
	║	You can also set max cap on any survivor, and by writing -1 on the max count, it will be infinite.				║
	╚═══════════════════════════════════════════════════════════════════════════════════════════════════════════════════╝
*/

#pragma semicolon 1

#include <sourcemod>
#include <sdkhooks>
#include <sdktools>
#include <contagion>

#define PLUGIN_VERSION "2.1"
// The higher number the less chance the carrier can infect
#define INFECTION_MAX_CHANCE	20

//=========================
// Modes
//========================

enum g_eStatus
{
	STATE_NOT_CARRIER=0,
	STATE_CARRIER
};

enum g_iStatus
{
	STATE_NORMAL=0,
	STATE_ARMOR
};

enum g_nStatus
{
	STATE_NOT_SELECTED=0,
	STATE_SELECTED,
	STATE_LATE
};

enum g_eRegene
{
	STATE_NO_REGEN=0,
	STATE_REGEN
};

enum g_eperks
{
	STATE_NONE=false,
	STATE_MELEE_GOOD=false,
	STATE_MELEE_BAD=false,
	STATE_DEMO=false,
	STATE_EXPLOBOLT=false,
	STATE_MEDIC=false,
	STATE_SREGEN=false
};

enum g_edata
{
	g_eRegene:g_nIfRegen,
	g_eStatus:g_nIfSpecial_Carrier,
	g_iStatus:g_nIfSpecial_Survivor,
	g_nStatus:g_nIfSelectedSurvivor
};


//=========================
// AskPluginLoad2
//========================

public APLRes:AskPluginLoad2(Handle:myself, bool:late, String:error[], err_max) {
	new String:Game[32];
	GetGameFolderName(Game, sizeof(Game));
	if(!StrEqual(Game, "contagion")) {
		Format(error, err_max, "This plugin only works for Contagion");
		return APLRes_Failure;
	}
	return APLRes_Success;
}

//=========================
// Handles
//========================

new Handle:mainmenu;
new Handle:kv;
new String:authid[MAXPLAYERS+1][35];
new CanBeCarrier;
new Handle:g_hDebugMode;
new Handle:g_hCvarMode;
new Handle:g_hCvarNormalInfectionMode;
new Handle:g_SetWhiteyHealth;
new Handle:g_SetWhiteyInfectionTime;
new Handle:g_SetCharRestriction;
new Handle:g_SetCharLimitTime;
new g_nBeTheMod[MAXPLAYERS+1][g_edata];
new g_nSurvivorPerks[MAXPLAYERS+1][g_eperks];
new Handle:ResetRegenTimer[MAXPLAYERS+1];
new MedicCoolDown[MAXPLAYERS+1];

new Handle:g_GetMeleeInfection_Easy;
new Handle:g_GetMeleeInfection_Normal;
new Handle:g_GetMeleeInfection_Hard;
new Handle:g_GetMeleeInfection_Extreme;

new Handle:g_explobolt_dmg;
new Handle:g_hMedicCoolDown;
new Handle:g_hMedicSpawns;
new GetCoolDownTimer;
new medkits_set = -1;

new String:logFilePath[512];
new String:db_model[256];
new String:db_group[256];
new String:db_type[256];
new String:gb_health[256];

//=========================
// Plugin:myinfo
//========================

public Plugin:myinfo =
{
	name = "[Contagion] Be The Special Survivor/Infected",
	author = "JonnyBoy0719",
	version = PLUGIN_VERSION,
	description = "Makes the first player a speical zombie and/or survivor",
	url = "https://forums.alliedmods.net/"
}

//=========================
// OnPluginStart()
//========================

public OnPluginStart()
{
	// Events
	HookEvent("player_spawn", EVENT_PlayerSpawned);
	HookEvent("player_death", EVENT_PlayerDeath);
	HookEvent("game_start", EVENT_GameStart);
	HookEvent("round_start", EVENT_GameStart);
	HookEvent("game_end", EVENT_GameEnd);
	HookEvent("round_end", EVENT_GameEnd);
	
	// Commands
	CreateConVar("sm_bethemod_version", PLUGIN_VERSION, "Current \"Be The Special Survivor/Infected\" Version",
		FCVAR_NOTIFY | FCVAR_DONTRECORD | FCVAR_SPONLY);
	g_hDebugMode						= CreateConVar("sm_bethemod_debug", "0", "0 - Disable debugging | 1 - Enable Debugging");
	g_hCvarMode							= CreateConVar("sm_bethemod_max_carrier", "1", "How many carriers should can we have alive at once?");
	g_hCvarNormalInfectionMode			= CreateConVar("sm_bethemod_infection_normal", "0", "0 - Disable normal zombie infection | 1 - Enable normal zombie infection");
	g_SetWhiteyHealth					= CreateConVar("sm_bethemod_carrier_health", "350.0", "Value to change the carrier health to. Minimum 250.", 
		FCVAR_PLUGIN | FCVAR_NOTIFY, true, 250.0);
	g_SetWhiteyInfectionTime			= CreateConVar("sm_bethemod_infection", "35.0", "Value to change the carrier infection time to. Minimum 20.", 
		FCVAR_PLUGIN | FCVAR_NOTIFY, true, 20.0);
	g_SetCharRestriction				= CreateConVar("sm_bethemod_csm_mode", "1", "0 - No map restriction | 1 - Hunted only | 2 - Hunted and Classic modes | 3 - All modes");
	g_SetCharLimitTime					= CreateConVar("sm_bethemod_csm_time", "35.0", "How many seconds until it will disable the survivor selection. Minimum 20.", 
		FCVAR_PLUGIN | FCVAR_NOTIFY, true, 20.0);
	g_hMedicSpawns						= CreateConVar("sm_bethemod_perk_medic", "2", "Set how many medkits can the medic spawn. Minimum 1.", 
		FCVAR_PLUGIN | FCVAR_NOTIFY, true, 1.0);
	g_hMedicCoolDown					= CreateConVar("sm_bethemod_perk_medic_cooldown", "35.0", "How many seconds until the medic can spawn more medkits. Minimum 20.", 
		FCVAR_PLUGIN | FCVAR_NOTIFY, true, 20.0);
	g_explobolt_dmg					= CreateConVar("sm_bethemod_perk_explobolt_damage", "450.0", "How much damage should the explosive arrows do. Minimum 50.", 
		FCVAR_PLUGIN | FCVAR_NOTIFY, true, 50.0);
	
	// Select model of choice
	RegConsoleCmd("sm_csm", SelectSurvivorModel, "Brings up a menu to select a different character");
	RegConsoleCmd("sm_medic", SpawnFirstAidKits, "Spawn some firstaid (The survivor needs \"medic\" perk!)");
	
	// Hooks
	HookConVarChange(g_hCvarNormalInfectionMode, OnConVarChange);
	
	// Get Contagion commands
	g_GetMeleeInfection_Easy = FindConVar("cg_infection_attacked_chance_easy");
	g_GetMeleeInfection_Normal = FindConVar("cg_infection_attacked_chance_normal");
	g_GetMeleeInfection_Hard = FindConVar("cg_infection_attacked_chance_hard");
	g_GetMeleeInfection_Extreme = FindConVar("cg_infection_attacked_chance_extreme");
	
	for(new i=1; i<=MaxClients; i++)
	{
		if(IsClientInGame(i))
		{
			SDKHook(i, SDKHook_OnTakeDamage, OnTakeDamage);
		}
	}
	
	CheckInfectionMode();
	
	AutoExecConfig(true, "contagion_bethemod_config");
}

//=========================
// SpawnFirstAidKits()
//========================

public Action:SpawnFirstAidKits(client, args) 
{
	// If he got the "medic" perk
	if (g_nSurvivorPerks[client][STATE_MEDIC])
	{
		new String:GetSecondsString[10];
		if (GetCoolDownTimer > 1)
			GetSecondsString = "seconds";
		else
			GetSecondsString = "second";
		
		// Lets check if the medic cool down is enabled, if not, don't continue.
		if(MedicCoolDown[client])
		{
			PrintToChat(client, "You need to wait %d %s until you can spawn more medkits.", GetCoolDownTimer, GetSecondsString);
			return Plugin_Handled;
		}
		
		medkits_set = 0;
		MedicCoolDown[client] = true;
		CreateTimer(0.1, StartMedicTimer, client);
	}
	return Plugin_Handled;
}

//=========================
// CheckInfectionMode()
//========================

public CheckInfectionMode()
{
	new disabled = -1;
	if (GetConVarInt(g_hCvarNormalInfectionMode) == 1)
	{
		SetConVarInt(g_GetMeleeInfection_Easy, disabled);
		SetConVarInt(g_GetMeleeInfection_Normal, 3);
		SetConVarInt(g_GetMeleeInfection_Hard, 8);
		SetConVarInt(g_GetMeleeInfection_Extreme, 20);
	}
	else
	{
		SetConVarInt(g_GetMeleeInfection_Easy, disabled);
		SetConVarInt(g_GetMeleeInfection_Normal, disabled);
		SetConVarInt(g_GetMeleeInfection_Hard, disabled);
		SetConVarInt(g_GetMeleeInfection_Extreme, disabled);
	}
}

//=========================
// OnConVarChange()
//========================

public OnConVarChange(Handle:convar, const String:oldValue[], const String:newValue[])
{
	new disabled = -1;
	if (strcmp(oldValue, newValue) != 0)
	{
		if (strcmp(newValue, "1") == 0)
		{
			SetConVarInt(g_GetMeleeInfection_Easy, disabled);
			SetConVarInt(g_GetMeleeInfection_Normal, 3);
			SetConVarInt(g_GetMeleeInfection_Hard, 8);
			SetConVarInt(g_GetMeleeInfection_Extreme, 20);
		}
		else
		{
			SetConVarInt(g_GetMeleeInfection_Easy, disabled);
			SetConVarInt(g_GetMeleeInfection_Normal, disabled);
			SetConVarInt(g_GetMeleeInfection_Hard, disabled);
			SetConVarInt(g_GetMeleeInfection_Extreme, disabled);
		}
	}
}

//=========================
// OnConfigsExecuted()
//========================

public OnConfigsExecuted()
{
	// Build Logfile path
	BuildPath(Path_SM, logFilePath, sizeof(logFilePath), "logs/contagion_bethemod.log");
}

//=========================
// Database_Init()
//========================
/*
Database_Init()
{
	// TODO: Auto create the database..
}
*/
//=========================
// Database_Create()
//========================

public Database_Create(client, const String:uid[])
{
	// Create connection to sql server
	decl String:error[255] = "\0";
	new Handle:connection = SQL_DefConnect(error, sizeof(error));
	
	if(connection == INVALID_HANDLE)
	{
		// Log error
		LogToFileEx(logFilePath, "[BTM] Couldn't connect to SQL server! Error: %s", error);
		PrintToServer("[BTM] Couldn't connect to SQL server! Error: %s", error);
		
		return;
	}
	else
	{
		new Handle:hQuery;
		decl String:Query[255] = "\0";
		
		// Set SQL query
		Format(Query, sizeof(Query), "INSERT INTO `contagion_bethemod` (`uid`, `type`, `model`, `group`) VALUES ('%s', '', '', '')", uid);
		hQuery = SQL_Query(connection, Query);
		
		if(hQuery == INVALID_HANDLE)
		{
			// Log error
			SQL_GetError(connection, error, sizeof(error));
			
			// If it somehow wants to still create one on the "Primary" Key, return nothing.
			if (StrContains(error, "'PRIMARY'", false) != -1)
				return;
			else
			{
				LogToFileEx(logFilePath, "[BTM] Error on Query! Error: %s", error);
				PrintToServer("[BTM] Error on Query! Error: %s", error);
			}
			
			return;
		}
		else
		{
			if(SQL_GetRowCount(hQuery) == 0)
			{
				LogToFileEx(logFilePath, "[BTM] %N (SteamID: %s) created", client, uid);
			}
			else
				return;
		}
		
		// Close Query
		CloseHandle(hQuery);
	}
	
	// Close connection
	CloseHandle(connection);
}

//=========================
// Database_Save()
//========================

public Database_Save(client, const String:uid[], const String:type[], const String:group[], const String:model[])
{
	// Create connection to sql server
	decl String:error[255] = "\0";
	new Handle:connection = SQL_DefConnect(error, sizeof(error));
	
	if(connection == INVALID_HANDLE)
	{
		// Log error
		LogToFileEx(logFilePath, "[BTM] Couldn't connect to SQL server! Error: %s", error);
		PrintToServer("[BTM] Couldn't connect to SQL server! Error: %s", error);
		
		return;
	}
	else
	{
		new Handle:hQuery;
		decl String:Query[255] = "\0";
		
		Format(Query, sizeof(Query), "REPLACE INTO `contagion_bethemod` (`uid`, `type`, `model`, `group`) VALUES ('%s', '%s', '%s', '%s')", uid, type, model, group);
		hQuery = SQL_Query(connection, Query);
		
		if(hQuery == INVALID_HANDLE)
		{
			// Log error
			SQL_GetError(connection, error, sizeof(error));
			LogToFileEx(logFilePath, "[BTM] Error on Query! Error: %s", error);
			PrintToServer("[BTM] Error on Query! Error: %s", error);
			
			return;
		}
		else
		{
			LogToFileEx(logFilePath, "[BTM] %N (SteamID: %s) overwritten with model: %s (Type: %s) | Group: %s", client, uid, model, type, group);
		}
		
		// Close Query
		CloseHandle(hQuery);
	}
	
	// Close connection
	CloseHandle(connection);
}

//=========================
// Database_load()
//========================

public Database_load(client)
{
	// Create SQL connection
	decl String:error[255] = "\0";
	new Handle:connection = SQL_DefConnect(error, sizeof(error));
	
	// Check for connection error
	if(connection == INVALID_HANDLE)
	{
		// Log error
		LogToFileEx(logFilePath, "[BTM] Couldn't connect to SQL server! Error: %s", error);
		PrintToServer("[BTM] Couldn't connect to SQL server! Error: %s", error);
		return;
	}
	else
	{
		decl String:query[255] = "\0";
		new Handle:hQuery;
		
		Format(query, sizeof(query), "SELECT `type`, `model`, `group` FROM `contagion_bethemod` WHERE ( `uid` = '%s' )", authid[client]);
		hQuery = SQL_Query(connection, query);
		
		if(hQuery == INVALID_HANDLE)
		{
			// Log error
			SQL_GetError(connection, error, sizeof(error));
			LogToFileEx(logFilePath, "[BTM] Error on Query! Error: %s", error);
			PrintToServer("[BTM] Error on Query! Error: %s", error);
			return;
		}
		else
		{
			// Return if we can't find any player on the database
			if(SQL_GetRowCount(hQuery) == 0)
			{
				return;
			}
			
			decl String:type[255] = "\0";
			decl String:model[255] = "\0";
			decl String:group[255] = "\0";
			
			while(SQL_FetchRow(hQuery))
			{
				SQL_FetchString(hQuery, 0, type, sizeof(type));
				SQL_FetchString(hQuery, 1, model, sizeof(model));
				SQL_FetchString(hQuery, 2, group, sizeof(group));
				
				// Execute custom SQL queries
				db_group = group;
				db_model = model;
				db_type = type;
				
			}
			
			// Close Query
			CloseHandle(hQuery);
		}
		
		// Close connection
		CloseHandle(connection);
	}
}

//=========================
// OnMapStart()
//========================

public OnMapStart()
{
	// Precache and download all models
	new String:file[256];
	BuildPath(Path_SM, file, 255, "configs/models_download.ini");
	new Handle:fileh = OpenFile(file, "r");
	new String:buffer[256];
	new String:file_p[256];
	BuildPath(Path_SM, file_p, 255, "configs/models_precache.ini");
	new Handle:filep = OpenFile(file_p, "r");
	
	kv = CreateKeyValues("Commands");
	new String:file2[256];
	BuildPath(Path_SM, file2, 255, "configs/models.ini");
	FileToKeyValues(kv, file2);
	
	while (ReadFileLine(fileh, buffer, sizeof(buffer)))
	{
		new len = strlen(buffer);
		if (buffer[len-1] == '\n')
   			buffer[--len] = '\0';
   			
		if (FileExists(buffer))
		{
			AddFileToDownloadsTable(buffer);
		}
		
		if (IsEndOfFile(fileh))
			break;
	}
	
	while (ReadFileLine(filep, buffer, sizeof(buffer)))
	{
		new len = strlen(buffer);
		if (buffer[len-1] == '\n')
   			buffer[--len] = '\0';
   			
		if (FileExists(buffer))
		{
			PrecacheModel(buffer);
		}
		
		if (IsEndOfFile(filep))
			break;
	}
	
	mainmenu = BuildMainMenu();
}

//=========================
// Handle:BuildMainMenu()
//========================

Handle:BuildMainMenu()
{
	/* Create the menu Handle */
	new Handle:menu = CreateMenu(Menu_Group);
	
	if (!KvGotoFirstSubKey(kv))
	{
		return INVALID_HANDLE;
	}
	
	decl String:buffer[30];
	
	do
	{
		KvGetSectionName(kv, buffer, sizeof(buffer));
		
		AddMenuItem(menu,buffer,buffer);
		
	} while (KvGotoNextKey(kv));
	
	KvRewind(kv);
	
	SetMenuTitle(menu, "Choose a Model Group");
 
	return menu;
}

//=========================
// SelectSurvivorModel()
//========================

public Action:SelectSurvivorModel(client, args) 
{
	if (mainmenu == INVALID_HANDLE)
	{
		PrintToConsole(client, "There was an error generating the menu. Check your models.ini file");
		return Plugin_Handled;
	}
 
	DisplayMenu(mainmenu, client, MENU_TIME_FOREVER);
	
	return Plugin_Handled;
}

//=========================
// Menu_Group()
//========================

public Menu_Group(Handle:menu, MenuAction:action, param1, param2)
{
	// user has selected a model group

	if (action == MenuAction_Select)
	{
		new String:info[30];

		/* Get item info */
		new bool:found = GetMenuItem(menu, param2, info, sizeof(info));
		
		if (!found)
			return;
		
		KvJumpToKey(kv, info);
		
		// build menu
		KvGotoFirstSubKey(kv);
		
		new Handle:tempmenu = CreateMenu(Menu_Model);
		
		decl String:buffer[30];
		decl String:path[256];
		do
		{
			KvGetSectionName(kv, buffer, sizeof(buffer));
			
			KvGetString(kv, "path", path, sizeof(path),"");
			
			AddMenuItem(tempmenu,buffer,buffer);
			
		} while (KvGotoNextKey(kv));
		
		SetMenuTitle(tempmenu, info);
		
		KvRewind(kv);
		KvRewind(kv);
		
		DisplayMenu(tempmenu, param1, MENU_TIME_FOREVER);
	}
}

//=========================
// Menu_Model()
//========================

public Menu_Model(Handle:menu, MenuAction:action, param1, param2)
{
	//user choose a model
	
	if (action == MenuAction_Select)
	{
		new String:info[256];
		new String:group[30];
		new bool:setarmor = false;

		/* Get item info */
		new bool:found = GetMenuItem(menu, param2, info, sizeof(info));
		GetMenuTitle(menu, group, sizeof(group));
		
		if (!found)
			return;
		
		KvJumpToKey(kv, group);
		KvGotoFirstSubKey(kv);
		
		decl String:buffer[255];
		decl String:path[256];
		decl String:f_path[256];
		decl String:z_path[256];
		decl String:zhealth[256];
		decl String:armor[256];
		decl String:getgroup[256];
		decl String:extra[256];
		decl String:slot1[255];
		decl String:slot2[256];
		decl String:slot3[256];
		decl String:slot4[256];
		decl String:slot1_ammo[256];
		decl String:slot2_ammo[256];
		decl String:slot3_ammo[256];
		decl String:slot4_ammo[256];
		decl String:getmaxsurv[256];
		do
		{
			KvGetSectionName(kv, buffer, sizeof(buffer));
			if (StrEqual(buffer, info))
			{
				KvGetString(kv, "path", path, sizeof(path),"");
				KvGetString(kv, "f_path", f_path, sizeof(f_path),"");
				KvGetString(kv, "z_path", z_path, sizeof(z_path),"");
				KvGetString(kv, "health", gb_health, sizeof(gb_health),"");
				KvGetString(kv, "zhealth", zhealth, sizeof(zhealth),"");
				KvGetString(kv, "armor", armor, sizeof(armor),"");
				KvGetString(kv, "group", getgroup, sizeof(getgroup),"");
				KvGetString(kv, "max", getmaxsurv, sizeof(getmaxsurv),"");
				KvGetString(kv, "extra", extra, sizeof(extra),"");
				KvGotoFirstSubKey(kv);
				KvGetString(kv, "slot1", slot1, sizeof(slot1),"");
				KvGetString(kv, "slot1_ammo", slot1_ammo, sizeof(slot1_ammo),"");
				KvGetString(kv, "slot2", slot2, sizeof(slot2),"");
				KvGetString(kv, "slot2_ammo", slot2_ammo, sizeof(slot2_ammo),"");
				KvGetString(kv, "slot3", slot3, sizeof(slot3),"");
				KvGetString(kv, "slot3_ammo", slot3_ammo, sizeof(slot3_ammo),"");
				KvGetString(kv, "slot4", slot4, sizeof(slot4),"");
				KvGetString(kv, "slot4_ammo", slot4_ammo, sizeof(slot4_ammo),"");
				KvGoBack(kv);
				KvGoBack(kv);
			}
		} while (KvGotoNextKey(kv));
		
		// check if they have access
		new String:temp[5];
		new AdminId:AdmId = GetUserAdmin(param1);
		new count = GetAdminGroupCount(AdmId);
		new bool:access = false;
		for (new i =0; i<count; i++) 
		{
			if (FindAdmGroup(getgroup) == GetAdminGroup(AdmId, i, temp, sizeof(temp)))
			{
				access = true;
			}
		}
		
		if (StrEqual(getgroup,""))
			access = true;
		
		if (!access)
		{
			PrintToChat(param1,"Sorry, You do not have access to this model.");
			return;
		}
		
		// Get max survivors (how many can use it until it can't be used)
		new max = StringToInt(getmaxsurv);
		if(!CanUseModel(max, path)) return;
		
		if (GetConVarInt(g_hDebugMode) >= 1)
		{
			PrintToServer("info: %s", info);
			PrintToServer("type: %s", group);
			PrintToServer("path: %s", path);
			PrintToServer("f_path: %s", f_path);
			PrintToServer("z_path: %s", z_path);
			PrintToServer("health: %s", gb_health);
			PrintToServer("zhealth: %s", zhealth);
			PrintToServer("armor: %s", armor);
			PrintToServer("group: %s", getgroup);
			PrintToServer("extra: %s", extra);
			PrintToServer("====================");
			PrintToServer("slot1: %s", slot1);
			PrintToServer("slot1_ammo: %s", slot1_ammo);
			PrintToServer("slot2: %s", slot2);
			PrintToServer("slot2_ammo: %s", slot2_ammo);
			PrintToServer("slot3: %s", slot3);
			PrintToServer("slot3_ammo: %s", slot3_ammo);
			PrintToServer("slot4: %s", slot4);
			PrintToServer("slot4_ammo: %s", slot4_ammo);
		}
		
		if (!StrEqual(armor,"") || StrEqual(armor,"true"))
			setarmor = true;
		
		if (g_nBeTheMod[param1][g_nIfSelectedSurvivor] == STATE_NOT_SELECTED)
		{
			// Lets set the players modelinfo
			if (!StrEqual(path,"") && IsModelPrecached(path) && IsClientConnected(param1))
			{
				PrintToServer("Setting Model for client %i: %s",param1,info);
				new hhealth = StringToInt(gb_health);
				new zzhealth = StringToInt(zhealth);
				new ammo1 = StringToInt(slot1_ammo);
				new ammo2 = StringToInt(slot2_ammo);
				new ammo3 = StringToInt(slot3_ammo);
				new ammo4 = StringToInt(slot4_ammo);
				SetModel(param1, path, f_path, z_path, hhealth, zzhealth, slot1, ammo1, slot2, ammo2, slot3, ammo3, slot4, ammo4, setarmor, info);
				ResetPerkStatus(param1);
				SetSurvivorPerks(param1, extra);
			}
			g_nBeTheMod[param1][g_nIfSelectedSurvivor] = STATE_SELECTED;
		}
		else if (g_nBeTheMod[param1][g_nIfSelectedSurvivor] == STATE_SELECTED)
			PrintToChat(param1,"[CSM] You can't change survivor twice, wait for the next round.");
		else
			PrintToChat(param1,"[CSM] The round has already started, wait for the next round.");
		
		Database_Save(param1, authid[param1], group, getgroup, info);
		
		// a failsafe, if it tries to bug and show "Weapons" instead of the actual survivors.
		KvGoBack(kv);
		KvGoBack(kv);
	}
	
	if (action == MenuAction_End)
	{
		CloseHandle(menu);
	}
}

//=========================
// OnMapEnd()
//========================

public OnMapEnd()
{
	CloseHandle(kv);
	CloseHandle(mainmenu);
}

//=========================
// ResetRegen()
//========================

public Action:ResetRegen(Handle:timer, any:client)
{
	g_nBeTheMod[client][g_nIfRegen] = STATE_REGEN;
	CreateTimer(0.5, RegenPlayer, client, TIMER_REPEAT);
	return Plugin_Handled;
}

//=========================
// StartMedicTimer()
//========================

public Action:StartMedicTimer(Handle:timer, any:client)
{
	GetCoolDownTimer = GetConVarInt(g_hMedicCoolDown);
	CreateTimer(1.0, StartCoolDown, client, TIMER_REPEAT);
	CreateTimer(0.1, SpawnMedkits, client, TIMER_REPEAT);
	return Plugin_Handled;
}

//=========================
// StartCoolDown()
//========================

public Action:StartCoolDown(Handle:timer, any:client)
{
	if (GetClientTeam(client) == _:CTEAM_Zombie)
		return Plugin_Stop;
	
	if (IsClientInGame(client) && MedicCoolDown[client])
	{
		GetCoolDownTimer --;
		
		if(GetCoolDownTimer <= 0)
		{
			MedicCoolDown[client] = false;
			return Plugin_Stop;
		}
		return Plugin_Handled;
	}
	return Plugin_Handled;
}

//=========================
// SpawnMedkits()
//========================

public Action:SpawnMedkits(Handle:timer, any:client)
{
	if (GetClientTeam(client) == _:CTEAM_Zombie)
		return Plugin_Stop;
	
	if (IsClientInGame(client))
	{
		if(medkits_set == -1)
			return Plugin_Stop;
		
		medkits_set ++;
		SpawnMedkit(client);
		
		if(medkits_set >= GetConVarInt(g_hMedicSpawns))
		{
			medkits_set = -1;
			return Plugin_Stop;
		}
		return Plugin_Handled;
	}
	return Plugin_Handled;
}

//=========================
// CheckTeams()
//========================

public CheckTeams()
{
	if (GetConVarInt(g_hCvarMode) > GetSpecialCount())
	{
		CanBeCarrier = true;
		if (GetConVarInt(g_hDebugMode) >= 1)
			PrintToServer("Carrier: YES");
	}
	else
	{
		CanBeCarrier = false;
		if (GetConVarInt(g_hDebugMode) >= 1)
			PrintToServer("Carrier: NO");
	}
}

//=========================
// EVENT_PlayerDeath()
//========================

public Action:EVENT_PlayerDeath(Handle:hEvent,const String:name[],bool:dontBroadcast)
{
//	new attacker = GetClientOfUserId(GetEventInt(hEvent, "attacker"));
	new victim = GetClientOfUserId(GetEventInt(hEvent, "userid"));
	
	if (!IsValidClient(victim, false)) return;
	
	if (g_nBeTheMod[victim][g_nIfRegen] == STATE_REGEN)
		g_nBeTheMod[victim][g_nIfRegen] = STATE_NO_REGEN;
}

//=========================
// EVENT_GameStart()
//========================

public Action:EVENT_GameStart(Handle:hEvent,const String:name[],bool:dontBroadcast)
{
	PrintToServer("[[ Round has Begun ]]");
	CreateTimer(GetConVarFloat(g_SetCharLimitTime), DisableCharSelection);
}

//=========================
// DisableCharSelection()
//========================

public Action:DisableCharSelection(Handle:timer)
{
	for (new i = 1; i <= MaxClients; i++)
	{
		if (IsValidClient(i))
		{
			new restriction = GetConVarInt(g_SetCharRestriction);
			new String:getname[253];
			GetCurrentMap(getname, 252);
			switch(restriction)
			{
				case 0:
				{
					// Disabled
				}
				case 1:
				{
					// Hunted Only
					if (StrContains(getname, "ch", false) == 0)
					{
						g_nBeTheMod[i][g_nIfSelectedSurvivor] = STATE_LATE;
					}
				}
				case 2:
				{
					// Hunted and Classic Only
					if (StrContains(getname, "ch", false) == 0)
					{
						g_nBeTheMod[i][g_nIfSelectedSurvivor] = STATE_LATE;
					}
					else if (StrContains(getname, "cpc", false) == 0)
					{
						g_nBeTheMod[i][g_nIfSelectedSurvivor] = STATE_LATE;
					}
					else if (StrContains(getname, "cpo", false) == 0)
					{
						g_nBeTheMod[i][g_nIfSelectedSurvivor] = STATE_LATE;
					}
				}
				default:
				{
					// All Modes
					g_nBeTheMod[i][g_nIfSelectedSurvivor] = STATE_LATE;
				}
			}
		}
	}
}

//=========================
// EVENT_GameEnd()
//========================

public ResetPerkStatus(client)
{
	if(!IsValidClient(client))
		return;
	
	if (g_nSurvivorPerks[client][STATE_EXPLOBOLT])
		g_nSurvivorPerks[client][STATE_EXPLOBOLT] = false;
	if (g_nSurvivorPerks[client][STATE_MELEE_GOOD])
		g_nSurvivorPerks[client][STATE_MELEE_GOOD] = false;
	if (g_nSurvivorPerks[client][STATE_MELEE_BAD])
		g_nSurvivorPerks[client][STATE_MELEE_BAD] = false;
	if (g_nSurvivorPerks[client][STATE_DEMO])
		g_nSurvivorPerks[client][STATE_DEMO] = false;
	if (g_nSurvivorPerks[client][STATE_MEDIC])
		g_nSurvivorPerks[client][STATE_MEDIC] = false;
	if (g_nSurvivorPerks[client][STATE_SREGEN])
		g_nSurvivorPerks[client][STATE_SREGEN] = false;
}

//=========================
// EVENT_GameEnd()
//========================

public Action:EVENT_GameEnd(Handle:hEvent,const String:name[],bool:dontBroadcast)
{
	// Disable everything due the survivors are dead
	CanBeCarrier = false;
	
	PrintToServer("[[ Round has Ended ]]");
	
	for (new i = 1; i <= MaxClients; i++)
	{
		if (IsValidClient(i))
		{
			if (g_nBeTheMod[i][g_nIfRegen] == STATE_REGEN)
				g_nBeTheMod[i][g_nIfRegen] = STATE_NO_REGEN;
			if (g_nBeTheMod[i][g_nIfSpecial_Carrier] == STATE_CARRIER)
				g_nBeTheMod[i][g_nIfSpecial_Carrier] = STATE_NOT_CARRIER;
			if (g_nBeTheMod[i][g_nIfSpecial_Survivor] == STATE_ARMOR)
				g_nBeTheMod[i][g_nIfSpecial_Survivor] = STATE_NORMAL;
			if (g_nBeTheMod[i][g_nIfSelectedSurvivor] == STATE_SELECTED)
				g_nBeTheMod[i][g_nIfSelectedSurvivor] = STATE_NOT_SELECTED;
			if (g_nBeTheMod[i][g_nIfSelectedSurvivor] == STATE_LATE)
				g_nBeTheMod[i][g_nIfSelectedSurvivor] = STATE_NOT_SELECTED;
		}
	}
}

//=========================
// EVENT_PlayerSpawned()
//========================

public Action:EVENT_PlayerSpawned(Handle:hEvent,const String:name[],bool:dontBroadcast)
{
	new client = GetClientOfUserId(GetEventInt(hEvent, "userid"));
	if (!IsValidClient(client)) return;
	
	CheckTeams();
	
	MedicCoolDown[client] = false;
	
	// Lets make a small timer, so the model can be set 1.2 second(s) after the player has actually spawned, so we can actually override the model.
	// Note#1: Don't change this, since it might screw up the spawning for the survivors.
	new Float:SetTime;
	if (GetClientTeam(client) == _:CTEAM_Survivor)
		SetTime = 1.2 + float(client) / 8;
	else
		SetTime = 0.2;
	PrintToServer("[[ Client Time: %f ]]", SetTime);
	CreateTimer(SetTime, SetSpawnModel, client);
}

//=========================
// SetSpawnModel()
//========================

public Action:SetSpawnModel(Handle:timer, any:client)
{
	Database_load(client);
	
	// A failsafe, because sometimes it wants to load "Weapons"
	KvGoBack(kv);
	KvGoBack(kv);
	
	new String:temp[2];
	new AdminId:AdmId = GetUserAdmin(client);
	new count = GetAdminGroupCount(AdmId);
	new bool:setarmor = false;
	new bool:access = false;
	for (new i =0; i<count; i++) 
	{
		if (FindAdmGroup(db_group) == GetAdminGroup(AdmId, i, temp, sizeof(temp)))
		{
			access = true;
			break;
		}
	}
	
	if (StrEqual(db_group,""))
		access = true;
	
	if (!access)
	{
		PrintToChat(client,"Sorry, You no longer have access to this model. Please select another using !csm");
		return;
	}
	
	KvJumpToKey(kv, db_type);
	KvGotoFirstSubKey(kv);
	
	decl String:buffer[255];
	decl String:path[256];
	decl String:f_path[256];
	decl String:z_path[256];
	decl String:zhealth[256];
	decl String:armor[256];
	decl String:getgroup[256];
	decl String:extra[256];
	decl String:slot1[255];
	decl String:slot2[256];
	decl String:slot3[256];
	decl String:slot4[256];
	decl String:slot1_ammo[256];
	decl String:slot2_ammo[256];
	decl String:slot3_ammo[256];
	decl String:slot4_ammo[256];
	decl String:getmaxsurv[256];
	do
	{
		KvGetSectionName(kv, buffer, sizeof(buffer));
		if (StrEqual(buffer, db_model))
		{
			KvGetString(kv, "path", path, sizeof(path),"");
			KvGetString(kv, "f_path", f_path, sizeof(f_path),"");
			KvGetString(kv, "z_path", z_path, sizeof(z_path),"");
			KvGetString(kv, "health", gb_health, sizeof(gb_health),"");
			KvGetString(kv, "zhealth", zhealth, sizeof(zhealth),"");
			KvGetString(kv, "armor", armor, sizeof(armor),"");
			KvGetString(kv, "group", getgroup, sizeof(getgroup),"");
			KvGetString(kv, "max", getmaxsurv, sizeof(getmaxsurv),"");
			KvGetString(kv, "extra", extra, sizeof(extra),"");
			KvGotoFirstSubKey(kv);
			KvGetString(kv, "slot1", slot1, sizeof(slot1),"");
			KvGetString(kv, "slot1_ammo", slot1_ammo, sizeof(slot1_ammo),"");
			KvGetString(kv, "slot2", slot2, sizeof(slot2),"");
			KvGetString(kv, "slot2_ammo", slot2_ammo, sizeof(slot2_ammo),"");
			KvGetString(kv, "slot3", slot3, sizeof(slot3),"");
			KvGetString(kv, "slot3_ammo", slot3_ammo, sizeof(slot3_ammo),"");
			KvGetString(kv, "slot4", slot4, sizeof(slot4),"");
			KvGetString(kv, "slot4_ammo", slot4_ammo, sizeof(slot4_ammo),"");
			KvGoBack(kv);
			KvGoBack(kv);
		}
	} while (KvGotoNextKey(kv));
	
	if (!StrEqual(armor,"") || StrEqual(armor,"true"))
		setarmor = true;
	
	// Get max survivors (how many can use it until it can't be used)
	new max = StringToInt(getmaxsurv);
	if(!CanUseModel(max, path)) return;
	
	// Lets set the players modelinfo
	if (!StrEqual(path,"") && IsModelPrecached(path) && IsClientConnected(client))
	{
		if (GetConVarInt(g_hDebugMode) >= 1)
		{
			PrintToServer("====================");
			PrintToServer("info: %s", db_model);
			PrintToServer("type: %s", db_group);
			PrintToServer("path: %s", path);
			PrintToServer("f_path: %s", f_path);
			PrintToServer("z_path: %s", z_path);
			PrintToServer("health: %s", gb_health);
			PrintToServer("zhealth: %s", zhealth);
			PrintToServer("armor: %s", armor);
			PrintToServer("group: %s", getgroup);
			PrintToServer("extra: %s", extra);
			PrintToServer("====================");
			PrintToServer("slot1: %s", slot1);
			PrintToServer("slot1_ammo: %s", slot1_ammo);
			PrintToServer("slot2: %s", slot2);
			PrintToServer("slot2_ammo: %s", slot2_ammo);
			PrintToServer("slot3: %s", slot3);
			PrintToServer("slot3_ammo: %s", slot3_ammo);
			PrintToServer("slot4: %s", slot4);
			PrintToServer("slot4_ammo: %s", slot4_ammo);
			PrintToServer("====================");
		}
		
		PrintToServer("Setting Model for client %i: %s",client,db_model);
		new hhealth = StringToInt(gb_health);
		new zzhealth = StringToInt(zhealth);
		new ammo1 = StringToInt(slot1_ammo);
		new ammo2 = StringToInt(slot2_ammo);
		new ammo3 = StringToInt(slot3_ammo);
		new ammo4 = StringToInt(slot4_ammo);
		SetModel(client, path, f_path, z_path, hhealth, zzhealth, slot1, ammo1, slot2, ammo2, slot3, ammo3, slot4, ammo4, setarmor, db_model);
		ResetPerkStatus(client);
		SetSurvivorPerks(client, extra);
	}
}

//=========================
// OnTakeDamage()
//========================

public Action:OnTakeDamage(victim, &attacker, &inflictor, &Float:damage, &damagetype, &weapon, Float:damageForce[3], Float:damagePosition[3], damagecustom)
{
	// lets make sure they are actual clients
	if (!IsValidClient(attacker)) return;
	if (!IsValidClient(victim)) return;
	
	if (GetClientTeam(victim) == _:CTEAM_Zombie)
	{
		// Don't continue if the victim is also the attacker
		if (attacker == victim) return;
		
		// Zombie Infection
		if (GetClientTeam(attacker) == _:CTEAM_Zombie && g_nBeTheMod[attacker][g_nIfSpecial_Carrier] == STATE_CARRIER && g_nBeTheMod[victim][g_nIfSpecial_Survivor] == STATE_NORMAL)
		{
			new infection_chance = GetRandomInt(1, INFECTION_MAX_CHANCE);
			switch(infection_chance)
			{
				// The carrier have higher chance to infect someone
				case 1,3,5,8,18,20:
				{
					CONTAGION_SetInfectionTime(victim, GetConVarFloat(g_SetWhiteyInfectionTime));
				}
				
				default:
				{
				}
			}
		}
		else if (GetClientTeam(attacker) == _:CTEAM_Zombie && g_nBeTheMod[attacker][g_nIfSpecial_Carrier] == STATE_CARRIER && g_nBeTheMod[victim][g_nIfSpecial_Survivor] == STATE_ARMOR)
		{
			new infection_chance = GetRandomInt(1, INFECTION_MAX_CHANCE);
			switch(infection_chance)
			{
				// The carrier have less chance to infect riot survivors
				case 2,5,20:
				{
					CONTAGION_SetInfectionTime(victim, GetConVarFloat(g_SetWhiteyInfectionTime));
				}
				
				default:
				{
				}
			}
		}
		// If the carrier is hurt, lets reset the regen
		if (g_nBeTheMod[victim][g_nIfSpecial_Carrier] == STATE_CARRIER)
		{
			if (g_nBeTheMod[victim][g_nIfRegen] == STATE_REGEN)
				g_nBeTheMod[victim][g_nIfRegen] = STATE_NO_REGEN;
			if(ResetRegenTimer[victim] != INVALID_HANDLE)
			{
				ResetRegenTimer[victim] = INVALID_HANDLE;
			}
			ResetRegenTimer[victim] = CreateTimer(30.0, ResetRegen, victim);
		}
	}
	
	// Survivor Perks (DMG TYPES)
	if (GetClientTeam(attacker) == _:CTEAM_Survivor)
	{
		// Get weapon name
		new String:WeaponName[256];
		GetClientWeapon(attacker, WeaponName, sizeof(WeaponName));
		
		// Debbuger that tells the client which gun he is using and how much damage he is doing.
		if (GetConVarInt(g_hDebugMode) >= 1)
		{
			PrintToChat(attacker,"[BTM || DEBUGGER] Weapon: %s | Damage: %f2.2", WeaponName, damage);
		}
		
		if(g_nSurvivorPerks[attacker][STATE_MELEE_GOOD])
		{
			if(StrEqual(WeaponName,"weapon_melee"))
			{
				// Setup new damage
				damage * 1.30;
				// Show how much extra damage we are doing currently
				if (GetConVarInt(g_hDebugMode) >= 1)
				{
					PrintToChat(attacker,"[BTM || DEBUGGER] Using perk \"Melee+\" | New Damage: %f2.2 ", damage);
				}
			}
		}
		if(g_nSurvivorPerks[attacker][STATE_MELEE_BAD])
		{
			if(StrEqual(WeaponName,"weapon_melee"))
			{
				// Setup new damage
				damage / 1.25;
				// Show how much extra damage we are doing currently
				if (GetConVarInt(g_hDebugMode) >= 1)
				{
					PrintToChat(attacker,"[BTM || DEBUGGER] Using perk \"Melee-\" | New Damage: %f2.2 ", damage);
				}
			}
		}
		if(g_nSurvivorPerks[attacker][STATE_DEMO])
		{
			if(StrEqual(WeaponName,"weapon_grenade") || StrEqual(WeaponName,"weapon_ied"))
			{
				// Setup new damage
				damage * 1.40;
				// Show how much extra damage we are doing currently
				if (GetConVarInt(g_hDebugMode) >= 1)
				{
					PrintToChat(attacker,"[BTM || DEBUGGER] Using perk \"Demolition\" | New Damage: %f2.2 ", damage);
				}
			}
		}
		if(g_nSurvivorPerks[victim][STATE_SREGEN])
		{
			if (g_nBeTheMod[victim][g_nIfRegen] == STATE_REGEN)
				g_nBeTheMod[victim][g_nIfRegen] = STATE_NO_REGEN;
			if(ResetRegenTimer[victim] != INVALID_HANDLE)
			{
				ResetRegenTimer[victim] = INVALID_HANDLE;
			}
			ResetRegenTimer[victim] = CreateTimer(30.0, ResetRegen, victim);
		}
	}
}

public OnEntityCreated(entity, const String:classname[])
{
	new bool:arrow = StrEqual(classname, "crossbow_arrow");
	if (arrow) {
		SDKHook(entity, SDKHook_Touch, OnArrowTouch);
	}
}

//=========================
// OnArrowTouch()
//========================

public Action:OnArrowTouch(entity, other) {
	new client = GetEntPropEnt(entity, Prop_Send, "m_hOwnerEntity");
	
	if(!IsValidClient(client))
		return Plugin_Continue;
	
	if(!g_nSurvivorPerks[client][STATE_EXPLOBOLT])
		return Plugin_Continue;
	
	new Float:g_pos[3];
	GetEntPropVector(entity, Prop_Send, "m_vecOrigin", g_pos);
	
	new Handle:pack;
	CreateDataTimer(0.0, Timer_Explode, pack, TIMER_FLAG_NO_MAPCHANGE);
	WritePackCell(pack, GetClientUserId(client));
	WritePackFloat(pack, g_pos[0]);
	WritePackFloat(pack, g_pos[1]);
	WritePackFloat(pack, g_pos[2]);
	
	return Plugin_Continue;
}

//=========================
// Timer_Explode()
//========================

public Action:Timer_Explode(Handle:timer, Handle:pack)
{
	ResetPack(pack);
	decl Float:pos1[3];
	new client = GetClientOfUserId(ReadPackCell(pack));
	pos1[0] = ReadPackFloat(pack);
	pos1[1] = ReadPackFloat(pack);
	pos1[2] = ReadPackFloat(pack);
	new dmg = GetConVarInt(g_explobolt_dmg);
	new range = 200;
	DoExplosion(client, dmg, range, pos1);
}

//=========================
// SpawnMedkit()
//========================

stock SpawnMedkit(origin)
{
	new firstaid = CreateEntityByName("weapon_firstaid");
	
	new String:position[64];
	decl Float:pos[3];
	
	if(!IsValidEntity(firstaid))
		return;
	
	if(!IsValidEntity(origin))
		return;
	
	GetClientAbsOrigin(origin, pos);
	
	pos[2] = pos[2] + 50;
	
	Format(position, sizeof(position), "%1.1f %1.1f %1.1f", pos[0], pos[1], pos[2]);
	
	DispatchKeyValue(firstaid, "origin", position);
	
	DispatchSpawn(firstaid);
	ActivateEntity(firstaid);
}

//=========================
// DoExplosion()
//========================

stock DoExplosion(owner, damage, radius, Float:pos[3])
{
	new explode = CreateEntityByName("env_explosion");
	
	new String:position[64];
	new String:dmg[64];
	new String:range[64];
	
	if(!IsValidEntity(explode))
		return;
	
	Format(position, sizeof(position), "%1.1f %1.1f %1.1f", pos[0], pos[1], pos[2]);
	Format(dmg, sizeof(dmg), "%d", damage);
	Format(range, sizeof(range), "%d", radius);
	
	DispatchKeyValue(explode, "origin", position);
	DispatchKeyValue(explode, "targetname", "explode");
	DispatchKeyValue(explode, "spawnflags", "2");
	DispatchKeyValue(explode, "rendermode", "5");
	
	DispatchKeyValue(explode, "iMagnitude", dmg);
	DispatchKeyValue(explode, "iRadiusOverride", range);
	
	SetEntPropEnt(explode, Prop_Data, "m_hOwnerEntity", owner);
	
	DispatchSpawn(explode);
	ActivateEntity(explode);
	
	AcceptEntityInput(explode, "Explode");
	AcceptEntityInput(explode, "Kill");
}

//=========================
// OnClientPutInServer()
//========================

public OnClientPutInServer(client)
{
	SDKHook(client, SDKHook_OnTakeDamage, OnTakeDamage);
	GetClientAuthId(client, AuthId_Steam3, authid[client], sizeof(authid[]));
	Database_Create(client, authid[client]);
}

//=========================
// RegenPlayer()
//========================

public Action:RegenPlayer(Handle:timer, any:client)
{
	if (IsClientInGame(client))
	{
		// If the player is not alive, don't do anything.
		if (!IsPlayerAlive(client))
		{
			ResetRegenTimer[client] = INVALID_HANDLE;
			return Plugin_Stop;
		}
		
		// It can somehow call this w/o its being called, pretty wierd huh?
		if (GetClientTeam(client) == _:CTEAM_Survivor)
		{
			if (!g_nSurvivorPerks[client][STATE_SREGEN])
			{
				ResetRegenTimer[client] = INVALID_HANDLE;
				return Plugin_Stop;
			}
		}
		
		// If the player got hurt, and has regen already running, lets make sure it stops. Else it will keep going.
		if (g_nBeTheMod[client][g_nIfRegen] == STATE_NO_REGEN)
		{
			ResetRegenTimer[client] = INVALID_HANDLE;
			return Plugin_Stop;
		}
		
		// Setup Stage
		new iHealth = GetClientHealth(client) + 5;
		new hhealth = StringToInt(gb_health);
		
		// If they already have full health, don't start this at all!
		if(GetClientTeam(client) == _:CTEAM_Survivor)
		{
			if(iHealth == hhealth)
			{
				ResetRegenTimer[client] = INVALID_HANDLE;
				return Plugin_Stop;
			}
		}
		else
		{
			if(iHealth == GetConVarInt(g_SetWhiteyHealth))
			{
				ResetRegenTimer[client] = INVALID_HANDLE;
				return Plugin_Stop;
			}
		}
		
		// Whitey Regen
		if (g_nBeTheMod[client][g_nIfRegen] == STATE_REGEN && ResetRegenTimer[client] != INVALID_HANDLE)
		{
			SetEntityHealth(client, iHealth);
			
			if (GetConVarInt(g_hDebugMode) >= 1)
			{
				PrintToServer("[[ %N new Health: %d ]]", client, iHealth);
				PrintToServer("[[ %N Regen Status: %d ]]", client, g_nBeTheMod[client][g_nIfRegen]);
			}
			
			if(g_nBeTheMod[client][g_nIfSpecial_Carrier] == STATE_CARRIER && iHealth >= GetConVarInt(g_SetWhiteyHealth))
			{
				g_nBeTheMod[client][g_nIfRegen] = STATE_NO_REGEN;
				SetEntityHealth(client, GetConVarInt(g_SetWhiteyHealth));
				if (GetConVarInt(g_hDebugMode) >= 1)
				{
					PrintToServer("[[ %N Health reset: %d ]]", client, GetConVarInt(g_SetWhiteyHealth));
					PrintToServer("[[ %N Regen Status: %d ]]", client, g_nBeTheMod[client][g_nIfRegen]);
				}
				ResetRegenTimer[client] = INVALID_HANDLE;
				return Plugin_Stop;
			}
		}
		
		// Survivor Regen perk
		if(GetClientTeam(client) == _:CTEAM_Survivor)
		{
			SetEntityHealth(client, iHealth);
			
			if (GetConVarInt(g_hDebugMode) >= 1)
			{
				PrintToServer("[[ %N new Health: %d ]]", client, iHealth);
			}
			
			if(g_nSurvivorPerks[client][STATE_SREGEN] && iHealth >= hhealth)
			{
				g_nBeTheMod[client][g_nIfRegen] = STATE_NO_REGEN;
				SetEntityHealth(client, hhealth);
				if (GetConVarInt(g_hDebugMode) >= 1)
				{
					PrintToServer("[[ %N Health reset: %d ]]", client, hhealth);
				}
				ResetRegenTimer[client] = INVALID_HANDLE;
				return Plugin_Stop;
			}
		}
	}
	return Plugin_Handled;
}

//=========================
// SetModel()
//========================

public SetModel(client, const String:model[], const String:fmodel[], const String:zmodel[], health, zhealth, const String:slot1[], slot1_ammo, const String:slot2[], slot2_ammo, const String:slot3[], slot3_ammo, const String:slot4[], slot4_ammo, hasarmor, const String:model_type[])
{
	if (GetClientTeam(client) == _:CTEAM_Zombie)
	{
		if (CanBeCarrier)
			g_nBeTheMod[client][g_nIfSpecial_Carrier] = STATE_CARRIER;
	}
	
	// Zombies only
	if (GetClientTeam(client) == _:CTEAM_Zombie)
	{
		if (g_nBeTheMod[client][g_nIfSpecial_Carrier] == STATE_CARRIER)
		{
			PrecacheModel("models/zombies/whitey/whitey.mdl", true);
			SetEntityModel(client,"models/zombies/whitey/whitey.mdl");
			new sethealth = GetConVarInt(g_SetWhiteyHealth);
			new newmaxhealth = GetConVarInt(g_SetWhiteyHealth);
			CONTAGION_SetNewHealth(client, sethealth, newmaxhealth);
		}
		else if (!StrEqual(zmodel,""))
		{
			PrecacheModel(zmodel, true);
			SetEntityModel(client,zmodel);
			new NewHP = zhealth;
			CONTAGION_SetNewHealth(client, NewHP, NewHP);
		}
	}
	// Survivor only
	else if (GetClientTeam(client) == _:CTEAM_Survivor)
	{
		// If the paths are nulled, then return errors, so the server owner knows the issue.
		if (StrEqual(model,""))
		{
			LogToFileEx(logFilePath, "[BTM] The survivor model (%s) do not exist!", model_type);
			PrintToServer("[BTM] The survivor model (%s) do not exist!", model_type);
		}
		if (StrEqual(fmodel,""))
		{
			LogToFileEx(logFilePath, "[BTM] The female survivor model (%s) do not exist!", model_type);
			PrintToServer("[BTM] The female survivor model (%s) do not exist!", model_type);
		}
		if (StrEqual(zmodel,""))
		{
			LogToFileEx(logFilePath, "[BTM] The zombie model (%s) do not exist!", model_type);
			PrintToServer("[BTM] The zombie model (%s) do not exist!", model_type);
		}
		
		// If they never specified a zombie model, then call nothing.
		if (!StrEqual(zmodel,""))
		{
			// Lets make sure what survivor they are, so we can actually make sure we set a male or a female model on them.
			new Gender = CONTAGION_GetSurvivorCharacter(client);
			new NewHP = health;
			if (Gender == 4 || Gender == 5)
			{
				PrecacheModel(fmodel, true);
				SetEntityModel(client, fmodel);
			}
			else
			{
				PrecacheModel(model, true);
				SetEntityModel(client, model);
			}
			
			if (hasarmor)
				g_nBeTheMod[client][g_nIfSpecial_Survivor] = STATE_ARMOR;
			else
				g_nBeTheMod[client][g_nIfSpecial_Survivor] = STATE_NORMAL;
			
			CONTAGION_SetNewHealth(client, NewHP, NewHP);
			if (!StrEqual(slot1,"") || !StrEqual(slot2,"") ||
				!StrEqual(slot3,"") ||  !StrEqual(slot4,""))
				{
					CONTAGION_RemoveAllFirearms(client);
					CONTAGION_GiveClientWeapon(client, slot1, slot1_ammo);
					CONTAGION_GiveClientWeapon(client, slot2, slot2_ammo);
					CONTAGION_GiveClientWeapon(client, slot3, slot3_ammo);
					CONTAGION_GiveClientWeapon(client, slot4, slot4_ammo);
				}
		}
	}
}

//=========================
// SetSurvivorPerks()
//========================

SetSurvivorPerks(client, const String:extras[])
{
	if (StrContains(extras, "grenades", false) != -1)
	{
		CONTAGION_ClientGiveExtraAmmo(client, "weapon_grenade", 3);
	}
	if (StrContains(extras, "melee+", false) != -1)
	{
		g_nSurvivorPerks[client][STATE_MELEE_GOOD] = true;
	}
	if (StrContains(extras, "melee-", false) != -1)
	{
		g_nSurvivorPerks[client][STATE_MELEE_BAD] = true;
	}
	if (StrContains(extras, "demo", false) != -1)
	{
		g_nSurvivorPerks[client][STATE_DEMO] = true;
	}
	if (StrContains(extras, "explobolt", false) != -1)
	{
		g_nSurvivorPerks[client][STATE_EXPLOBOLT] = true;
	}
	if (StrContains(extras, "medic", false) != -1)
	{
		g_nSurvivorPerks[client][STATE_MEDIC] = true;
	}
	if (StrContains(extras, "regeneration", false) != -1)
	{
		g_nSurvivorPerks[client][STATE_SREGEN] = true;
	}
}

//=========================
// OnClientDisconnect()
//========================

public OnClientDisconnect(client)
{
	CheckTeams();
}

//=========================
// bool:IsValidClient()
//========================

stock bool:IsValidClient(client, bool:bCheckAlive=true)
{
	if(client < 1 || client > MaxClients) return false;
	if(!IsClientInGame(client)) return false;
	if(IsClientSourceTV(client) || IsClientReplay(client)) return false;
	if(IsFakeClient(client)) return true; // must be true, so it checks for zombies etc..
	if(bCheckAlive) return IsPlayerAlive(client);
	return true;
}

//=========================
// bool:CanUseModel()
//========================

stock bool:CanUseModel(getmax, const String:getmodel[])
{
	if(getmax == 0)	return true;
	if(StrEqual(getmodel,"")) return true;
	
	new String:plymdl[128];
	decl iCount, i; iCount = 0;
	
	for( i = 1; i <= MaxClients; i++ )
		if( IsClientInGame(i) && IsPlayerAlive(i) )
		{
			GetEntPropString(i, Prop_Data, "m_ModelName", plymdl, 128);
			if (StrEqual(plymdl, getmodel))
				iCount++;
		}
	
	if(iCount == getmax)
		return false;
	else
		return true;
}

//=========================
// GetSpecialCount()
//========================

GetSpecialCount()
{
	decl iCount, i; iCount = 0;
	
	for( i = 1; i <= MaxClients; i++ )
		if( IsClientInGame(i) && IsPlayerAlive(i) && GetClientTeam(i) == _:CTEAM_Zombie && g_nBeTheMod[i][g_nIfSpecial_Carrier] == STATE_CARRIER )
			iCount++;
	
	return iCount;
}