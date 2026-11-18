//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

public import GroveFHIRContract


/// The outcome of converting one source record: one complete record, the source elements it omits, or both.
public struct ProviderConversionResult: Sendable {
    /// A source element a conversion omits, and why.
    public struct Omission: Sendable, Equatable {
        /// Why a source element is omitted.
        public enum Reason: Sendable, Equatable {
            /// The guide admits the element, but the converter doesn't convert it yet.
            case notYetImplemented
            /// The guide admits no output for the element.
            case notAdmitted
            /// The source record lacks evidence the conversion requires.
            case missingRequiredEvidence
        }

        /// The source token of the record.
        public let sourceToken: String
        /// The omitted element's path in the provider's payload.
        public let element: String
        /// Why the element is omitted.
        public let reason: Reason
    }

    /// The source token of the record.
    public let sourceToken: String
    /// The exchange record, or `nil` when the conversion produces no output.
    public let record: ExchangeRecord?
    /// The omitted source elements.
    public let omissions: [Omission]
}
