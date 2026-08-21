//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

private import CryptoKit
public import Foundation
public import GroveFHIRContract
public import GroveQuestionnaire
public import ModelsR4


/// An error that occurred when converting a Grove `QuestionnaireResponses` object into a FHIR R4 `QuestionnaireResponse`
struct FHIRResponseConversionError: LocalizedError {
    let errorDescription: String?
    
    init(_ message: String) {
        errorDescription = message
    }
}


@available(iOS 18, macOS 15, watchOS 11, *)
extension GroveQuestionnaire.QuestionnaireResponses {
    /// A custom response value that can be expressed as one or more FHIR R4 `QuestionnaireResponseItemAnswer`
    public protocol CustomResponseValueProtocolWithFHIRSupport: CustomResponseValueProtocol { // swiftlint:disable:this type_name
        /// Generates a FHIR R4 [`QuestionnaireResponseItemAnswer`](https://build.fhir.org/questionnaireresponse-definitions.html#QuestionnaireResponse.item.answer) for this custom value.
        ///
        /// - throws: If the response was invalid, or there was some other error turning it into a `ModelsR4.QuestionnaireResponseItemAnswer`.
        /// - returns: An array of `ModelsR4.QuestionnaireResponseItemAnswer` objects, which will be inserted into the `ModelsR4.QuestionnaireResponse` to which this response belongs.
        ///     In most cases this array should contain only a single element, but if the custom response represents multiple actual responses, it should contain one element per response.
        func toFHIR(
            for task: GroveQuestionnaire.Questionnaire.Task
        ) throws -> [ModelsR4.QuestionnaireResponseItemAnswer]
    }
}


@available(iOS 18, macOS 15, watchOS 11, *)
extension ModelsR4.QuestionnaireResponse {
    private static var electronicCompletionMode: Extension {
        Extension(
            url: "http://hl7.org/fhir/StructureDefinition/questionnaireresponse-completionMode",
            value: .codeableConcept(CodeableConcept(coding: [
                Coding(
                    code: "ELECTRONIC".asFHIRStringPrimitive(),
                    display: "electronic data".asFHIRStringPrimitive(),
                    system: "http://terminology.hl7.org/CodeSystem/v3-ParticipationMode".asFHIRURIPrimitive()
                )
            ]))
        )
    }

    /// Creates a FHIR R4 `QuestionnaireResponse` from a Grove `QuestionnaireResponses`.
    ///
    /// The generated response mirrors the questionnaire's structure: answers within FHIR
    /// groups are wrapped in items carrying the group linkIds, and answers to questions
    /// nested beneath another question are nested beneath the parent's answer.
    ///
    /// - parameter other: The collected Grove responses to convert.
    /// - parameter subject: Who the answers are about (`QuestionnaireResponse.subject`),
    ///     typically a reference to the study participant.
    /// - parameter author: Who recorded the answers (`QuestionnaireResponse.author`).
    /// - parameter source: Who supplied the answers (`QuestionnaireResponse.source`).
    /// - parameter status: The response's lifecycle state; pass `.inProgress` when
    ///     exporting a partially answered draft.
    /// - parameter identifier: A business identifier for the response. By default,
    ///     Grove uses the questionnaire canonical as its system and the response UUID as its value.
    /// - parameter repositoryID: A repository-assigned logical id for the resource. Leave it `nil`
    ///     unless the caller already holds an id assignment from the receiving repository.
    /// - parameter authored: The stored instant at which the response was authored.
    ///     It is deliberately required so an exported resource never depends on a hidden clock.
    public init(
        _ other: GroveQuestionnaire.QuestionnaireResponses,
        subject: Reference? = nil,
        author: Reference? = nil,
        source: Reference? = nil,
        status: QuestionnaireResponseStatus = .completed,
        identifier: Identifier? = nil,
        repositoryID: GroveFHIRRepositoryID? = nil,
        authored: Date
    ) throws {
        try self.init(
            other,
            subject: subject,
            author: author,
            source: source,
            status: status,
            identifier: identifier,
            repositoryID: repositoryID,
            authored: authored,
            droppingUnconvertibleAnswers: false
        )
    }

    /// A best-effort, non-exportable snapshot of the answers so far, for expression evaluation.
    ///
    /// An answer that cannot be expressed in FHIR yet — a half-entered number in an
    /// integer item, say — is left out rather than failing the conversion, which would
    /// take every expression in the form down with it. This internal snapshot deliberately omits
    /// `authored`; expression evaluation must not read the wall clock or masquerade as an export.
    init(evaluating responses: GroveQuestionnaire.QuestionnaireResponses) throws {
        try self.init(
            responses,
            status: .inProgress,
            identifier: nil,
            repositoryID: nil,
            authored: nil,
            droppingUnconvertibleAnswers: true
        )
    }

    private init(
        _ other: GroveQuestionnaire.QuestionnaireResponses,
        subject: Reference? = nil,
        author: Reference? = nil,
        source: Reference? = nil,
        status: QuestionnaireResponseStatus,
        identifier: Identifier?,
        repositoryID: GroveFHIRRepositoryID?,
        authored: Date?,
        droppingUnconvertibleAnswers: Bool
    ) throws {
        self.init(status: .init(status))
        if !droppingUnconvertibleAnswers {
            self.meta = Meta(profile: [GroveFHIRProfile.groveQuestionnaireResponse])
            self.id = repositoryID?.primitive
        }
        if let authored {
            self.authored = try FHIRPrimitive(DateTime(date: authored))
        }
        self.subject = subject
        self.author = author
        self.source = source
        if !droppingUnconvertibleAnswers {
            self.extension = [Self.electronicCompletionMode]
            guard let url = other.questionnaire.metadata.url else {
                throw GroveQuestionnaireFHIRContractError.missingQuestionnaireURL
            }
            guard let version = other.questionnaire.metadata.version else {
                throw GroveQuestionnaireFHIRContractError.missingQuestionnaireVersion
            }
            guard GroveQuestionnaireFHIRContract.isSemanticVersion(version) else {
                throw GroveQuestionnaireFHIRContractError.invalidQuestionnaireVersion(version)
            }
            let canonical = "\(url.absoluteString)|\(version)"
            guard !url.absoluteString.contains("|"),
                  !url.absoluteString.contains("#"),
                  !version.contains("|"),
                  !version.contains("#") else {
                throw GroveQuestionnaireFHIRContractError.invalidQuestionnaireCanonical(canonical)
            }
            self.questionnaire = FHIRPrimitive(Canonical(stringLiteral: canonical))
            let responseIdentifier = identifier ?? Identifier(
                system: url.asFHIRURIPrimitive(),
                value: other.id.uuidString.lowercased().asFHIRStringPrimitive()
            )
            do {
                _ = try GroveFHIRBusinessIdentifier(responseIdentifier)
            } catch {
                throw GroveQuestionnaireFHIRContractError.incompleteResponseIdentifier
            }
            self.identifier = responseIdentifier
        }
        let items = try Self.items(for: other, droppingUnconvertibleAnswers: droppingUnconvertibleAnswers)
        // An empty `item` array is invalid FHIR JSON; omit the element instead.
        self.item = items.isEmpty ? nil : items
    }

    /// The response items for the questionnaire's sections, in section order.
    private static func items(
        for other: GroveQuestionnaire.QuestionnaireResponses,
        droppingUnconvertibleAnswers: Bool
    ) throws -> [QuestionnaireResponseItem] {
        var items: [QuestionnaireResponseItem] = []
        for section in other.questionnaire.sections {
            let sectionItems = try other.responses.toFHIR(section: section, droppingUnconvertibleAnswers: droppingUnconvertibleAnswers)
            guard !sectionItems.isEmpty else {
                continue
            }
            if let groupId = section.fhirGroupId {
                // The section mirrors a FHIR group: wrap its answers in the group's item.
                var wrapper = QuestionnaireResponseItem(linkId: groupId.asFHIRStringPrimitive())
                if !section.title.isEmpty {
                    wrapper.text = section.title.asFHIRStringPrimitive()
                }
                wrapper.item = sectionItems
                items.append(wrapper)
            } else {
                items.append(contentsOf: sectionItems)
            }
        }
        return items
    }
}


@available(iOS 18, macOS 15, watchOS 11, *)
extension QuestionnaireResponses.Responses {
    struct FHIRConversionContext {
        /// All tasks in the questionnaire, in the current context.
        ///
        /// For non-nested tasks, this simply contains all root-level tasks in the questionnaire.
        /// For nested tasks, this contains all nested tasks for the nested task's parent task.
        let allTasks: [GroveQuestionnaire.Questionnaire.Task]
    }

    /// Builds the flat response items for a set of tasks (used for choice-option
    /// follow-up responses, which FHIR nests beneath the selected answer).
    func toFHIR(using context: FHIRConversionContext) throws -> [QuestionnaireResponseItem] {
        let items = try self.compactMap { taskId, response in
            guard let task = context.allTasks.first(where: { $0.id == taskId }) else {
                throw FHIRResponseConversionError("Unable to find task '\(taskId)'")
            }
            return try response.toFHIR(using: .init(task: task))
        }
        // sort the items by task
        let tasksIdsByOverallPosition: [String: Int] = context.allTasks
            .enumerated()
            .reduce(into: [:]) { $0[$1.element.id] = $1.offset }
        return try items.sorted { lhs, rhs in
            let lhsLinkId = try lhs.getLinkId()
            let rhsLinkId = try rhs.getLinkId()
            return tasksIdsByOverallPosition[lhsLinkId]! < tasksIdsByOverallPosition[rhsLinkId]! // swiftlint:disable:this force_unwrapping
        }
    }

    /// Builds the response items for one section, restoring the questionnaire's structure:
    /// nested-group wrappers from each task's ``Questionnaire/Task/groupPath``, and
    /// child-question answers beneath their parent per ``Questionnaire/Task/parentTaskId``.
    fileprivate func toFHIR(
        section: GroveQuestionnaire.Questionnaire.Section,
        droppingUnconvertibleAnswers: Bool = false
    ) throws -> [QuestionnaireResponseItem] {
        let items = try flatItems(for: section, droppingUnconvertibleAnswers: droppingUnconvertibleAnswers)
        let nested = attachingChildItems(to: items, in: section)
        return groupWrappedItems(nested, in: section)
    }

    /// The flat response item of every responded task in the section, keyed by task id.
    private func flatItems(
        for section: GroveQuestionnaire.Questionnaire.Section,
        droppingUnconvertibleAnswers: Bool
    ) throws -> [String: QuestionnaireResponseItem] {
        var itemsByTaskId: [String: QuestionnaireResponseItem] = [:]
        for task in section.tasks {
            do {
                // The subscript yields an empty response for unanswered tasks; toFHIR maps those to nil.
                if let item = try self[task.id].toFHIR(using: .init(task: task)) {
                    itemsByTaskId[task.id] = item
                }
            } catch {
                guard droppingUnconvertibleAnswers else {
                    throw error
                }
            }
        }
        return itemsByTaskId
    }

    /// Attaches child-question items beneath their parent (FHIR: in context of the answer).
    ///
    /// Children are processed deepest-first so grandchildren are attached before their
    /// parent is itself attached elsewhere.
    private func attachingChildItems(
        to items: [String: QuestionnaireResponseItem],
        in section: GroveQuestionnaire.Questionnaire.Section
    ) -> [String: QuestionnaireResponseItem] {
        var itemsByTaskId = items
        for task in section.tasks.reversed() {
            guard let parentId = task.parentTaskId, let childItem = itemsByTaskId.removeValue(forKey: task.id) else {
                continue
            }
            // A parent without an answer of its own (e.g. an optional question that was
            // skipped while an unconditional child was answered) carries the children on an
            // answerless parent item, which FHIR permits.
            var parent = itemsByTaskId[parentId] ?? QuestionnaireResponseItem(linkId: parentId.asFHIRStringPrimitive())
            if var answers = parent.answer, !answers.isEmpty {
                answers[0].item = (answers[0].item ?? []) + [childItem]
                parent.answer = answers
            } else {
                parent.item = (parent.item ?? []) + [childItem]
            }
            itemsByTaskId[parentId] = parent
        }
        return itemsByTaskId
    }

    /// Assembles the items in task order, restoring the nested-group wrappers each task's
    /// ``Questionnaire/Task/groupPath`` names.
    private func groupWrappedItems(
        _ itemsByTaskId: [String: QuestionnaireResponseItem],
        in section: GroveQuestionnaire.Questionnaire.Section
    ) -> [QuestionnaireResponseItem] {
        var result: [QuestionnaireResponseItem] = []
        // Stack of currently open group wrappers, outermost first.
        var openGroups: [(linkId: String, item: QuestionnaireResponseItem)] = []
        func close(downTo depth: Int) {
            while openGroups.count > depth {
                let closed = openGroups.removeLast()
                if openGroups.isEmpty {
                    result.append(closed.item)
                } else {
                    var parent = openGroups.removeLast()
                    parent.item.item = (parent.item.item ?? []) + [closed.item]
                    openGroups.append(parent)
                }
            }
        }
        for task in section.tasks where task.parentTaskId == nil {
            guard let item = itemsByTaskId[task.id] else {
                continue
            }
            // Find the shared prefix between the open groups and this task's path.
            let path = task.groupPath
            var shared = 0
            while shared < Swift.min(openGroups.count, path.count), openGroups[shared].linkId == path[shared].id {
                shared += 1
            }
            close(downTo: shared)
            for group in path[shared...] {
                var wrapper = QuestionnaireResponseItem(linkId: group.id.asFHIRStringPrimitive())
                if !group.title.isEmpty {
                    // A QuestionnaireResponse group item carries the group's text, never its enableWhen.
                    wrapper.text = group.title.asFHIRStringPrimitive()
                }
                openGroups.append((group.id, wrapper))
            }
            if var last = openGroups.popLast() {
                last.item.item = (last.item.item ?? []) + [item]
                openGroups.append(last)
            } else {
                result.append(item)
            }
        }
        close(downTo: 0)
        return result
    }
}


@available(iOS 18, macOS 15, watchOS 11, *)
extension GroveQuestionnaire.Questionnaire.Task.Kind.ChoiceConfig.Option {
    func toFHIRCoding() -> Coding {
        var coding = if let fhirCoding {
            Coding(
                code: fhirCoding.code.asFHIRStringPrimitive(),
                display: title.asFHIRStringPrimitive(),
                system: fhirCoding.system.asFHIRURIPrimitive()
            )
        } else {
            Coding(
                code: id.asFHIRStringPrimitive(),
                display: title.asFHIRStringPrimitive(),
                system: nil
            )
        }
        if let weight {
            // Carry the definitional weight onto the answer so consumers can score
            // responses without resolving the questionnaire.
            coding.extension = [
                Extension(
                url: "http://hl7.org/fhir/StructureDefinition/itemWeight",
                value: .decimal(FHIRPrimitive(FHIRDecimal(weight)))
            )
            ]
        }
        return coding
    }

    /// The FHIR answer value for a selected option, typed to match the
    /// `answerOption` the option was created from.
    func toFHIRAnswerValue() throws -> QuestionnaireResponseItemAnswer.ValueX {
        switch answerValue {
        case .string(let string):
            return .string(string.asFHIRStringPrimitive())
        case .integer(let integer):
            guard let value = Int32(exactly: integer) else {
                throw FHIRResponseConversionError("Integer answer option out of range")
            }
            return .integer(FHIRPrimitive(FHIRInteger(value)))
        case .date(let components):
            guard let year = components.year else {
                throw FHIRResponseConversionError("Date answer option is missing a year")
            }
            return .date(FHIRPrimitive(FHIRDate(
                year: year,
                month: components.month.map(numericCast),
                day: components.day.map(numericCast)
            )))
        case .time(let components):
            return .time(FHIRPrimitive(FHIRTime(
                hour: components.hour.map(numericCast) ?? 0,
                minute: components.minute.map(numericCast) ?? 0,
                second: components.second.map { Decimal($0) } ?? 0
            )))
        case nil:
            return .coding(toFHIRCoding())
        }
    }
}


extension QuestionnaireResponseItem {
    fileprivate func getLinkId() throws -> String {
        if let linkId = linkId.value?.string {
            return linkId
        } else {
            throw FHIRResponseConversionError("Unable to get linkId")
        }
    }
}


@available(iOS 18, macOS 15, watchOS 11, *)
extension QuestionnaireResponseItemAnswer {
    init(_ attachment: QuestionnaireResponses.CollectedAttachment) throws {
        // Mapped loading keeps large attachments from being copied wholesale into memory
        // before encoding.
        let data = try Data(contentsOf: attachment.url, options: .mappedIfSafe)
        let sha1 = Insecure.SHA1.hash(data: data)
        self.init(value: .attachment(.init(
            // att-1: inline data requires a contentType; fall back to the generic binary
            // type when the UTType lookup cannot produce a MIME type.
            contentType: (attachment.contentType?.preferredMIMEType ?? "application/octet-stream").asFHIRStringPrimitive(),
//                        creation: <#T##FHIRPrimitive<DateTime>?#>, // not easy bc eg an imported photo/file will likely not be brand new...
            data: FHIRPrimitive(Base64Binary(data.base64EncodedString())),
            hash: FHIRPrimitive(Base64Binary(Data(sha1).base64EncodedString())),
            id: attachment.id.uuidString.asFHIRStringPrimitive(),
            size: data.count.asFHIRUnsignedIntegerPrimitive(),
            title: attachment.filename.asFHIRStringPrimitive(),
        )))
    }
}
