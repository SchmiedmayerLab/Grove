//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

@testable import GroveLLM
import Testing


@Suite("LLMContext generated images")
struct LLMContextImageTests {
    private let picture = LLMContextEntity._ImageContent(contentType: "image/png", base64Image: "aGVsbG8=")

    @Test("An announced picture keeps its place and identity when it is filled in")
    func completesTheAnnouncedPicture() {
        var context = LLMContext()
        let interaction = LLMInteractionId()
        context.append(assistantOutputDelta: "Here it is:", isComplete: true, interactionId: interaction)
        context.append(assistantImage: .generating, interactionId: interaction)
        let placeholder = context[context.count - 1]
        context.append(assistantOutputDelta: "Anything else?", isComplete: true, interactionId: interaction)

        context.complete(assistantImage: picture, interactionId: interaction)

        #expect(context.count == 3)
        #expect(context[1].id == placeholder.id)
        #expect(context[1]._imageContent == picture)
        #expect(context.chat[1].content.parts.map(\.content).first != .image(.generating))
    }

    @Test("A picture nobody announced is appended")
    func appendsAnUnannouncedPicture() {
        var context = LLMContext()
        context.complete(assistantImage: picture)
        #expect(context.count == 1)
        #expect(context[0]._imageContent == picture)
    }

    @Test("An interrupted interaction takes its announced pictures with it")
    func removesAnnouncedPicturesOfAnInterruptedInteraction() {
        var context = LLMContext()
        let interaction = LLMInteractionId()
        context.append(assistantImage: picture)
        context.append(assistantImage: .generating, interactionId: interaction)
        context.removeGeneratingImages(for: interaction)
        #expect(context.count == 1)
        #expect(context[0]._imageContent == picture)
    }

    @Test("A picture still being drawn reaches the chat as a placeholder")
    func surfacesTheGeneratingState() {
        var context = LLMContext()
        context.append(assistantImage: .generating)
        #expect(context.chat[0].content.parts.map(\.content) == [.image(.generating)])
    }
}
