//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import Foundation


@available(iOS 18, macOS 15, watchOS 11, *)
extension LLMOpenAIRealtimeConnection {
    /// Derives the realtime socket from the REST endpoint it sits next to, so a gateway serving both is reached the same way.
    package static func realtimeSocketUrl(from serverUrl: URL, model: String) throws -> URL {
        guard var components = URLComponents(url: serverUrl, resolvingAgainstBaseURL: false) else {
            throw RealtimeError.malformedUrlError
        }
        components.scheme = components.scheme == "http" ? "ws" : "wss"
        let path = components.path.hasSuffix("/") ? String(components.path.dropLast()) : components.path
        components.path = path + "/realtime"
        components.queryItems = [URLQueryItem(name: "model", value: model)]
        guard let url = components.url else {
            throw RealtimeError.malformedUrlError
        }
        return url
    }
}
