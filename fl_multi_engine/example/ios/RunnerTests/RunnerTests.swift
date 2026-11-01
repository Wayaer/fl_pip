import Flutter
import UIKit
import XCTest

@testable import fl_multi_engine

/// 简单校验插件的公开常量，避免引用已不存在的模板方法。
/// A tiny smoke test that checks the public constants of the plugin.
class RunnerTests: XCTestCase {
  func testMainEngineName() {
    XCTAssertEqual(FlMultiEnginePlugin.mainName, "main")
  }
}
