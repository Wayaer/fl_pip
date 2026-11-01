import 'package:example/src/demo_controller.dart';
import 'package:example/src/demo_widgets.dart';
import 'package:fl_pip/fl_pip.dart';
import 'package:flutter/material.dart';

/// 画中画配置、开关与引擎消息页面。
///
/// Picture-in-picture configuration, toggling and engine messages.
class PiPPage extends StatelessWidget {
  const PiPPage({super.key, required this.controller});

  /// 共享的示例状态。 / The shared demo state.
  final DemoController controller;

  bool get isAndroid => controller.isAndroid;

  bool get isIOS => controller.isIOS;

  bool get isHarmonyOS => controller.isHarmonyOS;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('画中画与引擎消息')),
    body: ListenableBuilder(
      listenable: controller,
      builder: (BuildContext context, Widget? child) => FlPiPBuilder(
        builder: (FlPiPStatusInfo? info) {
          final FlPiPStatus status = info?.status ?? FlPiPStatus.disabled;
          final bool enabled = status == FlPiPStatus.enabled;
          // 消息是否可用只看 pipMain 引擎有没有被销毁，与画中画窗口是否展示无关。
          // Messages depend only on whether the pipMain engine still exists, not on the window.
          final bool canSendMessage = info?.hasEngine ?? false;
          return ListView(
            padding: const EdgeInsets.only(top: 8, bottom: 24),
            children: <Widget>[
              buildStatusSection(context, info, status),
              if (isAndroid)
                buildModeSection(context, enabled)
              else if (isHarmonyOS)
                buildModeSection(context, enabled),
              if (isAndroid && controller.mode == FlPiPPresentationMode.overlay)
                buildAndroidOverlayConfig(context, enabled),
              if (isAndroid && controller.mode == FlPiPPresentationMode.systemPip)
                buildAndroidSystemPipConfig(context, enabled),
              if (isHarmonyOS) buildHarmonyOSConfig(context, enabled),
              if (isIOS) buildIOSConfig(context, enabled),
              buildMessageSection(context, canSendMessage),
            ],
          );
        },
      ),
    ),
  );

  Widget buildStatusSection(BuildContext context, FlPiPStatusInfo? info, FlPiPStatus status) {
    final ThemeData theme = Theme.of(context);
    final Color color = pipStatusColor(context, status);
    final bool enabled = status == FlPiPStatus.enabled;
    return DemoSection(
      title: '画中画窗口',
      description: windowDescription(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(pipStatusIcon(status), size: 20, color: color),
              const SizedBox(width: 8),
              Expanded(
                child: Text('画中画${pipStatusLabel(status)}', style: theme.textTheme.titleSmall?.copyWith(color: color)),
              ),
              PipTimer(
                style: theme.textTheme.titleLarge?.copyWith(color: color, fontWeight: FontWeight.w600),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(pipStatusDescription(status), style: theme.textTheme.bodySmall),
          const SizedBox(height: 8),
          DemoInfoRow(label: '承载方式 mode', value: info?.mode?.value ?? '-'),
          DemoInfoRow(label: '已创建引擎 hasEngine', value: '${info?.hasEngine ?? false}'),
          DemoInfoRow(label: 'isSupportedPlatform', value: '${FlPiP.instance.isSupportedPlatform}'),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: controller.destroyEngineOnDismiss,
            onChanged: enabled
                ? null
                : (bool value) => controller.update(() {
                    controller.destroyEngineOnDismiss = value;
                  }),
            title: const Text('关闭时销毁引擎 destroyEngineOnDismiss'),
          ),
          const SizedBox(height: 12),
          if (enabled)
            DemoButton(text: '关闭画中画 dismiss()', primary: true, onPressed: controller.dismiss)
          else
            DemoButton(
              text: '开启画中画 present()',
              primary: true,
              // 系统画中画不可用时禁用；悬浮窗 / 应用内弹窗不依赖系统画中画能力。
              // Disabled when system PiP is unavailable; the overlay does not depend on it.
              onPressed: status == FlPiPStatus.unavailable && controller.mode == FlPiPPresentationMode.systemPip
                  ? null
                  : () => controller.present(context),
            ),
        ],
      ),
    );
  }

  /// 承载方式：Android 与 HarmonyOS 各有两种，切换后在下一次 present() 时生效。
  ///
  /// Presentation mode: Android and HarmonyOS both have two; the change applies on the next
  /// present().
  Widget buildModeSection(BuildContext context, bool enabled) {
    final ThemeData theme = Theme.of(context);
    return DemoSection(
      title: '承载方式',
      description: isAndroid
          ? 'Android 默认系统弹窗（悬浮窗）；系统画中画会把整个 FlutterActivity 缩成系统窗口，只用宽高比。'
          : 'HarmonyOS 默认系统画中画；应用内浮窗只在 App 前台可见，但可以拖拽与交互。',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SegmentedButton<FlPiPPresentationMode>(
            segments: const <ButtonSegment<FlPiPPresentationMode>>[
              ButtonSegment<FlPiPPresentationMode>(value: FlPiPPresentationMode.systemPip, label: Text('系统画中画')),
              ButtonSegment<FlPiPPresentationMode>(value: FlPiPPresentationMode.overlay, label: Text('悬浮窗')),
            ],
            selected: <FlPiPPresentationMode>{controller.mode},
            onSelectionChanged: enabled
                ? null
                : (Set<FlPiPPresentationMode> selection) => controller.update(() {
                    controller.mode = selection.first;
                  }),
          ),
          const SizedBox(height: 8),
          Text(
            controller.mode == FlPiPPresentationMode.systemPip
                ? '系统画中画：Android 只把宿主 Activity 缩成系统窗口，引擎虽已创建但不渲染；'
                      'iOS 会把 ${DemoController.pipEngineName} 引擎渲染进系统窗口；'
                      'HarmonyOS 会把引擎的 surface 移入系统窗口。'
                : '悬浮窗：把 ${DemoController.pipEngineName} 引擎放进弹窗；'
                      '只有该引擎创建成功后，主引擎才能向它发送消息，它发送时回到主引擎。',
            style: theme.textTheme.bodySmall,
          ),
        ],
      ),
    );
  }

  /// Android 悬浮窗：完整的位置、宽高（物理像素）与圆角，关闭按钮使用系统图标。
  ///
  /// Android overlay: full position, size in physical pixels and radius; the close button uses
  /// the system icon.
  Widget buildAndroidOverlayConfig(BuildContext context, bool enabled) => DemoSection(
    title: 'FlPiPAndroidOptions.overlay()',
    description: '系统弹窗：WindowManager 悬浮窗，由 present(name:) 指定的引擎渲染。窗口宽高与位置都是物理像素。',
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        buildWindowControls(context),
        const Divider(),
        slider(
          '悬浮窗圆角 cornerRadius',
          controller.overlayCornerRadius,
          0,
          32,
          (double value) => controller.overlayCornerRadius = value,
        ),
      ],
    ),
  );

  /// Android 系统画中画：只用宽高比，引擎虽已创建但不渲染。
  ///
  /// Android system PiP: aspect ratio only; the engine is created but not rendered.
  Widget buildAndroidSystemPipConfig(BuildContext context, bool enabled) {
    final ThemeData theme = Theme.of(context);
    return DemoSection(
      title: 'FlPiPAndroidOptions.systemPip()',
      description: '系统画中画只用宽高比，把宿主 Activity 缩成系统窗口；引擎会被创建以返回引擎信息，但不会被渲染。',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text('窗口宽高比 aspectRatio', style: theme.textTheme.titleSmall),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: DemoController.aspectRatios
                .map(
                  (FlPiPAspectRatio ratio) => ChoiceChip(
                    label: Text(ratioLabel(ratio)),
                    selected: controller.aspectRatio == ratio,
                    onSelected: enabled
                        ? null
                        : (bool selected) {
                            if (selected) {
                              controller.update(() {
                                controller.aspectRatio = ratio;
                              });
                            }
                          },
                  ),
                )
                .toList(),
          ),
          const SizedBox(height: 8),
          DemoInfoRow(label: '实际比例', value: controller.aspectRatio.ratio.toStringAsFixed(3)),
          DemoInfoRow(
            label: 'Android 是否支持',
            value: '${controller.aspectRatio.isSupported}',
            valueColor: controller.aspectRatio.isSupported ? null : theme.colorScheme.error,
          ),
        ],
      ),
    );
  }

  /// iOS：把命名引擎渲染进系统画中画；主引擎才使用原生生成的纯黑占位媒体。
  ///
  /// iOS renders the named engine in the system PiP; only the main engine uses natively
  /// generated placeholder media.
  Widget buildIOSConfig(BuildContext context, bool enabled) {
    final ThemeData theme = Theme.of(context);
    return DemoSection(
      title: 'FlPiPIOSOptions',
      description:
          'iOS 会把 present(name:) 指定的引擎渲染进系统画中画窗口；宽高只决定窗口比例，无需再传视频、音频资源与 packageName。'
          '主引擎没有独立的 FlutterEngine，窗口播放原生生成的 1 秒纯黑视频与静音音轨。',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          DemoInfoRow(label: '独立引擎', value: '渲染进画中画（hasEngine = true）'),
          DemoInfoRow(label: '占位媒体', value: '仅主引擎使用，原生生成并按尺寸缓存（未配置 window 时按屏幕宽度 16:9）'),
          buildWindowControls(context),
          const SizedBox(height: 8),
          Text('宽高与 left / top 都是物理像素；宽高只决定画中画窗口比例，实际大小与位置由系统管理。', style: theme.textTheme.bodySmall),
        ],
      ),
    );
  }

  /// HarmonyOS：系统画中画只用宽高比；overlay 支持位置、宽高、圆角与自定义控制面板。
  ///
  /// HarmonyOS: the system PiP only uses the aspect ratio; the overlay also supports offsets,
  /// the size, the corner radius and the custom panel.
  Widget buildHarmonyOSConfig(BuildContext context, bool enabled) {
    final ThemeData theme = Theme.of(context);
    final bool overlay = controller.mode == FlPiPPresentationMode.overlay;
    return DemoSection(
      title: overlay ? 'FlPiPHarmonyOSOptions.overlay()' : 'FlPiPHarmonyOSOptions.systemPip()',
      description: overlay
          ? '应用内浮窗：完整的位置与宽高（物理像素），cornerRadius 生效，关闭按钮使用系统图标。'
          : '系统画中画只用宽高比（aspectRatio），窗口大小与位置由系统管理；'
                'window、left / top 与 cornerRadius 不生效。',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          DemoInfoRow(label: '展示方式 mode', value: controller.mode.value),
          if (overlay) ...[
            buildWindowControls(context),
            const Divider(),
            slider(
              '浮窗圆角 cornerRadius',
              controller.overlayCornerRadius,
              0,
              32,
              (double value) => controller.overlayCornerRadius = value,
            ),
          ] else ...[
            Text('窗口宽高比 aspectRatio', style: theme.textTheme.titleSmall),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: DemoController.aspectRatios
                  .map(
                    (FlPiPAspectRatio ratio) => ChoiceChip(
                      label: Text(ratioLabel(ratio)),
                      selected: controller.aspectRatio == ratio,
                      onSelected: enabled
                          ? null
                          : (bool selected) {
                              if (selected) {
                                controller.update(() {
                                  controller.aspectRatio = ratio;
                                });
                              }
                            },
                    ),
                  )
                  .toList(),
            ),
            const SizedBox(height: 8),
            DemoInfoRow(label: '实际比例', value: controller.aspectRatio.ratio.toStringAsFixed(3)),
            DemoInfoRow(
              label: '系统是否支持',
              value: '${controller.aspectRatio.isSupported}',
              valueColor: controller.aspectRatio.isSupported ? null : theme.colorScheme.error,
            ),
          ],
        ],
      ),
    );
  }

  /// 跨引擎消息：主引擎通过同一个 fl_pip 通道向画中画引擎发送消息，画中画引擎发送时回到主引擎。
  ///
  /// Cross-engine messages: the main engine sends to the picture-in-picture engine through the same
  /// fl_pip channel, and messages from that engine go back to the main engine.
  Widget buildMessageSection(BuildContext context, bool canSendMessage) {
    final ThemeData theme = Theme.of(context);
    return DemoSection(
      title: '引擎消息',
      description: canSendMessage
          ? '主引擎发送的消息投递给 ${DemoController.pipEngineName} 引擎，该引擎发送时回到主引擎；'
                '只要引擎未被销毁，即使画中画已关闭也可以收发。'
          : '请先开启画中画并成功创建 ${DemoController.pipEngineName} 引擎，消息交互才会启用。',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          DemoButton(text: '发送消息 FlPiP.send()', onPressed: canSendMessage ? controller.sendMessage : null),
          const SizedBox(height: 8),
          Text('收到的消息', style: theme.textTheme.titleSmall),
          if (controller.engineMessages.isEmpty)
            Text('暂无消息', style: theme.textTheme.bodySmall)
          else
            ...controller.engineMessages
                .take(5)
                .map(
                  (FlPiPMessage message) =>
                      Text('${message.method}: ${message.arguments}', style: theme.textTheme.bodySmall),
                ),
        ],
      ),
    );
  }

  /// 自定义窗口：页面使用逻辑像素，传给原生前乘以 devicePixelRatio，原生只接受物理像素。
  ///
  /// Custom window adjusted in logical pixels and converted to physical pixels before use.
  Widget buildWindowControls(BuildContext context) {
    final double pixelRatio = MediaQuery.devicePixelRatioOf(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          value: controller.useCustomWindow,
          onChanged: (bool value) => controller.update(() {
            controller.useCustomWindow = value;
          }),
          title: const Text('自定义窗口 window（物理像素）'),
          subtitle: Text('页面按逻辑像素调整，传给原生时乘以 devicePixelRatio（当前 $pixelRatio）；原生收到的是物理像素。'),
        ),
        if (controller.useCustomWindow) ...<Widget>[
          buildPixelSlider(
            context,
            '左边距 left：${controller.windowLeft.toStringAsFixed(0)} 逻辑像素 → '
            '${(controller.windowLeft * pixelRatio).toStringAsFixed(0)} px',
            controller.windowLeft,
            0,
            400,
            (double value) => controller.windowLeft = value,
          ),
          buildPixelSlider(
            context,
            '上边距 top：${controller.windowTop.toStringAsFixed(0)} 逻辑像素 → '
            '${(controller.windowTop * pixelRatio).toStringAsFixed(0)} px',
            controller.windowTop,
            0,
            800,
            (double value) => controller.windowTop = value,
          ),
          buildPixelSlider(
            context,
            '宽度 width：${controller.windowWidth.toStringAsFixed(0)} 逻辑像素 → '
            '${(controller.windowWidth * pixelRatio).toStringAsFixed(0)} px',
            controller.windowWidth,
            100,
            800,
            (double value) => controller.windowWidth = value,
          ),
          buildPixelSlider(
            context,
            '高度 height：${controller.windowHeight.toStringAsFixed(0)} 逻辑像素 → '
            '${(controller.windowHeight * pixelRatio).toStringAsFixed(0)} px',
            controller.windowHeight,
            100,
            800,
            (double value) => controller.windowHeight = value,
          ),
        ],
      ],
    );
  }

  Widget buildPixelSlider(
    BuildContext context,
    String label,
    double value,
    double min,
    double max,
    ValueChanged<double> onChanged,
  ) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: <Widget>[
      Text(label, style: Theme.of(context).textTheme.bodySmall),
      Slider(
        value: value,
        min: min,
        max: max,
        onChanged: (double selected) => controller.update(() {
          onChanged(selected);
        }),
      ),
    ],
  );

  Widget slider(String label, double value, double min, double max, ValueChanged<double> onChanged) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: <Widget>[
      Text('$label: ${value.toStringAsFixed(0)}'),
      Slider(
        value: value,
        min: min,
        max: max,
        onChanged: (double selected) => controller.update(() {
          onChanged(selected);
        }),
      ),
    ],
  );

  /// 描述当前窗口渲染的内容以及由哪个 Flutter 引擎驱动。
  ///
  /// Describes what the window renders and which engine keeps it alive.
  String windowDescription() {
    if (isAndroid) {
      return controller.mode == FlPiPPresentationMode.overlay
          ? '系统弹窗：WindowManager 悬浮窗由 ${DemoController.pipEngineName} 引擎渲染，显示带实时计时器的 PiPHomePage。'
          : '系统画中画：Android 把当前 FlutterActivity 渲染到系统窗口，本页面与计时器继续运行；引擎已创建但不渲染。';
    }
    if (isIOS) {
      return '系统画中画：iOS 把 ${DemoController.pipEngineName} 引擎渲染进系统窗口，Flutter 引擎继续运行；主引擎才使用纯黑占位媒体。';
    }
    if (isHarmonyOS) {
      return controller.mode == FlPiPPresentationMode.overlay
          ? '应用内浮窗：在 FlPiPSurface 之上叠加可拖拽浮窗，由 ${DemoController.pipEngineName} 引擎渲染，仅前台可见。'
          : '系统画中画：HarmonyOS 把 ${DemoController.pipEngineName} 引擎的 surface 移入系统窗口，主页面不会被搬走。';
    }
    return '当前平台不支持画中画，所有调用都会返回 false 或 null。';
  }
}
