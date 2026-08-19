//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

public import Foundation


@available(iOS 18, macOS 15, watchOS 11, *)
extension ChatEntity {
    /// Where something in a message came from.
    ///
    /// A model that searches the web or reads a document reports what it drew on, and a chat that shows those
    /// sources lets the reader check a claim rather than take it on trust.
    ///
    /// ## Topics
    ///
    /// ### Where a citation points
    /// - ``Source-swift.enum``
    /// - ``source``
    /// - ``url``
    public struct Citation: Identifiable, Hashable, Codable, Sendable {
        /// What a citation points at.
        ///
        /// An enum rather than a pair of optionals: a citation always has exactly one source, and a type that
        /// could represent "neither" or "both" would have to be checked at every use.
        public enum Source: Hashable, Codable, Sendable {
            /// A page on the web.
            case web(URL)
            /// A file the model was given.
            case file(name: String)
        }

        public let id: UUID
        /// The source's title, as the provider reported it.
        public var title: String
        /// What the citation points at.
        public var source: Source

        /// The web address this citation points at, if it points at one.
        public var url: URL? {
            guard case .web(let url) = source else {
                return nil
            }
            return url
        }

        /// How the source is named in a list: a domain reads better than a full URL.
        public var displayName: String {
            switch source {
            case .web(let url):
                guard let host = url.host else {
                    return url.absoluteString
                }
                return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
            case .file(let name):
                return name
            }
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
}
