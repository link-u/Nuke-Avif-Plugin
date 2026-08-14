//
//  BufferConversion.swift
//  Nuke-Avif-Plugin
//
//  Created by murakami on 2021/11/26.
//

import Foundation
import Accelerate
import libavif

func converter8(
    avif: avifImage,
    yp: UnsafePointer<vImage_Buffer>, cb: UnsafePointer<vImage_Buffer>, cr: UnsafePointer<vImage_Buffer>,
    characteristics: Characteristics
) throws -> vImage_Buffer {
    func argbBuffer() -> ImageBufferWithDisposables {
        // ARGB8888 working buffer (4 bytes per pixel, rowBytes = width * 4).
        // The subsequent vImage YpCbCr → ARGB conversion overwrites every pixel
        // (alpha is filled with the constant 255), so the buffer is intentionally
        // left uninitialized to avoid a redundant full-size memset pass.
        let byteCount = avif.iWidth * avif.iHeight * 4 * MemoryLayout<UInt8>.size
        
        let data = UnsafeMutableRawPointer.allocate(byteCount: byteCount, alignment: MemoryLayout<UInt8>.alignment)
        
        let buffer = vImage_Buffer(data: data, height: avif.vHeight, width: avif.vWidth, rowBytes: avif.iWidth * 4)
        return (buffer, [data.deallocate])
    }

    func generateConversionInfo(type: vImageYpCbCrType) throws -> vImage_YpCbCrToARGB {
        var matrix = characteristics.matrix
        var pixelRange = characteristics.pixelRange
        
        var conversionInfo = vImage_YpCbCrToARGB()
        try vImageTry(vImageConvert_YpCbCrToARGB_GenerateConversion(&matrix,
                                                                    &pixelRange,
                                                                    &conversionInfo,
                                                                    type,
                                                                    kvImageARGB8888,
                                                                    vImage_Flags(kvImageNoFlags)
                                                                   ), errorMessage: "Failed to setup conversion.")
        return conversionInfo
    }
    
    func yuv420_400() throws -> ImageBufferWithDisposables {
        var (argbBuffer, disposable) = argbBuffer()
        var permuteMap: [UInt8] = [0, 1, 2, 3]
        
        var conversionInfo = try generateConversionInfo(type: kvImage420Yp8_Cb8_Cr8)
        try vImageTry(vImageConvert_420Yp8_Cb8_Cr8ToARGB8888(yp,
                                                             cb,
                                                             cr,
                                                             &argbBuffer,
                                                             &conversionInfo,
                                                             &permuteMap,
                                                             255,
                                                             vImage_Flags(kvImageNoFlags)
                                                            ), errorMessage: "Failed to convert to ARGB8888.")
        
        return (argbBuffer, disposable)
    }
    
    func yuv444() throws -> ImageBufferWithDisposables {
        var (argbBuffer, disposable) = argbBuffer()
        var permuteMap: [UInt8] = [0, 1, 2, 3]
        
        let yuvBufferDataByteCount = avif.iWidth * avif.iHeight * 3 * MemoryLayout<UInt8>.size
        let yuvBufferData = UnsafeMutableRawPointer.allocate(byteCount: yuvBufferDataByteCount, alignment: MemoryLayout<UInt8>.alignment)
        defer { yuvBufferData.deallocate() }
        
        var yuvBuffer = vImage_Buffer(data: yuvBufferData, height: avif.vHeight, width: avif.vWidth, rowBytes: avif.iWidth * 3)
        
        try vImageTry(vImageConvert_Planar8toRGB888(cr,
                                                    yp,
                                                    cb,
                                                    &yuvBuffer,
                                                    vImage_Flags(kvImageNoFlags)
                                                   ), errorMessage: "Failed to composite kvImage444CrYpCb8.")
        
        var conversionInfo = try generateConversionInfo(type: kvImage444CrYpCb8)
        try vImageTry(vImageConvert_444CrYpCb8ToARGB8888(&yuvBuffer,
                                                         &argbBuffer,
                                                         &conversionInfo,
                                                         &permuteMap,
                                                         255,
                                                         vImage_Flags(kvImageNoFlags)
                                                        ), errorMessage: "Failed to convert to ARGB8888.")
        
        return (argbBuffer, disposable)
    }
    
    // yuv422: 色差は水平方向に2個一組
    func yuv422() throws -> ImageBufferWithDisposables {
        var (argbBuffer, disposable) = argbBuffer()
        let permuteMap: [UInt8] = [0, 1, 2, 3]
        
        let alignedWidth = (yp.pointee.width + 1) & (~1)
        let ypDiffBufferDataByteCount = alignedWidth / 2 * yp.pointee.height * UInt(MemoryLayout<UInt8>.size)
        
        
        // compose yp-cb differnce buffer
        let ypCbDiffBufferData = UnsafeMutableRawPointer.allocate(byteCount: Int(ypDiffBufferDataByteCount), alignment: MemoryLayout<UInt8>.alignment)
        let ypBufferData0 = UnsafeMutablePointer<UnsafeRawPointer?>.allocate(capacity: 1)
        ypBufferData0.initialize(to: yp.pointee.data)
        defer {
            ypCbDiffBufferData.deallocate()
            ypBufferData0.deinitialize(count: 1)
            ypBufferData0.deallocate()
        }
        
        var ypCbDiffBuffer = vImage_Buffer(data: ypCbDiffBufferData, height: yp.pointee.height, width: alignedWidth / 2, rowBytes: Int(alignedWidth) / 2 * MemoryLayout<UInt8>.size)
        let ypCbDiffBufferArray = UnsafeMutablePointer<UnsafePointer<vImage_Buffer>?>.allocate(capacity: 1)
        ypCbDiffBufferArray.initialize(to: &ypCbDiffBuffer)
        defer {
            ypCbDiffBufferArray.deinitialize(count: 1)
            ypCbDiffBufferArray.deallocate()
        }
        
        try vImageTry(vImageConvert_ChunkyToPlanar8(ypBufferData0,
                                                    ypCbDiffBufferArray,
                                                    1,
                                                    2,
                                                    alignedWidth / 2,
                                                    yp.pointee.height,
                                                    yp.pointee.rowBytes,
                                                    vImage_Flags(kvImageNoFlags)
                                                   ), errorMessage: "Failed to separate first Y channel.")
        
        // compose yp-cr difference buffer
        let ypCrDiffBufferData = UnsafeMutableRawPointer.allocate(byteCount: Int(ypDiffBufferDataByteCount), alignment: MemoryLayout<UInt8>.alignment)
        let ypBufferData1 = UnsafeMutablePointer<UnsafeRawPointer?>.allocate(capacity: 1)
        ypBufferData1.initialize(to: yp.pointee.data.successor())
        defer {
            ypCrDiffBufferData.deallocate()
            ypBufferData1.deinitialize(count: 1)
            ypBufferData1.deallocate()
        }
        
        var ypCrDiffBuffer = vImage_Buffer(data: ypCrDiffBufferData, height: yp.pointee.height, width: avif.vWidth / 2, rowBytes: Int(alignedWidth) / 2 * MemoryLayout<UInt8>.size)
        let ypCrDiffBufferArray = UnsafeMutablePointer<UnsafePointer<vImage_Buffer>?>.allocate(capacity: 1)
        ypCrDiffBufferArray.initialize(to: &ypCrDiffBuffer)
        defer {
            ypCrDiffBufferArray.deinitialize(count: 1)
            ypCrDiffBufferArray.deallocate()
        }
        
        try vImageTry(vImageConvert_ChunkyToPlanar8(ypBufferData1,
                                                    ypCrDiffBufferArray,
                                                    1,
                                                    2,
                                                    yp.pointee.width / 2,
                                                    yp.pointee.height,
                                                    yp.pointee.rowBytes,
                                                    vImage_Flags(kvImageNoFlags)
                                                   ), errorMessage: "Failed to separate first Y channel.")
        
        // combine yp-cb diff, cb, yp-cr diff and cr
        let yuyvBufferData = UnsafeMutableRawPointer.allocate(byteCount: Int(alignedWidth) * avif.iHeight * 2 * MemoryLayout<UInt8>.size, alignment: MemoryLayout<UInt8>.alignment)
        var yuyvBuffer = vImage_Buffer(data: yuyvBufferData, height: avif.vHeight, width: alignedWidth / 2, rowBytes: Int(alignedWidth) * 2 * MemoryLayout<UInt8>.size)
        defer {
            yuyvBufferData.deallocate()
        }
        
        try vImageTry(vImageConvert_Planar8toARGB8888(&ypCbDiffBuffer,
                                                      cb,
                                                      &ypCrDiffBuffer,
                                                      cr,
                                                      &yuyvBuffer,
                                                      vImage_Flags(kvImageNoFlags)
                                                     ), errorMessage: "Failed to composite kvImage422YpCbYpCr8.")
        yuyvBuffer.width *= 2
        
        var conversionInfo = try generateConversionInfo(type: kvImage422YpCbYpCr8)
        try vImageTry(vImageConvert_422YpCbYpCr8ToARGB8888(&yuyvBuffer,
                                                           &argbBuffer,
                                                           &conversionInfo,
                                                           permuteMap,
                                                           255,
                                                           vImage_Flags(kvImageNoFlags)
                                                          ), errorMessage: "Failed to convert to ARGB8888.")
        
        return (argbBuffer, disposable)
    }
    
    func alpha() throws -> ImageBufferWithDisposables {
        var srcAlphaBuffer = vImage_Buffer(data: avif.alphaPlane, height: avif.vHeight, width: avif.vWidth, rowBytes: Int(avif.alphaRowBytes))
        guard characteristics.alphaRange == AVIF_RANGE_LIMITED else {
            return (srcAlphaBuffer, [])
        }

        // Limited → full range expansion in a single pass with a 256-entry LUT.
        // (Replaces the previous two-pass Planar8 → PlanarF → Planar8 conversion
        // and its W×H×4-byte float intermediate buffer.)
        let expandedAlphaBufferData = UnsafeMutableRawPointer.allocate(byteCount: avif.iWidth * avif.iHeight * MemoryLayout<UInt8>.size, alignment: MemoryLayout<UInt8>.alignment)
        var alphaBuffer = vImage_Buffer(data: expandedAlphaBufferData, height: avif.vHeight, width: avif.vWidth, rowBytes: avif.iWidth * MemoryLayout<UInt8>.size)

        do {
            try limitedRangeToFull8Table.withUnsafeBufferPointer { table in
                try vImageTry(vImageTableLookUp_Planar8(&srcAlphaBuffer,
                                                        &alphaBuffer,
                                                        table.baseAddress,
                                                        vImage_Flags(kvImageNoFlags)
                                                       ), errorMessage: "Failed to expand limited-range alpha plane.")
            }
            return (alphaBuffer, [expandedAlphaBufferData.deallocate])
        } catch let e {
            expandedAlphaBufferData.deallocate()
            throw e
        }
    }
    
    func monochromeCombine(argbBuffer: inout vImage_Buffer, alphaBuffer: inout vImage_Buffer?) throws -> vImage_Buffer {
        let resultBufferData = UnsafeMutableRawPointer.allocate(byteCount: characteristics.componentsPerPixel * avif.iWidth * avif.iHeight * MemoryLayout<UInt8>.size, alignment: MemoryLayout<UInt8>.alignment)
        var resultBuffer = vImage_Buffer(data: resultBufferData, height: avif.vHeight, width: avif.vWidth, rowBytes: Int(avif.vWidth) * characteristics.componentsPerPixel)
        
        let tmpBufferData = UnsafeMutableRawPointer.allocate(byteCount: avif.iWidth * MemoryLayout<UInt8>.size, alignment: MemoryLayout<UInt8>.alignment)
        defer { tmpBufferData.deallocate() }
        
        var tmpBuffer = vImage_Buffer(data: tmpBufferData, height: avif.vHeight, width: avif.vWidth, rowBytes: 0)
        
        if var alphaBuffer = alphaBuffer {
            let tmpMonoBufferData = UnsafeMutableRawPointer.allocate(byteCount: avif.iWidth * avif.iHeight * MemoryLayout<UInt8>.size, alignment: MemoryLayout<UInt8>.alignment)
            defer { tmpMonoBufferData.deallocate() }
            var tmpMonoBuffer = vImage_Buffer(data: tmpMonoBufferData, height: avif.vHeight, width: avif.vWidth, rowBytes: avif.iWidth)
            
            try vImageTry(vImageConvert_ARGB8888toPlanar8(&argbBuffer,
                                                          &tmpBuffer,
                                                          &tmpBuffer,
                                                          &tmpMonoBuffer,
                                                          &tmpBuffer,
                                                          vImage_Flags(kvImageNoFlags)
                                                         ), errorMessage: "Failed to convert ARGB to A_G_")
            
            let srcPlanarBuffers = UnsafeMutablePointer<UnsafePointer<vImage_Buffer>?>.allocate(capacity: 2)
            srcPlanarBuffers.initialize(to: &alphaBuffer)
            srcPlanarBuffers.successor().initialize(to: &tmpMonoBuffer)
            defer {
                srcPlanarBuffers.deinitialize(count: 2)
                srcPlanarBuffers.deallocate()
            }
            
            let destChannels = UnsafeMutablePointer<UnsafeMutableRawPointer?>.allocate(capacity: 2)
            destChannels.initialize(to: resultBufferData)
            destChannels.successor().initialize(to: resultBufferData.successor())
            
            defer {
                destChannels.deinitialize(count: 2)
                destChannels.deallocate()
            }
            
            try vImageTry(vImageConvert_PlanarToChunky8(srcPlanarBuffers,
                                                        destChannels,
                                                        2,
                                                        2,
                                                        avif.vWidth,
                                                        avif.vHeight,
                                                        characteristics.bytesPerRow,
                                                        vImage_Flags(kvImageNoFlags)
                                                       ), errorMessage: "Failed to combine mono and alpha")
            
            return resultBuffer
        } else {
            try vImageTry(vImageConvert_ARGB8888toPlanar8(&argbBuffer,
                                                      &tmpBuffer,
                                                      &tmpBuffer,
                                                      &resultBuffer,
                                                      &tmpBuffer,
                                                      vImage_Flags(kvImageNoFlags)
                                                     ), errorMessage: "Failed to convert ARGB to B(Mono).")
            return resultBuffer
        }
    }
    
    func colorCombine(argbBuffer: inout vImage_Buffer, alphaBuffer: inout vImage_Buffer?) throws -> vImage_Buffer {
        if var alphaBuffer = alphaBuffer {
            try vImageTry(vImageOverwriteChannels_ARGB8888(&alphaBuffer,
                                                           &argbBuffer,
                                                           &argbBuffer,
                                                           0x8,
                                                           vImage_Flags(kvImageNoFlags)
                                                          ), errorMessage: "Failed to overwrite alpha.")
            return argbBuffer
        } else {
            // No alpha: keep the ARGB8888 buffer as-is; CGImage creation marks the
            // leading byte as skipped (.noneSkipFirst). This removes a full
            // ARGB8888 → RGB888 conversion pass and a separate W×H×3 buffer.
            return argbBuffer
        }
    }
    
    var argbBuffer = try { () -> ImageBufferWithDisposables in
        switch avif.yuvFormat {
        case AVIF_PIXEL_FORMAT_NONE:
            throw FormatError(message: "Invalid pixel format.")
        case AVIF_PIXEL_FORMAT_YUV420, AVIF_PIXEL_FORMAT_YUV400:
            return try yuv420_400()
        case AVIF_PIXEL_FORMAT_YUV444:
            return try yuv444()
        case AVIF_PIXEL_FORMAT_YUV422:
            return try yuv422()
        default:
            throw FormatError(message: "Invalid pixel format.")
        }
    }()
    defer {
        // Color images (with or without alpha) now return the ARGB buffer itself
        // as the final result, so it may only be disposed on the monochrome path,
        // which copies its pixels out into a separate result buffer.
        if characteristics.monochrome {
            argbBuffer.disposers.forEach { $0() }
        }
    }
    
    var (alphaBuffer, alphaDisposers) = try { () -> (vImage_Buffer?, [Disposer]?) in
        guard (characteristics.hasAlpha) else { return (nil, nil) }
        return try alpha()
    }()
    defer { alphaDisposers?.forEach { $0() } }
    
    if characteristics.monochrome {
        return try monochromeCombine(argbBuffer: &argbBuffer.buffer, alphaBuffer: &alphaBuffer)
    } else {
        return try colorCombine(argbBuffer: &argbBuffer.buffer, alphaBuffer: &alphaBuffer)
    }
}

fileprivate struct ConversionError: Error {
    let message: String
    let vImageError: vImage_Error
}

fileprivate struct FormatError: Error {
    let message: String
}


fileprivate func vImageTry(_ result: vImage_Error, errorMessage: String) throws {
    if result != kvImageNoError {
        throw ConversionError(message: errorMessage, vImageError: result)
    }
}
