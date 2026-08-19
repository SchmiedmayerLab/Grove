//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

public import Foundation


/// Where something the model said came from.
///
/// A model that searches the web or reads a document reports what it drew on. Grove keeps that alongside the
/// answer so a chat can show its work, which is what makes an assistant's claim checkable rather than merely
/// confident.
///
/// ## Topics
///
/// ### Where a citation points
/// - ``Source-swift.enum``
/// - ``source``
@available(iOS 18, macOS 15, watchOS 11, *)
public struct LLMCitation: Identifiable, Hashable, Codable, Sendable {
    /// What a citation points at.
    ///
    /// An enum rather than a pair of optionals: a citation always has exactly one source, and a type that can
    /// represent "neither" or "both" would have to be checked everywhere it is read.
    public enum Source: Hashable, Codable, Sendable {
        /// A page on the web.
        case web(URL)
        /// A file the model was given.
        case file(name: String)
    }

    public let id: UUID
    /// The source's title, as the provider reported it.
    public let title: String
    /// What the citation points at.
    public let source: Source

    /// The web address this citation points at, if it points at one.
    public var url: URL? {
        guard case .web(let url) = source else {
            return nil
        }
        return url
    }

    /// - Parameters:
    ///   - title: The source's title.
    ///   - source: What the citation points at.
    ///   - id: The citation's identity, defaulting to a fresh one.
    public init(title: String, source: Source, id: UUID = .init()) {
        self.title = title
        self.source = source
        self.id = id
    }
}
