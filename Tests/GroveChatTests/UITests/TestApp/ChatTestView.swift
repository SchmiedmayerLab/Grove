//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2023 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import Foundation
import GroveChat
import SwiftUI


struct ChatTestView: View {
    @State private var chat: Chat = ProcessInfo.processInfo.arguments.contains("--emptyChat") ? [] : [
        ChatEntity(role: .hidden(type: .unknown), text: "Hidden Message!"),
        ChatEntity(role: .user, content: .images([.image(ChatTestView.generatedImage())], text: "What do you make of this?")),
        ChatEntity(role: .assistant(.response), text: "**Assistant** Message!")
    ]
    @State private var muted = true
    @State private var isGenerating = false
    @State private var lastError: (any Error)?
    @State private var generationTask: Task<Void, Never>?


    var body: some View {
        ChatView(
            $chat,
            exportFormat: .pdf,
            messagePendingAnimation: .automatic
        )
            .chatMessageActions(.all)
            .chatEmptyState(
                "Ask Me Anything",
                description: "Try “think”, “weather”, “draw”, “fib”, or “fail”."
            )
            .chatGenerating(isGenerating) {
                generationTask?.cancel()
            }
            .chatError(lastError) {
                lastError = nil
                if let message = chat.last(where: { $0.role == .user }) {
                    respond(to: message)
                }
            }
            .speak(chat, muted: muted)
            .speechToolbarButton(muted: $muted)
            .navigationTitle("GroveChat")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("New Chat", systemImage: "square.and.pencil") {
                        generationTask?.cancel()
                        lastError = nil
                        chat = []
                    }
                }
            }
            .onChange(of: chat) { _, newValue in
                guard let message = newValue.last, message.role == .user else {
                    return
                }
                respond(to: message)
            }
    }

    /// Answers a message, reporting the generation state and any failure the way a real chat would.
    private func respond(to message: ChatEntity) {
        lastError = nil
        isGenerating = true
        generationTask = Task {
            defer { isGenerating = false }
            do {
                try await generateAssistantMessage(for: message)
            } catch is CancellationError {
                // The user stopped it; what arrived stands.
            } catch {
                lastError = error
            }
        }
    }

    private func generateAssistantMessage(for userMessage: ChatEntity) async throws { // swiftlint:disable:this function_body_length
        let prompt = userMessage.content.text ?? ""
        try await Task.sleep(for: .seconds(3))
        if prompt.localizedCaseInsensitiveContains("call") {
            chat.append(.init(role: .assistant(.toolCall), text: "call_test_func({ test: true })"))
            try await Task.sleep(for: .seconds(1))
            chat.append(.init(role: .assistant(.toolResponse), text: "{ some: response }"))
            try await Task.sleep(for: .seconds(1))
            chat.append(.init(role: .assistant(.response), text: "**Assistant** Message Response!"))
        } else if prompt.localizedCaseInsensitiveContains("think") {
            let start = Date.now
            let thinkingId = UUID()
            chat.append(.init(
                role: .assistant(.thinking(startDate: start, endDate: nil)),
                text: "",
                complete: false,
                id: thinkingId
            ))
            try await Task.sleep(for: .seconds(2))
            if let index = chat.firstIndex(where: { $0.id == thinkingId }) {
                chat[index].role = .assistant(.thinking(startDate: start, endDate: .now))
                chat[index].content = .text("I considered the question, and then I answered it.")
                chat[index].complete = true
            }
            chat.append(.init(role: .assistant(.response), text: "**Assistant** Message Response!"))
        } else if prompt.localizedCaseInsensitiveContains("weather") {
            chat.append(.init(role: .assistant(.response), text: """
                Here's the current weather snapshot:

                | City | Temp | Condition |
                |------|------|-----------|
                | 🇩🇪 Munich | 41°F / 5°C | ❄️ Snow |
                | 🇦🇹 Vienna | 42°F / 5°C | ☁️ Cloudy |
                | 🇺🇸 San Francisco | 44°F / 7°C | ☁️ Cloudy |
                | 🇬🇧 London | 55°F / 13°C | ☁️ Cloudy |
                | 🇺🇸 New York City | 35°F / 2°C | ☀️ Sunny |
                | 🇳🇴 Svalbard | 0°F / -18°C | 🌤️ Partly Sunny |
                | 🇿🇦 Cape Town | 70°F / 21°C | 🌤️ Partly Sunny |
                | 🇯🇵 Tokyo | — | ⚠️ Data unavailable |
                | 🇨🇦 Toronto | 33°F / 1°C | ☁️ Cloudy |
                | 🇫🇷 Paris | 56°F / 13°C | ☁️ Cloudy |

                Tokyo's weather data returned an error — you may want to check a weather service directly for that one.
                """))
        } else if prompt.localizedCaseInsensitiveContains("sources") {
            chat.append(.init(
                role: .assistant(.response),
                content: .text("Reykjavík is the capital of Iceland."),
                citations: [
                    .init(title: "Reykjavík — Wikipedia", source: .web(URL(string: "https://en.wikipedia.org/wiki/Reykjav%C3%ADk")!)),
                    .init(title: "Iceland | University IT", source: .web(URL(string: "https://uit.stanford.edu/iceland")!)),
                    .init(title: "atlas.pdf", source: .file(name: "atlas.pdf"))
                ]
            ))
        } else if prompt.localizedCaseInsensitiveContains("attach") {
            chat.append(.init(
                role: .user,
                content: .init([.init(.file(Self.fixtureFile()), label: "A short test document")])
            ))
            try await Task.sleep(for: .seconds(1))
            chat.append(.init(role: .assistant(.response), text: "**Assistant** Message Response!"))
        } else if prompt.localizedCaseInsensitiveContains("draw") {
            chat.append(.init(
                role: .assistant(.response),
                content: .images([.image(Self.generatedImage())], text: "Here's what I came up with.")
            ))
        } else if prompt.localizedCaseInsensitiveContains("fail") {
            throw ChatTestError.generationFailed
        } else if prompt.localizedCaseInsensitiveContains("fib") {
            chat.append(.init(role: .assistant(.response), text: """
                ```rust
                fn fib(n: u64) -> u64 {
                    match n {
                        0 | 1 => n,
                        _ => fib(n - 1) + fib(n - 2)
                    }
                }
                ```
                """))
        } else {
            chat.append(.init(role: .assistant(.response), text: "**Assistant** Message Response!"))
        }
    }

    /// A real file on disk, so the chip and the Quick Look preview have something to work with.
    ///
    /// Written into the app's own container rather than shipped as a resource, which is also what the file picker
    /// produces: an app-owned copy the conversation can outlive the picker with.
    private static func fixtureFile() -> ChatEntity.Content.File {
        let url = URL.applicationSupportDirectory.appending(path: "fixture.txt")
        if !FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) {
            try? FileManager.default.createDirectory(
                at: .applicationSupportDirectory,
                withIntermediateDirectories: true
            )
            try? Data("A short test document, so the preview has something to show.".utf8).write(to: url)
        }
        return ChatEntity.Content.File(name: "fixture.txt", url: url, contentTypeIdentifier: "public.plain-text")
    }

    /// Stands in for an image the assistant produced, without shipping an asset with the test app.
    private static func generatedImage() -> PlatformImage {
        UIGraphicsImageRenderer(size: CGSize(width: 1024, height: 640)).image { context in
            let gradient = CGGradient(
                colorsSpace: CGColorSpaceCreateDeviceRGB(),
                colors: [UIColor.systemIndigo.cgColor, UIColor.systemTeal.cgColor] as CFArray,
                locations: [0, 1]
            )
            if let gradient {
                context.cgContext.drawLinearGradient(
                    gradient,
                    start: .zero,
                    end: CGPoint(x: 1024, y: 640),
                    options: []
                )
            }
        }
    }
}


#if DEBUG
#Preview {
    NavigationStack {
        ChatTestView()
    }
}
#endif


/// Stands in for whatever a real chat's inference layer would throw.
private enum ChatTestError: LocalizedError {
    case generationFailed

    var errorDescription: String? {
        switch self {
        case .generationFailed: "The assistant could not be reached. Check your connection and try again."
        }
    }
}
