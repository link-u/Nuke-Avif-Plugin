//
//  ColorSpace.swift
//  Nuke-Avif-Plugin
//
//  Created by murakami on 2022/01/12.
//

import CoreGraphics
import Accelerate
import libavif

func calcRGBPrimaries(colorPrimaries: avifColorPrimaries) -> vImageRGBPrimaries {
    var primaries = [Float](repeating: 0, count: 8)
    avifColorPrimariesGetValues(colorPrimaries, &primaries)
    return .init(red_x: primaries[0],
                 green_x: primaries[2],
                 blue_x: primaries[4],
                 white_x: primaries[6],
                 red_y: primaries[1],
                 green_y: primaries[3],
                 blue_y: primaries[5],
                 white_y: primaries[7])
}

struct ColorSpaceError: Error {
    let message: String
}

func createColorSpaceRGB(colorPrimaries: avifColorPrimaries, transferCharacteristics: avifTransferCharacteristics) throws -> CGColorSpace {
    var primaries = calcRGBPrimaries(colorPrimaries: colorPrimaries)
    guard var tf = transferFunction(for: transferCharacteristics) else { throw ColorSpaceError(message: "transfer function not available.") }
    var error = vImage_Error(0)
    
    let colorSpace = vImageCreateRGBColorSpaceWithPrimariesAndTransferFunction(&primaries,
                                                                               &tf,
                                                                               .defaultIntent,
                                                                               vImage_Flags(kvImagePrintDiagnosticsToConsole),
                                                                                     &error)
    
    guard let colorSpace = colorSpace, error != kvImageNoError else {
        throw ColorSpaceError(message: "color space creation failed.")
    }
    
    return colorSpace.takeRetainedValue()
}

let defaultColorSpace = CGColorSpaceCreateDeviceRGB()
func calcColorSpaceRGB(avif: avifImage) throws -> CGColorSpace {
    if avif.icc.data != nil && avif.icc.size > 0 {
        guard let iccData = CFDataCreateWithBytesNoCopy(kCFAllocatorDefault, avif.icc.data, avif.icc.size, kCFAllocatorNull) else { throw ColorSpaceError(message: "cfdata creation failed.") }
        guard let colorSpace = CGColorSpace(iccData: iccData) else { throw ColorSpaceError(message: "colorspace creation failed.") }
        return colorSpace
    }
    
    switch (avif.colorPrimaries, avif.transferCharacteristics) {
    case (AVIF_COLOR_PRIMARIES_UNKNOWN, AVIF_TRANSFER_CHARACTERISTICS_UNKNOWN),
        (AVIF_COLOR_PRIMARIES_UNKNOWN, AVIF_TRANSFER_CHARACTERISTICS_UNKNOWN),
        (AVIF_COLOR_PRIMARIES_UNKNOWN, AVIF_TRANSFER_CHARACTERISTICS_UNKNOWN),
        (AVIF_COLOR_PRIMARIES_UNKNOWN, AVIF_TRANSFER_CHARACTERISTICS_UNKNOWN):
        return defaultColorSpace
        
    case (AVIF_COLOR_PRIMARIES_BT709, AVIF_TRANSFER_CHARACTERISTICS_BT709):
        return CGColorSpace(name: CGColorSpace.itur_709)!
        
    case (AVIF_COLOR_PRIMARIES_BT709, AVIF_TRANSFER_CHARACTERISTICS_SRGB):
        return CGColorSpace(name: CGColorSpace.sRGB)!
        
    case (AVIF_COLOR_PRIMARIES_BT709, AVIF_TRANSFER_CHARACTERISTICS_LINEAR):
        return CGColorSpace(name: CGColorSpace.linearSRGB)!
        
    case (AVIF_COLOR_PRIMARIES_BT2020, AVIF_TRANSFER_CHARACTERISTICS_BT2020_10BIT),
        (AVIF_COLOR_PRIMARIES_BT2020, AVIF_TRANSFER_CHARACTERISTICS_BT2020_12BIT):
        return CGColorSpace(name: CGColorSpace.itur_2020)!
        
    case (AVIF_COLOR_PRIMARIES_SMPTE432, AVIF_TRANSFER_CHARACTERISTICS_SRGB):
        return CGColorSpace(name: CGColorSpace.displayP3)!
        
    case (AVIF_COLOR_PRIMARIES_SMPTE432, AVIF_TRANSFER_CHARACTERISTICS_HLG):
        if #available(iOS 12.6, *) {
            return CGColorSpace(name: CGColorSpace.displayP3_HLG)!
        } else {
            return defaultColorSpace
        }
        
    case (AVIF_COLOR_PRIMARIES_SMPTE432, AVIF_TRANSFER_CHARACTERISTICS_LINEAR):
        if #available(iOS 12.3, *) {
            return CGColorSpace(name: CGColorSpace.extendedLinearDisplayP3)!
        } else {
            return defaultColorSpace
        }
        
    default:
        return try createColorSpaceRGB(colorPrimaries: avif.colorPrimaries, transferCharacteristics: avif.transferCharacteristics)
    }
}
