#pragma semicolon               1
#pragma newdecls                required


#include <confogl_core>

#undef REQUIRE_PLUGIN
#include <l4d2_changelevel>
#define REQUIRE_PLUGIN


public Plugin myinfo =
{
	name = "ConfoglMatchAutoload",
	author = "TouchMe",
	description = "N/a",
	version = "build0000",
	url = "https://github.com/TouchMe-Inc/l4d2_confogl"
}


#define LIB_CHANGELEVEL         "l4d2_changelevel"

#define CONFIG_PATH        "configs/confogl_match_autoload.txt"


bool
	g_bInit = false,
	g_bLoopFixed = false
;

char
	g_sNewGamemode[32],
	g_sDifficulty[32]
;

Handle
	g_hGamemodes = null,
	g_hGamemodeConfig = null
;

ConVar
	g_cvGameMode = null,
	g_cvDifficulty = null,
	g_cvAllBotGame = null
;

bool g_bAllBotGameOldAValue = false;

bool g_bChangeLevelAvailable = false;


/**
  * Global event. Called when a library is removed.
  *
  * @param sName     Library name
  */
public void OnLibraryRemoved(const char[] sName)
{
	if (StrEqual(sName, LIB_CHANGELEVEL)) {
		g_bChangeLevelAvailable = false;
	}
}

/**
  * Global event. Called when a library is added.
  *
  * @param sName     Library name
  */
public void OnLibraryAdded(const char[] sName)
{
	if (StrEqual(sName, LIB_CHANGELEVEL)) {
		g_bChangeLevelAvailable = true;
	}
}

/**
 * Called before OnPluginStart.
 *
 * @param myself      Handle to the plugin
 * @param bLate       Whether or not the plugin was loaded "late" (after map load)
 * @param sErr        Error message buffer in case load failed
 * @param iErrLen     Maximum number of characters for error message buffer
 * @return            APLRes_Success | APLRes_SilentFailure
 */
public APLRes AskPluginLoad2(Handle myself, bool bLate, char[] sErr, int iErrLen)
{
	if (GetEngineVersion() != Engine_Left4Dead2) {
		strcopy(sErr, iErrLen, "Plugin only supports Left 4 Dead 2");
		return APLRes_SilentFailure;
	}

	return APLRes_Success;
}

public void OnPluginStart()
{
	LoadGamemodes(g_hGamemodes = CreateKeyValues("Gamemodes"));
	FillGamemodeConfig(g_hGamemodes, g_hGamemodeConfig = CreateTrie());

	g_cvAllBotGame = FindConVar("sb_all_bot_game");
	HookConVarChange((g_cvDifficulty = FindConVar("z_difficulty")), ConVarChange_Difficulty);
	HookConVarChange((g_cvGameMode = FindConVar("mp_gamemode")), OnConVarChange_GameMode);

	HookEvent("player_disconnect", Event_PlayerDisconnect, EventHookMode_Pre);

	g_bInit = false;
}

public void ConVarChange_Difficulty(ConVar convar, const char[] sOldGamemode, const char[] sGamemode)
{
	strcopy(g_sDifficulty, sizeof(g_sDifficulty), sGamemode);
}

public void OnConVarChange_GameMode(ConVar convar, const char[] sOldGamemode, const char[] sGamemode)
{
	if (Confogl_IsConfigLoaded() && !g_bLoopFixed)
	{
		g_bLoopFixed = true;

		char sConfig[64]; Confogl_GetConfigName(sConfig, sizeof(sConfig));

		char sGamemodeConfig[64];

		bool bNeedConfig = GetTrieString(g_hGamemodeConfig, sGamemode, sGamemodeConfig, sizeof(sGamemodeConfig));

		if (!bNeedConfig || !StrEqual(sGamemodeConfig, sConfig))
		{
			strcopy(g_sNewGamemode, sizeof(g_sNewGamemode), sGamemode);
			Confogl_UnloadConfig();
			CreateTimer(1.0, Timer_RestartMap);
		}
	}
}

Action Timer_RestartMap(Handle hTimer)
{
	SetConVarString(g_cvGameMode, g_sNewGamemode);
	SetConVarString(g_cvDifficulty, g_sDifficulty);
	RestartMap();

	return Plugin_Stop;
}

void LoadGamemodes(Handle hGamemodes)
{
	char sPath[PLATFORM_MAX_PATH];
	BuildPath(Path_SM, sPath, sizeof(sPath), CONFIG_PATH);

	if (!FileExists(sPath)) {
		SetFailState("Couldn't load %s", sPath);
	}

 	if (!FileToKeyValues(hGamemodes, sPath)) {
		SetFailState("Failed to parse keyvalues for %s", sPath);
	}
}

void FillGamemodeConfig(Handle hGamemodes, Handle hGamemodeConfig)
{
	if (KvGotoFirstSubKey(hGamemodes, false))
	{
		char sKey[32], sValue[64];

		do
		{
			KvGetSectionName(hGamemodes, sKey, sizeof(sKey));
			KvGetString(hGamemodes, "exec", sValue, sizeof(sValue));

			SetTrieString(hGamemodeConfig, sKey, sValue);
		} while (KvGotoNextKey(hGamemodes, false));
	}
}

public void OnAllPluginsLoaded()
{
	if (g_bInit) {
		return;
	}

	g_bInit = true;
	g_bLoopFixed = false;
	g_bChangeLevelAvailable = LibraryExists(LIB_CHANGELEVEL);

	if (!Confogl_IsConfigLoaded() && IsEmptyServer())
	{
		char sConfig[64];

		if (GetTrieString(g_hGamemodeConfig, "default", sConfig, sizeof(sConfig))) {
			Confogl_LoadConfig(sConfig);
		}
	}
}

Action Event_PlayerDisconnect(Event event, const char[] sName, bool bDontBroadcast)
{
	int iClient = GetClientOfUserId(GetEventInt(event, "userid"));

	if (!iClient
	|| (IsClientConnected(iClient) && !IsClientInGame(iClient))
	|| IsFakeClient(iClient)
	|| !IsEmptyServer(iClient)) {
		return Plugin_Continue;
	}

	g_bAllBotGameOldAValue = GetConVarBool(g_cvAllBotGame);
	SetConVarBool(g_cvAllBotGame, true, .notify = false);

	if (Confogl_IsConfigLoaded()) {
		Confogl_UnloadConfig();
	}

	CreateTimer(1.0, Timer_LoadDefaultConfig);

	return Plugin_Continue;
}

Action Timer_LoadDefaultConfig(Handle hTimer)
{
	char sConfig[64];

	if (GetTrieString(g_hGamemodeConfig, "default", sConfig, sizeof(sConfig))) {
		Confogl_LoadConfig(sConfig);
	}

	return Plugin_Stop;
}

public void Confogl_OnLoadConfig()
{
	g_bLoopFixed = false;

	SetConVarBool(g_cvAllBotGame, g_bAllBotGameOldAValue, .notify = false);
}

bool IsEmptyServer(int iIgnoreClient = -1)
{
	for(int iClient = 1; iClient <= MaxClients; iClient ++)
	{
		if (IsClientConnected(iClient) && !IsFakeClient(iClient) && iIgnoreClient != iClient) {
			return false;
		}
	}

	return true;
}

void RestartMap()
{
	char sMap[32]; GetCurrentMap(sMap, sizeof(sMap));

	if (g_bChangeLevelAvailable) {
		L4D2_ChangeLevel(sMap);
	} else {
		ServerCommand("changelevel %s", sMap);
	}
}
