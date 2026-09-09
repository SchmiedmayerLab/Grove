//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2022 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import FHIRModelsExtensions
import FHIRQuestionnaires
import Foundation
import ModelsR4
import Testing


@Suite
struct FHIRToResearchKitTests {
    private static let evaluationInstant = Date(timeIntervalSince1970: 1_700_000_000)

    @Test
    func testGetContainedValueSets() throws {
        let valueSets = Questionnaire.containedValueSetExample.getContainedValueSets()
        #expect(valueSets.count == 1)
    }

    @Test
    func testItemControlExtension() throws {
        let testItemControl = Questionnaire.sliderExample.item?.first?.itemControl
        let itemControlValue = try #require(testItemControl)
        #expect(itemControlValue == "slider")
    }

    @Test("Regex extension")
    func testRegexExtension() throws {
        let testRegex = try Questionnaire.textValidationExample.item?.first?.validationRegularExpression
        // swiftlint:disable:next line_length
        let regex = try NSRegularExpression(pattern: "^[a-zA-Z0-9.!#$%&'*+/=?^_`{|}~-]+@[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?(?:\\.[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?)*$")
        #expect(regex == testRegex)
    }

    @Test("Malformed present regex constraints fail instead of becoming absent")
    func malformedRegexFailsClosed() throws {
        var item = QuestionnaireItem(linkId: "regex", type: FHIRPrimitive(.string))
        item.extension = [
            Extension(
                url: "http://hl7.org/fhir/StructureDefinition/regex",
                value: .string("[".asFHIRStringPrimitive())
            )
        ]

        #expect(throws: QuestionnaireItemRegexError.invalidPattern("[")) {
            _ = try item.validationRegularExpression
        }
    }

    @Test("Slider step value extension")
    func testSliderStepValueExtension() throws {
        let testSliderStepValue = Questionnaire.sliderExample.item?.first?.sliderStepValue
        let sliderStepValue = try #require(testSliderStepValue)
        #expect(sliderStepValue == 1)
    }

    @Test("A regex does not infer a retired validation-message extension")
    func regexDoesNotInferValidationMessage() {
        #expect(Questionnaire.textValidationExample.item?.first?.validationMessage == nil)
    }

    @Test("Unit extension")
    func testUnitExtension() throws {
        let unit = Questionnaire.numberExample.item?[2].unit
        let unwrappedUnit = try #require(unit)
        #expect(unwrappedUnit == "g")
    }

    @Test("Minimum value extension")
    func testMinValueExtension() throws {
        let minValues = try #require(Questionnaire.numberExample.item).map { try $0.minValue }
        #expect(minValues == [
            NSNumber(value: 1),
            NSNumber(value: 1),
            NSNumber(value: 1)
        ])
    }

    @Test("Maximum value extension")
    func testMaxValueExtension() throws {
        let minValues = try #require(Questionnaire.numberExample.item).map { try $0.maxValue }
        #expect(minValues == [
            NSNumber(value: 100),
            NSNumber(value: 100),
            NSNumber(value: 100)
        ])
    }

    @Test
    func testMinDateValueExtension() throws {
        let minDateValue = try Questionnaire.dateTimeExample.item?.first?.minDateValue(
            evaluationInstant: Self.evaluationInstant
        )
        let unwrappedMinDateValue = try #require(minDateValue)
        #expect(unwrappedMinDateValue == DateComponents(year: 2001, month: 1, day: 1))
    }

    @Test
    func testMaxDateValueExtension() throws {
        let maxDateValue = try Questionnaire.dateTimeExample.item?.first?.maxDateValue(
            evaluationInstant: Self.evaluationInstant
        )
        let unwrappedMaxDateValue = try #require(maxDateValue)
        #expect(unwrappedMaxDateValue == DateComponents(year: 2024, month: 1, day: 1))
    }

    @Test
    func testMaxDecimalExtension() throws {
        let maxDecimals = Questionnaire.numberExample.item?[1].maximumDecimalPlaces
        let unwrappedMaxDecimals = try #require(maxDecimals)
        #expect(unwrappedMaxDecimals == 3)
    }

    @Test("Present malformed bounds fail rather than becoming unbounded")
    func malformedBoundsFailClosed() throws {
        let minURL = "http://hl7.org/fhir/StructureDefinition/minValue"
        let malformedDate = QuestionnaireItem(
            extension: [
                Extension(
                    url: try FHIRExtensionURL(minURL),
                    value: .string("today( broken".asFHIRStringPrimitive())
                )
            ],
            linkId: "date".asFHIRStringPrimitive(),
            type: FHIRPrimitive(.date)
        )
        #expect(throws: QuestionnaireItemBoundError.self) {
            _ = try malformedDate.minDateValue(evaluationInstant: Self.evaluationInstant)
        }

        let malformedNumber = QuestionnaireItem(
            extension: [
                Extension(
                    url: try FHIRExtensionURL(minURL),
                    value: .string("not-a-number".asFHIRStringPrimitive())
                )
            ],
            linkId: "number".asFHIRStringPrimitive(),
            type: FHIRPrimitive(.decimal)
        )
        #expect(throws: QuestionnaireItemBoundError.unsupportedValue(url: minURL)) {
            _ = try malformedNumber.minValue
        }
    }

    @Test("Relative bounds use exactly the supplied clock")
    func relativeBoundsUseExplicitClock() throws {
        let minURL = "http://hl7.org/fhir/StructureDefinition/minValue"
        let item = QuestionnaireItem(
            extension: [
                Extension(
                    url: try FHIRExtensionURL(minURL),
                    value: .string("today()".asFHIRStringPrimitive())
                )
            ],
            linkId: "date".asFHIRStringPrimitive(),
            type: FHIRPrimitive(.date)
        )
        let first = try #require(try item.minDateValue(evaluationInstant: Date(timeIntervalSince1970: 0)))
        let later = try #require(try item.minDateValue(evaluationInstant: Date(timeIntervalSince1970: 172_800)))
        #expect(first.day == 1)
        #expect(later.day == 3)
    }

    @Test("Invalid extension URL text throws", arguments: ["", "http://["])
    func invalidExtensionURLTextThrows(_ value: String) {
        #expect(throws: FHIRExtensionURL.ParsingError.self) {
            _ = try FHIRExtensionURL(value)
        }
    }

    @Test("Relative extension URLs remain valid")
    func relativeExtensionURLRemainsValid() throws {
        let url = try FHIRExtensionURL("relative/extension")
        #expect(url.url.relativeString == "relative/extension")
    }

    @Test("A type-erased builder cannot replace the concrete FHIR resource")
    func typeErasedBuilderResourceReplacementThrows() {
        let originalURL: FHIRPrimitive<FHIRURI> = "relative/extension"
        var resource = Extension(url: originalURL)
        let builder = FHIRExtensionBuilder<Void> { resource in
            resource = Coding()
        }

        #expect(throws: FHIRExtensionBuilderError.changedResourceType) {
            try builder.apply(to: &resource)
        }
        #expect(resource.url == originalURL)
    }
}
