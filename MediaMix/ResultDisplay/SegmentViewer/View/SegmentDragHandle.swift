//
//  SegmentDragHandle.swift
//  MediaMix
//
//  Created by Rahel Arnold
//

import SwiftUI

struct SegmentDragHandle: View {
    let onChanged: (CGSize) -> Void
    let onEnded: (CGSize) -> Void

    var body: some View {
        RoundedCorners(radius: 15, corners: [.topLeft, .topRight])
            .fill(Color.white.opacity(0.8))
            .frame(height: 30)
            .gesture(
                DragGesture()
                    .onChanged { onChanged($0.translation) }
                    .onEnded { onEnded($0.translation) }
            )
            .overlay(
                Text("Drag here")
                    .font(.caption)
                    .foregroundColor(.gray)
            )
    }
}
