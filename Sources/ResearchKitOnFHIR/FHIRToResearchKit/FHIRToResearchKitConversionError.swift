//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2022 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

@preconcurrency public import ModelsR4


/// An error that is thrown when translating a FHIR `Questionnaire` to an `ORKNavigableOrderedTask`
public enum FHIRToResearchKitConversionError: Error, CustomStringConvertible, Equatable {
    /// The parsed FHIR Questionnaire didn't contain any items.
    case noItems
    /// An unsupported operator was used.
    case unsupportedOperator(QuestionnaireItemOperator)
    /// An unsupported answer type was used.
    case unsupportedAnswer(QuestionnaireItemEnableWhen.AnswerX)
    /// No option was provided.
    case noOptions
    /// Encountered an invalid date when parsing the questionnaire.
    case invalidDate(FHIRPrimitive<FHIRDate>)
    case invalidDateBound(linkID: String)
    /// An item has no usable FHIR linkId.
    case missingLinkID
    /// Two items would produce the same ResearchKit step/result identifier.
    case duplicateLinkID(String)
    /// An item has no usable display/question text.
    case missingText(linkID: String)
    /// An item has no FHIR type value.
    case missingItemType(linkID: String?)
    /// ResearchKit has no faithful representation for the item type.
    case unsupportedItemType(QuestionnaireItemType, linkID: String)
    /// ResearchKit cannot faithfully collect more than one answer for this FHIR item type.
    case unsupportedRepeatedItem(QuestionnaireItemType, linkID: String)
    /// Presentation metadata contradicts the FHIR answer cardinality.
    case itemControlCardinalityConflict(linkID: String)
    /// A choice option or contained value set is incomplete.
    case invalidChoiceOption(linkID: String)
    /// A local answerValueSet does not resolve to exactly one contained ValueSet.
    case unresolvedContainedValueSet(String)
    /// Neither the Questionnaire canonical nor an explicit stable task identifier was supplied.
    case missingTaskIdentifier
    /// A Questionnaire canonical cannot be used as a stable versioned task identity.
    case invalidTaskCanonical(String)
    
    
    public var description: String {
        switch self {
        case .noItems:
            return "The parsed FHIR Questionnaire didn't contain any items"
        case let .unsupportedOperator(fhirOperator):
            return "An unsupported operator was used: \(fhirOperator)"
        case let .unsupportedAnswer(answer):
            return "An unsupported answer type was used: \(answer)"
        case .noOptions:
            return "No option was provided"
        case let .invalidDate(date):
            return "Encountered an invalid date when parsing the questionnaire: \(date)"
        case .invalidDateBound(let linkID):
            return "Questionnaire item '\(linkID)' has a date bound that cannot be represented"
        case .missingLinkID:
            return "A Questionnaire item has no usable linkId"
        case .duplicateLinkID(let linkID):
            return "Questionnaire linkId '\(linkID)' is not globally unique"
        case .missingText(let linkID):
            return "Questionnaire item '\(linkID)' has no usable text"
        case .missingItemType(let linkID):
            return "Questionnaire item '\(linkID ?? "<unknown>")' has no type"
        case let .unsupportedItemType(type, linkID):
            return "Questionnaire item '\(linkID)' has unsupported type '\(type.rawValue)'"
        case let .unsupportedRepeatedItem(type, linkID):
            return "Questionnaire item '\(linkID)' repeats '\(type.rawValue)' answers, which ResearchKit cannot collect faithfully"
        case .itemControlCardinalityConflict(let linkID):
            return "Questionnaire item '\(linkID)' uses check-box control but does not allow repeated answers"
        case .invalidChoiceOption(let linkID):
            return "Questionnaire item '\(linkID)' has an incomplete choice option"
        case .unresolvedContainedValueSet(let canonical):
            return "Questionnaire answerValueSet '\(canonical)' does not resolve to one contained ValueSet"
        case .missingTaskIdentifier:
            return "A Questionnaire without a canonical URL requires an explicit stable task identifier"
        case .invalidTaskCanonical(let canonical):
            return "Questionnaire canonical '\(canonical)' cannot be used as a stable task identifier"
        }
    }
}
