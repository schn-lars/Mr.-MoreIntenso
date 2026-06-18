//
//  SimilarityButton.swift
//  MediaMix
//
//  Created by Rahel Arnold
//

import SwiftUI

struct SimilarityButton: View {
    let action: () -> Void
    var isEnabled: Bool = true

    var body: some View {
        Button(action: action) {
            Label("Similar", systemImage: "sparkles")
                .font(.caption.bold())
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.small)
        .disabled(!isEnabled)
    }
}
