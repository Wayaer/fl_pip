#ifndef FLUTTER_PLUGIN_FL_MULTI_ENGINE_PLUGIN_H_
#define FLUTTER_PLUGIN_FL_MULTI_ENGINE_PLUGIN_H_

#include <flutter_linux/flutter_linux.h>

G_BEGIN_DECLS

#ifdef FLUTTER_PLUGIN_IMPL
#define FLUTTER_PLUGIN_EXPORT __attribute__((visibility("default")))
#else
#define FLUTTER_PLUGIN_EXPORT
#endif

typedef struct _FlMultiEnginePlugin FlMultiEnginePlugin;
typedef struct {
  GObjectClass parent_class;
} FlMultiEnginePluginClass;

FLUTTER_PLUGIN_EXPORT GType fl_multi_engine_plugin_get_type();

FLUTTER_PLUGIN_EXPORT void fl_multi_engine_plugin_register_with_registrar(
    FlPluginRegistrar* registrar);

/** 返回指定引擎，不存在时返回 NULL。 / Returns the running engine called @name, or NULL. */
FLUTTER_PLUGIN_EXPORT FlEngine* fl_multi_engine_get_engine(const gchar* name);

/** 销毁指定引擎；主引擎不会被销毁。 / Destroys the engine called @name. */
FLUTTER_PLUGIN_EXPORT gboolean fl_multi_engine_destroy_engine(const gchar* name);

/** 返回所有已注册引擎的信息列表。 / Returns a list describing every registered engine. */
FLUTTER_PLUGIN_EXPORT FlValue* fl_multi_engine_list_engines();

/** 返回指定引擎的信息 Map，不存在时返回 NULL。
 *  Returns the info map of @name, or NULL when it does not exist. */
FLUTTER_PLUGIN_EXPORT FlValue* fl_multi_engine_get_engine_status(const gchar* name);

/** 创建 headless 引擎并返回其信息 Map；失败时返回 NULL 并设置 @error。
 *  @arguments 必须是以 NULL 结尾的字符串数组。
 *
 *  Creates a headless engine and returns its info map, or NULL on failure.
 *  @arguments must be a NULL-terminated array. */
FLUTTER_PLUGIN_EXPORT FlValue* fl_multi_engine_create_engine(
    const gchar* name,
    const gchar* entrypoint,
    const gchar** arguments,
    GError** error);

G_END_DECLS

#endif  // FLUTTER_PLUGIN_FL_MULTI_ENGINE_PLUGIN_H_
