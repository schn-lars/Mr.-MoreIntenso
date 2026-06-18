//
//  BaseRenderer.swift
//  MediaMix
//
//  Created by Lars Schneider on 12.03.2026.
//

import RealityKit
import SwiftUI

/// we need it to be MainActor as it will be responisble to render elements into the RealityVeiw.
/// Otherwise compiler would be mean
@MainActor
protocol BaseRenderer {
    func setup(_ content: RealityViewContent)

    func update(_ content: RealityViewContent)
}
