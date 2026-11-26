# Generation Events

<!--
#
# This source file is part of the Grove open-source project
#
# SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
#
# SPDX-License-Identifier: MIT
#
-->

Read the text of a generation together with the outcome and token usage of each provider request.

## Overview

Use a session that conforms to ``LLMGenerationSession`` to read text and the outcome of each provider request. Each call to ``LLMGenerationSession/generateEvents()`` starts one generation. Use one iterator per stream. Call ``LLMSession/generate()`` when you need only text; it runs the same generation and sends the same requests.

The following example works in a server task without UI isolation. It returns the terminal result for a stream that ends normally. A caller that needs failure details can retain the final event it receives before iteration throws.

```swift
import GroveLLM

@available(iOS 18, macOS 15, watchOS 11, *)
func generationResult(for session: any LLMGenerationSession) async throws -> LLMGenerationResult? {
    var result: LLMGenerationResult?
    for try await event in try await session.generateEvents() {
        if case .finished(let outcome) = event {
            result = outcome
        }
    }
    return result
}
```

A tool call finishes one request and leads to another. The generation finishes after the tool loop ends, and a request that ends with tool calls does not complete the generation. Request and attempt numbers start at one within each invocation. Retries share a request number. An unstreamed fallback starts a new request. Provider identifiers can correlate events with provider records.

Each usage field is optional. A reported zero is a measurement. A missing value means the provider supplied no measurement for that field. The generation total for a field is available only when every attempt reported it. These counts exclude hosted tool fees.

A provider output limit produces an incomplete result. A stream that ends without the provider's terminal marker fails after any text already delivered. A failed generation delivers its final event before the stream throws. A session buffers a bounded number of undelivered events and throws ``LLMGenerationStreamError/bufferOverflow`` when the consumer falls behind further; the OpenAI session buffers 256 events. Cancellation or overflow can prevent delivery of the final event. When that event is absent, the outcome is unknown. Cancelling iteration stops the associated invocation. Explicit session cancellation applies to all its active generations.

## Topics

### Events

- ``LLMGenerationSession``
- ``LLMGenerationEvent``
- ``LLMGenerationStreamError``

### Results

- ``LLMGenerationResult``
- ``LLMRequestResult``
- ``LLMGenerationStatus``
- ``LLMFinishReason``
- ``LLMTokenUsage``
