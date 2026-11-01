#include "include/fl_multi_engine/fl_multi_engine_plugin_c_api.h"

#include <flutter/plugin_registrar_windows.h>

#include "fl_multi_engine_plugin.h"

void FlMultiEnginePluginCApiRegisterWithRegistrar(
    FlutterDesktopPluginRegistrarRef registrar) {
  fl_multi_engine::FlMultiEnginePlugin::RegisterWithRegistrar(
      flutter::PluginRegistrarManager::GetInstance()
          ->GetRegistrar<flutter::PluginRegistrarWindows>(registrar));
}
