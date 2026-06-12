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

Register the decoder when configuring Nuke:

```swift
import Nuke
import NukeAvifPlugin

ImageDecoderRegistry.shared.register(AvifImageDecoder())
```

## License

Nuke-Avif-Plugin is available under the MIT license. See the LICENSE file for more info.
