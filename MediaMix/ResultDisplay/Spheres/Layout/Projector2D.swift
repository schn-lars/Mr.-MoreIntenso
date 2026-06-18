//
//  Projector2D.swift
//  MediaMix
//
//  Created by Rahel Arnold
//

import Accelerate
import Foundation
import simd

protocol Projector2D {
    func project(_ vectors: [[Float]]) -> [SIMD2<Float>]
}
