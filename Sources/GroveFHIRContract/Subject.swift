//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

public import ModelsR4


/// The participant a record is about.
///
/// The identifier is the deployment's pseudonym. By default it travels as an identifier-only
/// logical Patient reference; a deployment that supplies a Patient bundles it as an entry instead. A bundled Patient
/// carries the pseudonym as its only identifier without a Grove role, so every reference to it states the same subject;
/// another business identifier of the participant, such as a medical record number, does not travel on it, and
/// ``ExchangeProducer`` refuses such a Patient.
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
            // A Patient that already carries the pseudonym, typed or with a `use`, keeps it as its own.
            if patient.identifier?.contains(where: { (try? BusinessIdentifier($0)) == identifier }) != true {
                patient.identifier = (patient.identifier ?? []) + [identifier.fhirIdentifier]
            }
            return patient
        }
    }
}
