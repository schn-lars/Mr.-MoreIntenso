//
//  StatusSection.swift
//  MediaMix
//
//  Created by Rahel Arnold
//

import SwiftUI

struct StatusSection: View {
    let isLoading: Bool
    let noResults: Bool
    let errorMessage: String?

    var body: some View {
        Group {
            if isLoading {
                ProgressView("Loading...")
            } else if noResults {
                Text("No results for this query").fontWeight(.bold)
            }

            if let errorMessage {
                Text("Error: \(errorMessage)")
                    .foregroundStyle(.red)
            }
        }
    }
}
