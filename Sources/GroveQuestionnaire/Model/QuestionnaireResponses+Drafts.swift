//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

public import Foundation


@available(iOS 18, macOS 15, watchOS 11, *)
extension QuestionnaireResponses {
    /// A serializable snapshot of partially collected responses, so an interrupted
    /// questionnaire can be resumed instead of losing all progress.
    ///
    /// Drafts contain participant health data: persist them encrypted at rest (e.g. a
    /// file protected with `FileProtectionType.complete`) and delete them when the
    /// participant withdraws or the response is submitted.
    ///
    /// Attachments are referenced by their temporary file URL and survive only as long
    /// as those files do; custom question kinds must have `Codable` response values.
    public struct Draft: Codable, Hashable, Sendable {
        /// The id of the responses instance the draft was taken from.
        public let responsesId: UUID
        /// The ``Questionnaire/Metadata/id`` of the questionnaire being answered.
        public let questionnaireId: String
        /// The questionnaire's business version at capture time; a resumed draft must
        /// match, so answers never silently attach to a different instrument revision.
        public let questionnaireVersion: String?
        /// When the draft was taken.
        public let savedAt: Date
        let responses: EncodedResponses
    }

    /// An error occurring while taking or restoring a ``Draft``.
    public enum DraftError: Error, Equatable {
        /// The draft belongs to a different questionnaire (or version).
        case questionnaireMismatch
        /// The draft contains a response that cannot be serialized.
        case unsupportedResponseValue(taskId: String)
    }

    /// Restores previously collected responses from a draft.
    ///
    /// - Throws: ``DraftError/questionnaireMismatch`` when the draft was taken from a
    ///     different questionnaire or version.
    public convenience init(questionnaire: Questionnaire, resuming draft: Draft) throws {
        guard draft.questionnaireId == questionnaire.id,
              draft.questionnaireVersion == questionnaire.metadata.version else {
            throw DraftError.questionnaireMismatch
        }
        self.init(id: draft.responsesId, questionnaire: questionnaire)
        self.responses = try draft.responses.restored()
    }

    /// Takes a serializable snapshot of the current responses.
    public func draft() throws -> Draft {
        Draft(
            responsesId: id,
            questionnaireId: questionnaire.id,
            questionnaireVersion: questionnaire.metadata.version,
            savedAt: Date(),
            responses: try EncodedResponses(responses)
        )
    }
}


// MARK: Serialization

@available(iOS 18, macOS 15, watchOS 11, *)
extension QuestionnaireResponses {
    struct EncodedResponses: Codable, Hashable, Sendable {
        var entries: [String: EncodedResponse]

        init(_ responses: Responses) throws {
            entries = try responses.reduce(into: [:]) { result, entry in
                result[entry.key] = try EncodedResponse(entry.value, taskId: entry.key)
            }
        }

        func restored() throws -> Responses {
            var responses = Responses()
            for (taskId, encoded) in entries {
                if let response = try encoded.restored() {
                    responses[taskId] = response
                }
            }
            return responses
        }
    }

    struct EncodedResponse: Codable, Hashable, Sendable {
        enum EncodedValue: Codable, Hashable, Sendable {
            case string(String)
            case bool(Bool)
            case date(DateComponents)
            case number(Double)
            case quantity(Double, unitCode: String)
            case choice(selectedOptions: [String], freeTextOtherResponse: String?)
            /// Attachments survive by their temporary file location.
            case attachments([URL])
        }

        var value: EncodedValue
        var nestedResponses: [String: EncodedResponses]

        /// `nil` for an unanswered response — there is nothing to carry into the draft.
        init?(_ response: Response, taskId: String) throws {
            switch response.value {
            case .none:
                return nil
            case .string(let string):
                value = .string(string)
            case .bool(let bool):
                value = .bool(bool)
            case .date(let components):
                value = .date(components)
            case .number(let number):
                value = .number(number)
            case let .quantity(number, unitCode):
                value = .quantity(number, unitCode: unitCode)
            case .choice(let choice):
                value = .choice(
                    selectedOptions: choice.selectedOptions.sorted(),
                    freeTextOtherResponse: choice.freeTextOtherResponse
                )
            case .attachments(let attachments):
                value = .attachments(attachments.map(\.url))
            case .custom:
                // Custom values would need their own Codable bridge; refuse rather than
                // silently dropping the participant's answer.
                throw DraftError.unsupportedResponseValue(taskId: taskId)
            }
            nestedResponses = try response.nestedResponses.reduce(into: [:]) { result, entry in
                switch entry.key {
                case .choiceOption(let optionId):
                    result[optionId] = try EncodedResponses(entry.value)
                }
            }
        }

        func restored() throws -> Response? {
            let restoredValue: Response.Value
            switch value {
            case .string(let string):
                restoredValue = .string(string)
            case .bool(let bool):
                restoredValue = .bool(bool)
            case .date(let components):
                restoredValue = .date(components)
            case .number(let number):
                restoredValue = .number(number)
            case let .quantity(number, unitCode):
                restoredValue = .quantity(number, unitCode: unitCode)
            case let .choice(selectedOptions, freeTextOtherResponse):
                restoredValue = .choice(.init(
                    selectedOptions: Set(selectedOptions),
                    freeTextOtherResponse: freeTextOtherResponse
                ))
            case .attachments(let urls):
                // An attachment whose backing file is gone cannot be restored; drop the
                // answer (the participant re-attaches) rather than failing the resume.
                let attachments = urls.compactMap { try? CollectedAttachment(url: $0) }
                guard !attachments.isEmpty else {
                    return nil
                }
                restoredValue = .attachments(attachments)
            }
            var response = Response(value: restoredValue)
            for (optionId, nested) in nestedResponses {
                response.nestedResponses[.choiceOption(optionId)] = try nested.restored()
            }
            return response
        }
    }
}
