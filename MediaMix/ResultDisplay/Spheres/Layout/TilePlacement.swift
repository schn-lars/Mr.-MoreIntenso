//
//  TilePlacement.swift
//  MediaMix
//
//  Created by Rahel Arnold
//

struct TilePlacement: Equatable {
    let index: Int // index into segments
    let position: SIMD3<Float> // world position on sphere surface
    let outward: SIMD3<Float> // normalized position
    let tileSize: Float
}
