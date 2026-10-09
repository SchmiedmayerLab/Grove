//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

public import ModelsR4


/// The participant an event is about.
///
/// The identifier is the deployment's pseudonym. By default it travels as an identifier-only
/// logical Patient reference; a deployment that supplies a Patient bundles it as an entry instead.
public enum Subject: Hashable, Sendable {
    case logical(BusinessIdentifier)
    case bundled(BusinessIdentifier, Patient)

    /// The pseudonym, however the subject travels.
    public var identifier: BusinessIdentifier {
        switch self {
        case .logical(let identifier), .bundled(let identifier, _):
            identifier
        }
    }

    /// The Patient a graph bundles for this subject: the deployment's, which always carries the pseudonym, or for a
    /// logical subject one stating only the pseudonym, as Questionnaire's graphs bundle it.
    package var bundledPatient: Patient {
        switch self {
        case .logical(let identifier):
            return Patient(identifier: [identifier.fhirIdentifier])
        case .bundled(let identifier, var patient):
            if patient.identifier?.contains(identifier.fhirIdentifier) != true {
                patient.identifier = (patient.identifier ?? []) + [identifier.fhirIdentifier]
            }
            return patient
        }
    }
}
