# Nuke-Avif-Plugin

[![Swift Package Manager compatible](https://img.shields.io/badge/Swift%20Package%20Manager-compatible-brightgreen.svg)](https://github.com/apple/swift-package-manager)

Nuke plugin for decoding AVIF images.

## Requirements

- iOS 15+
- Xcode 16+ (Swift 6)
- [Nuke](https://github.com/kean/Nuke) 13.x

## Installation

Add the package to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/link-u/Nuke-Avif-Plugin.git", from: "1.0.0"),
]
```

> **Note:** The formal `1.0.0` tag is not published yet. Until then, version resolution works with the pre-release tag `1.0.0-rc.2` (e.g. `exact: "1.0.0-rc.2"` or `from: "1.0.0-rc.2"`).

Then add `NukeAvifPlugin` to your target dependencies:

```swift
.target(
    name: "YourTarget",
    dependencies: [
        .product(name: "NukeAvifPlugin", package: "Nuke-Avif-Plugin"),
    ]
)
```

In Xcode: **File → Add Package Dependencies…** and enter the repository URL.

## Usage

Call `AvifImageDecoder.enable()` once at app launch (e.g. in `AppDelegate` or `@main` App init) before loading AVIF images:

```swift
import NukeAvifPlugin

AvifImageDecoder.enable()
```

After that, use Nuke as usual — AVIF URLs are decoded automatically via `ImageDecoderRegistry`.

To decode AVIF data manually:

```swift
let container = try AvifImageDecoder().decode(data)
```

### YUV400 DeviceGray decoding (1.1.0)

From 1.1.0, YUV400 / 8-bit / no-alpha AVIF is decoded as a DeviceGray 8bpp `CGImage` by default (instead of the legacy YUV→ARGB path).

To opt out and keep the previous conversion path:

```swift
AvifImageDecoder.yuv400DeviceGrayDecodingEnabled = false
```

## License

Nuke-Avif-Plugin is available under the MIT license. See the LICENSE file for more info.
