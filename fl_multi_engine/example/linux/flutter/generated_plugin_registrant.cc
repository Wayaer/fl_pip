//
//  Generated file. Do not edit.
//

// clang-format off

#include "generated_plugin_registrant.h"

#include <fl_multi_engine/fl_multi_engine_plugin.h>

void fl_register_plugins(FlPluginRegistry* registry) {
  g_autoptr(FlPluginRegistrar) fl_multi_engine_registrar =
      fl_plugin_registry_get_registrar_for_plugin(registry, "FlMultiEnginePlugin");
  fl_multi_engine_plugin_register_with_registrar(fl_multi_engine_registrar);
}
