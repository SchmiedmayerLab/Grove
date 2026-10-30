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
}
