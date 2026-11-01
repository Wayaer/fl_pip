import { FlutterAbility, FlutterEngine } from '@ohos/flutter_ohos';
import FlMultiEnginePlugin from 'fl_multi_engine';
import { GeneratedPluginRegistrant } from '../plugins/GeneratedPluginRegistrant';

export default class EntryAbility extends FlutterAbility {
  configureFlutterEngine(flutterEngine: FlutterEngine) {
    super.configureFlutterEngine(flutterEngine)
    GeneratedPluginRegistrant.registerWith(flutterEngine)
    // 新引擎需要注册 App 的生成插件，这样 fl_multi_engine 之外的其他插件也能工作。
    // New engines need the app plugins so other plugins keep working there.
    FlMultiEnginePlugin.pluginRegistrant = (engine: FlutterEngine) => {
      GeneratedPluginRegistrant.registerWith(engine)
    }
  }
}
