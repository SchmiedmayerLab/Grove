//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2022 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import Foundation
#if ResearchKit
import FHIRModelsExtensions
import ModelsR4
import ResearchKit
#endif


struct ValueCoding: Equatable, Codable, RawRepresentable {
    enum CodingKeys: String, CodingKey {
        case code
        case system
        case display
    }
    
    
    let code: String
    let system: String
    let display: String?
    
    /// Canonical JSON used as ResearchKit's answer token.
    ///
    /// This construction is total for Swift `String` and cannot fall back to `{}`. Key order
    /// is fixed because navigation predicates compare the serialized answer representation.
    var rawValue: String {
        let displayValue = display.map(Self.jsonString) ?? "null"
        return "{\"code\":\(Self.jsonString(code)),\"display\":\(displayValue),\"system\":\(Self.jsonString(system))}"
    }
    
    
    init(code: String, system: String, display: String?) {
        self.code = code
        self.system = system
        self.display = display
    }
    
    init?(rawValue: String) {
        let data = Data(rawValue.utf8)
        guard let valueCoding = try? JSONDecoder().decode(Self.self, from: data),
              !valueCoding.code.isEmpty,
              let systemURL = URL(string: valueCoding.system),
              systemURL.scheme != nil else {
            return nil
        }
        
        self = valueCoding
    }
    
    init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        self.code = try values.decode(String.self, forKey: .code)
        self.system = try values.decode(String.self, forKey: .system)
        self.display = try values.decodeIfPresent(String.self, forKey: .display)
    }

    /// JSON string escaping without a throwing encoder. Unicode scalar values are retained,
    /// while JSON syntax and every C0 control character are escaped deterministically.
    fileprivate static func jsonString(_ value: String) -> String {
        var result = "\""
        for scalar in value.unicodeScalars {
            switch scalar.value {
            case 0x08: result += "\\b"
            case 0x09: result += "\\t"
            case 0x0A: result += "\\n"
            case 0x0C: result += "\\f"
            case 0x0D: result += "\\r"
            case 0x22: result += "\\\""
            case 0x5C: result += "\\\\"
            case 0x00...0x1F:
                result += String(format: "\\u%04X", scalar.value)
            default:
                result.unicodeScalars.append(scalar)
            }
        }
        result += "\""
        return result
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(code, forKey: .code)
        try container.encode(system, forKey: .system)
        try container.encode(display, forKey: .display)
    }
}


extension ValueCoding {
    /// Returns a regular expression which can be used when creating `ORKChoiceQuestionResult` predicates.
    /// The reason why this exists, is that there might, in some cases, be a mismatch between the information we have here
    /// in the ValueCoding, and the information the `ORKChoiceQuestionResult` stores.
    /// This is caused by the fact that in the context in which the question is answered (i.e., in the context of the question item itself),
    /// the `display` value is known (and encoded into the result object), but if we want to check for some previous question's result
    /// (e.g., in the context of a later question's `enableWhen` conditions), then the `display` value will not be known.
    /// (Because it typically isn't included in the `enableWhen` condition.)
    /// However, if we were to check the `enableWhen` condition's valueCoding against the one of the question answering context,
    /// we'd end up comparing one with a null `display` value against one with a non-null `display` value.
    /// (This would, obviously, cause the comparison to always fail, and conditional questions would never be enabled and presented to the patient.)
    var patternForMatchingORKChoiceQuestionResult: String { // swiftlint:disable:this identifier_name
        if let display {
            return #"^\{"code":\#(code.jsonPattern),"display":\#(display.jsonPattern),"system":\#(system.jsonPattern)\}$"#
        } else {
            return #"^\{"code":\#(code.jsonPattern),"display":.*,"system":\#(system.jsonPattern)\}$"#
        }
    }
}

extension String {
    fileprivate var jsonPattern: String {
        NSRegularExpression.escapedPattern(for: ValueCoding.jsonString(self))
    }
}


#if ResearchKit
extension ORKTaskResult {
    func createChoiceResponse(
        _ result: ORKChoiceQuestionResult
    ) throws -> [QuestionnaireResponseItemAnswer.ValueX] {
        guard let answerArray = result.answer as? NSArray, answerArray.count > 0 else { // swiftlint:disable:this empty_count
            return []
        }

        var responses: [QuestionnaireResponseItemAnswer.ValueX] = []
        for answer in answerArray {
            if let valueCodingString = answer as? String, let valueCoding = ValueCoding(rawValue: valueCodingString) {
                let coding = Coding(
                    code: FHIRPrimitive(FHIRString(valueCoding.code)),
                    display: valueCoding.display.map { FHIRPrimitive(FHIRString($0)) },
                    system: FHIRPrimitive(FHIRURI(stringLiteral: valueCoding.system))
                )
                responses += [.coding(coding)]
            } else if let answerString = answer as? String, answerString.first == "{" {
                throw ResearchKitFHIRConversionError.malformedCodedAnswer(
                    resultIdentifier: result.identifier
                )
            } else if let answerString = answer as? String {
                responses += [.string(FHIRPrimitive(FHIRString(answerString)))]
            } else {
                throw ResearchKitFHIRConversionError.unsupportedChoiceAnswer(
                    resultIdentifier: result.identifier
                )
            }
        }
        return responses
    }

    func createBooleanResponse(
        _ result: ORKBooleanQuestionResult
    ) -> QuestionnaireResponseItemAnswer.ValueX? {
        guard let booleanAnswer = result.booleanAnswer else {
            return nil
        }
        return .boolean(FHIRPrimitive(FHIRBool(booleanAnswer.boolValue)))
    }

    func createDateResponse(
        _ result: ORKDateQuestionResult,
        using context: ResearchKitFHIRConversionContext
    ) throws -> QuestionnaireResponseItemAnswer.ValueX? {
        guard let dateAnswer = result.dateAnswer else {
            return nil
        }

        if result.questionType == .date {
            do {
                return .date(FHIRPrimitive(try FHIRDate(
                    date: dateAnswer,
                    timeZone: context.authoredTimeZone
                )))
            } catch {
                throw ResearchKitFHIRConversionError.temporalConversion(
                    resultIdentifier: result.identifier,
                    reason: String(describing: error)
                )
            }
        } else {
            do {
                return .dateTime(FHIRPrimitive(try DateTime(
                    date: dateAnswer,
                    timeZone: context.authoredTimeZone
                )))
            } catch {
                throw ResearchKitFHIRConversionError.temporalConversion(
                    resultIdentifier: result.identifier,
                    reason: String(describing: error)
                )
            }
        }
    }

    func createTimeResponse(
        _ result: ORKTimeOfDayQuestionResult
    ) -> QuestionnaireResponseItemAnswer.ValueX? {
        guard let timeDateComponents = result.dateComponentsAnswer,
              let hour = UInt8(exactly: timeDateComponents.hour ?? 0),
              let minute = UInt8(exactly: timeDateComponents.minute ?? 0) else {
            return nil
        }
        let fhirTime = FHIRPrimitive(FHIRTime(hour: hour, minute: minute, second: 0))
        return .time(fhirTime)
    }

    func createAttachmentResponse(
        _ result: ORKFileResult,
        using context: ResearchKitFHIRConversionContext
    ) throws -> QuestionnaireResponseItemAnswer.ValueX? {
        guard let url = result.fileURL else {
            return nil
        }
        guard url.isFileURL else {
            throw ResearchKitFHIRConversionError.invalidResolvedAttachment(
                resultIdentifier: result.identifier,
                reason: "ResearchKit source URL must be a local file"
            )
        }
        guard let resolver = context.attachmentResolver else {
            throw ResearchKitFHIRConversionError.attachmentResolverRequired(
                resultIdentifier: result.identifier
            )
        }
        let attachment = try resolver(result.identifier, url)
        try validateResolvedAttachment(attachment, resultIdentifier: result.identifier)
        return .attachment(attachment)
    }

    private func validateResolvedAttachment(
        _ attachment: Attachment,
        resultIdentifier: String
    ) throws {
        guard let contentType = attachment.contentType?.value?.string,
              contentType == contentType.trimmingCharacters(in: .whitespacesAndNewlines),
              !contentType.isEmpty else {
            throw ResearchKitFHIRConversionError.invalidResolvedAttachment(
                resultIdentifier: resultIdentifier,
                reason: "contentType is required"
            )
        }
        guard attachment.hash?.value != nil else {
            throw ResearchKitFHIRConversionError.invalidResolvedAttachment(
                resultIdentifier: resultIdentifier,
                reason: "SHA-1 hash is required"
            )
        }
        guard attachment.size?.value != nil else {
            throw ResearchKitFHIRConversionError.invalidResolvedAttachment(
                resultIdentifier: resultIdentifier,
                reason: "size is required"
            )
        }
        if attachment.data?.value != nil {
            return
        }
        guard let url = attachment.url?.value?.url,
              let scheme = url.scheme?.lowercased(),
              ["http", "https"].contains(scheme),
              url.host?.isEmpty == false else {
            throw ResearchKitFHIRConversionError.invalidResolvedAttachment(
                resultIdentifier: resultIdentifier,
                reason: "attachment must contain bytes or an HTTP(S) URL"
            )
        }
    }
}
#endif
