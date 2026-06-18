//
//  QueryButtonsBar.swift
//  MediaMix
//
//  Created by Rahel Arnold
//

import SwiftUI

struct QueryButtonsBar: View {
    let isLoading: Bool
    let queryText: String
    let showASR: Bool
    let onSim: () -> Void
    let onOCR: () -> Void
    let onASR: () -> Void

    var body: some View {
        HStack {
            Button("Similarity Query", action: onSim)
                .buttonStyle(DefaultButtonStyle())
                .frame(maxWidth: .infinity)
                .disabled(queryText.isEmpty || isLoading)

            Button("OCR Query", action: onOCR)
                .buttonStyle(DefaultButtonStyle())
                .frame(maxWidth: .infinity)
                .disabled(queryText.isEmpty || isLoading)

            if showASR {
                Button("ASR Query", action: onASR)
                    .buttonStyle(DefaultButtonStyle())
                    .frame(maxWidth: .infinity)
                    .disabled(queryText.isEmpty || isLoading)
            }
        }
        .frame(height: 44)
        .padding(.horizontal)
    }
}
