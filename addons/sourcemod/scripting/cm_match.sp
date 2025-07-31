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


#define PATH_TO_CONFIG          "configs/cm_match.txt"

#define TRANSLATIONS            "cm_match.phrases"

/*
 * String size limits.
 */
#define MAXLENGTH_NODE_KEY      32
#define MAXLENGTH_NODE_VALUE    128

#define MAXLENGTH_CONFIG_PATH   128
#define MAXLENGTH_CONFIG_NAME   64
#define MAXLENGTH_CONFIG_ALIAS  16
#define MAXLENGTH_CONFIG_VERSION 8
#define MAXLENGTH_CONFIG_AUTHOR 32

#define MAXLENGTH_CHAT_MESSAGE  256

/*
 * Votes.
 */
#define VOTE_TIME               12

/*
 * Teams.
 */
#define TEAM_SPECTATE           1

enum struct ConfigInfo
{
    char name[MAXLENGTH_CONFIG_NAME];
    char alias[MAXLENGTH_CONFIG_ALIAS];
    char version[MAXLENGTH_CONFIG_VERSION];
    char author[MAXLENGTH_CONFIG_AUTHOR];
    ArrayList description;
}

enum struct NodeItem
{
    char key[MAXLENGTH_NODE_KEY];
    char value[MAXLENGTH_NODE_VALUE];
    ArrayList children;
}

NodeItem g_aActiveNode[MAXPLAYERS + 1];
NodeItem g_eMenu;

StringMap g_smConfigInfo = null;

char g_szTargetConfig[PLATFORM_MAX_PATH];


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
    // Load translations.
    LoadTranslations(TRANSLATIONS);

    RegConsoleCmd("sm_match", Cmd_Match);
    RegConsoleCmd("sm_rmatch", Cmd_ResetMatch);

    g_smConfigInfo = new StringMap();

    char szPath[PLATFORM_MAX_PATH];
    BuildPath(Path_SM, szPath, sizeof(szPath), PATH_TO_CONFIG);
    BuildMenu(szPath, g_eMenu);

    PushConfigInfoFromMenu(g_smConfigInfo, g_eMenu.children);
}

Action Cmd_Match(int iClient, int iArgs)
{
    if (!iClient) {
        return Plugin_Continue;
    }

 
    switch (iArgs)
    {
        case 0: 
        {
            g_aActiveNode[iClient] = g_eMenu;
            ShowMenu(iClient, g_eMenu);
        }

        case 1:
        {
            if (IsClientSpectator(iClient))
            {
                CPrintToChat(iClient, "%T%T", "TAG", iClient, "DENY_FOR_SPECTATOR", iClient);
                return Plugin_Handled;
            }

            char szArg[MAXLENGTH_CONFIG_ALIAS]; GetCmdArg(1, szArg, sizeof(szArg));

            StringMapSnapshot smConfigInfoSnapshot = g_smConfigInfo.Snapshot();

            ConfigInfo info;
            char szConfigPath[MAXLENGTH_CONFIG_PATH];
            bool bFound = false;

            int iSize = smConfigInfoSnapshot.Length;
            for (int iIndex = 0; iIndex < iSize; iIndex ++)
            {
                smConfigInfoSnapshot.GetKey(iIndex, szConfigPath, sizeof szConfigPath);

                g_smConfigInfo.GetArray(szConfigPath, info, sizeof ConfigInfo);

                if (StrEqual(info.alias, szArg, false))
                {
                    RunVote(HandlerVoteMatchStart, iClient, szConfigPath);
                    bFound = true;
                    break;
                }
            }

            delete smConfigInfoSnapshot;

            if (!bFound) {
                CPrintToChat(iClient, "%T%T", "TAG", iClient, "ALIAS_NOT_FOUND", iClient, szArg);
            }
        }
    }

    return Plugin_Handled;
}

Action Cmd_ResetMatch(int iClient, int iArgs)
{
    if (!iClient) {
        return Plugin_Continue;
    }

    if (!ConfigManager_IsConfigLoaded())
    {
        CPrintToChat(iClient, "%T%T", "TAG", iClient, "CONFIG_NOT_LOADED", iClient);
        return Plugin_Handled;
    }

    if (IsClientSpectator(iClient))
    {
        CPrintToChat(iClient, "%T%T", "TAG", iClient, "DENY_FOR_SPECTATOR", iClient);
        return Plugin_Handled;
    }

    RunVote(HandlerVoteMatchEnd, iClient);

    return Plugin_Handled;
}

void ShowMenu(int iClient, NodeItem aActiveNode)
{
    Menu menu = CreateMenu(HandlerMenu, MenuAction_Select|MenuAction_End);

    char szMenuTitle[128];
    if (!ConfigManager_IsConfigLoaded()) {
        FormatEx(szMenuTitle, sizeof szMenuTitle, "%T", "MENU_MAIN_TITLE", iClient);
    } else {
        char szConfigPath[MAXLENGTH_CONFIG_PATH];
        ConfigManager_GetConfigPath(szConfigPath, sizeof(szConfigPath));

        ConfigInfo info;
        if (!g_smConfigInfo.GetArray(szConfigPath, info, sizeof(ConfigInfo))) {
            FormatEx(szMenuTitle, sizeof szMenuTitle, "%T", "MENU_MAIN_TITLE_WITH_UNKNOWN", iClient);
        } else {
           FormatEx(szMenuTitle, sizeof szMenuTitle, "%T", "MENU_MAIN_TITLE_WITH_CONFIG", iClient, info.name);
        }
    }

    menu.SetTitle(szMenuTitle);

    char szIdx[4];
    NodeItem node;
    ConfigInfo info;
    for (int iIdx = 0; iIdx < aActiveNode.children.Length; iIdx ++)
    {
        aActiveNode.children.GetArray(iIdx, node);

        IntToString(iIdx, szIdx, sizeof(szIdx));

        if (g_smConfigInfo.GetArray(node.value, info, sizeof(info))) {
            menu.AddItem(szIdx, info.name);
        } else {
            menu.AddItem(szIdx, node.value);
        }
    }

    menu.Display(iClient, -1);
}

/**
 *
 */
int HandlerMenu(Menu menu, MenuAction action, int iClient, int iItem)
{
    switch (action)
    {
        case MenuAction_End: delete menu;

        case MenuAction_Select:
        {
            char szIdx[8];
            menu.GetItem(iItem, szIdx, sizeof(szIdx));

            int iIdx = StringToInt(szIdx);

            NodeItem node;
            g_aActiveNode[iClient].children.GetArray(iIdx, node);

            if (node.children.Length) {
                g_aActiveNode[iClient] = node;
                ShowMenu(iClient, node);
            } else {
                ShowConfigMenu(iClient, node.value);
            }

        }
    }

    return 0;
}

void ShowConfigMenu(int iClient, char[] szConfigPath)
{
    Menu menu = CreateMenu(HandlerConfigMenu, MenuAction_Select|MenuAction_End|MenuAction_Cancel);

    ConfigInfo info;
    g_smConfigInfo.GetArray(szConfigPath, info, sizeof(info));

    menu.SetTitle("%T", "MENU_INFO_TITLE", iClient, info.name, info.alias, info.version, info.author);

    char szBuffer[64];

    FormatEx(szBuffer, sizeof(szBuffer), "%T", "RUN_VOTE", iClient);
    menu.AddItem(szConfigPath, szBuffer);

    FormatEx(szBuffer, sizeof(szBuffer), "%T", "PRINT_DESCRIPTION", iClient);
    menu.AddItem(szConfigPath, szBuffer, info.description != null && info.description.Length > 0 ? ITEMDRAW_DEFAULT : ITEMDRAW_DISABLED);

    menu.Display(iClient, -1);
}

public int HandlerConfigMenu(Menu menu, MenuAction action, int iClient, int iItem)
{
    switch (action)
    {
        case MenuAction_End: delete menu;

        case MenuAction_Cancel: {
            if (iItem == MenuEnd_Cancelled) {
                ShowMenu(iClient, g_aActiveNode[iClient]);
            }
        }

        case MenuAction_Select:
        {
            char szTargetConfig[MAXLENGTH_CONFIG_PATH];
            menu.GetItem(iItem, szTargetConfig, sizeof(szTargetConfig));

            switch (iItem)
            {
                case 0: {
                    if (!IsClientSpectator(iClient)) {
                        RunVote(HandlerVoteMatchStart, iClient, szTargetConfig);
                    } else {
                        CPrintToChat(iClient, "%T%T", "TAG", iClient, "DENY_FOR_SPECTATOR", iClient);
                        ShowConfigMenu(iClient, szTargetConfig);
                    }
                }

                case 1: {
                    ConfigInfo info;
                    g_smConfigInfo.GetArray(szTargetConfig, info, sizeof(info));

                    char szChatMessage[MAXLENGTH_CHAT_MESSAGE];
                    for (int iIdx = 0; iIdx < info.description.Length; iIdx++)
                    {
                        info.description.GetString(iIdx, szChatMessage, sizeof(szChatMessage));
                        CPrintToChat(iClient, "%s", szChatMessage);
                    }

                    ShowConfigMenu(iClient, szTargetConfig);
                }
            }
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
            char szVoteDetails[128];
            ConfigInfo info;
            if (!g_smConfigInfo.GetArray(g_szTargetConfig, info, sizeof(ConfigInfo))) {
                FormatEx(szVoteDetails, sizeof(szVoteDetails), "%T", "VOTE_MATCH_START", iParam1, g_szTargetConfig);
            } else {
                FormatEx(szVoteDetails, sizeof(szVoteDetails), "%T", "VOTE_MATCH_START", iParam1, info.name);
            }

            hVote.SetDetails(szVoteDetails);

            return Plugin_Changed;
        }

        case VoteAction_Cancel: hVote.DisplayFail();

        case VoteAction_Finish:
        {
            if (iParam1 == NATIVEVOTES_VOTE_NO)
            {
                hVote.DisplayFail();
                g_szTargetConfig[0] = '\0';

                return Plugin_Continue;
            }

            hVote.DisplayPass();

            ConfigManager_LoadConfig(g_szTargetConfig);
            g_szTargetConfig[0] = '\0';
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
            char szConfigPath[MAXLENGTH_CONFIG_PATH];
            ConfigManager_GetConfigPath(szConfigPath, sizeof(szConfigPath));

            char szVoteDetails[128];
            ConfigInfo info;

            if (!g_smConfigInfo.GetArray(szConfigPath, info, sizeof(ConfigInfo))) {
                FormatEx(szVoteDetails, sizeof(szVoteDetails), "%T", "VOTE_MATCH_END", iParam1, szConfigPath);
            } else {
                FormatEx(szVoteDetails, sizeof(szVoteDetails), "%T", "VOTE_MATCH_END", iParam1, info.name);
            }

            hVote.SetDetails(szVoteDetails);

            return Plugin_Changed;
        }

        case VoteAction_Cancel: hVote.DisplayFail();

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

void BuildMenu(char[] szPath, NodeItem menu)
{
    if (!FileExists(szPath)) {
        SetFailState("Couldn't load %s", szPath);
    }

    KeyValues kv = CreateKeyValues("Configs");

    if (!kv.ImportFromFile(szPath)) {
        SetFailState("Failed to parse keyvalues for %s", szPath);
    }

    ArrayList hierarchy = BuildHierarchy(kv);

    strcopy(menu.key, sizeof menu.key, "\0");
    strcopy(menu.value, sizeof menu.value, "MENU_MAIN_TITLE");
    menu.children = SimplifyHierarchy(hierarchy);

    delete kv;
    delete hierarchy;
}

/**
 * High-level transformation of a raw NodeItem hierarchy into a simplified category-item tree.
 *
 * This function iterates over all top-level nodes in the raw hierarchy (typically produced by BuildHierarchy),
 * and applies SimplifyNodeTo to each one. The result is a flattened structure where each node contains:
 * - a resolved name (from child "name" node),
 * - a value (used as identifier),
 * - and a list of children representing items or subcategories.
 *
 * @param rawHierarchy   An ArrayList of NodeItem structs from BuildHierarchy.
 * @return               A new ArrayList of simplified NodeItem structs with normalized structure.
 */
ArrayList SimplifyHierarchy(ArrayList rawHierarchy)
{
    ArrayList result = new ArrayList(sizeof(NodeItem));

    for (int iIdx = 0; iIdx < rawHierarchy.Length; iIdx++)
    {
        NodeItem src;
        rawHierarchy.GetArray(iIdx, src);
        SimplifyNodeTo(result, src);
    }

    return result;
}

/**
 * Recursively simplifies a hierarchical NodeItem structure into a flat category-item tree.
 *
 * This function transforms a complex node (with nested categories and items)
 * into a simplified representation where each node has:
 * - a `key` (original category key),
 * - a `value` (resolved name from child "name" node),
 * - and a list of children representing either items or subcategories.
 *
 * Items are extracted from "items" blocks, and subcategories are recursively simplified.
 *
 * @param result   The ArrayList to which the simplified NodeItem will be appended.
 * @param src      The source NodeItem to simplify.
 */
void SimplifyNodeTo(ArrayList result, const NodeItem src)
{
    // 1) Initialize the destination node with key and empty value
    NodeItem dst;
    strcopy(dst.key,   sizeof(dst.key),   src.key);
    dst.value[0] = '\0';
    dst.children = new ArrayList(sizeof(NodeItem));

    // 2) Try to extract the category name from a child node with key "name"
    for (int i = 0; i < src.children.Length; i++)
    {
        NodeItem child;
        src.children.GetArray(i, child);
        if (StrEqual(child.key, "name", false))
        {
            strcopy(dst.value, sizeof(dst.value), child.value);
            break;
        }
    }

    // Fallback: use src.key if no "name" child was found
    if (dst.value[0] == '\0')
    {
        strcopy(dst.value, sizeof(dst.value), src.key);
    }

    // 3) Process the "items" block, if present
    for (int i = 0; i < src.children.Length; i++)
    {
        NodeItem block;
        src.children.GetArray(i, block);
        if (!StrEqual(block.key, "items", false))
            continue;

        // Inside "items" we may find "item" or nested "category"
        for (int j = 0; j < block.children.Length; j++)
        {
            NodeItem sub;
            block.children.GetArray(j, sub);

            // 3.1) Handle individual item
            if (StrEqual(sub.key, "item", false))
            {
                // Ищем в sub его child.key == "name"
                NodeItem leafNode;
                strcopy(leafNode.key,   sizeof(leafNode.key),   sub.key);
                leafNode.children = new ArrayList(sizeof(NodeItem));

                for (int k = 0; k < sub.children.Length; k++)
                {
                    NodeItem child;
                    sub.children.GetArray(k, child);

                    if (StrEqual(child.key, "name", false))
                    {
                        strcopy(leafNode.value, sizeof(leafNode.value), child.value);
                        break;
                    }
                }

                dst.children.PushArray(leafNode);
            }
            // 3.2) Handle nested category inside "items"
            else if (StrEqual(sub.key, "category", false))
            {
                SimplifyNodeTo(dst.children, sub);
            }
        }
    }

    // 4) Process additional categories at the same level as src
    for (int i = 0; i < src.children.Length; i++)
    {
        NodeItem child;
        src.children.GetArray(i, child);

        // Skip already processed keys
        if (StrEqual(child.key, "name", false) || StrEqual(child.key, "items", false)) {
            continue;
        }

        // Treat any other "category" as a subcategory
        if (StrEqual(child.key, "category", false)) {
            SimplifyNodeTo(dst.children, child);
        }
    }

    // 5) Кладём готовый узел в результат
    result.PushArray(dst);
}

/**
 * Recursively constructs a tree of NodeItem structs from a KeyValues object.
 *
 * This function traverses all immediate subkeys of the current KeyValues position,
 * creating a NodeItem for each key. Each node stores its name, value, and a list
 * of child nodes built recursively from its own subkeys.
 *
 * @param kv         The KeyValues object to read from. Assumes current position is valid.
 * @return           An ArrayList containing NodeItem structs representing the hierarchy.
 *                   Each NodeItem owns its own children list.
 */
ArrayList BuildHierarchy(KeyValues kv)
{
    // Create a new list to hold nodes at the current level
    ArrayList nodes = new ArrayList(sizeof(NodeItem));

    // Attempt to enter the first child key (includes both sections and leaf nodes)
    if (!KvGotoFirstSubKey(kv, false)) {
        return nodes; // No children — return empty list
    }

    char keyName[MAXLENGTH_NODE_KEY];
    char keyValue[MAXLENGTH_NODE_VALUE];

    do
    {
        // Read the current key's name and value
        KvGetSectionName(kv, keyName, sizeof(keyName));
        KvGetString(kv, NULL_STRING, keyValue, sizeof(keyValue));

        // Create a new node and assign key/value
        NodeItem node;
        strcopy(node.key, sizeof(node.key), keyName);
        strcopy(node.value, sizeof(node.value), keyValue);

        // Recursively build children for this node
        node.children = BuildHierarchy(kv);

        // Add the completed node to the result list
        nodes.PushArray(node);
    }
    while (KvGotoNextKey(kv));

    // Return to parent level after traversal
    KvGoBack(kv);
    return nodes;
}

/**
 * Recursively traverses a hierarchy of NodeItem entries and loads ConfigInfo data from disk.
 *
 * For each leaf node (i.e., node without children), this function attempts to locate and parse
 * an `info.txt` file located at the path derived from the node's value. If successful, it extracts
 * metadata fields and description lines into a ConfigInfo struct, which is stored in the provided StringMap.
 *
 * @param smConfigInfo   A StringMap where parsed ConfigInfo structs will be stored.
 *                       The key is the node's value (used as config identifier).
 * @param nodes          An ArrayList of NodeItem structs representing the current level of hierarchy.
 */
void PushConfigInfoFromMenu(StringMap smConfigInfo, ArrayList nodes)
{
    KeyValues kv = new KeyValues("ConfigInfo");

    NodeItem node;
    ConfigInfo ci;
    char szConfigPath[PLATFORM_MAX_PATH], szMessage[MAXLENGTH_CHAT_MESSAGE];

    for (int iIdx = 0; iIdx < nodes.Length; iIdx++)
    {
        nodes.GetArray(iIdx, node);

        // If the node has children, recurse into them
        if (node.children.Length > 0)
        {
            PushConfigInfoFromMenu(smConfigInfo, node.children);
        }
        else
        {
            // Build path to info.txt and attempt to import
            ConfigManager_BuildConfigPath(szConfigPath, node.value);
            StrCat(szConfigPath, sizeof(szConfigPath), "/info.txt");

            // File not found or failed to parse — skip
            if (!kv.ImportFromFile(szConfigPath)) {
                continue;
            }

            // Extract fields into ConfigInfo struct
            kv.GetString("name",    ci.name,    sizeof(ci.name));
            kv.GetString("alias",   ci.alias,   sizeof(ci.alias));
            kv.GetString("version", ci.version, sizeof(ci.version));
            kv.GetString("author", ci.author, sizeof(ci.author));

            if (kv.JumpToKey("description") && KvGotoFirstSubKey(kv, false))
            {
                ci.description = new ArrayList(ByteCountToCells(sizeof(szMessage)));

                do
                {
                    kv.GetString(NULL_STRING, szMessage, sizeof(szMessage));
                    ci.description.PushString(szMessage);
                }
                while (KvGotoNextKey(kv, false));
            }

            // Store result in the map
            smConfigInfo.SetArray(node.value, ci, sizeof(ConfigInfo));
        }
    }

    delete kv;
}

/**
 *
 */
bool IsClientSpectator(int iClient) {
    return (GetClientTeam(iClient) == TEAM_SPECTATE);
}
