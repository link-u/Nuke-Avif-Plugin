//
//  YUV400Grayscale.swift
//  Nuke-Avif-Plugin
//
//  YUV400 / 8bit / no-alpha → DeviceGray 8bpp CGImage path.
//

import Accelerate
import CoreGraphics
import Foundation
import libavif

/// Inputs for YUV400 DeviceGray eligibility (pure / testable).
struct YUV400GrayscaleEligibility {
    let yuvFormat: avifPixelFormat
    let depth: UInt32
    let alphaPresent: Bool
    let alphaPlaneIsNull: Bool
    let transformFlags: UInt32
}

/// Returns true only when all conditions hold:
/// YUV400, 8-bit depth, alphaPresent == false, alphaPlane == NULL, no transforms.
func isEligibleForYUV400GrayscaleDecoding(_ input: YUV400GrayscaleEligibility) -> Bool {
    input.yuvFormat == AVIF_PIXEL_FORMAT_YUV400
        && input.depth == 8
        && input.alphaPresent == false
        && input.alphaPlaneIsNull
        && input.transformFlags == AVIF_TRANSFORM_NONE.rawValue
}

/// Limited-range Y (studio swing) → full-range 8-bit gray.
/// `v = ((Int(y) - 16) * 255 + 109) / 219`, then clamp to 0...255.
func expandLimitedRangeYToGray8(_ y: UInt8) -> UInt8 {
    let v = ((Int(y) - 16) * 255 + 109) / 219
    return UInt8(min(255, max(0, v)))
}

/// 256-entry LUT for limited-range (studio swing) → full-range 8-bit expansion.
/// Built from `expandLimitedRangeYToGray8` so the vImage path matches the scalar
/// reference bit-exactly. Also shared with the limited-range alpha-plane
/// expansion in `BufferConversion.swift`.
let limitedRangeToFull8Table: [UInt8] = (UInt8.min...UInt8.max).map(expandLimitedRangeYToGray8)

enum YUV400GrayscaleError: Error {
    case missingYPlane
    case conversionFailed(vImage_Error)
    case dataProviderCreationFailed
    case cgImageCreationFailed
}

/// Copies the Y plane into an owned contiguous buffer (width bytes per row),
/// applying limited-range expansion when needed, then builds a monochrome CGImage.
/// The copy/expansion runs as a single vImage pass (256-entry LUT for limited
/// range, plain buffer copy for full range) instead of a scalar per-pixel loop.
/// Color space uses CICP (`createColorSpaceMonochrome`); on failure falls back to DeviceGray.
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

    var srcBuffer = vImage_Buffer(data: UnsafeMutableRawPointer(yPlane),
                                  height: vImagePixelCount(height),
                                  width: vImagePixelCount(width),
                                  rowBytes: yRowBytes)
    var dstBuffer = vImage_Buffer(data: UnsafeMutableRawPointer(owned),
                                  height: vImagePixelCount(height),
                                  width: vImagePixelCount(width),
                                  rowBytes: width)

    let conversionError: vImage_Error
    if isLimited {
        conversionError = limitedRangeToFull8Table.withUnsafeBufferPointer { table in
            guard let tablePointer = table.baseAddress else {
                return kvImageNullPointerArgument
            }
            return vImageTableLookUp_Planar8(&srcBuffer, &dstBuffer, tablePointer, vImage_Flags(kvImageNoFlags))
        }
    } else {
        conversionError = vImageCopyBuffer(&srcBuffer, &dstBuffer, MemoryLayout<UInt8>.size, vImage_Flags(kvImageNoFlags))
    }
    guard conversionError == kvImageNoError else {
        owned.deallocate()
        throw YUV400GrayscaleError.conversionFailed(conversionError)
    }

    let data = Data(bytesNoCopy: owned, count: byteCount, deallocator: .custom { pointer, _ in
        pointer.deallocate()
    })

    guard let provider = CGDataProvider(data: data as CFData) else {
        throw YUV400GrayscaleError.dataProviderCreationFailed
    }

    let colorSpace: CGColorSpace
    do {
        colorSpace = try createColorSpaceMonochrome(
            colorPrimaries: avif.colorPrimaries,
            transferCharacteristics: avif.transferCharacteristics
        )
    } catch {
        colorSpace = CGColorSpaceCreateDeviceGray()
    }

    guard let image = CGImage(
        width: width,
        height: height,
        bitsPerComponent: 8,
        bitsPerPixel: 8,
        bytesPerRow: width,
        space: colorSpace,
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
