//
//  CGImageCreation.swift
//  Nuke-Avif-Plugin
//
//  Created by murakami on 2022/01/12.
//

import CoreGraphics
import Accelerate
import libavif

extension CGImage {
    static func create(from avif: avifImage, characteristics: Characteristics, buffer: vImage_Buffer) throws -> CGImage {
        guard let provider = CGDataProvider(dataInfo: nil, data: buffer.data, size: buffer.rowBytes * Int(buffer.height), releaseData: { info, data, size in data.deallocate() }) else { throw CGDataProviderCreationError() }
        let colorSpace = characteristics.monochrome ? try calcColorSpaceMonochrome(avif: avif) : try calcColorSpaceRGB(avif: avif)
        
        // Monochrome buffers are tightly packed (Mono8 / AlphaMono16).
        // Color buffers are always ARGB8888; when the image has no alpha the
        // leading byte is undefined and skipped via .noneSkipFirst, which lets
        // converter8 avoid a full ARGB8888 → RGB888 conversion pass.
        let bitsPerPixel = characteristics.monochrome ? characteristics.componentsPerPixel * 8 : 32
        let alphaInfo: CGImageAlphaInfo
        if characteristics.hasAlpha {
            alphaInfo = .first
        } else if characteristics.monochrome {
            alphaInfo = .none
        } else {
            alphaInfo = .noneSkipFirst
        }
        
        let imageRef = CGImage(width: avif.iWidth,
                               height: avif.iHeight,
                               bitsPerComponent: 8,
                               bitsPerPixel: bitsPerPixel,
                               bytesPerRow: buffer.rowBytes,
                               space: colorSpace,
                               bitmapInfo: .init(rawValue: alphaInfo.rawValue),
                               provider: provider,
                               decode: nil,
                               shouldInterpolate: false,
                               intent: .defaultIntent)
        
        guard let imageRef = imageRef else { throw CGImageCreationError() }
        return imageRef
    }
}

struct CGDataProviderCreationError: Error { }
struct CGImageCreationError: Error { }
