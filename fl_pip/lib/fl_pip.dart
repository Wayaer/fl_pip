/// fl_pip 的公共 API 出口。
///
/// 三个实现文件都是本库的 part，公共类型直接从本库导出：
/// - `src/pip_engine.dart`：画中画引擎、状态、承载方式与参数；
/// - `src/pip_video.dart`：视频播放 API 与三端参数；
/// - `src/pip_window.dart`：引擎与视频共用的窗口尺寸/位置。
///
/// [FlMultiEngineInfo] 由 `fl_multi_engine` 提供，`present()` 直接返回该类型。
///
/// Public entry point of fl_pip. The implementation files are parts of this library.
library;

import 'dart:async';

import 'package:fl_multi_engine/fl_multi_engine.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

export 'package:fl_multi_engine/fl_multi_engine.dart';

part 'src/pip_engine.dart';
part 'src/pip_window.dart';
part 'src/pip_video.dart';
