//
//  Extract.swift
//  Nuke-Avif-Plugin
//
//  Created by murakami on 2021/11/26.
//

import Foundation
import Accelerate
import libavif

func extract8(avif: avifImage, chromaShift: (x: Int, y: Int), pixelRange: vImage_YpCbCrPixelRange) -> (buffers: (yp: vImage_Buffer, cb: vImage_Buffer, cr: vImage_Buffer), disposers: [Disposer]) {
    let ypBuffer = vImage_Buffer(data: tuple3Index(avif.yuvPlanes, AVIF_CHAN_Y),
                                 height: vImagePixelCount(avif.height),
                                 width: vImagePixelCount(avif.width),
                                 rowBytes: Int(tuple3Index(avif.yuvRowBytes, AVIF_CHAN_Y)))
    
    let cbcrWidth = (Int(avif.width) + chromaShift.x) >> chromaShift.x
    let cbcrHeight = (Int(avif.height) + chromaShift.y) >> chromaShift.y
                          
    let cbData = tuple3Index(avif.yuvPlanes, AVIF_CHAN_U)
    let cbBufferWithDisposables = { () -> ImageBufferWithDisposables in
        if cbData != nil {
            return (
                .init(data: cbData,
                      height: vImagePixelCount(cbcrHeight),
                      width: vImagePixelCount(cbcrWidth),
                      rowBytes: Int(tuple3Index(avif.yuvRowBytes, AVIF_CHAN_U))),
                []
            )
        } else {
            let dummyCbData = UnsafeMutableRawPointer.allocate(byteCount: cbcrWidth * MemoryLayout<UInt8>.size, alignment: 0)
            dummyCbData.initializeMemory(as: UInt8.self, repeating: UInt8(pixelRange.CbCr_bias), count: cbcrWidth)
            return (
                .init(data: dummyCbData,
                      height: vImagePixelCount(cbcrHeight),
                      width: vImagePixelCount(cbcrWidth),
                      rowBytes: 0),
                [dummyCbData.deallocate]
            )
        }
    }()
    
    let crData = tuple3Index(avif.yuvPlanes, AVIF_CHAN_V)
    let crBufferDataWithDisposables = { () -> ImageBufferWithDisposables in
        if crData != nil {
            return (
                .init(data: crData,
                                      height: vImagePixelCount(cbcrHeight),
                                      width: vImagePixelCount(cbcrWidth),
                                      rowBytes: Int(tuple3Index(avif.yuvRowBytes, AVIF_CHAN_V))),
                []
            )
        } else {
            let dummyCrData = UnsafeMutableRawPointer.allocate(byteCount: cbcrWidth * MemoryLayout<Int>.size, alignment: 0)
            dummyCrData.initializeMemory(as: UInt8.self, repeating: UInt8(pixelRange.CbCr_bias), count: cbcrWidth)
            return (
                .init(data: dummyCrData,
                                      height: vImagePixelCount(cbcrHeight),
                                      width: vImagePixelCount(cbcrWidth),
                                      rowBytes: 0),
                [dummyCrData.deallocate]
            )
        }
    }()
    
    return (
        buffers: (yp: ypBuffer, cb: cbBufferWithDisposables.buffer, cr: crBufferDataWithDisposables.buffer),
        disposers: cbBufferWithDisposables.disposers + crBufferDataWithDisposables.disposers
    )
}

private func tuple3Index<T>(_ tuple: (T, T, T), _ index: avifChannelIndex) -> T {
    switch index.rawValue {
    case 0:     return tuple.0
    case 1:     return tuple.1
    default:    return tuple.2
    }
}
