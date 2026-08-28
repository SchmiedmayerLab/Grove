//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2022 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

#if ResearchKit

public import Foundation
public import ModelsR4
public import ResearchKit


extension ORKNavigableOrderedTask {
    /// Create a `ORKNavigableOrderedTask` by parsing a FHIR `Questionnaire`. Throws a `FHIRToResearchKitConversionError` if an error happens during the parsing.
    /// - Parameters:
    ///  - title: The title of the questionnaire. If you pass in a `String` the translation overrides the title that might be provided in the FHIR `Questionnaire`.
    ///  - questionnaire: The FHIR `Questionnaire` used to create the `ORKNavigableOrderedTask`.
    ///  - evaluationInstant: The explicit instant used to resolve relative date bounds.
    ///  - evaluationTimeZone: The explicit time zone used to resolve date-only bounds.
    ///  - taskIdentifier: A caller-governed stable identifier required when `Questionnaire.url` is absent.
    ///  - completionStep: An optional `ORKCompletionStep` that can be displayed at the end of the ResearchKit survey.
    public convenience init(
        title: String? = nil,
        questionnaire: Questionnaire,
        evaluationInstant: Date,
        evaluationTimeZone: TimeZone,
        taskIdentifier: String? = nil,
        completionStep: ORKCompletionStep? = nil
    ) throws {
        guard questionnaire.item?.isEmpty == false else {
            throw FHIRToResearchKitConversionError.noItems
        }
        
        let id: String
        if let canonical = questionnaire.url?.value?.url.absoluteString {
            guard ResearchKitQuestionnaireCanonical.isValidURL(canonical) else {
                throw FHIRToResearchKitConversionError.invalidTaskCanonical(canonical)
            }
            guard let version = questionnaire.version?.value?.string,
                  ResearchKitQuestionnaireCanonical.isSemanticVersion(version) else {
                let invalidCanonical = if let version = questionnaire.version?.value?.string {
                    "\(canonical)|\(version)"
                } else {
                    canonical
                }
                throw FHIRToResearchKitConversionError.invalidTaskCanonical(
                    invalidCanonical
                )
            }
            id = "\(canonical)|\(version)"
        } else if let taskIdentifier,
                  taskIdentifier == taskIdentifier.trimmingCharacters(in: .whitespacesAndNewlines),
                  !taskIdentifier.isEmpty,
                  taskIdentifier.unicodeScalars.allSatisfy({ !CharacterSet.controlCharacters.contains($0) }) {
            id = taskIdentifier
        } else {
            throw FHIRToResearchKitConversionError.missingTaskIdentifier
        }
        
        // Convert each FHIR Questionnaire Item to an ORKStep
        var steps = try questionnaire.toORKSteps(
            titleOverride: title,
            evaluationInstant: evaluationInstant,
            evaluationTimeZone: evaluationTimeZone
        )
        
        // Add a completion step at the end of the task if defined
        if let completionStep = completionStep {
            steps.append(completionStep)
        }
        
        self.init(identifier: id, steps: steps)
        
        // If any questions have defined skip logic, convert to ResearchKit navigation rules
        try constructNavigationRules(for: questionnaire.flattenedItems)
    }
}


extension Questionnaire {
    /// All items in the questionnaire, flattened.
    /// - Note: individual items in the returned array may still contain nested items;
    ///     the purpose of this property is to easily be able to access all items in the questionnaire, without having to explicitly take any nesting into account.
    var flattenedItems: [QuestionnaireItem] {
        flattenedItems()
    }
    
    /// All directly answerable items in the questionnaire, flattened.
    /// - Note: individual items in the returned array may still contain nested items;
    ///     the purpose of this property is to easily be able to access all questions in the questionnaire, without having to explicitly take any nesting into account.
    var flattenedQuestions: [QuestionnaireItem] {
        flattenedItems { $0.type.value?.isDirectlyAnswerableQuestion == true }
    }
    
    /// Flattens all `QuestionnaireItem`s in the questionnaire into an array.
    /// - parameter predicate: A predicate for filtering which items should be included. By default, all items are included.
    ///     Note that excluding an item via the predicate will only exclude it from being added to the returned array.
    ///     Children of excluded items will still be considered and may be included in the returned value, if the predicate returns true.
    private func flattenedItems(
        filter predicate: (QuestionnaireItem) -> Bool = { _ in true }
    ) -> [QuestionnaireItem] {
        var retval: [QuestionnaireItem] = []
        func imp(_ item: QuestionnaireItem) {
            if predicate(item) {
                retval.append(item)
            }
            item.item?.forEach(imp)
        }
        item?.forEach(imp)
        return retval
    }

    /// One global preflight catches malformed hidden items and duplicate nested identifiers before
    /// rendering is allowed to omit hidden content or construct any ResearchKit object.
    func validateResearchKitItems() throws {
        var linkIDs: Set<String> = []
        func validate(_ item: QuestionnaireItem) throws {
            guard let linkID = item.linkId.value?.string,
                  !linkID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw FHIRToResearchKitConversionError.missingLinkID
            }
            guard linkIDs.insert(linkID).inserted else {
                throw FHIRToResearchKitConversionError.duplicateLinkID(linkID)
            }
            guard let type = item.type.value else {
                throw FHIRToResearchKitConversionError.missingItemType(linkID: linkID)
            }
            if item.repeats?.value?.bool == true {
                switch type {
                case .choice, .openChoice:
                    break
                default:
                    throw FHIRToResearchKitConversionError.unsupportedRepeatedItem(type, linkID: linkID)
                }
            }
            if item.itemControl == "check-box", item.repeats?.value?.bool != true {
                throw FHIRToResearchKitConversionError.itemControlCardinalityConflict(linkID: linkID)
            }
            if !item.hidden, type != .group {
                guard let text = item.text?.value?.string,
                      !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    throw FHIRToResearchKitConversionError.missingText(linkID: linkID)
                }
            }
            for child in item.item ?? [] {
                try validate(child)
            }
        }
        for item in self.item ?? [] {
            try validate(item)
        }
    }
}


extension QuestionnaireItemType {
    /// Whether the item type refers to a directly answerable question.
    public var isDirectlyAnswerableQuestion: Bool {
        switch self {
        case .group:
            false
        case .display:
            false
        case .question, .boolean, .decimal, .integer, .date, .dateTime, .time, .string, .text, .url,
                .choice, .openChoice, .attachment, .reference, .quantity:
            true
        }
    }
}
#endif
