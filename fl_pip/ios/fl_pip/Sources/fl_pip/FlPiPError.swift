import Flutter
import Foundation

/// 三端共用的平台通道名称。 / The platform channel name shared by Android, iOS and HarmonyOS.
enum FlPiPChannel {
    static let name = "fl_pip"
}

/// 原生画中画实现返回的错误码，与 Dart 的 `FlPiPErrorCode` 保持一致。
///
/// Error codes reported by the native implementation. Every value must stay in sync with the Dart
/// `FlPiPErrorCode` enum and the other platforms.
enum FlPiPErrorCode: String {
    case permissionDenied = "permission_denied"
    case permissionRequestInProgress = "permission_request_in_progress"
    case notSupported = "not_supported"
    case alreadyEnabled = "already_enabled"
    case activityNotInitialized = "activity_not_initialized"
    case invalidConfiguration = "invalid_configuration"
    case startFailed = "start_failed"
    case overlayCreationFailed = "overlay_creation_failed"
    case audioSessionFailed = "audio_session_failed"
    case videoAssetNotFound = "video_asset_not_found"
    case windowUnavailable = "window_unavailable"
    case controllerUnavailable = "controller_unavailable"
    case engineCreationFailed = "engine_creation_failed"
    case engineNotFound = "engine_not_found"
    case unknown = "unknown"
}

/// 原生实现遇到上述错误时抛出的异常。 / Thrown when the native implementation reports an error.
struct FlPiPException: Error {
    let code: String
    let message: String?
    let details: Any?

    init(_ code: FlPiPErrorCode, message: String? = nil, details: Any? = nil) {
        self.code = code.rawValue
        self.message = message
        self.details = details
    }

    /// 转换成平台通道错误。 / Converts to a platform channel error.
    var flutterError: FlutterError {
        FlutterError(code: code, message: message, details: details)
    }
}
