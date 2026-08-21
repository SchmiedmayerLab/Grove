//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import Foundation
@testable import GroveChat
import SwiftUI
import Testing


/// Renders the chat bubble to images, so its geometry can be inspected rather than imagined.
///
/// The assertions hold the pieces a wrong path breaks — the render succeeding at the expected
/// scale — and every image is also written to `GROVE_SNAPSHOT_DIR` (or the temporary directory)
/// for review while iterating on the shape.
@Suite("Chat Bubble Snapshots")
@MainActor
struct ChatBubbleSnapshotTests {
    private static let snapshotDirectory: URL = {
        let base = ProcessInfo.processInfo.environment["GROVE_SNAPSHOT_DIR"]
            .map { URL(filePath: $0) }
            ?? FileManager.default.temporaryDirectory.appending(path: "GroveChatSnapshots")
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base
    }()

    @Test("A single message carries the tail")
    func singleMessage() throws {
        try snapshot("single-message", width: 320) {
            bubble("This is a test")
        }
    }

    @Test("Only the run's last message carries the tail")
    func groupedMessages() throws {
        try snapshot("grouped-messages", width: 320) {
            VStack(alignment: .trailing, spacing: 3) {
                bubble("This is a test", tail: false)
                bubble("And a longer test message\n\n>>>\n\n….")
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
    }

    @Test("The tail mirrors in a right-to-left layout")
    func rightToLeft() throws {
        try snapshot("right-to-left", width: 320) {
            bubble("This is a test")
                .environment(\.layoutDirection, .rightToLeft)
        }
    }

    @Test("A tailless bubble is a plain rounded rectangle")
    func tailless() throws {
        try snapshot("tailless", width: 320) {
            bubble("This is a test", tail: false)
        }
    }

    @Test("The raw shape, large enough to inspect")
    func rawShape() throws {
        try snapshot("raw-shape", width: 240) {
            ChatBubbleShape(cornerRadius: 18, tailEdge: .trailing)
                .fill(Color.blue)
                .frame(width: 200, height: 76)
        }
    }

    /// The bubble around a plain `Text`: these snapshots hold the bubble's geometry, not the message
    /// renderer, and a plain label also draws inside `ImageRenderer`'s single pass.
    private func bubble(_ text: String, tail: Bool = true) -> some View {
        Text(text)
            .chatMessageStyle(alignment: .trailing, tail: tail)
            .chatAccentColor(.blue)
    }

    private func snapshot(_ name: String, width: CGFloat, @ViewBuilder content: () -> some View) throws {
        let renderer = ImageRenderer(
            content: content()
                .frame(width: width, alignment: .trailing)
                .padding(8)
                .background(Color.white)
        )
        renderer.scale = 3
        let image = try #require(renderer.cgImage, "The bubble should render to an image.")
        #expect(image.width > Int(width) * 3, "The render should cover the asked-for width at 3×.")

        let destination = Self.snapshotDirectory.appending(path: "\(name).png")
        #if canImport(AppKit)
        let bitmap = NSBitmapImageRep(cgImage: image)
        try #require(bitmap.representation(using: .png, properties: [:])).write(to: destination)
        #else
        try #require(UIImage(cgImage: image).pngData()).write(to: destination)
        #endif
    }
}
