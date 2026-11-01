import 'dart:async';
import 'dart:math' as math;

import 'package:example/src/demo_widgets.dart';
import 'package:fl_pip/fl_pip.dart';
import 'package:flutter/material.dart';

/// 唯一的 `pipMain` 独立引擎中展示的精简页面。
///
/// Android 系统弹窗会把该引擎放进 `WindowManager` 悬浮窗，HarmonyOS 会把它挂到浮窗或系统画中画；
/// iOS 会把它渲染进系统画中画窗口。页面同时演示跨引擎消息收发与画中画状态监听。
///
/// The compact page rendered by the single `pipMain` engine.
class PiPHomePage extends StatefulWidget {
  const PiPHomePage({super.key});

  @override
  State<PiPHomePage> createState() => PiPHomePageState();
}

class PiPHomePageState extends State<PiPHomePage> {
  static const TextStyle caption = TextStyle(color: Colors.white70, fontSize: 11);

  final List<FlPiPMessage> messages = <FlPiPMessage>[];
  StreamSubscription<FlPiPMessage>? messageSubscription;

  /// 最近一次发送的送达数量（`1` 或 `0`），用于确认消息是否被投递到主引擎。
  ///
  /// Delivery count of the last send (`1` or `0`), used to confirm delivery to the main engine.
  int lastDelivered = 0;

  @override
  void initState() {
    super.initState();
    messageSubscription = FlPiP.instance.messages.listen((FlPiPMessage message) {
      if (!mounted) return;
      setState(() => messages.insert(0, message));
    });
  }

  @override
  void dispose() {
    messageSubscription?.cancel();
    super.dispose();
  }

  Future<void> sendToMain() async {
    final int delivered = await FlPiP.instance.send(
      'pip/message',
      arguments: <String, Object?>{'at': DateTime.now().toIso8601String()},
    );
    if (!mounted) return;
    setState(() => lastDelivered = delivered);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: const Color(0xFF111827),
    body: SafeArea(
      child: LayoutBuilder(
        // 窗口比内容高时把内容垂直居中，避免浮窗上下出现大片空白。
        // Center the content vertically so the overlay has no empty bands.
        builder: (BuildContext context, BoxConstraints constraints) => SingleChildScrollView(
          padding: const EdgeInsets.all(8),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: math.max(constraints.maxHeight - 16, 0.0)),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Icon(Icons.picture_in_picture_alt, size: 16, color: Colors.white70),
                      SizedBox(width: 6),
                      Text('pipMain 独立引擎', style: caption),
                    ],
                  ),
                  const SizedBox(height: 4),
                  const PipTimer(
                    style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 4),
                  FlPiPBuilder(
                    builder: (FlPiPStatusInfo? info) => Text(
                      '状态：${pipStatusLabel(info?.status ?? FlPiPStatus.disabled)} · '
                      'mode：${info?.mode?.value ?? '-'} · 引擎：${info?.hasEngine ?? false}',
                      style: caption,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text('消息数：${messages.length} · 已送达：$lastDelivered', style: caption, textAlign: TextAlign.center),
                  const SizedBox(height: 8),
                  FilledButton.tonal(onPressed: sendToMain, child: const Text('发送给主引擎')),
                  const SizedBox(height: 4),
                  FilledButton.tonal(onPressed: FlPiP.instance.dismiss, child: const Text('关闭画中画')),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
}
