//
//  LHECategoryChip.swift
//  MediaMix
//
//  Created by Rahel Arnold
//

import SwiftUI

struct LHECategoryChip: View {
    let title: String
    let subtitle: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.subheadline)
                        .lineLimit(1)

                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 0)

                Image(
                    systemName: isSelected ? "checkmark.circle.fill" : "circle"
                )
                .foregroundStyle(isSelected ? .primary : .secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(isSelected ? .ultraThinMaterial : .thinMaterial)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .strokeBorder(
                        isSelected
                            ? Color.primary.opacity(0.35)
                            : Color.secondary.opacity(0.25),
                        lineWidth: isSelected ? 2 : 1
                    )
            )
        }
        .buttonStyle(.plain)
        .contentShape(RoundedRectangle(cornerRadius: 14))
        .hoverEffect(.lift)
    }
}
