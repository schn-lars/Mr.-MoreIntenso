//
//  VideoPlayerView.swift
//  MediaMix
//
//  Created by Rahel Arnold
//

import AVKit
import SwiftUI

struct VideoPlayerView: View {
    let videoUrl: URL

    @State private var player: AVPlayer

    init(videoUrl: URL) {
        self.videoUrl = videoUrl
        _player = State(initialValue: AVPlayer(url: videoUrl))
    }

    var body: some View {
        Group {
            if videoUrl.absoluteString.isEmpty {
                Text("Invalid video URL")
                    .foregroundColor(.red)
                    .font(.headline)
            } else {
                VideoPlayer(player: player)
                    .onAppear { player.play() }
                    .onDisappear { player.pause() }
                    .onChange(of: videoUrl) { _, newURL in
                        player.replaceCurrentItem(with: AVPlayerItem(url: newURL))
                        player.play()
                    }
                    .background(Color.black)
            }
        }
        .background(Color.black.opacity(0.9))
    }
}
