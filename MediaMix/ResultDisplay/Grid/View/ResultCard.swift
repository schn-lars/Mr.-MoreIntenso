//
//  ResultCard.swift
//  MediaMix
//
//  Created by Rahel Arnold
//

import FereLightSwiftClient
import SwiftUI

struct ResultCard: View {
    let segment: DetailedSegment

    let onOpen: () -> Void
    let onSimilarity: () -> Void
    let isSimilarityEnabled: Bool

    @State private var isHovered = false

    var body: some View {
        VStack(alignment: .leading) {
            thumbnail
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(isHovered ? Color.accentColor.opacity(0.12) : Color.clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(isHovered ? Color.accentColor.opacity(0.55) : Color.gray.opacity(0.2), lineWidth: 1)
        )
        .scaleEffect(isHovered ? 1.02 : 1.0)
        .animation(.easeOut(duration: 0.15), value: isHovered)
        .onHover { isHovered = $0 }
        .onTapGesture { onOpen() }
    }

    private var thumbnail: some View {
        AsyncImage(
            url: URLGenerator.generateImageURL(
                database: segment.collection,
                objectId: segment.objectId,
                segmentId: segment.segmentId
            )
        ) { image in
            image.resizable().scaledToFill()
        } placeholder: {
            Color.gray.opacity(0.2).overlay(ProgressView())
        }
        .frame(width: 200, height: 120)
        .clipped()
        .cornerRadius(10)
        .shadow(radius: 2)
        .overlay(alignment: .bottomTrailing) {
            SubmitButton(segment: segment).padding(8)
        }
        .overlay(alignment: .bottomLeading) {
            SimilarityButton(
                action: onSimilarity,
                isEnabled: isSimilarityEnabled
            )
            .padding(8)
        }
    }
}
