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

public extension ImageType {
    static var avif: ImageType {
        return .init(rawValue: "avif")
    }
}

public struct AvifImageDecoder: Nuke.ImageDecoding {
    public func decode(_ data: Data) -> ImageContainer? {
        var rawData = avifROData(data: data.withUnsafeBytes { $0.bindMemory(to: UInt8.self).baseAddress }, size: data.count)
        let decoder = avifDecoderCreate()
        defer { avifDecoderDestroy(decoder) }
        let decodeResult = avifDecoderParse(decoder, &rawData)
        guard decodeResult == AVIF_RESULT_OK else {
            print("Failed to decode image: \(String(describing: avifResultToString(decodeResult)))")
            return nil
        }
        
        let nextImageResult = avifDecoderNextImage(decoder)
        guard nextImageResult == AVIF_RESULT_OK else {
            print("Failed to decode image: \(String(describing: avifResultToString(decodeResult)))")
            return nil
        }
        
        guard let decodedImage = decoder?.pointee.image else { return nil }
        //let imageRef = avifImageUsesU16(decodedImage) != 0 ? createCGImageU16(avif: decodedImage.pointee) : createCGImageU8(avif: decodedImage.pointee)
        do {
            let imageRef = try createCGImage8(avif: &decodedImage.pointee)
            let image = UIImage(cgImage: imageRef, scale: 1, orientation: .up)
            return .init(image: image, type: .avif, isPreview: false, data: data, userInfo: [:])
        } catch let e {
            print(e.localizedDescription)
            return nil
        }
    }
    
    private func createCGImage8(avif: inout avifImage) throws -> CGImage {
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
            return context.data.isAvifData ? AvifImageDecoder() : nil
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
