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


#define MAX_CONFIG_NAME_LENGTH  64
#define MAX_CONFIG_TITLE_LENGTH 64

#define PATH_TO_CONFIG          "configs/cm_match.txt"

#define TRANSLATIONS            "cm_match.phrases"

#define TEAM_SPECTATE           1

#define VOTE_TIME               15


enum struct ConfigInfo
{
    char name[32];
    char alias[32];
    char version[16];
    char author[32];
    ArrayList description;
}

enum struct NodeItem
{
    char key[32];
    char value[128];
    ArrayList children;
}

ArrayList g_hActiveMenu[MAXPLAYERS + 1];

ArrayList g_hMenu = null;
StringMap g_smConfigInfo = null;

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

    char szPath[PLATFORM_MAX_PATH];
    BuildPath(Path_SM, szPath, sizeof(szPath), PATH_TO_CONFIG);
    g_hMenu = BuildMenu(szPath);

    g_smConfigInfo = new StringMap();
    PushConfigInfoFromMenu(g_smConfigInfo, g_hMenu);
}

ArrayList BuildMenu(char[] szPath)
{
    if (!FileExists(szPath)) {
        SetFailState("Couldn't load %s", szPath);
    }

    KeyValues kv = CreateKeyValues("Configs");

    if (!kv.ImportFromFile(szPath)) {
        SetFailState("Failed to parse keyvalues for %s", szPath);
    }

    ArrayList hierarchy = BuildHierarchy(kv);

    delete kv;

    ArrayList menu = SimplifyHierarchy(hierarchy);

    delete hierarchy;

    return menu;
}

/**
 * Высокоуровневая функция: обходит весь rawHierarchy и
 * на каждый корневой узел вызывает SimplifyNodeTo.
 *
 * @param rawHierarchy  ArrayList sizeof(NodeItem) — от BuildHierarchy
 * @return              Новая иерархия с name→value и items→children
 */
ArrayList SimplifyHierarchy(ArrayList rawHierarchy)
{
    ArrayList result = new ArrayList(sizeof(NodeItem));

    for (int i = 0; i < rawHierarchy.Length; i++)
    {
        NodeItem src;
        rawHierarchy.GetArray(i, src);
        SimplifyNodeTo(result, src);
    }

    return result;
}

/**
 * Кладёт в result новый узел dst:
 *   dst.key     = src.key
 *   dst.value   = текст из под-узла "name" или, если нет, src.key
 *   dst.children = список:
 *     – всех созданных из "item" листов
 *     – рекурсивно упрощённых вложенных "category"
 *
 * @param result  ArrayList sizeof(NodeItem) — куда пушим dst
 * @param src     NodeItem из BuildHierarchy()
 */
void SimplifyNodeTo(ArrayList result, const NodeItem src)
{
    // 1) Собираем базовый dst
    NodeItem dst;
    strcopy(dst.key,   sizeof(dst.key),   src.key);
    dst.value[0] = '\0';
    dst.children = new ArrayList(sizeof(NodeItem));

    // 2) Находим имя категории (под-узел "name")
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

    // fallback на src.key, если name не найден
    if (dst.value[0] == '\0')
    {
        strcopy(dst.value, sizeof(dst.value), src.key);
    }

    // 3) Обрабатываем блок "items"
    for (int i = 0; i < src.children.Length; i++)
    {
        NodeItem block;
        src.children.GetArray(i, block);
        if (!StrEqual(block.key, "items", false))
            continue;

        // Внутри "items" может быть и "item", и вложенная "category"
        for (int j = 0; j < block.children.Length; j++)
        {
            NodeItem sub;
            block.children.GetArray(j, sub);

            // 3.1) Чистый элемент
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
            // 3.2) Вложенная категория внутри items
            else if (StrEqual(sub.key, "category", false))
            {
                SimplifyNodeTo(dst.children, sub);
            }
        }
    }

    // 4) Обрабатываем вложенные категории на том же уровне, что и src
    for (int i = 0; i < src.children.Length; i++)
    {
        NodeItem child;
        src.children.GetArray(i, child);

        // уже сделали name и items
        if (StrEqual(child.key, "name", false) || StrEqual(child.key, "items", false))
            continue;

        // любые другие под-узлы считаем дополнительными категориями
        if (StrEqual(child.key, "category", false)) {
            SimplifyNodeTo(dst.children, child);
        }
    }

    // 5) Кладём готовый узел в результат
    result.PushArray(dst);
}

/**
 * PushConfigInfoFromMenu
 *
 * Recursively traverses a menu node tree and loads configuration metadata for each leaf node
 * (i.e., nodes without children). For every such node:
 *   1) A configuration path is built using ConfigManager_BuildConfigPath().
 *   2) "/info.txt" is appended to the path.
 *   3) KeyValues are imported from the file.
 *   4) Fields "name", "alias", and "version" are extracted into a ConfigInfo struct.
 *   5) The struct is stored in the provided StringMap using node.value as the key.
 *
 * @param StringMap smConfigInfo
 *   A map that stores ConfigInfo structs indexed by node.value.
 *
 * @param ArrayList nodes
 *   A list of NodeItem objects representing menu nodes. Each node contains:
 *     - node.children: an ArrayList of child nodes;
 *     - node.value: a unique identifier for the configuration.
 */
void PushConfigInfoFromMenu(StringMap smConfigInfo, ArrayList nodes)
{
    KeyValues kv = new KeyValues("ConfigInfo");

    NodeItem node;
    ConfigInfo ci;
    char szConfigPath[PLATFORM_MAX_PATH];
    char szMessage[256];

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
                    kv.GetString("text", szMessage, sizeof(szMessage));
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
 * Рекурсивно собирает дерево из hKv в ArrayList.
 * @return Новый ArrayList (список узлов), владеющий своими children.
 */
ArrayList BuildHierarchy(Handle hKv)
{
    ArrayList nodes = new ArrayList(sizeof(NodeItem));

    // Заходим в первый дочерний узел (и секции, и leaf-элементы)
    if (!KvGotoFirstSubKey(hKv, false)) {
        return nodes; // пустой список, если нет потомков
    }

    do
    {
        // 1) Считываем имя и значение
        char keyName[32];
        KvGetSectionName(hKv, keyName, sizeof(keyName));

        char keyValue[128];
        KvGetString(hKv, NULL_STRING, keyValue, sizeof(keyValue));

        // 2) Создаём «узел» и кладём name/value
        NodeItem node;
        strcopy(node.key, sizeof(node.key), keyName);
        strcopy(node.value, sizeof(node.value), keyValue);

        // 3) Рекурсивно строим список детей
        node.children = BuildHierarchy(hKv);

        // 4) Кладём готовый узел в результирующий список
        nodes.PushArray(node);
    } while (KvGotoNextKey(hKv));

    KvGoBack(hKv);
    return nodes;
}

Action Cmd_Match(int iClient, int args)
{
    if (!iClient) {
        return Plugin_Continue;
    }

    ShowMenu(iClient, g_hActiveMenu[iClient] = g_hMenu);

    return Plugin_Handled;
}

Action Cmd_ResetMatch(int iClient, int args)
{
    if (!iClient) {
        return Plugin_Continue;
    }

    if (!ConfigManager_IsConfigLoaded())
    {
        CPrintToChat(iClient, "%T%T", "TAG", iClient, "CONFIG_NOT_LOADED", iClient);
        return Plugin_Handled;
    }

    // RunVote(HandlerVoteMatchEnd, iClient);

    return Plugin_Handled;
}

void ShowMenu(int iClient, ArrayList hActiveMenu)
{
    Menu menu = CreateMenu(HandlerMenu, MenuAction_Select|MenuAction_End);

    if (!ConfigManager_IsConfigLoaded()) {
        menu.SetTitle("%T", "MENU_MAIN_TITLE", iClient);
    } else {
        char szConfigName[MAX_CONFIG_NAME_LENGTH];
        ConfigManager_GetConfigName(szConfigName, sizeof(szConfigName));

        char szConfigTitle[MAX_CONFIG_TITLE_LENGTH];
        if (!g_smConfigInfo.GetString(szConfigName, szConfigTitle, sizeof(szConfigTitle))) {
            FormatEx(szConfigTitle, sizeof(szConfigTitle), "%T", "CONFIG_UNDEFINED", iClient);
        }

        menu.SetTitle("%T", "MENU_MAIN_TITLE_EX", iClient, szConfigTitle);
    }

    char szIdx[4];
    NodeItem node;
    ConfigInfo info;
    for (int iIdx = 0; iIdx < hActiveMenu.Length; iIdx ++)
    {
        hActiveMenu.GetArray(iIdx, node);

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
int HandlerMenu(Menu menu, MenuAction hAction, int iClient, int iItem)
{
    switch (hAction)
    {
        case MenuAction_End: delete menu;

        case MenuAction_Select:
        {
            char szIdx[8];
            menu.GetItem(iItem, szIdx, sizeof(szIdx));

            int iIdx = StringToInt(szIdx);

            NodeItem node;
            g_hActiveMenu[iClient].GetArray(iIdx, node);

            PrintToChatAll("%s %s : %d", node.key, node.value, node.children.Length);

            ShowMenu(iClient, g_hActiveMenu[iClient] = node.children);
        }
    }

    return 0;
}

// void ShowCategoryMenu(int iClient, int iCategoryIdx)
// {
//     Menu menu = CreateMenu(HandlerCategoryMenu, MenuAction_Select|MenuAction_End);

//     char szConfigName[MAX_CONFIG_NAME_LENGTH];
//     char szConfigTitle[MAX_CONFIG_TITLE_LENGTH];

//     Node node;
//     g_hMenu.GetArray(iCategoryIdx, node);

//     if (ConfigManager_IsConfigLoaded())
//     {
//         ConfigManager_GetConfigName(szConfigName, sizeof(szConfigName));

//         if (!g_smConfigInfo.GetString(szConfigName, szConfigTitle, sizeof(szConfigTitle))) {
//             FormatEx(szConfigTitle, sizeof(szConfigTitle), "%T", "CONFIG_UNDEFINED", iClient);
//         }

//         menu.SetTitle("%T", "MENU_CATEGORY_TITLE_EX", iClient, szConfigTitle);
//     }

//     else {
//         menu.SetTitle("%T", "MENU_CATEGORY_TITLE", iClient);
//     }

//     for (int iIdx = 0; iIdx < node.children.Length; iIdx ++)
//     {
//         node.children.GetString(iIdx, szConfigName, sizeof(szConfigName));

//         g_smConfigInfo.GetString(szConfigName, szConfigTitle, sizeof(szConfigTitle));

//         menu.AddItem(szConfigName, szConfigTitle);
//     }

//     menu.Display(iClient, -1);
// }

// public int HandlerCategoryMenu(Menu menu, MenuAction hAction, int iClient, int iItem)
// {
//     switch (hAction)
//     {
//         case MenuAction_End: delete menu;

//         case MenuAction_Select:
//         {
//             char szTargetConfig[MAX_CONFIG_NAME_LENGTH];
//             menu.GetItem(iItem, szTargetConfig, sizeof(szTargetConfig));

//             RunVote(HandlerVoteMatchStart, iClient, szTargetConfig);
//         }
//     }

//     return 0;
// }

// NativeVote RunVote(NativeVotes_Handler hHandler, int iInitiator, char[] szTargetConfig = "")
// {
//     if (!NativeVotes_IsNewVoteAllowed())
//     {
//         CPrintToChat(iInitiator, "%T%T", "TAG", iInitiator, "VOTE_COULDOWN", iInitiator, NativeVotes_CheckVoteDelay());
//         return null;
//     }

//     strcopy(g_szTargetConfig, sizeof(g_szTargetConfig), szTargetConfig);

//     int iTotalPlayers = 0;
//     int[] iPlayers = new int[MaxClients];

//     for (int iPlayer = 1; iPlayer <= MaxClients; iPlayer ++)
//     {
//         if (!IsClientInGame(iPlayer) || IsFakeClient(iPlayer) || IsClientSpectator(iPlayer)) {
//             continue;
//         }

//         iPlayers[iTotalPlayers++] = iPlayer;
//     }

//     NativeVote hVote = new NativeVote(hHandler, NativeVotesType_Custom_YesNo);
//     hVote.Initiator = iInitiator;

//     hVote.DisplayVote(iPlayers, iTotalPlayers, VOTE_TIME);

//     return hVote;
// }

/**
 * Called when a vote action is completed.
 *
 * @param hVote             The vote being acted upon.
 * @param tAction           The action of the vote.
 * @param iParam1           First action parameter.
 * @param iParam2           Second action parameter.
 */
// Action HandlerVoteMatchStart(NativeVote hVote, VoteAction tAction, int iParam1, int iParam2)
// {
//     switch (tAction)
//     {
//         case VoteAction_Display:
//         {
//             char szConfigTitle[MAX_CONFIG_TITLE_LENGTH], sVoteDisplayMessage[128];

//             g_smConfigInfo.GetString(g_szTargetConfig, szConfigTitle, sizeof(szConfigTitle));

//             FormatEx(sVoteDisplayMessage, sizeof(sVoteDisplayMessage), "%T", "VOTE_MATCH_START", iParam1, szConfigTitle);

//             hVote.SetDetails(sVoteDisplayMessage);

//             return Plugin_Changed;
//         }

//         case VoteAction_Cancel: hVote.DisplayFail();

//         case VoteAction_Finish:
//         {
//             if (iParam1 == NATIVEVOTES_VOTE_NO)
//             {
//                 g_szTargetConfig[0] = '\0';
//                 hVote.DisplayFail();

//                 return Plugin_Continue;
//             }

//             ConfigManager_LoadConfig(g_szTargetConfig);
//             g_szTargetConfig[0] = '\0';

//             hVote.DisplayPass();
//         }

//         case VoteAction_End: hVote.Close();
//     }

//     return Plugin_Continue;
// }

/**
 * Called when a vote action is completed.
 *
 * @param hVote             The vote being acted upon.
 * @param tAction           The action of the vote.
 * @param iParam1           First action parameter.
 * @param iParam2           Second action parameter.
 */
// Action HandlerVoteMatchEnd(NativeVote hVote, VoteAction tAction, int iParam1, int iParam2)
// {
//     switch (tAction)
//     {
//         case VoteAction_Display:
//         {
//             char sVoteDisplayMessage[128];

//             char szConfigName[MAX_CONFIG_NAME_LENGTH], szConfigTitle[MAX_CONFIG_TITLE_LENGTH];
//             ConfigManager_GetConfigName(szConfigName, sizeof(szConfigName));

//             if (!g_smConfigInfo.GetString(szConfigName, szConfigTitle, sizeof(szConfigTitle))) {
//                 FormatEx(szConfigTitle, sizeof(szConfigTitle), "%T", "CONFIG_UNDEFINED", iParam1);
//             }

//             FormatEx(sVoteDisplayMessage, sizeof(sVoteDisplayMessage), "%T", "VOTE_MATCH_END", iParam1, szConfigTitle);

//             hVote.SetDetails(sVoteDisplayMessage);

//             return Plugin_Changed;
//         }

//         case VoteAction_Cancel: hVote.DisplayFail();

//         case VoteAction_Finish:
//         {
//             if (iParam1 == NATIVEVOTES_VOTE_NO)
//             {
//                 hVote.DisplayFail();

//                 return Plugin_Continue;
//             }

//             hVote.DisplayPass();

//             ConfigManager_UnloadConfig();
//         }

//         case VoteAction_End: hVote.Close();
//     }

//     return Plugin_Continue;
// }

/**
 *
 */
bool IsClientSpectator(int iClient) {
    return (GetClientTeam(iClient) == TEAM_SPECTATE);
}
