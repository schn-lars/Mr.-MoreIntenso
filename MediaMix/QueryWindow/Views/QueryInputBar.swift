//
//  QueryInputBar.swift
//  MediaMix
//
//  Created by Rahel Arnold
//

import SwiftUI

struct QueryInputBar: View {
    @Binding var queryText: String
    let onClear: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            TextField("Enter your query...", text: $queryText)
                .textFieldStyle(.roundedBorder)

            if !queryText.isEmpty {
                Button(action: onClear) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .hoverEffect(.lift)
                .accessibilityLabel("Clear query text")
            }
        }
        .padding(.vertical)
    }
}
