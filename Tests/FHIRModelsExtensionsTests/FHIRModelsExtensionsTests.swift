//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2022 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

@testable import FHIRModelsExtensions
import FHIRQuestionnaires
import Foundation
import ModelsR4
import Testing


@Suite
struct FHIRToResearchKitTests {
    private static let evaluationInstant = Date(timeIntervalSince1970: 1_700_000_000)

    /// - Note: "FHIR extensions" here meaning Swift extensions on FHIR types, not actual FHIR extensions.
    @Test
    func fhirExtensions() {
        #expect(Questionnaire.numberExample.flattenedItems.count == 3)
        #expect(Questionnaire.numberExample.flattenedQuestions.count == 3)
        #expect(Questionnaire.formExample.flattenedItems.count == 5)
        #expect(Questionnaire.formExample.flattenedQuestions.count == 3)
        #expect(Questionnaire.skipLogicExample.flattenedItems.count == 3)
        #expect(Questionnaire.skipLogicExample.flattenedQuestions.count == 3)
    }
    

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
        let testRegex = Questionnaire.textValidationExample.item?.first?.validationRegularExpression
        // swiftlint:disable:next line_length
        let regex = try NSRegularExpression(pattern: "^[a-zA-Z0-9.!#$%&'*+/=?^_`{|}~-]+@[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?(?:\\.[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?)*$")
        #expect(regex == testRegex)
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
        let minValues = try #require(Questionnaire.numberExample.item).map(\.minValue)
        #expect(minValues == [
            NSNumber(value: 1),
            NSNumber(value: 1),
            NSNumber(value: 1)
        ])
    }

    @Test("Maximum value extension")
    func testMaxValueExtension() throws {
        let minValues = try #require(Questionnaire.numberExample.item).map(\.maxValue)
        #expect(minValues == [
            NSNumber(value: 100),
            NSNumber(value: 100),
            NSNumber(value: 100)
        ])
    }

    @Test
    func testMinDateValueExtension() throws {
        let minDateValue = Questionnaire.dateTimeExample.item?.first?.minDateValue(
            evaluationInstant: Self.evaluationInstant
        )
        let unwrappedMinDateValue = try #require(minDateValue)
        #expect(unwrappedMinDateValue == DateComponents(year: 2001, month: 1, day: 1))
    }

    @Test
    func testMaxDateValueExtension() throws {
        let maxDateValue = Questionnaire.dateTimeExample.item?.first?.maxDateValue(
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
}
