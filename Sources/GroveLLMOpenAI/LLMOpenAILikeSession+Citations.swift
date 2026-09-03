//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import Foundation
import GeneratedOpenAIClient
import GroveLLM


@available(iOS 18, macOS 15, watchOS 11, *)
extension LLMOpenAILikeSession {
    /// The citations carried by a decoded piece of output text.
    ///
    /// A citation's `start_index`/`end_index` are deliberately ignored. The API does not say whether they count
    /// UTF-8 bytes, UTF-16 units or scalars, and its own worked example disagrees with its prose about whether the
    /// end is inclusive — so positioning a marker by them would be a guess. Grove groups the sources instead,
    /// which needs no offset to be correct.
    static func citations(from annotations: [Components.Schemas.Annotation]) -> [LLMCitation] {
        annotations.compactMap { annotation in
            switch annotation {
            case .url_citation(let citation):
                guard let url = URL(string: citation.url) else {
                    return nil
                }
                return LLMCitation(title: citation.title, source: .web(url))
            case .file_citation(let citation):
                return LLMCitation(title: citation.filename, source: .file(name: citation.filename))
            case .container_file_citation(let citation):
                return LLMCitation(title: citation.filename, source: .file(name: citation.filename))
            case .file_path:
                // A pointer to a file the model wrote, not a source it drew on.
                return nil
            }
        }
    }

    /// The citations carried by a streamed `response.output_item.done` payload.
    ///
    /// The streamed path hand-parses events, so the annotations arrive as raw JSON rather than as decoded types.
    /// A finished item carries every annotation for that item at once, which is why this reads the item rather
    /// than following `response.output_text.annotation.added` event by event.
    /// The image a finished `image_generation_call` output item carries, if the item is one.
    ///
    /// The tool streams progress events of its own, but the finished picture only ever travels in this item: a base64
    /// payload in `result`, in the `output_format` the tool was asked for (PNG unless told otherwise).
    static func generatedImage(fromOutputItem item: [String: Any]) -> LLMContextEntity._ImageContent? {
        guard item["type"] as? String == "image_generation_call",
              item["status"] as? String ?? "completed" == "completed",
              let result = item["result"] as? String, !result.isEmpty else {
            return nil
        }
        let format = item["output_format"] as? String ?? "png"
        return .init(contentType: "image/\(format)", base64Image: result)
    }

    static func citations(fromOutputItem item: [String: Any]) -> [LLMCitation] {
        guard let content = item["content"] as? [[String: Any]] else {
            return []
        }
        return content
            .flatMap { part in part["annotations"] as? [[String: Any]] ?? [] }
            .compactMap(citation(fromAnnotation:))
    }

    /// One citation, from the raw JSON the stream delivers.
    private static func citation(fromAnnotation annotation: [String: Any]) -> LLMCitation? {
        switch annotation["type"] as? String {
        case "url_citation":
            guard let raw = annotation["url"] as? String, let url = URL(string: raw) else {
                return nil
            }
            let title = annotation["title"] as? String
            return LLMCitation(title: title ?? url.host() ?? raw, source: .web(url))
        case "file_citation", "container_file_citation":
            guard let filename = annotation["filename"] as? String else {
                return nil
            }
            return LLMCitation(title: filename, source: .file(name: filename))
        default:
            return nil
        }
    }
}
