import { common, UIAbility } from '@kit.AbilityKit';
import { FlutterEngine, FlutterManager, FlutterView } from '@ohos/flutter_ohos';
import { FlMultiEngine } from 'fl_multi_engine';
import { FlPiPErrorCode, FlPiPException } from './FlPiPError';

/** `pipMain` 引擎的 Dart 入口函数，与 Android / iOS 保持一致。 */
const ENGINE_ENTRYPOINT: string = 'pipMain';

/**
 * 画中画引擎的视图挂载与销毁，引擎实例本身统一交给引擎管理插件（fl_multi_engine）管理。
 *
 * `present()` 传入的引擎名直接使用 Flutter 通过 fl_multi_engine 创建的引擎；本类只负责给
 * 引擎挂载 `FlutterView`，并在引擎被外部销毁时通知窗口层关闭对应窗口。
 *
 * Attaches and detaches the FlutterView for engine windows. Engine instances are owned by
 * fl_multi_engine; windows reuse the named engines created by Flutter.
 */
export class FlPiPEngineManager {
  private static sharedInstance: FlPiPEngineManager | null = null;

  static getInstance(): FlPiPEngineManager {
    if (FlPiPEngineManager.sharedInstance == null) {
      FlPiPEngineManager.sharedInstance = new FlPiPEngineManager();
    }
    return FlPiPEngineManager.sharedInstance;
  }

  private view: FlutterView | null = null;
  private attachedEngineName: string | null = null;
  private destroyedNotifier: (() => void) | null = null;

  private constructor() {
    // 引擎被外部销毁时先解绑视图，再通知窗口层，避免窗口清理操作碰到已销毁的引擎。
    // Detach the view first, then notify the window layer so teardown never touches a dead engine.
    FlMultiEngine.addDestroyListener((name: string): void => {
      if (name != this.attachedEngineName) {
        return;
      }
      this.releaseView();
      const notifier = this.destroyedNotifier;
      if (notifier != null) {
        notifier();
      }
    });
  }

  /** 注册引擎被外部销毁时的回调。 / Registers the external engine destroy callback. */
  setDestroyedNotifier(notifier: (() => void) | null): void {
    this.destroyedNotifier = notifier;
  }

  /** 指定引擎是否已创建。 / Whether the engine called [name] exists. */
  hasEngine(name: string): boolean {
    return FlMultiEngine.engine(name) != null;
  }

  /**
   * 创建（或复用）指定引擎的视图；引擎不存在时用 `pipMain` 入口补建。
   *
   * Creates (or reuses) the view of the engine called [name], creating it with the `pipMain`
   * entry point when it was not created by Flutter yet.
   */
  createView(name: string): FlutterView {
    if (this.view != null && this.attachedEngineName == name) {
      return this.view;
    }
    this.releaseView();
    if (!this.hasEngine(name)) {
      try {
        FlMultiEngine.create(name, ENGINE_ENTRYPOINT);
      } catch (error) {
        throw new FlPiPException(
          FlPiPErrorCode.ENGINE_CREATION_FAILED,
          `Unable to create the engine ${name}: ${error}`
        );
      }
    }
    const engine: FlutterEngine | null = FlMultiEngine.engine(name);
    if (engine == null) {
      throw new FlPiPException(FlPiPErrorCode.ENGINE_NOT_FOUND, `The engine ${name} is unavailable`);
    }
    const view: FlutterView = this.createFlutterView(engine);
    this.view = view;
    this.attachedEngineName = name;
    return view;
  }

  /** 解绑视图并销毁指定引擎。 / Detaches the view and destroys the engine called [name]. */
  destroy(name: string): void {
    this.releaseView();
    FlMultiEngine.destroy(name);
  }

  /** 只解绑视图，不销毁引擎。 / Detaches the view without destroying the engine. */
  releaseView(): void {
    const view = this.view;
    this.view = null;
    this.attachedEngineName = null;
    if (view == null) {
      return;
    }
    try {
      view.detachFromFlutterEngine();
      FlutterManager.getInstance().deleteFlutterView(view.getId(), view);
    } catch (error) {
      // 视图可能随引擎一起销毁。
      // The view may already be destroyed together with the engine.
    }
  }

  /**
   * 为引擎创建视图并标记为可见。
   *
   * 动态创建的 FlutterView 不会经过 FlutterAbility 的生命周期回调，必须在这里补上
   * `onWindowCreated` 和页面可见状态，否则引擎不会渲染任何帧。
   *
   * Dynamic views do not receive the FlutterAbility lifecycle callbacks, so window creation and
   * page visibility must be dispatched here; otherwise the engine never draws.
   */
  private createFlutterView(engine: FlutterEngine): FlutterView {
    const view: FlutterView = FlutterManager.getInstance().createFlutterView(this.getContext());
    view.attachToFlutterEngine(engine);
    view.onWindowCreated();
    view.onPageVisibilityChanged(true);
    view.onVisibleAreaChanged(true);
    return view;
  }

  private getContext(): common.UIAbilityContext {
    const ability: UIAbility = FlutterManager.getInstance().getUIAbility();
    if (ability == null) {
      throw new FlPiPException(FlPiPErrorCode.ACTIVITY_NOT_INITIALIZED, 'The Flutter UIAbility is not initialized');
    }
    return ability.context as common.UIAbilityContext;
  }
}
