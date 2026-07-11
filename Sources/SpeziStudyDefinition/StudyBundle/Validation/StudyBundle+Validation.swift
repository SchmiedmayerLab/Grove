//
// This source file is part of the Stanford Spezi open source project
//
// SPDX-FileCopyrightText: 2025 Stanford University
//
// SPDX-License-Identifier: MIT
//

import Foundation
import ModelsR4
import SpeziFoundation
import SpeziLocalization


@available(iOS 18, macOS 15, watchOS 11, *)
extension StudyBundle {
    @_spi(APISupport)
    public enum BundleValidationIssue: Hashable, DiagnosticMessageConvertible, CustomStringConvertible, Sendable {
        case general(GeneralIssue)
        case article(ArticleIssue)
        case questionnaire(QuestionnaireIssue)
        
        public enum GeneralIssue: Hashable, Sendable {
            /// The study bundle doesn't contain any files that would match the file reference found in the study definition.
            case noFilesMatchingFileRef(StudyBundle.FileReference)
        }
        
        public enum ArticleIssue: Hashable, Sendable {
            case documentMetadataMissingId(fileRef: LocalizedFileReference)
            case documentMetadataIdMismatchToBase(
                baseLocalization: LocalizedFileReference,
                localizedFileRef: LocalizedFileReference,
                baseId: String,
                localizedFileRefId: String
            )
        }
        
        public var description: String {
            diagnostic.message
        }
        
        var diagnostic: DiagnosticMessage {
            switch self {
            case let .general(.noFilesMatchingFileRef(fileRef)):
                "No files matching file ref '\(fileRef)'"
            case let .article(.documentMetadataMissingId(fileRef)):
                "Article is missing 'id' in metadata: \(fileRef.filenameIncludingLocalization)"
            case let .article(.documentMetadataIdMismatchToBase(baseLocalization, fileRef, baseId, localizedFileRefId)):
                DiagnosticMessage("Localized Article id does not match base localization's id") {
                    DiagnosticMessage.Item("base localization", value: baseLocalization)
                    DiagnosticMessage.Item("localized article", value: fileRef)
                    DiagnosticMessage.Item("base id", value: baseId)
                    DiagnosticMessage.Item("localized articleid", value: localizedFileRefId)
                }
            case let .questionnaire(.missingField(fileRef, path, comment)):
                DiagnosticMessage("Questionnaire: missing field value") {
                    DiagnosticMessage.Item("file", value: fileRef)
                    DiagnosticMessage.Item("path", value: path)
                    DiagnosticMessage.Item("comment", omitIfNil: true, value: comment)
                }
            case let .questionnaire(.invalidField(fileRef, path, fieldValue, failureReason)):
                DiagnosticMessage("Questionnaire: invalid field value") {
                    DiagnosticMessage.Item("file", value: fileRef)
                    DiagnosticMessage.Item("path", value: path)
                    DiagnosticMessage.Item("value", value: fieldValue)
                    DiagnosticMessage.Item("issue", value: failureReason)
                }
            case let .questionnaire(.conflictingFieldValues(fileRef, fstPath, fstValue, sndPath, sndValue, comment)):
                DiagnosticMessage("Conflicting field values withon questionnaire") {
                    DiagnosticMessage.Item("questionnaire", value: fileRef)
                    DiagnosticMessage.Item("1st value path", value: fstPath)
                    DiagnosticMessage.Item("1st value", value: fstValue)
                    DiagnosticMessage.Item("2nd value path", value: sndPath)
                    DiagnosticMessage.Item("2nd value", value: sndValue)
                    DiagnosticMessage.Item("comment", omitIfNil: true, value: comment)
                }
            case let .questionnaire(.mismatchingFieldValues(baseFileRef, localizedFileRef, path, baseValue, localizedValue)):
                DiagnosticMessage("Localized Questionnaire: field value does not match base localization") {
                    DiagnosticMessage.Item("base questionnaire", value: baseFileRef)
                    DiagnosticMessage.Item("localized questionnaire", value: localizedFileRef)
                    DiagnosticMessage.Item("path", value: path)
                    DiagnosticMessage.Item("base questionnaire value", value: baseValue)
                    DiagnosticMessage.Item("localized questionnaire value", value: localizedValue)
                }
            case let .questionnaire(.languageDiffersFromFilenameLocalization(fileRef, questionnaireLanguage)):
                DiagnosticMessage("Questionnaire: language in metadata does not match filename localization component") {
                    DiagnosticMessage.Item("questionnaire", value: fileRef)
                    DiagnosticMessage.Item("metadata lang", value: questionnaireLanguage)
                }
            }
        }
    }
    
    
    /// Validates the StudyBundle.
    ///
    /// This function performs the following checks:
    /// - for informational components:
    ///     - check that each informational component's file ref can be resolved;
    ///     - check that for each article, all localized variants have the same `id` in their metadata;
    /// - for questionnaire components:
    ///     - check that each questionnaire component's file ref can be resolved;
    ///     - check that for each questionnaire, all localized variants share the following properties:
    ///         - questionnaire id
    ///         - number of items in the questionnaire
    ///         - item identifiers
    ///         - item types
    func validate() throws -> [BundleValidationIssue] {
        var issues: [BundleValidationIssue] = []
        issues.append(contentsOf: try validateArticles())
        issues.append(contentsOf: try validateQuestionnaires().map { .questionnaire($0) })
        return issues
    }
}


// MARK: Helpers

@available(iOS 18, macOS 15, watchOS 11, *)
extension LocalizedFileResource {
    init(_ other: StudyBundle.FileReference, locale: Locale = .autoupdatingCurrent) {
        self.init("\(other.category.rawValue)/\(other.filename).\(other.fileExtension)", locale: locale)
    }
}
