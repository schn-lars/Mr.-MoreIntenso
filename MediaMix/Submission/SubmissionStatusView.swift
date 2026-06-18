//
//  SubmissionStatusView.swift
//  MediaMix
//
//  Created by Rahel Arnold
//

import SwiftUI

struct SubmissionStatusView: View {
    @EnvironmentObject var popup: SubmissionPopupModel
    @Environment(\.dismissWindow) private var dismissWindow

    var body: some View {
        VStack(spacing: 14) {
            Image(
                systemName: popup.isSuccess
                    ? "checkmark.circle.fill" : "xmark.octagon.fill"
            )
            .font(.system(size: 40))
            .foregroundStyle(popup.isSuccess ? .green : .red)

            Text(popup.message)
                .multilineTextAlignment(.center)
                .font(.title3)
        }
        .padding(24)
        .onAppear {
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 3_000_000_000) // 3 seconds
                dismissWindow(id: "submissionStatus")
            }
        }
    }
}
