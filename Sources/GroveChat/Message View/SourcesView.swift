//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import GroveViews
import SwiftUI


/// The full list of sources behind an answer.
@available(iOS 18, macOS 15, watchOS 11, *)
struct SourcesList: View {
    let citations: [ChatEntity.Citation]

    @State private var openedURL: URL?

    private var webCitations: [ChatEntity.Citation] {
        citations.filter { $0.url != nil }
    }

    private var fileCitations: [ChatEntity.Citation] {
        citations.filter { $0.url == nil }
    }

    var body: some View {
        NavigationStack {
            List {
                fileSection
                webSection
            }
            .navigationTitle(Text("SOURCES", bundle: .module))
            #if os(iOS) || os(visionOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    DismissButton()
                }
            }
        }
        .presentationDetents([.medium, .large])
        .inAppBrowser(url: $openedURL)
    }

    @ViewBuilder private var fileSection: some View {
        if !fileCitations.isEmpty {
            Section {
                ForEach(fileCitations) { citation in
                    row(for: citation)
                }
            } header: {
                Text("SOURCES_FILES \(fileCitations.count)", bundle: .module)
            }
        }
    }

    @ViewBuilder private var webSection: some View {
        if !webCitations.isEmpty {
            Section {
                ForEach(webCitations) { citation in
                    Button {
                        openedURL = citation.url
                    } label: {
                        row(for: citation)
                    }
                    .buttonStyle(.plain)
                }
            } header: {
                Text("SOURCES_WEB \(webCitations.count)", bundle: .module)
            }
        }
    }

    private func row(for citation: ChatEntity.Citation) -> some View {
        HStack(spacing: 10) {
            Image(systemName: citation.url == nil ? "document" : "globe")
                .foregroundStyle(.secondary)
                .frame(width: 20)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(citation.title)
                    .font(.subheadline)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                // A file cited under its own file name has nothing left to say on a second line.
                if citation.displayName != citation.title {
                    Text(citation.displayName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
    }
}


/// Shows where an answer came from, without getting in the way of reading it.
///
/// Sources sit under the message as one quiet line rather than as links through the text: a reader who wants to
/// check a claim asks for them, and everyone else is not made to read around them. Tapping opens the full list.
@available(iOS 18, macOS 15, watchOS 11, *)
struct SourcesView: View {
    /// How many sources are named before the rest become a count.
    private static let namedSourceLimit = 2

    let citations: [ChatEntity.Citation]

    @State private var isShowingSources = false

    private var summary: String {
        let names = citations.prefix(Self.namedSourceLimit).map(\.displayName)
        let remainder = citations.count - names.count
        guard remainder > 0 else {
            return names.joined(separator: ", ")
        }
        return names.joined(separator: ", ") + " +\(remainder)"
    }

    var body: some View {
        if !citations.isEmpty {
            Button {
                isShowingSources = true
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "book")
                        .accessibilityHidden(true)
                    Text("SOURCES_SUMMARY \(summary)", bundle: .module)
                        .lineLimit(1)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("SOURCES_COUNT \(citations.count)", bundle: .module))
            .sheet(isPresented: $isShowingSources) {
                SourcesList(citations: citations)
            }
        }
    }
}
