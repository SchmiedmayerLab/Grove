//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

#if canImport(UIKit)
import GroveViews
import SwiftUI


@available(iOS 18, macOS 15, watchOS 11, *)
struct AnnotationRegionButton: View {
    let region: AnnotateImageConfig.Region
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Circle()
                    .fill(Color(region.color))
                    .frame(width: 18, height: 18)
                    .overlay {
                        Circle().stroke(.primary.opacity(0.25), lineWidth: 1)
                        Image(systemName: "checkmark")
                            .font(.caption2.bold())
                            .foregroundStyle(.white)
                            .shadow(color: .black.opacity(0.25), radius: 0.5, y: 0.5)
                            .opacity(isSelected ? 1 : 0)
                            .scaleEffect(isSelected ? 1 : 0.6)
                            .animation(.snappy(duration: 0.25), value: isSelected)
                    }
                    .accessibilityHidden(true)
                Text(region.name)
                    .foregroundStyle(.primary)
                    .fontWeight(isSelected ? .bold : .regular)
            }
            .padding(.horizontal, 14)
            .frame(minHeight: 44)
        }
        .buttonStyleGlass(fallback: .bordered)
        .tint(isSelected ? Color.accentColor : Color.secondary)
        .accessibilityIdentifier("AnnotationRegion:\(region.name)")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
#endif
