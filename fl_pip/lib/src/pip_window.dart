part of 'package:fl_pip/fl_pip.dart';

/// 引擎与视频共用的唯一平台通道。 / The single platform channel shared by the engine and the video.
const MethodChannel _channel = MethodChannel('fl_pip');

/// 原生窗口/视频控件的尺寸与位置。
///
/// **所有字段的单位都是物理像素（device pixels / px）**，不是 Flutter 逻辑像素、不是 dp，
/// 也不是 HarmonyOS 的 vp。请用 `MediaQuery.devicePixelRatioOf(context)` 把逻辑尺寸换算成
/// 物理像素，例如 `360 * devicePixelRatio`。
///
/// - [width] / [height]：控件或窗口的宽高。视频播放传入后，三端原生会把视频控件设置成该
///   宽高，视频画面自适应填充（保持视频原始宽高比，宽或高撑满控件）。HarmonyOS 系统画中画
///   不使用这两个值，改用 `aspectRatio`；iOS 系统画中画只用它决定窗口比例（实际大小与位置由
///   系统管理），视频的内联预览在 iOS 上固定隐藏。
/// - [top] / [left]：窗口左上角相对屏幕的偏移，用于定义视频弹窗和新引擎窗口的位置。
///   系统画中画的窗口位置由系统管理，HarmonyOS 与 iOS 的系统画中画会忽略这两个值。
///
/// [FlPiP.present] 与 [FlPiPVideo.play] 共用本类；两者都只使用当前平台的那一份参数。
///
/// The size and position of a native window or video view.
///
/// **Every field is expressed in physical pixels (device pixels / px)**, not Flutter logical
/// pixels, not dp and not HarmonyOS vp. Multiply the logical size by
/// `MediaQuery.devicePixelRatioOf(context)` before passing it here.
@immutable
class FlPiPWindow {
  const FlPiPWindow({required this.width, required this.height, this.top = 0, this.left = 0});

  /// 宽度，单位物理像素（px）。HarmonyOS 系统画中画不使用该值。
  ///
  /// Width in physical pixels; ignored by the HarmonyOS system PiP window.
  final double width;

  /// 高度，单位物理像素（px）。HarmonyOS 系统画中画不使用该值。
  ///
  /// Height in physical pixels; ignored by the HarmonyOS system PiP window.
  final double height;

  /// 顶部偏移，单位物理像素（px）。系统画中画忽略该值。
  ///
  /// Top offset in physical pixels; ignored by the system PiP window.
  final double top;

  /// 左侧偏移，单位物理像素（px）。系统画中画忽略该值。
  ///
  /// Left offset in physical pixels; ignored by the system PiP window.
  final double left;

  /// 转换为原生参数表。 / Converts to the native argument map.
  Map<String, Object?> toMap() => <String, Object?>{'width': width, 'height': height, 'top': top, 'left': left};

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is FlPiPWindow && other.width == width && other.height == height && other.top == top && other.left == left;

  @override
  int get hashCode => Object.hash(width, height, top, left);

  @override
  String toString() => 'FlPiPWindow(width: $width, height: $height, top: $top, left: $left)';
}
