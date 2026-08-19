//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import SwiftUI
#if canImport(SafariServices) && !os(macOS)
import SafariServices
#endif


// The modifier is an implementation detail of the extension below, which is the file's actual API.
// swiftlint:disable file_types_order
@available(iOS 18, macOS 15, watchOS 11, *)
private struct InAppBrowserModifier: ViewModifier {
    /// A `URL` that can drive a `sheet(item:)`.
    private struct InAppBrowserURL: Identifiable {
        var id: URL { url }
        let url: URL
    }

    @Binding var url: URL?

    #if !canImport(SafariServices) || os(macOS)
    @Environment(\.openURL) private var openURL
    #endif

    func body(content: Content) -> some View {
        #if canImport(SafariServices) && !os(macOS)
        content
            .sheet(item: Binding(get: { url.map(InAppBrowserURL.init) }, set: { url = $0?.url })) { identifiable in
                SafariView(url: identifiable.url)
                    .ignoresSafeArea()
            }
        #else
        content
            .onChange(of: url) { _, newValue in
                guard let newValue else {
                    return
                }
                openURL(newValue)
                url = nil
            }
        #endif
    }
}
// swiftlint:enable file_types_order
#if canImport(SafariServices) && !os(macOS)
@available(iOS 18, macOS 15, watchOS 11, *)
private struct SafariView: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> SFSafariViewController {
        SFSafariViewController(url: url)
    }

    func updateUIViewController(_ controller: SFSafariViewController, context: Context) {}
}
#endif


@available(iOS 18, macOS 15, watchOS 11, *)
extension View {
    /// Opens a source in a browser without leaving the conversation.
    ///
    /// A cited page is something to glance at and come back from, so on iOS it opens in a Safari view sheet rather
    /// than handing the reader to another app and losing their place. Where that view does not exist the system
    /// browser takes over, which is the same intent with the platform's own answer.
    @available(iOS 18, macOS 15, watchOS 11, *)
    func inAppBrowser(url: Binding<URL?>) -> some View {
        modifier(InAppBrowserModifier(url: url))
    }
}
