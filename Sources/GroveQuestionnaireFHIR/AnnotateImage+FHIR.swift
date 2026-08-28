//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

private import Foundation
public import GroveQuestionnaire
public import ModelsR4
private import PencilKit

@available(iOS 18, macOS 15, watchOS 11, *)
extension QuestionnaireResponses.ImageAnnotation: GroveQuestionnaire.QuestionnaireResponses.CustomResponseValueProtocolWithFHIRSupport {
    private struct ConversionError: LocalizedError {
        let errorDescription: String?
        
        init(_ message: String) {
            errorDescription = message
        }
    }
    
    public func toFHIR(
        for task: GroveQuestionnaire.Questionnaire.Task
    ) throws -> [QuestionnaireResponseItemAnswer] {
        #if !canImport(UIKit)
        // Rendering the annotated image requires UIKit; parsing annotate-image questionnaires
        // (`QuestionKindDefinitionWithFHIRDecodingSupport` above) still works on all platforms.
        throw ConversionError("Image annotation FHIR encoding is not supported on this platform.")
        #else
        let baseImage: UIImage
        switch task.kind.variant {
        case .custom(questionKind: _, let config):
            guard let config = config as? AnnotateImageConfig else {
                throw ConversionError("Invalid task kind")
            }
            guard let image = config.inputImage.image() else {
                // Simply draw the annotation onto a clear backgrund in this case? (no.)
                throw ConversionError("Unable to obtain baseImage")
            }
            baseImage = image
        default:
            throw ConversionError("Invalid task kind")
        }
        guard let annotatedImage = self.draw(onto: baseImage) else {
            throw ConversionError("Unable to draw annotated image")
        }
        let tmpUrl = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, conformingTo: .png)
        guard let pngData = annotatedImage.pngData() else {
            throw ConversionError("Unable to process annotated image")
        }
        try pngData.write(to: tmpUrl)
        defer {
            try? FileManager.default.removeItem(at: tmpUrl)
        }
        let attachment = try QuestionnaireResponses.CollectedAttachment(url: tmpUrl)
        return try [QuestionnaireResponseItemAnswer(attachment)]
        #endif
    }
}
