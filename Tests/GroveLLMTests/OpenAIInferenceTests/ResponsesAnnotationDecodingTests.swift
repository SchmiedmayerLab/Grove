//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import Foundation
import GeneratedOpenAIClient
import Testing


/// Pins that a response carrying citations decodes.
///
/// `Annotation` is a discriminated union, and a union whose discriminator has no mapping matches on *schema name*
/// rather than on the `type` the wire actually sends. `annotations` is required on every piece of output text, so
/// getting that wrong does not lose the citation — it fails the whole response body, turning any answer that cites
/// a source into a generic generation error.
@Suite("Responses Annotation Decoding")
struct ResponsesAnnotationDecodingTests {
    @Test("A response whose text carries a URL citation decodes")
    func urlCitationDecodes() throws {
        var builder = ResponsesPayloadBuilder()
        builder.message(
            "Stanford's gateway runs LiteLLM.",
            citations: [
                ResponsesPayloadBuilder.urlCitation(
                    url: "https://uit.stanford.edu/service/api-gateway",
                    title: "AI API Gateway | University IT",
                    startIndex: 0,
                    endIndex: 31
                )
            ]
        )

        let response = try builder.response()

        let message = try #require(response.value3.output.first)
        guard case let .message(outputMessage) = message else {
            Issue.record("Expected an output message, got \(message)")
            return
        }
        let content = try #require(outputMessage.content.first)
        guard case let .output_text(text) = content else {
            Issue.record("Expected output text, got \(content)")
            return
        }
        let annotation = try #require(text.annotations.first)
        guard case let .url_citation(citation) = annotation else {
            Issue.record("The wire sends type \"url_citation\"; the union has to bind on that, got \(annotation)")
            return
        }
        #expect(citation.url == "https://uit.stanford.edu/service/api-gateway")
        #expect(citation.title == "AI API Gateway | University IT")
    }

    @Test("A response with no citations still decodes")
    func emptyAnnotationsDecode() throws {
        var builder = ResponsesPayloadBuilder()
        builder.message("No sources here.")

        let response = try builder.response()
        #expect(response.value3.output.count == 1)
    }
}
