#pragma semicolon               1
#pragma newdecls                required

#include <sourcemod>
#include <config_manager>


public Plugin myinfo = {
    name =        "ConfoglMatchAutoload",
    author =      "TouchMe",
    description = "Automatic loading of config",
    version =     "build_0002",
    url =         "https://github.com/TouchMe-Inc/l4d2_config_manager"
}


#define CONFIG_PATH        "configs/cm_autoload.txt"

#define MAXLENGTH_CONFIG_PATH 128


ConVar
    g_cvAutoload = null,
    g_cvGameMode = null
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
    g_cvGameMode = FindConVar("mp_gamemode");
    HookConVarChange(g_cvGameMode, CvChange_GameMode);

    g_cvAutoload = CreateConVar("sm_cm_autoload", "");
}

public void OnAllPluginsLoaded()
{
    if (!ConfigManager_IsConfigLoaded() && IsEmptyServer())
    {
        char szAutoload[MAXLENGTH_CONFIG_PATH];
        g_cvAutoload.GetString(szAutoload, sizeof szAutoload);

        if (szAutoload[0] != '\0') {
            ConfigManager_LoadConfig(szAutoload);
        }
    }
}

void CvChange_GameMode(ConVar convar, const char[] szOldGamemode, const char[] szGamemode)
{
    if (ConfigManager_IsConfigLoaded() && IsEmptyServer()) {
        ConfigManager_UnloadConfig();
    }
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
