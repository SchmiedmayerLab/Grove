//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

// swiftlint:disable file_types_order

public import SwiftUI


@available(iOS 18, macOS 15, watchOS 11, *)
extension Questionnaire.Task.Kind {
    /// A task that asks the user to annotate an image
    public static func annotateImage(_ config: AnnotateImageConfig) -> Self {
        .custom(AnnotateImageQuestionKind.self, config: config)
    }
}


/// Configures an image annotation task.
@available(iOS 18, macOS 15, watchOS 11, *)
public struct AnnotateImageConfig: QuestionKindConfig {
    public enum InputImage: Hashable, Sendable {
        case namedInMainBundle(filename: String)
        
#if canImport(UIKit)
        public func image() -> UIImage? {
            switch self {
            case .namedInMainBundle(let filename):
                guard let url = Bundle.main.url(forResource: filename, withExtension: nil),
                      let data = try? Data(contentsOf: url) else {
                    print("unable to find '\(filename)' in main bundle")
                    return nil
                }
                return UIImage(data: data)
            }
        }
        #endif
    }
    
    public struct Region: Hashable, Identifiable, Sendable {
        public let name: String
        public let color: Color
        
        public var id: some Hashable {
            name
        }
        
        public init(name: String, color: Color) {
            self.name = name
            self.color = color
        }
    }
    
    /// The image onto which the annotations should be drawn.
    public let inputImage: InputImage
    /// The regions offered to the user to select from.
    ///
    /// - Important: Regions are identified by their ``Region/name``. It is invalid for multiple regions to have identical names. If that is the case, the behaviour is undefined.
    public let regions: [Region]
    
    public init(inputImage: InputImage, regions: [Region]) {
        self.inputImage = inputImage
        self.regions = regions
    }
}


/// Prompts the user to respond to a question by highlighting regions on an image.
///
/// ## Topics
///
/// ### Related Types
/// 
/// - ``AnnotateImageConfig``
@available(iOS 18, macOS 15, watchOS 11, *)
public struct AnnotateImageQuestionKind: QuestionKindDefinition {
    public static func validate(
        response: QuestionnaireResponses.Response,
        for config: AnnotateImageConfig
    ) -> QuestionnaireResponses.ResponseValidationResult {
        .ok
    }
    
    public static func makeView(
        for task: Questionnaire.Task,
        using config: AnnotateImageConfig,
        response: Binding<QuestionnaireResponses.Response>
    ) -> some View {
        #if canImport(UIKit)
        AnnotateImageView(
            task: task,
            config: config,
            response: response.value.annotatedImageValue.withDefault(.init())
        )
        #else
        // NOTE: GroveQuestionnaire doesn't have official macOS (or, more generally, non-UIKit) support yet.
        // Image annotation is implemented on top of UIKit and PencilKit; on platforms without UIKit the question kind
        // still exists (so that questionnaires using it can be parsed), but it can neither be rendered nor answered:
        // the task ends up displaying only its title/subtitle, with no way for the user to enter a response.
        //
        // ISSUE: the task nonetheless takes part in completeness checking (`validate` above returns `.ok`, but
        // `QuestionnaireResponses.isMissingResponse(for:)` keeps returning true, since no response can ever be produced).
        // A *required* annotate-image task therefore is an unsatisfiable blocker on these platforms: the section, and with it
        // the questionnaire, can never be completed. (For the same reason, encoding such a response into FHIR throws;
        // see `QuestionnaireResponses.ImageAnnotation.toFHIR(for:)` in GroveQuestionnaireFHIR.)
        EmptyView()
        #endif
    }
}
