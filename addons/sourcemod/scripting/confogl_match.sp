#pragma semicolon               1
#pragma newdecls                required

#include <sourcemod>
#include <confogl_core>
#include <nativevotes_rework>
#include <colors>


public Plugin myinfo =
{
	name = "ConfoglMatch",
	author = "TouchMe",
	description = "N/a",
	version = "build0000",
	url = "https://github.com/TouchMe-Inc/l4d2_confogl"
}


#define CONFIG_NAME_MAX         64

#define CONFIG_LIST_PATH        "configs/confogl_match.txt"

#define TRANSLATIONS            "confogl_match.phrases"

#define TEAM_SPECTATE           1

#define VOTE_TIME               15


Handle
	g_hConfigList = null,
	g_hConfigTitle = null
;

char
	g_sConfigName[CONFIG_NAME_MAX],
	g_sConfigTitle[CONFIG_NAME_MAX]
;

/**
 * Called before OnPluginStart.
 *
 * @param myself            Handle to the plugin.
 * @param late              Whether or not the plugin was loaded "late" (after map load).
 * @param error             Error message buffer in case load failed.
 * @param err_max           Maximum number of characters for error message buffer.
 * @return                  APLRes_Success | APLRes_SilentFailure.
 */
public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
	EngineVersion engine = GetEngineVersion();

	if (engine != Engine_Left4Dead2)
	{
		strcopy(error, err_max, "Plugin only supports Left 4 Dead 2.");
		return APLRes_SilentFailure;
	}

	return APLRes_Success;
}

public void OnPluginStart()
{
	g_hConfigList = CreateKeyValues("ConfigList");

	LoadConfigList(g_hConfigList);
	FillConfigTitle(g_hConfigList, g_hConfigTitle = CreateTrie());

	// Load translations.
	LoadTranslations(TRANSLATIONS);

	RegConsoleCmd("sm_match", Cmd_Match);
	RegConsoleCmd("sm_rmatch", Cmd_ResetMatch);
}

void LoadConfigList(Handle hConfigList)
{
	char sPath[PLATFORM_MAX_PATH ];
	BuildPath(Path_SM, sPath, sizeof(sPath), CONFIG_LIST_PATH);

	if (!FileExists(sPath)) {
        SetFailState("Couldn't load %s", sPath);
    }

 	if (!FileToKeyValues(hConfigList, sPath)) {
        SetFailState("Failed to parse keyvalues for %s", sPath);
    }
}

void FillConfigTitle(Handle hConfigList, Handle hConfigTitle)
{
	if (KvGotoFirstSubKey(hConfigList, false))
	{
		char sCategory[64], sKey[CONFIG_NAME_MAX], sValue[CONFIG_NAME_MAX];

		do
		{
			KvGetSectionName(hConfigList, sCategory, sizeof(sCategory));

			KvRewind(hConfigList);

			if (KvJumpToKey(hConfigList, sCategory) && KvGotoFirstSubKey(hConfigList, false))
			{
				do
				{
					KvGetSectionName(hConfigList, sKey, sizeof(sKey));
					KvGetString(hConfigList, "name", sValue, sizeof(sValue));

					SetTrieString(hConfigTitle, sKey, sValue);
				} while (KvGotoNextKey(hConfigList, false));

				KvGoBack(hConfigList);
			}
		} while (KvGotoNextKey(hConfigList, false));
	}
}

/**
 * When a player wants to find out whos becoming tank,
 * output to them.
 */
Action Cmd_Match(int iClient, int args)
{
	if (!IsValidClient(iClient)) {
		return Plugin_Continue;
	}

	if (IsClientSpectator(iClient)) {
		return Plugin_Handled;
	}

	ShowCategoryMenu(iClient);

	return Plugin_Handled;
}

/**
 * When a player wants to find out whos becoming tank,
 * output to them.
 */
Action Cmd_ResetMatch(int iClient, int args)
{
	if (!IsValidClient(iClient)) {
		return Plugin_Continue;
	}

	if (IsClientSpectator(iClient)) {
		return Plugin_Handled;
	}

	if (!Confogl_IsConfigLoaded()) {
		return Plugin_Handled;
	}

	RunVoteMatchEnd(iClient);

	return Plugin_Handled;
}


void ShowCategoryMenu(int iClient)
{
	Menu hMenu = CreateMenu(HandlerCategoryMenu, MenuAction_Select|MenuAction_End);

	char sConfigTitle[64];

	if (Confogl_IsConfigLoaded())
	{
		char sConfigName[CONFIG_NAME_MAX];
		Confogl_GetConfigName(sConfigName, sizeof(sConfigName));
		
		if (!GetTrieString(g_hConfigTitle, sConfigName, sConfigTitle, sizeof(sConfigTitle))) {
			FormatEx(sConfigTitle, sizeof(sConfigTitle), "%T", "CONFIG_UNKNOWN", iClient);
		}
	}

	else {
		FormatEx(sConfigTitle, sizeof(sConfigTitle), "%T", "CONFIG_NONE", iClient);
	}

	SetMenuTitle(hMenu, "%T", "CATEGORY_MENU_TITLE", iClient, sConfigTitle);

	KvRewind(g_hConfigList);

	if (KvGotoFirstSubKey(g_hConfigList, false))
	{
		char sBuffer[64];

		do {
			KvGetSectionName(g_hConfigList, sBuffer, sizeof(sBuffer));
			AddMenuItem(hMenu, sBuffer, sBuffer);
		} while (KvGotoNextKey(g_hConfigList, false));
	}

	DisplayMenu(hMenu, iClient, -1);
}

/**
 *
 */
int HandlerCategoryMenu(Menu hMenu, MenuAction hAction, int iClient, int iItem)
{
	switch(hAction)
	{
		case MenuAction_End: CloseHandle(hMenu);

		case MenuAction_Select:
		{
			char sCategory[64];
			GetMenuItem(hMenu, iItem, sCategory, sizeof(sCategory));

			KvRewind(g_hConfigList);

			if (KvJumpToKey(g_hConfigList, sCategory) && KvGotoFirstSubKey(g_hConfigList, false))
			{
				Menu hConfigMenu = CreateMenu(HandlerConfigMenu, MenuAction_Select|MenuAction_End);

				char sConfigTitle[64];

				if (Confogl_IsConfigLoaded())
				{
					char sConfigName[CONFIG_NAME_MAX];
					Confogl_GetConfigName(sConfigName, sizeof(sConfigName));
					
					if (!GetTrieString(g_hConfigTitle, sConfigName, sConfigTitle, sizeof(sConfigTitle))) {
						FormatEx(sConfigTitle, sizeof(sConfigTitle), "%T", "CONFIG_UNKNOWN", iClient);
					}
				}
				
				else {
					FormatEx(sConfigTitle, sizeof(sConfigTitle), "%T", "CONFIG_NONE", iClient);
				}

				SetMenuTitle(hConfigMenu, "%T", "CONFIG_MENU_TITLE", iClient, sCategory, sConfigTitle);

				char sTitle[64], sBuffer[64];

				do {
					KvGetSectionName(g_hConfigList, sTitle, sizeof(sTitle));
					KvGetString(g_hConfigList, "name", sBuffer, sizeof(sBuffer));

					AddMenuItem(hConfigMenu, sTitle, sBuffer);
				} while (KvGotoNextKey(g_hConfigList, false));

				DisplayMenu(hConfigMenu, iClient, -1);
			}

			else {
				ShowCategoryMenu(iClient);
			}
		}
	}

	return 0;
}

public int HandlerConfigMenu(Menu hMenu, MenuAction hAction, int iClient, int iItem)
{
	switch(hAction)
	{
		case MenuAction_End: CloseHandle(hMenu);

		case MenuAction_Select:
		{
			GetMenuItem(hMenu, iItem, g_sConfigName, sizeof(g_sConfigName), _, g_sConfigTitle, sizeof(g_sConfigTitle));

			RunVoteMatchStart(iClient);
		}
	}

	return 0;
}

void RunVoteMatchStart(int iClient)
{
	if (!NativeVotes_IsNewVoteAllowed())
	{
		CPrintToChat(iClient, "%T%T", "TAG", iClient, "VOTE_COULDOWN", iClient, NativeVotes_CheckVoteDelay());
		return;
	}

	int iTotalPlayers;
	int[] iPlayers = new int[MaxClients];

	for (int iPlayer = 1; iPlayer <= MaxClients; iPlayer ++)
	{
		if (!IsClientInGame(iPlayer) || IsFakeClient(iPlayer) || IsClientSpectator(iPlayer)) {
			continue;
		}

		iPlayers[iTotalPlayers++] = iPlayer;
	}

	NativeVote hVote = new NativeVote(HandlerVoteMatchStart, NativeVotesType_Custom_YesNo);
	hVote.Initiator = iClient;

	hVote.DisplayVote(iPlayers, iTotalPlayers, VOTE_TIME);
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
			char sVoteDisplayMessage[128];

			FormatEx(sVoteDisplayMessage, sizeof(sVoteDisplayMessage), "%T", "VOTE_MATCH_START", iParam1, g_sConfigTitle);

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

			Confogl_LoadConfig(g_sConfigName);
		}

		case VoteAction_End: hVote.Close();
	}

	return Plugin_Continue;
}

void RunVoteMatchEnd(int iClient)
{
	if (!NativeVotes_IsNewVoteAllowed())
	{
		CPrintToChat(iClient, "%T%T", "TAG", iClient, "VOTE_COULDOWN", iClient, NativeVotes_CheckVoteDelay());
		return;
	}

	int iTotalPlayers;
	int[] iPlayers = new int[MaxClients];

	for (int iPlayer = 1; iPlayer <= MaxClients; iPlayer ++)
	{
		if (!IsClientInGame(iPlayer) || IsFakeClient(iPlayer) || IsClientSpectator(iPlayer)) {
			continue;
		}

		iPlayers[iTotalPlayers++] = iPlayer;
	}

	NativeVote hVote = new NativeVote(HandlerVoteMatchEnd, NativeVotesType_Custom_YesNo);
	hVote.Initiator = iClient;

	hVote.DisplayVote(iPlayers, iTotalPlayers, VOTE_TIME);
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

			char sConfigName[CONFIG_NAME_MAX];
			Confogl_GetConfigName(sConfigName, sizeof(sConfigName));
			
			char sConfigTitle[64];

			if (!GetTrieString(g_hConfigTitle, sConfigName, sConfigTitle, sizeof(sConfigTitle))) {
				FormatEx(sConfigTitle, sizeof(sConfigTitle), "%T", "CONFIG_UNKNOWN", iParam1);
			}

			FormatEx(sVoteDisplayMessage, sizeof(sVoteDisplayMessage), "%T", "VOTE_MATCH_END", iParam1, sConfigTitle);

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

			Confogl_UnloadConfig();
		}

		case VoteAction_End: hVote.Close();
	}

	return Plugin_Continue;
}

/**
 *
 */
bool IsValidClient(int iClient) {
	return (iClient > 0 && iClient <= MaxClients);
}

/**
 *
 */
bool IsClientSpectator(int iClient) {
	return (GetClientTeam(iClient) == TEAM_SPECTATE);
}
