//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

public import Foundation
public import ModelsR4


/// The exact canonical identity of one Questionnaire definition.
///
/// FHIR canonical identity includes both the canonical URL and its business version. Comparing
/// only the URL can incorrectly collapse simultaneously active revisions of one instrument.
public struct QuestionnaireCanonicalIdentity: Hashable, Sendable {
    public let url: URL
    public let version: String

    public init(url: URL, version: String) {
        self.url = url
        self.version = version
    }

    /// Reads the URL and version already separated by ModelsR4's Canonical representation.
    public init?(_ canonical: FHIRPrimitive<Canonical>?) {
        guard let canonical = canonical?.value,
              let version = canonical.version,
              !version.isEmpty else {
            return nil
        }
        self.init(url: canonical.url, version: version)
    }

    /// Reads the exact identity declared by a Questionnaire resource.
    public init?(_ questionnaire: ModelsR4.Questionnaire) {
        guard let url = questionnaire.url?.value?.url,
              let version = questionnaire.version?.value?.string,
              !version.isEmpty else {
            return nil
        }
        self.init(url: url, version: version)
    }
}


extension ModelsR4.Questionnaire {
    /// The exact canonical URL and business version, when both are present.
    public var canonicalIdentity: QuestionnaireCanonicalIdentity? {
        QuestionnaireCanonicalIdentity(self)
    }
}


extension ModelsR4.QuestionnaireResponse {
    /// The exact Questionnaire identity carried by this response.
    public var questionnaireCanonicalIdentity: QuestionnaireCanonicalIdentity? {
        QuestionnaireCanonicalIdentity(questionnaire)
    }
}
