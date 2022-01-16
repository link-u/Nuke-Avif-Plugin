//
//  Buffer.swift
//  Nuke-Avif-Plugin
//
//  Created by murakami on 2022/01/17.
//

import Accelerate

typealias Disposer = () -> ()
typealias ImageBufferWithDisposables = (buffer: vImage_Buffer, disposers: [Disposer])
