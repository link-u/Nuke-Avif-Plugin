//
//  Decoder.swift
//  Nuke-Avif-Plugin
//
//  Created by murakami on 2021/05/27.
//

import Foundation
import Accelerate
import Nuke
import libavif
import UIKit

public enum AvifDecoderError: Error {
    case unknownError
    case underlyingError(Error)
}

public extension AssetType {
    static let avif: AssetType = "avif"
}

public struct AvifImageDecoder: ImageDecoding {
    /// When `true` (default), YUV400 / 8-bit / no-alpha AVIF is decoded as DeviceGray 8bpp.
    /// Set to `false` to keep the legacy YUV→ARGB conversion path for those images.
    public static var yuv400DeviceGrayDecodingEnabled: Bool {
        get { yuv400DeviceGrayFlag.value }
        set { yuv400DeviceGrayFlag.value = newValue }
    }

    private static let yuv400DeviceGrayFlag = LockedFlag(true)

    public func decode(_ data: Data) throws -> ImageContainer {
        var rawData = avifROData(data: data.withUnsafeBytes { $0.bindMemory(to: UInt8.self).baseAddress }, size: data.count)
        let decoder = avifDecoderCreate()
        defer { avifDecoderDestroy(decoder) }
        let decodeResult = avifDecoderParse(decoder, &rawData)
        guard decodeResult == AVIF_RESULT_OK else {
            print("Failed to decode image: \(String(describing: avifResultToString(decodeResult)))")
            throw AvifDecoderError.unknownError
        }
        
        let nextImageResult = avifDecoderNextImage(decoder)
        guard nextImageResult == AVIF_RESULT_OK else {
            print("Failed to decode image: \(String(describing: avifResultToString(decodeResult)))")
            throw AvifDecoderError.unknownError
        }
        
        guard let decodedImage = decoder?.pointee.image else { throw AvifDecoderError.unknownError }
        let alphaPresent = decoder?.pointee.alphaPresent == AVIF_TRUE
        //let imageRef = avifImageUsesU16(decodedImage) != 0 ? createCGImageU16(avif: decodedImage.pointee) : createCGImageU8(avif: decodedImage.pointee)
        do {
            let imageRef = try createCGImage8(avif: &decodedImage.pointee, alphaPresent: alphaPresent)
            let image = UIImage(cgImage: imageRef, scale: 1, orientation: .up)
            return .init(image: image, type: .avif, isPreview: false, data: data, userInfo: [:])
        } catch let e {
            throw AvifDecoderError.underlyingError(e)
        }
    }
    
    private func createCGImage8(avif: inout avifImage, alphaPresent: Bool) throws -> CGImage {
        if Self.yuv400DeviceGrayDecodingEnabled {
            let eligibility = YUV400GrayscaleEligibility(
                yuvFormat: avif.yuvFormat,
                depth: avif.depth,
                alphaPresent: alphaPresent,
                alphaPlaneIsNull: avif.alphaPlane == nil
            )
            if isEligibleForYUV400GrayscaleDecoding(eligibility) {
                return try createDeviceGrayCGImage8(from: avif)
            }
        }

        let characteristics = try extractCharacteristics8(avif: &avif)
        let (buffers, cbcrDisposers) = extract8(avif: avif, chromaShift: (x: Int(characteristics.reformatState.formatInfo.chromaShiftX), y: Int(characteristics.reformatState.formatInfo.chromaShiftY)), pixelRange: characteristics.pixelRange)
        var yp = buffers.yp
        var cb = buffers.cb
        var cr = buffers.cr
        defer { cbcrDisposers.forEach { $0() } }
        
        let convertedBuffer = try converter8(avif: avif, yp: &yp, cb: &cb, cr: &cr, characteristics: characteristics)
        
        return try CGImage.create(from: avif, characteristics: characteristics, buffer: convertedBuffer)
    }
}

public extension AvifImageDecoder {
    static func enable() {
        Nuke.ImageDecoderRegistry.shared.register { context in
            guard context.isCompleted, context.data.isAvifData else { return nil }
            return AvifImageDecoder()
        }
    }
}

public extension Data {
    var isAvifData: Bool {
        return withUnsafeBytes { bytes in
            var roData = avifROData(data: bytes.bindMemory(to: UInt8.self).baseAddress, size: count)
            return avifPeekCompatibleFileType(&roData) == AVIF_TRUE
        }
    }
}

/// Thread-safe Bool box for process-wide opt-out flags (Swift 6 concurrency).
private final class LockedFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: Bool

    init(_ initial: Bool) {
        stored = initial
    }

    var value: Bool {
        get {
            lock.lock()
            defer { lock.unlock() }
            return stored
        }
        set {
            lock.lock()
            defer { lock.unlock() }
            stored = newValue
        }
    }
}
