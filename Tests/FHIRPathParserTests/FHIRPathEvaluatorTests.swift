//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//


@testable import FHIRPathParser
import Foundation
import Testing


@Suite
struct FHIRPathEvaluatorTests {
    private func evaluate(_ expression: String, context: FHIRPathEvaluationContext = .init()) throws -> [FHIRPathValue] {
        try FHIRPathExpression.evaluate(expression: expression, context: context)
    }

    /// A QuestionnaireResponse-shaped tree with weighted coding answers.
    private func responseContext() throws -> FHIRPathEvaluationContext {
        let json = """
        {
            "resourceType": "QuestionnaireResponse",
            "status": "in-progress",
            "item": [
                {
                    "linkId": "q1",
                    "answer": [{
                        "valueCoding": {
                            "system": "https://example.org/scale",
                            "code": "several-days",
                            "extension": [{
                                "url": "http://hl7.org/fhir/StructureDefinition/itemWeight",
                                "valueDecimal": 1
                            }]
                        }
                    }]
                },
                {
                    "linkId": "q2",
                    "answer": [{
                        "valueCoding": {
                            "system": "https://example.org/scale",
                            "code": "nearly-every-day",
                            "extension": [{
                                "url": "http://hl7.org/fhir/StructureDefinition/ordinalValue",
                                "valueDecimal": 3
                            }]
                        }
                    }]
                },
                {
                    "linkId": "age",
                    "answer": [{ "valueInteger": 42 }]
                },
                {
                    "linkId": "name",
                    "answer": [{ "valueString": "Grove" }]
                }
            ]
        }
        """
        let node = try FHIRPathNode(jsonData: Data(json.utf8))
        return FHIRPathEvaluationContext(
            focus: [.object(node)],
            constants: ["resource": [.object(node)]]
        )
    }

    // MARK: Literals & Arithmetic

    @Test
    func integerArithmetic() throws {
        #expect(try evaluate("1 + 2") == [.integer(3)])
        #expect(try evaluate("7 - 10") == [.integer(-3)])
        #expect(try evaluate("6 * 7") == [.integer(42)])
        #expect(try evaluate("7 div 2") == [.integer(3)])
        #expect(try evaluate("7 mod 2") == [.integer(1)])
        #expect(try evaluate("10 / 4") == [.decimal(2.5)])
        #expect(try evaluate("1 / 0").isEmpty)
    }

    @Test
    func decimalArithmetic() throws {
        #expect(try evaluate("1.5 + 2.5") == [.decimal(4)])
        #expect(try evaluate("0.1 + 0.2") == [.decimal(Decimal(string: "0.3") ?? 0)])
        #expect(try evaluate("-(3.5)") == [.decimal(-3.5)])
    }

    @Test
    func stringOperators() throws {
        #expect(try evaluate("'a' + 'b'") == [.string("ab")])
        #expect(try evaluate("'a' & 'b'") == [.string("ab")])
        #expect(try evaluate("{} & 'b'") == [.string("b")])
        #expect(try evaluate(#"'it\'s'"#) == [.string("it's")])
    }

    @Test
    func stringEscapes() throws {
        #expect(try evaluate(#"'a\nb'"#) == [.string("a\nb")])
        #expect(try evaluate(#"'a\\nb'"#) == [.string(#"a\nb"#)], "an escaped backslash must not start a new escape")
        #expect(try evaluate(#"'a\\\nb'"#) == [.string("a\\\nb")])
        #expect(try evaluate(#"'a\\\\b'"#) == [.string(#"a\\b"#)])
        #expect(try evaluate(#"'\\'"#) == [.string(#"\"#)])
        #expect(try evaluate(#"'a\tb\rc\/d\`e'"#) == [.string("a\tb\rc/d`e")])
    }

    // MARK: Boolean Logic

    @Test
    func threeValuedLogic() throws {
        #expect(try evaluate("true and false") == [.boolean(false)])
        #expect(try evaluate("{} and false") == [.boolean(false)])
        #expect(try evaluate("{} and true").isEmpty)
        #expect(try evaluate("true or {}") == [.boolean(true)])
        #expect(try evaluate("false or {}").isEmpty)
        #expect(try evaluate("true xor true") == [.boolean(false)])
        #expect(try evaluate("false implies false") == [.boolean(true)])
        #expect(try evaluate("(1 > 2) or (1 < 2)") == [.boolean(true)])
    }

    // MARK: Comparisons & Equality

    @Test
    func comparisons() throws {
        #expect(try evaluate("3 > 2") == [.boolean(true)])
        #expect(try evaluate("3 >= 3") == [.boolean(true)])
        #expect(try evaluate("2.5 < 2") == [.boolean(false)])
        #expect(try evaluate("'abc' < 'abd'") == [.boolean(true)])
        #expect(try evaluate("1 = 1.0") == [.boolean(true)])
        #expect(try evaluate("1 != 2") == [.boolean(true)])
        #expect(try evaluate("'A' ~ 'a'") == [.boolean(true)])
        #expect(try evaluate("{} = 1").isEmpty)
    }

    @Test
    func temporalComparisons() throws {
        #expect(try evaluate("@2026-01-01 < @2026-02-01") == [.boolean(true)])
        #expect(try evaluate("@2026-03-14 = @2026-03-14") == [.boolean(true)])
        // Deviation from full FHIRPath: the literal parser zero-fills partial dates,
        // so differing precision compares on the filled fields instead of being empty.
        #expect(try evaluate("@2026-01 = @2026-01-15") == [.boolean(false)])
        #expect(try evaluate("@T10:30 < @T11:00") == [.boolean(true)])
    }

    @Test
    func offsetDateTimeComparisons() throws {
        // The offsets invert the component ordering: 00:30+02:00 is 22:30Z on the previous day.
        #expect(try evaluate("@2024-01-01T00:30:00+02:00 > @2024-01-01T00:00:00Z") == [.boolean(false)])
        #expect(try evaluate("@2024-01-01T00:30:00+02:00 < @2024-01-01T00:00:00Z") == [.boolean(true)])
        #expect(try evaluate("@2024-01-01T12:00:00+02:00 = @2024-01-01T10:00:00Z") == [.boolean(true)])
        #expect(try evaluate("@2024-01-01T09:00:00-05:00 > @2024-01-01T13:00:00Z") == [.boolean(true)])
        // Without an offset the comparison stays component-wise.
        #expect(try evaluate("@2024-01-01T00:30:00 > @2024-01-01T00:00:00") == [.boolean(true)])
    }

    @Test
    func quantityComparisons() throws {
        #expect(try evaluate("5 'kg' > 3 'kg'") == [.boolean(true)])
        #expect(try evaluate("5 'kg' = 5.0 'kg'") == [.boolean(true)])
        // Mismatched units are incomparable (no unit conversion) — empty.
        #expect(try evaluate("5 'kg' > 3 'lb'").isEmpty)
        #expect(try evaluate("5 'kg' + 2 'kg' = 7 'kg'") == [.boolean(true)])
    }

    @Test
    func dateArithmetic() throws {
        #expect(try evaluate("@2020-01-31 + 1 month") == [.date(DateComponents(year: 2020, month: 2, day: 29))])
        #expect(try evaluate("@2026-08-14 - 18 years") == [.date(DateComponents(year: 2008, month: 8, day: 14))])
        let fixed = try #require(Calendar.current.date(from: DateComponents(year: 2026, month: 8, day: 14, hour: 12)))
        let context = FHIRPathEvaluationContext(now: fixed)
        #expect(try evaluate("today()", context: context) == [.date(DateComponents(year: 2026, month: 8, day: 14))])
        #expect(try evaluate("today() - 18 years < @2010-01-01", context: context) == [.boolean(true)])
    }

    // MARK: Collections

    @Test
    func collectionOperators() throws {
        #expect(try evaluate("(1 | 2 | 3).count()") == [.integer(3)])
        #expect(try evaluate("(1 | 2 | 2).count()") == [.integer(2)], "union is distinct")
        #expect(try evaluate("(10 | 20 | 30)[1]") == [.integer(20)])
        #expect(try evaluate("2 in (1 | 2 | 3)") == [.boolean(true)])
        #expect(try evaluate("(1 | 2 | 3) contains 4") == [.boolean(false)])
        #expect(try evaluate("(1 | 2 | 3).first()") == [.integer(1)])
        #expect(try evaluate("(1 | 2 | 3).tail()") == [.integer(2), .integer(3)])
        #expect(try evaluate("(1 | 2 | 3).skip(1).take(1)") == [.integer(2)])
        #expect(try evaluate("{}.empty()") == [.boolean(true)])
        #expect(try evaluate("(1 | 2).exists()") == [.boolean(true)])
    }

    @Test
    func filteringAndProjection() throws {
        #expect(try evaluate("(1 | 2 | 3 | 4).where($this > 2)") == [.integer(3), .integer(4)])
        #expect(try evaluate("(1 | 2 | 3).select($this * 2)") == [.integer(2), .integer(4), .integer(6)])
        #expect(try evaluate("(1 | 2 | 3).all($this > 0)") == [.boolean(true)])
        #expect(try evaluate("(1 | 2 | 3).exists($this > 2)") == [.boolean(true)])
        #expect(try evaluate("(1 | 2 | 3).select($index)") == [.integer(0), .integer(1), .integer(2)])
    }

    @Test
    func aggregates() throws {
        #expect(try evaluate("(1 | 2 | 3).sum()") == [.integer(6)])
        #expect(try evaluate("{}.sum()") == [.integer(0)])
        #expect(try evaluate("(1 | 2 | 3).min()") == [.integer(1)])
        #expect(try evaluate("(1 | 2 | 3).max()") == [.integer(3)])
        #expect(try evaluate("(1 | 2 | 3 | 4).avg()") == [.decimal(2.5)])
        #expect(try evaluate("(1.5 | 2.5).sum()") == [.decimal(4)])
    }

    @Test
    func conversionAndUtility() throws {
        #expect(try evaluate("iif(2 > 1, 'yes', 'no')") == [.string("yes")])
        #expect(try evaluate("iif(1 > 2, 'yes')").isEmpty)
        #expect(try evaluate("(2 > 1).not()") == [.boolean(false)])
        #expect(try evaluate("'42'.toInteger()") == [.integer(42)])
        #expect(try evaluate("'2.5'.toDecimal()") == [.decimal(2.5)])
        #expect(try evaluate("42.toString()") == [.string("42")])
        #expect(try evaluate("(3.7).round()") == [.decimal(4)])
        #expect(try evaluate("(-5).abs()") == [.integer(5)])
    }

    @Test
    func stringFunctions() throws {
        #expect(try evaluate("'hello'.length()") == [.integer(5)])
        #expect(try evaluate("'hello'.upper()") == [.string("HELLO")])
        #expect(try evaluate("'HELLO'.lower()") == [.string("hello")])
        #expect(try evaluate("'hello'.substring(1, 3)") == [.string("ell")])
        #expect(try evaluate("'hello'.startsWith('he')") == [.boolean(true)])
        #expect(try evaluate("'hello'.endsWith('lo')") == [.boolean(true)])
        #expect(try evaluate("'hello'.contains('ell')") == [.boolean(true)])
        #expect(try evaluate("'hello'.indexOf('l')") == [.integer(2)])
        #expect(try evaluate("'a,b'.replace(',', '-')") == [.string("a-b")])
        #expect(try evaluate("'12345'.matches('^[0-9]+$')") == [.boolean(true)])
        #expect(try evaluate("('a' | 'b' | 'c').join('-')") == [.string("a-b-c")])
    }

    // MARK: Resource Navigation

    @Test
    func navigatesResponseItems() throws {
        let context = try responseContext()
        #expect(try evaluate("item.count()", context: context) == [.integer(4)])
        #expect(try evaluate("item.where(linkId = 'age').answer.value", context: context) == [.integer(42)])
        #expect(try evaluate("item.where(linkId = 'name').answer.value", context: context) == [.string("Grove")])
        #expect(try evaluate("QuestionnaireResponse.item.count()", context: context) == [.integer(4)])
        #expect(try evaluate("status = 'in-progress'", context: context) == [.boolean(true)])
    }

    @Test
    func externalConstants() throws {
        let context = try responseContext()
        #expect(try evaluate("%resource.item.count()", context: context) == [.integer(4)])
        #expect(try evaluate("%context.item.count()", context: context) == [.integer(4)])
        #expect(try evaluate("%ucum = 'http://unitsofmeasure.org'", context: context) == [.boolean(true)])
        #expect(throws: FHIRPathEvaluationError.self) {
            try evaluate("%undefined", context: context)
        }
    }

    @Test
    func weightComputesScores() throws {
        let context = try responseContext()
        // PHQ-9-style scoring: the sum of the selected options' weights.
        let total = try evaluate(
            "item.where(linkId = 'q1' or linkId = 'q2').answer.weight().sum()",
            context: context
        )
        #expect(total == [.decimal(4)])
        // weight() also accepts the codings directly.
        #expect(try evaluate("item.answer.valueCoding.weight().sum()", context: context) == [.decimal(4)])
    }

    @Test
    func choiceTypeNavigation() throws {
        let context = try responseContext()
        // `value` matches valueInteger/valueString/valueCoding via choice-type naming.
        #expect(try evaluate("item.answer.value.count()", context: context) == [.integer(4)])
    }

    // MARK: Failure Modes

    @Test
    func unsupportedConstructsThrowLoudly() throws {
        #expect(throws: FHIRPathEvaluationError.self) {
            try evaluate("(1 | 2).aggregate($this + $total)")
        }
        #expect(throws: FHIRPathEvaluationError.self) {
            try evaluate("unknownFunction(1)")
        }
        #expect(throws: FHIRPathEvaluationError.self) {
            try evaluate("1 +")
        }
    }

    @Test
    func typeOperators() throws {
        #expect(try evaluate("1 is Integer") == [.boolean(true)])
        #expect(try evaluate("1 is String") == [.boolean(false)])
        #expect(try evaluate("1 is System.Integer") == [.boolean(true)])
        #expect(try evaluate("(1 | 'a' | 2.5).ofType(Integer)") == [.integer(1)])
        #expect(try evaluate("'x' as String") == [.string("x")])
        #expect(try evaluate("'x' as Integer").isEmpty)
        #expect(try evaluate("5 'kg' is Quantity") == [.boolean(true)])
        #expect(throws: FHIRPathEvaluationError.self) {
            try evaluate("1 is Foo")
        }
    }

    @Test
    func singletonBooleanConversion() throws {
        let context = try responseContext()
        #expect(try FHIRPathExpression.evaluateBoolean(expression: "item.where(linkId = 'age')", context: context) == .true)
        #expect(try FHIRPathExpression.evaluateBoolean(expression: "item.where(linkId = 'nope')", context: context) == .empty)
        #expect(try FHIRPathExpression.evaluateBoolean(expression: "1 > 2", context: context) == .false)
    }
}
