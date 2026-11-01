# Changelog

## 4.0.0

### 中文

#### 功能

* 在 Android / iOS / HarmonyOS 的原生画中画或悬浮窗中展示 Flutter 页面与视频
* 引擎由 `fl_multi_engine` 托管：`present(name:)` 按名称读取引擎，不存在时通过 `pipMain` 入口补建，
  并返回该引擎的 `FlMultiEngineInfo`
* `FlPiP` 提供 `present(name:, destroyEngineOnDismiss:)`、`dismiss()`、`isAvailable`、`isActive`、
  `toggle()`、`send()`，以及实时响应状态的 `FlPiPBuilder`
* `FlPiPStatusInfo.hasEngine` 表示 `present(name:)` 指定的引擎是否仍然存在，与窗口是否打开无关
* 主引擎与画中画引擎通过同一个 `fl_pip` 通道收发消息：`send()` 投递给 `present(name:)` 指定的画中画引擎
  （例如 `pipMain`，也可以是自定义名称），该引擎调用时投递回主引擎，`FlPiP.instance.messages` 负责监听
* 三端参数是独立的类：`FlPiPAndroidOptions`、`FlPiPIOSOptions`、`FlPiPHarmonyOSOptions`
* 画中画与视频窗口统一用 `FlPiPWindow` 设置 `width` / `height` / `top` / `left`，单位为物理像素（px）
* 原生实现分为 `FlPiPPlugin`（通道分派）、`FlPiPEngineManager`、`FlPiPVideoManager`，以及统一维护
  窗口状态、`owner`（engine / video）与 `mode`（systemPip / overlay）的 `FlPiPWindowManager`
* 原生通道名为 `FlPiPChannel.name`（`'fl_pip'`），原生失败统一抛出带 `FlPiPErrorCode` 的
  `FlPiPException`

#### Android

* `FlPiPAndroidOptions.overlay()` 用 `WindowManager` 展示引擎悬浮窗，支持像素单位的 `window`
  与 `cornerRadius`
* `FlPiPAndroidOptions.systemPip()` 把整个 Activity 缩进系统画中画窗口，只接受 `aspectRatio`
* `present()` 自动申请悬浮窗权限并在用户操作后继续：授权后创建悬浮窗，拒绝时抛出
  `FlPiPErrorCode.permissionDenied`
* 悬浮窗使用 `FlutterTextureView` 在硬件加速窗口中渲染；未传 `window` 时高度默认 16:9；
  `width` / `height` 超过屏幕时按屏幕尺寸截断，`left` / `top` 按 `屏幕尺寸 - 窗口尺寸` 截断，
  窗口始终留在屏幕内
* 拖动时与屏幕边缘保留 8 dp 间距；引擎悬浮窗与视频窗口共享同一份引擎状态

#### iOS

* 需要 iOS 15+，并在 `Background Modes` 中勾选 `Audio, AirPlay, And Picture in Picture`；
  同时支持 CocoaPods 与 Swift Package Manager
* 非主引擎通过 `AVPictureInPictureVideoCallViewController` 内容源，把自身的
  `FlutterViewController` 渲染进画中画窗口
* 主引擎没有独立的 `FlutterEngine` 实例，窗口循环播放原生按尺寸生成并缓存的占位媒体
  （1 秒纯黑视频 + 1 秒静音音轨）；无需传入视频、音频资源与 `packageName`，
  `FlPiPIOSOptions.window` 只决定窗口比例
* 内联视频层在 App 内固定为 0.01pt 并放在左上角，页面不出现视频框
* 网络视频先用本地占位媒体启动画中画，真实 `AVPlayerItem` 就绪后替换，缓冲在画中画窗口内完成
* `FlPiPVideo.stop()` 与 `FlPiP.dismiss()` 等 `didStopPictureInPicture` 之后再释放控制器与播放项，
  浮窗始终能正常关闭
* 系统静默忽略 `startPictureInPicture()` 时（例如上一个窗口刚关闭就播放新视频），通过看门狗重试启动
* `FlPiPVideoIOSOptions.showControls` 不生效：面板由系统绘制并自动隐藏

#### HarmonyOS

* `FlPiPHarmonyOSOptions.systemPip()` 只用 `aspectRatio`（`null` 时为 16:9），窗口大小与位置由系统
  管理；`FlPiPHarmonyOSOptions.overlay()` 接受像素单位的 `window` 与 `cornerRadius`
* `FlPiPSurface` 为指定引擎与视频挂载独立的 surface，主页面与主引擎保持不变
* 系统画中画与应用内弹窗都支持视频播放，应用内弹窗的控制面板、进度条与拖动行为与 Android 一致
* `FlPiPWindow` 的像素值通过 `px2vp` 换算为 vp

#### 视频

* `FlPiPVideo` 提供 `play()`、`stop()`、`setPlaying()`、`pause()`、`resume()`、`seek()`、`seekBy()`、
  `stopPlayback()`、`setSpeed()`、`setVolume()`、`setLooping()`、`status`、`isActive` 与 `events`
* 视频来源：`FlPiPVideoSource.asset(uri, {packageName})`、`FlPiPVideoSource.file(path)`、
  `FlPiPVideoSource.network(url)`
* 视频事件：`play`、`playPause`、`skip`、`close`、`ended`、`position`、`stop`、`speed`、`volume`、
  `error`，以及 `controls`（仅 Android 悬浮窗与 HarmonyOS 应用内弹窗上报）
* 视频控件按像素 `window` 设置尺寸，画面等比缩放并撑满其中一条边，`top` / `left` 决定窗口位置；
  进度条与 `seek()` / `seekBy()` 负责定位
* Android 与 HarmonyOS 的悬浮窗使用系统关闭图标，点击视频可重新显示自动隐藏的控制面板

#### 环境要求

* Dart `>= 3.11.0`，Flutter `>= 3.41.0`
* Android 7.0（API 24）及以上，AGP 9.x，Kotlin 2.4 built-in Kotlin，`compileSdk 36`
* iOS 15.0 及以上
* HarmonyOS 6.0（API 20）及以上

---

### English

#### Features

* Present Flutter pages and videos in native picture-in-picture or overlay windows on Android, iOS
  and HarmonyOS
* Engine lifecycle is owned by `fl_multi_engine`: `present(name:)` reads the named engine or creates
  it through the `pipMain` entry point, and returns its `FlMultiEngineInfo`
* `FlPiP` exposes `present(name:, destroyEngineOnDismiss:)`, `dismiss()`, `isAvailable`, `isActive`,
  `toggle()` and `send()`, plus `FlPiPBuilder` for reactive status
* `FlPiPStatusInfo.hasEngine` reports whether the engine passed to `present(name:)` still exists,
  independent of whether the window is open
* The main engine and the presented engine exchange messages through the single `fl_pip` channel:
  `send()` delivers to the engine passed to `present(name:)` (for example `pipMain`, or a custom
  name) and calls from that engine go back to the main engine, received by `FlPiP.instance.messages`
* Per-platform options are independent classes: `FlPiPAndroidOptions`, `FlPiPIOSOptions` and
  `FlPiPHarmonyOSOptions`
* `FlPiPWindow` sets `width` / `height` / `top` / `left` in physical pixels (px) for both PiP and
  video windows
* Native layout is split into `FlPiPPlugin` (channel dispatch), `FlPiPEngineManager`,
  `FlPiPVideoManager` and a shared `FlPiPWindowManager` that owns the single window state and
  `owner` (engine / video) plus `mode` (systemPip / overlay)
* The native channel name is `FlPiPChannel.name` (`'fl_pip'`), and native failures throw
  `FlPiPException` with a `FlPiPErrorCode`

##### Android

* `FlPiPAndroidOptions.overlay()` presents the engine in a `WindowManager` overlay with a pixel
  `window` and `cornerRadius`
* `FlPiPAndroidOptions.systemPip()` shrinks the whole Activity into the system PiP window and takes
  only `aspectRatio`
* `present()` requests the overlay permission automatically and continues once the user responds;
  a denial throws `FlPiPErrorCode.permissionDenied`
* Overlays render with `FlutterTextureView` inside a hardware-accelerated window, default to a
  16:9 height when no window is passed, and stay on screen: `width` / `height` are capped to the
  screen size, `left` / `top` to `screen size - window size`
* Dragging keeps an 8 dp gap from the screen edges, and the engine overlay and video window share
  the same single engine state

##### iOS

* Requires iOS 15+ and `Background Modes` with `Audio, AirPlay, And Picture in Picture`; both
  CocoaPods and Swift Package Manager are supported
* Engines other than the main engine render into the PiP window through an
  `AVPictureInPictureVideoCallViewController` content source backed by their `FlutterViewController`
* The main engine has no standalone `FlutterEngine` instance, so the window loops placeholder media
  (a 1-second black video with a silent audio track generated and cached natively per size); no
  video, audio or `packageName` has to be passed and `FlPiPIOSOptions.window` only decides the
  window aspect ratio
* The inline video preview stays hidden in the app: the `AVPlayerLayer` container is fixed at
  0.01pt in the top-left corner
* Network videos start PiP with local placeholder media and swap in the real `AVPlayerItem` once it
  is ready, so buffering happens inside the PiP window
* `FlPiPVideo.stop()` and `FlPiP.dismiss()` wait for `didStopPictureInPicture` before releasing the
  controller and player item, so the floating window always closes
* `startPictureInPicture()` is retried with a watchdog when the system silently ignores it, for
  example when a new video starts right after the previous window was closed
* `FlPiPVideoIOSOptions.showControls` has no effect: the system draws the PiP panel and hides it
  automatically

##### HarmonyOS

* `FlPiPHarmonyOSOptions.systemPip()` uses only `aspectRatio` (`null` means 16:9) and leaves the
  window size and position to the system; `FlPiPHarmonyOSOptions.overlay()` takes a pixel `window`
  and `cornerRadius`
* `FlPiPSurface` mounts a separate surface for the presented engine and for videos, so the host main
  page and the main engine stay unchanged
* Video playback works in both system PiP and the in-app overlay, with the custom control panel,
  progress slider and drag matching Android
* `FlPiPWindow` values are converted to vp with `px2vp`

##### Video

* `FlPiPVideo` exposes `play()`, `stop()`, `setPlaying()`, `pause()`, `resume()`, `seek()`,
  `seekBy()`, `stopPlayback()`, `setSpeed()`, `setVolume()`, `setLooping()`, `status`, `isActive`
  and `events`
* Sources: `FlPiPVideoSource.asset(uri, {packageName})`, `FlPiPVideoSource.file(path)` and
  `FlPiPVideoSource.network(url)`
* Events: `play`, `playPause`, `skip`, `close`, `ended`, `position`, `stop`, `speed`, `volume`,
  `error`, and `controls` (Android overlay and HarmonyOS in-app overlay only)
* The video view is sized to the pixel `window`, the picture aspect-fits inside it and `top` /
  `left` position the window; seeking uses the progress bar and the `seek()` / `seekBy()` APIs
* Android and HarmonyOS overlays use the system close icon and show the auto-hidden panel again
  when the video is tapped

#### Requirements

* Dart `>= 3.11.0`, Flutter `>= 3.41.0`
* Android 7.0 (API 24) or newer, AGP 9.x, Kotlin 2.4 built-in Kotlin, `compileSdk 36`
* iOS 15.0 or newer
* HarmonyOS 6.0 (API 20) or newer
