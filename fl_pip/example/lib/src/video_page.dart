import 'package:example/src/demo_controller.dart';
import 'package:example/src/demo_widgets.dart';
import 'package:fl_pip/fl_pip.dart';
import 'package:flutter/material.dart';

/// 视频播放的演示页面。 / Demo page for video playback.
class VideoPage extends StatelessWidget {
  const VideoPage({super.key, required this.controller});

  /// 共享的示例状态。 / The shared demo state.
  final DemoController controller;

  bool get isIOS => controller.isIOS;

  bool get isAndroid => controller.isAndroid;

  bool get isHarmonyOS => controller.isHarmonyOS;

  /// HarmonyOS 系统画中画不显示任何自定义控件。
  /// The HarmonyOS system PiP shows no custom controls.
  bool get systemPipWithoutControls => isHarmonyOS && controller.mode == FlPiPPresentationMode.systemPip;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('视频播放')),
    body: ListenableBuilder(
      listenable: controller,
      builder: (BuildContext context, Widget? child) => ListView(
        padding: const EdgeInsets.only(top: 8, bottom: 24),
        children: <Widget>[
          if (isHarmonyOS) buildModeSection(context),
          buildVideoSection(context),
          buildStatusSection(context),
        ],
      ),
    ),
  );

  /// HarmonyOS 视频承载方式：系统画中画与应用内弹窗，切换后在下一次 play() 时生效。
  ///
  /// HarmonyOS video presentation mode; the change applies to the next play().
  Widget buildModeSection(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return DemoSection(
      title: '视频承载方式',
      description: 'HarmonyOS 视频同时支持系统画中画与应用内弹窗；切换后在下一次 play() 时生效。',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SegmentedButton<FlPiPPresentationMode>(
            segments: const <ButtonSegment<FlPiPPresentationMode>>[
              ButtonSegment<FlPiPPresentationMode>(value: FlPiPPresentationMode.systemPip, label: Text('系统画中画')),
              ButtonSegment<FlPiPPresentationMode>(value: FlPiPPresentationMode.overlay, label: Text('应用内弹窗')),
            ],
            selected: <FlPiPPresentationMode>{controller.mode},
            onSelectionChanged: (Set<FlPiPPresentationMode> selection) => controller.update(() {
              controller.mode = selection.first;
            }),
          ),
          const SizedBox(height: 8),
          Text(
            controller.mode == FlPiPPresentationMode.systemPip
                ? '系统画中画：跨应用展示，只用宽高比，窗口大小与位置由系统管理。'
                : '应用内弹窗：只在 App 前台可见，使用与 Android 一致的自定义控制面板。',
            style: theme.textTheme.bodySmall,
          ),
        ],
      ),
    );
  }

  /// 视频：来源、窗口宽高（物理像素）、圆角与控制面板。
  ///
  /// Video: source, window size in physical pixels, corner radius and control panel.
  Widget buildVideoSection(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final double pixelRatio = MediaQuery.devicePixelRatioOf(context);
    return DemoSection(
      title: '推送视频',
      description: isIOS
          ? 'FlPiPVideo.play() 使用 AVPlayerLayer 系统画中画；App 内不显示内联视频层（原生固定为 0.01pt）。'
                '网络视频会先用本地占位媒体启动画中画，首帧到达后在画中画窗口内加载。'
          : (isHarmonyOS
                ? 'HarmonyOS 系统画中画只用宽高比（aspectRatio），不自定义时跟随视频原始比例，'
                      '窗口大小与位置由系统管理；应用内弹窗使用 window 的宽高与位置，画面等比缩放不拉伸。'
                : 'Android 使用 WindowManager 系统弹窗 + MediaPlayer；window 的宽高与位置均为物理像素。'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text('视频来源 FlPiPVideoSource', style: theme.textTheme.titleSmall),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: DemoVideoSource.values
                .map(
                  (DemoVideoSource source) => ChoiceChip(
                    label: Text(videoSourceLabel(source)),
                    selected: controller.videoSource == source,
                    onSelected: (bool selected) {
                      if (!selected) return;
                      controller.update(() {
                        controller.videoSource = source;
                      });
                    },
                  ),
                )
                .toList(),
          ),
          if (controller.videoSource == DemoVideoSource.url)
            TextField(
              controller: controller.urlController,
              decoration: const InputDecoration(labelText: '视频 URL'),
            ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: controller.mediaLoop,
            onChanged: (bool value) => controller.update(() {
              controller.mediaLoop = value;
            }),
            title: const Text('循环播放 loop'),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: controller.mediaMuted,
            onChanged: (bool value) => controller.update(() {
              controller.mediaMuted = value;
            }),
            title: const Text('静音 muted'),
          ),
          if (systemPipWithoutControls)
            buildVideoAspectRatioControls(theme)
          else ...<Widget>[
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: controller.useCustomVideoWindow,
              onChanged: (bool value) => controller.update(() {
                controller.useCustomVideoWindow = value;
              }),
              title: const Text('自定义视频控件宽高与位置 window'),
              subtitle: Text(
                '页面按逻辑像素调整，传给原生时乘以 devicePixelRatio（当前 $pixelRatio），'
                '原生收到的是物理像素；传入后视频画面宽或高撑满控件并保持比例。',
              ),
            ),
            if (controller.useCustomVideoWindow) ...<Widget>[
              buildSlider(
                theme,
                label:
                    '宽度：${controller.videoWidth.toStringAsFixed(0)} 逻辑像素 → '
                    '${(controller.videoWidth * pixelRatio).toStringAsFixed(0)} px',
                value: controller.videoWidth,
                min: 100,
                max: 800,
                onChanged: (double value) => controller.update(() {
                  controller.videoWidth = value;
                }),
              ),
              buildSlider(
                theme,
                label:
                    '高度：${controller.videoHeight.toStringAsFixed(0)} 逻辑像素 → '
                    '${(controller.videoHeight * pixelRatio).toStringAsFixed(0)} px',
                value: controller.videoHeight,
                min: 100,
                max: 800,
                onChanged: (double value) => controller.update(() {
                  controller.videoHeight = value;
                }),
              ),
              buildSlider(
                theme,
                label:
                    '左边距 left：${controller.videoLeft.toStringAsFixed(0)} 逻辑像素 → '
                    '${(controller.videoLeft * pixelRatio).toStringAsFixed(0)} px',
                value: controller.videoLeft,
                min: 0,
                max: 400,
                onChanged: (double value) => controller.update(() {
                  controller.videoLeft = value;
                }),
              ),
              buildSlider(
                theme,
                label:
                    '上边距 top：${controller.videoTop.toStringAsFixed(0)} 逻辑像素 → '
                    '${(controller.videoTop * pixelRatio).toStringAsFixed(0)} px',
                value: controller.videoTop,
                min: 0,
                max: 800,
                onChanged: (double value) => controller.update(() {
                  controller.videoTop = value;
                }),
              ),
            ],
          ],
          buildCornerRadiusControl(theme),
          buildControlSwitches(theme),
          const SizedBox(height: 8),
          DemoButton(text: '播放视频 FlPiPVideo.play()', primary: true, onPressed: () => controller.playVideo(context)),
          const Divider(),
          DemoButton(
            text: '暂停 pause()',
            onPressed: () => controller.record('pause()', () => FlPiPVideo.instance.pause()),
          ),
          const SizedBox(height: 8),
          DemoButton(
            text: '恢复播放 resume()',
            onPressed: () => controller.record('resume()', () => FlPiPVideo.instance.resume()),
          ),
          const SizedBox(height: 8),
          DemoButton(
            text: '停止并回到开头 stopPlayback()',
            onPressed: () => controller.record('stopPlayback()', () => FlPiPVideo.instance.stopPlayback()),
          ),
          const SizedBox(height: 8),
          DemoButton(text: '设置循环 setLooping()', onPressed: controller.setLooping),
          const SizedBox(height: 8),
          Text('跳转位置：${controller.mediaSeekSeconds.toStringAsFixed(1)} 秒', style: theme.textTheme.bodySmall),
          Slider(
            value: controller.mediaSeekSeconds,
            min: 0,
            max: 120,
            divisions: 120,
            onChanged: (double value) => controller.update(() {
              controller.mediaSeekSeconds = value;
            }),
          ),
          DemoButton(text: '跳转到指定位置 seek()', onPressed: controller.seekAbsolute),
          Text('播放速度：${controller.playbackSpeed.toStringAsFixed(2)}x（范围 0.25 ~ 4.0）', style: theme.textTheme.bodySmall),
          Slider(
            value: controller.playbackSpeed,
            min: 0.25,
            max: 4.0,
            divisions: 15,
            label: '${controller.playbackSpeed.toStringAsFixed(2)}x',
            onChanged: controller.setPlaybackSpeed,
          ),
          Text('音量：${controller.mediaVolume.toStringAsFixed(2)}', style: theme.textTheme.bodySmall),
          Slider(
            value: controller.mediaVolume,
            min: 0.0,
            max: 1.0,
            divisions: 10,
            label: controller.mediaVolume.toStringAsFixed(2),
            onChanged: controller.setMediaVolume,
          ),
        ],
      ),
    );
  }

  /// HarmonyOS 系统画中画：只使用宽高比，未自定义时跟随视频原始比例；不展示位置与宽高。
  ///
  /// HarmonyOS system PiP: only the aspect ratio is used; it follows the video when disabled, so
  /// no window size or offsets are shown.
  Widget buildVideoAspectRatioControls(ThemeData theme) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: <Widget>[
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        value: controller.useVideoAspectRatio,
        onChanged: (bool value) => controller.update(() {
          controller.useVideoAspectRatio = value;
        }),
        title: const Text('自定义系统画中画宽高比 aspectRatio'),
        subtitle: const Text('关闭时跟随视频原始宽高比；开启后窗口按所选比例展示，实际大小由系统决定。'),
      ),
      if (controller.useVideoAspectRatio) ...<Widget>[
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: DemoController.aspectRatios
              .map(
                (FlPiPAspectRatio ratio) => ChoiceChip(
                  label: Text(ratioLabel(ratio)),
                  selected: controller.videoAspectRatio == ratio,
                  onSelected: (bool selected) {
                    if (selected) {
                      controller.update(() {
                        controller.videoAspectRatio = ratio;
                      });
                    }
                  },
                ),
              )
              .toList(),
        ),
        const SizedBox(height: 8),
        DemoInfoRow(
          label: '系统是否支持',
          value: '${controller.videoAspectRatio.isSupported}',
          valueColor: controller.videoAspectRatio.isSupported ? null : theme.colorScheme.error,
        ),
      ],
    ],
  );

  /// 视频窗口状态、关闭入口和原生事件。
  /// Video window status, the close entry and native events.
  Widget buildStatusSection(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return DemoSection(
      title: '视频窗口状态',
      description: '同一时间只允许一个视频窗口。',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          DemoButton(text: '关闭视频窗口 stop()', onPressed: controller.stopVideo),
          const SizedBox(height: 8),
          Row(
            children: <Widget>[
              Expanded(
                child: DemoButton(
                  text: '查询状态 status',
                  onPressed: () => controller.record('status', () => FlPiPVideo.instance.status),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: DemoButton(text: '是否激活 isActive', onPressed: controller.checkVideoActive),
              ),
            ],
          ),
          const Divider(),
          Text('原生视频事件', style: theme.textTheme.titleSmall),
          if (controller.videoEvents.isEmpty)
            Text('暂无事件', style: theme.textTheme.bodySmall)
          else
            ...controller.videoEvents
                .take(6)
                .map(
                  (FlPiPVideoEvent event) => Text(
                    '${event.event} ${event.action?.name ?? ''} '
                    '${event.positionMs ?? ''}/${event.durationMs ?? ''}',
                    style: theme.textTheme.bodySmall,
                  ),
                ),
        ],
      ),
    );
  }

  String videoSourceLabel(DemoVideoSource source) => switch (source) {
    DemoVideoSource.landscape => '横屏 h.mp4',
    DemoVideoSource.portrait => '竖屏 v.mp4',
    DemoVideoSource.url => '远程 URL',
  };

  Widget buildSlider(
    ThemeData theme, {
    required String label,
    required double value,
    required double min,
    required double max,
    required ValueChanged<double> onChanged,
  }) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: <Widget>[
      Text(label, style: theme.textTheme.bodySmall),
      Slider(value: value, min: min, max: max, onChanged: (double next) => onChanged(next)),
    ],
  );

  /// 控制面板开关：Android 全量支持；iOS 的面板由系统管理，无法隐藏；HarmonyOS 系统画中画
  /// 没有控件，应用内弹窗与 Android 一致。
  ///
  /// Control switches: Android supports all of them, iOS manages the panel itself, HarmonyOS
  /// has no control in the system PiP and behaves like Android in the in-app overlay.
  Widget buildControlSwitches(ThemeData theme) {
    if (systemPipWithoutControls || isIOS) {
      return DemoInfoRow(
        label: '控制面板',
        value: systemPipWithoutControls ? 'HarmonyOS 系统画中画不支持任何控件的隐藏或开启；切换到应用内弹窗后生效' : 'iOS 系统画中画的控制面板由系统管理，会自动隐藏，无法关闭',
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        controlSwitch('显示控制面板', controller.controlsEnabled, (bool value) => controller.controlsEnabled = value),
        controlSwitch('播放/暂停按钮', controller.showPlayPause, (bool value) => controller.showPlayPause = value),
        controlSwitch('进度条', controller.showProgress, (bool value) => controller.showProgress = value),
        controlSwitch('关闭按钮', controller.showClose, (bool value) => controller.showClose = value),
        controlSwitch('允许拖动', controller.allowDrag, (bool value) => controller.allowDrag = value),
        controlSwitch('自动隐藏', controller.autoHide, (bool value) => controller.autoHide = value),
      ],
    );
  }

  /// Android 与 HarmonyOS 应用内弹窗支持 `cornerRadius`，iOS 与 HarmonyOS 系统画中画的圆角由系统决定。
  ///
  /// Android and the HarmonyOS overlay apply `cornerRadius`; the system windows decide their own.
  Widget buildCornerRadiusControl(ThemeData theme) {
    if (isIOS || systemPipWithoutControls) {
      return const DemoInfoRow(label: '窗口圆角', value: '由系统画中画窗口决定，cornerRadius 不生效');
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text('窗口圆角：${controller.mediaCornerRadius.toStringAsFixed(0)} dp', style: theme.textTheme.bodySmall),
        Slider(
          value: controller.mediaCornerRadius,
          min: 0,
          max: 32,
          divisions: 32,
          label: '${controller.mediaCornerRadius.toStringAsFixed(0)} dp',
          onChanged: (double value) => controller.update(() {
            controller.mediaCornerRadius = value;
          }),
        ),
      ],
    );
  }

  Widget controlSwitch(String label, bool value, void Function(bool value) onChanged) => SwitchListTile(
    contentPadding: EdgeInsets.zero,
    dense: true,
    title: Text(label),
    value: value,
    onChanged: (bool selected) => controller.update(() {
      onChanged(selected);
    }),
  );
}
