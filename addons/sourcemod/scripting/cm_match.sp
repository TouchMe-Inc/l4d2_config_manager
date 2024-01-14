#pragma semicolon               1
#pragma newdecls                required

#include <sourcemod>
#include <config_manager>
#include <nativevotes_rework>
#include <colors>


public Plugin myinfo =
{
    name =        "ConfigManagerMatch",
    author =      "TouchMe",
    description = "The plugin allows you to load a config from a file",
    version =     "build_0002",
    url =         "https://github.com/TouchMe-Inc/l4d2_config_manager"
}


#define MAX_CONFIG_NAME_LENGTH         64
#define MAX_CONFIG_TITLE_LENGTH         64

#define PATH_CONFIG_MATCH        "configs/cm_match.txt"

#define TRANSLATIONS            "cm_match.phrases"

#define TEAM_SPECTATE           1

#define VOTE_TIME               15

enum struct Node
{
    char phrases[32];
    ArrayList children;
}

char g_szTargetConfig[MAX_CONFIG_NAME_LENGTH];


ArrayList g_aConfigs = null;
StringMap g_smConfigsByNames = null;

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

    return APLRes_Success;
}

public void OnPluginStart()
{
    g_aConfigs = new ArrayList(sizeof(Node));
    g_smConfigsByNames = new StringMap();

    char szPath[PLATFORM_MAX_PATH];
    BuildPath(Path_SM, szPath, sizeof(szPath), PATH_CONFIG_MATCH);
    LoadConfigs(szPath, g_smConfigsByNames, g_aConfigs);

    // Load translations.
    LoadTranslations(TRANSLATIONS);

    RegConsoleCmd("sm_match", Cmd_Match);
    RegConsoleCmd("sm_rmatch", Cmd_ResetMatch);
}

void LoadConfigs(char[] szPath, StringMap smConfigsByNames, ArrayList aConfigs)
{
    if (!FileExists(szPath)) {
        SetFailState("Couldn't load %s", szPath);
    }

    KeyValues cvConfigs = CreateKeyValues("Configs");

    if (!cvConfigs.ImportFromFile(szPath)) {
        SetFailState("Failed to parse keyvalues for %s", szPath);
    }

    if (cvConfigs.GotoFirstSubKey(false))
    {
        char szCurrentCategory[64], sKey[MAX_CONFIG_NAME_LENGTH], sValue[MAX_CONFIG_TITLE_LENGTH];
        Node node;

        do
        {
            cvConfigs.GetSectionName(szCurrentCategory, sizeof(szCurrentCategory));

            cvConfigs.Rewind();

            if (!cvConfigs.JumpToKey(szCurrentCategory) || !cvConfigs.GotoFirstSubKey(false)) {
                continue;
            }

            strcopy(node.phrases, sizeof(node.phrases), szCurrentCategory);
            node.children = new ArrayList(ByteCountToCells(MAX_CONFIG_NAME_LENGTH));

            do
            {
                cvConfigs.GetSectionName(sKey, sizeof(sKey));
                cvConfigs.GetString("name", sValue, sizeof(sValue));

                smConfigsByNames.SetString(sKey, sValue);
                node.children.PushString(sKey);
            } while (cvConfigs.GotoNextKey(false));

            aConfigs.PushArray(node);

            cvConfigs.GoBack();
        } while (cvConfigs.GotoNextKey(false));
    }

    delete cvConfigs;
}

/**
 * When a player wants to find out whos becoming tank,
 * output to them.
 */
Action Cmd_Match(int iClient, int args)
{
    if (!iClient || IsClientSpectator(iClient)) {
        return Plugin_Continue;
    }

    ShowMainMenu(iClient);

    return Plugin_Handled;
}

/**
 * When a player wants to find out whos becoming tank,
 * output to them.
 */
Action Cmd_ResetMatch(int iClient, int args)
{
    if (!iClient || IsClientSpectator(iClient)) {
        return Plugin_Continue;
    }

    if (!ConfigManager_IsConfigLoaded())
    {
        CPrintToChat(iClient, "%T%T", "TAG", iClient, "CONFIG_NOT_LOADED", iClient);
        return Plugin_Handled;
    }

    RunVote(HandlerVoteMatchEnd, iClient);

    return Plugin_Handled;
}


void ShowMainMenu(int iClient)
{
    Menu menu = CreateMenu(HandlerMainMenu, MenuAction_Select|MenuAction_End);

    if (ConfigManager_IsConfigLoaded())
    {
        char szConfigName[MAX_CONFIG_NAME_LENGTH];
        ConfigManager_GetConfigName(szConfigName, sizeof(szConfigName));

        char szConfigTitle[MAX_CONFIG_TITLE_LENGTH];
        if (!g_smConfigsByNames.GetString(szConfigName, szConfigTitle, sizeof(szConfigTitle))) {
            FormatEx(szConfigTitle, sizeof(szConfigTitle), "%T", "CONFIG_UNDEFINED", iClient);
        }

        menu.SetTitle("%T", "MENU_MAIN_TITLE_EX", iClient, szConfigTitle);
    }

    else {
        menu.SetTitle("%T", "MENU_MAIN_TITLE", iClient);
    }

    Node node;
    char szIdx[4];
    for (int iIdx = 0; iIdx < g_aConfigs.Length; iIdx ++)
    {
        g_aConfigs.GetArray(iIdx, node);

        IntToString(iIdx, szIdx, sizeof(szIdx));

        menu.AddItem(szIdx, node.phrases);
    }

    menu.Display(iClient, -1);
}

/**
 *
 */
int HandlerMainMenu(Menu menu, MenuAction hAction, int iClient, int iItem)
{
    switch(hAction)
    {
        case MenuAction_End: delete menu;

        case MenuAction_Select:
        {
            char szIdx[8];
            menu.GetItem(iItem, szIdx, sizeof(szIdx));

            ShowCategoryMenu(iClient, StringToInt(szIdx));
        }
    }

    return 0;
}

void ShowCategoryMenu(int iClient, int iCategoryIdx)
{
    Menu menu = CreateMenu(HandlerCategoryMenu, MenuAction_Select|MenuAction_End);

    char szConfigName[MAX_CONFIG_NAME_LENGTH];
    char szConfigTitle[MAX_CONFIG_TITLE_LENGTH];

    Node node;
    g_aConfigs.GetArray(iCategoryIdx, node);

    if (ConfigManager_IsConfigLoaded())
    {
        ConfigManager_GetConfigName(szConfigName, sizeof(szConfigName));

        if (!g_smConfigsByNames.GetString(szConfigName, szConfigTitle, sizeof(szConfigTitle))) {
            FormatEx(szConfigTitle, sizeof(szConfigTitle), "%T", "CONFIG_UNDEFINED", iClient);
        }

        menu.SetTitle("%T", "MENU_CATEGORY_TITLE_EX", iClient, szConfigTitle);
    }

    else {
        menu.SetTitle("%T", "MENU_CATEGORY_TITLE", iClient);
    }

    for (int iIdx = 0; iIdx < node.children.Length; iIdx ++)
    {
        node.children.GetString(iIdx, szConfigName, sizeof(szConfigName));

        g_smConfigsByNames.GetString(szConfigName, szConfigTitle, sizeof(szConfigTitle));

        menu.AddItem(szConfigName, szConfigTitle);
    }

    menu.Display(iClient, -1);
}

public int HandlerCategoryMenu(Menu menu, MenuAction hAction, int iClient, int iItem)
{
    switch(hAction)
    {
        case MenuAction_End: delete menu;

        case MenuAction_Select:
        {
            char szTargetConfig[MAX_CONFIG_NAME_LENGTH];
            menu.GetItem(iItem, szTargetConfig, sizeof(szTargetConfig));

            RunVote(HandlerVoteMatchStart, iClient, szTargetConfig);
        }
    }

    return 0;
}

NativeVote RunVote(NativeVotes_Handler hHandler, int iInitiator, char[] szTargetConfig = "")
{
    if (!NativeVotes_IsNewVoteAllowed())
    {
        CPrintToChat(iInitiator, "%T%T", "TAG", iInitiator, "VOTE_COULDOWN", iInitiator, NativeVotes_CheckVoteDelay());
        return null;
    }

    strcopy(g_szTargetConfig, sizeof(g_szTargetConfig), szTargetConfig);

    int iTotalPlayers = 0;
    int[] iPlayers = new int[MaxClients];

    for (int iPlayer = 1; iPlayer <= MaxClients; iPlayer ++)
    {
        if (!IsClientInGame(iPlayer) || IsFakeClient(iPlayer) || IsClientSpectator(iPlayer)) {
            continue;
        }

        iPlayers[iTotalPlayers++] = iPlayer;
    }

    NativeVote hVote = new NativeVote(hHandler, NativeVotesType_Custom_YesNo);
    hVote.Initiator = iInitiator;

    hVote.DisplayVote(iPlayers, iTotalPlayers, VOTE_TIME);

    return hVote;
}

/**
 * Called when a vote action is completed.
 *
 * @param hVote             The vote being acted upon.
 * @param tAction           The action of the vote.
 * @param iParam1           First action parameter.
 * @param iParam2           Second action parameter.
 */
Action HandlerVoteMatchStart(NativeVote hVote, VoteAction tAction, int iParam1, int iParam2)
{
    switch (tAction)
    {
        case VoteAction_Display:
        {
            char szConfigTitle[MAX_CONFIG_TITLE_LENGTH], sVoteDisplayMessage[128];

            g_smConfigsByNames.GetString(g_szTargetConfig, szConfigTitle, sizeof(szConfigTitle));

            FormatEx(sVoteDisplayMessage, sizeof(sVoteDisplayMessage), "%T", "VOTE_MATCH_START", iParam1, szConfigTitle);

            hVote.SetDetails(sVoteDisplayMessage);

            return Plugin_Changed;
        }

        case VoteAction_Cancel: {
            hVote.DisplayFail();
        }

        case VoteAction_Finish:
        {
            if (iParam1 == NATIVEVOTES_VOTE_NO)
            {
                g_szTargetConfig[0] = '\0';
                hVote.DisplayFail();

                return Plugin_Continue;
            }

            ConfigManager_LoadConfig(g_szTargetConfig);
            g_szTargetConfig[0] = '\0';

            hVote.DisplayPass();
        }

        case VoteAction_End: hVote.Close();
    }

    return Plugin_Continue;
}

/**
 * Called when a vote action is completed.
 *
 * @param hVote             The vote being acted upon.
 * @param tAction           The action of the vote.
 * @param iParam1           First action parameter.
 * @param iParam2           Second action parameter.
 */
Action HandlerVoteMatchEnd(NativeVote hVote, VoteAction tAction, int iParam1, int iParam2)
{
    switch (tAction)
    {
        case VoteAction_Display:
        {
            char sVoteDisplayMessage[128];

            char szConfigName[MAX_CONFIG_NAME_LENGTH], szConfigTitle[MAX_CONFIG_TITLE_LENGTH];
            ConfigManager_GetConfigName(szConfigName, sizeof(szConfigName));

            if (!g_smConfigsByNames.GetString(szConfigName, szConfigTitle, sizeof(szConfigTitle))) {
                FormatEx(szConfigTitle, sizeof(szConfigTitle), "%T", "CONFIG_UNDEFINED", iParam1);
            }

            FormatEx(sVoteDisplayMessage, sizeof(sVoteDisplayMessage), "%T", "VOTE_MATCH_END", iParam1, szConfigTitle);

            hVote.SetDetails(sVoteDisplayMessage);

            return Plugin_Changed;
        }

        case VoteAction_Cancel: {
            hVote.DisplayFail();
        }

        case VoteAction_Finish:
        {
            if (iParam1 == NATIVEVOTES_VOTE_NO)
            {
                hVote.DisplayFail();

                return Plugin_Continue;
            }

            hVote.DisplayPass();

            ConfigManager_UnloadConfig();
        }

        case VoteAction_End: hVote.Close();
    }

    return Plugin_Continue;
}

/**
 *
 */
bool IsClientSpectator(int iClient) {
    return (GetClientTeam(iClient) == TEAM_SPECTATE);
}
