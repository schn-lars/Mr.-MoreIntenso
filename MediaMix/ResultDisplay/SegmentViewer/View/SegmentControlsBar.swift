//
//  SegmentControlsBar.swift
//  MediaMix
//
//  Created by Rahel Arnold
//

import SwiftUI

struct SegmentControlsBar: View {
    let engine: RetrievalEngine
    let isSubmitting: Bool

    let onSimilarityAtCurrentTime: () -> Void
    let onSimilarity: () -> Void
    let onSubmitFrame: () -> Void

    var body: some View {
        HStack {
            if engine == .ferelight {
                Button("Similarity @ Current Time", action: onSimilarityAtCurrentTime)
            }

            Button("Similarity Search", action: onSimilarity)

            Button("Submit Frame", action: onSubmitFrame)
                .disabled(isSubmitting)
        }
    }
}
