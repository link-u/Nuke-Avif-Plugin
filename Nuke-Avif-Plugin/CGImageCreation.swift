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
        let colorSpace = try calcColorSpaceRGB(avif: avif)
        
        let imageRef = CGImage(width: avif.iWidth,
                               height: avif.iHeight,
                               bitsPerComponent: 8,
                               bitsPerPixel: characteristics.componentsPerPixel * 8,
                               bytesPerRow: characteristics.bytesPerRow,
                               space: colorSpace,
                               bitmapInfo: .init(rawValue: (characteristics.hasAlpha ? CGImageAlphaInfo.first : CGImageAlphaInfo.none).rawValue),
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
