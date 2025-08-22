#include "include/river_player/river_player_plugin_c_api.h"

#include <flutter/plugin_registrar_windows.h>

#include "river_player_plugin.h"

void RiverPlayerPluginCApiRegisterWithRegistrar(
    FlutterDesktopPluginRegistrarRef registrar) {
  river_player::RiverPlayerPlugin::RegisterWithRegistrar(
      flutter::PluginRegistrarManager::GetInstance()
          ->GetRegistrar<flutter::PluginRegistrarWindows>(registrar));
}