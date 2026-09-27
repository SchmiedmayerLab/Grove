//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2022 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

public import GroveFoundation
public import SwiftUI


/// Present informational content in a row-based style.
///
/// The `OnboardingInformationView` allows developers to present a unified style to display informational content as defined
/// by the ``OnboardingInformationView/Area`` type.
///
/// The following example displays an ``OnboardingInformationView`` with two information areas:
/// ```swift
/// OnboardingInformationView {
///     OnboardingInformationView.Area(
///         iconSymbol: "pc",
///         title: "PC",
///         description: "This is a PC."
///     )
///     OnboardingInformationView.Content(
///         iconSymbol: "desktopcomputer",
///         title: "Mac",
///         description: "This is an iMac."
///     )
/// }
/// ```
@available(iOS 18, macOS 15, watchOS 11, *)
public struct OnboardingInformationView: View {
    private let areas: [Area]
    
    @_documentation(visibility: internal)
    public var body: some View {
        Grid(alignment: .topLeading, horizontalSpacing: 16, verticalSpacing: 16) {
            ForEach(0..<areas.count, id: \.self) { index in
                areaRow(area: areas[index])
            }
        }
    }
    
    /// Creates an `OnboardingInformationView` instance with a collection of areas defined by the ``Area`` type.
    /// - Parameter areas: The areas that should be displayed.
    public init(areas: [Area]) {
        self.areas = areas
    }
    
    /// Creates an `OnboardingInformationView` instance with a collection of areas defined by the ``Area`` type.
    /// - Parameter areas: The areas that should be displayed.
    public init(@ArrayBuilder<Area> areas: () -> [Area]) {
        self.init(areas: areas())
    }
    
    private func areaRow(area: Area) -> some View {
        GridRow {
            area.icon
                .font(.system(size: 28))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.tint)
                .frame(width: 42, height: 42)
                .gridCellAnchor(.topLeading)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                area.title
                    .bold()
                    .accessibilityAddTraits(.isHeader)
                area.description
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.bottom, 8)
        }
    }
}


#if DEBUG
@available(iOS 18, macOS 15, watchOS 11, *)
#Preview {
    OnboardingInformationView {
        OnboardingInformationView.Area(
            iconSymbol: "pc",
            title: String("PC"),
            description: String("This is a PC.")
        )
        OnboardingInformationView.Area(
            iconSymbol: "desktopcomputer",
            title: String("Mac"),
            description: String("This is an iMac.")
        )
    }
}
#endif
