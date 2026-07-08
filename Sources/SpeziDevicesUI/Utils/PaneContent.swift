//
// This source file is part of the Stanford Spezi open-source project
//
// SPDX-FileCopyrightText: 2024 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import SpeziViews
import SwiftUI


#if DEBUG
@available(iOS 17, macOS 14, macCatalyst 17, visionOS 1, *)
struct SheetPreview<Content: View>: View {
    private let content: Content

    @State private var isPresented = true

    var body: some View {
        Text(verbatim: "")
            .sheet(isPresented: $isPresented) {
                NavigationStack {
                    content
                        .toolbar {
                            DismissButton()
                        }
                }
                    .presentationDetents([.medium])
                    .presentationCornerRadius(25)
            }
    }

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }
}
#endif


@available(iOS 17, macOS 14, macCatalyst 17, visionOS 1, *)
struct PaneContent<Title: View, Subtitle: View, Content: View, Action: View>: View {
    private let title: Title
    private let subtitle: Subtitle?
    private let content: Content
    private let action: Action

    @AccessibilityFocusState private var isHeaderFocused: Bool

    var body: some View {
        VStack {
            VStack {
                title
                    .bold()
                    .font(.largeTitle)
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityFocused($isHeaderFocused)
                if let subtitle {
                    subtitle
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
                .padding([.leading, .trailing], 20)
                .multilineTextAlignment(.center)

            Spacer()
            content
            Spacer()

            action
        }
            .task {
                try? await Task.sleep(for: .milliseconds(300))
                isHeaderFocused = true
            }
    }

    init(
        @ViewBuilder title: () -> Title,
        @ViewBuilder subtitle: () -> Subtitle = { EmptyView() },
        @ViewBuilder content: () -> Content,
        @ViewBuilder action: () -> Action = { EmptyView() }
    ) {
        self.title = title()
        self.subtitle = subtitle()
        self.content = content()
        self.action = action()
    }

    init(title: Text, subtitle: Text? = nil, @ViewBuilder content: () -> Content, @ViewBuilder action: () -> Action = { EmptyView() })
        where Title == Text, Subtitle == Text {
        self.title = title
        self.subtitle = subtitle
        self.content = content()
        self.action = action()
    }

    init(
        title: LocalizedStringResource,
        subtitle: LocalizedStringResource? = nil,
        @ViewBuilder content: () -> Content,
        @ViewBuilder action: () -> Action = { EmptyView() }
    ) where Title == Text, Subtitle == Text {
        self.init(title: Text(title), subtitle: subtitle.map { Text($0) }, content: content, action: action)
    }
}


#if DEBUG
@available(iOS 17, macOS 14, macCatalyst 17, visionOS 1, *)
#Preview {
    SheetPreview {
        PaneContent(title: Text(verbatim: "The Title"), subtitle: Text(verbatim: "The Subtitle")) {
            Image(systemName: "person.crop.square.badge.camera.fill")
                .symbolRenderingMode(.hierarchical)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .accessibilityHidden(true)
                .frame(maxWidth: 250, maxHeight: 120)
                .foregroundStyle(.red)
        } action: {
            Button {
            } label: {
                Text(verbatim: "Button")
                    .frame(maxWidth: .infinity, maxHeight: 35)
            }
                .buttonStyle(.borderedProminent)
                .padding([.leading, .trailing], 36)
        }
    }
}
#endif
