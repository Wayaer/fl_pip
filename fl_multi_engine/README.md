# fl_multi_engine

创建、销毁、查询和连接命名 Flutter 引擎。 / Creates, destroys, lists and connects named Flutter engines.

| 平台 Platform | 引擎创建 Engine | Entry point | 渲染 Rendering |
| ------------- | --------------- | ----------- | -------------- |
| Android       | `FlutterEngineGroup` | 支持 / supported | 由宿主 App 或 `fl_pip` 展示 |
| iOS           | `FlutterEngineGroup` | 支持 / supported | 由宿主 App 或 `fl_pip` 展示 |
| HarmonyOS     | `FlutterEngineGroup` | 支持 / supported | 由宿主 App 或 `fl_pip` 展示（系统画中画） |
| macOS         | `FlutterEngine` + `FlutterDartProject` | 支持 / supported | headless |
| Windows       | `FlutterDesktopEngineCreate` | 支持 / supported | headless |
| Linux         | `FlDartProject` + `fl_engine_new_headless` | **仅参数 / arguments only** | headless |

- 支持 Android、iOS、HarmonyOS、macOS、Windows、Linux；不支持 Web（一个浏览器页面无法承载多个引擎）。
- 插件只负责引擎的创建、销毁、查询和消息收发，不包含任何界面展示逻辑，展示形态由宿主 App 或 `fl_pip` 负责。
- Supported platforms: Android, iOS, HarmonyOS, macOS, Windows, Linux. Web is not supported.
- The plugin only manages engines; UI presentation is the responsibility of the host app or `fl_pip`.

---

## 中文文档

### 快速开始

```dart
import 'package:fl_multi_engine/fl_multi_engine.dart';

final FlMultiEngineInfo? info = await FlMultiEngine.instance.create(
  name: 'engine_a',
  entrypoint: 'engineAMain', // @pragma('vm:entry-point')
  arguments: <String>['--foo'],
);

await FlMultiEngine.instance.destroy('engine_a');
final List<FlMultiEngineInfo> engines = await FlMultiEngine.instance.list();
final FlMultiEngineInfo? status = await FlMultiEngine.instance.status('engine_a');
final String? ownName = await FlMultiEngine.instance.currentEngineName;
```

运行 `main()` 的主引擎会自动注册为 `main`，不能销毁。

`create` 的原生实现只返回创建成功的唯一 ID（即引擎名称），插件随后重新调用 `list` 并按 ID
筛选出该引擎的信息；原生未返回 ID 时 `create` 返回 `null`，原生错误会以
`FlMultiEngineException` 抛出。

原生实现创建或销毁引擎后会调用 Flutter 方法 `onEnginesChanged` 通知插件，通知不携带引擎数据，
插件重新拉取列表并通过 `FlMultiEngine.instance.engines` 推送最新列表：

```dart
FlMultiEngine.instance.engines.listen((List<FlMultiEngineInfo> engines) {});
```

`create` / `list` / `status` 返回的 `FlMultiEngineInfo` 也能直接操作该引擎：

```dart
await info.send(method: 'command', value: <String, Object?>{'text': 'hello'});
await info.destroy(); // 主引擎不可销毁
```

### 消息

```dart
// 从当前引擎发送给 main。
final int delivered = await FlMultiEngineBridge('engine_a').send(
  target: 'main',
  method: 'state/sync',
  value: <String, Object?>{'endsAt': 123456789},
);

// 监听发送给当前引擎的、指定 method 的消息。
final StreamSubscription<FlMultiEngineMessage> subscription = FlMultiEngineBridge('engine_a').listen(
  'command',
  (Map<String, Object?> value) {},
);
```

- 消息值必须能被 `StandardMessageCodec` 序列化：`null`、`bool`、`num`、`String`、`Uint8List`、`List`、`Map`。
- `send` 返回接收消息的引擎数量：目标存在且运行中返回 1，否则返回 0。
- 消息不做缓存，只投递给已经注册插件的引擎。
- 不是由 `fl_multi_engine` 创建的引擎（例如 `fl_pip` 的 `pipMain` 专用引擎）不会登记为命名引擎，
  也不会覆盖 `main` 的通道；这类引擎的 `currentEngineName` 返回 `null`。

### 错误码

原生错误通过 [FlMultiEngineException.code] 返回，所有平台使用同一套稳定错误码：Dart 侧为
`FlMultiEngineErrorCode` 常量，Android 为 `FlMultiEngineErrorCode` 对象，iOS / macOS / HarmonyOS 为
`FlMultiEngineErrorCode`，Windows / Linux 为 `fl_multi_engine_error_codes.h`。

| code                          | 含义                   | 触发场景                                 |
| ----------------------------- | ---------------------- | ---------------------------------------- |
| `not_supported`               | 当前平台不支持该插件   | `create`（例如 Fuchsia / Web）           |
| `invalid_name`                | 引擎名或入口函数为空   | `create`                                 |
| `engine_exists`               | 同名引擎已存在         | `create`（`main` 也不能重复创建）        |
| `create_failed`               | 引擎创建或启动失败     | `create`                                 |
| `main_engine_not_destroyable` | 主引擎不允许销毁       | `destroy('main')`                        |
| `not_initialized`             | 原生实现尚未绑定主引擎 | 原生直接调用时插件还未 attach            |
| `unknown`                     | 未识别的原生异常       | 原生实现异常兜底                         |

```dart
try {
  await FlMultiEngine.instance.create(name: 'engine_a', entrypoint: 'engineAMain');
} on FlMultiEngineException catch (error) {
  if (error.code == FlMultiEngineErrorCode.engineExists) {
    // 同名引擎已存在，直接复用即可。
  }
}
```

### 平台注意事项

- Android：新引擎的插件注册与引擎命名由注册表统一处理，`GeneratedPluginRegister` 由引擎组自动执行。
- iOS / macOS：需要宿主 App 提供插件注册回调（见下节）。
- Windows / Linux：引擎为 headless，渲染到窗口是另一个独立能力。
- HarmonyOS：引擎通过 `FlutterEngineGroup` 创建，插件本身不创建视图；宿主 App 需要为引擎创建 `FlutterView` 并渲染到 `XComponent`，`fl_pip` 已提供 `FlPiPSurface`（系统画中画）。宿主 App 需要在 `EntryAbility` 中提供插件注册回调（见下节）。
- Linux 嵌入层不暴露自定义 entrypoint，插件会把 `--fl-multi-engine-entrypoint=<entrypoint>` 和
  `--fl-multi-engine-name=<name>` 作为 Dart 参数传入，App 的 `main(List<String> args)` 需要自行分发。
- 引擎创建时会立即执行入口函数，插件注册发生在入口启动之后。入口函数不要在 `main()` 里同步调用
  插件通道，应在 `runApp` 之后或首帧回调中调用，否则可能抛出 `MissingPluginException`。
- HarmonyOS 的销毁监听器可以返回 `Promise`，注册表会等所有监听器完成后再销毁引擎；`fl_pip` 依赖
  这一点完成视图解绑。

### 插件注册

```swift
// iOS
FlMultiEnginePlugin.pluginRegistrant = { engine in
    GeneratedPluginRegistrant.register(with: engine)
}

// macOS
FlMultiEnginePlugin.pluginRegistrant = { engine in
    RegisterGeneratedPlugins(registry: engine)
}
```

```ts
// HarmonyOS / OpenHarmony：EntryAbility.ets
import { FlutterAbility, FlutterEngine } from '@ohos/flutter_ohos';
import FlMultiEnginePlugin from 'fl_multi_engine';
import { GeneratedPluginRegistrant } from '../plugins/GeneratedPluginRegistrant';

export default class EntryAbility extends FlutterAbility {
  configureFlutterEngine(flutterEngine: FlutterEngine) {
    super.configureFlutterEngine(flutterEngine)
    GeneratedPluginRegistrant.registerWith(flutterEngine)
    FlMultiEnginePlugin.pluginRegistrant = (engine: FlutterEngine) => {
      GeneratedPluginRegistrant.registerWith(engine)
    }
  }
}
```

Android 通过 `GeneratedPluginRegister` 自动完成注册；Windows / Linux 只自动安装
`fl_multi_engine` 自身的通道，其他插件需要宿主 App 自行注册。HarmonyOS 未设置
`pluginRegistrant` 时，新引擎仍会自动注册 `fl_multi_engine` 自身，其他插件不可用。

### 原生 API

Android（`fl.multi.engine`）：

```kotlin
FlMultiEngine.create(name = "engine_a", entrypoint = "engineAMain")
FlMultiEngine.create(name = "engine_b", entrypoint = "engineBMain")
FlMultiEngine.destroy("engine_a")
FlMultiEngine.engines()
FlMultiEngine.engine("engine_a") // FlutterEngine?
FlMultiEngine.addEngineDestroyListener { name -> } // 引擎销毁回调
FlMultiEngineBridge("engine_a").send(target = "main", method = "state/sync", value = mapOf(...))
```

iOS / macOS（`fl_multi_engine`）：

```swift
FlMultiEngine.shared.create(name: "engine_a", entrypoint: "engineAMain")
FlMultiEngine.shared.create(name: "engine_b", entrypoint: "engineBMain")
FlMultiEngine.shared.destroy(name: "engine_a")
FlMultiEngine.shared.engines()
FlMultiEngine.shared.engine(named: "engine_a") // FlutterEngine?
FlMultiEngine.shared.addDestroyObserver(FlMultiEngineDestroyObserver { name in }) // 引擎销毁回调
FlMultiEngineBridge(engineName: "engine_a").send(target: "main", method: "state/sync", value: [...])
```

HarmonyOS / OpenHarmony（ArkTS）：

```ts
import { FlMultiEngine, FlMultiEngineBridge } from 'fl_multi_engine';

const info = FlMultiEngine.create('engine_a', 'engineAMain');
FlMultiEngine.destroy('engine_a');
const engines = FlMultiEngine.engines();
const engine = FlMultiEngine.engine('engine_a'); // FlutterEngine | null
FlMultiEngine.addDestroyListener(async (name: string) => {}); // 引擎销毁回调，可返回 Promise

const bridge = new FlMultiEngineBridge('engine_a');
bridge.send('main', 'state/sync', new Map<string, ESObject>());
bridge.listen((sender: string, method: string, value: Map<string, ESObject>) => {});
bridge.dispose();
```

> `FlMultiEngine` 与 `FlMultiEngineBridge` 不是 `index.ets` 的默认导出，需要按名称导入。

Windows / Linux：

```c
FlutterDesktopEngineRef fl_multi_engine_get_engine(const char* name);
FlValue* fl_multi_engine_create_engine(name, entrypoint, arguments, &error);
bool fl_multi_engine_destroy_engine(name);
FlValue* fl_multi_engine_list_engines();
FlValue* fl_multi_engine_get_engine_status(const char* name);
```

Windows 还提供 C++ 原生入口：

```cpp
fl_multi_engine::EngineInfo info = fl_multi_engine::CreateEngine(name, entrypoint, arguments);
fl_multi_engine::StatusEngine(name, &info);
fl_multi_engine::ListEngines();
fl_multi_engine::GetEngine(name);
fl_multi_engine::DestroyEngine(name);
```

`CreateEngine` 失败时抛出 `fl_multi_engine::FlMultiEngineException`，其 `code` 与错误码表一致。

### 示例

`example` 覆盖了全部参数与状态：

- `create` / `destroy` / `status` / `list`；
- entrypoint 参数与 `currentEngineName`；
- `send` 消息与 `messages` 实时列表；
- `engines` 实时列表：原生创建或销毁引擎后自动刷新；
- 新引擎上也可以给 `main` 发消息并监听消息。

---

## English

### Quick start

```dart
final FlMultiEngineInfo? info = await FlMultiEngine.instance.create(
  name: 'engine_a',
  entrypoint: 'engineAMain', // @pragma('vm:entry-point')
  arguments: <String>['--foo'],
);

await FlMultiEngine.instance.destroy('engine_a');
final List<FlMultiEngineInfo> engines = await FlMultiEngine.instance.list();
final String? ownName = await FlMultiEngine.instance.currentEngineName;
```

The engine that runs `main()` is registered automatically as `main` and cannot be destroyed.

The native implementation only returns the unique ID (the engine name) of the created engine. The
plugin then re-fetches `list` and returns the matching info; `create` returns `null` when no ID is
reported, and native errors are thrown as `FlMultiEngineException`.

After an engine is created or destroyed natively, the implementation calls the Flutter method
`onEnginesChanged`. The notification carries no engine data: the plugin re-fetches the list and
emits it on `FlMultiEngine.instance.engines`:

```dart
FlMultiEngine.instance.engines.listen((List<FlMultiEngineInfo> engines) {});
```

The `FlMultiEngineInfo` returned by `create`, `list` and `status` can also operate on its engine
directly:

```dart
await info.send(method: 'command', value: <String, Object?>{'text': 'hello'});
await info.destroy(); // The main engine cannot be destroyed
```

### Messages

```dart
final int delivered = await FlMultiEngineBridge('engine_a').send(
  target: 'main',
  method: 'state/sync',
  value: <String, Object?>{'endsAt': 123456789},
);

FlMultiEngineBridge('engine_a').listen('command', (Map<String, Object?> value) {});
```

Only values supported by `StandardMessageCodec` are allowed. `send` returns `1` when the target
exists and is running, `0` otherwise. Messages are not stored.

Engines that were not created by `fl_multi_engine` (for example the `fl_pip` `pipMain` engine) are
never registered as named engines and never take over `main`; `currentEngineName` returns `null`
inside them.

### Error codes

Native errors are reported through `FlMultiEngineException.code`. Every platform uses the same
stable codes (`FlMultiEngineErrorCode` on Dart, Android, iOS / macOS and HarmonyOS, and
`fl_multi_engine_error_codes.h` on Windows / Linux):

| code                          | Meaning                             | Raised by                                |
| ----------------------------- | ----------------------------------- | ---------------------------------------- |
| `not_supported`               | The plugin is not supported here    | `create` (for example Fuchsia / Web)     |
| `invalid_name`                | The name or entry point is empty    | `create`                                 |
| `engine_exists`               | An engine with the name already exists | `create` (`main` cannot be recreated) |
| `create_failed`               | The engine could not be started     | `create`                                 |
| `main_engine_not_destroyable` | The main engine cannot be destroyed | `destroy('main')`                        |
| `not_initialized`             | The plugin is not attached yet      | Native calls before attach               |
| `unknown`                     | Unrecognized native exception       | Native fallback                          |

```dart
try {
  await FlMultiEngine.instance.create(name: 'engine_a', entrypoint: 'engineAMain');
} on FlMultiEngineException catch (error) {
  if (error.code == FlMultiEngineErrorCode.engineExists) {
    // The engine already exists and can be reused.
  }
}
```

### Plugin registration

```swift
// iOS
FlMultiEnginePlugin.pluginRegistrant = { engine in
    GeneratedPluginRegistrant.register(with: engine)
}

// macOS
FlMultiEnginePlugin.pluginRegistrant = { engine in
    RegisterGeneratedPlugins(registry: engine)
}
```

```ts
// HarmonyOS / OpenHarmony: EntryAbility.ets
import { FlutterAbility, FlutterEngine } from '@ohos/flutter_ohos';
import FlMultiEnginePlugin from 'fl_multi_engine';
import { GeneratedPluginRegistrant } from '../plugins/GeneratedPluginRegistrant';

export default class EntryAbility extends FlutterAbility {
  configureFlutterEngine(flutterEngine: FlutterEngine) {
    super.configureFlutterEngine(flutterEngine)
    GeneratedPluginRegistrant.registerWith(flutterEngine)
    FlMultiEnginePlugin.pluginRegistrant = (engine: FlutterEngine) => {
      GeneratedPluginRegistrant.registerWith(engine)
    }
  }
}
```

Android registers plugins automatically through `GeneratedPluginRegister`. Windows and Linux only
install the `fl_multi_engine` channel; other plugins must be registered by the host app. On
HarmonyOS an engine created without `pluginRegistrant` still gets the `fl_multi_engine` channel,
but no other plugins.

The engine runs its entry point immediately on creation, while plugins are registered right after.
Entry points must not call plugin channels synchronously from `main()`; call them after `runApp` or
from a post-frame callback, otherwise an early call can throw `MissingPluginException`.

On HarmonyOS a destroy listener may return a `Promise`. The registry waits for every listener to
settle before destroying the engine, so hosts can tear down views mounted on the engine safely.

### Native API

Android (`fl.multi.engine`):

```kotlin
FlMultiEngine.create(name = "engine_a", entrypoint = "engineAMain")
FlMultiEngine.create(name = "engine_b", entrypoint = "engineBMain")
FlMultiEngine.destroy("engine_a")
FlMultiEngine.engines()
FlMultiEngine.engine("engine_a")
FlMultiEngineBridge("engine_a").send(target = "main", method = "state/sync", value = mapOf(...))
```

iOS / macOS (`fl_multi_engine`):

```swift
FlMultiEngine.shared.create(name: "engine_a", entrypoint: "engineAMain")
FlMultiEngine.shared.create(name: "engine_b", entrypoint: "engineBMain")
FlMultiEngine.shared.destroy(name: "engine_a")
FlMultiEngine.shared.engines()
FlMultiEngine.shared.engine(named: "engine_a")
FlMultiEngineBridge(engineName: "engine_a").send(target: "main", method: "state/sync", value: [...])
```

HarmonyOS / OpenHarmony (ArkTS):

```ts
import { FlMultiEngine, FlMultiEngineBridge } from 'fl_multi_engine';

const info = FlMultiEngine.create('engine_a', 'engineAMain');
FlMultiEngine.destroy('engine_a');
const engines = FlMultiEngine.engines();
const engine = FlMultiEngine.engine('engine_a'); // FlutterEngine | null
FlMultiEngine.addDestroyListener((name: string) => {});

const bridge = new FlMultiEngineBridge('engine_a');
bridge.send('main', 'state/sync', new Map<string, ESObject>());
bridge.listen((sender: string, method: string, value: Map<string, ESObject>) => {});
bridge.dispose();
```

`FlMultiEngine` and `FlMultiEngineBridge` are named exports; the package default export is the plugin
class used by the generated registrant.

Windows and Linux expose the C API listed above. Windows also provides a C++ native entry point:

```cpp
fl_multi_engine::EngineInfo info = fl_multi_engine::CreateEngine(name, entrypoint, arguments);
fl_multi_engine::StatusEngine(name, &info);
fl_multi_engine::ListEngines();
fl_multi_engine::GetEngine(name);
fl_multi_engine::DestroyEngine(name);
```

`CreateEngine` throws `fl_multi_engine::FlMultiEngineException` on failure; its `code` matches the
error code table.

### Example

The example app demonstrates every parameter and state: create, destroy, status, list, entrypoint
arguments, sending messages, live message and engine lists (automatically refreshed after native
changes), and engines that talk back to `main`.

## License

MIT
