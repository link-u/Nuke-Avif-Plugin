// swift-tools-version:5.7
import PackageDescription

let package = Package(
    name: "NukeAvifPlugin",
    platforms: [
        .iOS(.v14)
    ],
    products: [
        .library(name: "NukeAvifPlugin", targets: ["NukeAvifPlugin"]),
    ],
    dependencies: [
        .package(url: "https://github.com/kean/Nuke.git", "12.0.0"..<"13.0.0"), // 12系までをサポートする
        .package(url: "git@github.com:link-u/libavif-Xcode.git", .branch("dav1d_static_0.1.1")) // タグで指定
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
    ]
)
