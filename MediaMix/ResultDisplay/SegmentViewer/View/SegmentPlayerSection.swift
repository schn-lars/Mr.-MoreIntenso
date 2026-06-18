//
//  SegmentPlayerSection.swift
//  MediaMix
//
//  Created by Rahel Arnold
//

import AVKit
import SwiftUI

struct SegmentPlayerSection: View {
    let title: String
    let videoURL: URL?
    let player: AVPlayer?
    let onAppearWithURL: (URL) -> Void

    var body: some View {
        if let url = videoURL {
            VStack(spacing: 0) {
                HStack {
                    Text(title)
                        .font(.headline)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(Color(.secondarySystemBackground))
                .overlay(Divider(), alignment: .bottom)

                VideoPlayer(player: player)
                    .frame(height: 600)
                    .onAppear { onAppearWithURL(url) }
            }
        } else {
            Text("Video not available")
                .foregroundColor(.red)
                .frame(height: 600)
        }
    }
}
