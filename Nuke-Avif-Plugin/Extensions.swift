//
//  Extensions.swift
//  Nuke-Avif-Plugin
//
//  Created by murakami on 2022/01/12.
//

import Accelerate
import libavif

extension avifImage {
    var vWidth: vImagePixelCount {
        return .init(width)
    }
    
    var iWidth: Int {
        return .init(width)
    }
    
    var vHeight: vImagePixelCount {
        return .init(height)
    }
    
    var iHeight: Int {
        return .init(height)
    }
    
    var vAlphaRowBytes: Int {
        return .init(alphaRowBytes)
    }
}
