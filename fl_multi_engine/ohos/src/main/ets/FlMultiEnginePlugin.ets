import { FlutterEngine, FlutterInjector, FlutterPlugin, FlutterPluginBinding, MethodCall, MethodCallHandler, MethodChannel, MethodResult } from '@ohos/flutter_ohos';
import FlutterEngineGroup, { Options } from '@ohos/flutter_ohos/src/main/ets/embedding/engine/FlutterEngineGroup';
import { DartEntrypoint } from '@ohos/flutter_ohos/src/main/ets/embedding/engine/dart/DartExecutor';
import common from '@ohos.app.ability.common';

const CHANNEL_NAME = 'fl_multi_engine';
const MAIN_NAME = 'main';
// 销毁监听器最多等待这么久，超时后仍销毁引擎，避免监听器卡住时引擎永远不释放。
// Destroy listeners are awaited for at most this long so an engine is still released on timeout.
const DESTROY_LISTENER_TIMEOUT_MS = 2000;

/**
 * 与 Dart 侧 `FlMultiEngineErrorCode` 一一对应的稳定错误码。
 *
 * Stable error codes shared with the Dart implementation.
 */
class FlMultiEngineErrorCode {
  static readonly NOT_SUPPORTED: string = 'not_supported';
  static readonly INVALID_NAME: string = 'invalid_name';
  static readonly ENGINE_EXISTS: string = 'engine_exists';
  static readonly CREATE_FAILED: string = 'create_failed';
  static readonly MAIN_ENGINE_NOT_DESTROYABLE: string = 'main_engine_not_destroyable';
  static readonly NOT_INITIALIZED: string = 'not_initialized';
  static readonly UNKNOWN: string = 'unknown';
}

/**
 * 描述一个由 fl_multi_engine 管理的引擎。
 *
 * Describes an engine managed by fl_multi_engine.
 */
export class FlMultiEngineInfo {
  readonly name: string;
  readonly entrypoint: string;
  readonly state: string;
  readonly createdAt: number;
  readonly isMain: boolean;

  constructor(name: string, entrypoint: string, state: string, createdAt: number, isMain: boolean) {
    this.name = name;
    this.entrypoint = entrypoint;
    this.state = state;
    this.createdAt = createdAt;
    this.isMain = isMain;
  }

  /** 转换成平台通道使用的 Map。 / Converts the info into a platform channel map. */
  toMap(): Map<string, ESObject> {
    const map: Map<string, ESObject> = new Map<string, ESObject>();
    map.set('name', this.name);
    map.set('entrypoint', this.entrypoint);
    map.set('state', this.state);
    map.set('createdAt', this.createdAt);
    map.set('isMain', this.isMain);
    return map;
  }
}

/** 引擎管理器抛出的错误，code 与 Dart 侧的错误码一一对应。 / An error reported by the engine manager. */
export class FlMultiEngineException extends Error {
  readonly code: string;

  constructor(code: string, message: string) {
    super(message);
    this.code = code;
  }
}

class FlMultiEngineEntry {
  readonly name: string;
  readonly entrypoint: string;
  readonly engine: FlutterEngine | null;
  readonly isMain: boolean;
  readonly createdAt: number;
  channel: MethodChannel | null = null;
  state: string = 'running';

  constructor(name: string, entrypoint: string, engine: FlutterEngine | null, isMain: boolean) {
    this.name = name;
    this.entrypoint = entrypoint;
    this.engine = engine;
    this.isMain = isMain;
    this.createdAt = Date.now();
  }

  toInfo(): FlMultiEngineInfo {
    return new FlMultiEngineInfo(this.name, this.entrypoint, this.state, this.createdAt, this.isMain);
  }
}

export class FlMultiEngineNativeListener {
  readonly engineName: string;
  readonly method: string | null;
  readonly callback: (sender: string, method: string, value: Map<string, ESObject>) => void;

  constructor(
    engineName: string,
    method: string | null,
    callback: (sender: string, method: string, value: Map<string, ESObject>) => void
  ) {
    this.engineName = engineName;
    this.method = method;
    this.callback = callback;
  }
}

/**
 * 命名引擎的注册表：维护引擎实例、通道、生命周期状态以及原生监听器。
 *
 * Registry of named engines: instances, channels, lifecycle state and native listeners.
 */
export class FlMultiEngineRegistry {
  private static sharedInstance: FlMultiEngineRegistry | null = null;

  static get instance(): FlMultiEngineRegistry {
    if (FlMultiEngineRegistry.sharedInstance == null) {
      FlMultiEngineRegistry.sharedInstance = new FlMultiEngineRegistry();
    }
    return FlMultiEngineRegistry.sharedInstance;
  }

  private entries: Map<string, FlMultiEngineEntry> = new Map<string, FlMultiEngineEntry>();
  private pendingNames: Map<FlutterEngine, string> = new Map<FlutterEngine, string>();
  private listeners: Array<FlMultiEngineNativeListener> = [];
  private destroyListeners: Array<(name: string) => Promise<void> | void> = [];
  private context: common.Context | null = null;
  private engineGroup: FlutterEngineGroup | null = null;
  private mainAttached: boolean = false;

  private constructor() {
  }

  /** 返回全局共享的引擎组，保证同组引擎共享渲染等资源。 / Returns the shared engine group. */
  sharedGroup(): FlutterEngineGroup {
    if (this.engineGroup == null) {
      this.engineGroup = new FlutterEngineGroup();
    }
    return this.engineGroup;
  }

  attachMain(engine: FlutterEngine, context: common.Context): void {
    this.context = context;
    // main 一旦注册过，后续再出现的「未命名引擎」都属于外部引擎（例如 fl_pip 的 pipMain），
    // 不能把它们当成 main，否则会覆盖主引擎的通道。
    this.mainAttached = true;
    if (this.entries.has(MAIN_NAME)) {
      return;
    }
    this.entries.set(MAIN_NAME, new FlMultiEngineEntry(MAIN_NAME, 'main', engine, true));
  }

  /** 返回引擎名称：由 [create] 创建的引擎返回自己的名字；外部引擎在 main 已注册后返回 null。 */
  takePendingName(engine: FlutterEngine): string | null {
    const name = this.pendingNames.get(engine);
    if (name != null) {
      this.pendingNames.delete(engine);
      return name;
    }
    return this.mainAttached ? null : MAIN_NAME;
  }

  /** 记录引擎对应的 MethodChannel，供定向消息投递使用。 */
  registerChannel(name: string, channel: MethodChannel): void {
    const entry = this.entries.get(name);
    if (entry != null) {
      entry.channel = channel;
    }
  }

  /** 引擎销毁时清除通道引用，避免向已失效的引擎发送消息。 */
  unregisterChannel(name: string, channel: MethodChannel): void {
    const entry = this.entries.get(name);
    if (entry != null && entry.channel == channel) {
      entry.channel = null;
    }
  }

  /**
   * 创建并启动命名引擎。
   *
   * Creates and starts a named engine. The engine name is registered before the plugins are
   * attached so that the new engine is not mistaken for the main engine.
   */
  create(name: string, entrypoint: string, entrypointArgs: Array<string>): FlMultiEngineInfo {
    if (name.length === 0 || entrypoint.length === 0) {
      throw new FlMultiEngineException(
        FlMultiEngineErrorCode.INVALID_NAME,
        'The engine name and entry point must not be empty'
      );
    }
    const context = this.context;
    if (context == null) {
      throw new FlMultiEngineException(
        FlMultiEngineErrorCode.NOT_INITIALIZED,
        'fl_multi_engine is not attached to the main engine'
      );
    }
    if (name === MAIN_NAME || this.entries.has(name)) {
      throw new FlMultiEngineException(FlMultiEngineErrorCode.ENGINE_EXISTS, `The engine ${name} already exists`);
    }

    const loader = FlutterInjector.getInstance().getFlutterLoader();
    const dartEntrypoint = new DartEntrypoint(loader.findAppBundlePath(), '', entrypoint);
    const options = new Options(context);
    options.setDartEntrypoint(dartEntrypoint);
    options.setDartEntrypointArgs(entrypointArgs);

    let engine: FlutterEngine;
    try {
      engine = this.sharedGroup().createAndRunEngineByOptions(options);
    } catch (error) {
      throw new FlMultiEngineException(
        FlMultiEngineErrorCode.CREATE_FAILED,
        `Unable to create the engine ${name}: ${error}`
      );
    }

    const entry = new FlMultiEngineEntry(name, entrypoint, engine, false);
    this.entries.set(name, entry);
    // 先登记名称，再注册插件，插件 onAttachedToEngine 才能拿到正确的引擎名。
    this.pendingNames.set(engine, name);

    try {
      const registrant = FlMultiEnginePlugin.pluginRegistrant;
      if (registrant != null) {
        registrant(engine);
      }
      // 宿主 App 没有提供注册回调时，至少保证 fl_multi_engine 自身在新引擎上可用。
      if (entry.channel == null) {
        engine.getPlugins()?.add(new FlMultiEnginePlugin());
      }
    } catch (error) {
      this.pendingNames.delete(engine);
      this.entries.delete(name);
      engine.destroy();
      throw new FlMultiEngineException(
        FlMultiEngineErrorCode.CREATE_FAILED,
        `Unable to register plugins on ${name}: ${error}`
      );
    }

    this.notifyEnginesChanged();
    return entry.toInfo();
  }

  /** 销毁指定引擎。 / Destroys the engine called [name]. */
  destroy(name: string): boolean {
    const entry = this.entries.get(name);
    if (entry == null) {
      return false;
    }
    if (entry.isMain) {
      throw new FlMultiEngineException(
        FlMultiEngineErrorCode.MAIN_ENGINE_NOT_DESTROYABLE,
        'The main engine cannot be destroyed'
      );
    }
    entry.channel?.setMethodCallHandler(null);
    entry.state = 'disposed';
    this.entries.delete(name);
    const engine = entry.engine;
    if (engine != null) {
      this.pendingNames.delete(engine);
    }
    // 监听器里通常会关闭挂在该引擎上的悬浮窗并解绑视图，这些操作仍要访问引擎，
    // 因此必须等监听器全部完成后再销毁引擎，避免视图清理碰到已销毁的引擎。
    //
    // Listeners usually close the float view and detach the view mounted on this engine, and
    // those steps still use the engine. Wait for all listeners before destroying it.
    this.notifyDestroyedAsync(name).then(() => {
      if (engine != null) {
        try {
          engine.destroy();
        } catch (error) {
          // 引擎可能已经被系统回收，销毁失败不应影响列表通知。
          // The engine may already be reclaimed; keep notifying the engine list.
        }
      }
      this.notifyEnginesChanged();
    });
    return true;
  }

  /** 通知 Flutter 侧引擎列表发生变化；只发通知，不携带引擎数据。 */
  notifyEnginesChanged(): void {
    const entry = this.entries.get(MAIN_NAME);
    const channel = entry?.channel;
    if (channel == null) {
      return;
    }
    const targetChannel: MethodChannel = channel;
    // 延后到当前调用返回之后再通知，避免通知和 create/destroy 的结果竞争。
    setTimeout(() => targetChannel.invokeMethod('onEnginesChanged', null), 0);
  }

  private notifyDestroyedAsync(name: string): Promise<void> {
    const pending: Array<Promise<void>> = new Array<Promise<void>>();
    this.destroyListeners.forEach((listener: (name: string) => Promise<void> | void) => {
      try {
        const result: Promise<void> | void = listener(name);
        // 监听器返回的 Promise 失败也不能阻止引擎销毁，这里统一吞掉错误。
        // A rejected listener must not block engine destruction either.
        pending.push(Promise.resolve(result).then(() => {}).catch(() => {}));
      } catch (error) {
        // 单个监听器失败不应该阻止引擎销毁。
        // A single listener must not block engine destruction.
      }
    });
    // 监听器可能等待悬浮窗关闭等异步操作；超时后仍要销毁引擎，否则会泄漏引擎。
    // Listeners may wait for asynchronous window teardown; destroy the engine on timeout anyway.
    const waitAll: Promise<void> = Promise.all(pending).then(() => {});
    const timeout: Promise<void> = new Promise<void>((resolve: () => void) => {
      setTimeout(() => resolve(), DESTROY_LISTENER_TIMEOUT_MS);
    });
    return Promise.race([waitAll, timeout]);
  }

  addDestroyListener(listener: (name: string) => Promise<void> | void): void {
    this.destroyListeners.push(listener);
  }

  removeDestroyListener(listener: (name: string) => Promise<void> | void): void {
    const index = this.destroyListeners.indexOf(listener);
    if (index >= 0) {
      this.destroyListeners.splice(index, 1);
    }
  }

  list(): Array<FlMultiEngineInfo> {
    const result = new Array<FlMultiEngineInfo>();
    this.entries.forEach((entry: FlMultiEngineEntry) => result.push(entry.toInfo()));
    return result;
  }

  status(name: string): FlMultiEngineInfo | null {
    return this.entries.get(name)?.toInfo() ?? null;
  }

  engine(name: string): FlutterEngine | null {
    return this.entries.get(name)?.engine ?? null;
  }

  /**
   * 把消息定向投递给 [target] 引擎的 Dart 侧，同时通知该引擎上的原生监听器。
   * 返回 1 表示目标存在，0 表示目标不存在或尚未注册通道。
   */
  send(sender: string, target: string, method: string, value: Map<string, ESObject>): number {
    const entry = this.entries.get(target);
    if (entry == null || entry.channel == null) {
      return 0;
    }
    const payload: Map<string, ESObject> = new Map<string, ESObject>();
    payload.set('sender', sender);
    payload.set('method', method);
    payload.set('value', value);
    entry.channel.invokeMethod('onMessage', payload);
    this.listeners
      .filter((listener: FlMultiEngineNativeListener) => {
        return listener.engineName == target && (listener.method == null || listener.method == method);
      })
      .forEach((listener: FlMultiEngineNativeListener) => listener.callback(sender, method, value));
    return 1;
  }

  addListener(
    engineName: string,
    method: string | null,
    callback: (sender: string, method: string, value: Map<string, ESObject>) => void
  ): FlMultiEngineNativeListener {
    const listener = new FlMultiEngineNativeListener(engineName, method, callback);
    this.listeners.push(listener);
    return listener;
  }

  removeListener(listener: FlMultiEngineNativeListener): void {
    const index = this.listeners.indexOf(listener);
    if (index >= 0) {
      this.listeners.splice(index, 1);
    }
  }
}

/**
 * 在每个 Flutter 引擎上注册 fl_multi_engine 通道。
 *
 * The plugin is attached to the main engine by the Flutter tool and to every engine created by
 * [FlMultiEngineRegistry]. The channel identity is used as the sender of messages.
 */
export default class FlMultiEnginePlugin implements FlutterPlugin, MethodCallHandler {
  static readonly mainName: string = MAIN_NAME;

  /**
   * Registers the generated app plugins on engines created by [FlMultiEngineRegistry].
   *
   * Set this in `EntryAbility.configureFlutterEngine`:
   *
   * ```ts
   * GeneratedPluginRegistrant.registerWith(flutterEngine)
   * FlMultiEnginePlugin.pluginRegistrant = (engine: FlutterEngine) => {
   *   GeneratedPluginRegistrant.registerWith(engine)
   * }
   * ```
   */
  static pluginRegistrant: ((engine: FlutterEngine) => void) | null = null;

  private channel: MethodChannel | null = null;
  private engineName: string | null = null;

  getUniqueClassName(): string {
    return 'FlMultiEnginePlugin';
  }

  onAttachedToEngine(binding: FlutterPluginBinding): void {
    const engine = binding.getFlutterEngine();
    const registry = FlMultiEngineRegistry.instance;
    const name = registry.takePendingName(engine);
    this.engineName = name;

    const methodChannel = new MethodChannel(binding.getBinaryMessenger(), CHANNEL_NAME);
    methodChannel.setMethodCallHandler(this);
    this.channel = methodChannel;

    if (name === MAIN_NAME) {
      registry.attachMain(engine, binding.getApplicationContext());
      registry.registerChannel(MAIN_NAME, methodChannel);
    } else if (name != null) {
      // 外部引擎同样可以收发消息，但不能登记成任何命名引擎，否则会覆盖 main 的通道。
      registry.registerChannel(name, methodChannel);
    }
  }

  onDetachedFromEngine(binding: FlutterPluginBinding): void {
    const name = this.engineName;
    if (name != null && this.channel != null) {
      FlMultiEngineRegistry.instance.unregisterChannel(name, this.channel);
    }
    this.channel?.setMethodCallHandler(null);
    this.channel = null;
  }

  onMethodCall(call: MethodCall, result: MethodResult): void {
    try {
      switch (call.method) {
        case 'currentEngineName':
          result.success(this.engineName);
          break;

        case 'create': {
          const name = (call.argument('name') as string | null) ?? '';
          const entrypoint = (call.argument('entrypoint') as string | null) ?? '';
          const argumentsValue = call.argument('arguments') as Array<string> | null;
          const entrypointArgs = argumentsValue == null ? new Array<string>() : argumentsValue;
          // 只返回创建成功的唯一 ID，Dart 侧会重新拉取引擎列表并筛选。
          const info = FlMultiEngineRegistry.instance.create(name, entrypoint, entrypointArgs);
          result.success(info.name);
          break;
        }

        case 'destroy': {
          const name = (call.argument('name') as string | null) ?? '';
          result.success(FlMultiEngineRegistry.instance.destroy(name));
          break;
        }

        case 'list': {
          const infos = FlMultiEngineRegistry.instance.list();
          const maps: Array<Map<string, ESObject>> = new Array<Map<string, ESObject>>();
          infos.forEach((info: FlMultiEngineInfo) => maps.push(info.toMap()));
          result.success(maps);
          break;
        }

        case 'status': {
          const name = (call.argument('name') as string | null) ?? '';
          result.success(FlMultiEngineRegistry.instance.status(name)?.toMap() ?? null);
          break;
        }

        case 'send': {
          const target = (call.argument('target') as string | null) ?? '';
          const method = (call.argument('method') as string | null) ?? 'message';
          const value: Map<string, ESObject> = this.readMapArgument(call.argument('value'));
          result.success(FlMultiEngineRegistry.instance.send(this.engineName ?? '', target, method, value));
          break;
        }

        default:
          result.notImplemented();
          break;
      }
    } catch (error) {
      if (error instanceof FlMultiEngineException) {
        result.error(error.code, error.message, null);
      } else {
        const message = error instanceof Error ? error.message : 'Unknown fl_multi_engine error';
        result.error(FlMultiEngineErrorCode.UNKNOWN, message, null);
      }
    }
  }

  private readMapArgument(argument: ESObject): Map<string, ESObject> {
    const result: Map<string, ESObject> = new Map<string, ESObject>();
    const source: Map<ESObject, ESObject> | null = argument as Map<ESObject, ESObject> | null;
    if (source == null) {
      return result;
    }
    source.forEach((value: ESObject, key: ESObject) => {
      if (typeof key == 'string') {
        result.set(key as string, value);
      }
    });
    return result;
  }
}

/**
 * 命名引擎管理器的原生入口，宿主 App 可以不经过 Flutter 直接创建、销毁和查询引擎。
 * 插件与 Flutter 侧共用同一份注册表。
 */
export class FlMultiEngine {
  /** 创建并启动一个运行 [entrypoint] 的命名引擎。 */
  static create(
    name: string,
    entrypoint: string,
    entrypointArgs: Array<string> = new Array<string>()
  ): FlMultiEngineInfo {
    return FlMultiEngineRegistry.instance.create(name, entrypoint, entrypointArgs);
  }

  /** 销毁指定引擎，主引擎不允许销毁。 */
  static destroy(name: string): boolean {
    return FlMultiEngineRegistry.instance.destroy(name);
  }

  /** 返回所有已注册引擎（包含主引擎）。 */
  static engines(): Array<FlMultiEngineInfo> {
    return FlMultiEngineRegistry.instance.list();
  }

  /** 返回指定引擎的信息，不存在时返回 null。 */
  static status(name: string): FlMultiEngineInfo | null {
    return FlMultiEngineRegistry.instance.status(name);
  }

  /** 返回指定引擎的 FlutterEngine 实例，不存在时返回 null。 */
  static engine(name: string): FlutterEngine | null {
    return FlMultiEngineRegistry.instance.engine(name);
  }

  /** 注册引擎销毁监听，供其他插件在引擎消失时释放对应的原生视图；监听器可返回 Promise。 */
  static addDestroyListener(listener: (name: string) => Promise<void> | void): void {
    FlMultiEngineRegistry.instance.addDestroyListener(listener);
  }

  /** 移除引擎销毁监听。 */
  static removeDestroyListener(listener: (name: string) => Promise<void> | void): void {
    FlMultiEngineRegistry.instance.removeDestroyListener(listener);
  }
}

/**
 * 原生侧消息桥：以某个引擎身份向其他命名引擎发送消息，并监听投递到该引擎的消息。
 *
 * Sends messages from a native engine to a named engine and listens to messages delivered to that
 * engine.
 */
export class FlMultiEngineBridge {
  private readonly engineName: string;
  private listeners: Array<FlMultiEngineNativeListener> = new Array<FlMultiEngineNativeListener>();

  constructor(engineName: string) {
    this.engineName = engineName;
  }

  /** 向 [target] 发送消息，目标存在返回 1，否则返回 0。 */
  send(target: string, method: string = 'message', value: Map<string, ESObject> = new Map<string, ESObject>()): number {
    return FlMultiEngineRegistry.instance.send(this.engineName, target, method, value);
  }

  /** 监听投递到 [engineName] 的所有消息。 */
  listen(callback: (sender: string, method: string, value: Map<string, ESObject>) => void): void {
    const listener = FlMultiEngineRegistry.instance.addListener(this.engineName, null, callback);
    this.listeners.push(listener);
  }

  /** 监听投递到 [engineName] 且 method 等于 [method] 的消息。 */
  listenMethod(method: string, callback: (value: Map<string, ESObject>) => void): void {
    const listener = FlMultiEngineRegistry.instance.addListener(
      this.engineName,
      method,
      (sender: string, receivedMethod: string, value: Map<string, ESObject>) => {
        if (receivedMethod == method) {
          callback(value);
        }
      }
    );
    this.listeners.push(listener);
  }

  /** 停止监听所有消息。 */
  dispose(): void {
    this.listeners.forEach((listener: FlMultiEngineNativeListener) => {
      FlMultiEngineRegistry.instance.removeListener(listener);
    });
    this.listeners.length = 0;
  }
}
