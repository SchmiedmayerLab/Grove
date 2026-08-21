//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import FHIRModelsExtensions
private import Foundation
public import GroveQuestionnaire
public import ModelsR4
private import PencilKit
private import struct SwiftUI.Color


/// The identifiers the current Grove implementation guide publishes for annotate-image items.
@available(iOS 18, macOS 15, watchOS 11, *)
extension AnnotateImageQuestionKind {
    private static let base = "https://grovealliance.org/fhir/core"

    fileprivate static let itemControlSystem = "\(base)/CodeSystem/grove-questionnaire-item-control"
    fileprivate static let region = "\(base)/StructureDefinition/grove-annotate-image-region"
}


@available(iOS 18, macOS 15, watchOS 11, *)
extension AnnotateImageQuestionKind: QuestionKindDefinitionWithFHIRDecodingSupport {
    public static func parse( // swiftlint:disable:this function_body_length
        _ item: QuestionnaireItem
    ) throws(GroveQuestionnaire.Questionnaire.FHIRConversionError) -> AnnotateImageConfig? {
        let itemControlExts = item.extensions(for: "http://hl7.org/fhir/StructureDefinition/questionnaire-itemControl")
        guard itemControlExts.count == 1,
              let itemControlExt = itemControlExts.first,
              let itemControlCoding = itemControlExt.value?.codeableConceptValue?.coding?.first,
              Self.itemControlSystem == itemControlCoding.system?.value?.url.absoluteString,
              itemControlCoding.code == "annotate-image" else {
            return nil
        }
        let regionExts = item.extensions(for: Self.region)
        return AnnotateImageConfig(
            inputImage: try Self.baseImage(of: item),
            regions: try regionExts.map { regionExt throws(GroveQuestionnaire.Questionnaire.FHIRConversionError) in
                // swiftlint:disable:previous closure_body_length
                let labelExts = regionExt.extensions(for: "label")
                let colorExts = regionExt.extensions(for: "color")
                guard labelExts.count == 1 else {
                    throw .other("Must specify exactly one (1) label per region in annotate-image question!")
                }
                guard colorExts.count == 1 else {
                    throw .other("Must specify exactly one (1) color per region in annotate-image question!")
                }
                // The guide types `color` as a code and `label` as a string; both spellings read.
                let label: String? = labelExts.first?.value?.stringValue
                let color: String? = colorExts.first?.value?.stringValue
                guard let label, let color else {
                    throw .other("Region label and color must be coded or string values.")
                }
                let colorMapping: [String: Color] = [
                    "red": .red,
                    "orange": .orange,
                    "yellow": .yellow,
                    "green": .green,
                    "mint": .mint,
                    "teal": .teal,
                    "cyan": .cyan,
                    "blue": .blue,
                    "indigo": .indigo,
                    "purple": .purple,
                    "pink": .pink,
                    "brown": .brown,
                    "white": .white,
                    "gray": .gray,
                    "black": .black,
                    "clear": .clear,
                    "primary": .primary,
                    "secondary": .secondary
                ]
                guard let color = colorMapping[color] else {
                    throw .other("Invalid color '\(color)'")
                }
                return .init(name: label, color: color)
            }
        )
    }

    /// The image the participant annotates.
    ///
    /// The guide carries it inline as an SDC `itemMedia` attachment.
    private static func baseImage(
        of item: QuestionnaireItem
    ) throws(GroveQuestionnaire.Questionnaire.FHIRConversionError) -> AnnotateImageConfig.InputImage {
        if case .attachment(let attachment)? = item.extensions(
            for: "http://hl7.org/fhir/uv/sdc/StructureDefinition/sdc-questionnaire-itemMedia"
        ).first?.value {
            guard let base64 = attachment.data?.value?.dataString, let data = Data(base64Encoded: base64) else {
                throw .other("The itemMedia attachment of an annotate-image question must carry inline data")
            }
            return .inlineData(data)
        }
        throw .other("An annotate-image question must carry its base image in an itemMedia attachment")
    }
}

@available(iOS 18, macOS 15, watchOS 11, *)
extension QuestionnaireResponses.ImageAnnotation: GroveQuestionnaire.QuestionnaireResponses.CustomResponseValueProtocolWithFHIRSupport {
    private struct FHIRConversionError: LocalizedError {
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
        throw FHIRConversionError("Image annotation FHIR encoding is not supported on this platform.")
        #else
        let baseImage: UIImage
        switch task.kind.variant {
        case .custom(questionKind: _, let config):
            guard let config = config as? AnnotateImageConfig else {
                throw FHIRConversionError("Invalid task kind")
            }
            guard let image = config.inputImage.image() else {
                // Simply draw the annotation onto a clear backgrund in this case? (no.)
                throw FHIRConversionError("Unable to obtain baseImage")
            }
            baseImage = image
        default:
            throw FHIRConversionError("Invalid task kind")
        }
        guard let annotatedImage = self.draw(onto: baseImage) else {
            throw FHIRConversionError("Unable to draw annotated image")
        }
        let tmpUrl = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, conformingTo: .png)
        guard let pngData = annotatedImage.pngData() else {
            throw FHIRConversionError("Unable to process annotated image")
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
