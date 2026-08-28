//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2022 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import FHIRQuestionnaires
import GroveFHIRContract
import GroveQuestionnaireFHIR
import ModelsR4
import ResearchKit
@testable import ResearchKitOnFHIR
import Testing

struct ResearchKitToFHIRTests {
    private static let questionnaireURL = "https://example.org/fhir/Questionnaire/test"
    private static let questionnaireVersion = "1.0.0"
    static let questionnaireCanonical = "\(questionnaireURL)|\(questionnaireVersion)"

    func createStepResult(_ result: ORKResult) -> ORKStepResult {
        let stepResult = ORKStepResult(identifier: result.identifier)
        stepResult.results = [result]
        return stepResult
    }

    func createTaskResult(_ result: ORKResult) -> ORKTaskResult {
        let stepResult = createStepResult(result)
        let taskResult = ORKTaskResult(
            taskIdentifier: Self.questionnaireCanonical,
            taskRun: UUID(),
            outputDirectory: nil
        )
        taskResult.results = [stepResult]
        return taskResult
    }

    private func defaultQuestionnaire() -> Questionnaire {
        let identifiers = [
            "testResult",
            "booleanResult",
            "numericResult",
            "scaleResult",
            "dateResult",
            "timeResult",
            "choiceResult",
            "File Result"
        ]
        return questionnaire(items: identifiers.map {
            QuestionnaireItem(
                linkId: $0.asFHIRStringPrimitive(),
                text: $0.asFHIRStringPrimitive(),
                type: FHIRPrimitive(.question)
            )
        })
    }

    func questionnaire(items: [QuestionnaireItem]) -> Questionnaire {
        var questionnaire = Questionnaire(
            item: items,
            status: FHIRPrimitive(.active),
            url: FHIRPrimitive(FHIRURI(stringLiteral: Self.questionnaireURL)),
            version: Self.questionnaireVersion.asFHIRStringPrimitive()
        )
        questionnaire.meta = Meta(profile: [Profile.groveQuestionnaire])
        return questionnaire
    }

    func context(
        questionnaire: Questionnaire? = nil,
        author: Reference? = nil,
        source: Reference? = nil,
        attachmentResolver: ResearchKitAttachmentResolver? = nil
    ) throws -> ResearchKitFHIRConversionContext {
        let subjectID = try BusinessIdentifier(
            system: "https://example.org/fhir/identifier/participant",
            value: "participant-1"
        )
        let subject = Reference(
            identifier: subjectID.fhirIdentifier,
            type: "Patient".asFHIRURIPrimitive()
        )
        return try ResearchKitFHIRConversionContext(
            questionnaire: questionnaire ?? defaultQuestionnaire(),
            responseIdentifier: BusinessIdentifier(
                system: "https://example.org/fhir/identifier/questionnaire-response",
                value: "response-1"
            ),
            subject: subject,
            authored: Date(timeIntervalSince1970: 1_700_000_000),
            authoredTimeZone: TimeZone(secondsFromGMT: 0)!, // swiftlint:disable:this force_unwrapping
            author: author,
            source: source,
            unitsByResultIdentifier: [
                "numericResult": .ucum(code: "g")
            ],
            attachmentResolver: attachmentResolver
        )
    }

    @Test("Text response")
    func testTextResponse() throws {
        let testValue = "test answer"
        var responseValue: String?
        let textResult = ORKTextQuestionResult(identifier: "testResult")
        textResult.textAnswer = testValue
        let taskResult = createTaskResult(textResult)
        let fhirResponse = try taskResult.fhirResponse(using: context())
        let answer = fhirResponse.item?.first?.answer?.first?.value
        if case let .string(value) = answer,
           let unwrappedValue = value.value?.string {
            responseValue = unwrappedValue
        }
        #expect(testValue == responseValue)
    }

    @Test("ResearchKit export is directly conformant with the Grove response contract")
    func responseCarriesRequiredConformanceMetadata() throws {
        let item = QuestionnaireItem(
            linkId: "testResult".asFHIRStringPrimitive(),
            text: "Test result".asFHIRStringPrimitive(),
            type: FHIRPrimitive(.string)
        )
        let source = questionnaire(items: [item])
        let result = ORKTextQuestionResult(identifier: "testResult")
        result.textAnswer = "answer"
        let response = try createTaskResult(result).fhirResponse(
            using: context(questionnaire: source)
        )
        #expect(response.meta?.profile == [Profile.groveQuestionnaireResponse])
        let completionMode = response.extension?.first {
            $0.url.value?.url.absoluteString
                == "http://hl7.org/fhir/StructureDefinition/questionnaireresponse-completionMode"
        }
        guard case let .codeableConcept(concept)? = completionMode?.value else {
            Issue.record("Expected the electronic completion-mode extension")
            return
        }
        #expect(concept.coding?.count == 1)
        #expect(concept.coding?.first?.system?.value?.url.absoluteString
            == "http://terminology.hl7.org/CodeSystem/v3-ParticipationMode")
        #expect(concept.coding?.first?.code?.value?.string == "ELECTRONIC")
        #expect(try PairValidator().validate(questionnaire: source, response: response).isEmpty)
    }

    @Test("Conformant export requires the exact Grove Questionnaire profile")
    func sourceProfileIsRequired() throws {
        var source = defaultQuestionnaire()
        source.meta = nil
        #expect(throws: ResearchKitFHIRConversionError.questionnaireProfileRequired) {
            try context(questionnaire: source)
        }
    }

    @Test("Boolean response")
    func testBooleanResponse() throws {
        let testValue = true
        var responseValue = false
        let booleanResult = ORKBooleanQuestionResult(identifier: "booleanResult")
        booleanResult.booleanAnswer = NSNumber(true)
        let taskResult = createTaskResult(booleanResult)
        let fhirResponse = try taskResult.fhirResponse(using: context())
        let answer = fhirResponse.item?.first?.answer?.first?.value
        if case let .boolean(value) = answer,
           let unwrappedValue = value.value?.bool {
            responseValue = unwrappedValue
        }
        #expect(testValue == responseValue)
    }

    @Test("Decimal response")
    func testDecimalResponse() throws {
        let testValue: Decimal = 1.5
        var responseValue: Decimal?
        let numericResult = ORKNumericQuestionResult(identifier: "numericResult")
        numericResult.numericAnswer = testValue as NSNumber
        let taskResult = createTaskResult(numericResult)
        let fhirResponse = try taskResult.fhirResponse(using: context())
        let answer = fhirResponse.item?.first?.answer?.first?.value
        if case let .decimal(value) = answer,
           let unwrappedValue = value.value?.decimal {
            responseValue = unwrappedValue
        }
        #expect(testValue == responseValue)
    }

    @Test("Integer response")
    func testIntegerResponse() throws {
        let testValue = 1
        var responseValue: Int?
        let numericResult = ORKNumericQuestionResult(identifier: "numericResult")
        numericResult.numericAnswer = testValue as NSNumber
        numericResult.questionType = ORKQuestionType.integer
        let taskResult = createTaskResult(numericResult)
        let fhirResponse = try taskResult.fhirResponse(using: context())
        let answer = fhirResponse.item?.first?.answer?.first?.value
        if case let .integer(value) = answer,
           let unwrappedValue = value.value?.integer {
            responseValue = Int(unwrappedValue)
        }
        #expect(testValue == responseValue)
    }
}


extension ResearchKitToFHIRTests {
    @Test("Scale response")
    func testScaleResponse() throws {
        let testValue = 1
        var responseValue: Int?
        let scaleResult = ORKScaleQuestionResult(identifier: "scaleResult")
        scaleResult.scaleAnswer = testValue as NSNumber
        let taskResult = createTaskResult(scaleResult)
        let fhirResponse = try taskResult.fhirResponse(using: context())
        let answer = fhirResponse.item?.first?.answer?.first?.value
        if case let .integer(value) = answer,
           let unwrappedValue = value.value?.integer {
            responseValue = Int(unwrappedValue)
        }
        #expect(testValue == responseValue)
    }

    @Test("Quantity response")
    func testQuantityResponse() throws {
        let testValue: Decimal = 1.5
        let testUnit = "g"
        var responseValue: Decimal?
        var responseUnit = ""
        let numericResult = ORKNumericQuestionResult(identifier: "numericResult")
        numericResult.numericAnswer = testValue as NSNumber
        numericResult.unit = testUnit
        numericResult.questionType = ORKQuestionType.decimal
        let taskResult = createTaskResult(numericResult)
        let fhirResponse = try taskResult.fhirResponse(using: context())
        let answer = fhirResponse.item?.first?.answer?.first?.value
        if case let .quantity(value) = answer,
           let unwrappedValue = value.value?.value?.decimal,
           let unit = value.unit?.value?.string {
            responseValue = unwrappedValue
            responseUnit = unit
        }
        #expect(testValue == responseValue)
        #expect(testUnit == responseUnit)
    }

    @Test("DateTime response")
    func testDateTimeResponse() throws {
        let testValue = Date()
        var responseValue: Date?
        let dateResult = ORKDateQuestionResult(identifier: "dateResult")
        dateResult.dateAnswer = testValue
        let taskResult = createTaskResult(dateResult)
        let fhirResponse = try taskResult.fhirResponse(using: context())
        let answer = fhirResponse.item?.first?.answer?.first?.value
        if case let .dateTime(value) = answer,
           let unwrappedValue = try? value.value?.asNSDate() {
            responseValue = unwrappedValue
        }
        #expect(testValue == responseValue)
    }

    @Test("Time response")
    func testTimeResponse() throws {
        let calendar = Calendar.current
        let hour = calendar.component(.hour, from: Date())
        let minute = calendar.component(.minute, from: Date())
        let testValue = DateComponents(hour: hour, minute: minute)
        var responseValue = DateComponents()
        let timeResult = ORKTimeOfDayQuestionResult(identifier: "timeResult")
        timeResult.dateComponentsAnswer = testValue
        let taskResult = createTaskResult(timeResult)
        let fhirResponse = try taskResult.fhirResponse(using: context())
        let answer = fhirResponse.item?.first?.answer?.first?.value
        if case let .time(value) = answer,
           let minuteValue = value.value?.minute,
           let hourValue = value.value?.hour {
            responseValue = DateComponents(hour: Int(hourValue), minute: Int(minuteValue))
        }
        #expect(testValue == responseValue)
    }
}


extension ResearchKitToFHIRTests {
    @Test("Single choice response")
    func testSingleChoiceResponse() throws {
        let testValue = ValueCoding(code: "testCode", system: "http://grovealliance.org/test-system", display: "Test Code")

        let choiceResult = ORKChoiceQuestionResult(identifier: "choiceResult")
        choiceResult.choiceAnswers = [testValue.rawValue as any NSSecureCoding & NSCopying & NSObjectProtocol]
        let taskResult = createTaskResult(choiceResult)

        let fhirResponse = try taskResult.fhirResponse(using: context())
        guard let answer = fhirResponse.item?.first?.answer?.first?.value else {
            Issue.record("Could not find the answer in the FHIR response.")
            return
        }

        switch answer {
        case let .coding(coding):
            guard let code = coding.code?.value?.string,
                  let display = coding.display?.value?.string,
                  let system = coding.system?.value?.url.absoluteString else {
                Issue.record("Could not extract the code and system from the coding.")
                return
            }

            let valueCoding = ValueCoding(code: code, system: system, display: display)
            #expect(testValue == valueCoding)

        default:
            Issue.record("Expected a coding value.")
        }
    }

    @Test("Multiple choice response")
    func testMultipleChoiceResponse() throws {
        let testValues = [
            ValueCoding(code: "testCode1", system: "http://grovealliance.org/test-system", display: "Test Code 1"),
            ValueCoding(code: "testCode2", system: "http://grovealliance.org/test-system", display: "Test Code 2")
        ]

        let choiceResult = ORKChoiceQuestionResult(identifier: "choiceResult")
        choiceResult.choiceAnswers = testValues.map { $0.rawValue as any NSSecureCoding & NSCopying & NSObjectProtocol }

        let taskResult = createTaskResult(choiceResult)

        let item = QuestionnaireItem(
            answerOption: testValues.map {
                QuestionnaireItemAnswerOption(value: .coding(Coding(
                    code: $0.code.asFHIRStringPrimitive(),
                    display: $0.display?.asFHIRStringPrimitive(),
                    system: FHIRPrimitive(FHIRURI(stringLiteral: $0.system))
                )))
            },
            linkId: "choiceResult".asFHIRStringPrimitive(),
            repeats: FHIRPrimitive(true),
            text: "Choice result".asFHIRStringPrimitive(),
            type: FHIRPrimitive(.choice)
        )
        let fhirResponse = try taskResult.fhirResponse(
            using: context(questionnaire: questionnaire(items: [item]))
        )

        guard let firstItem = fhirResponse.item?.first,
              let answers = firstItem.answer?.compactMap({ $0.value }) else {
            Issue.record("Invalid FHIR response.")
            return
        }

        guard answers.count == testValues.count else {
            Issue.record("Number of returned answers (\(answers.count)) does not match expected (\(testValues.count)).")
            return
        }

        for (index, answer) in answers.enumerated() {
            switch answer {
            case let .coding(coding):
                guard let code = coding.code?.value?.string,
                      let display = coding.display?.value?.string,
                      let system = coding.system?.value?.url.absoluteString else {
                    Issue.record("Could not extract the code and system from the coding.")
                    return
                }

                let valueCoding = ValueCoding(code: code, system: system, display: display)
                #expect(testValues[index] == valueCoding)

            default:
                Issue.record("Expected a coding value.")
            }
        }
    }
    @Test("Multiple ResearchKit answers cannot violate a single-choice Questionnaire")
    func singleChoiceCardinalityFailsClosed() throws {
        let item = QuestionnaireItem(
            linkId: "choiceResult".asFHIRStringPrimitive(),
            repeats: FHIRPrimitive(false),
            text: "Choice result".asFHIRStringPrimitive(),
            type: FHIRPrimitive(.choice)
        )
        let result = ORKChoiceQuestionResult(identifier: "choiceResult")
        result.choiceAnswers = [
            "one" as any NSSecureCoding & NSCopying & NSObjectProtocol,
            "two" as any NSSecureCoding & NSCopying & NSObjectProtocol
        ]
        #expect(throws: ResearchKitFHIRConversionError.invalidAnswerCardinality(
            linkID: "choiceResult",
            answerCount: 2
        )) {
            try createTaskResult(result).fhirResponse(
                using: context(questionnaire: questionnaire(items: [item]))
            )
        }
    }
    @Test("A non-string ResearchKit choice token fails instead of disappearing")
    func unsupportedChoiceAnswerFailsClosed() throws {
        let item = QuestionnaireItem(
            linkId: "choiceResult".asFHIRStringPrimitive(),
            repeats: FHIRPrimitive(true),
            text: "Choice result".asFHIRStringPrimitive(),
            type: FHIRPrimitive(.choice)
        )
        let result = ORKChoiceQuestionResult(identifier: "choiceResult")
        result.choiceAnswers = [NSNumber(value: 1)]

        #expect(throws: ResearchKitFHIRConversionError.unsupportedChoiceAnswer(
            resultIdentifier: "choiceResult"
        )) {
            try createTaskResult(result).fhirResponse(
                using: context(questionnaire: questionnaire(items: [item]))
            )
        }
    }
    @Test("Repeated attachments are an explicit adapter limitation, not an IG prohibition")
    func repeatedAttachmentLayoutIsRejectedPrecisely() throws {
        let item = QuestionnaireItem(
            linkId: "File Result".asFHIRStringPrimitive(),
            repeats: FHIRPrimitive(true),
            text: "Images".asFHIRStringPrimitive(),
            type: FHIRPrimitive(.attachment)
        )
        #expect(throws: ResearchKitFHIRConversionError.unsupportedRepeatedAttachment(linkID: "File Result")) {
            try context(questionnaire: questionnaire(items: [item]))
        }
    }
    @Test("Attachment result")
    func testAttachmentResult() throws {
        let fileResult = ORKFileResult(identifier: "File Result")
        fileResult.fileURL = URL(fileURLWithPath: "/tmp/researchkit-image.jpg")

        let taskResult = createTaskResult(fileResult)

        let fhirResponse = try taskResult.fhirResponse(using: context { identifier, localURL in
            #expect(identifier == "File Result")
            #expect(localURL.isFileURL)
            return Attachment(
                contentType: "image/jpeg".asFHIRStringPrimitive(),
                hash: FHIRPrimitive(Base64Binary("AQID")),
                size: FHIRPrimitive(FHIRUnsignedInteger(3)),
                url: FHIRPrimitive(FHIRURI(stringLiteral: "https://objects.example.org/image.jpg"))
            )
        })
        let answer = fhirResponse.item?.first?.answer?.first?.value

        guard case let .attachment(fhirAttachment) = answer else {
            Issue.record("Could not extract attachment file URL.")
            return
        }

        #expect(fhirAttachment.url?.value?.url.absoluteString == "https://objects.example.org/image.jpg")
        #expect(fhirAttachment.contentType?.value?.string == "image/jpeg")
        #expect(fhirAttachment.hash != nil)
        #expect(fhirAttachment.size?.value?.integer == 3)
    }
    @Test("A local file result requires explicit staging and never leaks file URLs")
    func localAttachmentRequiresResolver() throws {
        let fileResult = ORKFileResult(identifier: "File Result")
        fileResult.fileURL = URL(fileURLWithPath: "/tmp/private-image.jpg")
        let taskResult = createTaskResult(fileResult)

        #expect(throws: ResearchKitFHIRConversionError.attachmentResolverRequired(resultIdentifier: "File Result")) {
            try taskResult.fhirResponse(using: context())
        }

        #expect(throws: ResearchKitFHIRConversionError.invalidResolvedAttachment(
            resultIdentifier: "File Result",
            reason: "contentType is required"
        )) {
            try taskResult.fhirResponse(using: context { _, _ in
                Attachment(url: FHIRPrimitive(FHIRURI(stringLiteral: "file:///tmp/private-image.jpg")))
            })
        }
    }
    @Test("ORKFileResult with no URL")
    func testORKFileResultWithNoURL() throws {
        let fileResult = ORKFileResult(identifier: "File Result")
        fileResult.fileURL = nil

        let taskResult = createTaskResult(fileResult)
        let fhirResponse = try taskResult.fhirResponse(using: context())
        let answer = fhirResponse.item?.first?.answer?.first?.value

        #expect(answer == nil)
    }
}
