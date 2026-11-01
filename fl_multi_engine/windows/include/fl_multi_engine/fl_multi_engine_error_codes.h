#ifndef FLUTTER_PLUGIN_FL_MULTI_ENGINE_ERROR_CODES_H_
#define FLUTTER_PLUGIN_FL_MULTI_ENGINE_ERROR_CODES_H_

// 与 Dart / Android / Swift 侧一一对应的稳定错误码。
// Stable error codes shared with the Dart, Android and Swift implementations.
namespace fl_multi_engine {
namespace error_code {

inline constexpr const char* kNotSupported = "not_supported";
inline constexpr const char* kInvalidName = "invalid_name";
inline constexpr const char* kEngineExists = "engine_exists";
inline constexpr const char* kCreateFailed = "create_failed";
inline constexpr const char* kMainEngineNotDestroyable = "main_engine_not_destroyable";
inline constexpr const char* kNotInitialized = "not_initialized";
inline constexpr const char* kUnknown = "unknown";

}  // namespace error_code
}  // namespace fl_multi_engine

#endif  // FLUTTER_PLUGIN_FL_MULTI_ENGINE_ERROR_CODES_H_
