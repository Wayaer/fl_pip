import { common, UIAbility } from '@kit.AbilityKit';
import {
  FlutterEngine,
  FlutterManager,
  FlutterPlugin,
  FlutterPluginBinding,
  MethodCall,
  MethodCallHandler,
  MethodChannel,
  MethodResult
} from '@ohos/flutter_ohos';
import FlMultiEnginePlugin, { FlMultiEngine, FlMultiEngineInfo } from 'fl_multi_engine';
import { FlPiPEngineManager } from './FlPiPEngineManager';
import { FL_PIP_CHANNEL_NAME, FlPiPErrorCode, FlPiPException } from './FlPiPError';
import { FlPiPVideoManager } from './FlPiPVideoManager';
import { FlPiPWindowManager } from './FlPiPWindowManager';

/** 一个引擎注册的 `fl_pip` 通道。 / The `fl_pip` channel registered by one engine. */
interface PipChannelEntry {
  engine: FlutterEngine;
  channel: MethodChannel;
}

/**
 * fl_pip 的 HarmonyOS 平台通道入口，只负责参数解析与方法分派。
 *
 * 窗口、引擎与视频分别由 [FlPiPWindowManager]、[FlPiPEngineManager] 与 [FlPiPVideoManager]
 * 处理，本类不持有任何状态。`send` 只投递给 `present(name:)` 指定的画中画引擎，该引擎发送时
 * 回到主引擎。
 *
 * The HarmonyOS platform channel entry point of fl_pip. It only parses arguments and dispatches
 * calls; the window, engine and video layers own the state. `send` only reaches the
 * picture-in-picture engine selected by `present(name:)`, whose own `send` goes back to the main
 * engine.
 */
export default class FlPiPPlugin implements FlutterPlugin, MethodCallHandler {
  /**
   * 宿主 App 注册生成插件的回调，用于给 `pipMain` 引擎注册插件。
   *
   * 设置后同步转发给 fl_multi_engine，宿主只需设置 fl_pip 的回调。
   *
   * Registers the generated plugins on the `pipMain` engine. The callback is forwarded to
   * fl_multi_engine so the host only needs to configure the fl_pip one.
   */
  static set pluginRegistrant(registrant: ((engine: FlutterEngine) => void) | null) {
    if (registrant == null) {
      FlMultiEnginePlugin.pluginRegistrant = null;
      return;
    }
    FlMultiEnginePlugin.pluginRegistrant = (engine: FlutterEngine): void => {
      registrant(engine);
    };
  }

  private static readonly pipChannels: Array<PipChannelEntry> = new Array<PipChannelEntry>();
  private static notifiersRegistered: boolean = false;
  /** 未知方法的内部标记，最终转成 `MethodResult.notImplemented()`。 */
  private static readonly NOT_IMPLEMENTED: string = 'fl_pip_not_implemented';

  private channel: MethodChannel | null = null;

  getUniqueClassName(): string {
    return 'FlPiPPlugin';
  }

  onAttachedToEngine(binding: FlutterPluginBinding): void {
    const channel = new MethodChannel(binding.getBinaryMessenger(), FL_PIP_CHANNEL_NAME);
    channel.setMethodCallHandler(this);
    this.channel = channel;
    FlPiPPlugin.pipChannels.push({ engine: binding.getFlutterEngine(), channel: channel });

    FlPiPPlugin.ensureNotifiers();
    FlPiPVideoManager.getInstance().setBinding(binding);
  }

  onDetachedFromEngine(binding: FlutterPluginBinding): void {
    const attached: MethodChannel | null = this.channel;
    if (attached != null) {
      const index: number = FlPiPPlugin.pipChannels.findIndex(
        (entry: PipChannelEntry): boolean => entry.channel == attached
      );
      if (index >= 0) {
        FlPiPPlugin.pipChannels.splice(index, 1);
        attached.setMethodCallHandler(null);
      }
    }
    this.channel = null;
  }

  onMethodCall(call: MethodCall, result: MethodResult): void {
    this.handle(call)
      .then((value: ESObject) => result.success(value))
      .catch((error: ESObject) => {
        if (error instanceof FlPiPException && error.code == FlPiPPlugin.NOT_IMPLEMENTED) {
          // 与 Android / iOS 的 `FlutterMethodNotImplemented` 对齐。
          // Match `FlutterMethodNotImplemented` on Android / iOS.
          result.notImplemented();
        } else if (error instanceof FlPiPException) {
          result.error(error.code, error.message, null);
        } else {
          const message = error instanceof Error ? error.message : 'Unknown fl_pip error';
          result.error(FlPiPErrorCode.UNKNOWN, message, null);
        }
      });
  }

  private async handle(call: MethodCall): Promise<ESObject> {
    const windowManager: FlPiPWindowManager = FlPiPWindowManager.getInstance();
    switch (call.method) {
      case 'available':
        return windowManager.isAvailable();

      case 'present': {
        const mode: string = (call.argument('mode') as string | null) ?? '';
        const name: string = (call.argument('name') as string | null) ?? '';
        const destroyEngineOnDismiss: boolean =
          (call.argument('destroyEngineOnDismiss') as boolean | null) ?? true;
        await windowManager.presentEngine(
          mode,
          name,
          this.readNumber(call, 'width', 0),
          this.readNumber(call, 'height', 0),
          this.readNumber(call, 'left', -1),
          this.readNumber(call, 'top', -1),
          this.readAspectRatio(call),
          this.readNumber(call, 'cornerRadius', 12),
          destroyEngineOnDismiss
        );
        const info = FlMultiEngine.status(name);
        if (info == null) {
          throw new FlPiPException(FlPiPErrorCode.ENGINE_NOT_FOUND, `The engine ${name} does not exist`);
        }
        return info.toMap();
      }

      case 'dismiss':
        await windowManager.dismissEngine();
        return true;

      case 'isActive':
        return windowManager.statusMap();

      case 'toggle':
        // Dart 直接发送布尔值；不能按 Map 读取，否则会抛类型异常。
        // Dart sends a raw boolean, so read the arguments directly rather than a map key.
        await windowManager.toggle((call.args as boolean | null) ?? true);
        return null;

      case 'send':
        return this.send(call);

      case 'playVideo':
        return this.playVideo(call);

      case 'stopVideo':
        return FlPiPVideoManager.getInstance().stop();

      case 'isVideoActive':
        return FlPiPVideoManager.getInstance().isActive();

      case 'setVideoPlaying':
        return FlPiPVideoManager.getInstance().setPlaying((call.argument('playing') as boolean | null) ?? false);

      case 'seekVideo':
        return FlPiPVideoManager.getInstance().seek((call.argument('positionMs') as number | null) ?? 0);

      case 'seekVideoBy':
        return FlPiPVideoManager.getInstance().seekBy((call.argument('offsetMs') as number | null) ?? 0);

      case 'stopVideoPlayback':
        return FlPiPVideoManager.getInstance().stopPlayback();

      case 'setVideoSpeed':
        return FlPiPVideoManager.getInstance().setSpeed((call.argument('speed') as number | null) ?? 1);

      case 'setVideoVolume':
        return FlPiPVideoManager.getInstance().setVolume((call.argument('volume') as number | null) ?? 0);

      case 'setVideoLooping':
        return FlPiPVideoManager.getInstance().setLooping((call.argument('loop') as boolean | null) ?? false);

      case 'getVideoStatus':
        return FlPiPVideoManager.getInstance().getStatus();

      default:
        throw new FlPiPException(FlPiPPlugin.NOT_IMPLEMENTED, `The method ${call.method} is not implemented`);
    }
  }

  /**
   * 向画中画引擎投递消息：主引擎发往 `present(name:)` 指定的引擎，该引擎发往主引擎。
   *
   * 只投递一次，返回送达数量（`1` 或 `0`），其他引擎不会收到消息。
   *
   * Delivers a message to the picture-in-picture engine, or back to the main engine when the
   * picture-in-picture engine sends; other engines never receive it.
   */
  private send(call: MethodCall): number {
    const method: string = (call.argument('method') as string | null) ?? 'message';
    const payload: Map<string, ESObject> = new Map<string, ESObject>();
    payload.set('method', method);
    payload.set('arguments', call.argument('arguments') as ESObject);
    const target: MethodChannel | null = this.resolveMessageTarget();
    if (target == null) {
      return 0;
    }
    target.invokeMethod('onMessage', payload);
    return 1;
  }

  /** 解析消息目标通道；没有画中画引擎时返回 null。 / Resolves the message target channel. */
  private resolveMessageTarget(): MethodChannel | null {
    const pipName: string | null = FlPiPWindowManager.getInstance().pipEngineNameForMessages;
    if (pipName == null) {
      return null;
    }
    const pipChannel: MethodChannel | null = FlPiPPlugin.channelOf(pipName);
    if (pipChannel == null) {
      return null;
    }
    if (pipChannel != this.channel) {
      return pipChannel;
    }
    // 画中画引擎向主引擎发消息。 / The picture-in-picture engine sends back to the main engine.
    const main: FlMultiEngineInfo | undefined =
      FlMultiEngine.engines().find((info: FlMultiEngineInfo): boolean => info.isMain);
    if (main == undefined) {
      return null;
    }
    const mainChannel: MethodChannel | null = FlPiPPlugin.channelOf(main.name);
    // 主引擎本身是画中画引擎时没有其他引擎可投递。
    if (mainChannel == null || mainChannel == this.channel) {
      return null;
    }
    return mainChannel;
  }

  /** 返回指定引擎注册的 `fl_pip` 通道。 / Returns the `fl_pip` channel of the named engine. */
  private static channelOf(name: string): MethodChannel | null {
    const engine: FlutterEngine | null = FlMultiEngine.engine(name);
    if (engine == null) {
      return null;
    }
    const entry: PipChannelEntry | undefined =
      FlPiPPlugin.pipChannels.find((item: PipChannelEntry): boolean => item.engine == engine);
    if (entry == undefined) {
      return null;
    }
    return entry.channel;
  }

  private async playVideo(call: MethodCall): Promise<boolean> {
    return FlPiPVideoManager.getInstance().playVideo(
      this.getContext(),
      (call.argument('type') as string | null) ?? '',
      (call.argument('uri') as string | null) ?? '',
      (call.argument('packageName') as string | null),
      (call.argument('loop') as boolean | null) ?? false,
      (call.argument('muted') as boolean | null) ?? false,
      this.readNumber(call, 'width', 0),
      this.readNumber(call, 'height', 0),
      this.readNumber(call, 'left', -1),
      this.readNumber(call, 'top', -1),
      (call.argument('mode') as string | null) ?? '',
      this.readAspectRatio(call),
      this.readNumber(call, 'cornerRadius', 12),
      this.readControls(call)
    );
  }

  private readControls(call: MethodCall): Map<string, ESObject> | null {
    const controls: Map<ESObject, ESObject> | null = call.argument('controls') as Map<ESObject, ESObject> | null;
    if (controls == null) {
      return null;
    }
    const result: Map<string, ESObject> = new Map<string, ESObject>();
    controls.forEach((value: ESObject, key: ESObject) => {
      if (typeof key == 'string') {
        result.set(key as string, value);
      }
    });
    return result;
  }

  /** 读取可选的 double 参数；参数缺失时返回 [fallback]。 */
  private readNumber(call: MethodCall, key: string, fallback: number): number {
    const value = call.argument(key) as number | null;
    return value == null ? fallback : value;
  }

  /** 读取可选宽高比，单位为 numerator / denominator；缺省或非法时返回 0。 */
  private readAspectRatio(call: MethodCall): number {
    const numerator = call.argument('numerator') as number | null;
    const denominator = call.argument('denominator') as number | null;
    if (numerator == null || denominator == null || numerator <= 0 || denominator <= 0) {
      return 0;
    }
    return numerator / denominator;
  }

  private getContext(): common.UIAbilityContext {
    const ability: UIAbility = FlutterManager.getInstance().getUIAbility();
    if (ability == null) {
      throw new FlPiPException(FlPiPErrorCode.ACTIVITY_NOT_INITIALIZED, 'The Flutter UIAbility is not initialized');
    }
    return ability.context as common.UIAbilityContext;
  }

  /**
   * 注册三个原生通知：画中画状态、引擎面板操作与视频事件。
   *
   * Registers the native notifiers for the PiP status, engine panel actions and video events.
   */
  private static ensureNotifiers(): void {
    if (FlPiPPlugin.notifiersRegistered) {
      return;
    }
    FlPiPPlugin.notifiersRegistered = true;
    const broadcast = (method: string, payload: Map<string, ESObject>): void => {
      FlPiPPlugin.pipChannels.forEach((entry: PipChannelEntry) => entry.channel.invokeMethod(method, payload));
    };
    FlPiPWindowManager.getInstance().setStatusNotifier((status: Map<string, ESObject>): void => {
      broadcast('onPiPStatus', status);
    });
    // HarmonyOS 独有：把系统画中画面板的操作转发成 `onMessage` 里的 `control` 消息。
    // HarmonyOS only: forward system PiP panel actions as `control` messages.
    FlPiPWindowManager.getInstance().setControlNotifier((payload: Map<string, ESObject>): void => {
      const message: Map<string, ESObject> = new Map<string, ESObject>();
      message.set('method', 'control');
      message.set('arguments', payload);
      broadcast('onMessage', message);
    });
    FlPiPVideoManager.getInstance().setEventNotifier((payload: Map<string, ESObject>): void => {
      broadcast('onVideoEvent', payload);
    });
    // 引擎被外部销毁时由窗口层关闭它占用的窗口。
    FlPiPEngineManager.getInstance().setDestroyedNotifier((): void => {
      FlPiPWindowManager.getInstance().onEngineDestroyed();
    });
  }
}
