//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

// swiftlint:disable file_types_order

public import Foundation
#if canImport(UIKit)
public import class UIKit.UIImage
#endif


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
        /// The image travels with the questionnaire (SDC `itemMedia`).
        case inlineData(Data)

        #if canImport(UIKit)
        /// Loads the image, if it can be found and decoded.
        public func image() -> UIImage? {
            switch self {
            case .namedInMainBundle(let filename):
                guard let url = Bundle.main.url(forResource: filename, withExtension: nil),
                      let data = try? Data(contentsOf: url) else {
                    return nil
                }
                return UIImage(data: data)
            case .inlineData(let data):
                return UIImage(data: data)
            }
        }
        #endif
    }

    public struct Region: Hashable, Identifiable, Sendable {
        public let name: String
        public let color: AnnotationColor

        public var id: some Hashable {
            name
        }

        public init(name: String, color: AnnotationColor) {
            self.name = name
            self.color = color
        }
    }

    /// The image onto which the annotations should be drawn.
    public let inputImage: InputImage
    /// The regions offered to the user to select from.
    ///
    /// - Important: Regions are identified by their ``Region/name``. It is invalid for multiple regions to have identical names.
    public let regions: [Region]

    public init(inputImage: InputImage, regions: [Region]) {
        self.inputImage = inputImage
        self.regions = regions
    }
}


/// The colour a region is drawn in, as sRGB components.
///
/// Components rather than a `SwiftUI.Color` so a questionnaire keeps its full definition on every
/// platform; the on-screen module turns one of these into a `Color` when it draws.
public struct AnnotationColor: Hashable, Sendable {
    /// The sRGB red component, 0...1.
    public let red: Double
    /// The sRGB green component, 0...1.
    public let green: Double
    /// The sRGB blue component, 0...1.
    public let blue: Double
    /// The opacity, 0...1.
    public let opacity: Double

    public init(red: Double, green: Double, blue: Double, opacity: Double = 1) {
        self.red = red
        self.green = green
        self.blue = blue
        self.opacity = opacity
    }
}


extension AnnotationColor {
    // swiftlint:disable missing_docs
    public static let red = Self(red: 1, green: 0.23, blue: 0.19)
    public static let orange = Self(red: 1, green: 0.58, blue: 0)
    public static let yellow = Self(red: 1, green: 0.8, blue: 0)
    public static let green = Self(red: 0.2, green: 0.78, blue: 0.35)
    public static let blue = Self(red: 0, green: 0.48, blue: 1)
    public static let purple = Self(red: 0.69, green: 0.32, blue: 0.87)
    // swiftlint:enable missing_docs
}


/// Prompts the user to respond to a question by highlighting regions on an image.
///
/// The kind is defined here rather than alongside its view so a questionnaire using it can be read,
/// converted, and stored anywhere; `GroveQuestionnaireUI` supplies the editor that fills it in.
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
}


@available(iOS 18, macOS 15, watchOS 11, *)
extension Questionnaire {
    /// The question kinds Grove understands without the caller registering them.
    package static let builtinQuestionKinds: [any QuestionKindDefinition.Type] = [
        AnnotateImageQuestionKind.self
    ]
}
