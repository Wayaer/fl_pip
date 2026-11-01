import 'package:example/src/demo_controller.dart';
import 'package:example/src/demo_widgets.dart';
import 'package:fl_pip/fl_pip.dart';
import 'package:flutter/material.dart';

/// 调试页面：查询支持情况、激活状态与前后台切换。
///
/// Debug page: availability, active state and app foreground/background switching.
class ToolsPage extends StatelessWidget {
  const ToolsPage({super.key, required this.controller});

  /// 共享的示例状态。 / The shared demo state.
  final DemoController controller;

  bool get isAndroid => controller.isAndroid;

  /// 鸿蒙同样支持前后台切换调试。 / HarmonyOS supports the same debug actions.
  bool get isHarmonyOS => controller.isHarmonyOS;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('调试')),
    body: ListenableBuilder(
      listenable: controller,
      builder: (BuildContext context, Widget? child) => ListView(
        padding: const EdgeInsets.only(top: 8, bottom: 24),
        children: <Widget>[buildMethodsSection(context), buildResultsSection(context)],
      ),
    ),
  );

  Widget buildMethodsSection(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return DemoSection(
      title: '其他方法',
      description: '每次调用都会记录到首页和本页下方的“调用结果”中。',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: DemoButton(text: '是否支持 isAvailable', onPressed: controller.checkAvailable),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: DemoButton(text: '是否开启 isActive', onPressed: controller.checkActive),
              ),
            ],
          ),
          if (isAndroid || isHarmonyOS) ...<Widget>[
            const SizedBox(height: 8),
            Row(
              children: <Widget>[
                Expanded(
                  child: DemoButton(
                    text: '切换到后台 background',
                    onPressed: () => controller.toggle(FlPiPAppState.background),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: DemoButton(
                    text: '切换到前台 foreground',
                    onPressed: () => controller.toggle(FlPiPAppState.foreground),
                  ),
                ),
              ],
            ),
            if (isHarmonyOS) ...<Widget>[
              const SizedBox(height: 4),
              Text('鸿蒙没有把应用切回前台的公开 API，foreground 会被忽略。', style: theme.textTheme.bodySmall),
            ],
          ],
        ],
      ),
    );
  }

  /// 调试页下方的调用结果，与首页的展示保持一致。
  /// The call results shown below the debug actions, matching the home page.
  Widget buildResultsSection(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return DemoSection(
      title: '调用结果',
      description: '最新的调用在最上方，插件抛出的异常会以“异常：”开头显示。',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          if (controller.calls.isEmpty)
            Text('暂无调用，点击上方按钮开始调试。', style: theme.textTheme.bodySmall)
          else
            ...controller.calls.map((DemoLogEntry call) => DemoLogTile(entry: call)),
          if (controller.calls.isNotEmpty) ...<Widget>[
            const SizedBox(height: 4),
            DemoButton(text: '清空结果', onPressed: controller.clearResults),
          ],
        ],
      ),
    );
  }
}
