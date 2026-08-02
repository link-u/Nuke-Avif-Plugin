//
//  YUV400Grayscale.swift
//  Nuke-Avif-Plugin
//
//  YUV400 / 8bit / no-alpha → DeviceGray 8bpp CGImage path.
//

import CoreGraphics
import Foundation
import libavif

/// Inputs for YUV400 DeviceGray eligibility (pure / testable).
struct YUV400GrayscaleEligibility {
    let yuvFormat: avifPixelFormat
    let depth: UInt32
    let alphaPresent: Bool
    let alphaPlaneIsNull: Bool
}

/// Returns true only when all four conditions hold:
/// YUV400, 8-bit depth, alphaPresent == false, alphaPlane == NULL.
func isEligibleForYUV400GrayscaleDecoding(_ input: YUV400GrayscaleEligibility) -> Bool {
    input.yuvFormat == AVIF_PIXEL_FORMAT_YUV400
        && input.depth == 8
        && input.alphaPresent == false
        && input.alphaPlaneIsNull
}

/// Limited-range Y (studio swing) → full-range 8-bit gray.
/// `v = ((Int(y) - 16) * 255 + 109) / 219`, then clamp to 0...255.
func expandLimitedRangeYToGray8(_ y: UInt8) -> UInt8 {
    let v = ((Int(y) - 16) * 255 + 109) / 219
    return UInt8(min(255, max(0, v)))
}

enum YUV400GrayscaleError: Error {
    case missingYPlane
    case dataProviderCreationFailed
    case cgImageCreationFailed
}

/// Copies the Y plane into an owned contiguous buffer (width bytes per row),
/// applying limited-range expansion when needed, then builds a DeviceGray CGImage.
func createDeviceGrayCGImage8(from avif: avifImage) throws -> CGImage {
    guard let yPlane = avif.yuvPlanes.0 else {
        throw YUV400GrayscaleError.missingYPlane
    }

    let width = Int(avif.width)
    let height = Int(avif.height)
    let yRowBytes = Int(avif.yuvRowBytes.0)
    let isLimited = avif.yuvRange == AVIF_RANGE_LIMITED

    let byteCount = width * height
    let owned = UnsafeMutablePointer<UInt8>.allocate(capacity: byteCount)
    owned.initialize(repeating: 0, count: byteCount)

    for row in 0..<height {
        let src = yPlane.advanced(by: row * yRowBytes)
        let dst = owned.advanced(by: row * width)
        if isLimited {
            for x in 0..<width {
                dst[x] = expandLimitedRangeYToGray8(src[x])
            }
        } else {
            dst.update(from: src, count: width)
        }
    }

    let data = Data(bytesNoCopy: owned, count: byteCount, deallocator: .custom { pointer, _ in
        pointer.deallocate()
    })

    guard let provider = CGDataProvider(data: data as CFData) else {
        throw YUV400GrayscaleError.dataProviderCreationFailed
    }

    guard let image = CGImage(
        width: width,
        height: height,
        bitsPerComponent: 8,
        bitsPerPixel: 8,
        bytesPerRow: width,
        space: CGColorSpaceCreateDeviceGray(),
        bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue),
        provider: provider,
        decode: nil,
        shouldInterpolate: false,
        intent: .defaultIntent
    ) else {
        throw YUV400GrayscaleError.cgImageCreationFailed
    }

    return image
}
