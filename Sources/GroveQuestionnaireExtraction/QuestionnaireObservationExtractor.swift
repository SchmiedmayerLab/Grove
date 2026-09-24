//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import Foundation
import GroveFHIRContract
import ModelsR4


/// Why a response cannot be projected into measurements.
///
/// Every refusal names the exact defect: a projection that guesses is worse than none, so an
/// instrument or response that leaves the extractor guessing does not project.
public enum ObservationExtractionError: Error, Equatable, Sendable {
    case responseNotCompleted(status: String)
    case responseAuthoredMissing
    case responseIdentifierMissing
    case versionedQuestionnaireCanonicalMissing
    case subjectMissing
    /// The response names an author other than its subject; Grove re-attributes nothing.
    case authorIsNotTheSubject
    /// The response names a source other than its subject; author and source are independent facts.
    case sourceIsNotTheSubject
    case contradictoryExtractionMarking(linkID: String)
    case itemCodeMissing(linkID: String)
    case answerMissing(linkID: String)
    /// A repeating item carried several answers; projecting one of them would lose the rest.
    case multipleAnswers(linkID: String)
    case unitMissing(linkID: String)
    case unitMismatch(linkID: String, expected: String, answered: String)
    case measurementNotInCatalog(linkID: String, system: String, code: String)
    /// The measurement is only ever effective over a Period, and a response states one authored
    /// instant; stating that instant as the effective time would invent a duration the answer never gave.
    case measurementRequiresEffectivePeriod(linkID: String, measurement: String)
    case componentNotInMeasurement(linkID: String, code: String)
    case componentIncomplete(measurement: String, missing: String)
    case unsupportedAnswer(linkID: String)
    case unsupportedRelationship(linkID: String, relationship: String)
    case answerNotInMeasurement(linkID: String, code: String)
    case incompleteWriterContext
    case writerContextMissing
    /// The instrument marks nothing for extraction, so there is no exchange event to state.
    case noExtractableMeasurements
}


/// One value extracted from an answered item, before identity and envelope are added.
enum ExtractedValue: Equatable {
    case quantity(Quantity)
    case components([Component])
    case codeableConcept(CodeableConcept)
    case boolean(Bool)

    /// One component's fixed code and the value answered for it.
    struct Component: Equatable {
        let code: CodingContract
        let value: Quantity
    }
}


/// One measurement the pair extracts to, bound to its catalog contract.
struct ExtractedMeasurement {
    let contract: MeasurementContract
    let value: ExtractedValue
    let categories: [CodeableConcept]
}


/// Walks a Questionnaire and its Response and extracts every marked measurement.
///
/// The walk is driven entirely by what the instrument declares: `observationExtract` markings,
/// `item.code`, unit declarations, and `definitionExtractValue` bindings. Nothing is inferred
/// from answer shapes alone, so an unmarked item never projects.
struct QuestionnaireObservationExtractor {
    let questionnaire: ModelsR4.Questionnaire
    let response: ModelsR4.QuestionnaireResponse

    private static func measurement(system: String, code: String) -> MeasurementContract? {
        (MeasurementCatalog.all + HealthKitMeasurementCatalog.all).first {
            $0.code.system == system && $0.code.code == code
        }
    }

    /// The item's one answer.
    ///
    /// A repeating item's further answers have no projection yet, and keeping only the first would
    /// silently drop what the participant answered.
    private static func singleAnswer(
        of item: ModelsR4.QuestionnaireResponseItem,
        linkID: String
    ) throws -> QuestionnaireResponseItemAnswer? {
        guard let answers = item.answer, answers.count > 1 else {
            return item.answer?.first
        }
        throw ObservationExtractionError.multipleAnswers(linkID: linkID)
    }

    func extract() throws -> [ExtractedMeasurement] {
        let status = response.status.value?.rawValue ?? ""
        guard status == "completed" || status == "amended" else {
            throw ObservationExtractionError.responseNotCompleted(status: status)
        }
        guard response.subject != nil else {
            throw ObservationExtractionError.subjectMissing
        }
        var extracted: [ExtractedMeasurement] = []
        for item in questionnaire.item ?? [] {
            try appendExtractions(
                from: item,
                answers: responseItem(linkID: item.linkId.value?.string, in: response.item ?? []),
                into: &extracted
            )
        }
        return extracted
    }

    // MARK: Item Walk

    private func appendExtractions(
        from item: ModelsR4.QuestionnaireItem,
        answers: ModelsR4.QuestionnaireResponseItem?,
        into extracted: inout [ExtractedMeasurement]
    ) throws {
        let linkID = item.linkId.value?.string ?? ""
        let marking = try item.extractionMarking()
        switch marking {
        case .standalone, .independent:
            extracted.append(try measurement(for: item, answers: answers, linkID: linkID))
        case .member, .derived:
            // SDC links these to a parent Observation; emitting them unlinked would misstate
            // the relationship, so they refuse until the linkage is implemented.
            throw ObservationExtractionError.unsupportedRelationship(
                linkID: linkID,
                relationship: marking == .member ? "member" : "derived"
            )
        case .component, nil:
            // A bare component marking has no parent Observation here; it is consumed by the
            // parent's walk below, so at this level only recursion remains.
            for child in item.item ?? [] {
                try appendExtractions(
                    from: child,
                    answers: responseItem(linkID: child.linkId.value?.string, in: answers?.item ?? []),
                    into: &extracted
                )
            }
        }
    }

    private func measurement(
        for item: ModelsR4.QuestionnaireItem,
        answers: ModelsR4.QuestionnaireResponseItem?,
        linkID: String
    ) throws -> ExtractedMeasurement {
        guard let coding = item.code?.first,
              let system = coding.system?.value?.url.absoluteString,
              let code = coding.code?.value?.string else {
            throw ObservationExtractionError.itemCodeMissing(linkID: linkID)
        }
        guard let contract = Self.measurement(system: system, code: code) else {
            throw ObservationExtractionError.measurementNotInCatalog(linkID: linkID, system: system, code: code)
        }
        guard contract.effective != .period else {
            throw ObservationExtractionError.measurementRequiresEffectivePeriod(linkID: linkID, measurement: contract.id)
        }
        let value: ExtractedValue
        if contract.components.isEmpty {
            guard let answers else {
                throw ObservationExtractionError.answerMissing(linkID: linkID)
            }
            value = try scalarValue(for: item, answers: answers, contract: contract, linkID: linkID)
        } else {
            value = try componentValue(for: item, answers: answers, contract: contract)
        }
        return ExtractedMeasurement(
            contract: contract,
            value: value,
            categories: item.extractionCategories
        )
    }

    // MARK: Values

    private func scalarValue(
        for item: ModelsR4.QuestionnaireItem,
        answers: ModelsR4.QuestionnaireResponseItem,
        contract: MeasurementContract,
        linkID: String
    ) throws -> ExtractedValue {
        guard let answer = try Self.singleAnswer(of: answers, linkID: linkID) else {
            throw ObservationExtractionError.answerMissing(linkID: linkID)
        }
        switch answer.value {
        case .quantity(let quantity):
            return .quantity(try validated(quantity, against: contract.quantity, linkID: linkID))
        case .integer(let integer):
            guard let value = integer.value?.integer else {
                throw ObservationExtractionError.answerMissing(linkID: linkID)
            }
            return .quantity(try fixedUnitQuantity(
                decimal: Decimal(value),
                item: item,
                contract: contract,
                linkID: linkID
            ))
        case .decimal(let decimal):
            guard let value = decimal.value?.decimal else {
                throw ObservationExtractionError.answerMissing(linkID: linkID)
            }
            return .quantity(try fixedUnitQuantity(
                decimal: value,
                item: item,
                contract: contract,
                linkID: linkID
            ))
        case .coding(let coding):
            return try codedValue(coding, contract: contract, linkID: linkID)
        case .boolean(let flag):
            guard let value = flag.value?.bool else {
                throw ObservationExtractionError.answerMissing(linkID: linkID)
            }
            return .boolean(value)
        default:
            throw ObservationExtractionError.unsupportedAnswer(linkID: linkID)
        }
    }

    // A coded result must be one the measurement admits, or the projection would
    // smuggle an unmodeled concept under a modeled code.
    private func codedValue(
        _ coding: Coding,
        contract: MeasurementContract,
        linkID: String
    ) throws -> ExtractedValue {
        if let system = contract.resultCodeSystem {
            let answered = coding.code?.value?.string ?? ""
            guard coding.system?.value?.url.absoluteString == system,
                  contract.resultCodes.contains(where: { $0.code == answered }) else {
                throw ObservationExtractionError.answerNotInMeasurement(linkID: linkID, code: answered)
            }
        }
        return .codeableConcept(CodeableConcept(coding: [coding]))
    }

    private func componentValue(
        for item: ModelsR4.QuestionnaireItem,
        answers: ModelsR4.QuestionnaireResponseItem?,
        contract: MeasurementContract
    ) throws -> ExtractedValue {
        var components: [ExtractedValue.Component] = []
        for child in item.item ?? [] {
            guard try child.extractionMarking() == .component else {
                continue
            }
            let childLinkID = child.linkId.value?.string ?? ""
            guard let coding = child.code?.first,
                  let code = coding.code?.value?.string else {
                throw ObservationExtractionError.itemCodeMissing(linkID: childLinkID)
            }
            guard let component = contract.components.first(where: { $0.code == code }) else {
                throw ObservationExtractionError.componentNotInMeasurement(linkID: childLinkID, code: code)
            }
            let answered = responseItem(linkID: childLinkID, in: answers?.item ?? [])
            guard let answer = try answered.flatMap({ try Self.singleAnswer(of: $0, linkID: childLinkID) }),
                  case .quantity(let quantity) = answer.value else {
                throw ObservationExtractionError.answerMissing(linkID: childLinkID)
            }
            components.append(ExtractedValue.Component(
                code: CodingContract(system: component.system, code: component.code),
                value: try validated(quantity, against: component.quantity, linkID: childLinkID)
            ))
        }
        // The measurement's own completeness rule: every declared component or nothing.
        for declared in contract.components where !components.contains(where: { $0.code.code == declared.code }) {
            throw ObservationExtractionError.componentIncomplete(
                measurement: contract.id,
                missing: declared.code
            )
        }
        return .components(components)
    }

    private func validated(
        _ quantity: Quantity,
        against declared: QuantityContract?,
        linkID: String
    ) throws -> Quantity {
        guard let declared else {
            return quantity
        }
        let answeredCode = quantity.code?.value?.string ?? ""
        guard answeredCode == declared.code,
              quantity.system?.value?.url.absoluteString == declared.system else {
            throw ObservationExtractionError.unitMismatch(
                linkID: linkID,
                expected: declared.code,
                answered: answeredCode
            )
        }
        // An answer may spell the display as the UCUM code; the catalog owns the emitted display.
        var normalized = quantity
        normalized.unit = declared.unit.asFHIRStringPrimitive()
        return normalized
    }

    private func fixedUnitQuantity(
        decimal: Decimal,
        item: ModelsR4.QuestionnaireItem,
        contract: MeasurementContract,
        linkID: String
    ) throws -> Quantity {
        guard let unit = item.fixedUnit,
              let code = unit.code?.value?.string,
              let system = unit.system?.value?.url.absoluteString else {
            throw ObservationExtractionError.unitMissing(linkID: linkID)
        }
        let quantity = Quantity(
            code: code.asFHIRStringPrimitive(),
            system: FHIRPrimitive(FHIRURI(stringLiteral: system)),
            unit: unit.display?.value?.string.asFHIRStringPrimitive() ?? code.asFHIRStringPrimitive(),
            value: FHIRPrimitive(FHIRDecimal(decimal))
        )
        return try validated(quantity, against: contract.quantity, linkID: linkID)
    }


    // MARK: Lookup

    private func responseItem(
        linkID: String?,
        in items: [QuestionnaireResponseItem]
    ) -> QuestionnaireResponseItem? {
        guard let linkID else {
            return nil
        }
        return items.first { $0.linkId.value?.string == linkID }
    }
}
