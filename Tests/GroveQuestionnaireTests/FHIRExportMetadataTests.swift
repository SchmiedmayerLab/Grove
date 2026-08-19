//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import Foundation
@testable import GroveQuestionnaire
@testable import GroveQuestionnaireFHIR
import ModelsR4
import Testing


/// Verifies what an exported resource says about itself: the profile it claims, the
/// lifecycle it carries, the instrument it answers, and the FHIR types its bounds take.
@Suite
struct FHIRExportMetadataTests {
    // MARK: Helpers

    private static let url = URL(string: "https://example.org/fhir/Questionnaire/export")!

    private func makeFHIRQuestionnaire(status: PublicationStatus) -> ModelsR4.Questionnaire {
        var questionnaire = ModelsR4.Questionnaire(status: FHIRPrimitive(status))
        questionnaire.url = Self.url.absoluteString.asFHIRURIPrimitive()
        var item = ModelsR4.QuestionnaireItem(linkId: "agree".asFHIRStringPrimitive(), type: .init(.boolean))
        item.text = "Agree?".asFHIRStringPrimitive()
        questionnaire.item = [item]
        return questionnaire
    }

    private func item(_ linkId: String, in questionnaire: ModelsR4.Questionnaire) -> ModelsR4.QuestionnaireItem? {
        func find(_ items: [ModelsR4.QuestionnaireItem]) -> ModelsR4.QuestionnaireItem? {
            for item in items {
                if item.linkId.value?.string == linkId {
                    return item
                }
                if let match = find(item.item ?? []) {
                    return match
                }
            }
            return nil
        }
        return find(questionnaire.item ?? [])
    }

    private func profiles(of meta: Meta?) -> [String] {
        (meta?.profile ?? []).compactMap { $0.value?.url.absoluteString }
    }

    // MARK: Profile

    @Test
    func exportedResourcesDeclareTheirProfile() throws {
        let questionnaire = GroveQuestionnaire.Questionnaire(url: Self.url, title: "Export") {
            Section("s1") {
                BooleanQuestion("agree", "Agree?")
            }
        }
        let fhir = try ModelsR4.Questionnaire(questionnaire)
        #expect(profiles(of: fhir.meta) == ["https://grovealliance.org/fhir/core/StructureDefinition/grove-questionnaire"])
        let responses = QuestionnaireResponses(questionnaire: questionnaire)
        responses.responses["agree"] = .init(value: .bool(true))
        let fhirResponse = try ModelsR4.QuestionnaireResponse(responses)
        #expect(profiles(of: fhirResponse.meta) == ["https://grovealliance.org/fhir/core/StructureDefinition/grove-questionnaire-response"])
    }

    // MARK: Publication Lifecycle

    @Test
    func draftSurvivesTheRoundTrip() throws {
        let imported = try GroveQuestionnaire.Questionnaire(makeFHIRQuestionnaire(status: .draft))
        #expect(imported.metadata.lifecycle == .draft)
        #expect(try ModelsR4.Questionnaire(imported).status.value == .draft)
    }

    @Test
    func retiredSurvivesTheRoundTrip() throws {
        let imported = try GroveQuestionnaire.Questionnaire(
            makeFHIRQuestionnaire(status: .retired),
            using: .init(enforcesPublicationLifecycle: false)
        )
        #expect(imported.metadata.lifecycle == .retired)
        #expect(try ModelsR4.Questionnaire(imported).status.value == .retired)
    }

    @Test
    func entryModeSurvivesTheRoundTrip() throws {
        var source = makeFHIRQuestionnaire(status: .active)
        source.extension = [
            Extension(
                url: "http://hl7.org/fhir/uv/sdc/StructureDefinition/sdc-questionnaire-entryMode",
                value: .code(FHIRPrimitive(ModelsR4.FHIRString("prior-edit")))
            )
        ]

        let exported = try ModelsR4.Questionnaire(GroveQuestionnaire.Questionnaire(source))
        guard case .code(let mode)? = exported.extensions(
            for: "http://hl7.org/fhir/uv/sdc/StructureDefinition/sdc-questionnaire-entryMode"
        ).first?.value else {
            Issue.record("Expected the entryMode extension")
            return
        }
        #expect(mode.value?.string == "prior-edit")
    }

    // MARK: Instrument Link

    @Test
    func aResponseWithoutAnInstrumentCanonicalIsRefused() throws {
        let questionnaire = GroveQuestionnaire.Questionnaire(
            metadata: .init(id: "local", url: nil, title: "Local", explainer: ""),
            sections: [.init(id: "s1", tasks: [.init(id: "agree", title: "Agree?", kind: .boolean)])]
        )
        let responses = QuestionnaireResponses(questionnaire: questionnaire)
        responses.responses["agree"] = .init(value: .bool(true))
        #expect(throws: (any Error).self) {
            try ModelsR4.QuestionnaireResponse(responses)
        }
    }

    @Test
    func responseIdentityAndAuthoredTimestampAreStableWhenSupplied() throws {
        let questionnaire = GroveQuestionnaire.Questionnaire(url: Self.url, title: "Export") {
            Section("s1") {
                BooleanQuestion("agree", "Agree?")
            }
        }
        let responses = QuestionnaireResponses(questionnaire: questionnaire)
        let authored = Date(timeIntervalSince1970: 1_700_000_000)

        let first = try ModelsR4.QuestionnaireResponse(responses, authored: authored)
        let second = try ModelsR4.QuestionnaireResponse(responses, authored: authored)

        #expect(first.identifier?.system?.value?.url == Self.url)
        #expect(first.identifier == second.identifier)
        #expect(first.authored == second.authored)
    }

    // MARK: Numeric Bounds

    @Test
    func numericBoundsTakeTheAnswerType() throws {
        let questionnaire = GroveQuestionnaire.Questionnaire(url: Self.url, title: "Bounds") {
            Section("s1") {
                NumberQuestion.integer("count", "How many?").range(0...10)
                NumberQuestion("score", "Score").range(0...1)
                NumberQuestion.quantity("weight", "Weight", unit: "kg").range(30...200)
            }
        }
        let fhir = try ModelsR4.Questionnaire(questionnaire)
        let count = try #require(item("count", in: fhir))
        guard case .integer(let minimum)? = count.extensions(for: "http://hl7.org/fhir/StructureDefinition/minValue").first?.value,
              case .integer(let maximum)? = count.extensions(for: "http://hl7.org/fhir/StructureDefinition/maxValue").first?.value else {
            Issue.record("Expected integer bounds on an integer item")
            return
        }
        #expect(minimum.value?.integer == 0 && maximum.value?.integer == 10)

        let score = try #require(item("score", in: fhir))
        guard case .decimal(let lowest)? = score.extensions(for: "http://hl7.org/fhir/StructureDefinition/minValue").first?.value else {
            Issue.record("Expected a decimal bound on a decimal item")
            return
        }
        #expect(lowest.value?.decimal == 0)

        // A quantity bound needs a unit, which only SDC's min/maxQuantity carries.
        let weight = try #require(item("weight", in: fhir))
        #expect(weight.extensions(for: "http://hl7.org/fhir/StructureDefinition/minValue").isEmpty)
        let quantityBound = weight.extensions(for: "http://hl7.org/fhir/uv/sdc/StructureDefinition/sdc-questionnaire-minQuantity").first
        guard case .quantity(let quantity)? = quantityBound?.value else {
            Issue.record("Expected a quantity bound on a quantity item")
            return
        }
        #expect(quantity.value?.value?.decimal == 30)
        #expect(quantity.code?.value?.string == "kg")
        #expect(quantity.system?.value?.url.absoluteString == "http://unitsofmeasure.org")
        #expect(weight.extensions(for: "http://hl7.org/fhir/StructureDefinition/questionnaire-unit").isEmpty)
        let fixedUnit = weight.extensions(
            for: "http://hl7.org/fhir/StructureDefinition/questionnaire-unitOption"
        ).first
        guard case .coding(let coding)? = fixedUnit?.value else {
            Issue.record("Expected a fixed unit option on a quantity item")
            return
        }
        #expect(coding.code?.value?.string == "kg")
    }

    @Test
    func fixedQuantityResponseUsesTheDeclaredUnitDisplay() throws {
        let questionnaire = GroveQuestionnaire.Questionnaire(url: Self.url, title: "Temperature") {
            Section("s1") {
                NumberQuestion.quantity(
                    "temperature",
                    "Temperature",
                    unit: "Cel",
                    display: "(degree Celsius)"
                )
            }
        }
        let responses = QuestionnaireResponses(questionnaire: questionnaire)
        responses.responses["temperature"] = .init(value: .quantity(36.8, unitCode: "Cel"))

        let response = try ModelsR4.QuestionnaireResponse(responses)
        guard case .quantity(let quantity)? = response.item?.first?.item?.first?.answer?.first?.value else {
            Issue.record("Expected a quantity response")
            return
        }
        #expect(quantity.code?.value?.string == "Cel")
        #expect(quantity.unit?.value?.string == "(degree Celsius)")
    }

    @Test
    func maximumDecimalPlacesSurvivesTheRoundTrip() throws {
        var scoreItem = ModelsR4.QuestionnaireItem(linkId: "score".asFHIRStringPrimitive(), type: .init(.decimal))
        scoreItem.text = "Score".asFHIRStringPrimitive()
        scoreItem.extension = [
            Extension(
            url: "http://hl7.org/fhir/StructureDefinition/maxDecimalPlaces",
            value: .integer(FHIRPrimitive(FHIRInteger(2)))
            )
        ]
        var source = makeFHIRQuestionnaire(status: .active)
        source.item = [scoreItem]

        let exported = try ModelsR4.Questionnaire(GroveQuestionnaire.Questionnaire(source))
        let score = try #require(item("score", in: exported))
        guard case .integer(let places)? = score.extensions(
            for: "http://hl7.org/fhir/StructureDefinition/maxDecimalPlaces"
        ).first?.value else {
            Issue.record("Expected maxDecimalPlaces on the exported item")
            return
        }
        #expect(places.value?.integer == 2)
    }

    // MARK: Constraint Keys

    @Test
    func synthesizedConstraintKeysStayWithinTheIdAlphabet() throws {
        let questionnaire = GroveQuestionnaire.Questionnaire(url: Self.url, title: "Keys") {
            Section("s1") {
                TextQuestion("email_address", "Email").constraint("$this.matches('.+@.+')", message: "Enter a valid address.")
            }
        }
        let fhir = try ModelsR4.Questionnaire(questionnaire)
        let email = try #require(item("email_address", in: fhir))
        let target = try #require(email.extensions(for: "http://hl7.org/fhir/StructureDefinition/targetConstraint").first)
        let key = target.extension?.first { $0.url.value?.url.absoluteString == "key" }
        guard case .id(let value)? = key?.value else {
            Issue.record("Expected a valueId key sub-extension, got \(String(describing: key?.value))")
            return
        }
        #expect(value.value?.string == "email-address-1")
    }
}
