import 'package:example/src/demo_controller.dart';
import 'package:example/src/fl_counter.dart';
import 'package:fl_pip/fl_pip.dart';
import 'package:flutter/material.dart';

/// A full-width button used by the demo pages.
class DemoButton extends StatelessWidget {
  const DemoButton({super.key, required this.text, this.onPressed, this.primary = false});

  /// The button label.
  final String text;

  /// Called when the button is tapped.
  final VoidCallback? onPressed;

  /// Whether the button uses the filled style.
  final bool primary;

  @override
  Widget build(BuildContext context) {
    final Widget label = Text(text, textAlign: TextAlign.center);
    return SizedBox(
      width: double.infinity,
      child: primary
          ? FilledButton(onPressed: onPressed, child: label)
          : FilledButton.tonal(onPressed: onPressed, child: label),
    );
  }
}

/// A bordered container with a title and an optional description.
class DemoSection extends StatelessWidget {
  const DemoSection({super.key, required this.title, required this.child, this.description});

  /// The section title.
  final String title;

  /// The optional section description.
  final String? description;

  /// The section content.
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: theme.dividerColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(title, style: theme.textTheme.titleMedium),
          if (description != null) ...<Widget>[
            const SizedBox(height: 4),
            Text(description!, style: theme.textTheme.bodySmall),
          ],
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}

/// A label/value row used to print API results and configuration values.
class DemoInfoRow extends StatelessWidget {
  const DemoInfoRow({super.key, required this.label, required this.value, this.valueColor});

  /// The label on the left.
  final String label;

  /// The value on the right.
  final String value;

  /// The optional color of [value].
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SizedBox(
            width: 172,
            child: Text(label, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
          ),
          Expanded(
            child: SelectableText(value, style: theme.textTheme.bodySmall?.copyWith(color: valueColor)),
          ),
        ],
      ),
    );
  }
}

/// A live timer shown by both the main page and the picture-in-picture page.
///
/// The timer keeps ticking as long as the Flutter engine that renders it is alive, which makes it
/// a simple way to verify that Android keeps the FlutterActivity and iOS keeps the
/// FlutterViewController running while picture-in-picture is active.
class PipTimer extends StatelessWidget {
  const PipTimer({super.key, this.style});

  /// The optional text style.
  final TextStyle? style;

  @override
  Widget build(BuildContext context) => FlCounter.up(
    builder: (Duration duration, bool isRunning, VoidCallback startTiming, VoidCallback stopTiming) {
      final String seconds = (duration.inSeconds % 60).toString().padLeft(2, '0');
      return Text('计时 ${duration.inMinutes}:$seconds', style: style);
    },
  );
}

/// 把画中画状态转换为中文。 / Maps the picture-in-picture status to Chinese.
String pipStatusLabel(FlPiPStatus status) => switch (status) {
  FlPiPStatus.enabled => '已开启',
  FlPiPStatus.disabled => '未开启',
  FlPiPStatus.unavailable => '不支持',
};

/// 把画中画状态转换为图标。 / Maps the picture-in-picture status to an icon.
IconData pipStatusIcon(FlPiPStatus status) => switch (status) {
  FlPiPStatus.enabled => Icons.picture_in_picture_alt,
  FlPiPStatus.disabled => Icons.picture_in_picture_alt_outlined,
  FlPiPStatus.unavailable => Icons.block,
};

/// 把画中画状态转换为主题色。 / Maps the picture-in-picture status to a theme color.
Color pipStatusColor(BuildContext context, FlPiPStatus status) => switch (status) {
  FlPiPStatus.enabled => Theme.of(context).colorScheme.primary,
  FlPiPStatus.disabled => Theme.of(context).colorScheme.onSurfaceVariant,
  FlPiPStatus.unavailable => Theme.of(context).colorScheme.error,
};

/// 画中画状态的说明文字。 / Explains the current picture-in-picture status.
String pipStatusDescription(FlPiPStatus status) => switch (status) {
  FlPiPStatus.enabled => '画中画窗口正在显示。',
  FlPiPStatus.disabled => '画中画未开启，点击 present() 即可启动。',
  FlPiPStatus.unavailable => '当前平台或设备不支持画中画，所有调用都会返回 false 或 null。',
};

/// 宽高比的展示名称。 / Human readable aspect ratio label.
String ratioLabel(FlPiPAspectRatio ratio) {
  if (ratio == const FlPiPAspectRatio.square()) return '1:1';
  if (ratio == const FlPiPAspectRatio.landscape()) return '16:9';
  if (ratio == const FlPiPAspectRatio.vertical()) return '9:16';
  if (ratio == const FlPiPAspectRatio.maxLandscape()) return '2.39:1（最大）';
  if (ratio == const FlPiPAspectRatio.maxVertical()) return '1:2.39（最大）';
  return '${ratio.numerator}:${ratio.denominator}';
}

/// 一条调用结果。
class DemoLogTile extends StatelessWidget {
  const DemoLogTile({super.key, required this.entry});

  /// The recorded call.
  final DemoLogEntry entry;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool isError = entry.result.startsWith('异常');
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(entry.api, style: theme.textTheme.labelMedium?.copyWith(fontFamily: 'monospace')),
          const SizedBox(height: 2),
          SelectableText(
            entry.result,
            style: theme.textTheme.bodySmall?.copyWith(
              color: isError ? theme.colorScheme.error : null,
              fontFamily: 'monospace',
            ),
          ),
        ],
      ),
    );
  }
}
