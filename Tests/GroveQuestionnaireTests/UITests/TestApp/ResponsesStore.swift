//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2022 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import Foundation
import GroveQuestionnaire
import GroveQuestionnaireFHIR
import struct ModelsR4.QuestionnaireResponse
import Observation


/// What a consuming app does with a finished questionnaire: convert it to FHIR and keep it.
@Observable
@MainActor
final class ResponsesStore {
    struct Entry: Identifiable {
        let id = UUID()
        /// The example the answers came from, which is more use here than the response's own id.
        let source: String
        let response: QuestionnaireResponse
    }

    private(set) var entries: [Entry] = []

    func record(_ responses: QuestionnaireResponses, from source: String) throws {
        entries.append(Entry(source: source, response: try QuestionnaireResponse(responses)))
    }

    func record(_ response: QuestionnaireResponse, from source: String) {
        entries.append(Entry(source: source, response: response))
    }
}
