//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import FHIRModelsExtensions
import Foundation
import GroveQuestionnaire
import ModelsR4


private enum ExtractionURL {
    static let marking = "http://hl7.org/fhir/uv/sdc/StructureDefinition/sdc-questionnaire-observationExtract"
    static let category = "http://hl7.org/fhir/uv/sdc/StructureDefinition/sdc-questionnaire-observation-extract-category"
}


@available(iOS 18, macOS 15, watchOS 11, *)
extension GroveQuestionnaire.Questionnaire.Task.Code {
    var fhirCoding: ModelsR4.Coding {
        Coding(code: code.asFHIRStringPrimitive(), display: display?.asFHIRStringPrimitive(), system: system?.asFHIRURIPrimitive())
    }

    /// The code of a FHIR coding; `nil` when it states none.
    init?(_ coding: ModelsR4.Coding) {
        guard let code = coding.code?.value?.string else {
            return nil
        }
        self.init(system: coding.system?.value?.url, code: code, display: .init(coding.display))
    }
}


@available(iOS 18, macOS 15, watchOS 11, *)
extension GroveQuestionnaire.Questionnaire.Concept {
    var fhirConcept: ModelsR4.CodeableConcept {
        CodeableConcept(coding: codes.isEmpty ? nil : codes.map(\.fhirCoding), text: text?.asFHIRStringPrimitive())
    }

    init(_ concept: ModelsR4.CodeableConcept) {
        self.init(codes: (concept.coding ?? []).compactMap { .init($0) }, text: .init(concept.text))
    }
}


@available(iOS 18, macOS 15, watchOS 11, *)
extension GroveQuestionnaire.Questionnaire.UsageContext {
    var fhirUsageContext: ModelsR4.UsageContext {
        let fhirValue: ModelsR4.UsageContext.ValueX = switch value {
        case .concept(let concept):
            .codeableConcept(concept.fhirConcept)
        case .quantity(let quantity):
            .quantity(quantity.fhirQuantity)
        case let .range(low, high):
            .range(ModelsR4.Range(high: high?.fhirQuantity, low: low?.fhirQuantity))
        case .reference(let reference):
            .reference(reference.fhirReference)
        }
        return ModelsR4.UsageContext(code: code.fhirCoding, value: fhirValue)
    }

    init(_ context: ModelsR4.UsageContext) throws(GroveQuestionnaire.Questionnaire.ConversionError) {
        guard let code = GroveQuestionnaire.Questionnaire.Task.Code(context.code) else {
            throw .other("A useContext must state its code")
        }
        let value: Value = switch context.value {
        case .codeableConcept(let concept):
            .concept(.init(concept))
        case .quantity(let quantity):
            .quantity(.init(quantity))
        case .range(let range):
            .range(low: range.low.map { .init($0) }, high: range.high.map { .init($0) })
        case .reference(let reference):
            .reference(.init(reference))
        }
        self.init(code: code, value: value)
    }
}


@available(iOS 18, macOS 15, watchOS 11, *)
extension GroveQuestionnaire.Questionnaire.UsageContext.Quantity {
    var fhirQuantity: ModelsR4.Quantity {
        ModelsR4.Quantity(
            code: code?.asFHIRStringPrimitive(),
            comparator: comparator.flatMap(QuantityComparator.init(rawValue:)).map { FHIRPrimitive($0) },
            system: system?.asFHIRURIPrimitive(),
            unit: unit?.asFHIRStringPrimitive(),
            value: value.map { FHIRPrimitive(FHIRDecimal($0)) }
        )
    }

    init(_ quantity: ModelsR4.Quantity) {
        self.init(
            value: quantity.value?.value?.decimal,
            comparator: quantity.comparator?.value?.rawValue,
            unit: .init(quantity.unit),
            system: quantity.system?.value?.url,
            code: quantity.code?.value?.string
        )
    }
}


@available(iOS 18, macOS 15, watchOS 11, *)
extension GroveQuestionnaire.Questionnaire.UsageContext.Reference {
    var fhirReference: ModelsR4.Reference {
        let identifier = identifierSystem == nil && identifierValue == nil ? nil : Identifier(
            system: identifierSystem?.asFHIRURIPrimitive(),
            value: identifierValue?.asFHIRStringPrimitive()
        )
        return ModelsR4.Reference(
            display: display?.asFHIRStringPrimitive(),
            identifier: identifier,
            reference: reference?.asFHIRStringPrimitive(),
            type: type?.asFHIRURIPrimitive()
        )
    }

    init(_ reference: ModelsR4.Reference) {
        self.init(
            reference: reference.reference?.value?.string,
            type: reference.type?.value?.url,
            identifierSystem: reference.identifier?.system?.value?.url,
            identifierValue: reference.identifier?.value?.value?.string,
            display: .init(reference.display)
        )
    }
}


@available(iOS 18, macOS 15, watchOS 11, *)
extension GroveQuestionnaire.Questionnaire.ObservationExtraction {
    var fhirExtensions: [Extension] {
        var extensions: [Extension] = []
        switch marking {
        case .extracts(let extracts):
            extensions.append(Extension(
                url: FHIRPrimitive(FHIRURI(stringLiteral: ExtractionURL.marking)),
                value: .boolean(FHIRPrimitive(FHIRBool(extracts)))
            ))
        case .relation(let relation):
            extensions.append(Extension(
                url: FHIRPrimitive(FHIRURI(stringLiteral: ExtractionURL.marking)),
                value: .code(FHIRPrimitive(ModelsR4.FHIRString(relation)))
            ))
        case nil:
            break
        }
        extensions += categories.map { category in
            Extension(url: FHIRPrimitive(FHIRURI(stringLiteral: ExtractionURL.category)), value: .codeableConcept(category.fhirConcept))
        }
        return extensions
    }

    /// The element's SDC observation extraction; `nil` when it declares none.
    init?(_ element: some FHIRTypeWithExtensions) throws(GroveQuestionnaire.Questionnaire.ConversionError) {
        let markings = element.extensions(for: FHIRPrimitive(FHIRURI(stringLiteral: ExtractionURL.marking)))
        var categories: [GroveQuestionnaire.Questionnaire.Concept] = []
        for category in element.extensions(for: FHIRPrimitive(FHIRURI(stringLiteral: ExtractionURL.category))) {
            guard case .codeableConcept(let concept) = category.value else {
                throw .other("An observation-extract-category must carry a CodeableConcept")
            }
            categories.append(.init(concept))
        }
        guard markings.count <= 1 else {
            throw .other("An item declares more than one observationExtract marking")
        }
        guard let marking = markings.first else {
            guard !categories.isEmpty else {
                return nil
            }
            self.init(marking: nil, categories: categories)
            return
        }
        switch marking.value {
        case .boolean(let extracts):
            self.init(marking: .extracts(extracts.value?.bool == true), categories: categories)
        case .code(let relation):
            self.init(marking: .relation(relation.value?.string ?? ""), categories: categories)
        default:
            throw .other("An observationExtract marking must be a boolean or a code")
        }
    }
}
