//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

/// The response a Responses stream event carries. Fields of an unexpected type stay unknown.
struct ResponseEvent: Decodable {
    private enum CodingKeys: String, CodingKey {
        case response
    }

    let response: ResponseMetadata?

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        response = try? container.decodeIfPresent(ResponseMetadata.self, forKey: .response)
    }
}


struct ResponseMetadata: Decodable {
    struct Usage: Decodable {
        let inputTokens: Int?
        let outputTokens: Int?

        init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: Keys.self)
            inputTokens = try? container.decodeIfPresent(Int.self, forKey: .inputTokens)
            outputTokens = try? container.decodeIfPresent(Int.self, forKey: .outputTokens)
        }
    }

    private struct IncompleteDetails: Decodable {
        let reason: String?
    }

    private enum Keys: String, CodingKey {
        case id, model, usage
        case incompleteDetails = "incomplete_details"
        case inputTokens = "input_tokens"
        case outputTokens = "output_tokens"
    }

    let id: String?
    let model: String?
    let usage: Usage?
    let incompleteReason: String?

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: Keys.self)
        id = try? container.decodeIfPresent(String.self, forKey: .id)
        model = try? container.decodeIfPresent(String.self, forKey: .model)
        usage = try? container.decodeIfPresent(Usage.self, forKey: .usage)
        incompleteReason = (try? container.decodeIfPresent(IncompleteDetails.self, forKey: .incompleteDetails))?.reason
    }
}
