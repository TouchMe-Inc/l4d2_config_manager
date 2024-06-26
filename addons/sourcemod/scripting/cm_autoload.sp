#pragma semicolon               1
#pragma newdecls                required

#include <sourcemod>
#include <config_manager>


public Plugin myinfo = {
	name =        "ConfoglMatchAutoload",
	author =      "TouchMe",
	description = "Automatic loading of config (for each mode)",
	version =     "build_0001",
	url =         "https://github.com/TouchMe-Inc/l4d2_config_manager"
}


#define CONFIG_PATH        "configs/cm_autoload.txt"


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
	g_cvDifficulty = null
;


/**
 * Called before OnPluginStart.
 */
public APLRes AskPluginLoad2(Handle myself, bool bLate, char[] sErr, int iErrLen)
{
	if (GetEngineVersion() != Engine_Left4Dead2)
	{
		strcopy(sErr, iErrLen, "Plugin only supports Left 4 Dead 2");
		return APLRes_SilentFailure;
	}

	return APLRes_Success;
}

public void OnPluginStart()
{
	LoadGamemodes(g_hGamemodes = CreateKeyValues("Gamemodes"));
	FillGamemodeConfig(g_hGamemodes, g_hGamemodeConfig = CreateTrie());

	HookConVarChange((g_cvDifficulty = FindConVar("z_difficulty")), ConVarChange_Difficulty);
	HookConVarChange((g_cvGameMode = FindConVar("mp_gamemode")), OnConVarChange_GameMode);

	g_bInit = false;
	g_bLoopFixed = false;
}


public void ConVarChange_Difficulty(ConVar convar, const char[] sOldGamemode, const char[] sGamemode)
{
	strcopy(g_sDifficulty, sizeof(g_sDifficulty), sGamemode);
}

public void OnConVarChange_GameMode(ConVar convar, const char[] sOldGamemode, const char[] sGamemode)
{
	if (ConfigManager_IsConfigLoaded() && !g_bLoopFixed)
	{
		g_bLoopFixed = true;

		char sConfig[64]; ConfigManager_GetConfigName(sConfig, sizeof(sConfig));

		char sGamemodeConfig[64];

		bool bNeedConfig = GetTrieString(g_hGamemodeConfig, sGamemode, sGamemodeConfig, sizeof(sGamemodeConfig));

		if (!bNeedConfig || !StrEqual(sGamemodeConfig, sConfig))
		{
			strcopy(g_sNewGamemode, sizeof(g_sNewGamemode), sGamemode);
			ConfigManager_UnloadConfig();
			CreateTimer(1.0, Timer_SetGamemodeAndDifficulty);
		}
	}
}

Action Timer_SetGamemodeAndDifficulty(Handle hTimer)
{
	SetConVarString(g_cvGameMode, g_sNewGamemode);
	SetConVarString(g_cvDifficulty, g_sDifficulty);

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

	if (!ConfigManager_IsConfigLoaded() && IsEmptyServer())
	{
		char sConfig[64];

		if (GetTrieString(g_hGamemodeConfig, "default", sConfig, sizeof(sConfig))) {
			ConfigManager_LoadConfig(sConfig);
		}
	}
}

public void ConfigManager_OnLoadConfig() {
	g_bLoopFixed = false;
}

bool IsEmptyServer()
{
	for (int iClient = 1; iClient <= MaxClients; iClient ++)
	{
		if (IsClientConnected(iClient) && !IsFakeClient(iClient)) {
			return false;
		}
	}

	return true;
}
