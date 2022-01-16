//
//  TransferCharacteristics.swift
//  Nuke-Avif-Plugin
//
//  Created by murakami on 2021/06/01.
//

import Accelerate
import libavif

// CICP enums - https://www.itu.int/rec/T-REC-H.273-201612-I/en

func transferFunction(for characteristics: avifTransferCharacteristics) -> vImageTransferFunction? {
    let alpha: CGFloat = 1.099296826809442
    let beta: CGFloat = 0.018053968510807
    
    // R' = c0 * pow( c1 * R + c2, gamma ) + c3,    (R >= cutoff)
    // R' = c4 * R + c5
    
    switch characteristics {
    case AVIF_TRANSFER_CHARACTERISTICS_BT709, // 1
         AVIF_TRANSFER_CHARACTERISTICS_BT601, // 6
         AVIF_TRANSFER_CHARACTERISTICS_IEC61966, // 11, ignore R < -beta
         AVIF_TRANSFER_CHARACTERISTICS_BT1361, // 12, ignore R <= -gamma
         AVIF_TRANSFER_CHARACTERISTICS_BT2020_10BIT, // 14
         AVIF_TRANSFER_CHARACTERISTICS_BT2020_12BIT: // 15
        return .init(c0: alpha,
                     c1: 1,
                     c2: 0,
                     c3: -alpha + 1,
                     gamma: 0.45,
                     cutoff: beta,
                     c4: 4.5,
                     c5: 0)
    case AVIF_TRANSFER_CHARACTERISTICS_BT470M: // 4, assume gamma 2.2
        return .init(c0: 1,
                     c1: 1,
                     c2: 0,
                     c3: 0,
                     gamma: 1 / 2.2,
                     cutoff: -.infinity,
                     c4: 0,
                     c5: 0)
    case AVIF_TRANSFER_CHARACTERISTICS_BT470BG: // 5, assume gamma 2.8
        return .init(c0: 1,
                     c1: 1,
                     c2: 0,
                     c3: 0,
                     gamma: 1 / 2.8,
                     cutoff: -.infinity,
                     c4: 0,
                     c5: 0)
    case AVIF_TRANSFER_CHARACTERISTICS_SMPTE240: // 7
        return .init(c0: alpha,
                     c1: 1,
                     c2: 0,
                     c3: -alpha + 1,
                     gamma: 0.45,
                     cutoff: beta,
                     c4: 4,
                     c5: 0)
    case AVIF_TRANSFER_CHARACTERISTICS_LINEAR: // 8
        return .init(c0: 1,
                     c1: 1,
                     c2: 0,
                     c3: 0,
                     gamma: 1,
                     cutoff: 1,
                     c4: 1,
                     c5: 0)
    case AVIF_TRANSFER_CHARACTERISTICS_UNKNOWN, // 0
         AVIF_TRANSFER_CHARACTERISTICS_UNSPECIFIED, // 2
         AVIF_TRANSFER_CHARACTERISTICS_LOG100, // 9
         AVIF_TRANSFER_CHARACTERISTICS_LOG100_SQRT10, // 10
         AVIF_TRANSFER_CHARACTERISTICS_SMPTE2084, // 16
         AVIF_TRANSFER_CHARACTERISTICS_HLG: // 18
        // can't represent transfer function with vImageTransferFunction, so return nil
        return nil
    case AVIF_TRANSFER_CHARACTERISTICS_SRGB: // 13
        return .init(c0: alpha,
                     c1: 1,
                     c2: 0,
                     c3: -alpha + 1,
                     gamma: 1 / 2.4,
                     cutoff: beta,
                     c4: 12.92,
                     c5: 0)
    case AVIF_TRANSFER_CHARACTERISTICS_SMPTE428: // 17
        return .init(c0: 1,
                     c1: 48 / 52.37,
                     c2: 0,
                     c3: 0,
                     gamma: 1 / 2.6,
                     cutoff: -.infinity,
                     c4: 1,
                     c5: 0)
        
    default:
        return nil
    }
}

