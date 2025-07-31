#pragma semicolon               1
#pragma newdecls                required

#include <sourcemod>

#undef REQUIRE_PLUGIN
#include <l4d2_changelevel>
#define REQUIRE_PLUGIN


public Plugin myinfo =
{
    name =        "ConfigManager",
    author =      "ConfoglTeam, TouchMe",
    description = "The plugin allows you to run configs located in the \"cfg/config_manager\" folder",
    version =     "build_0002",
    url =         "https://github.com/TouchMe-Inc/l4d2_config_manager"
}


#define PATH_TO_CFG_RELATIVE    "../../cfg/"
#define CONFIG_MANAGER_DIR      "config_manager"

/*
 * Libs.
 */
#define LIB_CHANGELEVEL         "l4d2_changelevel"

/*
 * String limit.
 */
#define MAXLENGTH_MAP_NAME      32
#define MAXLENGTH_CONFIG_PATH         128
#define MAXLENGTH_CVAR_NAME     64
#define MAXLENGTH_CVAR_VALUE    128
#define MAXLENGTH_PLUGIN_NAME   128


StringMap
    g_smPluginWhiteList = null,
    g_smUpdatedConVars = null
;

Handle
    g_hFwdOnLoadConfig = null,
    g_hFwdOnUnloadConfig = null
;

char PATH_TO_CFG_ABSOLUTE[PLATFORM_MAX_PATH];

char g_szConfigPath[MAXLENGTH_CONFIG_PATH];

bool g_bConVarHookIgnore = false;

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
    if (GetEngineVersion() != Engine_Left4Dead2)
    {
        strcopy(error, err_max, "Plugin only supports Left 4 Dead 2.");
        return APLRes_SilentFailure;
    }

    g_hFwdOnLoadConfig   = CreateGlobalForward("ConfigManager_OnLoadConfig", ET_Ignore);
    g_hFwdOnUnloadConfig = CreateGlobalForward("ConfigManager_OnUnloadConfig", ET_Ignore);

    CreateNative("ConfigManager_BuildConfigPath", Native_BuildConfigPath);
    CreateNative("ConfigManager_IsConfigLoaded", Native_IsConfigLoaded);
    CreateNative("ConfigManager_GetConfigPath", Native_GetConfigPath);
    CreateNative("ConfigManager_LoadConfig", Native_LoadConfig);
    CreateNative("ConfigManager_UnloadConfig", Native_UnloadConfig);

    RegPluginLibrary("config_manager");

    return APLRes_Success;
}

int Native_BuildConfigPath(Handle plugin, int numParams)
{
    char szConfigName[MAXLENGTH_CONFIG_PATH];
    GetNativeString(2, szConfigName, sizeof(szConfigName));

    char szConfigPath[PLATFORM_MAX_PATH];
    BuildConfigPath(szConfigPath, szConfigName);

    SetNativeString(1, szConfigPath, sizeof(szConfigPath));

    return 1;
}

int Native_IsConfigLoaded(Handle plugin, int numParams) {
    return IsConfigLoaded();
}

int Native_GetConfigPath(Handle plugin, int numParams)
{
    SetNativeString(1, g_szConfigPath, GetNativeCell(2), true);

    return 1;
}

int Native_LoadConfig(Handle plugin, int numParams)
{
    char szConfigName[MAXLENGTH_CONFIG_PATH];

    GetNativeString(1, szConfigName, sizeof(szConfigName));

    if (IsConfigLoaded())
    {
        if (UnloadConfig())
        {
            DataPack hPack;
            CreateDataTimer(1.0, Timer_LoadConfig, hPack, .flags = TIMER_FLAG_NO_MAPCHANGE);
            hPack.WriteString(szConfigName);
        }
    }

    else if (LoadConfig(szConfigName)) {
        CreateTimer(1.0, Timer_ApplyAction, true, .flags = TIMER_FLAG_NO_MAPCHANGE);
    }

    return 1;
}

int Native_UnloadConfig(Handle plugin, int numParams)
{
    if (!IsConfigLoaded()) {
        return 1;
    }

    if (UnloadConfig()) {
        CreateTimer(1.0, Timer_ApplyAction, false, .flags = TIMER_FLAG_NO_MAPCHANGE);
    }

    return 1;
}

public void OnPluginStart()
{
    BuildPath(Path_SM, PATH_TO_CFG_ABSOLUTE, sizeof(PATH_TO_CFG_ABSOLUTE), PATH_TO_CFG_RELATIVE);

    g_smPluginWhiteList = new StringMap();
    g_smUpdatedConVars = new StringMap();

    GetPluginWhitelist(g_smPluginWhiteList);

    RegServerCmd("config_manager_addcvar", Cmd_AddCvar, "config_manager_addcvar <cvar> <value>");
    RegServerCmd("config_manager_deletecvar", Cmd_DeleteCvar, "config_manager_deletecvar <cvar>");
    RegServerCmd("config_manager_resetcvars", Cmd_ResetCvars);
}

Action Cmd_AddCvar(int iArgs)
{
    if (iArgs != 2)
    {
        char sCmdArgs[128]; GetCmdArgString(sCmdArgs, sizeof(sCmdArgs));
        LogError("Invalid command \"%s\". Usage: config_manager_addcvar <cvar> <value>", sCmdArgs);
        return Plugin_Handled;
    }

    char szConVarName[MAXLENGTH_CVAR_NAME]; GetCmdArg(1, szConVarName, sizeof(szConVarName));
    char szConVarValue[MAXLENGTH_CVAR_VALUE]; GetCmdArg(2, szConVarValue, sizeof(szConVarValue));

    if (strlen(szConVarName) >= MAXLENGTH_CVAR_NAME)
    {
        LogError("ConVar name \"%s\" is longer than max length \"%d\"", szConVarName, MAXLENGTH_CVAR_NAME);
        return Plugin_Handled;
    }

    if (strlen(szConVarValue) >= MAXLENGTH_CVAR_VALUE)
    {
        LogError("ConVar \"%s\" has value \"%s\" is longer than max length \"%d\"", szConVarName, szConVarValue, MAXLENGTH_CVAR_VALUE);
        return Plugin_Handled;
    }

    if (g_smUpdatedConVars.ContainsKey(szConVarName))
    {
        LogError("ConVar \"%s\" already added", szConVarName);
        return Plugin_Handled;
    }

    ConVar convar = FindConVar(szConVarName);
    if (convar == null)
    {
        LogError("Could not find Convar \"%s\"", szConVarName);
        return Plugin_Handled;
    }

    char szConVarOldValue[MAXLENGTH_CVAR_VALUE];
    GetConVarString(convar, szConVarOldValue, sizeof(szConVarOldValue));

    SetConVarStringSilence(convar, szConVarValue);
    HookConVarChange(convar, OnConVarChanged);

    g_smUpdatedConVars.SetString(szConVarName, szConVarOldValue);

    return Plugin_Handled;
}

Action Cmd_DeleteCvar(int iArgs)
{
    if (iArgs != 1)
    {
        char sCmdArgs[128]; GetCmdArgString(sCmdArgs, sizeof(sCmdArgs));
        LogError("Invalid command \"%s\". Usage: config_manager_deletecvar <cvar>", sCmdArgs);
        return Plugin_Handled;
    }

    char szConVarName[MAXLENGTH_CVAR_NAME]; GetCmdArg(1, szConVarName, sizeof(szConVarName));

    if (!g_smUpdatedConVars.ContainsKey(szConVarName))
    {
        LogError("ConVar \"%s\" not found", szConVarName);
        return Plugin_Handled;
    }

    ConVar convar = FindConVar(szConVarName);
    if (convar == null)
    {
        LogError("Could not find Convar \"%s\"", szConVarName);
        return Plugin_Handled;
    }

    char szConVarOldValue[MAXLENGTH_CVAR_VALUE];
    g_smUpdatedConVars.GetString(szConVarName, szConVarOldValue, sizeof(szConVarOldValue));

    UnhookConVarChange(convar, OnConVarChanged);
    SetConVarStringSilence(convar, szConVarOldValue);

    g_smUpdatedConVars.Remove(szConVarName);

    return Plugin_Handled;
}

Action Cmd_ResetCvars(int iArgs)
{
    ResetConVars();

    return Plugin_Handled;
}

public void OnConVarChanged(ConVar convar, const char[] sOldValue, const char[] sNewValue)
{
    if (g_bConVarHookIgnore) {
        return;
    }

    g_bConVarHookIgnore = true;

    SetConVarStringSilence(convar, sOldValue);

    g_bConVarHookIgnore = false;
}

void BuildConfigPath(char szConfigPath[PLATFORM_MAX_PATH], const char[] szConfigName) {
    BuildPath(Path_SM, szConfigPath, sizeof(szConfigPath), "%s%s/%s", PATH_TO_CFG_RELATIVE, CONFIG_MANAGER_DIR, szConfigName);
}

bool IsConfigLoaded() {
    return (g_szConfigPath[0] != '\0');
}

bool LoadConfig(const char[] szConfigName)
{
    char szPathToConfigLoadFile[PLATFORM_MAX_PATH];
    BuildConfigPath(szPathToConfigLoadFile, szConfigName);
    Format(szPathToConfigLoadFile, sizeof(szPathToConfigLoadFile), "%s/config_load.cfg", szPathToConfigLoadFile);

    if (!FileExists(szPathToConfigLoadFile))
    {
        LogError("Failed to load configuration \"%s\": File \"%s\" not found", szConfigName, szPathToConfigLoadFile);
        return false;
    }

    ServerCommand("sm plugins load_unlock");
    ServerCommand("exec %s", szPathToConfigLoadFile[strlen(PATH_TO_CFG_ABSOLUTE)]);
    ServerExecute();

    strcopy(g_szConfigPath,  sizeof(g_szConfigPath), szConfigName);

    return true;
}

bool UnloadConfig()
{
    char szPathToConfigUnloadFile[PLATFORM_MAX_PATH];
    BuildConfigPath(szPathToConfigUnloadFile, g_szConfigPath);
    Format(szPathToConfigUnloadFile, sizeof(szPathToConfigUnloadFile), "%s/config_unload.cfg", szPathToConfigUnloadFile);

    if (!FileExists(szPathToConfigUnloadFile))
    {
        LogError("Failed to unload configuration \"%s\": File \"%s\" not found", g_szConfigPath, szPathToConfigUnloadFile);
        return false;
    }

    g_szConfigPath[0] = '\0';

    ServerCommand("sm plugins load_unlock");
    ServerCommand("exec %s", szPathToConfigUnloadFile[strlen(PATH_TO_CFG_ABSOLUTE)]);
    ServerExecute();

    ResetConVars();
    UnloadPlugins(g_smPluginWhiteList);

    return true;
}

Action Timer_LoadConfig(Handle hTimer, Handle hPack)
{
    char szConfigName[MAXLENGTH_CONFIG_PATH];

    ResetPack(hPack);
    ReadPackString(hPack, szConfigName, sizeof(szConfigName));

    LoadConfig(szConfigName);

    CreateTimer(1.0, Timer_ApplyAction, true, .flags = TIMER_FLAG_NO_MAPCHANGE);

    return Plugin_Stop;
}

Action Timer_ApplyAction(Handle hTimer, bool bIsLoad)
{
    ServerCommand("sm plugins load_lock");
    ServerExecute();

    ExecForwardWithoutParams(bIsLoad ? g_hFwdOnLoadConfig : g_hFwdOnUnloadConfig);

    /**
     * Restart so that all modules and plugins work correctly.
     */
    RestartMap();

    return Plugin_Stop;
}

void ResetConVars()
{
    StringMapSnapshot hSnapshot = g_smUpdatedConVars.Snapshot();

    char szConVarName[MAXLENGTH_CVAR_NAME];
    char szConVarOldValue[MAXLENGTH_CVAR_VALUE];
    for (int iIndex = hSnapshot.Length - 1; iIndex >= 0; iIndex--)
    {
        hSnapshot.GetKey(iIndex, szConVarName, sizeof(szConVarName));

        ConVar convar = FindConVar(szConVarName);
        if (convar != null)
        {
            g_smUpdatedConVars.GetString(szConVarName, szConVarOldValue, sizeof(szConVarOldValue));
            UnhookConVarChange(convar, OnConVarChanged);
            SetConVarStringSilence(convar, szConVarOldValue);
        }

        g_smUpdatedConVars.Remove(szConVarName);
    }

    delete hSnapshot;
}

void GetPluginWhitelist(StringMap smPluginWhiteList)
{
    char sPath[PLATFORM_MAX_PATH];
    BuildPath(Path_SM, sPath, sizeof(sPath), "plugins");

    DirectoryListing dir = OpenDirectory(sPath);

    if (dir == null) {
        return;
    }

    char szPluginName[MAXLENGTH_PLUGIN_NAME];
    FileType type;
    while (ReadDirEntry(dir, szPluginName, sizeof(szPluginName), type))
    {
        if (type != FileType_File) {
            continue;
        }

        smPluginWhiteList.SetValue(szPluginName, 1);
    }

    delete dir;
}

void UnloadPlugins(StringMap smPluginWhiteList)
{
    Handle it = GetPluginIterator();

    Handle hSelf = GetMyHandle();

    char sPluginFilename[128];

    while (MorePlugins(it))
    {
        Handle hPlugin = ReadPlugin(it);

        if (hSelf == hPlugin) {
            continue;
        }

        GetPluginFilename(hPlugin, sPluginFilename, sizeof(sPluginFilename));

        if (!smPluginWhiteList.ContainsKey(sPluginFilename))
        {
            ServerCommand("sm plugins unload %s", sPluginFilename);
            ServerExecute();
        }
    }

    CloseHandle(it);
}

void ExecForwardWithoutParams(Handle hForward)
{
    Call_StartForward(hForward);
    Call_Finish();
}

void SetConVarStringSilence(ConVar convar, const char[] sValue)
{
    int iFlags = GetConVarFlags(convar);
    SetConVarFlags(convar, iFlags & ~FCVAR_NOTIFY);
    SetConVarString(convar, sValue);
    SetConVarFlags(convar, iFlags);
}

void RestartMap()
{
    char szCurrentMap[MAXLENGTH_MAP_NAME]; GetCurrentMap(szCurrentMap, sizeof(szCurrentMap));

    if (g_bChangeLevelAvailable) {
        L4D2_ChangeLevel(szCurrentMap);
    } else {
        ServerCommand("changelevel %s", szCurrentMap);
    }
}
