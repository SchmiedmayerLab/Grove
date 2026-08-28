//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2022 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import CryptoKit
import FHIRQuestionnaires
import Foundation
import GroveFHIRContract
import ModelsR4
import ResearchKit
import ResearchKitOnFHIR
import ResearchKitSwiftUI
import SwiftUI
import UniformTypeIdentifiers


/// Renders a ResearchKit task from the selected FHIR questionnaire
struct QuestionnaireView: View {
    @Environment(QuestionnaireResponseStorage.self) private var responseStorage
    @Environment(\.dismiss) private var dismiss
    
    @Binding var questionnaire: Questionnaire?
    
    
    var body: some View {
        if let activeQuestionnaire = questionnaire,
           let task = createTask(questionnaire: activeQuestionnaire) {
            ORKOrderedTaskView(tasks: task) { result in
                handleResult(result, questionnaire: activeQuestionnaire)
            }
                .ignoresSafeArea(.container, edges: .bottom)
                .ignoresSafeArea(.keyboard, edges: .bottom)
        } else {
            Text("ERROR_MESSAGE")
        }
    }

    private func handleResult(_ result: TaskResult, questionnaire: Questionnaire) {
        defer {
            dismiss()
        }
        guard case let .completed(taskResult) = result else {
            return // user cancelled
        }
        do {
            guard let authored = taskResult.endDate else {
                throw SampleConversionError.missingCompletionInstant
            }
            let participantID = try BusinessIdentifier(
                system: "https://example.org/fhir/identifier/participant",
                value: "example-participant"
            )
            let subject = Reference(
                identifier: participantID.fhirIdentifier,
                type: "Patient".asFHIRURIPrimitive()
            )
            let responseID = try BusinessIdentifier(
                system: "https://example.org/fhir/identifier/questionnaire-response",
                value: taskResult.taskRunUUID.uuidString.lowercased()
            )
            let context = try ResearchKitFHIRConversionContext(
                questionnaire: questionnaire,
                responseIdentifier: responseID,
                subject: subject,
                authored: authored,
                authoredTimeZone: TimeZone(secondsFromGMT: 0)! // swiftlint:disable:this force_unwrapping
            ) { _, localURL in
                try Self.embeddedAttachment(at: localURL)
            }
            let fhirResponse = try taskResult.fhirResponse(using: context)
            guard let questionnaireIdentifier = fhirResponse.questionnaire?.value?.url else {
                throw SampleConversionError.missingQuestionnaireCanonical
            }
            responseStorage.append(fhirResponse, for: questionnaireIdentifier)
        } catch {
            assertionFailure("FHIR conversion failed: \(error)")
        }
    }

    private static func embeddedAttachment(at url: URL) throws -> Attachment {
        let data = try Data(contentsOf: url)
        guard data.count <= Int(Int32.max),
              let contentType = UTType(filenameExtension: url.pathExtension)?.preferredMIMEType else {
            throw SampleConversionError.invalidAttachment(url)
        }
        return Attachment(
            contentType: contentType.asFHIRStringPrimitive(),
            data: FHIRPrimitive(Base64Binary(with: data)),
            hash: FHIRPrimitive(Base64Binary(with: Data(Insecure.SHA1.hash(data: data)))),
            size: FHIRPrimitive(FHIRUnsignedInteger(Int32(data.count))),
            title: url.lastPathComponent.asFHIRStringPrimitive()
        )
    }

    
    /// Creates a ResearchKit navigable task from a FHIR questionnaire
    /// - Parameter questionnaire: a FHIR questionnaire
    /// - Returns: a ResearchKit navigable task
    private func createTask(questionnaire: Questionnaire) -> ORKNavigableOrderedTask? {
        // Create a completion step to add to the end of the Questionnaire (optional)
        let completionStep = ORKCompletionStep(identifier: "completion-step")
        completionStep.text = String(localized: "COMPLETION_STEP_MESSAGE")
        
        // Create a navigable task from the Questionnaire
        do {
            return try ORKNavigableOrderedTask(
                questionnaire: questionnaire,
                evaluationInstant: .now,
                evaluationTimeZone: .current,
                completionStep: completionStep
            )
        } catch {
            print("Error creating task: \(error)")
        }
        return nil
    }
}


private enum SampleConversionError: Error {
    case invalidAttachment(URL)
    case missingCompletionInstant
    case missingQuestionnaireCanonical
}


#Preview {
    @Previewable @State var questionnaire: Questionnaire? = .textValidationExample
    
    QuestionnaireView(questionnaire: $questionnaire)
}
