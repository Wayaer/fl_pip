import { display, PiPWindow } from '@kit.ArkUI';
import { common, UIAbility } from '@kit.AbilityKit';
import { FlutterManager } from '@ohos/flutter_ohos';
import { FlMultiEngine } from 'fl_multi_engine';
import { FlPiPEngineManager } from './FlPiPEngineManager';
import { FlPiPErrorCode, FlPiPException } from './FlPiPError';

/** 窗口所有者：`pipMain` 引擎。 / The window is owned by the `pipMain` engine. */
export const PIP_OWNER_ENGINE: string = 'engine';

/** 窗口所有者：视频。 / The window is owned by the video player. */
export const PIP_OWNER_VIDEO: string = 'video';

/** 承载方式：系统画中画。 / Presentation mode: the system PiP window. */
export const PIP_MODE_SYSTEM: string = 'systemPip';

/** 承载方式：应用内浮窗。 / Presentation mode: the in-app overlay. */
export const PIP_MODE_OVERLAY: string = 'overlay';

/**
 * 统一窗口的布局参数，单位为 vp。
 *
 * Layout of the unified window, in vp.
 */
export interface FlPiPOverlayLayout {
  left: number;
  top: number;
  width: number;
  height: number;
  cornerRadius: number;
}

/**
 * [FlPiPSurface] 提供给统一窗口层的宿主回调。
 *
 * 引擎与视频都通过这一组回调挂载内容，[owner] 决定挂载哪一个：
 * 引擎使用 `FlutterView` 的 XComponent，视频使用媒体 XComponent。
 *
 * Surface callbacks used by the unified window layer. [owner] decides which content is mounted:
 * the engine uses its FlutterView XComponent while the video uses the media XComponent.
 */
export interface FlPiPWindowSurfaceHost {
  attachPipSurface(owner: string, viewId: string, ratio: number): void;

  detachPipSurface(): void;

  attachOverlaySurface(owner: string, viewId: string, layout: FlPiPOverlayLayout): void;

  updateOverlayLayout(layout: FlPiPOverlayLayout): void;

  detachOverlaySurface(): void;
}

/**
 * 引擎与视频共用的唯一窗口层。
 *
 * 本类只持有一份窗口状态：`owner`（engine / video / 无）、`mode`（systemPip / overlay）、
 * 内容宽高比与浮窗布局。系统画中画控制器、状态广播和浮窗几何都在这里统一管理，
 * 引擎层与视频层只负责准备内容并向本层申请展示。
 *
 * The single window layer shared by the engine and the video. It owns the only window state
 * (owner, mode, content ratio and overlay layout), creates the system PiP controller, broadcasts
 * the status and resolves the overlay geometry.
 */
export class FlPiPWindowManager {
  private static sharedInstance: FlPiPWindowManager | null = null;

  /** 应用内浮窗拖动时与屏幕边缘保留的间距（vp），与 Android 的 8dp 一致。 */
  private static readonly OVERLAY_EDGE_MARGIN_VP: number = 8;

  static getInstance(): FlPiPWindowManager {
    if (FlPiPWindowManager.sharedInstance == null) {
      FlPiPWindowManager.sharedInstance = new FlPiPWindowManager();
    }
    return FlPiPWindowManager.sharedInstance;
  }

  private notifier: ((status: Map<string, ESObject>) => void) | null = null;
  private controlNotifier: ((payload: Map<string, ESObject>) => void) | null = null;
  private surfaceHost: FlPiPWindowSurfaceHost | null = null;

  /** 当前窗口所有者；没有窗口时为 `null`。 / The window owner, `null` when nothing is shown. */
  private owner: string | null = null;
  /** 当前承载方式；没有窗口时为 `null`。 / The presentation mode, `null` when nothing is shown. */
  private mode: string | null = null;
  /** 当前窗口展示的引擎名称；没有窗口时为 `null`。 */
  /** Name of the presented engine, `null` when no window is shown. */
  private presentedEngineName: string | null = null;
  /** `presentEngine()` 关联的引擎名称，用于判断 hasEngine；引擎销毁后查询结果自动变为 `false`。 */
  /** Name of the engine associated with `presentEngine(); it resolves hasEngine and turns false
   * once the engine is destroyed. */
  private pipEngineName: string | null = null;
  /** `presentEngine()` 指定的画中画引擎名称，窗口关闭后引擎被保留时仍然返回该名称。 */
  /** Name of the picture-in-picture engine passed to `presentEngine(); it is still returned after
   * the window closes while the engine is kept. */
  get pipEngineNameForMessages(): string | null {
    return this.pipEngineName;
  }

  /** 窗口关闭时是否销毁展示的引擎。 / Whether the presented engine is destroyed on dismissal. */
  private destroyEngineOnDismiss: boolean = true;
  /** 系统画中画的内容宽高比。 / Content ratio of the system PiP window. */
  private contentRatio: number = 16 / 9;
  /** 应用内浮窗的布局（vp）。 / The in-app overlay layout in vp. */
  private overlayLayout: FlPiPOverlayLayout = { left: 0, top: 0, width: 0, height: 0, cornerRadius: 12 };

  private pipController: PiPWindow.PiPController | null = null;
  private pipStarting: boolean = false;
  private pipStarted: boolean = false;
  /** 系统画中画由用户或系统关闭时的回调，由占用方提供。 */
  /** Called when the system closes the PiP window; provided by the current owner. */
  private pipStopHandler: (() => void) | null = null;

  private pipSurfaceController: XComponentController | null = null;
  private pipSurfaceResolver: ((controller: XComponentController) => void) | null = null;
  private pipSurfaceReject: ((reason: FlPiPException) => void) | null = null;
  private pipSurfaceTimer: number = -1;

  /** 注册状态回调；插件收到后通过 `onPiPStatus` 同步给 Dart。 */
  setStatusNotifier(notifier: ((status: Map<string, ESObject>) => void) | null): void {
    this.notifier = notifier;
  }

  /** 注册系统画中画面板操作回调；插件收到后通过 `onMessage` 转发给 Dart。 */
  setControlNotifier(notifier: ((payload: Map<string, ESObject>) => void) | null): void {
    this.controlNotifier = notifier;
  }

  /** [FlPiPSurface] 注册渲染宿主。 / Registers the rendering host implemented by FlPiPSurface. */
  setSurfaceHost(host: FlPiPWindowSurfaceHost | null): void {
    this.surfaceHost = host;
    if (host == null) {
      return;
    }
    // 页面重建后重新挂载仍在展示的窗口。
    // Re-attach the window when the host page is recreated while it is still visible.
    if (this.owner == null || this.mode == null) {
      return;
    }
    if (this.mode == PIP_MODE_SYSTEM) {
      host.attachPipSurface(this.owner, this.currentViewId, this.contentRatio);
    } else {
      host.attachOverlaySurface(this.owner, this.currentViewId, this.overlayLayout);
    }
  }

  clearSurfaceHost(host: FlPiPWindowSurfaceHost): void {
    if (this.surfaceHost == host) {
      this.surfaceHost = null;
    }
  }

  /** 当前窗口正在展示的内容视图 id；视频没有引擎视图，返回空字符串。 */
  private currentViewId: string = '';

  isAvailable(): boolean {
    try {
      return PiPWindow.isPiPEnabled();
    } catch (error) {
      return false;
    }
  }

  /** 当前是否有窗口（引擎或视频）可见。 / Whether any window is currently visible. */
  isActive(): boolean {
    return this.owner != null;
  }

  /** 当前窗口是否属于引擎。 / Whether the visible window belongs to the engine. */
  isEngineWindow(): boolean {
    return this.owner == PIP_OWNER_ENGINE;
  }

  /**
   * 与 Android 保持一致：系统画中画比例必须在 1/2.39 ~ 2.39 之间；0 表示未指定。
   *
   * Keeps the same range as Android: the system PiP ratio must be within 1/2.39 ~ 2.39; 0 means
   * the ratio was not provided.
   */
  static isSupportedAspectRatio(ratio: number): boolean {
    if (!(ratio > 0)) {
      return true;
    }
    const min: number = 1 / 2.39;
    const max: number = 2.39;
    return ratio >= min && ratio <= max;
  }

  /** 状态快照，字段与 Dart 的 `FlPiPStatusInfo` 保持一致。 / Snapshot of the PiP status. */
  statusMap(): Map<string, ESObject> {
    const status: Map<string, ESObject> = new Map<string, ESObject>();
    // 状态码与 Dart 的 FlPiPStatus / Android / iOS 保持一致：0 开启、1 关闭、2 不可用。
    // Keep the status codes in sync with the Dart FlPiPStatus enum, Android and iOS.
    const available: boolean = this.isAvailable();
    // 与 Android/iOS 一致：设备不支持时优先生效，不报告窗口状态。
    // Match Android/iOS: an unsupported device takes precedence over the window state.
    const active: boolean = available && this.isActive();
    status.set('status', !available ? 2 : (active ? 0 : 1));
    // 承载方式只在窗口展示时有效；字符串与 Dart 的 FlPiPPresentationMode 保持一致。
    // The presentation mode is only reported while a window is visible.
    status.set('mode', active ? this.mode : null);
    const engineName = this.pipEngineName;
    // hasEngine 只反映 presentEngine() 关联的引擎是否仍存在，与窗口是否展示无关。
    // hasEngine only reflects whether the engine from presentEngine() still exists, regardless
    // of whether the window is visible.
    const hasEngine: boolean = engineName != null &&
      FlPiPEngineManager.getInstance().hasEngine(engineName);
    status.set('hasEngine', hasEngine);
    return status;
  }

  // ---------------------------------------------------------------------------------------------
  // 引擎窗口 / Engine window
  // ---------------------------------------------------------------------------------------------

  /**
   * 展示指定引擎：`overlay` 放进应用内浮窗，`systemPip` 移入系统画中画。
   *
   * [name] 是引擎在 fl_multi_engine 中的名称，不存在时用 `pipMain` 入口补建；
   * [width] / [height] / [left] / [top] 都是**物理像素（px）**，仅 `overlay` 使用；
   * `systemPip` 只用 [aspectRatio]，为 0 时按 16:9；[destroyEngineOnDismiss] 决定窗口关闭时是否销毁引擎。
   *
   * Presents the engine called [name]. Sizes and offsets are physical pixels used by the overlay;
   * the system PiP only uses [aspectRatio] (0 falls back to 16:9). [destroyEngineOnDismiss]
   * decides whether the engine is destroyed when the window closes.
   */
  async presentEngine(
    mode: string,
    name: string,
    width: number,
    height: number,
    left: number,
    top: number,
    aspectRatio: number,
    cornerRadius: number,
    destroyEngineOnDismiss: boolean
  ): Promise<void> {
    if (name.length === 0) {
      throw new FlPiPException(FlPiPErrorCode.INVALID_CONFIGURATION, 'The engine name must not be empty');
    }
    if (this.isActive() || this.pipStarting) {
      throw new FlPiPException(FlPiPErrorCode.ALREADY_ENABLED, 'Picture-in-picture is already enabled');
    }
    if (mode != PIP_MODE_OVERLAY && !this.isAvailable()) {
      throw new FlPiPException(FlPiPErrorCode.NOT_SUPPORTED, 'Picture-in-picture is not supported on this device');
    }

    const engineManager = FlPiPEngineManager.getInstance();
    const view = engineManager.createView(name);
    const info = FlMultiEngine.status(name);
    if (info == null) {
      // 视图已创建，校验失败时必须释放，避免遗留不可见的 FlutterView。
      // The view already exists, so release it when validation fails.
      engineManager.releaseView();
      throw new FlPiPException(FlPiPErrorCode.ENGINE_NOT_FOUND, `The engine ${name} does not exist`);
    }
    if (info.isMain && destroyEngineOnDismiss) {
      engineManager.releaseView();
      throw new FlPiPException(FlPiPErrorCode.INVALID_CONFIGURATION, 'The main engine cannot be destroyed');
    }

    this.presentedEngineName = name;
    this.pipEngineName = name;
    this.destroyEngineOnDismiss = destroyEngineOnDismiss;
    this.currentViewId = view.getId();

    if (mode == PIP_MODE_OVERLAY) {
      this.contentRatio = width > 0 && height > 0 ? width / height : 16 / 9;
      this.owner = PIP_OWNER_ENGINE;
      this.mode = PIP_MODE_OVERLAY;
      this.overlayLayout = this.resolveOverlayLayout(left, top, width, height, cornerRadius, this.contentRatio);
      const host = this.surfaceHost;
      if (host == null) {
        this.resetState();
        this.releaseEngine(name, destroyEngineOnDismiss);
        throw new FlPiPException(
          FlPiPErrorCode.WINDOW_UNAVAILABLE,
          'The host page must render Flutter through FlPiPSurface before presenting picture-in-picture'
        );
      }
      host.attachOverlaySurface(PIP_OWNER_ENGINE, this.currentViewId, this.overlayLayout);
      this.notifyStatus();
      return;
    }

    // 系统画中画只用宽高比；未传时使用 16:9，实际窗口大小由系统决定。
    // The system PiP only uses the aspect ratio; it falls back to 16:9 and the system decides
    // the actual window size.
    if (!FlPiPWindowManager.isSupportedAspectRatio(aspectRatio)) {
      this.resetState();
      this.releaseEngine(name, destroyEngineOnDismiss);
      throw new FlPiPException(
        FlPiPErrorCode.INVALID_CONFIGURATION,
        'The aspect ratio must be between 1/2.39 and 2.39'
      );
    }
    this.contentRatio = aspectRatio > 0 ? aspectRatio : 16 / 9;
    const pipWidth: number = 1080;
    const pipHeight: number = Math.max(pipWidth / this.contentRatio, 1);
    try {
      await this.startSystemPip(PIP_OWNER_ENGINE, pipWidth, pipHeight, (): void => {
        this.engineWindowStopped();
      });
    } catch (error) {
      this.releaseEngine(name, destroyEngineOnDismiss);
      if (error instanceof FlPiPException) {
        throw error;
      }
      throw new FlPiPException(FlPiPErrorCode.UNKNOWN, 'Unable to enable picture-in-picture');
    }
  }

  /** 关闭引擎窗口；按展示时的 `destroyEngineOnDismiss` 决定是否销毁引擎。 */
  async dismissEngine(): Promise<void> {
    if (this.owner != PIP_OWNER_ENGINE) {
      return;
    }
    const previousMode = this.mode;
    const name = this.presentedEngineName;
    const destroy = this.destroyEngineOnDismiss;
    // 先清空状态，避免销毁引擎时再次触发窗口清理。
    // Clear the state first so destroying the engine does not tear the window down twice.
    this.resetState();
    await this.stopSystemPip();
    if (previousMode == PIP_MODE_OVERLAY) {
      this.surfaceHost?.detachOverlaySurface();
    } else {
      this.detachPipSurface();
    }
    if (name != null) {
      this.releaseEngine(name, destroy);
    }
    this.notifyStatus();
  }

  /** 引擎被外部销毁时关闭引擎窗口。 / Closes the engine window after an external destroy. */
  onEngineDestroyed(): void {
    if (this.owner != PIP_OWNER_ENGINE) {
      return;
    }
    const previousMode = this.mode;
    this.resetState();
    this.stopSystemPip().then((): void => {
      this.notifyStatus();
    });
    if (previousMode == PIP_MODE_OVERLAY) {
      this.surfaceHost?.detachOverlaySurface();
    } else {
      this.detachPipSurface();
    }
  }

  private engineWindowStopped(): void {
    const name = this.presentedEngineName;
    if (name == null) {
      return;
    }
    const destroy = this.destroyEngineOnDismiss;
    this.resetState();
    this.detachPipSurface();
    this.releaseEngine(name, destroy);
    this.notifyStatus();
  }

  /** 按展示时的设置销毁或保留引擎。 / Destroys or keeps the engine according to the presentation. */
  private releaseEngine(name: string, destroy: boolean): void {
    if (destroy) {
      FlPiPEngineManager.getInstance().destroy(name);
    } else {
      FlPiPEngineManager.getInstance().releaseView();
    }
  }

  // ---------------------------------------------------------------------------------------------
  // 视频窗口 / Video window
  // ---------------------------------------------------------------------------------------------

  /**
   * 把视频移入系统画中画窗口。
   *
   * [ratio] 是窗口宽高比，未指定时调用方按视频原始比例传入；窗口大小由系统决定。
   * [onStop] 在系统关闭窗口时回调，用于释放播放器。
   *
   * Shows the video in the system PiP window. [ratio] is the window aspect ratio (the video's
   * intrinsic ratio when not customized) and the system decides the actual size. [onStop] is
   * called when the system closes the window so the caller can release the player.
   */
  async presentVideoSystemPip(
    controller: XComponentController,
    ratio: number,
    onStop: () => void
  ): Promise<void> {
    if (this.isActive() || this.pipStarting) {
      throw new FlPiPException(FlPiPErrorCode.ALREADY_ENABLED, 'A window is already visible');
    }
    if (!this.isAvailable()) {
      throw new FlPiPException(
        FlPiPErrorCode.NOT_SUPPORTED,
        'Picture-in-picture is not supported on this device'
      );
    }
    this.currentViewId = '';
    this.contentRatio = ratio > 0 ? ratio : 16 / 9;
    // 系统画中画只用比例建窗，实际窗口大小由系统决定。
    // The system PiP only uses the ratio; the system decides the actual window size.
    const contentWidth: number = 1080;
    const contentHeight: number = Math.max(contentWidth / this.contentRatio, 1);
    await this.startSystemPip(PIP_OWNER_VIDEO, contentWidth, contentHeight, onStop, controller);
  }

  /** 把视频放进应用内浮窗。 / Shows the video in the in-app overlay. */
  presentVideoOverlay(layout: FlPiPOverlayLayout): void {
    if (this.isActive()) {
      throw new FlPiPException(FlPiPErrorCode.ALREADY_ENABLED, 'A window is already visible');
    }
    this.currentViewId = '';
    this.owner = PIP_OWNER_VIDEO;
    this.mode = PIP_MODE_OVERLAY;
    this.overlayLayout = layout;
    this.notifyStatus();
  }

  /** 关闭视频窗口，不动播放器。 / Closes the video window without touching the player. */
  async closeVideoWindow(): Promise<void> {
    if (this.owner != PIP_OWNER_VIDEO) {
      return;
    }
    const previousMode = this.mode;
    this.resetState();
    await this.stopSystemPip();
    if (previousMode == PIP_MODE_OVERLAY) {
      this.surfaceHost?.detachOverlaySurface();
    } else {
      this.detachPipSurface();
    }
    this.notifyStatus();
  }

  /** 更新应用内浮窗的布局并同步给宿主页面。 / Updates the overlay layout on the host page. */
  updateOverlayLayout(layout: FlPiPOverlayLayout): void {
    if (this.mode != PIP_MODE_OVERLAY) {
      return;
    }
    this.overlayLayout = layout;
    this.surfaceHost?.updateOverlayLayout(layout);
  }

  /** 拖动应用内浮窗到新的位置（vp），限制在屏幕范围内。 / Moves the overlay inside the screen. */
  moveOverlayTo(left: number, top: number): void {
    if (this.mode != PIP_MODE_OVERLAY) {
      return;
    }
    const screenWidth: number = px2vp(display.getDefaultDisplaySync().width);
    const screenHeight: number = px2vp(display.getDefaultDisplaySync().height);
    const maxLeft: number = Math.max(screenWidth - this.overlayLayout.width, 0);
    const maxTop: number = Math.max(screenHeight - this.overlayLayout.height, 0);
    // 与屏幕边缘保留一点间距，拖动时不会完全贴边，与 Android 悬浮窗一致。
    // Keep a small gap from the screen edges so the overlay never sits flush against one.
    const marginX: number = Math.min(FlPiPWindowManager.OVERLAY_EDGE_MARGIN_VP, maxLeft);
    const marginY: number = Math.min(FlPiPWindowManager.OVERLAY_EDGE_MARGIN_VP, maxTop);
    const maxAllowedLeft: number = Math.max(maxLeft - marginX, marginX);
    const maxAllowedTop: number = Math.max(maxTop - marginY, marginY);
    this.overlayLayout.left = Math.min(Math.max(left, marginX), maxAllowedLeft);
    this.overlayLayout.top = Math.min(Math.max(top, marginY), maxAllowedTop);
    this.surfaceHost?.updateOverlayLayout(this.overlayLayout);
  }

  /**
   * 计算应用内浮窗的最终布局。
   *
   * 入参的位置和宽高都是**物理像素（px）**，这里先用 `px2vp` 换算成本地布局单位 vp；
   * 未指定的位置和尺寸按屏幕居中并接近铺满宽度，与 Android 悬浮窗默认值一致。
   *
   * Resolves the overlay layout. The arguments are physical pixels and are converted to vp first;
   * unspecified values default to a near full-width window centered on the screen.
   */
  resolveOverlayLayout(
    leftPx: number,
    topPx: number,
    widthPx: number,
    heightPx: number,
    cornerRadius: number,
    ratio: number
  ): FlPiPOverlayLayout {
    const safeRatio: number = ratio > 0 ? ratio : 16 / 9;
    const screenWidth: number = px2vp(display.getDefaultDisplaySync().width);
    const screenHeight: number = px2vp(display.getDefaultDisplaySync().height);
    const hasWidth: boolean = widthPx > 0;
    const hasHeight: boolean = heightPx > 0;
    let width: number = hasWidth ? px2vp(widthPx) : Math.max(screenWidth - 32, 1);
    let height: number = hasHeight ? px2vp(heightPx) : Math.max(width / safeRatio, 1);
    if (!hasWidth && hasHeight) {
      width = Math.max(height * safeRatio, 1);
    }
    // 自定义宽高不能超过屏幕，保证悬浮窗整体留在屏幕内。
    // The custom size never exceeds the screen so the whole overlay stays on screen.
    width = Math.min(Math.max(width, 1), screenWidth);
    height = Math.min(Math.max(height, 1), screenHeight);
    const maxLeft: number = Math.max(screenWidth - width, 0);
    const maxTop: number = Math.max(screenHeight - height, 0);
    const left: number = leftPx >= 0 ? px2vp(leftPx) : maxLeft / 2;
    const top: number = topPx >= 0 ? px2vp(topPx) : maxTop / 2;
    return {
      left: Math.min(Math.max(left, 0), maxLeft),
      top: Math.min(Math.max(top, 0), maxTop),
      width: width,
      height: height,
      cornerRadius: cornerRadius > 0 ? cornerRadius : 12
    };
  }

  // ---------------------------------------------------------------------------------------------
  // 系统画中画 / System picture-in-picture
  // ---------------------------------------------------------------------------------------------

  private async startSystemPip(
    owner: string,
    contentWidth: number,
    contentHeight: number,
    onStop: () => void,
    surfaceController: XComponentController | null = null
  ): Promise<void> {
    this.pipStarting = true;
    this.owner = owner;
    this.mode = PIP_MODE_SYSTEM;
    try {
      // 视频窗口的媒体 XComponent 在 [FlPiPVideoManager.playVideo] 里已经挂载完成，直接使用它；
      // 引擎窗口还需要等 [FlPiPSurface] 挂载引擎 XComponent。
      // The media XComponent is already mounted by FlPiPVideoManager.playVideo for video windows;
      // the engine window still waits for FlPiPSurface to mount its XComponent.
      const controller: XComponentController = surfaceController ?? await this.waitForPipSurface();
      const pipController: PiPWindow.PiPController =
        await this.createPipController(controller, contentWidth, contentHeight, onStop);
      await pipController.startPiP();
      // 启动过程中系统可能立即上报 STOPPED 并释放控制器，此时不能再把状态置为已启动。
      // The system may report STOPPED while startPiP() is awaiting and release the controller,
      // so only mark the window as started while the controller is still alive.
      if (this.pipController == null) {
        throw new FlPiPException(
          FlPiPErrorCode.START_FAILED,
          'Picture-in-picture stopped before it was started'
        );
      }
      this.pipStarted = true;
      this.notifyStatus();
    } catch (error) {
      this.resetState();
      await this.stopSystemPip();
      this.detachPipSurface();
      this.notifyStatus();
      if (error instanceof FlPiPException) {
        throw error;
      }
      throw new FlPiPException(FlPiPErrorCode.START_FAILED, `Unable to start picture-in-picture: ${error}`);
    } finally {
      this.pipStarting = false;
    }
  }

  /**
   * 等待 [FlPiPSurface] 挂载好画中画 XComponent。
   *
   * 画中画需要的 `XComponentController` 只有在 XComponent 的 `onLoad` 之后才可用，
   * 因此必须等宿主页面完成挂载再创建控制器。
   *
   * Waits until FlPiPSurface mounted the XComponent used by PiP; the controller is only available
   * after the XComponent loads.
   */
  private waitForPipSurface(): Promise<XComponentController> {
    if (this.pipSurfaceController != null) {
      return Promise.resolve(this.pipSurfaceController);
    }
    const host = this.surfaceHost;
    if (host == null) {
      return Promise.reject(new FlPiPException(
        FlPiPErrorCode.WINDOW_UNAVAILABLE,
        'The host page must render Flutter through FlPiPSurface before enabling picture-in-picture'
      ));
    }
    return new Promise<XComponentController>((resolve: (controller: XComponentController) => void,
      reject: (reason?: ESObject) => void) => {
      this.clearPipSurfaceWaiter();
      this.pipSurfaceResolver = (controller: XComponentController): void => resolve(controller);
      this.pipSurfaceReject = (reason: FlPiPException): void => reject(reason);
      (this.surfaceHost as FlPiPWindowSurfaceHost).attachPipSurface(
        this.owner ?? PIP_OWNER_ENGINE,
        this.currentViewId,
        this.contentRatio
      );
      this.pipSurfaceTimer = setTimeout(() => {
        this.pipSurfaceTimer = -1;
        this.clearPipSurfaceWaiter();
        reject(new FlPiPException(
          FlPiPErrorCode.START_FAILED,
          'Timed out while mounting the picture-in-picture surface'
        ));
      }, 3000);
    });
  }

  /** [FlPiPSurface] 的画中画 XComponent 加载完成时回调。 / Called when the PiP XComponent loads. */
  onPipSurfaceCreated(controller: XComponentController): void {
    this.pipSurfaceController = controller;
    const resolver = this.pipSurfaceResolver;
    this.clearPipSurfaceWaiter();
    if (resolver != null) {
      resolver(controller);
    }
  }

  onPipSurfaceDestroyed(controller: XComponentController): void {
    if (this.pipSurfaceController == controller) {
      this.pipSurfaceController = null;
    }
  }

  private clearPipSurfaceWaiter(reason: FlPiPException | null = null): void {
    if (this.pipSurfaceTimer >= 0) {
      clearTimeout(this.pipSurfaceTimer);
      this.pipSurfaceTimer = -1;
    }
    this.pipSurfaceResolver = null;
    const reject = this.pipSurfaceReject;
    this.pipSurfaceReject = null;
    // 等待过程中窗口被关闭时必须中断等待，否则 startSystemPip 会一直挂起。
    // Abort a pending wait when the window is closed, otherwise startSystemPip never settles.
    if (reason != null && reject != null) {
      reject(reason);
    }
  }

  private async createPipController(
    controller: XComponentController,
    contentWidth: number,
    contentHeight: number,
    onStop: () => void
  ): Promise<PiPWindow.PiPController> {
    const config: PiPWindow.PiPConfiguration = {
      context: this.getAbilityContext(),
      componentController: controller,
      templateType: PiPWindow.PiPTemplateType.VIDEO_PLAY,
      // 两种承载方式都使用 Dart 传入的自定义宽高；未指定时回退到 16:9。
      // Both presentation modes use the custom size from Dart, falling back to 16:9.
      contentWidth: contentWidth > 0 ? contentWidth : 16,
      contentHeight: contentHeight > 0 ? contentHeight : 9
    };
    try {
      const pipController: PiPWindow.PiPController = await PiPWindow.create(config);
      this.pipStopHandler = onStop;
      // 引擎窗口使用系统画中画的自动拉起，视频窗口由 Dart 主动控制。
      // Auto-start is enabled for the engine window only; the video window is driven from Dart.
      pipController.setAutoStartEnabled(this.owner == PIP_OWNER_ENGINE);
      pipController.on('controlEvent', (event: PiPWindow.ControlEventParam) => {
        this.forwardControl(event);
      });
      pipController.on('stateChange', (state: PiPWindow.PiPState, reason: string) => {
        this.pipStarted = state == PiPWindow.PiPState.STARTED ||
          state == PiPWindow.PiPState.ABOUT_TO_STOP;
        if (state == PiPWindow.PiPState.STOPPED || state == PiPWindow.PiPState.ERROR) {
          this.pipStarted = false;
          try {
            pipController.off('stateChange');
            pipController.off('controlEvent');
          } catch (error) {
            // 控制器可能已经失效。
          }
          // 用户关闭画中画后必须关闭自动拉起，否则应用再次切后台时系统会自动弹出画中画。
          // Disable auto-start after the system stops PiP; otherwise backgrounding the app again
          // makes the system pop the window by itself.
          try {
            pipController.setAutoStartEnabled(false);
          } catch (error) {
            // 控制器可能已经失效。
          }
          if (this.pipController == pipController) {
            this.pipController = null;
          }
          const stopHandler = this.pipStopHandler;
          this.pipStopHandler = null;
          if (this.owner != null) {
            this.owner = null;
            this.mode = null;
            this.notifyStatus();
          }
          if (stopHandler != null) {
            stopHandler();
          }
        }
      });
      this.pipController = pipController;
      return pipController;
    } catch (error) {
      throw new FlPiPException(
        FlPiPErrorCode.CONTROLLER_UNAVAILABLE,
        `Unable to create the picture-in-picture controller: ${error}`
      );
    }
  }

  /**
   * 释放当前的画中画控制器。
   *
   * 控制器创建后就会注册 `stateChange` / `controlEvent` 监听，因此启动失败或关闭窗口时都必须
   * 解绑监听并关闭自动拉起，否则系统会在应用切后台时自行弹出画中画。
   *
   * Releases the current PiP controller and detaches its listeners.
   */
  private async stopSystemPip(): Promise<void> {
    this.clearPipSurfaceWaiter(new FlPiPException(
      FlPiPErrorCode.START_FAILED,
      'Picture-in-picture was stopped while mounting the surface'
    ));
    this.pipStopHandler = null;
    const controller = this.pipController;
    this.pipController = null;
    this.pipStarted = false;
    if (controller == null) {
      return;
    }
    try {
      controller.off('stateChange');
    } catch (error) {
      // 监听可能已经解绑，控制器也可能已经失效。
    }
    try {
      controller.off('controlEvent');
    } catch (error) {
      // 监听可能已经解绑。
    }
    try {
      controller.setAutoStartEnabled(false);
    } catch (error) {
      // 控制器可能已经失效。
    }
    try {
      // 解绑失败也必须关闭画中画，否则窗口会一直留在屏幕上。
      // The PiP window must still be stopped even when detaching the listeners fails.
      await controller.stopPiP();
    } catch (error) {
      // 画中画可能已经被用户关闭，stop 失败不应阻塞后续清理。
    }
  }

  private detachPipSurface(): void {
    this.pipSurfaceController = null;
    this.currentViewId = '';
    this.surfaceHost?.detachPipSurface();
  }

  /** HarmonyOS 独有：把系统画中画面板的操作转发成 `control` 消息，由引擎窗口处理。 */
  private forwardControl(event: PiPWindow.ControlEventParam): void {
    if (this.owner != PIP_OWNER_ENGINE) {
      // 视频窗口的面板操作由视频层在创建控制器时自行处理。
      // Panel actions of the video window are handled by the video layer.
      const videoNotifier = this.videoControlHandler;
      if (videoNotifier != null) {
        videoNotifier(event);
      }
      return;
    }
    const payload: Map<string, ESObject> = new Map<string, ESObject>();
    if (event.controlType == PiPWindow.PiPControlType.VIDEO_PLAY_PAUSE) {
      payload.set('action', 'playPause');
      payload.set('playing', event.status == PiPWindow.PiPControlStatus.PLAY);
    } else if (event.controlType == PiPWindow.PiPControlType.FAST_FORWARD) {
      payload.set('action', 'skip');
      payload.set('seconds', 15);
    } else if (event.controlType == PiPWindow.PiPControlType.FAST_BACKWARD) {
      payload.set('action', 'skip');
      payload.set('seconds', -15);
    } else {
      return;
    }
    const notifier = this.controlNotifier;
    if (notifier != null) {
      try {
        notifier(payload);
      } catch (error) {
        // 引擎尚未注册通道时忽略，不影响画中画窗口本身。
      }
    }
  }

  /** 视频层注册系统画中画面板的操作回调。 / Registers the video panel control handler. */
  setVideoControlHandler(handler: ((event: PiPWindow.ControlEventParam) => void) | null): void {
    this.videoControlHandler = handler;
  }

  private videoControlHandler: ((event: PiPWindow.ControlEventParam) => void) | null = null;

  // ---------------------------------------------------------------------------------------------
  // 宿主状态 / Host state
  // ---------------------------------------------------------------------------------------------

  /** 把应用切到后台；鸿蒙没有把应用拉到前台的公开 API，前台方向会被忽略。 */
  async toggle(foreground: boolean): Promise<void> {
    if (foreground) {
      return;
    }
    try {
      await this.getAbilityContext().moveAbilityToBackground();
    } catch (error) {
      // 切换前后台是 best effort，不向 Dart 抛错。
    }
  }

  private resetState(): void {
    this.owner = null;
    this.mode = null;
    this.presentedEngineName = null;
    this.destroyEngineOnDismiss = true;
    this.currentViewId = '';
    this.contentRatio = 16 / 9;
  }

  private notifyStatus(): void {
    if (this.notifier != null) {
      this.notifier(this.statusMap());
    }
  }

  private getAbilityContext(): common.UIAbilityContext {
    const ability: UIAbility = FlutterManager.getInstance().getUIAbility();
    if (ability == null) {
      throw new FlPiPException(
        FlPiPErrorCode.ACTIVITY_NOT_INITIALIZED,
        'The Flutter UIAbility is not initialized'
      );
    }
    return ability.context as common.UIAbilityContext;
  }
}
