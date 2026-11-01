#ifndef FLUTTER_PLUGIN_FL_MULTI_ENGINE_PLUGIN_H_
#define FLUTTER_PLUGIN_FL_MULTI_ENGINE_PLUGIN_H_

#include <flutter/method_channel.h>
#include <flutter/plugin_registrar_windows.h>
#include <flutter_windows.h>

#include <cstdint>
#include <memory>
#include <string>
#include <vector>

#ifndef FLUTTER_PLUGIN_EXPORT
#ifdef FLUTTER_PLUGIN_IMPL
#define FLUTTER_PLUGIN_EXPORT __declspec(dllexport)
#else
#define FLUTTER_PLUGIN_EXPORT __declspec(dllimport)
#endif
#endif

namespace fl_multi_engine {

/// 描述一个由 fl_multi_engine 管理的引擎。 / Describes an engine managed by fl_multi_engine.
struct EngineInfo {
  std::string name;
  std::string entrypoint;
  std::string state;
  int64_t created_at;
  bool is_main;
};

/// 引擎管理器抛出的错误，code 与 Dart 侧的 FlMultiEngineErrorCode 一一对应。
/// An error reported by the engine manager; the code matches FlMultiEngineErrorCode on Dart.
struct FlMultiEngineException {
  std::string code;
  std::string message;
};

/// 创建并启动一个运行 |entrypoint| 的命名引擎；失败时抛出 FlMultiEngineException。
/// Creates and starts a named engine; throws FlMultiEngineException on failure.
FLUTTER_PLUGIN_EXPORT EngineInfo CreateEngine(const std::string& name,
                                              const std::string& entrypoint,
                                              const std::vector<std::string>& arguments);

/// 返回所有已注册引擎（包含主引擎）。 / Returns every registered engine.
FLUTTER_PLUGIN_EXPORT std::vector<EngineInfo> ListEngines();

/// 返回指定引擎的信息，不存在时返回 false。
/// Fills |info| with the engine called |name|; returns false when it does not exist.
FLUTTER_PLUGIN_EXPORT bool StatusEngine(const std::string& name, EngineInfo* info);

/// 返回指定引擎的 FlutterDesktopEngineRef，不存在时返回 nullptr。
/// Returns the running engine called |name|, or nullptr.
FLUTTER_PLUGIN_EXPORT FlutterDesktopEngineRef GetEngine(const std::string& name);

/// 销毁指定引擎；不存在或为主引擎时返回 false。
/// Destroys the engine called |name|. Returns false when it does not exist.
FLUTTER_PLUGIN_EXPORT bool DestroyEngine(const std::string& name);

class FlMultiEnginePlugin : public flutter::Plugin {
 public:
  static void RegisterWithRegistrar(flutter::PluginRegistrarWindows* registrar);

  explicit FlMultiEnginePlugin(std::string engine_name);
  ~FlMultiEnginePlugin() override;

  // Disallow copy and assign.
  FlMultiEnginePlugin(const FlMultiEnginePlugin&) = delete;
  FlMultiEnginePlugin& operator=(const FlMultiEnginePlugin&) = delete;

  void HandleMethodCall(
      const flutter::MethodCall<flutter::EncodableValue>& method_call,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);

 private:
  std::string engine_name_;
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> channel_;
};

}  // namespace fl_multi_engine

#endif  // FLUTTER_PLUGIN_FL_MULTI_ENGINE_PLUGIN_H_
