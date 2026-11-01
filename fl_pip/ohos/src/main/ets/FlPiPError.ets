/** 三端共用的平台通道名称。 / The platform channel name shared by Android, iOS and HarmonyOS. */
export const FL_PIP_CHANNEL_NAME: string = 'fl_pip';

/**
 * fl_pip 与 Dart 侧共享的稳定错误码。
 *
 * Stable error codes shared with the Dart implementation and the other platforms.
 */
export class FlPiPErrorCode {
  static readonly PERMISSION_DENIED: string = 'permission_denied';
  static readonly PERMISSION_REQUEST_IN_PROGRESS: string = 'permission_request_in_progress';
  static readonly NOT_SUPPORTED: string = 'not_supported';
  static readonly ALREADY_ENABLED: string = 'already_enabled';
  static readonly ACTIVITY_NOT_INITIALIZED: string = 'activity_not_initialized';
  static readonly INVALID_CONFIGURATION: string = 'invalid_configuration';
  static readonly START_FAILED: string = 'start_failed';
  static readonly OVERLAY_CREATION_FAILED: string = 'overlay_creation_failed';
  static readonly AUDIO_SESSION_FAILED: string = 'audio_session_failed';
  static readonly VIDEO_ASSET_NOT_FOUND: string = 'video_asset_not_found';
  static readonly WINDOW_UNAVAILABLE: string = 'window_unavailable';
  static readonly CONTROLLER_UNAVAILABLE: string = 'controller_unavailable';
  static readonly ENGINE_CREATION_FAILED: string = 'engine_creation_failed';
  static readonly ENGINE_NOT_FOUND: string = 'engine_not_found';
  static readonly UNKNOWN: string = 'unknown';
}

/** 原生实现抛出的错误，code 与 Dart 侧 [FlPiPErrorCode] 一一对应。 */
export class FlPiPException extends Error {
  readonly code: string;

  constructor(code: string, message: string) {
    super(message);
    this.code = code;
  }
}
