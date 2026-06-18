//
//  LHEFiltersSection.swift
//  MediaMix
//
//  Created by Rahel Arnold
//

import SwiftUI

struct LHEFiltersSection: View {
    let bundle: LHEFiltersBundle
    let selectedKeys: Set<String>

    let onToggle: (String) -> Void
    let onClear: () -> Void

    private let columns = Array(
        repeating: GridItem(.flexible(), spacing: 10),
        count: 3
    )

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            selectionInfo
            categoryGrid
        }
        .padding(.vertical, 6)
    }

    // MARK: - Subviews

    private var header: some View {
        HStack {
            Text("LHE Filters")
                .font(.headline)

            Spacer()

            if !selectedKeys.isEmpty {
                Button("Clear", action: onClear)
                    .buttonStyle(.bordered)
            }
        }
    }

    private var selectionInfo: some View {
        Text(
            selectedKeys.isEmpty
                ? "All categories"
                : "\(selectedKeys.count) selected"
        )
        .font(.subheadline)
        .foregroundStyle(.secondary)
    }

    private var categoryGrid: some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: 10) {
            ForEach(bundle.categories) { category in
                LHECategoryChip(
                    title: category.displayName,
                    subtitle: "\(category.count)",
                    isSelected: selectedKeys.contains(category.key)
                ) {
                    onToggle(category.key)
                }
            }
        }
        .padding(.top, 4)
    }
}
