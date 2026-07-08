//
// This source file is part of the Stanford Spezi open-source project
//
// SPDX-FileCopyrightText: 2024 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import SwiftUI


@available(iOS 17, macOS 14, *)
struct DetailsSectionIcon: View {
    var body: some View {
        Image(systemName: "person.text.rectangle.fill")
            .accessibilityHidden(true)
            .font(.footnote)
            .foregroundStyle(.white)
            .graySquareBackground()
    }
}


@available(iOS 17, macOS 14, *)
struct SecuritySectionIcon: View {
    var body: some View {
        ZStack {
            Image(systemName: "shield.fill")
                .foregroundStyle(.white)
                .font(.title3)
            Image(systemName: "key.fill")
                .foregroundStyle(.gray)
                .font(.caption)
        }
            .accessibilityHidden(true)
            .graySquareBackground()
    }
}


@available(iOS 17, macOS 14, *)
extension View {
    fileprivate func graySquareBackground() -> some View {
        background {
            RoundedRectangle(cornerSize: .init(width: 4, height: 4))
                .aspectRatio(1, contentMode: .fill)
                .frame(height: 30)
                .foregroundStyle(.gray)
        }
    }
}


@available(iOS 17, macOS 14, *)
#Preview {
    List {
        Label {
            Text(verbatim: "Name, E-Mail Address")
        } icon: {
            DetailsSectionIcon()
        }
        Label {
            Text(verbatim: "Sign-In & Security")
        } icon: {
            SecuritySectionIcon()
        }
    }
}
