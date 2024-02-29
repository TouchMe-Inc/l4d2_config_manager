#if defined _confogl_core_included
	#endinput
#endif
#define _confogl_core_included

native bool Confogl_IsConfigLoaded();
native void Confogl_GetConfigName(char[] sConfigName, int iLength);
native void Confogl_LoadConfig(const char[] sConfigName);
native void Confogl_UnloadConfig();

public SharedPlugin __pl_confogl_core =
{
	name = "confogl_core",
	file = "confogl_core.smx",
#if defined REQUIRE_PLUGIN
	required = 1,
#else
	required = 0,
#endif
};

#if !defined REQUIRE_PLUGIN
public void __pl_confogl_SetNTVOptional()
{
	MarkNativeAsOptional("Confogl_IsConfigLoaded");
	MarkNativeAsOptional("Confogl_GetConfigName");
	MarkNativeAsOptional("Confogl_LoadConfig");
	MarkNativeAsOptional("Confogl_UnloadConfig");
}
#endif