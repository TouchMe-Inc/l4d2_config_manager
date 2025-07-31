# About config_manager
The plugin allows you to run configs located in the `configs/config_manager` folder.

> [!IMPORTANT]
> The plugin only provides API

### Commands (config only)
* `config_manager_addcvar <cvar> <value>` - set and lock convar value.
* `config_manager_deletecvar <cvar>` - unlock and return original value.
* `config_manager_resetcvars` - unlock and return original value for all convars.

### Config struct
* `configs/config_manager/<config_path>/config_load.cfg` - Commands executed by the server when running the config.
* `configs/config_manager/<config_path>/config_unload.cfg` - Commands executed by the server when 

> [!IMPORTANT]
>  The folder hierarchy can be anything. Like `configs/config_manager/zonemod/1v1/config_load.cfg`

# About cm_match
The plugin provides a menu for creating votes for changing the config.

### Commands
* `!match` - Show menu with configs.
* `!match <alias>` - Load config by alias.
* `!rmatch` - Unload current config.

### Config list
To add a config you need:
1. Open `addons/sourcemod/configs/cm_match.txt`;
2. Create a category;
3. Create a item with `name` = `<config_path>`.
4. Create the `configs/config_manager/<config_path>/info.txt` file:
```ini
ConfigInfo
{
    "name"    "My config name"
    "alias"   "megacfg" // !match megacfg
    "version" "v1.0"
    "author"  "TouchMe"
    "description"
    {
        "space" " "
        "info" "  {green}About my config:"
        "info" "    └ Removal of all Tier 2 weapons for better gameplay balance"
        "space" " "
    }
}
```



