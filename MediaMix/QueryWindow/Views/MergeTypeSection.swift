//
//  MergeTypeSection.swift
//  MediaMix
//
//  Created by Rahel Arnold
//

import SwiftUI

struct MergeTypeSection: View {
    @Binding var selectedMergeType: MergeType
    let onChange: (MergeType) -> Void

    var body: some View {
        VStack(spacing: 20) {
            Text("Select Merge type")
                .font(.headline)

            Picker("Merge Type", selection: $selectedMergeType) {
                ForEach(MergeType.allCases) { type in
                    Text(type.displayName).tag(type)
                }
            }
            .pickerStyle(.segmented)
            .onChange(of: selectedMergeType) { _, newValue in
                onChange(newValue)
            }
        }
    }
}
