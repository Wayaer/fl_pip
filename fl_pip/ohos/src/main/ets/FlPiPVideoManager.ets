import { common } from '@kit.AbilityKit';
import { media } from '@kit.MediaKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import { resourceManager } from '@kit.LocalizationKit';
import { FlutterPluginBinding } from '@ohos/flutter_ohos';
import { PiPWindow } from '@kit.ArkUI';
import { FlPiPErrorCode, FlPiPException } from './FlPiPError';
import { FlPiPOverlayLayout, FlPiPWindowManager } from './FlPiPWindowManager';

/**
 * [FlPiPSurface] 提供给视频层的宿主回调。
 *
 * 视频由主页面额外挂载的媒体 XComponent 渲染：系统画中画由 `@ohos.PiPWindow` 把该 surface
 * 移入窗口，应用内浮窗则按传入的宽高与位置布局在页面上，并显示与 Android 一致的控制面板。
 *
 * Surface callbacks used by the video layer. The media XComponent is mounted by the host page;
 * the system PiP moves it into the window while the overlay lays it out with a control panel.
 */
export interface FlPiPVideoSurfaceHost {
  attachMediaSurface(): void;
  detachMediaSurface(): void;
  /** 更新媒体 XComponent 的宽高比，使其与视频比例一致。 */
  setMediaAspectRatio(ratio: number): void;
  /** 以应用内浮窗展示媒体 XComponent。 / Shows the media XComponent as an in-app overlay. */
  attachMediaOverlay(layout: FlPiPOverlayLayout, controls: Map<string, ESObject>): void;
  /** 更新应用内浮窗的位置与尺寸。 / Updates the overlay position and size. */
  updateMediaOverlayLayout(layout: FlPiPOverlayLayout): void;
  /** 同步播放状态给应用内浮窗的控制面板。 / Syncs playback state to the overlay panel. */
  updateMediaOverlayPlayback(playing: boolean, positionMs: number, durationMs: number): void;
  /** 显示或隐藏应用内浮窗的控制面板。 / Shows or hides the overlay control panel. */
  setMediaOverlayControlsVisible(visible: boolean): void;
}

/**
 * AVPlayer 与 XComponent 之间的桥：surface 创建后把 surfaceId 交给播放器。
 *
 * Bridges the AVPlayer with the XComponent surface.
 */
class FlPiPVideoXComponentController extends XComponentController {
  private manager: FlPiPVideoManager;

  constructor(manager: FlPiPVideoManager) {
    super();
    this.manager = manager;
  }

  onSurfaceCreated(surfaceId: string): void {
    this.manager.onMediaSurfaceCreated(surfaceId);
  }

  onSurfaceDestroyed(surfaceId: string): void {
    this.manager.onMediaSurfaceDestroyed(surfaceId);
  }

  onSurfaceChanged(surfaceId: string, rect: SurfaceRect): void {
    // rect 只用于确认 surface 已按新的宽高比换过尺寸，这里只需要通知等待方。
    this.manager.onMediaSurfaceChanged(surfaceId);
  }
}

/**
 * 视频播放管理。
 *
 * 只负责视频源、AVPlayer 播放状态与事件；窗口本身（系统画中画或应用内浮窗）由
 * [FlPiPWindowManager] 统一管理，两者互不持有对方的内容状态。
 *
 * Owns the video source, the AVPlayer state and the playback events. The window itself is managed
 * by FlPiPWindowManager.
 */
export class FlPiPVideoManager {
  private static sharedInstance: FlPiPVideoManager | null = null;

  static getInstance(): FlPiPVideoManager {
    if (FlPiPVideoManager.sharedInstance == null) {
      FlPiPVideoManager.sharedInstance = new FlPiPVideoManager();
    }
    return FlPiPVideoManager.sharedInstance;
  }

  private notifier: ((payload: Map<string, ESObject>) => void) | null = null;
  private binding: FlutterPluginBinding | null = null;

  private active: boolean = false;
  private surfaceHost: FlPiPVideoSurfaceHost | null = null;
  private mediaController: FlPiPVideoXComponentController | null = null;
  private surfaceId: string = '';
  private surfaceResolver: (() => void) | null = null;
  private surfaceReject: ((reason: FlPiPException) => void) | null = null;
  private surfaceTimer: number = -1;

  private player: media.AVPlayer | null = null;
  private playerState: media.AVPlayerState = 'idle';
  private sourceFd: number = -1;
  private sourceAssetPath: string = '';
  private sourceResourceManager: resourceManager.ResourceManager | null = null;
  private prepared: boolean = false;
  private preparing: boolean = false;
  private playing: boolean = false;
  private positionMs: number = 0;
  private durationMs: number = 0;
  private speed: number = 1.0;
  private volume: number = 1.0;
  private loop: boolean = false;
  private progressTimer: number = -1;
  // 画中画窗口的比例由 contentWidth:contentHeight 决定，媒体 XComponent 必须按同一比例布局，
  // 否则系统会把画面拉伸到窗口尺寸（竖屏视频会被拉成横屏）。
  // The media XComponent must use the same ratio as the PiP window, otherwise it is stretched.
  private contentRatio: number = 16 / 9;
  private videoWidth: number = 0;
  private videoHeight: number = 0;
  private videoSizeResolver: (() => void) | null = null;
  private videoSizeTimer: number = -1;
  private surfaceChangedResolver: (() => void) | null = null;
  private surfaceChangedTimer: number = -1;
  // stop() 和系统关闭画中画可能同时触发清理，重入时复用进行中的清理。
  // stop() and the PiP STOPPED callback may both clean up; re-entrant calls reuse it.
  private releasing: boolean = false;

  /** 视频承载方式：`systemPip` 或 `overlay`。 / The presentation mode of the video window. */
  private mode: string = 'systemPip';
  /** 系统画中画的自定义宽高比；0 表示跟随视频原始宽高比。 */
  /** Custom system PiP aspect ratio; 0 follows the video's intrinsic ratio. */
  private systemAspectRatio: number = 0;
  /** 应用内浮窗的布局（vp）。 / The in-app overlay layout in vp. */
  private overlayLayout: FlPiPOverlayLayout = { left: 0, top: 0, width: 0, height: 0, cornerRadius: 12 };
  /** 应用内浮窗的控制面板开关。 / The control panel switches of the overlay. */
  private overlayControls: Map<string, ESObject> | null = null;
  /** 控制面板是否显示。 / Whether the control panel is visible. */
  private controlsVisible: boolean = true;
  /** 上一次上报给 Dart 的控制面板可见状态。 / The last panel visibility reported to Dart. */
  private lastControlsVisible: boolean = true;
  private controlsTimer: number = -1;
  /** prepare 之前的 seek 目标；prepare 完成后应用。 / Pending seek applied once prepared. */
  private pendingSeekMs: number = -1;

  setEventNotifier(notifier: ((payload: Map<string, ESObject>) => void) | null): void {
    this.notifier = notifier;
  }

  setBinding(binding: FlutterPluginBinding): void {
    this.binding = binding;
    // 系统画中画面板的操作由窗口层转回视频层。
    // Panel actions of the system PiP window are forwarded back to the video layer.
    FlPiPWindowManager.getInstance().setVideoControlHandler((event: PiPWindow.ControlEventParam): void => {
      this.onPipControl(event);
    });
  }

  /** [FlPiPSurface] 注册媒体 XComponent 的宿主。 */
  setSurfaceHost(host: FlPiPVideoSurfaceHost | null): void {
    this.surfaceHost = host;
  }

  clearSurfaceHost(host: FlPiPVideoSurfaceHost): void {
    if (this.surfaceHost == host) {
      this.surfaceHost = null;
    }
  }

  isActive(): boolean {
    return this.active;
  }

  controller(): XComponentController | null {
    return this.mediaController;
  }

  surfaceKey(): string {
    return 'fl_pip_media_surface';
  }

  /**
   * 媒体 surface 的宽高比，[FlPiPSurface] 用它给媒体 XComponent 布局。
   *
   * Aspect ratio of the media surface used by FlPiPSurface to lay out the media XComponent.
   */
  getContentRatio(): number {
    return this.contentRatio;
  }

  /** 当前是否以应用内浮窗展示视频。 / Whether the video is shown as an in-app overlay. */
  isOverlayMode(): boolean {
    return this.active && this.mode == 'overlay';
  }

  /** 控制面板是否启用。 / Whether the control panel is enabled. */
  isControlsEnabled(): boolean {
    return this.controlFlag('enabled', true);
  }

  /** 读取控制面板开关；缺失时使用 [fallback]。 / Reads a control switch, using [fallback] when absent. */
  controlFlag(name: string, fallback: boolean): boolean {
    const controls: Map<string, ESObject> | null = this.overlayControls;
    if (controls == null || !controls.has(name)) {
      return fallback;
    }
    const value: ESObject = controls.get(name) as ESObject;
    return typeof value == 'boolean' ? value as boolean : fallback;
  }

  /** 显示控制面板并重置自动隐藏计时。 / Shows the panel and restarts the auto-hide timer. */
  showOverlayControls(): void {
    if (!this.isOverlayMode() || !this.isControlsEnabled()) {
      return;
    }
    this.controlsVisible = true;
    this.surfaceHost?.setMediaOverlayControlsVisible(true);
    this.notifyControls(true);
    this.scheduleControlsHide();
  }

  private scheduleControlsHide(): void {
    this.stopControlsTimer();
    if (!this.controlFlag('autoHide', true)) {
      return;
    }
    this.controlsTimer = setTimeout(() => {
      this.controlsTimer = -1;
      if (!this.isOverlayMode()) {
        return;
      }
      this.controlsVisible = false;
      this.surfaceHost?.setMediaOverlayControlsVisible(false);
      this.notifyControls(false);
    }, 3000);
  }

  /** 只在可见状态变化时上报 `controls`，与 Android 一致。 */
  private notifyControls(visible: boolean): void {
    if (visible == this.lastControlsVisible) {
      return;
    }
    this.lastControlsVisible = visible;
    this.notifyEvent('controls', null, false, visible ? 'show' : 'hide');
  }

  private stopControlsTimer(): void {
    if (this.controlsTimer >= 0) {
      clearTimeout(this.controlsTimer);
      this.controlsTimer = -1;
    }
  }

  /** 切换应用内浮窗的播放/暂停。 / Toggles playback of the in-app overlay. */
  toggleOverlayPlaying(): void {
    this.setPlaying(!this.playing);
  }

  isPlaying(): boolean {
    return this.playing;
  }

  /**
   * 播放视频；视频画面由 [FlPiPSurface] 里的媒体 XComponent 渲染。
   *
   * [widthPx] / [heightPx] / [leftPx] / [topPx] 都是**物理像素（px）**，仅应用内浮窗使用；
   * 系统画中画只用 [aspectRatio]，为 0 时按视频原始宽高比。
   *
   * Plays a video. Sizes and offsets are physical pixels used by the overlay; the system PiP only
   * uses [aspectRatio] (0 follows the video's intrinsic ratio).
   */
  async playVideo(
    context: common.UIAbilityContext,
    type: string,
    uri: string,
    packageName: string | null,
    loop: boolean,
    muted: boolean,
    widthPx: number,
    heightPx: number,
    leftPx: number,
    topPx: number,
    mode: string,
    aspectRatio: number,
    cornerRadius: number,
    controls: Map<string, ESObject> | null
  ): Promise<boolean> {
    if (this.isActive()) {
      throw new FlPiPException(FlPiPErrorCode.ALREADY_ENABLED, 'A media window is already visible');
    }
    if (FlPiPWindowManager.getInstance().isActive()) {
      throw new FlPiPException(
        FlPiPErrorCode.ALREADY_ENABLED,
        'A picture-in-picture window is showing; close it before playing media'
      );
    }
    if (uri.length == 0) {
      throw new FlPiPException(FlPiPErrorCode.INVALID_CONFIGURATION, 'The video source must not be empty');
    }

    this.resetSession();
    this.active = true;
    this.mode = mode == 'overlay' ? 'overlay' : 'systemPip';
    if (this.mode != 'overlay' && !FlPiPWindowManager.isSupportedAspectRatio(aspectRatio)) {
      this.resetSession();
      this.active = false;
      throw new FlPiPException(
        FlPiPErrorCode.INVALID_CONFIGURATION,
        'The aspect ratio must be between 1/2.39 and 2.39'
      );
    }
    this.systemAspectRatio = aspectRatio > 0 ? aspectRatio : 0;
    this.loop = loop;
    this.volume = muted ? 0 : 1;
    this.playing = true;
    this.prepared = false;
    this.overlayControls = controls;
    this.mediaController = new FlPiPVideoXComponentController(this);
    const hasSize: boolean = widthPx > 0 && heightPx > 0;
    if (hasSize) {
      this.contentRatio = widthPx / heightPx;
    }
    const isOverlay: boolean = this.mode == 'overlay';
    if (isOverlay) {
      this.overlayLayout = FlPiPWindowManager.getInstance().resolveOverlayLayout(
        leftPx,
        topPx,
        widthPx,
        heightPx,
        cornerRadius,
        this.contentRatio
      );
      this.controlsVisible = this.isControlsEnabled();
      // 与 Android 一致：首次同步面板状态时不额外上报 `controls`。
      // Match Android: the first panel sync does not emit a `controls` event.
      this.lastControlsVisible = this.controlsVisible;
    }

    try {
      await this.waitForMediaSurface(isOverlay);
      const player: media.AVPlayer = await media.createAVPlayer();
      this.player = player;
      this.registerPlayerListeners(player);
      // 先注册等待再设置视频源：视频源设置后立即可能进入 prepared。
      // Register the waiter before setting the source, since prepared can happen right after.
      const sizeReady: Promise<void> = this.waitForVideoSize();
      await this.setVideoSource(context, player, type, uri, packageName);
      await sizeReady;
      // 视频必须按自身原始比例缩放，任何宽高都不能直接拉伸画面。
      // The picture keeps its intrinsic aspect ratio; custom sizes never stretch it.
      const videoRatio: number = this.videoWidth > 0 && this.videoHeight > 0
        ? this.videoWidth / this.videoHeight
        : this.contentRatio;
      if (isOverlay) {
        this.contentRatio = videoRatio;
        // 无论是否自定义宽高，媒体 surface 都必须使用视频自身的比例，否则竖屏视频会被拉伸。
        // The media surface always uses the video's own ratio so a portrait video is never stretched.
        this.surfaceHost?.setMediaAspectRatio(videoRatio);
        if (!hasSize) {
          // 未指定宽高时按视频原始比例建窗，竖屏视频不会被拉伸成默认的 16:9。
          // Without an explicit size, adopt the video's own ratio.
          this.overlayLayout = FlPiPWindowManager.getInstance().resolveOverlayLayout(
            leftPx,
            topPx,
            widthPx,
            heightPx,
            cornerRadius,
            videoRatio
          );
          this.surfaceHost?.updateMediaOverlayLayout(this.overlayLayout);
        }
      } else {
        // 系统画中画优先使用自定义比例，未指定时跟随视频原始比例；窗口大小由系统决定。
        // The system PiP prefers the custom ratio and follows the video when it is absent; the
        // system decides the actual window size.
        const pipRatio: number = this.systemAspectRatio > 0 ? this.systemAspectRatio : videoRatio;
        await this.applyContentRatio(pipRatio);
      }
      if (isOverlay) {
        FlPiPWindowManager.getInstance().presentVideoOverlay(this.overlayLayout);
        this.showOverlayControls();
      } else {
        const controller = this.mediaController;
        if (controller == null) {
          throw new FlPiPException(FlPiPErrorCode.WINDOW_UNAVAILABLE, 'The media surface is not ready');
        }
        await FlPiPWindowManager.getInstance().presentVideoSystemPip(
          controller,
          this.contentRatio,
          (): void => {
            this.releaseMedia(true).catch(() => {});
          }
        );
      }
      // 与 Android / iOS 一致：窗口展示后只上报一次 play，并带 action。
      // Match Android / iOS: report `play` once after the window is shown, with the action.
      this.notifyEvent('play', this.playing, false, 'play');
      return true;
    } catch (error) {
      await this.releaseMedia(true);
      if (error instanceof FlPiPException) {
        throw error;
      }
      throw new FlPiPException(FlPiPErrorCode.OVERLAY_CREATION_FAILED, `Unable to play the video: ${error}`);
    }
  }

  onMediaSurfaceCreated(surfaceId: string): void {
    this.surfaceId = surfaceId;
    const player = this.player;
    if (player != null) {
      try {
        player.surfaceId = surfaceId;
      } catch (error) {
        // 播放器可能还没有进入 initialized 状态，稍后在 stateChange 里再设置。
      }
      this.prepareIfReady();
    }
    this.clearSurfaceWaiter();
    const resolver = this.surfaceResolver;
    this.surfaceResolver = null;
    if (resolver != null) {
      resolver();
    }
  }

  onMediaSurfaceDestroyed(surfaceId: string): void {
    if (surfaceId == this.surfaceId) {
      this.surfaceId = '';
    }
  }

  onMediaSurfaceChanged(surfaceId: string): void {
    if (surfaceId == this.surfaceId) {
      this.resolveSurfaceChanged();
    }
  }

  /**
   * 等视频进入 prepared 以读取原始宽高；超时后按已确定的比例继续，避免远程视频长时间拖慢窗口。
   *
   * Waits for `prepared` to read the intrinsic video size; on timeout it keeps the configured ratio
   * so a slow remote source does not hold back the window.
   */
  private waitForVideoSize(): Promise<void> {
    if (this.prepared) {
      return Promise.resolve();
    }
    return new Promise<void>((resolve: () => void) => {
      this.videoSizeResolver = resolve;
      this.videoSizeTimer = setTimeout(() => {
        this.resolveVideoSize();
      }, 5000);
    });
  }

  private resolveVideoSize(): void {
    if (this.videoSizeTimer >= 0) {
      clearTimeout(this.videoSizeTimer);
      this.videoSizeTimer = -1;
    }
    const resolve = this.videoSizeResolver;
    this.videoSizeResolver = null;
    if (resolve != null) {
      resolve();
    }
  }

  /**
   * 按新的宽高比重新布局媒体 surface，并等 XComponent 真正换到新尺寸。
   *
   * 画中画窗口按 surface 当前尺寸展示内容，比例还没生效就启动窗口时，竖屏视频仍会被拉伸。
   *
   * Re-lays out the media surface and waits until the XComponent really resized.
   */
  private applyContentRatio(ratio: number): Promise<void> {
    if (ratio <= 0 || Math.abs(ratio - this.contentRatio) < 0.001) {
      return Promise.resolve();
    }
    this.contentRatio = ratio;
    const host = this.surfaceHost;
    if (host == null) {
      return Promise.resolve();
    }
    return new Promise<void>((resolve: () => void) => {
      this.surfaceChangedResolver = resolve;
      host.setMediaAspectRatio(ratio);
      this.surfaceChangedTimer = setTimeout(() => {
        this.resolveSurfaceChanged();
      }, 500);
    });
  }

  private resolveSurfaceChanged(): void {
    if (this.surfaceChangedTimer >= 0) {
      clearTimeout(this.surfaceChangedTimer);
      this.surfaceChangedTimer = -1;
    }
    const resolve = this.surfaceChangedResolver;
    this.surfaceChangedResolver = null;
    if (resolve != null) {
      resolve();
    }
  }

  private playPlayer(player: media.AVPlayer): void {
    player.play().catch((error: ESObject) => {
      // 播放器状态切换失败时保持当前状态，事件仍由 stateChange 同步。
    });
  }

  private pausePlayer(player: media.AVPlayer): void {
    player.pause().catch((error: ESObject) => {
      // 播放器状态切换失败时保持当前状态。
    });
  }

  setPlaying(playing: boolean): boolean {
    if (!this.isActive()) {
      return false;
    }
    this.playing = playing;
    const player = this.player;
    if (player != null && this.prepared) {
      if (playing) {
        this.playPlayer(player);
        // 恢复播放时套用上次设置的倍速，避免暂停前设置的倍速丢失，与 Android / iOS 一致。
        // Re-apply the stored speed because some players reset it on pause/resume.
        if (this.speed != 1.0) {
          try {
            player.setPlaybackRate(this.speed);
          } catch (error) {
            // 部分设备在切换状态时无法立即修改倍速。
          }
        }
      } else {
        this.pausePlayer(player);
      }
    }
    this.notifyEvent('playPause', playing, false, playing ? 'play' : 'pause');
    return true;
  }

  seek(positionMs: number): boolean {
    if (!this.isActive()) {
      return false;
    }
    const target = this.clampPosition(positionMs);
    this.positionMs = target;
    const player = this.player;
    if (player != null && this.prepared) {
      try {
        player.seek(target, media.SeekMode.SEEK_PREV_SYNC);
      } catch (error) {
        return false;
      }
    } else {
      // prepare 之前只记录目标位置，onPrepared 再应用，与 Android / iOS 一致。
      // Record the target before `prepared` and apply it in onPrepared, like Android / iOS.
      this.pendingSeekMs = target;
    }
    this.notifyEvent('position', this.playing, true, 'seek', target, this.durationMs);
    return true;
  }

  seekBy(offsetMs: number): boolean {
    return this.seek(this.positionMs + offsetMs);
  }

  /** 系统画中画面板的快进/快退并上报 `skip`，action 为 `rewind` / `forward`。 */
  skip(offsetMs: number): boolean {
    if (!this.isActive()) {
      return false;
    }
    const target = this.clampPosition(this.positionMs + offsetMs);
    this.positionMs = target;
    const player = this.player;
    if (player != null && this.prepared) {
      try {
        player.seek(target, media.SeekMode.SEEK_PREV_SYNC);
      } catch (error) {
        return false;
      }
    } else {
      this.pendingSeekMs = target;
    }
    this.notifyEvent(
      'skip',
      this.playing,
      true,
      offsetMs < 0 ? 'rewind' : 'forward',
      target,
      this.durationMs
    );
    return true;
  }

  stopPlayback(): boolean {
    if (!this.isActive()) {
      return false;
    }
    this.playing = false;
    this.positionMs = 0;
    const player = this.player;
    if (player != null && this.prepared) {
      this.pausePlayer(player);
      player.seek(0, media.SeekMode.SEEK_PREV_SYNC);
    } else {
      this.pendingSeekMs = 0;
    }
    this.notifyEvent('stop', false, true, 'pause', 0, this.durationMs);
    return true;
  }

  setSpeed(speed: number): boolean {
    if (!this.isActive() || speed <= 0) {
      return false;
    }
    this.speed = speed;
    const player = this.player;
    // 只在播放中应用：暂停状态下设置倍速可能让播放器重新开始播放，与 Android / iOS 一致。
    // Apply only while playing; setting the rate on a paused player may resume it.
    if (player != null && this.prepared && this.playing) {
      try {
        player.setPlaybackRate(speed);
      } catch (error) {
        return false;
      }
    }
    this.notifyEvent('speed', this.playing, false);
    return true;
  }

  setVolume(volume: number): boolean {
    if (!this.isActive()) {
      return false;
    }
    this.volume = Math.min(Math.max(volume, 0), 1);
    const player = this.player;
    // prepare 之前只记录音量，onPrepared 再应用，与 Android / iOS 一致。
    // Record the volume before `prepared` and apply it in onPrepared.
    if (player != null && this.prepared) {
      try {
        player.setVolume(this.volume);
      } catch (error) {
        return false;
      }
    }
    this.notifyEvent('volume', this.playing, false);
    return true;
  }

  setLooping(loop: boolean): boolean {
    const player = this.player;
    if (player == null) {
      return false;
    }
    this.loop = loop;
    player.loop = loop;
    return true;
  }

  getStatus(): Map<string, ESObject> | null {
    if (!this.isActive()) {
      return null;
    }
    const status: Map<string, ESObject> = new Map<string, ESObject>();
    status.set('playing', this.playing);
    status.set('positionMs', this.positionMs);
    status.set('durationMs', this.durationMs);
    status.set('speed', this.speed);
    status.set('volume', this.volume);
    return status;
  }

  /** 关闭视频窗口并释放播放器与 surface。 / Closes the video window and releases the player. */
  async stop(): Promise<boolean> {
    if (!this.isActive()) {
      return false;
    }
    await this.releaseMedia(true);
    return true;
  }

  /**
   * 等待 [FlPiPSurface] 挂载好媒体 XComponent。
   *
   * 媒体 surface 必须在主页面挂载完成后才能创建播放器与画中画控制器。
   *
   * Waits until FlPiPSurface mounted the media XComponent.
   */
  private waitForMediaSurface(overlay: boolean): Promise<void> {
    if (this.surfaceId.length > 0) {
      return Promise.resolve();
    }
    const host = this.surfaceHost;
    if (host == null) {
      return Promise.reject(new FlPiPException(
        FlPiPErrorCode.WINDOW_UNAVAILABLE,
        'The host page must render Flutter through FlPiPSurface before playing media'
      ));
    }
    return new Promise<void>((resolve: () => void, reject: (reason?: ESObject) => void) => {
      this.clearSurfaceWaiter();
      this.surfaceResolver = resolve;
      this.surfaceReject = (reason: FlPiPException): void => reject(reason);
      if (overlay) {
        host.attachMediaOverlay(this.overlayLayout, this.overlayControls ?? new Map<string, ESObject>());
      } else {
        host.attachMediaSurface();
      }
      this.surfaceTimer = setTimeout(() => {
        this.surfaceTimer = -1;
        this.clearSurfaceWaiter();
        reject(new FlPiPException(
          FlPiPErrorCode.START_FAILED,
          'Timed out while mounting the media surface'
        ));
      }, 3000);
    });
  }

  private clearSurfaceWaiter(reason: FlPiPException | null = null): void {
    if (this.surfaceTimer >= 0) {
      clearTimeout(this.surfaceTimer);
      this.surfaceTimer = -1;
    }
    const reject = this.surfaceReject;
    this.surfaceReject = null;
    if (reason != null && reject != null) {
      reject(reason);
    }
  }

  /** 把系统画中画面板的操作应用到播放器。 / Applies the system PiP panel actions. */
  private onPipControl(event: PiPWindow.ControlEventParam): void {
    if (event.controlType == PiPWindow.PiPControlType.VIDEO_PLAY_PAUSE) {
      this.setPlaying(event.status == PiPWindow.PiPControlStatus.PLAY);
    } else if (event.controlType == PiPWindow.PiPControlType.FAST_FORWARD) {
      this.skip(15000);
    } else if (event.controlType == PiPWindow.PiPControlType.FAST_BACKWARD) {
      this.skip(-15000);
    }
  }

  private registerPlayerListeners(player: media.AVPlayer): void {
    player.on('stateChange', (state: media.AVPlayerState, reason: media.StateChangeReason) => {
      this.playerState = state;
      if (state == 'initialized') {
        this.prepareIfReady();
      } else if (state == 'prepared') {
        this.onPrepared();
      } else if (state == 'playing') {
        this.playing = true;
      } else if (state == 'paused') {
        this.playing = false;
      } else if (state == 'completed') {
        this.onCompleted();
      } else if (state == 'error') {
        this.resolveVideoSize();
        this.notifyEvent('error', false, false);
      }
    });
    player.on('error', (error: ESObject) => {
      this.resolveVideoSize();
      this.notifyEvent('error', false, false);
    });
  }

  private prepareIfReady(): void {
    const player = this.player;
    if (player == null || this.prepared || this.preparing) {
      return;
    }
    if (this.playerState != 'initialized' || this.surfaceId.length == 0) {
      return;
    }
    this.preparing = true;
    player.surfaceId = this.surfaceId;
    player.prepare().catch((error: ESObject) => {
      this.preparing = false;
      this.notifyEvent('error', false, false);
    });
  }

  private onPrepared(): void {
    this.preparing = false;
    this.prepared = true;
    const player = this.player;
    if (player == null) {
      this.resolveVideoSize();
      return;
    }
    // 视频原始宽高只在 prepared 之后有效，画中画窗口按它决定比例。
    // The intrinsic video size is only valid after `prepared`.
    this.videoWidth = player.width > 0 ? player.width : 0;
    this.videoHeight = player.height > 0 ? player.height : 0;
    this.resolveVideoSize();
    this.durationMs = Math.max(player.duration, 0);
    try {
      player.loop = this.loop;
      player.setVolume(this.volume);
      player.setPlaybackRate(this.speed);
    } catch (error) {
      // 部分设备在 prepared 阶段不支持立即设置倍速，保留默认速度即可。
    }
    if (this.pendingSeekMs >= 0) {
      const target = this.clampPosition(this.pendingSeekMs);
      this.pendingSeekMs = -1;
      try {
        player.seek(target, media.SeekMode.SEEK_PREV_SYNC);
      } catch (error) {
        // 跳转失败时保留当前位置。
      }
      this.positionMs = target;
    }
    if (this.playing) {
      this.playPlayer(player);
    } else {
      this.pausePlayer(player);
    }
    this.startProgressTimer();
  }

  private onCompleted(): void {
    const player = this.player;
    if (player == null) {
      return;
    }
    if (this.loop) {
      this.positionMs = 0;
      player.seek(0, media.SeekMode.SEEK_PREV_SYNC);
      if (this.playing) {
        this.playPlayer(player);
      }
      return;
    }
    this.playing = false;
    this.positionMs = this.durationMs;
    this.notifyEvent('ended', false, false, 'pause', this.positionMs, this.durationMs);
  }

  private startProgressTimer(): void {
    this.stopProgressTimer();
    this.progressTimer = setInterval(() => {
      const player = this.player;
      if (player == null || !this.prepared) {
        return;
      }
      this.positionMs = Math.max(player.currentTime, 0);
      this.durationMs = Math.max(player.duration, 0);
      this.notifyEvent('position', this.playing, true, 'progress', this.positionMs, this.durationMs);
    }, 500);
  }

  private stopProgressTimer(): void {
    if (this.progressTimer >= 0) {
      clearInterval(this.progressTimer);
      this.progressTimer = -1;
    }
  }

  private async setVideoSource(
    context: common.UIAbilityContext,
    player: media.AVPlayer,
    type: string,
    uri: string,
    packageName: string | null
  ): Promise<void> {
    // 切换视频源前先关掉上一份 fd，避免重复设置时泄漏。
    // Close the previous descriptor before switching sources.
    await this.closeSource();
    if (type == 'network' || uri.startsWith('http://') || uri.startsWith('https://')) {
      player.url = uri;
      return;
    }
    if (type == 'file' || uri.startsWith('file://') || uri.startsWith('/')) {
      const path = uri.startsWith('file://') ? uri.substring('file://'.length) : uri;
      let fd: number = -1;
      try {
        fd = fs.openSync(path, fs.OpenMode.READ_ONLY).fd;
        const stat = fs.statSync(path);
        this.sourceFd = fd;
        player.fdSrc = { fd: fd, offset: 0, length: stat.size };
      } catch (error) {
        if (fd >= 0) {
          try {
            fs.closeSync(fd);
          } catch (closeError) {
            // fd 可能已经失效。
          }
        }
        // 与 Android / iOS 一致：文件不存在时返回 video_asset_not_found。
        // Match Android / iOS: report video_asset_not_found when the file is missing.
        throw new FlPiPException(FlPiPErrorCode.VIDEO_ASSET_NOT_FOUND, `The video file does not exist: ${path}`);
      }
      return;
    }
    const binding = this.binding;
    if (binding == null) {
      throw new FlPiPException(FlPiPErrorCode.INVALID_CONFIGURATION, 'The Flutter plugin binding is unavailable');
    }
    const assets = binding.getFlutterAssets();
    const assetPath = packageName == null
      ? assets.getAssetFilePathByName(uri)
      : assets.getAssetFilePathByName(uri, packageName);
    try {
      const descriptor = await context.resourceManager.getRawFd(assetPath);
      this.sourceAssetPath = assetPath;
      this.sourceResourceManager = context.resourceManager;
      player.fdSrc = { fd: descriptor.fd, offset: descriptor.offset, length: descriptor.length };
    } catch (error) {
      // 与 Android / iOS 一致：asset 不存在时返回 video_asset_not_found。
      // Match Android / iOS: report video_asset_not_found when the asset is missing.
      throw new FlPiPException(FlPiPErrorCode.VIDEO_ASSET_NOT_FOUND, `The video asset does not exist: ${uri}`);
    }
  }

  /**
   * 关闭视频源占用的文件描述符。
   *
   * AVPlayer 只借用 `fdSrc` 里的 fd，不会自动关闭；这里必须释放，否则每次播放都会泄漏 fd。
   *
   * Closes the descriptor backing the current video source.
   */
  private async closeSource(): Promise<void> {
    const fd = this.sourceFd;
    this.sourceFd = -1;
    if (fd >= 0) {
      try {
        fs.closeSync(fd);
      } catch (error) {
        // fd 可能已经随播放器一起失效。
      }
    }
    const assetPath = this.sourceAssetPath;
    const manager = this.sourceResourceManager;
    this.sourceAssetPath = '';
    this.sourceResourceManager = null;
    if (assetPath.length > 0 && manager != null) {
      try {
        await manager.closeRawFd(assetPath);
      } catch (error) {
        // 资源可能已经被系统回收。
      }
    }
  }

  private clampPosition(positionMs: number): number {
    const target = Math.max(positionMs, 0);
    return this.durationMs > 0 ? Math.min(target, this.durationMs) : target;
  }

  private async releaseMedia(notifyClose: boolean): Promise<void> {
    if (this.releasing) {
      return;
    }
    this.releasing = true;
    try {
      await this.releaseMediaInternal(notifyClose);
    } finally {
      this.releasing = false;
    }
  }

  private async releaseMediaInternal(notifyClose: boolean): Promise<void> {
    const wasActive = this.active;
    this.stopProgressTimer();
    this.stopControlsTimer();
    const player = this.player;
    this.player = null;
    this.prepared = false;
    this.preparing = false;
    if (player != null) {
      try {
        player.off('stateChange');
        player.off('error');
      } catch (error) {
        // 监听可能已经解绑。
      }
      try {
        await player.release();
      } catch (error) {
        // 播放器可能已经释放。
      }
    }
    // 播放器释放后才能关闭视频源的 fd。
    // Release the source descriptor only after the player stops using it.
    await this.closeSource();

    // 窗口由统一窗口层关闭，同时停止系统画中画与移除浮窗。
    // The unified window layer closes the window, stopping PiP and removing the overlay.
    await FlPiPWindowManager.getInstance().closeVideoWindow();

    this.clearSurfaceWaiter(new FlPiPException(
      FlPiPErrorCode.START_FAILED,
      'The media surface was released while waiting for it'
    ));
    this.surfaceHost?.detachMediaSurface();
    this.surfaceId = '';
    this.mediaController = null;
    this.resolveVideoSize();
    this.resolveSurfaceChanged();
    this.videoWidth = 0;
    this.videoHeight = 0;
    this.contentRatio = 16 / 9;
    this.playing = false;
    this.positionMs = 0;
    this.durationMs = 0;
    this.mode = 'systemPip';
    this.overlayControls = null;
    this.controlsVisible = true;
    this.lastControlsVisible = true;
    this.pendingSeekMs = -1;
    if (wasActive && notifyClose) {
      // close 事件与 Android/iOS 对齐，不携带 playing 字段。
      this.notifyEvent('close', null, false, 'close');
    }
    this.active = false;
  }

  private resetSession(): void {
    this.stopProgressTimer();
    this.stopControlsTimer();
    this.resolveVideoSize();
    this.resolveSurfaceChanged();
    this.player = null;
    this.playerState = 'idle';
    this.surfaceId = '';
    this.prepared = false;
    this.preparing = false;
    this.positionMs = 0;
    this.durationMs = 0;
    this.speed = 1.0;
    this.volume = 1.0;
    this.videoWidth = 0;
    this.videoHeight = 0;
    this.contentRatio = 16 / 9;
    this.systemAspectRatio = 0;
    this.playing = false;
    this.mode = 'systemPip';
    this.overlayControls = null;
    this.controlsVisible = true;
    this.lastControlsVisible = true;
    this.pendingSeekMs = -1;
  }

  private notifyEvent(
    event: string,
    playing: boolean | null,
    includePosition: boolean,
    action: string | null = null,
    positionMs: number | null = null,
    durationMs: number | null = null
  ): void {
    const payload: Map<string, ESObject> = new Map<string, ESObject>();
    payload.set('event', event);
    if (playing != null) {
      payload.set('playing', playing);
    }
    if (includePosition) {
      payload.set('positionMs', positionMs ?? this.positionMs);
      payload.set('durationMs', durationMs ?? this.durationMs);
    }
    if (action != null) {
      payload.set('action', action);
    }
    if (this.isOverlayMode()) {
      // 应用内浮窗的控制面板由 ArkUI 绘制，需要同步播放状态。
      this.surfaceHost?.updateMediaOverlayPlayback(this.playing, this.positionMs, this.durationMs);
    }
    const notifier = this.notifier;
    if (notifier != null) {
      notifier(payload);
    }
  }
}
