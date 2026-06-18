//
//  SphereSettings.swift
//  MediaMix
//
//  Created by Rahel Arnold
//

import SwiftUI

struct SphereSettings: View {
    @ObservedObject var controller: SphereController
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(controller.descriptor.label)

            Picker("Layout", selection: $controller.layoutMode) {
                ForEach(SphereLayoutMode.allCases) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }

            Slider(value: $controller.resolution, in: 2 ... 14, step: 1) {
                Text("Resolution")
            }

            HStack(spacing: 12) {
                Button("Apply") {
                    Task { await controller.rebuild() }
                }

                Button(role: .destructive) {
                    onClose()
                } label: {
                    Text("Close")
                }
            }
        }
        .padding()
    }
}
