# fl_pip 示例

演示如何使用 [fl_pip](https://pub.dev/packages/fl_pip) 插件。

## 运行

```shell
flutter pub get
flutter run
```

## 平台配置

- Android：`MainActivity` 继承 `FlPiPActivity`，启动 Activity 声明
  `android:supportsPictureInPicture="true"`，悬浮窗需要 `SYSTEM_ALERT_WINDOW` 权限。
- iOS：`Info.plist` 开启 `audio` 后台模式；`AppDelegate` 通过
  `FlPiPPlugin.pluginRegistrant` 为新引擎注册生成插件。非主引擎直接渲染到系统画中画，
  主引擎则使用原生生成的占位媒体。
- HarmonyOS：入口页使用 `FlPiPSurface` 渲染 Flutter，`EntryAbility` 设置
  `FlPiPPlugin.pluginRegistrant`。

## 页面结构

- **首页**：画中画状态概览、当前模式、功能入口和调用结果。
- **视频播放**：asset / file / network 三种来源，视频窗口宽高与 `top` / `left`
  （均为物理像素），播放控制面板开关与事件列表。
- **画中画与引擎消息**：开启/关闭、承载方式（Android 系统画中画 / 悬浮窗，
  HarmonyOS 系统画中画 / 浮窗）、窗口配置；只要 `pipMain` 引擎未被销毁，就启用与主引擎的
  消息交互，与画中画窗口是否打开无关。
- **调试**：`isAvailable` / `isActive` 和前后台切换。

页面共享同一个 `DemoController`，所有 API 调用统一记录到首页的“调用结果”。

示例覆盖了两种画中画模式、全部配置参数、播放控制、媒体事件和跨引擎消息。
更多细节见[插件文档](../README.md)。
