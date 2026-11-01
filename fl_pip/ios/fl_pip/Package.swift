// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "fl_pip",
    platforms: [
        .iOS("15.0")
    ],
    products: [
        .library(name: "fl-pip", targets: ["fl_pip"])
    ],
    dependencies: [
        .package(name: "FlutterFramework", path: "../FlutterFramework"),
        // Flutter 工具会把插件之间的相对依赖改写成同目录下的符号链接（例如
        // ../fl_multi_engine-0.0.1），因此这里必须写成 ../<插件名>。
        // The Flutter tool rewrites plugin-to-plugin dependencies to the sibling symlink,
        // so the path must be ../<plugin name>.
        .package(name: "fl_multi_engine", path: "../fl_multi_engine")
    ],
    targets: [
        .target(
            name: "fl_pip",
            dependencies: [
                .product(name: "FlutterFramework", package: "FlutterFramework"),
                .product(name: "fl-multi-engine", package: "fl_multi_engine")
            ],
            resources: [
                .process("PrivacyInfo.xcprivacy")
            ]
        )
    ]
)
