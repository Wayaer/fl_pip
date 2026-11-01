package fl.pip

/** 三端共用的平台通道名称。 / The platform channel name shared by Android, iOS and HarmonyOS. */
internal const val FL_PIP_CHANNEL_NAME = "fl_pip"

/**
 * 原生画中画实现返回的错误码，与 Dart 的 `FlPiPErrorCode` 保持一致。
 *
 * Error codes reported by the native implementation. Every value must stay in sync with the Dart
 * `FlPiPErrorCode` enum and the other platforms.
 */
object FlPiPErrorCode {
    const val PERMISSION_DENIED = "permission_denied"
    const val PERMISSION_REQUEST_IN_PROGRESS = "permission_request_in_progress"
    const val NOT_SUPPORTED = "not_supported"
    const val ALREADY_ENABLED = "already_enabled"
    const val ACTIVITY_NOT_INITIALIZED = "activity_not_initialized"
    const val INVALID_CONFIGURATION = "invalid_configuration"
    const val START_FAILED = "start_failed"
    const val OVERLAY_CREATION_FAILED = "overlay_creation_failed"
    const val AUDIO_SESSION_FAILED = "audio_session_failed"
    const val VIDEO_ASSET_NOT_FOUND = "video_asset_not_found"
    const val WINDOW_UNAVAILABLE = "window_unavailable"
    const val CONTROLLER_UNAVAILABLE = "controller_unavailable"
    const val ENGINE_CREATION_FAILED = "engine_creation_failed"
    const val ENGINE_NOT_FOUND = "engine_not_found"
    const val UNKNOWN = "unknown"
}

/** 原生实现遇到上述错误时抛出的异常。 / Thrown when the native implementation reports an error. */
class FlPiPException(
    val code: String,
    message: String? = null,
    val details: Any? = null,
) : Exception(message)
