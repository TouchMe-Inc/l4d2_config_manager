#if defined _config_manager_included
	#endinput
#endif
#define _config_manager_included

native void ConfigManager_BuildConfigPath(char szFullConfigPath[PLATFORM_MAX_PATH], const char[] szConfigPath);
native bool ConfigManager_IsConfigLoaded();
native void ConfigManager_GetConfigPath(char[] szConfigPath, int iMaxLength);
native void ConfigManager_LoadConfig(const char[] szConfigPath);
native void ConfigManager_UnloadConfig();

forward void ConfigManager_OnLoadConfig();
forward void ConfigManager_OnUnloadConfig();

public SharedPlugin __pl_config_manager =
{
	name = "config_manager",
	file = "config_manager.smx",
#if defined REQUIRE_PLUGIN
	required = 1,
#else
	required = 0,
#endif
};

#if !defined REQUIRE_PLUGIN
public void __pl_config_manager_SetNTVOptional()
{
	MarkNativeAsOptional("ConfigManager_BuildConfigPath")
	MarkNativeAsOptional("ConfigManager_IsConfigLoaded");
	MarkNativeAsOptional("ConfigManager_GetConfigPath");
	MarkNativeAsOptional("ConfigManager_LoadConfig");
	MarkNativeAsOptional("ConfigManager_UnloadConfig");
}
#endif
