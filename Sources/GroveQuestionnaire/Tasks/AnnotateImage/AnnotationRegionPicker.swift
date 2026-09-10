//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

#if canImport(UIKit)
import SwiftUI


@available(iOS 18, macOS 15, watchOS 11, *)
struct AnnotationRegionPicker: View {
    private static let margin = CGFloat(12)
    private static let spacing = CGFloat(8)
    private static let fadeWidth = CGFloat(24)

    let regions: [AnnotateImageConfig.Region]
    @Binding var selectedRegion: AnnotateImageConfig.Region?
    @Binding var isErasing: Bool

    var body: some View {
        HStack(spacing: Self.spacing) {
            ScrollView(.horizontal) {
                regionButtons
                    .padding(.vertical, Self.spacing)
            }
            .contentMargins(.leading, Self.margin, for: .scrollContent)
            .contentMargins(.trailing, Self.fadeWidth, for: .scrollContent)
            .scrollIndicators(.hidden)
            .scrollClipDisabled()
            .mask { trailingFade }
            AnnotationEraserButton(isSelected: isErasing, action: selectEraser)
                .padding(.trailing, Self.margin)
        }
        .sensoryFeedback(.selection, trigger: selectedRegion)
        .sensoryFeedback(.selection, trigger: isErasing)
    }

    @ViewBuilder private var regionButtons: some View {
        if #available(iOS 26, *) {
            GlassEffectContainer(spacing: Self.spacing) {
                buttons
            }
        } else {
            buttons
        }
    }

    private var buttons: some View {
        HStack(spacing: Self.spacing) {
            ForEach(regions) { region in
                AnnotationRegionButton(
                    region: region,
                    isSelected: selectedRegion == region,
                    action: { select(region) }
                )
            }
        }
    }

    private var trailingFade: some View {
        HStack(spacing: 0) {
            Color.black
            LinearGradient(colors: [.black, .clear], startPoint: .leading, endPoint: .trailing)
                .frame(width: Self.fadeWidth)
        }
        .padding(.vertical, -Self.spacing)
    }

    private func select(_ region: AnnotateImageConfig.Region) {
        selectedRegion = region
        isErasing = false
    }

    private func selectEraser() {
        isErasing = true
        selectedRegion = nil
    }
}
#endif
