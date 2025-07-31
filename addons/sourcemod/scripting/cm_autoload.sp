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

#define MAXLENGTH_CONFIG_PATH 128

bool
    g_bInit = false,
    g_bOnLoadLoopFix = false
;

char
    g_szNewGamemode[32],
    g_szDifficulty[32]
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
    g_cvDifficulty = FindConVar("z_difficulty");
    g_cvGameMode = FindConVar("mp_gamemode");

    g_hGamemodes = CreateKeyValues("Gamemodes");
    FillGamemodeConfig(g_hGamemodes, g_hGamemodeConfig = CreateTrie());

    HookConVarChange(g_cvDifficulty, CvChange_Difficulty);
    HookConVarChange(g_cvGameMode, CvChange_GameMode);

    g_bInit = false;
    g_bOnLoadLoopFix = false;
}


void CvChange_Difficulty(ConVar convar, const char[] szOldDifficulty, const char[] szDifficulty) {
    strcopy(g_szDifficulty, sizeof g_szDifficulty, szDifficulty);
}

void CvChange_GameMode(ConVar convar, const char[] szOldGamemode, const char[] szGamemode)
{
    if (!g_bOnLoadLoopFix && ConfigManager_IsConfigLoaded() && IsEmptyServer())
    {
        g_bOnLoadLoopFix = true;

        char szGamemodePath[MAXLENGTH_CONFIG_PATH];
        bool bPreloadByGamemode = GetTrieString(g_hGamemodeConfig, szGamemode, szGamemodePath, sizeof szGamemodePath);

        char szCurrentConfigPath[MAXLENGTH_CONFIG_PATH];
        ConfigManager_GetConfigPath(szCurrentConfigPath, sizeof szCurrentConfigPath);

        if (!bPreloadByGamemode || !StrEqual(szGamemodePath, szCurrentConfigPath))
        {
            strcopy(g_szNewGamemode, sizeof g_szNewGamemode, szGamemode);

            ConfigManager_UnloadConfig();
            CreateTimer(1.0, Timer_SetGamemodeAndDifficulty, .flags = TIMER_FLAG_NO_MAPCHANGE);
        }
    }
}

Action Timer_SetGamemodeAndDifficulty(Handle hTimer)
{
    SetConVarString(g_cvGameMode, g_szNewGamemode, .notify = false);
    SetConVarString(g_cvDifficulty, g_szDifficulty, .notify = false);

    return Plugin_Stop;
}

void FillGamemodeConfig(Handle hGamemodes, Handle hGamemodeConfig)
{
    char szPath[PLATFORM_MAX_PATH];
    BuildPath(Path_SM, szPath, sizeof szPath, CONFIG_PATH);

    if (!FileExists(szPath)) {
        SetFailState("Couldn't load %s", szPath);
    }

    if (!FileToKeyValues(hGamemodes, szPath)) {
        SetFailState("Failed to parse keyvalues for %s", szPath);
    }

    if (KvGotoFirstSubKey(hGamemodes, false))
    {
        char szKey[32], szValue[MAXLENGTH_CONFIG_PATH];

        do
        {
            KvGetSectionName(hGamemodes, szKey, sizeof szKey);
            KvGetString(hGamemodes, "exec", szValue, sizeof szValue);

            SetTrieString(hGamemodeConfig, szKey, szValue);
        } while (KvGotoNextKey(hGamemodes, false));
    }
}

public void OnAllPluginsLoaded()
{
    if (g_bInit) {
        return;
    }

    g_bInit = true;
    g_bOnLoadLoopFix = false;

    if (!ConfigManager_IsConfigLoaded() && IsEmptyServer())
    {
        char szDefaultPath[MAXLENGTH_CONFIG_PATH];

        if (GetTrieString(g_hGamemodeConfig, "default", szDefaultPath, sizeof szDefaultPath)) {
            ConfigManager_LoadConfig(szDefaultPath);
        }
    }
}

public void ConfigManager_OnLoadConfig() {
    g_bOnLoadLoopFix = false;
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
