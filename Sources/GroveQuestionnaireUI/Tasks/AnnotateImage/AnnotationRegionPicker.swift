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
    let regions: [AnnotateImageConfig.Region]
    @Binding var selectedRegion: AnnotateImageConfig.Region?

    var body: some View {
        ScrollView(.horizontal) {
            regionButtons
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
        }
        .scrollIndicators(.hidden)
        .scrollClipDisabled()
        .sensoryFeedback(.selection, trigger: selectedRegion)
    }

    @ViewBuilder private var regionButtons: some View {
        if #available(iOS 26, *) {
            GlassEffectContainer(spacing: 8) {
                buttons
            }
        } else {
            buttons
        }
    }

    private var buttons: some View {
        HStack(spacing: 8) {
            ForEach(regions) { region in
                AnnotationRegionButton(
                    region: region,
                    isSelected: selectedRegion == region,
                    action: { selectedRegion = region }
                )
            }
        }
    }
}
#endif
