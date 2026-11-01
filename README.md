# fl_pip 仓库

本仓库统一管理两个 Flutter 插件，二者通过路径依赖配合使用：

| 插件 | 说明 | 支持平台 |
| ---- | ---- | -------- |
| [`fl_pip`](fl_pip/README.md) | 在原生画中画或系统悬浮窗中播放视频、帧数据，或展示命名 engine 内容 | Android、iOS、HarmonyOS |
| [`fl_multi_engine`](fl_multi_engine/README.md) | 创建、销毁、查询命名 engine，并在 engine 之间定向转发消息；不含任何画中画逻辑 | Android、iOS、HarmonyOS、macOS、Windows、Linux |

## 目录结构

```
fl_pip/                         # 仓库根目录（git 管理）
├── fl_pip/                     # 画中画插件
│   ├── lib/
│   ├── android/
│   ├── ios/
│   ├── example/                # 示例 App
│   ├── doc/                    # 设计文档
│   └── README.md               # 插件使用文档
├── fl_multi_engine/            # 命名 engine 管理插件
│   ├── lib/
│   ├── android/ darwin/ ohos/ windows/ linux/
│   ├── example/                # 示例 App
│   └── README.md               # 插件使用文档
└── README.md                   # 仓库说明（本文件）
```

## 插件关系

依赖方向是单向的：`fl_pip → fl_multi_engine`。`fl_multi_engine` 不依赖 `fl_pip`，也不包含任何画中画逻辑，展示形态由宿主 App 或 `fl_pip` 负责。

- `fl_pip` 使用 `fl_multi_engine` 创建独立 engine，再将其画面放入画中画/系统弹窗。
- `fl_pip` 支持 Android / iOS / HarmonyOS（HarmonyOS 支持系统画中画，视频/帧窗口同样使用系统画中画）；`fl_multi_engine` 额外支持 macOS / Windows / Linux。

## 本地开发

两个插件各自独立，`fl_pip` 通过路径依赖指向同级的 `fl_multi_engine`：

```yaml
# fl_pip/pubspec.yaml
dependency_overrides:
  fl_multi_engine:
    path: ../fl_multi_engine
```

```yaml
# fl_pip/example/pubspec.yaml
dependency_overrides:
  fl_multi_engine:
    path: ../../fl_multi_engine
```

首次拉取代码或目录结构变更后，依次执行：

```bash
# 独立插件
cd fl_multi_engine && flutter pub get
cd example && flutter pub get

# 画中画插件
cd fl_pip && flutter pub get
cd example && flutter pub get

# iOS 示例（非 SPM 模式使用 CocoaPods）
cd fl_pip/example/ios && pod install
```

运行示例：

```bash
cd fl_pip/example && flutter run
cd fl_multi_engine/example && flutter run
```

## 环境要求

- Flutter `>= 3.41.0`，Dart `>= 3.11.0`（`fl_pip`）
- Android：`compileSdk 36`、AGP 9.x、Kotlin 2.4，最低 API 24
- iOS：最低 15.0，CocoaPods 与 Swift Package Manager（SPM）均支持
- HarmonyOS：鸿蒙版 Flutter SDK `3.44.9`（已在 `3.44.9+ohos-0.0.1-canary1` 验证），DevEco Studio / OpenHarmony SDK

各插件更精确的版本约束见各自的 `pubspec.yaml`。

## 相关文档

- [fl_pip 使用文档](fl_pip/README.md)
- [fl_multi_engine 使用文档](fl_multi_engine/README.md)
- [多 engine 设计方案](fl_pip/doc/multi_engine_design.md)
- [engine 消息桥](fl_pip/doc/engine_bridge.md)

---

## English

This repository contains two Flutter plugins that work together through a path dependency:

| Plugin | Description | Platforms |
| ------ | ----------- | --------- |
| [`fl_pip`](fl_pip/README.md) | Plays videos/frames or mirrors named engines in a native picture-in-picture or overlay window | Android, iOS, HarmonyOS |
| [`fl_multi_engine`](fl_multi_engine/README.md) | Creates, destroys, lists and connects named engines; no picture-in-picture logic | Android, iOS, HarmonyOS, macOS, Windows, Linux |

The dependency direction is one-way: `fl_pip → fl_multi_engine`. `fl_multi_engine` never depends on
`fl_pip`, and presentation is the responsibility of the host app or `fl_pip`.

`fl_pip` supports Android, iOS and HarmonyOS. HarmonyOS provides the system PiP, the float view
and the native video/frame window.

### Local development

`fl_pip` uses a path override for `fl_multi_engine`:

```yaml
# fl_pip/pubspec.yaml
dependency_overrides:
  fl_multi_engine:
    path: ../fl_multi_engine
```

```yaml
# fl_pip/example/pubspec.yaml
dependency_overrides:
  fl_multi_engine:
    path: ../../fl_multi_engine
```

Then run:

```bash
cd fl_multi_engine && flutter pub get && cd example && flutter pub get
cd fl_pip && flutter pub get && cd example && flutter pub get
cd fl_pip/example/ios && pod install   # CocoaPods only
```

Run an example:

```bash
cd fl_pip/example && flutter run
cd fl_multi_engine/example && flutter run
```

### Environment

- Flutter `>= 3.41.0`, Dart `>= 3.11.0`
- Android `compileSdk 36`, AGP 9.x, Kotlin 2.4, min API 24
- iOS 15.0+, CocoaPods and Swift Package Manager (SPM)
- HarmonyOS: HarmonyOS Flutter SDK `3.44.9` (verified with `3.44.9+ohos-0.0.1-canary1`), DevEco Studio / OpenHarmony SDK

See each plugin README and `pubspec.yaml` for exact constraints.
