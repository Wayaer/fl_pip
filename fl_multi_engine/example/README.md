# fl_multi_engine 示例

演示如何使用 fl_multi_engine 插件创建、销毁和连接命名 Flutter 引擎。

## 运行

```shell
flutter pub get
flutter run
```

## 示例内容

- 创建 headless 引擎；
- 销毁、查询状态和列出所有引擎；
- 向指定引擎发送消息，并实时接收消息；
- 新引擎中可以给主引擎回发消息并监听消息；
- Linux 通过 `main(List<String> args)` 分发 entrypoint，示例已处理；
- HarmonyOS 在 `ohos/entry/src/main/ets/entryability/EntryAbility.ets` 中设置
  `FlMultiEnginePlugin.pluginRegistrant`。

### HarmonyOS

```shell
flutter build hap --debug
```

先通过 DevEco Studio 打开 `ohos/` 并配置签名（`File -> Project Structure -> Signing Configs`）。

更多细节见[插件文档](../README.md)。
