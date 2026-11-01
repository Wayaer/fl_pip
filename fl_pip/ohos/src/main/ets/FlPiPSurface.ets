import { display } from '@kit.ArkUI';
import { FlutterManager, FlutterView } from '@ohos/flutter_ohos';
import { FlPiPVideoManager, FlPiPVideoSurfaceHost } from './FlPiPVideoManager';
import {
  FlPiPOverlayLayout,
  FlPiPWindowManager,
  FlPiPWindowSurfaceHost,
  PIP_OWNER_ENGINE,
  PIP_OWNER_VIDEO
} from './FlPiPWindowManager';

/** 应用内浮窗拖动时与屏幕边缘保留的间距（vp），与 Android 的 8dp 一致。 */
const OVERLAY_EDGE_MARGIN_VP: number = 8;

/** [FlPiPWindowSurfaceHost] 的实现，把统一窗口层的回调转成组件状态。 */
class FlPiPWindowHost implements FlPiPWindowSurfaceHost {
  attachPipSurface: (owner: string, viewId: string, ratio: number) => void;
  detachPipSurface: () => void;
  attachOverlaySurface: (owner: string, viewId: string, layout: FlPiPOverlayLayout) => void;
  updateOverlayLayout: (layout: FlPiPOverlayLayout) => void;
  detachOverlaySurface: () => void;

  constructor(
    attachPipSurface: (owner: string, viewId: string, ratio: number) => void,
    detachPipSurface: () => void,
    attachOverlaySurface: (owner: string, viewId: string, layout: FlPiPOverlayLayout) => void,
    updateOverlayLayout: (layout: FlPiPOverlayLayout) => void,
    detachOverlaySurface: () => void
  ) {
    this.attachPipSurface = attachPipSurface;
    this.detachPipSurface = detachPipSurface;
    this.attachOverlaySurface = attachOverlaySurface;
    this.updateOverlayLayout = updateOverlayLayout;
    this.detachOverlaySurface = detachOverlaySurface;
  }
}

/** [FlPiPVideoSurfaceHost] 的实现，把视频层的回调转成组件状态。 */
class FlPiPVideoHost implements FlPiPVideoSurfaceHost {
  attachMediaSurface: () => void;
  detachMediaSurface: () => void;
  setMediaAspectRatio: (ratio: number) => void;
  attachMediaOverlay: (layout: FlPiPOverlayLayout, controls: Map<string, ESObject>) => void;
  updateMediaOverlayLayout: (layout: FlPiPOverlayLayout) => void;
  updateMediaOverlayPlayback: (playing: boolean, positionMs: number, durationMs: number) => void;
  setMediaOverlayControlsVisible: (visible: boolean) => void;

  constructor(
    attachMediaSurface: () => void,
    detachMediaSurface: () => void,
    setMediaAspectRatio: (ratio: number) => void,
    attachMediaOverlay: (layout: FlPiPOverlayLayout, controls: Map<string, ESObject>) => void,
    updateMediaOverlayLayout: (layout: FlPiPOverlayLayout) => void,
    updateMediaOverlayPlayback: (playing: boolean, positionMs: number, durationMs: number) => void,
    setMediaOverlayControlsVisible: (visible: boolean) => void
  ) {
    this.attachMediaSurface = attachMediaSurface;
    this.detachMediaSurface = detachMediaSurface;
    this.setMediaAspectRatio = setMediaAspectRatio;
    this.attachMediaOverlay = attachMediaOverlay;
    this.updateMediaOverlayLayout = updateMediaOverlayLayout;
    this.updateMediaOverlayPlayback = updateMediaOverlayPlayback;
    this.setMediaOverlayControlsVisible = setMediaOverlayControlsVisible;
  }
}

/**
 * 主引擎的渲染宿主，同时为引擎窗口与视频窗口提供 XComponent。
 *
 * 与官方 `FlutterPage` 不同，本组件显式持有 [XComponentController]。主页面始终保留自己的
 * surface：引擎画中画与视频都在这里额外挂载一个 XComponent，由 [FlPiPWindowManager] 与
 * [FlPiPVideoManager] 按需要求挂载、关闭时移除。
 *
 * Hosts the main engine surface plus the extra XComponent used by the engine window and the video
 * window. The main page never turns blank.
 */
@Component
export struct FlPiPSurface {
  /** 主引擎的 XComponent id，由 FlutterAbility 写入 LocalStorage。 */
  @Prop viewId: string = '';

  private controller: XComponentController = new XComponentController();
  private flutterView: FlutterView | null = null;
  private surfaceToken: number = 0;

  /** 系统画中画是否挂载、由谁占用与内容宽高比。 */
  @State pipVisible: boolean = false;
  @State pipOwner: string = '';
  @State pipViewId: string = '';
  @State pipAspectRatio: number = 16 / 9;
  private pipController: XComponentController = new XComponentController();
  private pipFlutterView: FlutterView | null = null;
  private pipSurfaceToken: number = 0;

  /** 应用内浮窗是否挂载、由谁占用以及布局（vp）。 */
  @State overlayVisible: boolean = false;
  @State overlayOwner: string = '';
  @State overlayViewId: string = '';
  @State overlayLeft: number = 0;
  @State overlayTop: number = 0;
  @State overlayWidth: number = 0;
  @State overlayHeight: number = 0;
  @State overlayCornerRadius: number = 12;
  private overlayController: XComponentController = new XComponentController();
  private overlayFlutterView: FlutterView | null = null;
  private overlaySurfaceToken: number = 0;
  private overlayDragLeft: number = 0;
  private overlayDragTop: number = 0;

  /** 媒体 XComponent 的宽高比，必须与视频比例一致，否则画面会被拉伸。 */
  @State mediaAspectRatio: number = 16 / 9;
  /** 控制面板是否可见，由视频层的自动隐藏计时控制。 */
  @State mediaControlsVisible: boolean = true;
  /** 播放状态，供控制面板绘制播放/暂停与进度。 */
  @State mediaPlaying: boolean = true;
  @State mediaPositionMs: number = 0;
  @State mediaDurationMs: number = 0;
  /** 视频浮窗拖动起点（vp）。 / Drag origin of the video overlay in vp. */
  private mediaDragLeft: number = 0;
  private mediaDragTop: number = 0;

  private windowHost: FlPiPWindowHost = new FlPiPWindowHost(
    (owner: string, viewId: string, ratio: number): void => {
      this.pipOwner = owner;
      this.pipViewId = owner == PIP_OWNER_ENGINE ? viewId : '';
      this.pipAspectRatio = ratio > 0 ? ratio : 16 / 9;
      this.pipVisible = true;
    },
    (): void => {
      this.pipVisible = false;
      this.pipOwner = '';
      this.pipViewId = '';
    },
    (owner: string, viewId: string, layout: FlPiPOverlayLayout): void => {
      this.showOverlay(owner, viewId, layout);
    },
    (layout: FlPiPOverlayLayout): void => {
      this.applyOverlayLayout(layout);
    },
    (): void => {
      this.overlayVisible = false;
      this.overlayOwner = '';
      this.overlayViewId = '';
    }
  );

  private videoHost: FlPiPVideoHost = new FlPiPVideoHost(
    (): void => {
      this.mediaAspectRatio = FlPiPVideoManager.getInstance().getContentRatio();
      this.pipOwner = PIP_OWNER_VIDEO;
      this.pipViewId = '';
      this.pipAspectRatio = this.mediaAspectRatio;
      this.pipVisible = true;
    },
    (): void => {
      if (this.pipOwner == PIP_OWNER_VIDEO) {
        this.pipVisible = false;
        this.pipOwner = '';
      }
      this.overlayVisible = false;
      this.overlayOwner = '';
      this.overlayViewId = '';
    },
    (ratio: number): void => {
      this.mediaAspectRatio = ratio;
      this.pipAspectRatio = ratio;
    },
    (layout: FlPiPOverlayLayout): void => {
      this.mediaAspectRatio = FlPiPVideoManager.getInstance().getContentRatio();
      this.mediaControlsVisible = FlPiPVideoManager.getInstance().isControlsEnabled();
      this.showOverlay(PIP_OWNER_VIDEO, '', layout);
    },
    (layout: FlPiPOverlayLayout): void => {
      this.applyOverlayLayout(layout);
    },
    (playing: boolean, positionMs: number, durationMs: number): void => {
      this.mediaPlaying = playing;
      this.mediaPositionMs = positionMs;
      this.mediaDurationMs = durationMs;
    },
    (visible: boolean): void => {
      this.mediaControlsVisible = visible;
    }
  );

  aboutToAppear(): void {
    FlPiPWindowManager.getInstance().setSurfaceHost(this.windowHost);
    FlPiPVideoManager.getInstance().setSurfaceHost(this.videoHost);
  }

  aboutToDisappear(): void {
    FlPiPWindowManager.getInstance().clearSurfaceHost(this.windowHost);
    FlPiPVideoManager.getInstance().clearSurfaceHost(this.videoHost);
  }

  /** 展示浮窗：引擎与视频共用同一份布局状态。 / Shows the overlay shared by engine and video. */
  private showOverlay(owner: string, viewId: string, layout: FlPiPOverlayLayout): void {
    this.overlayOwner = owner;
    this.overlayViewId = owner == PIP_OWNER_ENGINE ? viewId : '';
    this.applyOverlayLayout(layout);
    this.overlayDragLeft = layout.left;
    this.overlayDragTop = layout.top;
    this.mediaDragLeft = layout.left;
    this.mediaDragTop = layout.top;
    this.overlayVisible = true;
  }

  private applyOverlayLayout(layout: FlPiPOverlayLayout): void {
    this.overlayLeft = layout.left;
    this.overlayTop = layout.top;
    this.overlayWidth = layout.width;
    this.overlayHeight = layout.height;
    this.overlayCornerRadius = layout.cornerRadius;
  }

  /** 拖动引擎浮窗：限制在屏幕范围内，不会被拖出可视区域。 */
  private moveOverlay(offsetX: number, offsetY: number): void {
    const screen = display.getDefaultDisplaySync();
    const screenWidth: number = px2vp(screen.width);
    const screenHeight: number = px2vp(screen.height);
    const maxLeft: number = Math.max(screenWidth - this.overlayWidth, 0);
    const maxTop: number = Math.max(screenHeight - this.overlayHeight, 0);
    // 与屏幕边缘保留一点间距，拖动时不会完全贴边，与 Android 悬浮窗一致。
    // Keep a small gap from the screen edges so the overlay never sits flush against one.
    const marginX: number = Math.min(OVERLAY_EDGE_MARGIN_VP, maxLeft);
    const marginY: number = Math.min(OVERLAY_EDGE_MARGIN_VP, maxTop);
    const maxAllowedLeft: number = Math.max(maxLeft - marginX, marginX);
    const maxAllowedTop: number = Math.max(maxTop - marginY, marginY);
    this.overlayLeft = Math.min(Math.max(this.overlayDragLeft + offsetX, marginX), maxAllowedLeft);
    this.overlayTop = Math.min(Math.max(this.overlayDragTop + offsetY, marginY), maxAllowedTop);
  }

  /** 拖动视频浮窗：位置由统一窗口层限制在屏幕范围内。 */
  private moveMediaOverlay(offsetX: number, offsetY: number): void {
    // 只有允许拖动时才应用贴边间距，关闭拖动后浮窗仍可按传入位置贴边展示。
    // The edge gap only applies while dragging is allowed; a non-draggable overlay may stay flush.
    if (!FlPiPVideoManager.getInstance().controlFlag('allowDrag', true)) {
      return;
    }
    FlPiPWindowManager.getInstance().moveOverlayTo(this.mediaDragLeft + offsetX, this.mediaDragTop + offsetY);
  }

  /**
   * 视频画面在浮窗内的宽度（vp）。
   *
   * 宽高比与浮窗不一致时按 `contain` 自适应：浮窗更宽时高度撑满，否则宽度撑满。
   *
   * Aspect-fit width of the video inside the overlay in vp.
   */
  private mediaVideoWidth(): number {
    const ratio: number = this.mediaAspectRatio > 0 ? this.mediaAspectRatio : 16 / 9;
    if (this.overlayWidth <= 0 || this.overlayHeight <= 0) {
      return this.overlayWidth;
    }
    const containerRatio: number = this.overlayWidth / this.overlayHeight;
    return containerRatio > ratio ? this.overlayHeight * ratio : this.overlayWidth;
  }

  /** 视频画面在浮窗内的高度（vp）。 / Aspect-fit height of the video inside the overlay. */
  private mediaVideoHeight(): number {
    const ratio: number = this.mediaAspectRatio > 0 ? this.mediaAspectRatio : 16 / 9;
    if (this.overlayWidth <= 0 || this.overlayHeight <= 0) {
      return this.overlayHeight;
    }
    const containerRatio: number = this.overlayWidth / this.overlayHeight;
    return containerRatio > ratio ? this.overlayHeight : this.overlayWidth / ratio;
  }

  /** 把毫秒格式化成 `mm:ss`。 / Formats milliseconds as `mm:ss`. */
  private formatMillis(value: number): string {
    const totalSeconds: number = Math.max(Math.floor(value / 1000), 0);
    const minutes: number = Math.floor(totalSeconds / 60);
    const seconds: number = totalSeconds % 60;
    return `${minutes}:${seconds < 10 ? '0' : ''}${seconds}`;
  }

  /** 控制面板可见且被启用。 / Whether the control panel is visible and enabled. */
  private mediaControlsShown(): boolean {
    return this.mediaControlsVisible && FlPiPVideoManager.getInstance().isControlsEnabled();
  }

  /**
   * 视频浮窗的控制面板。
   *
   * 按钮与 Android 悬浮窗一致（播放/暂停、进度条），显隐由
   * `FlPiPVideoHarmonyOSOptions` 的开关决定；关闭按钮独立绘制在右上角，不随面板隐藏。
   *
   * The in-app video control panel, matching the Android overlay.
   */
  @Builder
  mediaControlPanel() {
    Column() {
      Blank()

      Column() {
        if (FlPiPVideoManager.getInstance().controlFlag('showProgress', true)) {
          Row() {
            Text(this.formatMillis(this.mediaPositionMs))
              .fontSize(11)
              .fontColor(Color.White)
            Slider({
              value: this.mediaPositionMs,
              min: 0,
              max: Math.max(this.mediaDurationMs, 1),
              style: SliderStyle.OutSet
            })
              .layoutWeight(1)
              .height(24)
              .selectedColor(Color.White)
              .onChange((value: number, mode: SliderChangeMode): void => {
                // 拖动结束后再跳转，避免拖动过程中被进度回调不断重置。
                if (mode == SliderChangeMode.End || mode == SliderChangeMode.Click) {
                  FlPiPVideoManager.getInstance().seek(value);
                }
              })
            Text(this.formatMillis(this.mediaDurationMs))
              .fontSize(11)
              .fontColor(Color.White)
          }
          .width('100%')
          .padding({ left: 6, right: 6 })
        }

        Row() {
          if (FlPiPVideoManager.getInstance().controlFlag('showPlayPause', true)) {
            // 使用系统 Symbol 图标，与 Android 的 ic_media_play / ic_media_pause 一致。
            // Use the system play/pause symbols, matching the Android media icons.
            SymbolGlyph(this.mediaPlaying ? $r('sys.symbol.pause') : $r('sys.symbol.play_fill'))
              .fontSize(20)
              .fontColor([Color.White])
              .padding(4)
              .onClick((): void => {
                FlPiPVideoManager.getInstance().toggleOverlayPlaying();
              })
          }
        }
        .width('100%')
        .justifyContent(FlexAlign.Center)
      }
      .width('100%')
      .padding({ bottom: 2 })
      .backgroundColor('#33000000')
    }
    .width('100%')
    .height('100%')
    .onClick((): void => {
      // 点击浮窗重新显示控制面板并重置自动隐藏计时。
      FlPiPVideoManager.getInstance().showOverlayControls();
    })
  }

  build() {
    Stack() {
      // 系统画中画：引擎使用独立引擎的 XComponent，视频使用媒体 XComponent。
      // 宽度铺满、高度按窗口宽高比推导，系统把这块 surface 迁入窗口后按比例缩放。
      // System PiP: the engine surface or the media surface, laid out at the window ratio.
      if (this.pipVisible && this.pipOwner == PIP_OWNER_ENGINE) {
        XComponent({
          id: this.pipViewId,
          type: XComponentType.SURFACE,
          controller: this.pipController,
          libraryname: 'flutter'
        })
          .id(this.pipViewId)
          .width('100%')
          .aspectRatio(this.pipAspectRatio)
          .onLoad(() => {
            const view: FlutterView | null = FlutterManager.getInstance().getFlutterView(this.pipViewId);
            this.pipFlutterView = view;
            if (view != null) {
              this.pipSurfaceToken = view.onSurfaceCreated();
              view.onPageVisibilityChanged(true);
              view.onVisibleAreaChanged(true);
            }
            FlPiPWindowManager.getInstance().onPipSurfaceCreated(this.pipController);
          })
          .onDestroy(() => {
            this.pipFlutterView?.onSurfaceDestroyed(this.pipSurfaceToken);
            this.pipFlutterView?.onPageVisibilityChanged(false);
            this.pipFlutterView = null;
            FlPiPWindowManager.getInstance().onPipSurfaceDestroyed(this.pipController);
          })
      } else if (this.pipVisible && this.pipOwner == PIP_OWNER_VIDEO) {
        XComponent({
          id: FlPiPVideoManager.getInstance().surfaceKey(),
          type: XComponentType.SURFACE,
          controller: FlPiPVideoManager.getInstance().controller() as XComponentController
        })
          .id(FlPiPVideoManager.getInstance().surfaceKey())
          .width('100%')
          .aspectRatio(this.pipAspectRatio)
          .backgroundColor(Color.Black)
      }

      // 主引擎 surface。
      XComponent({
        id: this.viewId,
        type: XComponentType.SURFACE,
        controller: this.controller,
        libraryname: 'flutter'
      })
        .id(this.viewId)
        .width('100%')
        .height('100%')
        .onLoad(() => {
          const view: FlutterView | null = FlutterManager.getInstance().getFlutterView(this.viewId);
          this.flutterView = view;
          if (view != null) {
            this.surfaceToken = view.onSurfaceCreated();
            view.onPageVisibilityChanged(true);
            view.onVisibleAreaChanged(true);
          }
        })
        .onDestroy(() => {
          this.flutterView?.onSurfaceDestroyed(this.surfaceToken);
          this.flutterView?.onPageVisibilityChanged(false);
          this.flutterView = null;
        })

      // 视频浮窗：按传入的物理像素宽高（换算成 vp）放置视频控件，top/left 决定浮窗位置；
      // 视频画面在控件内按比例自适应，宽或高撑满。
      // The video overlay: the view uses the pixel size converted to vp and the video aspect-fits.
      if (this.overlayVisible && this.overlayOwner == PIP_OWNER_VIDEO) {
        Stack() {
          XComponent({
            id: FlPiPVideoManager.getInstance().surfaceKey(),
            type: XComponentType.SURFACE,
            controller: FlPiPVideoManager.getInstance().controller() as XComponentController
          })
            .id(FlPiPVideoManager.getInstance().surfaceKey())
            .width(this.mediaVideoWidth())
            .height(this.mediaVideoHeight())
            .backgroundColor(Color.Black)

          // 控制面板隐藏后保留整块点击区域，点击视频任意位置可重新显示面板。
          // Keep a full-size tap target after the panel hides so tapping the video shows it again.
          if (!this.mediaControlsShown() && FlPiPVideoManager.getInstance().isControlsEnabled()) {
            Row() {
            }
              .width('100%')
              .height('100%')
              .onClick((): void => {
                FlPiPVideoManager.getInstance().showOverlayControls();
              })
          }

          if (this.mediaControlsShown()) {
            this.mediaControlPanel()
          }

          // 关闭按钮固定在右上角，不跟随控制面板自动隐藏，与 Android / iOS 一致。
          // The close button stays in the upper right corner and never auto-hides.
          if (FlPiPVideoManager.getInstance().controlFlag('showClose', true)) {
            Row() {
              Row() {
                SymbolGlyph($r('sys.symbol.xmark'))
                  .fontSize(16)
                  .fontColor([Color.White])
              }
              .width(28)
              .height(28)
              .justifyContent(FlexAlign.Center)
              .borderRadius(14)
              .backgroundColor('#66000000')
              .onClick((): void => {
                FlPiPVideoManager.getInstance().stop();
              })
            }
            .width('100%')
            .height(28)
            .padding({ left: 4, right: 4, top: 4 })
            .justifyContent(FlexAlign.End)
            .position({ x: 0, y: 0 })
            .hitTestBehavior(HitTestMode.Transparent)
          }

          // 顶部透明拖动区域，宽度留出右上角的关闭按钮，避免抢占按钮点击。
          if (FlPiPVideoManager.getInstance().controlFlag('allowDrag', true)) {
            Row() {
            }
              .width(Math.max(this.overlayWidth - 40, 1))
              .height(28)
              .position({ x: 0, y: 0 })
              .gesture(PanGesture()
                .onActionStart((): void => {
                  this.mediaDragLeft = this.overlayLeft;
                  this.mediaDragTop = this.overlayTop;
                })
                .onActionUpdate((event: GestureEvent): void => {
                  this.moveMediaOverlay(event.offsetX, event.offsetY);
                }))
          }
        }
        .width(this.overlayWidth)
        .height(this.overlayHeight)
        .position({ x: this.overlayLeft, y: this.overlayTop })
        // 视频按比例自适应后剩余的方向会留出黑边，窗口需要黑色底，避免透出下层页面。
        // The bars left by aspect-fit use the black window background instead of the page below.
        .backgroundColor(Color.Black)
        .borderRadius(this.overlayCornerRadius)
        .clip(true)
      }

      // 引擎浮窗：承载 `pipMain` 独立引擎，可拖拽、可交互，仅在本页面（应用前台）可见。
      // The engine overlay hosting the `pipMain` engine, visible only in the foreground.
      if (this.overlayVisible && this.overlayOwner == PIP_OWNER_ENGINE) {
        Stack() {
          XComponent({
            id: this.overlayViewId,
            type: XComponentType.SURFACE,
            controller: this.overlayController,
            libraryname: 'flutter'
          })
            .id(this.overlayViewId)
            .width('100%')
            .height('100%')
            .backgroundColor(Color.Black)
            .onLoad(() => {
              const view: FlutterView | null = FlutterManager.getInstance().getFlutterView(this.overlayViewId);
              this.overlayFlutterView = view;
              if (view != null) {
                this.overlaySurfaceToken = view.onSurfaceCreated();
                view.onPageVisibilityChanged(true);
                view.onVisibleAreaChanged(true);
                // 动态创建的视图在挂载时按整屏尺寸和全屏安全区布局，状态栏/导航栏的安全区内边距
                // 会被带进浮窗，内容上下因此各留出一条黑边。这里按浮窗尺寸布局。
                // A dynamic view attaches with full-screen metrics and padding; lay it out at the
                // overlay size instead so no black bands appear.
                view.onAreaChange({
                  width: this.overlayWidth,
                  height: this.overlayHeight,
                  position: { x: 0, y: 0 },
                  globalPosition: { x: 0, y: 0 }
                });
              }
            })
            .onDestroy(() => {
              this.overlayFlutterView?.onSurfaceDestroyed(this.overlaySurfaceToken);
              this.overlayFlutterView?.onPageVisibilityChanged(false);
              this.overlayFlutterView = null;
            })

          // 顶部透明拖动区域：不绘制黑色横条，内容区域保持可交互。
          Row() {
          }
            .width(Math.max(this.overlayWidth - 40, 1))
            .height(28)
            .position({ x: 0, y: 0 })
            .gesture(PanGesture()
              .onActionStart((): void => {
                this.overlayDragLeft = this.overlayLeft;
                this.overlayDragTop = this.overlayTop;
              })
              .onActionUpdate((event: GestureEvent): void => {
                this.moveOverlay(event.offsetX, event.offsetY);
              }))

          // 右上角浮动关闭按钮，样式与 Android 悬浮窗一致，使用系统 xmark 图标。
          // The floating close button uses the system xmark icon, matching the Android overlay.
          Row() {
            Row() {
              SymbolGlyph($r('sys.symbol.xmark'))
                .fontSize(16)
                .fontColor([Color.White])
            }
            .width(28)
            .height(28)
            .justifyContent(FlexAlign.Center)
            .borderRadius(14)
            .backgroundColor('#66000000')
            .onClick((): void => {
              FlPiPWindowManager.getInstance().dismissEngine();
            })
          }
          .width('100%')
          .height(28)
          .padding({ right: 4 })
          .justifyContent(FlexAlign.End)
          .position({ x: 0, y: 4 })
          .hitTestBehavior(HitTestMode.Transparent)
        }
        .width(this.overlayWidth)
        .height(this.overlayHeight)
        .position({ x: this.overlayLeft, y: this.overlayTop })
        .borderRadius(this.overlayCornerRadius)
        .clip(true)
      }
    }
    .width('100%')
    .height('100%')
  }
}
