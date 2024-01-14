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

    HookConVarChange((g_cvDifficulty = FindConVar("z_difficulty")), CvChange_Difficulty);
    HookConVarChange((g_cvGameMode = FindConVar("mp_gamemode")), CvChange_GameMode);

    g_bInit = false;
    g_bLoopFixed = false;
}


void CvChange_Difficulty(ConVar convar, const char[] sOldDifficulty, const char[] sDifficulty) {
    strcopy(g_sDifficulty, sizeof(g_sDifficulty), sDifficulty);
}

void CvChange_GameMode(ConVar convar, const char[] sOldGamemode, const char[] szGamemode)
{
    if (ConfigManager_IsConfigLoaded() && !g_bLoopFixed && IsEmptyServer())
    {
        g_bLoopFixed = true;

        char szGamemodeConfig[64];
        bool bNeedConfig = GetTrieString(g_hGamemodeConfig, szGamemode, szGamemodeConfig, sizeof(szGamemodeConfig));

        char szCurrentConfig[64]; ConfigManager_GetConfigName(szCurrentConfig, sizeof(szCurrentConfig));

        if (!bNeedConfig || !StrEqual(szGamemodeConfig, szCurrentConfig))
        {
            strcopy(g_sNewGamemode, sizeof(g_sNewGamemode), szGamemode);
            
            ConfigManager_UnloadConfig();
            CreateTimer(1.0, Timer_SetGamemodeAndDifficulty, .flags = TIMER_FLAG_NO_MAPCHANGE);
        }
    }
}

Action Timer_SetGamemodeAndDifficulty(Handle hTimer)
{
    SetConVarString(g_cvGameMode, g_sNewGamemode, .notify = false);
    SetConVarString(g_cvDifficulty, g_sDifficulty, .notify = false);

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
        char szNeedConfig[64];

        if (GetTrieString(g_hGamemodeConfig, "default", szNeedConfig, sizeof(szNeedConfig))) {
            ConfigManager_LoadConfig(szNeedConfig);
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
