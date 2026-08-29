// swift-tools-version: 5.10

import PackageDescription

let package = Package(
    name: "Lang4SelfServerTemplate",
    platforms: [.macOS(.v14)],
    dependencies: [.package(path: "../..")],
    targets: [
        .executableTarget(
            name: "Lang4SelfServer",
            dependencies: [.product(name: "Lang4SelfCore", package: "Lang4Self")]
        )
    ]
)
