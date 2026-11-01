#include "fl_multi_engine_plugin.h"

#include "include/fl_multi_engine/fl_multi_engine_error_codes.h"

// This must be included before many other Windows headers.
#include <windows.h>

#include <flutter/method_channel.h>
#include <flutter/plugin_registrar.h>
#include <flutter/plugin_registrar_windows.h>
#include <flutter/standard_method_codec.h>

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
#include <utility>
#include <vector>

// 本文件实现 Windows 端的命名引擎管理：
// 1. 主引擎由 Flutter 工具注册插件后登记到 g_entries；
// 2. 新引擎在独立线程中创建，线程内维护自己的消息循环和平台通道；
// 3. 所有引擎均为 headless（无窗口），窗口渲染由宿主 App 或其他插件负责。
//
// Windows implementation of the named engine manager. Every engine runs headless on a
// dedicated thread with its own platform channel.
namespace fl_multi_engine {

void HandleEngineCall(const std::string& engine_name,
                      const flutter::MethodCall<flutter::EncodableValue>& call,
                      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);

namespace {

using EncodableMethodChannel = flutter::MethodChannel<flutter::EncodableValue>;

int64_t NowMillis() {
  return std::chrono::duration_cast<std::chrono::milliseconds>(
             std::chrono::system_clock::now().time_since_epoch())
      .count();
}

std::wstring ExecutableDirectory() {
  wchar_t buffer[MAX_PATH];
  DWORD length = GetModuleFileNameW(nullptr, buffer, MAX_PATH);
  std::wstring path(buffer, length);
  const size_t separator = path.find_last_of(L"\\/");
  return separator == std::wstring::npos ? path : path.substr(0, separator);
}

struct Entry {
  std::string name;
  std::string entrypoint;
  std::string state = "running";
  int64_t created_at = NowMillis();
  bool is_main = false;
  FlutterDesktopEngineRef engine = nullptr;
  std::unique_ptr<flutter::PluginRegistrar> registrar;
  std::unique_ptr<EncodableMethodChannel> channel;
  EncodableMethodChannel* channel_ptr = nullptr;
  std::thread thread;
  DWORD thread_id = 0;
  std::atomic<bool> shutdown{false};
  std::shared_ptr<std::promise<bool>> ready;
  // 保护 channel_ptr：发送方引擎线程与目标引擎线程可能同时访问。
  // Guards channel_ptr, which can be accessed from another engine thread.
  std::mutex channel_mutex;

  // 进程退出时静态表会析构 Entry，若线程仍可 join 会直接触发 std::terminate。
  // 因此析构时主动 detach，让引擎线程随进程一起结束。
  // A joinable thread would call std::terminate during static destruction, so detach it.
  ~Entry() {
    if (thread.joinable()) {
      thread.detach();
    }
  }
};

std::mutex g_mutex;
std::map<std::string, std::shared_ptr<Entry>> g_entries;

flutter::EncodableMap InfoToMap(const Entry& entry) {
  return flutter::EncodableMap{
      {flutter::EncodableValue("name"), flutter::EncodableValue(entry.name)},
      {flutter::EncodableValue("entrypoint"), flutter::EncodableValue(entry.entrypoint)},
      {flutter::EncodableValue("state"), flutter::EncodableValue(entry.state)},
      {flutter::EncodableValue("createdAt"), flutter::EncodableValue(entry.created_at)},
      {flutter::EncodableValue("isMain"), flutter::EncodableValue(entry.is_main)},
  };
}

const flutter::EncodableMap* ArgumentsOf(const flutter::MethodCall<flutter::EncodableValue>& call) {
  const flutter::EncodableValue* arguments = call.arguments();
  return arguments == nullptr ? nullptr : std::get_if<flutter::EncodableMap>(arguments);
}

std::string StringValue(const flutter::EncodableMap* arguments, const char* key) {
  if (arguments == nullptr) return {};
  const auto iterator = arguments->find(flutter::EncodableValue(key));
  if (iterator == arguments->end()) return {};
  const std::string* value = std::get_if<std::string>(&iterator->second);
  return value == nullptr ? std::string() : *value;
}

std::vector<std::string> StringListValue(const flutter::EncodableMap* arguments, const char* key) {
  std::vector<std::string> result;
  if (arguments == nullptr) return result;
  const auto iterator = arguments->find(flutter::EncodableValue(key));
  if (iterator == arguments->end()) return result;
  const flutter::EncodableList* values = std::get_if<flutter::EncodableList>(&iterator->second);
  if (values == nullptr) return result;
  for (const flutter::EncodableValue& value : *values) {
    const std::string* text = std::get_if<std::string>(&value);
    if (text != nullptr) result.push_back(*text);
  }
  return result;
}

flutter::EncodableMap MapValue(const flutter::EncodableMap* arguments, const char* key) {
  if (arguments == nullptr) return {};
  const auto iterator = arguments->find(flutter::EncodableValue(key));
  if (iterator == arguments->end()) return {};
  const flutter::EncodableMap* value = std::get_if<flutter::EncodableMap>(&iterator->second);
  return value == nullptr ? flutter::EncodableMap() : *value;
}

void Error(std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result,
           const std::string& code,
           const std::string& message) {
  result->Error(code, message);
}

// 在独立线程中创建 headless 引擎、安装 fl_multi_engine 通道并驱动消息循环。
// Creates the headless engine, installs the channel and runs the message loop.
void RunEngine(std::shared_ptr<Entry> entry, std::string entrypoint, std::vector<std::string> arguments) {
  entry->thread_id = GetCurrentThreadId();
  const std::wstring directory = ExecutableDirectory();
  const std::wstring assets = directory + L"\\data\\flutter_assets";
  const std::wstring icu = directory + L"\\data\\icudtl.dat";
  const std::wstring aot = directory + L"\\data\\app.so";

  std::vector<const char*> argv;
  argv.reserve(arguments.size());
  for (const std::string& argument : arguments) {
    argv.push_back(argument.c_str());
  }

  FlutterDesktopEngineProperties properties = {};
  properties.assets_path = assets.c_str();
  properties.icu_data_path = icu.c_str();
  properties.aot_library_path = aot.c_str();
  properties.dart_entrypoint = entrypoint.empty() ? nullptr : entrypoint.c_str();
  properties.dart_entrypoint_argc = static_cast<int>(argv.size());
  properties.dart_entrypoint_argv = argv.empty() ? nullptr : argv.data();
  properties.gpu_preference = static_cast<FlutterDesktopGpuPreference>(0);
  properties.ui_thread_policy = static_cast<FlutterDesktopUIThreadPolicy>(0);
  properties.accessibility_mode = static_cast<FlutterDesktopAccessibilityMode>(0);
  properties.impeller_switch = static_cast<FlutterDesktopImpellerSwitch>(0);

  FlutterDesktopEngineRef engine = FlutterDesktopEngineCreate(&properties);
  if (engine == nullptr) {
    entry->ready->set_value(false);
    return;
  }
  entry->engine = engine;
  if (!FlutterDesktopEngineRun(engine, nullptr)) {
    FlutterDesktopEngineDestroy(engine);
    entry->engine = nullptr;
    entry->ready->set_value(false);
    return;
  }

  FlutterDesktopPluginRegistrarRef core_registrar =
      FlutterDesktopEngineGetPluginRegistrar(engine, "fl_multi_engine");
  if (core_registrar == nullptr) {
    FlutterDesktopEngineDestroy(engine);
    entry->engine = nullptr;
    entry->ready->set_value(false);
    return;
  }
  entry->registrar = std::make_unique<flutter::PluginRegistrar>(core_registrar);
  auto channel = std::make_unique<EncodableMethodChannel>(
      entry->registrar->messenger(), "fl_multi_engine",
      &flutter::StandardMethodCodec::GetInstance());
  Entry* raw_entry = entry.get();
  channel->SetMethodCallHandler(
      [raw_entry](const flutter::MethodCall<flutter::EncodableValue>& call,
                  std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
        HandleEngineCall(raw_entry->name, call, std::move(result));
      });
  entry->channel_ptr = channel.get();
  entry->channel = std::move(channel);
  // 先创建线程消息队列再通知 ready，避免 create() 返回后 destroy() 的 PostThreadMessage
  // 因为队列尚不存在而失败，导致 join() 永久阻塞。
  // Create the thread message queue before signalling ready so a later PostThreadMessage
  // from destroy() cannot fail and block join() forever.
  MSG queue_probe;
  PeekMessage(&queue_probe, nullptr, 0, 0, PM_NOREMOVE);
  entry->ready->set_value(true);

  MSG message;
  while (!entry->shutdown && GetMessage(&message, nullptr, 0, 0) > 0) {
    TranslateMessage(&message);
    DispatchMessage(&message);
    FlutterDesktopEngineProcessMessages(engine);
  }

  {
    std::lock_guard<std::mutex> lock(entry->channel_mutex);
    entry->channel.reset();
    entry->channel_ptr = nullptr;
  }
  entry->registrar.reset();
  FlutterDesktopEngineDestroy(engine);
  entry->engine = nullptr;
}

void HandleEngineCall(const std::string& engine_name,
                      const flutter::MethodCall<flutter::EncodableValue>& call,
                      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);

std::shared_ptr<Entry> FindEntry(const std::string& name) {
  std::lock_guard<std::mutex> lock(g_mutex);
  const auto iterator = g_entries.find(name);
  return iterator == g_entries.end() ? nullptr : iterator->second;
}

// 按创建时间排序，保证与 Android / HarmonyOS 的注册顺序和 Darwin 的排序一致。
// Sorts by creation time so every platform returns engines in the same order.
std::vector<std::shared_ptr<Entry>> EntriesByCreation() {
  std::lock_guard<std::mutex> lock(g_mutex);
  std::vector<std::shared_ptr<Entry>> entries;
  entries.reserve(g_entries.size());
  for (const auto& pair : g_entries) {
    entries.push_back(pair.second);
  }
  std::sort(entries.begin(), entries.end(),
            [](const std::shared_ptr<Entry>& left, const std::shared_ptr<Entry>& right) {
              if (left->created_at != right->created_at) return left->created_at < right->created_at;
              return left->name < right->name;
            });
  return entries;
}

// 通知 Flutter 侧引擎列表发生变化；只发通知，不携带引擎数据。
// Notifies Flutter that the engine list changed; the notification carries no engine data.
void NotifyEnginesChanged() {
  std::shared_ptr<Entry> main_entry;
  {
    std::lock_guard<std::mutex> lock(g_mutex);
    const auto iterator = g_entries.find("main");
    if (iterator == g_entries.end()) return;
    main_entry = iterator->second;
  }
  std::lock_guard<std::mutex> channel_lock(main_entry->channel_mutex);
  if (main_entry->channel_ptr == nullptr) return;
  main_entry->channel_ptr->InvokeMethod("onEnginesChanged", nullptr);
}

// 创建并启动命名引擎；失败时通过 |error_code| / |error_message| 返回我们定义的错误码。
// Creates a named engine; failures are reported through our stable error codes.
std::shared_ptr<Entry> CreateEngineInternal(const std::string& name,
                                            const std::string& entrypoint,
                                            const std::vector<std::string>& arguments,
                                            std::string* error_code,
                                            std::string* error_message) {
  if (name.empty() || entrypoint.empty()) {
    *error_code = error_code::kInvalidName;
    *error_message = "The engine name and entry point must not be empty";
    return nullptr;
  }
  auto entry = std::make_shared<Entry>();
  entry->name = name;
  entry->entrypoint = entrypoint;
  entry->ready = std::make_shared<std::promise<bool>>();
  {
    std::lock_guard<std::mutex> lock(g_mutex);
    if (name == "main" || g_entries.find(name) != g_entries.end()) {
      *error_code = error_code::kEngineExists;
      *error_message = "The engine " + name + " already exists";
      return nullptr;
    }
    // 与存在性检查放在同一临界区，避免并发创建同名引擎时覆盖已有条目。
    // Insert under the same lock as the existence check so concurrent creates cannot overwrite.
    g_entries[name] = entry;
  }
  entry->thread = std::thread(RunEngine, entry, entrypoint, arguments);
  const bool created = entry->ready->get_future().get();
  if (!created) {
    {
      std::lock_guard<std::mutex> lock(g_mutex);
      g_entries.erase(name);
    }
    if (entry->thread.joinable()) entry->thread.join();
    *error_code = error_code::kCreateFailed;
    *error_message = "Unable to create the engine " + name;
    return nullptr;
  }

  NotifyEnginesChanged();
  return entry;
}

}  // namespace

// 所有平台通道方法（create / destroy / list / status / send 等）的统一分发入口。
// Dispatches every platform channel method (create / destroy / list / status / send ...).
void HandleEngineCall(const std::string& engine_name,
                      const flutter::MethodCall<flutter::EncodableValue>& call,
                      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  const std::string& method = call.method_name();
  const flutter::EncodableMap* arguments = ArgumentsOf(call);

  if (method == "currentEngineName") {
    result->Success(flutter::EncodableValue(engine_name));
    return;
  }

  if (method == "create") {
    const std::string name = StringValue(arguments, "name");
    const std::string entrypoint = StringValue(arguments, "entrypoint");
    const std::vector<std::string> entrypoint_arguments = StringListValue(arguments, "arguments");
    std::string code;
    std::string message;
    const auto entry = CreateEngineInternal(name, entrypoint, entrypoint_arguments, &code, &message);
    if (entry == nullptr) {
      Error(std::move(result), code, message);
      return;
    }
    // 只返回创建成功的唯一 ID，Dart 侧会重新拉取引擎列表并筛选。
    // Only return the unique ID; Dart re-fetches the engine list afterwards.
    result->Success(flutter::EncodableValue(entry->name));
    return;
  }

  if (method == "destroy") {
    const std::string name = StringValue(arguments, "name");
    if (name == "main") {
      Error(std::move(result), error_code::kMainEngineNotDestroyable, "The main engine cannot be destroyed");
      return;
    }
    result->Success(flutter::EncodableValue(DestroyEngine(name)));
    return;
  }

  if (method == "list") {
    flutter::EncodableList list;
    for (const auto& entry : EntriesByCreation()) {
      list.push_back(flutter::EncodableValue(InfoToMap(*entry)));
    }
    result->Success(flutter::EncodableValue(list));
    return;
  }

  if (method == "status") {
    const std::string name = StringValue(arguments, "name");
    const auto entry = FindEntry(name);
    if (entry == nullptr) {
      result->Success(flutter::EncodableValue());
    } else {
      result->Success(flutter::EncodableValue(InfoToMap(*entry)));
    }
    return;
  }

  if (method == "send") {
    const std::string target = StringValue(arguments, "target");
    const std::string message = StringValue(arguments, "method");
    const flutter::EncodableMap value = MapValue(arguments, "value");
    std::shared_ptr<Entry> entry;
    {
      std::lock_guard<std::mutex> lock(g_mutex);
      const auto iterator = g_entries.find(target);
      if (iterator != g_entries.end()) entry = iterator->second;
    }
    if (entry == nullptr) {
      result->Success(flutter::EncodableValue(0));
      return;
    }
    auto payload = std::make_unique<flutter::EncodableValue>(flutter::EncodableMap{
        {flutter::EncodableValue("sender"), flutter::EncodableValue(engine_name)},
        {flutter::EncodableValue("method"), flutter::EncodableValue(message.empty() ? "message" : message)},
        {flutter::EncodableValue("value"), flutter::EncodableValue(value)},
    });
    // 持有 entry 的引用并在锁内调用，避免目标引擎销毁时把 channel 置空后继续使用。
    // Keep the entry alive and invoke under the lock so engine teardown cannot invalidate it.
    std::lock_guard<std::mutex> channel_lock(entry->channel_mutex);
    if (entry->channel_ptr == nullptr) {
      result->Success(flutter::EncodableValue(0));
      return;
    }
    entry->channel_ptr->InvokeMethod("onMessage", std::move(payload), nullptr);
    result->Success(flutter::EncodableValue(1));
    return;
  }

  result->NotImplemented();
}

EngineInfo CreateEngine(const std::string& name,
                        const std::string& entrypoint,
                        const std::vector<std::string>& arguments) {
  std::string code;
  std::string message;
  const auto entry = CreateEngineInternal(name, entrypoint, arguments, &code, &message);
  if (entry == nullptr) {
    throw FlMultiEngineException{code, message};
  }
  return EngineInfo{entry->name, entry->entrypoint, entry->state, entry->created_at, entry->is_main};
}

std::vector<EngineInfo> ListEngines() {
  std::vector<EngineInfo> result;
  for (const auto& entry : EntriesByCreation()) {
    result.push_back(EngineInfo{entry->name, entry->entrypoint, entry->state, entry->created_at, entry->is_main});
  }
  return result;
}

bool StatusEngine(const std::string& name, EngineInfo* info) {
  if (info == nullptr) return false;
  std::lock_guard<std::mutex> lock(g_mutex);
  const auto iterator = g_entries.find(name);
  if (iterator == g_entries.end()) return false;
  const Entry& entry = *iterator->second;
  *info = EngineInfo{entry.name, entry.entrypoint, entry.state, entry.created_at, entry.is_main};
  return true;
}

FlutterDesktopEngineRef GetEngine(const std::string& name) {
  std::lock_guard<std::mutex> lock(g_mutex);
  const auto iterator = g_entries.find(name);
  return iterator == g_entries.end() ? nullptr : iterator->second->engine;
}

bool DestroyEngine(const std::string& name) {
  std::shared_ptr<Entry> entry;
  {
    std::lock_guard<std::mutex> lock(g_mutex);
    const auto iterator = g_entries.find(name);
    if (iterator == g_entries.end() || iterator->second->is_main) return false;
    entry = iterator->second;
    g_entries.erase(iterator);
  }
  entry->shutdown = true;
  const bool destroying_self = entry->thread_id == GetCurrentThreadId();
  if (entry->thread_id != 0) PostThreadMessage(entry->thread_id, WM_QUIT, 0, 0);
  if (entry->thread.joinable()) {
    if (destroying_self) {
      // 在引擎自己的平台线程上销毁自己时不能 join，直接 detach 让线程随消息循环退出。
      // Joining the current thread would deadlock, so detach and let the message loop exit.
      entry->thread.detach();
    } else {
      entry->thread.join();
    }
  }
  NotifyEnginesChanged();
  return true;
}

FlMultiEnginePlugin::FlMultiEnginePlugin(std::string engine_name)
    : engine_name_(std::move(engine_name)) {}

FlMultiEnginePlugin::~FlMultiEnginePlugin() = default;

void FlMultiEnginePlugin::RegisterWithRegistrar(flutter::PluginRegistrarWindows* registrar) {
  auto plugin = std::make_unique<FlMultiEnginePlugin>("main");
  auto channel = std::make_unique<EncodableMethodChannel>(
      registrar->messenger(), "fl_multi_engine",
      &flutter::StandardMethodCodec::GetInstance());
  FlMultiEnginePlugin* raw_plugin = plugin.get();
  channel->SetMethodCallHandler(
      [raw_plugin](const flutter::MethodCall<flutter::EncodableValue>& call,
                   std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
        raw_plugin->HandleMethodCall(call, std::move(result));
      });
  plugin->channel_ = std::move(channel);

  {
    std::lock_guard<std::mutex> lock(g_mutex);
    if (g_entries.find("main") == g_entries.end()) {
      auto entry = std::make_shared<Entry>();
      entry->name = "main";
      entry->entrypoint = "main";
      entry->is_main = true;
      entry->channel_ptr = plugin->channel_.get();
      g_entries["main"] = entry;
    }
  }

  registrar->AddPlugin(std::move(plugin));
}

void FlMultiEnginePlugin::HandleMethodCall(
    const flutter::MethodCall<flutter::EncodableValue>& method_call,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  HandleEngineCall(engine_name_, method_call, std::move(result));
}

}  // namespace fl_multi_engine
