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
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif


@Suite("Chat Entity")
struct ChatEntityTests {
    /// A 1×1 image, created without touching the file system.
    private static func testImage() -> PlatformImage {
        #if canImport(UIKit)
        UIGraphicsImageRenderer(size: CGSize(width: 1, height: 1)).image { context in
            UIColor.red.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 1, height: 1))
        }
        #else
        let image = NSImage(size: NSSize(width: 1, height: 1))
        image.lockFocus()
        NSColor.red.setFill()
        NSRect(x: 0, y: 0, width: 1, height: 1).fill()
        image.unlockFocus()
        return image
        #endif
    }

    @Test("Text content exposes its text and no images")
    func textContent() {
        let content = ChatEntity.Content.text("hello")
        #expect(content.text == "hello")
        #expect(content.images.isEmpty)
    }

    @Test("A single image is modelled as images without accompanying text")
    func imageContent() {
        let url = URL(string: "https://grove.stanford.edu/image.png")!
        let content = ChatEntity.Content.image(.url(url))
        #expect(content.text == nil)
        #expect(content.images == [.url(url)])
    }

    @Test("Images and text can travel together in one message")
    func multipartContent() {
        let url = URL(string: "https://grove.stanford.edu/image.png")!
        let content = ChatEntity.Content.images([.url(url)], text: "what is this?")
        #expect(content.text == "what is this?")
        #expect(content.images.count == 1)
    }

    @Test("Every role has a distinct raw value")
    func roleRawValues() {
        let roles: [ChatEntity.Role] = [
            .user,
            .assistant(.response),
            .assistant(.toolCall),
            .assistant(.toolResponse),
            .assistant(.thinking(startDate: nil, endDate: nil)),
            .hidden(type: .unknown)
        ]
        #expect(Set(roles.map(\.rawValue)).count == roles.count)
    }

    @Test("Text entities round-trip through Codable")
    func textCodableRoundTrip() throws {
        let entity = ChatEntity(role: .assistant(.response), text: "hello", complete: false)
        let decoded = try roundTrip(entity)
        #expect(decoded == entity)
    }

    @Test("Image URL entities round-trip through Codable")
    func imageURLCodableRoundTrip() throws {
        let url = URL(string: "https://grove.stanford.edu/image.png")!
        let entity = ChatEntity(role: .user, content: .images([.url(url)], text: "look"))
        let decoded = try roundTrip(entity)
        #expect(decoded == entity)
        #expect(decoded.content.text == "look")
    }

    @Test("In-memory image entities round-trip through Codable")
    func inMemoryImageCodableRoundTrip() throws {
        let entity = ChatEntity(role: .user, content: .images([.image(Self.testImage())], text: "look"))
        let decoded = try roundTrip(entity)
        #expect(decoded.content.text == "look")
        guard case .image(let image) = try #require(decoded.content.images.first) else {
            Issue.record("Expected an in-memory image after decoding")
            return
        }
        #expect(image.pngData() != nil)
    }

    @Test("A thinking role round-trips with its dates intact")
    func thinkingCodableRoundTrip() throws {
        let start = Date(timeIntervalSince1970: 1_000)
        let end = Date(timeIntervalSince1970: 1_042)
        let entity = ChatEntity(role: .assistant(.thinking(startDate: start, endDate: end)), text: "hmm")
        let decoded = try roundTrip(entity)
        guard case let .assistant(.thinking(decodedStart, decodedEnd)) = decoded.role else {
            Issue.record("Expected a thinking role, got \(decoded.role)")
            return
        }
        #expect(decodedStart == start)
        #expect(decodedEnd == end)
    }

    @Test("Content carrying neither text nor images fails to decode")
    func decodingEmptyContentFails() {
        let json = Data("{}".utf8)
        #expect(throws: (any Error).self) {
            try JSONDecoder().decode(ChatEntity.Content.self, from: json)
        }
    }

    /// Round-trips with the default date strategy, which preserves sub-second precision and so keeps the
    /// comparison about the entity rather than about date formatting.
    private func roundTrip(_ entity: ChatEntity) throws -> ChatEntity {
        try JSONDecoder().decode(ChatEntity.self, from: JSONEncoder().encode(entity))
    }
}
