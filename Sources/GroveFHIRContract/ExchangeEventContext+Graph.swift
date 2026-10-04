//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import Foundation
package import ModelsR4


extension ExchangeEventContext {
    /// Builds the entry-node keyed study context the catalog recommends for a known enrollment.
    package func studyContext() throws(ExchangeIdentityError) -> StudyContext {
        try StudyContext(subject: subject, studies: studies, event: event, identityScope: identityScope)
    }

    /// What every output's `subject` states, derived the same way the bundled study context is.
    package func subjectReference() throws(ExchangeIdentityError) -> Reference {
        try studyContext().subjectReference
    }

    /// One resolving literal reference per bundled ResearchStudy entry.
    package func studyReferences() throws(ExchangeIdentityError) -> [Reference] {
        try studyContext().studyReferences
    }

    /// The application that mediated the measurement: the converter itself, a distinct application
    /// snapshot, or none.
    package func gatewayURL(converterURL: String) throws(OpaqueIdentityError) -> String? {
        switch converterRole {
        case .assembler:
            return nil
        case .gateway:
            return converterURL
        case .gatewayApplication(let application):
            let snapshot = try identityScope.deviceSnapshot(
                event: event,
                role: .application,
                sourceDeviceToken: application.sourceDeviceToken
            )
            return try? snapshot.fullURLString
        }
    }
}
