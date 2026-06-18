//
//  SphereLayoutEngine.swift
//  MediaMix
//
//  Created by Rahel Arnold
//

protocol SphereLayoutEngine {
    func layout(
        segments: [DetailedSegment],
        radius: Float,
        resolution: Double
    ) throws -> [TilePlacement]
}
