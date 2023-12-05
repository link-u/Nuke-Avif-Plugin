// swift-tools-version:5.7
import PackageDescription

let package = Package(
    name: "Nuke-Avif-Plugin",
    platforms: [
        .iOS(.v11)
    ],
    products: [
        .library(name: "Nuke-Avif-Plugin", targets: ["Nuke-Avif-Plugin"]),
    ],
    dependencies: [
        .package(url: "https://github.com/kean/Nuke.git", from: "12.0.0"),
        .package(url: "git@github.com:link-u/libavif-Xcode.git", .branch("workaround/dav1d-static"))
    ],
    targets: [
        .target(
            name: "Nuke-Avif-Plugin",
            dependencies: [
                "Nuke",
                .product(name: "libavif", package: "libavif-Xcode")
            ],
            path: "Nuke-Avif-Plugin"
        ),
    ]
)
