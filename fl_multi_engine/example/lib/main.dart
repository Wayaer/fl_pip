import 'dart:async';

import 'package:fl_multi_engine/fl_multi_engine.dart';
import 'package:flutter/material.dart';

/// Linux 没有自定义 entrypoint 能力，插件会通过 Dart 参数传入引擎名，这里手动分发。
/// Linux passes the entrypoint name as Dart arguments, so dispatch it here.
void main([List<String> args = const <String>[]]) {
  const String prefix = '--fl-multi-engine-entrypoint=';
  final String entrypoint = args.firstWhere(
    (String value) => value.startsWith(prefix),
    orElse: () => '',
  );
  if (entrypoint == '${prefix}engineMain') {
    engineMain(args);
    return;
  }
  runApp(const ExampleApp());
}

/// 新引擎的 Dart 入口，必须标注 @pragma('vm:entry-point')，保证 AOT 编译后仍然保留。
/// Entry point of the engines created by the example app.
@pragma('vm:entry-point')
void engineMain([List<String> args = const <String>[]]) =>
    runApp(EngineApp(arguments: args));

/// 主引擎页面：演示创建、销毁、查询和消息收发。
/// Main page demonstrating every fl_multi_engine API.
class ExampleApp extends StatefulWidget {
  const ExampleApp({super.key});

  @override
  State<ExampleApp> createState() => _ExampleAppState();
}

class _ExampleAppState extends State<ExampleApp> {
  final TextEditingController nameController = TextEditingController(
    text: 'engine_demo',
  );
  final TextEditingController entrypointController = TextEditingController(
    text: 'engineMain',
  );
  final TextEditingController argumentsController = TextEditingController();
  final TextEditingController targetController = TextEditingController(
    text: 'main',
  );
  final TextEditingController methodController = TextEditingController(
    text: 'message',
  );
  final TextEditingController valueKeyController = TextEditingController(
    text: 'text',
  );
  final TextEditingController valueController = TextEditingController(
    text: 'hello',
  );

  final List<String> logs = <String>[];
  final List<FlMultiEngineMessage> messages = <FlMultiEngineMessage>[];

  List<FlMultiEngineInfo> engines = <FlMultiEngineInfo>[];
  StreamSubscription<FlMultiEngineMessage>? messageSubscription;
  StreamSubscription<List<FlMultiEngineInfo>>? enginesSubscription;

  String? currentEngineName;

  @override
  void initState() {
    super.initState();
    messageSubscription = FlMultiEngine.instance.messages.listen((
      FlMultiEngineMessage message,
    ) {
      if (!mounted) return;
      setState(() => messages.insert(0, message));
    });
    // 原生创建/销毁引擎后会通知 Flutter，插件重新拉取列表后推送到这里。
    // Native changes are reported to Flutter, which re-fetches and emits the new list.
    enginesSubscription = FlMultiEngine.instance.engines.listen((
      List<FlMultiEngineInfo> list,
    ) {
      if (!mounted) return;
      setState(() => engines = list);
    });
    loadCurrentName();
    refresh();
  }

  @override
  void dispose() {
    messageSubscription?.cancel();
    enginesSubscription?.cancel();
    nameController.dispose();
    entrypointController.dispose();
    argumentsController.dispose();
    targetController.dispose();
    methodController.dispose();
    valueKeyController.dispose();
    valueController.dispose();
    super.dispose();
  }

  List<String> get entrypointArguments => argumentsController.text
      .split(',')
      .map((String value) => value.trim())
      .where((String value) => value.isNotEmpty)
      .toList(growable: false);

  Future<void> loadCurrentName() async {
    final String? name = await FlMultiEngine.instance.currentEngineName;
    if (!mounted) return;
    setState(() => currentEngineName = name);
  }

  Future<void> refresh() async {
    try {
      final List<FlMultiEngineInfo> list = await FlMultiEngine.instance.list();
      if (!mounted) return;
      setState(() {
        engines = list;
      });
    } catch (error) {
      record('刷新列表异常：$error');
    }
  }

  /// 统一执行一次 API 调用并把结果写入日志。
  /// Runs an API call and records its result or error.
  Future<void> run(String label, Future<void> Function() action) async {
    try {
      await action();
      record('$label 成功');
    } catch (error) {
      record('$label 异常：$error');
    } finally {
      await refresh();
    }
  }

  void record(String text) {
    if (!mounted) return;
    setState(() {
      logs.insert(0, text);
      if (logs.length > 12) logs.removeLast();
    });
  }

  Future<void> createHeadless() => run('创建引擎 create', () async {
    final String name = nameController.text.trim();
    final FlMultiEngineInfo? info = await FlMultiEngine.instance.create(
      name: name,
      entrypoint: entrypointController.text.trim(),
      arguments: entrypointArguments,
    );
    if (info == null) {
      record('创建失败：原生未返回引擎 ID');
      return;
    }
    // 创建成功后把消息目标指向新引擎，避免「发送消息」仍然发给 main。
    // Point the message target at the new engine so main can message it right away.
    targetController.text = info.name;
  });

  Future<void> destroy() => run('销毁引擎 destroy', () async {
    final bool destroyed = await FlMultiEngine.instance.destroy(
      nameController.text.trim(),
    );
    record('引擎已销毁：$destroyed');
  });

  Future<void> status() => run('查询状态 status', () async {
    final FlMultiEngineInfo? info = await FlMultiEngine.instance.status(
      nameController.text.trim(),
    );
    record('引擎状态：${info ?? '不存在'}');
  });

  Future<void> send() => run('发送消息 send', () async {
    final int delivered = await FlMultiEngine.instance.send(
      target: targetController.text.trim(),
      method: methodController.text.trim(),
      value: <String, Object?>{
        valueKeyController.text.trim(): valueController.text,
      },
    );
    record('消息投递数：$delivered');
  });

  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    home: Scaffold(
      appBar: AppBar(title: const Text('fl_multi_engine 示例')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          buildHeaderSection(context),
          buildEngineSection(context),
          buildMessageSection(context),
          buildLogSection(context),
        ],
      ),
    ),
  );

  /// 把引擎状态转换为中文。 / Maps the engine state to Chinese.
  String stateLabel(FlMultiEngineState state) => switch (state) {
    FlMultiEngineState.running => '运行中',
    FlMultiEngineState.disposed => '已销毁',
    FlMultiEngineState.failed => '创建失败',
  };

  Widget buildHeaderSection(BuildContext context) => _Section(
    title: '当前引擎',
    children: <Widget>[
      _InfoRow(label: 'currentEngineName', value: currentEngineName ?? '加载中'),
      _InfoRow(label: 'isSupported', value: '${FlMultiEngine.isSupported}'),
    ],
  );

  Widget buildEngineSection(BuildContext context) => _Section(
    title: '引擎管理',
    children: <Widget>[
      TextField(
        controller: nameController,
        decoration: const InputDecoration(labelText: '引擎名称 name'),
      ),
      TextField(
        controller: entrypointController,
        decoration: const InputDecoration(
          labelText: '入口函数 entrypoint（需 vm:entry-point）',
        ),
      ),
      TextField(
        controller: argumentsController,
        decoration: const InputDecoration(labelText: 'Dart 参数 arguments（逗号分隔）'),
      ),
      const SizedBox(height: 8),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: <Widget>[
          FilledButton(onPressed: createHeadless, child: const Text('创建引擎')),
          OutlinedButton(onPressed: destroy, child: const Text('销毁引擎')),
          OutlinedButton(onPressed: status, child: const Text('查询状态')),
          OutlinedButton(onPressed: refresh, child: const Text('刷新列表')),
        ],
      ),
      const Divider(),
      if (engines.isEmpty)
        const Text('暂无引擎')
      else
        ...engines.map(
          (FlMultiEngineInfo info) => ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: Icon(
              info.isMain ? Icons.home : Icons.widgets,
              color: info.state == FlMultiEngineState.running
                  ? Colors.green
                  : Colors.grey,
            ),
            title: Text(info.name),
            subtitle: Text(
              '${stateLabel(info.state)} · ${info.entrypoint} · ${info.createdAt}',
            ),
            onTap: () => setState(() => nameController.text = info.name),
          ),
        ),
    ],
  );

  Widget buildMessageSection(BuildContext context) => _Section(
    title: '消息',
    children: <Widget>[
      TextField(
        controller: targetController,
        decoration: const InputDecoration(labelText: '目标引擎 target'),
      ),
      TextField(
        controller: methodController,
        decoration: const InputDecoration(labelText: '方法名 method'),
      ),
      Row(
        children: <Widget>[
          Expanded(
            child: TextField(
              controller: valueKeyController,
              decoration: const InputDecoration(labelText: '数据键 value key'),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: valueController,
              decoration: const InputDecoration(labelText: '数据值 value'),
            ),
          ),
        ],
      ),
      const SizedBox(height: 8),
      FilledButton.tonal(onPressed: send, child: const Text('发送消息')),
      const Divider(),
      if (messages.isEmpty)
        const Text('暂无消息')
      else
        ...messages
            .take(5)
            .map(
              (FlMultiEngineMessage message) => Text(
                '${message.sender} → ${message.method}: ${message.value}',
              ),
            ),
    ],
  );

  Widget buildLogSection(BuildContext context) => _Section(
    title: '调用结果',
    children: <Widget>[
      if (logs.isEmpty)
        const Text('暂无调用，点击上方按钮开始')
      else
        ...logs.map((String log) => SelectableText(log)),
    ],
  );
}

/// 新引擎页面：展示自身名称，并可以给 main 发送消息、监听来自其他引擎的消息。
/// Page rendered by every engine created by the demo.
class EngineApp extends StatefulWidget {
  const EngineApp({super.key, this.arguments = const <String>[]});

  /// 创建引擎时传入的 Dart 参数。
  /// Entry point arguments passed to [FlMultiEngine.create].
  final List<String> arguments;

  @override
  State<EngineApp> createState() => _EngineAppState();
}

class _EngineAppState extends State<EngineApp> {
  String? name;
  final List<FlMultiEngineMessage> messages = <FlMultiEngineMessage>[];
  StreamSubscription<FlMultiEngineMessage>? subscription;

  @override
  void initState() {
    super.initState();
    load();
    subscription = FlMultiEngine.instance.messages.listen((
      FlMultiEngineMessage message,
    ) {
      if (!mounted) return;
      setState(() => messages.insert(0, message));
    });
  }

  @override
  void dispose() {
    subscription?.cancel();
    super.dispose();
  }

  Future<void> load() async {
    final String? current = await FlMultiEngine.instance.currentEngineName;
    if (!mounted) return;
    setState(() => name = current);
  }

  Future<void> sendToMain() async {
    final String? current = name;
    if (current == null) return;
    await FlMultiEngineBridge(current).send(
      target: kFlMultiEngineMainName,
      method: 'engine/hello',
      value: <String, Object?>{'from': current, 'arguments': widget.arguments},
    );
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    home: Scaffold(
      appBar: AppBar(title: Text('引擎：${name ?? '加载中'}')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          _InfoRow(label: 'currentEngineName', value: name ?? '加载中'),
          _InfoRow(label: 'arguments', value: widget.arguments.join(', ')),
          const SizedBox(height: 12),
          FilledButton(onPressed: sendToMain, child: const Text('发送消息给主引擎')),
          const SizedBox(height: 12),
          if (messages.isEmpty)
            const Text('暂无消息')
          else
            ...messages.map(
              (FlMultiEngineMessage message) => Text(
                '${message.sender} → ${message.method}: ${message.value}',
              ),
            ),
        ],
      ),
    ),
  );
}

/// 带标题的演示分组。
/// A titled demo section.
class _Section extends StatelessWidget {
  const _Section({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: theme.dividerColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(title, style: theme.textTheme.titleMedium),
          const SizedBox(height: 12),
          ...children,
        ],
      ),
    );
  }
}

/// 键值信息行。
/// A label/value row.
class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SizedBox(
            width: 150,
            child: Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Expanded(
            child: SelectableText(value, style: theme.textTheme.bodySmall),
          ),
        ],
      ),
    );
  }
}
