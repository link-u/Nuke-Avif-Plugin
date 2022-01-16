//
//  Characteristics.swift
//  Nuke-Avif-Plugin
//
//  Created by murakami on 2021/11/26.
//

import Foundation
import libavif
import Accelerate

struct Characteristics {
    let monochrome: Bool
    let hasAlpha: Bool
    let alphaRange: avifRange
    let componentsPerPixel: Int
    let bytesPerRow: Int
    let matrix: vImage_YpCbCrToARGBMatrix
    let pixelRange: vImage_YpCbCrPixelRange
    let reformatState: avifReformatState
}

struct UnknownDepthError: Error {
    let depth: UInt32
}

func extractCharacteristics8(avif: inout avifImage) throws -> Characteristics {
    let monochrome = avif.yuvPlanes.1 == nil || avif.yuvPlanes.2 == nil
    let hasAlpha = avif.alphaPlane != nil
    let componentsPerPixel = (monochrome ? 1 : 3) + (hasAlpha ? 1 : 0)
    
    var emptyRGBImage = avifRGBImage(width: avif.width,
                                     height: avif.height,
                                     depth: avif.depth,
                                     format: AVIF_RGB_FORMAT_ARGB,
                                     chromaUpsampling: AVIF_CHROMA_UPSAMPLING_BILINEAR,
                                     ignoreAlpha: AVIF_FALSE,
                                     pixels: nil,
                                     rowBytes: 0)
    var state = avifReformatState()
    avifPrepareReformatState(&avif, &emptyRGBImage, &state)
    
    let matrix = vImage_YpCbCrToARGBMatrix(Yp: 1,
                                           Cr_R: 2 * (1 - state.kr),
                                           Cr_G: -2 * (1 - state.kr) * state.kr / state.kg,
                                           Cb_G: -2 * (1 - state.kb) * state.kb / state.kg,
                                           Cb_B: 2 * (1 - state.kb))
    
    let pixelRange = try { () -> vImage_YpCbCrPixelRange in
        switch (avif.depth, avif.yuvRange) {
        case (8, AVIF_RANGE_LIMITED):
            return .init(Yp_bias: 16, CbCr_bias: 128, YpRangeMax: 235, CbCrRangeMax: 240, YpMax: 255, YpMin: 0, CbCrMax: 255, CbCrMin: 0)
        case (8, AVIF_RANGE_FULL):
            return .init(Yp_bias: 0, CbCr_bias: 128, YpRangeMax: 255, CbCrRangeMax: 255, YpMax: 255, YpMin: 0, CbCrMax: 255, CbCrMin: 0)
        case (10, AVIF_RANGE_LIMITED):
            return .init(Yp_bias: 64, CbCr_bias: 512, YpRangeMax: 940, CbCrRangeMax: 960, YpMax: 1023, YpMin: 0, CbCrMax: 1023, CbCrMin: 0)
        case (10, AVIF_RANGE_FULL):
            return .init(Yp_bias: 0, CbCr_bias: 512, YpRangeMax: 1023, CbCrRangeMax: 1023, YpMax: 1023, YpMin: 0, CbCrMax: 1023, CbCrMin: 0)
        case (12, AVIF_RANGE_LIMITED):
            return .init(Yp_bias: 256, CbCr_bias: 2048, YpRangeMax: 3760, CbCrRangeMax: 3840, YpMax: 4095, YpMin: 0, CbCrMax: 4095, CbCrMin: 0)
        case (12, AVIF_RANGE_FULL):
            return .init(Yp_bias: 0, CbCr_bias: 2048, YpRangeMax: 4095, CbCrRangeMax: 4095, YpMax: 4095, YpMin: 0, CbCrMax: 4095, CbCrMin: 0)
        default:
            throw UnknownDepthError(depth: avif.depth)
        }
    }()
    
    return .init(monochrome: monochrome,
                 hasAlpha: hasAlpha,
                 alphaRange: avif.alphaRange,
                 componentsPerPixel: componentsPerPixel,
                 bytesPerRow: componentsPerPixel * MemoryLayout<UInt8>.size * Int(avif.width),
                 matrix: matrix,
                 pixelRange: pixelRange,
                 reformatState: state)
}
