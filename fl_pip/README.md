# fl_pip

A Flutter plugin that presents Flutter pages and videos in a native picture-in-picture or overlay
window on Android, iOS and HarmonyOS.

| 平台 Platform | 最低版本 Minimum |
| ------------- | ---------------- |
| Android       | 7.0 (API 24)     |
| iOS           | 15.0             |
| HarmonyOS     | 6.0 (API 20)     |

- Flutter `>= 3.41.0`
- Dart `>= 3.11.0`
- Android: AGP 9.x / Kotlin 2.4 built-in Kotlin, `compileSdk 36`
- iOS: CocoaPods and Swift Package Manager (SPM) are both supported

---

## 中文文档

### 功能

- 在 Android / iOS / HarmonyOS 原生画中画、悬浮窗中展示 Flutter 页面与视频
- 引擎由 `fl_multi_engine` 统一管理；`present(name: ...)` 按名称读取或补建引擎，并返回该引擎的
  `FlMultiEngineInfo`
- 三端参数完全独立，互不继承，`present()` / `play()` 一次性传入三端参数，原生只使用当前平台的一份
- 主引擎与画中画引擎通过同一个 `fl_pip` 通道收发消息：`send()` 投递给 `present(name:)` 指定的画中画引擎
  （例如 `pipMain`，也可以是自定义名称）
- 通过 `FlPiPBuilder` 实时响应画中画状态

| 能力 | Android | iOS | HarmonyOS |
| ---- | ------- | --- | --------- |
| 系统画中画 | `FlPiPAndroidOptions.systemPip()`（整个 Activity 缩窗，只用 `FlPiPAspectRatio`） | 系统画中画（引擎画面实时渲染进窗口；主引擎用纯黑占位媒体兜底） | `FlPiPHarmonyOSOptions.systemPip()`（只用 `FlPiPAspectRatio`，窗口大小与位置由系统管理） |
| 悬浮窗 / 应用内弹窗 | `FlPiPAndroidOptions.overlay()`（`WindowManager`） | — | `FlPiPHarmonyOSOptions.overlay()` |
| 画中画引擎 | `overlay` 模式渲染引擎；`systemPip` 创建引擎但不渲染 | 非主引擎渲染进画中画；主引擎不渲染（占位媒体兜底） | 两种模式都渲染 |
| 引擎消息互通 | 支持 | 支持 | 支持 |
| 视频控制面板 | 完整自定义面板 | 系统面板（由系统绘制、自动隐藏，不可关闭） | 系统画中画用系统面板，应用内弹窗用自定义面板 |

> iOS 视频说明：App 内不展示画中画弹出前的内联视频框（原生固定为 0.01pt 并放在左上角）；
> 网络视频会先用本地占位媒体启动画中画，首帧到达后在画中画窗口内完成加载。

### 安装

```yaml
dependencies:
  fl_pip: ^4.0.0
```

### Android 配置

1. `MainActivity` 继承 `FlPiPActivity`：

```kotlin
package your.package.name

import fl.pip.FlPiPActivity

class MainActivity : FlPiPActivity()
```

2. 在 `android/app/src/main/AndroidManifest.xml` 的启动 Activity 中开启画中画：

```xml
<activity
    android:name=".MainActivity"
    android:launchMode="singleTop"
    android:supportsPictureInPicture="true"
    ... />
```

3. 悬浮窗模式（`FlPiPAndroidOptions.overlay()`）使用 `WindowManager`，需要 `SYSTEM_ALERT_WINDOW`
   权限。插件已声明该权限，`present()` 会自动跳转系统授权页并等待用户操作：授权后继续创建悬浮窗，
   拒绝时抛出 `FlPiPException`（`FlPiPErrorCode.permissionDenied`）。
   系统画中画（`FlPiPAndroidOptions.systemPip()`）不需要悬浮窗权限。

### iOS 配置

1. `Signing & Capabilities` → `Capability` 添加 `Background Modes`，勾选
   `Audio, AirPlay, And Picture in Picture`。
2. 把 App 生成插件注册到画中画引擎：

```swift
// Flutter 3.47 隐式 engine 模板（SceneDelegate 生命周期）
func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    FlPiPPlugin.pluginRegistrant = { registry in
        GeneratedPluginRegistrant.register(with: registry)
    }
}
```

### HarmonyOS 配置

1. 主页面用 `FlPiPSurface` 代替 `FlutterPage`，并把 `FlutterAbility` 写入的 `viewId` 传进去：

```ts
// entry/src/main/ets/pages/Index.ets
import { FlPiPSurface } from 'fl_pip';

@Entry(storage)
@Component
struct Index {
  @LocalStorageLink('viewId') viewId: string = '';

  build() {
    Column() {
      FlPiPSurface({ viewId: this.viewId })
    }
    .width('100%')
    .height('100%')
  }
}
```

2. 在 `EntryAbility` 里把 App 生成插件注册到画中画引擎：

```ts
import FlPiPPlugin from 'fl_pip';
import { GeneratedPluginRegistrant } from '../plugins/GeneratedPluginRegistrant';

configureFlutterEngine(flutterEngine: FlutterEngine) {
  super.configureFlutterEngine(flutterEngine)
  GeneratedPluginRegistrant.registerWith(flutterEngine)
  FlPiPPlugin.pluginRegistrant = (engine: FlutterEngine) => {
    GeneratedPluginRegistrant.registerWith(engine)
  }
}
```

`systemPip` 通过 `FlPiPSurface` 为 `present(name:)` 指定的引擎在系统画中画中挂载独立的 surface，
主页面与主引擎保持不变；`overlay` 则在 `FlPiPSurface` 之上叠加一层可拖拽、可交互的浮层，仅在
App 前台可见。

### 画中画

```dart
import 'package:fl_pip/fl_pip.dart';

// name 是 fl_multi_engine 中的引擎名称；不存在时原生会用 pipMain 入口补建。
// Android 默认悬浮窗；iOS 把引擎渲染进系统画中画（主引擎用占位媒体）；HarmonyOS 默认系统画中画。
final FlMultiEngineInfo engine = await FlPiP.instance.present(
  name: 'pipMain',
  android: const FlPiPAndroidOptions.overlay(),
  ios: const FlPiPIOSOptions(),
  harmonyOS: const FlPiPHarmonyOSOptions.systemPip(),
);

// Android：系统画中画，只用宽高比；引擎会创建但不渲染
await FlPiP.instance.present(
  name: 'pipMain',
  android: const FlPiPAndroidOptions.systemPip(aspectRatio: FlPiPAspectRatio.landscape()),
);

// HarmonyOS：系统画中画，与 Android 一样只用宽高比；不传时默认 16:9
await FlPiP.instance.present(
  name: 'pipMain',
  harmonyOS: const FlPiPHarmonyOSOptions.systemPip(aspectRatio: FlPiPAspectRatio.vertical()),
);

// HarmonyOS：应用内浮窗，支持自定义宽高、位置与圆角
await FlPiP.instance.present(
  name: 'pipMain',
  harmonyOS: const FlPiPHarmonyOSOptions.overlay(
    window: FlPiPWindow(width: 720, height: 405, top: 300, left: 60),
    cornerRadius: 16,
  ),
);

// 关闭画中画；destroyEngineOnDismiss 决定是否销毁该引擎
await FlPiP.instance.dismiss();

// isAvailable 只表示系统画中画能力；悬浮窗 / 应用内弹窗不依赖该值
final bool available = await FlPiP.instance.isAvailable;
final FlPiPStatusInfo? info = await FlPiP.instance.isActive;
// info.status / info.mode(FlPiPPresentationMode) / info.hasEngine

// 仅 Android 支持切前后台；HarmonyOS 只能切到后台，iOS 忽略
await FlPiP.instance.toggle(FlPiPAppState.background);

// 向画中画引擎发送消息，返回送达数量
final int delivered = await FlPiP.instance.send('main/message', arguments: <String, Object?>{'from': 'main'});
```

`FlPiPBuilder` 根据状态自动刷新：

```dart
FlPiPBuilder(
  builder: (FlPiPStatusInfo? info) {
    switch (info?.status) {
      case FlPiPStatus.enabled:
        return FilledButton(onPressed: FlPiP.instance.dismiss, child: const Text('dismiss'));
      case FlPiPStatus.unavailable:
        return const Text('Picture-in-picture is not supported');
      case FlPiPStatus.disabled:
      case null:
        return FilledButton(onPressed: () => FlPiP.instance.present(name: 'pipMain'), child: const Text('present'));
    }
  },
)
```

### 引擎管理与引擎消息

- 引擎由 `fl_multi_engine` 创建和销毁；`present(name:)` 按名称读取引擎注册表，不存在时用
  `pipMain` 入口补建，成功返回 `FlMultiEngineInfo`，失败抛 `FlPiPException`
  （`FlPiPErrorCode.engineCreationFailed` / `engineNotFound`）。
- `destroyEngineOnDismiss`（默认 `true`）决定关闭窗口时销毁引擎还是保留引擎；主引擎只能在
  `destroyEngineOnDismiss = false` 时展示，为 `true` 时传入会返回 `invalid_configuration`。
- 引擎入口函数仍需用 `@pragma('vm:entry-point')` 标记：

```dart
@pragma('vm:entry-point')
void pipMain() {
  runApp(const PiPApp());
}
```

- `FlPiPStatusInfo.hasEngine` 表示 `present(name:)` 指定的引擎是否仍然存在，与窗口是否展示无关；
  窗口关闭时 `destroyEngineOnDismiss = false` 会保留引擎，此时仍为 `true`，引擎被销毁后才变为 `false`。
- 主引擎与画中画引擎都注册同一个 `fl_pip` 通道，`send()` 只会投递给 `present(name:)` 指定的画中画引擎
  （例如 `pipMain`，也可以是自定义名称）；该引擎调用 `send()` 时投递回主引擎，双方通过
  `FlPiP.instance.messages` 监听，其他引擎不会收到消息。
- HarmonyOS 系统画中画面板的操作会转成 `method: 'control'` 的消息，通过
  `FlPiP.instance.messages` 送达；`arguments.action` 为 `playPause`（带 `playing`）或
  `skip`（带 `seconds`）。
- 三端原生实现统一分层，便于对照维护：

| 层 | Android | iOS | HarmonyOS |
| -- | ------- | --- | --------- |
| 通道分派 | `FlPiPPlugin` | `FlPiPPlugin` | `FlPiPPlugin` |
| 错误定义 | `FlPiPError.kt` | `FlPiPError.swift` | `FlPiPError.ets` |
| 引擎管理 | `FlPiPEngineManager` | `FlPiPEngineManager` | `FlPiPEngineManager` |
| 视频管理 | `FlPiPVideoManager` | `FlPiPVideoManager` | `FlPiPVideoManager` |
| 窗口 / 画中画状态 | `FlPiPWindowManager` | `FlPiPWindowManager` | `FlPiPWindowManager` |
| 渲染宿主 | — | `FlPiPVideoCallViewController`（引擎）/ `FlPiPPlaceholderMedia`（主引擎兜底） | `FlPiPSurface` |

- 引擎与视频都向同一个窗口层申请展示，`owner`（engine / video）与 `mode`（systemPip / overlay）
  由窗口层统一管理；三端的通道名统一为 `FlPiPChannel.name`（`'fl_pip'`），错误码统一为
  `FlPiPErrorCode`，原生错误统一用 `FlPiPException` 抛出。

### 视频播放

```dart
await FlPiPVideo.instance.play(
  android: FlPiPVideoAndroidOptions(
    source: const FlPiPVideoSource.asset('assets/h.mp4'),
    loop: true,
    window: const FlPiPWindow(width: 720, height: 405, top: 200, left: 40),
    cornerRadius: 12,
  ),
  ios: FlPiPVideoIOSOptions(
    source: const FlPiPVideoSource.asset('assets/h.mp4'),
    window: const FlPiPWindow(width: 720, height: 405, top: 200, left: 40),
  ),
  harmonyOS: FlPiPVideoHarmonyOSOptions.overlay(
    source: const FlPiPVideoSource.asset('assets/h.mp4'),
    window: const FlPiPWindow(width: 720, height: 405, top: 200, left: 40),
  ),
);

await FlPiPVideo.instance.stop();
final bool active = await FlPiPVideo.instance.isActive;
```

播放控制：

```dart
await FlPiPVideo.instance.pause();
await FlPiPVideo.instance.resume();
await FlPiPVideo.instance.setPlaying(false);
await FlPiPVideo.instance.seek(const Duration(seconds: 30));
await FlPiPVideo.instance.seekBy(const Duration(seconds: -15));
await FlPiPVideo.instance.stopPlayback(); // 暂停并回到开头，保持窗口
await FlPiPVideo.instance.setSpeed(1.5);
await FlPiPVideo.instance.setVolume(0.4);
await FlPiPVideo.instance.setLooping(true);
final FlPiPVideoStatus? status = await FlPiPVideo.instance.status;
FlPiPVideo.instance.events.listen((FlPiPVideoEvent event) {});
```

视频来源：`FlPiPVideoSource.asset(uri, {packageName})`、`FlPiPVideoSource.file(path)`、
`FlPiPVideoSource.network(url)`。

视频事件（`FlPiPVideoEvent.event`）：`play`、`playPause`、`skip`、`close`、`ended`、`position`、
`stop`、`speed`、`volume`、`error`。`skip` 只由 HarmonyOS 系统画中画面板的快退 / 快进触发，
action 为 `rewind` / `forward`；`controls`
（控制面板显示 / 隐藏）只在 Android 悬浮窗与 HarmonyOS 应用内浮窗上报，iOS 的系统面板由系统
绘制，不上报 `controls`。

应用内弹窗与 Android 悬浮窗行为一致：拖动时与屏幕边缘保留 8 vp / 8 dp 间距，不会贴边；
控制面板自动隐藏后，点击视频任意位置可重新显示；播放 / 暂停与关闭按钮均使用系统图标。

### 像素单位

`FlPiPWindow` 的 `width`、`height`、`top`、`left` 全部是**手机物理像素（px，像素密度）**，
不是 dp / vp / 逻辑像素。传了宽高后，原生把视频控件设置为该宽高，视频画面按比例自适应，
宽或高撑满控件；`top` / `left` 用于定义视频弹窗在屏幕上的位置。

```dart
// Flutter 页面通常拿到的是逻辑像素，需要乘以 devicePixelRatio 才能传给原生
final double pixelRatio = MediaQuery.devicePixelRatioOf(context);
final window = FlPiPWindow(
  width: 240 * pixelRatio,
  height: 135 * pixelRatio,
  top: 120 * pixelRatio,
  left: 24 * pixelRatio,
);
```

- Android：`WindowManager` 直接使用 px。
- iOS：原生除以 `UIScreen.main.scale` 得到 point。
- HarmonyOS：原生用 `px2vp` 换算成 vp。

Android 与 HarmonyOS 的悬浮窗会保证整个窗口留在屏幕内：`width` / `height` 超过屏幕时按屏幕
尺寸截断，`left` / `top` 超过 `屏幕尺寸 - 窗口尺寸` 时按上限截断，窗口不会超出屏幕。

Android 与 HarmonyOS 的悬浮窗关闭按钮统一使用系统图标（Android `ic_menu_close_clear_cancel`，
HarmonyOS `sys.symbol.xmark`）。

### 参数表

`FlPiPAndroidOptions` 提供两个构造函数：

| 构造函数 | 参数 | 说明 |
| -------- | ---- | ---- |
| `FlPiPAndroidOptions.overlay()` | `window`（px）、`cornerRadius`（dp） | `WindowManager` 悬浮窗，由 `present(name:)` 指定的引擎渲染；`window` 为 `null` 时使用原生默认尺寸 |
| `FlPiPAndroidOptions.systemPip()` | `aspectRatio` | 整个 Activity 进入系统画中画，只用宽高比（`1/2.39 ~ 2.39`）；引擎会创建但不渲染 |

`FlPiPIOSOptions`：

| 参数 | 说明 |
| ---- | ---- |
| `window` | 窗口宽高与位置，单位**物理像素（px）**；只决定画中画窗口的比例，实际大小与位置由系统管理，`null` 时使用 16:9 |

iOS 会把 `present(name:)` 指定的引擎渲染进系统画中画窗口（通过
`AVPictureInPictureVideoCallViewController` 内容源承载该引擎的 `FlutterViewController`），
因此不需要再传视频、音频资源与 `packageName`。主引擎没有独立的 `FlutterEngine` 实例，无法作为
内容源，此时原生会按 `window` 的宽高运行时生成 1 秒纯黑视频与 1 秒静音音轨（按尺寸缓存）循环播放。

`FlPiPHarmonyOSOptions` 与 Android 一样按承载方式提供两个构造函数：

| 构造函数 | 参数 |
| ---- | ---- |
| `FlPiPHarmonyOSOptions.systemPip()`（默认） | `aspectRatio`（`FlPiPAspectRatio`，`1/2.39 ~ 2.39`），`null` 时使用 16:9；窗口大小与位置由系统管理 |
| `FlPiPHarmonyOSOptions.overlay()` | `window`（**物理像素 px**）、`cornerRadius`（vp） |

视频参数 `FlPiPVideoAndroidOptions` / `FlPiPVideoIOSOptions` / `FlPiPVideoHarmonyOSOptions`
同样相互独立，公共字段为 `source`、`loop`、`muted`、`window`；HarmonyOS 的 `systemPip()`
另提供 `aspectRatio`，`null` 时跟随视频原始宽高比：

| 参数类 | 额外字段 |
| ------ | -------- |
| `FlPiPVideoAndroidOptions` | `cornerRadius`（dp）、`showControls`、`showPlayPause`、`showProgress`、`showClose`、`allowDrag`、`autoHide` |
| `FlPiPVideoIOSOptions` | `showControls`（iOS 由系统管理面板，该参数不生效） |
| `FlPiPVideoHarmonyOSOptions` | `systemPip()`（默认，只用 `aspectRatio`，无自定义面板）与 `overlay()`（`window`（px）+ `cornerRadius`（vp）+ 全套控制面板开关） |

### 错误处理

失败时抛出 `FlPiPException`，通过 `code`（`FlPiPErrorCode`）判断原因：

| 错误码 | 说明 |
| ------ | ---- |
| `permissionDenied` | 用户拒绝了 Android 悬浮窗权限 |
| `permissionRequestInProgress` | 上一次权限申请尚未结束 |
| `notSupported` | 当前设备或平台不支持画中画 |
| `alreadyEnabled` | 画中画（或视频窗口）已经开启 |
| `activityNotInitialized` | `MainActivity` 未继承 `FlPiPActivity` |
| `invalidConfiguration` | 参数不合法 |
| `startFailed` | 原生启动失败 |
| `overlayCreationFailed` | Android 悬浮窗创建失败 |
| `audioSessionFailed` | iOS 音频会话配置失败 |
| `videoAssetNotFound` | 视频资源不存在 |
| `windowUnavailable` | 宿主窗口或 `FlPiPSurface` 不可用 |
| `controllerUnavailable` | 画中画控制器创建失败 |
| `engineCreationFailed` | 画中画引擎创建失败 |
| `engineNotFound` | `fl_multi_engine` 中不存在该名称的引擎 |
| `unknown` | 未识别的原生错误 |

`FlPiPAspectRatio` 超出 `1/2.39 ~ 2.39` 时，Android 与 HarmonyOS 的 `systemPip` 会在调用前抛出
`FlPiPAspectRatioNotSupportedException`；原生侧同样返回 `invalidConfiguration`。HarmonyOS 视频的
`systemPip()` 只在显式传入 `aspectRatio` 时校验，未传时跟随视频原始宽高比。

### 注意事项

- iOS 的非主引擎会把 `FlutterViewController` 渲染进系统画中画窗口；主引擎没有独立的
  `FlutterEngine` 实例，窗口循环播放原生按 `FlPiPIOSOptions.window` 生成的纯黑占位媒体。
  `AVPictureInPictureVideoCallViewController` 按 Apple 文档仅用于视频通话场景，非通话场景上架前
  请自行确认审核要求。视频的内联预览固定为 0.01pt 放在左上角，App 内不会出现视频框；网络视频会用
  本地占位媒体先启动画中画，首帧到达后在画中画窗口内完成加载。
- Android 的 `systemPip` 是真正的系统画中画，`overlay` 是 `WindowManager` 悬浮窗；两者互斥。
- HarmonyOS 的系统画中画只接受 `XComponentType.SURFACE`，`FlPiPSurface` 会在主页面里为
  `present(name:)` 指定的引擎与视频挂载对应的 surface；系统画中画只用 `aspectRatio` 决定窗口比例，
  大小与位置由系统管理，`window` / `top` / `left` 不生效；应用内浮窗与系统画中画互斥，但不影响视频
  继续使用系统画中画。
- 远程 URL 视频需要 `INTERNET` 权限（插件已声明），`http://` 明文地址还需要宿主 App 配置
  `networkSecurityConfig`。
- 不支持平台（Web、桌面）调用时安全返回 `false` / `null`。

### 示例

`example` 覆盖了全部能力：

- 画中画与引擎消息同页展示，只要 `hasEngine == true`（`pipMain` 引擎未被销毁）就启用消息交互，与窗口是否打开无关；
- Android `overlay()` / `systemPip()` 两个构造函数与全部宽高比；
- iOS 引擎渲染进画中画、`window` 宽高与 `top` / `left` 物理像素（主引擎用占位媒体兜底）；
- HarmonyOS `systemPip` 的宽高比选择与 `overlay` 的宽高、位置、圆角；
- 视频三种来源、HarmonyOS 系统画中画宽高比与视频原始比例跟随、应用内弹窗自定义宽高与位置、
  控制面板开关、播放控制与事件列表。

---

## English

### Features

- Present Flutter pages and videos in native picture-in-picture / overlay windows on Android, iOS
  and HarmonyOS
- Engines are created and destroyed by `fl_multi_engine`; `present(name: ...)` reads or creates the
  named engine and returns its `FlMultiEngineInfo`
- Per-platform options are independent classes, not a shared base class
- The main engine and the PiP engine exchange messages through the single `fl_pip` channel;
  `send()` targets only the engine passed to `present(name:)` (for example `pipMain`, or a custom name)
- Rebuild UI reactively with `FlPiPBuilder`

| Capability | Android | iOS | HarmonyOS |
| ---------- | ------- | --- | --------- |
| System PiP | `FlPiPAndroidOptions.systemPip()` (whole Activity, `FlPiPAspectRatio` only) | System PiP rendering the engine; the main engine falls back to black placeholder media | `FlPiPHarmonyOSOptions.systemPip()` (`FlPiPAspectRatio` only, size and position managed by the system) |
| Overlay | `FlPiPAndroidOptions.overlay()` (`WindowManager`) | — | `FlPiPHarmonyOSOptions.overlay()` |
| PiP engine | Rendered by `overlay`; created but not rendered by `systemPip` | Engines other than the main engine are rendered; the main engine is not (placeholder fallback) | Rendered by both modes |
| Engine messaging | Yes | Yes | Yes |
| Video controls | Full custom panel | System panel, drawn and auto-hidden by the system and not dismissible | System panel for PiP, custom panel for the overlay |

> iOS videos: the inline preview is never shown in the app (it is fixed at 0.01pt in the
> top-left corner). Network videos start PiP with local placeholder media, so the first frame
> loads inside the PiP window.

### Installation

```yaml
dependencies:
  fl_pip: ^4.0.0
```

### Android setup

1. Make `MainActivity` extend `FlPiPActivity`:

```kotlin
package your.package.name

import fl.pip.FlPiPActivity

class MainActivity : FlPiPActivity()
```

2. Enable picture-in-picture on the launch activity in `android/app/src/main/AndroidManifest.xml`:

```xml
<activity
    android:name=".MainActivity"
    android:launchMode="singleTop"
    android:supportsPictureInPicture="true"
    ... />
```

3. `FlPiPAndroidOptions.overlay()` uses `WindowManager` and requires the `SYSTEM_ALERT_WINDOW`
   permission, which the plugin declares. `present()` opens the system permission page and waits for
   the user: the overlay is created after the permission is granted, otherwise a `FlPiPException`
   with `FlPiPErrorCode.permissionDenied` is thrown. `FlPiPAndroidOptions.systemPip()` needs no
   overlay permission.

### iOS setup

1. Add `Background Modes` in `Signing & Capabilities` and check
   `Audio, AirPlay, And Picture in Picture`.
2. Register the app plugins on the PiP engine:

```swift
func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    FlPiPPlugin.pluginRegistrant = { registry in
        GeneratedPluginRegistrant.register(with: registry)
    }
}
```

### HarmonyOS setup

1. Render the main page with `FlPiPSurface` instead of `FlutterPage` and pass the `viewId` written
   into LocalStorage by `FlutterAbility`.
2. Register the app plugins on the PiP engine with
   `FlPiPPlugin.pluginRegistrant = (engine) => GeneratedPluginRegistrant.registerWith(engine)`.

### Usage

```dart
import 'package:fl_pip/fl_pip.dart';

final FlMultiEngineInfo engine = await FlPiP.instance.present(
  name: 'pipMain',
  android: const FlPiPAndroidOptions.overlay(),
  ios: const FlPiPIOSOptions(),
  harmonyOS: const FlPiPHarmonyOSOptions.systemPip(),
);

await FlPiP.instance.present(
  name: 'pipMain',
  android: const FlPiPAndroidOptions.systemPip(aspectRatio: FlPiPAspectRatio.landscape()),
);

// HarmonyOS system PiP: aspect ratio only, 16:9 when omitted
await FlPiP.instance.present(
  name: 'pipMain',
  harmonyOS: const FlPiPHarmonyOSOptions.systemPip(aspectRatio: FlPiPAspectRatio.vertical()),
);

await FlPiP.instance.dismiss();

final bool available = await FlPiP.instance.isAvailable;
final FlPiPStatusInfo? info = await FlPiP.instance.isActive;

await FlPiP.instance.toggle(FlPiPAppState.background);
final int delivered = await FlPiP.instance.send('main/message');
```

### Engine management and messages

Engines are owned by `fl_multi_engine`; `present(name:)` reads the engine registry and creates it
with the `pipMain` entry point when it does not exist, returning `FlMultiEngineInfo`. Failures
throw `FlPiPException` (`FlPiPErrorCode.engineCreationFailed` / `engineNotFound`).
`destroyEngineOnDismiss` (default `true`) decides whether the engine is destroyed or kept when the
window closes. The main engine can only be presented with `destroyEngineOnDismiss = false`;
passing it with `true` returns `invalid_configuration`.

The entry point is still named `pipMain` and must be annotated with `@pragma('vm:entry-point')`.
Both the main engine and the PiP engine register the same `fl_pip` channel; `send()` delivers only
to the engine passed to `present(name:)` (for example `pipMain`, or a custom name), and calls made
by that engine go back to the main engine. Both listen through `FlPiP.instance.messages`, and other
engines never receive the message.
`FlPiPStatusInfo.hasEngine` tells whether the engine passed to `present(name:)` still exists,
independent of the window; it stays `true` after the window closes when the engine is kept alive
with `destroyEngineOnDismiss = false`, and turns `false` once the engine is destroyed.
HarmonyOS system PiP panel actions are exposed as `method: 'control'` messages on
`FlPiP.instance.messages` (`action` is `playPause` or `skip`).

### Video playback

`FlPiPVideo.instance.play(...)` takes independent
`FlPiPVideoAndroidOptions` / `FlPiPVideoIOSOptions` / `FlPiPVideoHarmonyOSOptions`; only the current
platform is used. Controls:

`stop`、`setPlaying` / `pause` / `resume`、`seek`、`seekBy`、`stopPlayback`、`setSpeed`、
`setVolume`、`setLooping`、`status`、`isActive`、`events`.

Video events (`FlPiPVideoEvent.event`): `play`, `playPause`, `skip`, `close`, `ended`, `position`,
`stop`, `speed`, `volume` and `error`; `skip` is only emitted by the HarmonyOS system PiP panel
and uses the `rewind` / `forward` action. `controls`
(panel shown / hidden) is only emitted by the Android overlay and the HarmonyOS in-app overlay;
iOS leaves the panel to the system. The in-app overlays match each other: dragging keeps an 8 dp /
8 vp gap from the screen edges, tapping the video brings back the auto-hidden panel and the
play/pause button uses the system media icon.

`FlPiPWindow.width` / `height` / `top` / `left` are **physical pixels** (not dp / vp / logical
pixels). The native side sizes the video view to that size, aspect-fits the video inside it, and
uses `top` / `left` to position the video window on the screen. Multiply logical pixels by
`MediaQuery.devicePixelRatioOf(context)` before passing them.

The HarmonyOS system PiP cannot use a custom pixel size or position: `systemPip()` takes an
`aspectRatio` instead (`null` uses the video's original ratio), and the system decides the actual
size and position, so `window` / `top` / `left` are ignored.

The Android and HarmonyOS overlays always stay on screen: `width` / `height` are capped to the
screen size and `left` / `top` are capped to `screen size - window size`.

### Error handling

Failures throw `FlPiPException`; inspect `code` (`FlPiPErrorCode`, see the Chinese table above).
An `FlPiPAspectRatio` outside `1/2.39 ~ 2.39` throws
`FlPiPAspectRatioNotSupportedException` for Android and HarmonyOS `systemPip` before the native
call; the native side also returns `invalidConfiguration`. The HarmonyOS video `systemPip()` is
only validated when an explicit `aspectRatio` is passed.

### Notes

- iOS renders engines other than the main engine into the PiP window through their
  `FlutterViewController`. The main engine has no standalone `FlutterEngine` instance, so the
  window loops placeholder media generated natively for `FlPiPIOSOptions.window` (1-second black
  video plus a silent audio track); no video, audio or `packageName` has to be passed. The
  requested size only determines the PiP window aspect ratio.
- iOS videos use a hidden inline preview (0.01pt in the top-left corner) and network sources start
  PiP with local placeholder media before the real item is swapped in.
- Android `overlay` and `systemPip` are mutually exclusive, as are the HarmonyOS system PiP and
  in-app overlay. The HarmonyOS system PiP only uses `aspectRatio` (`window` / `top` / `left` are
  ignored) and the system manages its size and position.
- `isAvailable` reports whether system PiP is available; the overlay does not depend on it.
- Unsupported platforms safely return `false` / `null`.
