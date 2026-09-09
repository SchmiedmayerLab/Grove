//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import Foundation
@testable import GroveChat
import Testing


@Suite("ChatEntity image coding")
struct ChatEntityImageCodingTests {
    @Test("A picture still being drawn round-trips")
    func generatingRoundTrips() throws {
        let data = try JSONEncoder().encode(ChatEntity.Content.Image.generating)
        #expect(try JSONDecoder().decode(ChatEntity.Content.Image.self, from: data) == .generating)
    }

    @Test("A URL still decodes as before")
    func urlRoundTrips() throws {
        let url = try #require(URL(string: "https://example.com/picture.png"))
        let data = try JSONEncoder().encode(ChatEntity.Content.Image.url(url))
        #expect(try JSONDecoder().decode(ChatEntity.Content.Image.self, from: data) == .url(url))
    }
}
