//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

public import GroveFHIRContract


/// A conversion either produces one complete record or explicitly omits a source element.
public struct ProviderConversionResult: Sendable {
    public struct Omission: Sendable, Equatable {
        public enum Reason: Sendable, Equatable {
            case notYetImplemented
            case notAdmitted
            case missingRequiredEvidence
        }

        public let sourceToken: String
        public let element: String
        public let reason: Reason
    }

    public let sourceToken: String
    public let record: ExchangeRecord?
    public let omissions: [Omission]
}
