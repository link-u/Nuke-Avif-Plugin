// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "NukeAvifPlugin",
    platforms: [
        .iOS(.v15)
    ],
    products: [
        .library(name: "NukeAvifPlugin", targets: ["NukeAvifPlugin"]),
    ],
    dependencies: [
        .package(url: "https://github.com/kean/Nuke.git", "13.0.0"..<"14.0.0"),
        .package(url: "https://github.com/link-u/libavif-Xcode.git", .branch("dav1d_static_0.1.3"))
    ],
    targets: [
        .target(
            name: "NukeAvifPlugin",
            dependencies: [
                .product(name: "Nuke", package: "Nuke"),
                .product(name: "libavif", package: "libavif-Xcode")
            ],
            path: "Nuke-Avif-Plugin"
        ),
        .testTarget(
            name: "NukeAvifPluginTests",
            dependencies: ["NukeAvifPlugin", "Nuke"],
            path: "Tests/NukeAvifPluginTests",
            resources: [.process("Fixtures")]
        ),
    ]
)
