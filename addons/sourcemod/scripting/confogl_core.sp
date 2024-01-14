#include <sourcemod>

#undef REQUIRE_PLUGIN
#include <l4d2_changelevel>
#define REQUIRE_PLUGIN


public Plugin myinfo =
{
	name = "ConfoglCore",
	author = "TouchMe",
	description = "N/a",
	version = "build0000",
	url = "https://github.com/TouchMe-Inc/l4d2_confogl"
}


#define LIB_CHANGELEVEL         "l4d2_changelevel"

#define CONFIG_NAME_MAX         64

#define CVAR_NAME_MAX           64
#define CVAR_VALUE_MAX          128

#define PLUGIN_NAME_MAX         128


enum struct ConVarInfo
{
	ConVar convar;
	char old_value[CVAR_VALUE_MAX];
	char new_value[CVAR_VALUE_MAX];
}

Handle
	g_hPluginWhiteList = null,
	g_hConVarList = null
;

Handle
	g_hFwdOnLoadConfig = null,
	g_hFwdOnUnloadConfig = null
;

char g_sConfoglPath[PLATFORM_MAX_PATH];

char g_cDirSeparator;

char g_sConfigName[CONFIG_NAME_MAX];

bool g_bChangeLevelAvailable = false;


/**
  * Global event. Called when all plugins loaded.
  */
public void OnAllPluginsLoaded() {
	g_bChangeLevelAvailable = LibraryExists(LIB_CHANGELEVEL);
}

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
  */
public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
	EngineVersion engine = GetEngineVersion();

	if (engine != Engine_Left4Dead2)
	{
		strcopy(error, err_max, "Plugin only supports Left 4 Dead 2.");
		return APLRes_SilentFailure;
	}

	g_hFwdOnLoadConfig   = CreateGlobalForward("Confogl_OnLoadConfig", ET_Ignore);
	g_hFwdOnUnloadConfig = CreateGlobalForward("Confogl_OnUnloadConfig", ET_Ignore);

	CreateNative("Confogl_IsConfigLoaded", Native_IsConfigLoaded);
	CreateNative("Confogl_GetConfigName", Native_GetConfigName);
	CreateNative("Confogl_LoadConfig", Native_LoadConfig);
	CreateNative("Confogl_UnloadConfig", Native_UnloadConfig);

	RegPluginLibrary("confogl_core");

	return APLRes_Success;
}

int Native_IsConfigLoaded(Handle plugin, int numParams) {
	return IsConfigLoaded();
}

int Native_GetConfigName(Handle plugin, int numParams)
{
	SetNativeString(1, g_sConfigName, GetNativeCell(2), true);

	return 1;
}

int Native_LoadConfig(Handle plugin, int numParams)
{
	char sConfigName[CONFIG_NAME_MAX];

	GetNativeString(1, sConfigName, sizeof(sConfigName));

	return LoadConfig(sConfigName);
}

int Native_UnloadConfig(Handle plugin, int numParams)
{
	return UnloadConfig();
}

public void OnPluginStart()
{
	LoadPluginWhitelist(g_hPluginWhiteList = CreateArray(ByteCountToCells(PLUGIN_NAME_MAX)));

	BuildPath(Path_SM, g_sConfoglPath, sizeof(g_sConfoglPath), "../../cfg/");
	g_cDirSeparator = g_sConfoglPath[(strlen(g_sConfoglPath) - 1)];

	g_hConVarList = CreateTrie();

	RegServerCmd("confogl_addcvar", Cmd_AddCvar, "confogl_addcvar <cvar> <value>");
	RegServerCmd("confogl_deletecvar", Cmd_DeleteCvar, "confogl_deletecvar <cvar>");
	RegServerCmd("confogl_resetcvars", Cmd_ResetCvars);
}

Action Cmd_AddCvar(int iArgs)
{
	if (iArgs != 2)
	{
		char sCmdArgs[128]; GetCmdArgString(sCmdArgs, sizeof(sCmdArgs));
		LogError("Invalid command \"%s\". Usage: confogl_addcvar <cvar> <value>", sCmdArgs);
		return Plugin_Handled;
	}

	char sConVarName[256]; GetCmdArg(1, sConVarName, sizeof(sConVarName));
	char sConVarValue[512]; GetCmdArg(2, sConVarValue, sizeof(sConVarValue));

	if (strlen(sConVarName) >= CVAR_NAME_MAX)
	{
		LogError("ConVar name \"%s\" is longer than max length \"%d\"", sConVarName, CVAR_NAME_MAX);
		return Plugin_Handled;
	}

	if (strlen(sConVarValue) >= CVAR_VALUE_MAX)
	{
		LogError("ConVar \"%s\" has value \"%s\" is longer than max length \"%d\"", sConVarName, sConVarValue, CVAR_VALUE_MAX);
		return Plugin_Handled;
	}

	ConVar convar = FindConVar(sConVarName);

	if (convar == null)
	{
		LogError("Could not find Convar \"%s\" for \"%s\"", sConVarName, g_sConfigName);
		return Plugin_Handled;
	}

	ConVarInfo entry;

	if (GetTrieArray(g_hConVarList, sConVarName, entry, sizeof(entry)))
	{
		LogError("ConVar \"%s\" already added for \"%s\"", sConVarName, g_sConfigName);
		return Plugin_Handled;
	}

	entry.convar = convar;
	GetConVarString(entry.convar, entry.old_value, sizeof(entry.old_value));
	strcopy(entry.new_value,  sizeof(entry.new_value), sConVarValue);

	SetConVarStringSilence(entry.convar, sConVarValue);
	HookConVarChange(entry.convar, OnConVarChanged);

	SetTrieArray(g_hConVarList, sConVarName, entry, sizeof(entry));

	return Plugin_Handled;
}

Action Cmd_DeleteCvar(int iArgs)
{
	if (iArgs != 1)
	{
		char sCmdArgs[128]; GetCmdArgString(sCmdArgs, sizeof(sCmdArgs));
		LogError("Invalid command \"%s\". Usage: confogl_deletecvar <cvar>", sCmdArgs);
		return Plugin_Handled;
	}

	char sConVarName[CVAR_NAME_MAX]; GetCmdArg(1, sConVarName, sizeof(sConVarName));

	ConVarInfo entry;

	if (!GetTrieArray(g_hConVarList, sConVarName, entry, sizeof(entry)))
	{
		LogError("ConVar \"%s\" not found", sConVarName);
		return Plugin_Handled;
	}

	UnhookConVarChange(entry.convar, OnConVarChanged);
	SetConVarStringSilence(entry.convar, entry.old_value);

	RemoveFromTrie(g_hConVarList, sConVarName);

	return Plugin_Handled;
}

Action Cmd_ResetCvars(int iArgs)
{
	ResetConVars();

	return Plugin_Handled;
}

public void OnConVarChanged(ConVar convar, const char[] sOldValue, const char[] sNewValue)
{
	char sConVarName[CVAR_NAME_MAX]; GetConVarName(convar, sConVarName, sizeof(sConVarName));

	UnhookConVarChange(convar, OnConVarChanged);
	SetConVarStringSilence(convar, sOldValue);
	HookConVarChange(convar, OnConVarChanged);
}

bool IsConfigLoaded() {
	return (g_sConfigName[0] != '\0');
}

bool LoadConfig(const char[] sConfigName)
{
	if (IsConfigLoaded())
	{
		LogError("Failed to load configuration \"%s\": Configuration already loaded \"%s\"", sConfigName, g_sConfigName);
		return false;
	}

	char sPath[PLATFORM_MAX_PATH];
	FormatEx(sPath, sizeof(sPath), "%sconfogl%c%s", g_sConfoglPath, g_cDirSeparator, sConfigName);

	if (!DirExists(sPath))
	{
		LogError("Failed to load configuration \"%s\": Dir \"%s\" not found", sConfigName, sPath);
		return false;
	}

	char sConfigPath[PLATFORM_MAX_PATH]; FormatEx(sConfigPath, sizeof(sConfigPath), "%s%cconfig_load.cfg", sPath, g_cDirSeparator);

	if (!FileExists(sConfigPath))
	{
		LogError("Failed to load configuration \"%s\": File \"%s\" not found", sConfigName, sConfigPath);
		return false;
	}

	ServerCommand("sm plugins load_unlock");

	UnloadPlugins();
	ResetConVars();

	ServerCommand("exec %s", sConfigPath[strlen(g_sConfoglPath)]);

	strcopy(g_sConfigName,  sizeof(g_sConfigName), sConfigName);

	CreateTimer(3.0, Timer_ApplyConfig, .flags = TIMER_FLAG_NO_MAPCHANGE);

	return true;
}

Action Timer_ApplyConfig(Handle hTimer)
{
	ServerCommand("sm plugins load_lock");

	/**
	 * Restart so that all modules and plugins work correctly.
	 */
	RestartMap();

	ExecForwardWithoutParams(g_hFwdOnLoadConfig);

	return Plugin_Stop;
}

bool UnloadConfig()
{
	if (!IsConfigLoaded())
	{
		LogError("Failed to unload configuration: Configuration not loaded");
		return false;
	}

	char sPath[PLATFORM_MAX_PATH]; FormatEx(sPath, sizeof(sPath), "%sconfogl%c%s", g_sConfoglPath, g_cDirSeparator, g_sConfigName);

	if (!DirExists(sPath))
	{
		LogError("Failed to unload configuration \"%s\": Dir \"%s\" not found", g_sConfigName, sPath);
		return false;
	}

	char sConfigPath[PLATFORM_MAX_PATH]; FormatEx(sConfigPath, sizeof(sConfigPath), "%s%cconfig_unload.cfg", sPath, g_cDirSeparator);

	if (!FileExists(sConfigPath))
	{
		LogError("Failed to unload configuration \"%s\": File \"%s\" not found", g_sConfigName, sPath);
		return false;
	}

	ServerCommand("sm plugins load_unlock");

	ServerCommand("exec %s", sConfigPath[strlen(g_sConfoglPath)]);

	UnloadPlugins();
	ResetConVars();

	g_sConfigName[0] = '\0';

	ExecForwardWithoutParams(g_hFwdOnUnloadConfig);

	return true;
}

void ResetConVars()
{
	Handle hSnapshot = CreateTrieSnapshot(g_hConVarList);

	int iSize = TrieSnapshotLength(hSnapshot);

	char sConVarName[CVAR_NAME_MAX];
	ConVarInfo entry;

	/*
	 * First you need to remove all the hooks.
	 */
	for (int iIndex = 0; iIndex < iSize; iIndex ++)
	{
		GetTrieSnapshotKey(hSnapshot, iIndex, sConVarName, sizeof(sConVarName));
		GetTrieArray(g_hConVarList, sConVarName, entry, sizeof(entry));

		UnhookConVarChange(entry.convar, OnConVarChanged);
	}

	/*
	 * Set the old value of cvar. 
	 * If you run it in one loop, the hooks will not have time to unload.
	 */
	for (int iIndex = 0; iIndex < iSize; iIndex ++)
	{
		GetTrieSnapshotKey(hSnapshot, iIndex, sConVarName, sizeof(sConVarName));
		GetTrieArray(g_hConVarList, sConVarName, entry, sizeof(entry));

		SetConVarStringSilence(entry.convar, entry.old_value);

		RemoveFromTrie(g_hConVarList, sConVarName);
	}

	CloseHandle(hSnapshot);
}

public void LoadPluginWhitelist(Handle hPluginWhiteList)
{
	char sPath[PLATFORM_MAX_PATH];
	BuildPath(Path_SM, sPath, sizeof(sPath), "plugins");

	Handle dir = OpenDirectory(sPath);

	if (dir != INVALID_HANDLE)
	{
		char sFileName[128];

		FileType type;
		while (ReadDirEntry(dir, sFileName, sizeof(sFileName), type))
		{
			if (type != FileType_File) {
				continue;
			}

			PushArrayString(hPluginWhiteList, sFileName);
		}

		CloseHandle(dir);
	}
}

bool IsPluginInWhitelist(const char[] sPluginFilename)
{
	char sFileName[PLUGIN_NAME_MAX];
	int iArraySize = GetArraySize(g_hPluginWhiteList);

	for (int iPlugin = 0; iPlugin < iArraySize; iPlugin ++)
	{
		GetArrayString(g_hPluginWhiteList, iPlugin, sFileName, sizeof(sFileName));

		if (StrEqual(sPluginFilename, sFileName, false)) {
			return true;
		}
	}

	return false;
}

void UnloadPlugins()
{
	Handle it = GetPluginIterator();

	Handle hThis = GetMyHandle();

	char sPluginFilename[PLUGIN_NAME_MAX];

	while (MorePlugins(it))
	{
		Handle hPlugin = ReadPlugin(it);

		if (hThis == hPlugin) {
			continue;
		}

		GetPluginFilename(hPlugin, sPluginFilename, sizeof(sPluginFilename));
		
		if (!IsPluginInWhitelist(sPluginFilename)) {
			ServerCommand("sm plugins unload %s", sPluginFilename);
		}
	}

	CloseHandle(it);
}

void ExecForwardWithoutParams(Handle hForward)
{
	Call_StartForward(hForward);
	Call_Finish();
}

void SetConVarStringSilence(Handle hConVar, const char[] sValue)
{
	int iFlags = GetConVarFlags(hConVar);
	SetConVarFlags(hConVar, iFlags & ~FCVAR_NOTIFY);
	SetConVarString(hConVar, sValue, .notify = false);
	SetConVarFlags(hConVar, iFlags);
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