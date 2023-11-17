// swift-tools-version:5.7
import PackageDescription

let package = Package(
    name: "Nuke-Avif-Plugin",
    platforms: [
        .iOS(.v14)
    ],
    products: [
        .library(name: "Nuke-Avif-Plugin", targets: ["Nuke-Avif-Plugin"]),
    ],
    dependencies: [
        .package(url: "https://github.com/kean/Nuke.git", from: "10.0.0"),
        .package(url: "https://github.com/SDWebImage/libavif-Xcode.git", exact: "0.10.1"),
    ],
    targets: [
        .target(
            name: "Nuke-Avif-Plugin",
            dependencies: [
                "Nuke",
                "libavif"
            ],
            path: "Nuke-Avif-Plugin"
        ),
    ]
)
