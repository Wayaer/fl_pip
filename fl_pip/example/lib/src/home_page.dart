import 'package:example/src/demo_controller.dart';
import 'package:example/src/demo_widgets.dart';
import 'package:example/src/pip_page.dart';
import 'package:example/src/tools_page.dart';
import 'package:example/src/video_page.dart';
import 'package:fl_pip/fl_pip.dart';
import 'package:flutter/material.dart';

/// 示例首页：概览和按功能拆分的入口。 / Demo home page with an overview and feature entries.
class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final DemoController controller = DemoController();

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  Future<void> open(Widget page) =>
      Navigator.of(context).push(MaterialPageRoute<void>(builder: (BuildContext context) => page));

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('fl_pip 示例')),
    body: ListenableBuilder(
      listenable: controller,
      builder: (BuildContext context, Widget? child) => ListView(
        padding: const EdgeInsets.only(top: 8, bottom: 24),
        children: <Widget>[buildOverview(context), buildEntries(context), buildResultsSection(context)],
      ),
    ),
  );

  Widget buildOverview(BuildContext context) => FlPiPBuilder(
    builder: (FlPiPStatusInfo? info) {
      final FlPiPStatus status = info?.status ?? FlPiPStatus.disabled;
      final ThemeData theme = Theme.of(context);
      final Color color = pipStatusColor(context, status);
      return DemoSection(
        title: '概览',
        description: '视频播放是第一排的主要功能；每次调用都会记录到下方“调用结果”中。',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Icon(pipStatusIcon(status), size: 20, color: color),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '画中画${pipStatusLabel(status)}',
                    style: theme.textTheme.titleSmall?.copyWith(color: color),
                  ),
                ),
                PipTimer(
                  style: theme.textTheme.titleLarge?.copyWith(color: color, fontWeight: FontWeight.w600),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(pipStatusDescription(status), style: theme.textTheme.bodySmall),
            const SizedBox(height: 8),
            DemoInfoRow(label: '承载方式', value: info?.mode?.value ?? '-'),
            DemoInfoRow(label: '是否创建独立引擎', value: '${info?.hasEngine ?? false}'),
            DemoInfoRow(label: 'isSupportedPlatform', value: '${FlPiP.instance.isSupportedPlatform}'),
            const SizedBox(height: 8),
            DemoInfoRow(label: '当前示例模式', value: controller.mode.name),
          ],
        ),
      );
    },
  );

  Widget buildEntries(BuildContext context) => DemoSection(
    title: '功能页面',
    child: Column(
      children: <Widget>[
        entryTile(
          icon: Icons.video_settings,
          title: '视频播放',
          subtitle: 'asset / file / network 三种来源、窗口宽高与位置（物理像素）、原生控制面板',
          onTap: () => open(VideoPage(controller: controller)),
        ),
        const Divider(height: 1),
        entryTile(
          icon: Icons.picture_in_picture_alt,
          title: '画中画与引擎消息',
          subtitle: '开启/关闭、承载方式、窗口配置，以及主引擎与 pipMain 引擎的消息交互',
          onTap: () => open(PiPPage(controller: controller)),
        ),
        const Divider(height: 1),
        entryTile(
          icon: Icons.hub_outlined,
          title: '调试',
          subtitle: 'isAvailable / isActive / 前后台切换',
          onTap: () => open(ToolsPage(controller: controller)),
        ),
      ],
    ),
  );

  Widget entryTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) => ListTile(
    contentPadding: EdgeInsets.zero,
    leading: Icon(icon),
    title: Text(title),
    subtitle: Text(subtitle),
    trailing: const Icon(Icons.chevron_right),
    onTap: onTap,
  );

  Widget buildResultsSection(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return DemoSection(
      title: '调用结果',
      description: '最新的调用在最上方，插件抛出的异常会以“异常：”开头显示。',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          if (controller.calls.isEmpty)
            Text('暂无调用，进入功能页面开始操作。', style: theme.textTheme.bodySmall)
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
