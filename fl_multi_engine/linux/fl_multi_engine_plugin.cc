#include "include/fl_multi_engine/fl_multi_engine_plugin.h"

#include "include/fl_multi_engine/fl_multi_engine_error_codes.h"

#include <flutter_linux/flutter_linux.h>
#include <gtk/gtk.h>

#include <algorithm>
#include <atomic>
#include <chrono>
#include <cstring>
#include <future>
#include <map>
#include <memory>
#include <mutex>
#include <string>
#include <thread>
#include <vector>

// 本文件实现 Linux 端的命名引擎管理：
// 1. 每个新引擎运行在独立线程中，并拥有自己的 GMainContext / GMainLoop；
// 2. Linux 嵌入层不暴露自定义 entrypoint，因此把 entrypoint 与引擎名作为 Dart 参数传入，
//    App 的 main(List<String> args) 需要自行分发；
// 3. 所有引擎均为 headless，窗口渲染由宿主 App 或其他插件负责。
//
// Linux implementation of the named engine manager. Every engine runs headless on a dedicated
// thread with its own main context; the entrypoint is passed as a Dart argument.

#define FL_MULTI_ENGINE_PLUGIN(obj) \
  (G_TYPE_CHECK_INSTANCE_CAST((obj), fl_multi_engine_plugin_get_type(), FlMultiEnginePlugin))

void HandleLinuxMethodCall(const std::string& engine_name, FlMethodCall* method_call);

struct ChannelContext {
  explicit ChannelContext(std::string value) : name(std::move(value)) {}
  std::string name;
};

struct EngineEntry {
  std::string name;
  std::string entrypoint;
  std::string state = "running";
  int64_t created_at;
  bool is_main = false;
  FlEngine* engine = nullptr;
  FlMethodChannel* channel = nullptr;
  GMainContext* context = nullptr;
  GMainLoop* loop = nullptr;
  std::thread thread;
  std::atomic<bool> shutdown{false};
  std::shared_ptr<std::promise<bool>> ready;

  EngineEntry() {
    created_at = std::chrono::duration_cast<std::chrono::milliseconds>(
                     std::chrono::system_clock::now().time_since_epoch())
                     .count();
  }

  // 静态表析构时若引擎线程仍可 join，会触发 std::terminate，因此主动 detach。
  // Detach a still-joinable engine thread to avoid std::terminate at static destruction.
  ~EngineEntry() {
    if (thread.joinable()) {
      thread.detach();
    }
  }
};

namespace {

std::mutex g_mutex;
std::map<std::string, std::shared_ptr<EngineEntry>> g_entries;

std::string StringValue(FlValue* map, const char* key) {
  if (map == nullptr || fl_value_get_type(map) != FL_VALUE_TYPE_MAP) return {};
  FlValue* value = fl_value_lookup_string(map, key);
  if (value == nullptr || fl_value_get_type(value) != FL_VALUE_TYPE_STRING) return {};
  return std::string(fl_value_get_string(value));
}

std::vector<std::string> StringListValue(FlValue* map, const char* key) {
  std::vector<std::string> result;
  if (map == nullptr || fl_value_get_type(map) != FL_VALUE_TYPE_MAP) return result;
  FlValue* value = fl_value_lookup_string(map, key);
  if (value == nullptr || fl_value_get_type(value) != FL_VALUE_TYPE_LIST) return result;
  for (size_t index = 0; index < fl_value_get_length(value); index++) {
    FlValue* item = fl_value_get_list_value(value, index);
    if (fl_value_get_type(item) == FL_VALUE_TYPE_STRING) {
      result.push_back(fl_value_get_string(item));
    }
  }
  return result;
}

FlValue* NewInfoMap(const EngineEntry& entry) {
  FlValue* map = fl_value_new_map();
  fl_value_set_string_take(map, "name", fl_value_new_string(entry.name.c_str()));
  fl_value_set_string_take(map, "entrypoint", fl_value_new_string(entry.entrypoint.c_str()));
  fl_value_set_string_take(map, "state", fl_value_new_string(entry.state.c_str()));
  fl_value_set_string_take(map, "createdAt", fl_value_new_int(entry.created_at));
  fl_value_set_string_take(map, "isMain", fl_value_new_bool(entry.is_main));
  return map;
}

void RespondError(FlMethodCall* call, const gchar* code, const gchar* message) {
  g_autoptr(FlMethodResponse) response = fl_method_error_response_new(code, message, nullptr);
  fl_method_call_respond(call, response, nullptr);
}

void RespondSuccess(FlMethodCall* call, FlValue* value) {
  g_autoptr(FlMethodResponse) response = fl_method_success_response_new(value);
  fl_method_call_respond(call, response, nullptr);
  if (value != nullptr) fl_value_unref(value);
}

void QuitLoop(gpointer data) {
  g_main_loop_quit(static_cast<GMainLoop*>(data));
}

void EngineMethodCallCb(FlMethodChannel* channel, FlMethodCall* method_call, gpointer user_data) {
  ChannelContext* current = static_cast<ChannelContext*>(user_data);
  HandleLinuxMethodCall(current->name, method_call);
}

void ChannelContextDestroy(gpointer data) {
  delete static_cast<ChannelContext*>(data);
}

std::shared_ptr<EngineEntry> FindEntry(const std::string& name) {
  std::lock_guard<std::mutex> lock(g_mutex);
  auto iterator = g_entries.find(name);
  return iterator == g_entries.end() ? nullptr : iterator->second;
}

// 按创建时间排序，保证与 Android / HarmonyOS 的注册顺序和 Darwin 的排序一致。
// Sorts by creation time so every platform returns engines in the same order.
std::vector<std::shared_ptr<EngineEntry>> EntriesByCreation() {
  std::lock_guard<std::mutex> lock(g_mutex);
  std::vector<std::shared_ptr<EngineEntry>> entries;
  entries.reserve(g_entries.size());
  for (const auto& pair : g_entries) {
    entries.push_back(pair.second);
  }
  std::sort(entries.begin(), entries.end(),
            [](const std::shared_ptr<EngineEntry>& left, const std::shared_ptr<EngineEntry>& right) {
              if (left->created_at != right->created_at) return left->created_at < right->created_at;
              return left->name < right->name;
            });
  return entries;
}

struct EnginesChangedData {
  FlMethodChannel* channel;
};

gboolean NotifyEnginesChangedCb(gpointer data) {
  auto* notify = static_cast<EnginesChangedData*>(data);
  fl_method_channel_invoke_method(notify->channel, "onEnginesChanged", nullptr, nullptr, nullptr, nullptr);
  return G_SOURCE_REMOVE;
}

void EnginesChangedDataDestroy(gpointer data) {
  auto* notify = static_cast<EnginesChangedData*>(data);
  g_object_unref(notify->channel);
  delete notify;
}

// 通知 Flutter 侧引擎列表发生变化；只发通知，不携带引擎数据。
// Notifies Flutter that the engine list changed; the notification carries no engine data.
void NotifyEnginesChanged() {
  FlMethodChannel* channel = nullptr;
  {
    std::lock_guard<std::mutex> lock(g_mutex);
    auto iterator = g_entries.find("main");
    if (iterator == g_entries.end() || iterator->second->channel == nullptr) return;
    channel = FL_METHOD_CHANNEL(g_object_ref(iterator->second->channel));
  }
  auto* notify = new EnginesChangedData{channel};
  // 通过默认主上下文的空闲任务延后执行，确保通知在 create/destroy 结果之后到达 Flutter。
  // Defer the notification to the default main context so it arrives after the result.
  g_idle_add_full(G_PRIORITY_DEFAULT_IDLE, NotifyEnginesChangedCb, notify, EnginesChangedDataDestroy);
}

// 引擎线程入口：创建 headless 引擎、安装通道、运行自己的 GMainLoop。
// Entry point of an engine thread: creates the headless engine and runs its main loop.
void EngineThread(std::shared_ptr<EngineEntry> entry,
                  std::string entrypoint,
                  std::vector<std::string> arguments) {
  GMainContext* context = g_main_context_new();
  g_main_context_push_thread_default(context);

  FlDartProject* project = fl_dart_project_new();
  std::vector<std::string> all_arguments;
  all_arguments.push_back("--fl-multi-engine-entrypoint=" + entrypoint);
  all_arguments.push_back("--fl-multi-engine-name=" + entry->name);
  for (const std::string& argument : arguments) all_arguments.push_back(argument);

  std::vector<char*> argv;
  argv.reserve(all_arguments.size() + 1);
  for (std::string& argument : all_arguments) argv.push_back(argument.data());
  argv.push_back(nullptr);
  fl_dart_project_set_dart_entrypoint_arguments(project, argv.data());

  FlEngine* engine = fl_engine_new_headless(project);
  g_object_unref(project);
  if (engine == nullptr) {
    entry->ready->set_value(false);
    g_main_context_pop_thread_default(context);
    g_main_context_unref(context);
    return;
  }
  entry->engine = engine;

  FlBinaryMessenger* messenger = fl_engine_get_binary_messenger(engine);
  g_autoptr(FlStandardMethodCodec) codec = fl_standard_method_codec_new();
  FlMethodChannel* channel = fl_method_channel_new(messenger, "fl_multi_engine", FL_METHOD_CODEC(codec));
  ChannelContext* channel_context = new ChannelContext(entry->name);
  fl_method_channel_set_method_call_handler(
      channel, EngineMethodCallCb, channel_context, ChannelContextDestroy);

  GMainLoop* loop = g_main_loop_new(context, FALSE);
  entry->context = context;
  entry->loop = loop;
  entry->channel = channel;
  entry->ready->set_value(true);

  g_main_loop_run(loop);

  {
    // 与 send 共用同一把锁，避免其他引擎线程在通道被释放后继续调用。
    // Share the registry lock with send so no other thread uses the channel after teardown.
    std::lock_guard<std::mutex> lock(g_mutex);
    entry->channel = nullptr;
  }
  g_object_unref(channel);
  g_main_loop_unref(loop);
  g_object_unref(engine);
  entry->engine = nullptr;
  entry->loop = nullptr;
  entry->context = nullptr;
  g_main_context_pop_thread_default(context);
  g_main_context_unref(context);
}

}  // namespace

void HandleLinuxMethodCall(const std::string& engine_name, FlMethodCall* method_call);

bool CreateEngineNative(const std::string& name,
                        const std::string& entrypoint,
                        const std::vector<std::string>& arguments,
                        GError** error) {
  auto entry = std::make_shared<EngineEntry>();
  entry->name = name;
  entry->entrypoint = entrypoint;
  entry->ready = std::make_shared<std::promise<bool>>();
  {
    std::lock_guard<std::mutex> lock(g_mutex);
    if (name == "main" || g_entries.find(name) != g_entries.end()) {
      g_set_error(error, g_quark_from_static_string("fl_multi_engine"), 1, "The engine %s already exists",
                  name.c_str());
      return false;
    }
    // 与存在性检查放在同一临界区，避免并发创建同名引擎时覆盖已有条目。
    // Insert under the same lock as the existence check so concurrent creates cannot overwrite.
    g_entries[name] = entry;
  }

  entry->thread = std::thread(EngineThread, entry, entrypoint, arguments);
  if (!entry->ready->get_future().get()) {
    {
      std::lock_guard<std::mutex> lock(g_mutex);
      g_entries.erase(name);
    }
    if (entry->thread.joinable()) entry->thread.join();
    g_set_error(error, g_quark_from_static_string("fl_multi_engine"), 1, "Unable to create the engine %s",
                name.c_str());
    return false;
  }
  NotifyEnginesChanged();
  return true;
}

bool DestroyEngineNative(const std::string& name) {
  std::shared_ptr<EngineEntry> entry;
  {
    std::lock_guard<std::mutex> lock(g_mutex);
    auto iterator = g_entries.find(name);
    if (iterator == g_entries.end() || iterator->second->is_main) return false;
    entry = iterator->second;
    g_entries.erase(iterator);
  }
  entry->shutdown = true;
  if (entry->context != nullptr && entry->loop != nullptr) {
    g_main_context_invoke(entry->context, QuitLoop, entry->loop);
  }
  if (entry->thread.joinable()) {
    if (entry->thread.get_id() == std::this_thread::get_id()) {
      // 在引擎自己的线程上销毁自己时不能 join，直接 detach 让主循环退出。
      // Joining the current thread would deadlock, so detach and let the main loop exit.
      entry->thread.detach();
    } else {
      entry->thread.join();
    }
  }
  NotifyEnginesChanged();
  return true;
}

void HandleLinuxMethodCall(const std::string& engine_name, FlMethodCall* method_call) {
  const gchar* method = fl_method_call_get_name(method_call);
  FlValue* arguments = fl_method_call_get_args(method_call);

  if (g_strcmp0(method, "currentEngineName") == 0) {
    RespondSuccess(method_call, fl_value_new_string(engine_name.c_str()));
    return;
  }

  if (g_strcmp0(method, "create") == 0) {
    const std::string name = StringValue(arguments, "name");
    const std::string entrypoint = StringValue(arguments, "entrypoint");
    const std::vector<std::string> entrypoint_arguments = StringListValue(arguments, "arguments");
    if (name.empty() || entrypoint.empty()) {
      RespondError(method_call, fl_multi_engine::error_code::kInvalidName,
                   "The engine name and entry point must not be empty");
      return;
    }
    if (name == "main" || FindEntry(name) != nullptr) {
      const std::string message = "The engine " + name + " already exists";
      RespondError(method_call, fl_multi_engine::error_code::kEngineExists, message.c_str());
      return;
    }
    GError* error = nullptr;
    if (!CreateEngineNative(name, entrypoint, entrypoint_arguments, &error)) {
      RespondError(method_call, fl_multi_engine::error_code::kCreateFailed,
                   error == nullptr ? "Unable to create the engine" : error->message);
      if (error != nullptr) g_error_free(error);
      return;
    }
    // 只返回创建成功的唯一 ID，Dart 侧会重新拉取引擎列表并筛选。
    // Only return the unique ID; Dart re-fetches the engine list afterwards.
    RespondSuccess(method_call, fl_value_new_string(name.c_str()));
    return;
  }

  if (g_strcmp0(method, "destroy") == 0) {
    const std::string name = StringValue(arguments, "name");
    if (name == "main") {
      RespondError(method_call, fl_multi_engine::error_code::kMainEngineNotDestroyable,
                   "The main engine cannot be destroyed");
      return;
    }
    RespondSuccess(method_call, fl_value_new_bool(DestroyEngineNative(name)));
    return;
  }

  if (g_strcmp0(method, "list") == 0) {
    FlValue* list = fl_value_new_list();
    for (const auto& entry : EntriesByCreation()) {
      fl_value_append_take(list, NewInfoMap(*entry));
    }
    RespondSuccess(method_call, list);
    return;
  }

  if (g_strcmp0(method, "status") == 0) {
    const std::string name = StringValue(arguments, "name");
    const auto entry = FindEntry(name);
    RespondSuccess(method_call, entry == nullptr ? fl_value_new_null() : NewInfoMap(*entry));
    return;
  }

  if (g_strcmp0(method, "send") == 0) {
    const std::string target = StringValue(arguments, "target");
    const std::string message = StringValue(arguments, "method");
    FlValue* value = nullptr;
    if (arguments != nullptr && fl_value_get_type(arguments) == FL_VALUE_TYPE_MAP) {
      value = fl_value_lookup_string(arguments, "value");
    }
    FlValue* payload = fl_value_new_map();
    fl_value_set_string_take(payload, "sender", fl_value_new_string(engine_name.c_str()));
    fl_value_set_string_take(payload, "method", fl_value_new_string(message.empty() ? "message" : message.c_str()));
    fl_value_set_string_take(payload, "value", value == nullptr ? fl_value_new_null() : fl_value_ref(value));
    // 在注册表锁内调用，避免目标引擎销毁时把通道置空后继续使用。
    // Invoke under the registry lock so engine teardown cannot invalidate the channel.
    std::lock_guard<std::mutex> lock(g_mutex);
    const auto iterator = g_entries.find(target);
    if (iterator == g_entries.end() || iterator->second->channel == nullptr) {
      fl_value_unref(payload);
      RespondSuccess(method_call, fl_value_new_int(0));
      return;
    }
    fl_method_channel_invoke_method(iterator->second->channel, "onMessage", payload, nullptr, nullptr, nullptr);
    fl_value_unref(payload);
    RespondSuccess(method_call, fl_value_new_int(1));
    return;
  }

  g_autoptr(FlMethodResponse) response = fl_method_not_implemented_response_new();
  fl_method_call_respond(method_call, response, nullptr);
}

// ===== Flutter plugin entry point =====

struct _FlMultiEnginePlugin {
  GObject parent_instance;
  FlMethodChannel* channel;
};

G_DEFINE_TYPE(FlMultiEnginePlugin, fl_multi_engine_plugin, g_object_get_type())

static void fl_multi_engine_plugin_dispose(GObject* object) {
  FlMultiEnginePlugin* self = FL_MULTI_ENGINE_PLUGIN(object);
  g_clear_object(&self->channel);
  G_OBJECT_CLASS(fl_multi_engine_plugin_parent_class)->dispose(object);
}

static void fl_multi_engine_plugin_class_init(FlMultiEnginePluginClass* klass) {
  G_OBJECT_CLASS(klass)->dispose = fl_multi_engine_plugin_dispose;
}

static void fl_multi_engine_plugin_init(FlMultiEnginePlugin* self) {
  self->channel = nullptr;
}

static void main_method_call_cb(FlMethodChannel* channel, FlMethodCall* method_call, gpointer user_data) {
  HandleLinuxMethodCall("main", method_call);
}

void fl_multi_engine_plugin_register_with_registrar(FlPluginRegistrar* registrar) {
  FlMultiEnginePlugin* plugin =
      FL_MULTI_ENGINE_PLUGIN(g_object_new(fl_multi_engine_plugin_get_type(), nullptr));

  g_autoptr(FlStandardMethodCodec) codec = fl_standard_method_codec_new();
  FlBinaryMessenger* messenger = fl_plugin_registrar_get_messenger(registrar);
  FlMethodChannel* channel =
      fl_method_channel_new(messenger, "fl_multi_engine", FL_METHOD_CODEC(codec));
  fl_method_channel_set_method_call_handler(channel, main_method_call_cb, g_object_ref(plugin), g_object_unref);
  plugin->channel = FL_METHOD_CHANNEL(g_object_ref(channel));

  {
    std::lock_guard<std::mutex> lock(g_mutex);
    if (g_entries.find("main") == g_entries.end()) {
      auto entry = std::make_shared<EngineEntry>();
      entry->name = "main";
      entry->entrypoint = "main";
      entry->is_main = true;
      entry->channel = plugin->channel;
      g_entries["main"] = entry;
    }
  }

  g_object_unref(channel);
  g_object_unref(plugin);
}

// ===== Native API =====

FlEngine* fl_multi_engine_get_engine(const gchar* name) {
  const auto entry = FindEntry(name == nullptr ? "" : name);
  return entry == nullptr ? nullptr : entry->engine;
}

gboolean fl_multi_engine_destroy_engine(const gchar* name) {
  return DestroyEngineNative(name == nullptr ? "" : name) ? TRUE : FALSE;
}

FlValue* fl_multi_engine_list_engines() {
  FlValue* list = fl_value_new_list();
  for (const auto& entry : EntriesByCreation()) {
    fl_value_append_take(list, NewInfoMap(*entry));
  }
  return list;
}

FlValue* fl_multi_engine_get_engine_status(const gchar* name) {
  const auto entry = FindEntry(name == nullptr ? "" : name);
  return entry == nullptr ? nullptr : NewInfoMap(*entry);
}

FlValue* fl_multi_engine_create_engine(const gchar* name,
                                       const gchar* entrypoint,
                                       const gchar** arguments,
                                       GError** error) {
  std::vector<std::string> values;
  if (arguments != nullptr) {
    for (const gchar** argument = arguments; *argument != nullptr; argument++) {
      values.push_back(*argument);
    }
  }
  const std::string engine_name = name == nullptr ? "" : name;
  const std::string engine_entrypoint = entrypoint == nullptr ? "" : entrypoint;
  if (engine_name.empty() || engine_entrypoint.empty()) {
    g_set_error(error, g_quark_from_static_string("fl_multi_engine"), 1,
                "The engine name and entry point must not be empty");
    return nullptr;
  }
  if (!CreateEngineNative(engine_name, engine_entrypoint, values, error)) {
    return nullptr;
  }
  const auto entry = FindEntry(engine_name);
  return entry == nullptr ? nullptr : NewInfoMap(*entry);
}
