import { FlutterAbility, FlutterEngine } from '@ohos/flutter_ohos';
import FlPiPPlugin from 'fl_pip';
import { GeneratedPluginRegistrant } from '../plugins/GeneratedPluginRegistrant';

export default class EntryAbility extends FlutterAbility {
  configureFlutterEngine(flutterEngine: FlutterEngine) {
    super.configureFlutterEngine(flutterEngine)
    GeneratedPluginRegistrant.registerWith(flutterEngine)
    // 画中画引擎由插件内部创建，需要注册 App 的生成插件，画中画页面才能使用其它插件。
    // The PiP engine is created by the plugin and needs the app plugins registered.
    FlPiPPlugin.pluginRegistrant = (engine: FlutterEngine) => {
      GeneratedPluginRegistrant.registerWith(engine)
    }
  }
}
