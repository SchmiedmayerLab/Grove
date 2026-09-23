//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

public import Foundation


@available(iOS 18, macOS 15, watchOS 11, *)
extension Questionnaire {
    /// A coded concept (FHIR `CodeableConcept`): its codings and the text shown for it.
    public struct Concept: Hashable, Sendable {
        public var codes: [Task.Code]
        public var text: LocalizedText?

        public init(codes: [Task.Code], text: LocalizedText? = nil) {
            self.codes = codes
            self.text = text
        }
    }

    /// A context the questionnaire is intended for (FHIR `useContext`).
    public struct UsageContext: Hashable, Sendable {
        /// What the context is, in one of the kinds FHIR allows.
        public enum Value: Hashable, Sendable {
            case concept(Concept)
            case quantity(Quantity)
            case range(low: Quantity?, high: Quantity?)
            case reference(Reference)
        }

        /// An amount (FHIR `Quantity`), such as an age the questionnaire is meant for.
        public struct Quantity: Hashable, Sendable {
            public var value: Decimal?
            public var comparator: String?
            /// The unit as displayed.
            public var unit: LocalizedText?
            public var system: URL?
            public var code: String?

            public init(value: Decimal?, comparator: String? = nil, unit: LocalizedText? = nil, system: URL? = nil, code: String? = nil) {
                self.value = value
                self.comparator = comparator
                self.unit = unit
                self.system = system
                self.code = code
            }
        }

        /// A resource the context names (FHIR `Reference`).
        public struct Reference: Hashable, Sendable {
            public var reference: String?
            public var type: URL?
            /// The system of the identifier the reference carries instead of, or alongside, a literal reference.
            public var identifierSystem: URL?
            public var identifierValue: String?
            public var display: LocalizedText?

            public init(
                reference: String? = nil,
                type: URL? = nil,
                identifierSystem: URL? = nil,
                identifierValue: String? = nil,
                display: LocalizedText? = nil
            ) {
                self.reference = reference
                self.type = type
                self.identifierSystem = identifierSystem
                self.identifierValue = identifierValue
                self.display = display
            }
        }

        /// The kind of context, such as `focus`.
        public var code: Task.Code
        public var value: Value

        public init(code: Task.Code, value: Value) {
            self.code = code
            self.value = value
        }
    }

    /// How an item takes part in SDC observation extraction.
    public struct ObservationExtraction: Hashable, Sendable {
        /// The item's `observationExtract` marking.
        public enum Marking: Hashable, Sendable {
            /// `valueBoolean`: whether the item extracts as an Observation of its own.
            case extracts(Bool)
            /// `valueCode`: how the item relates to the Observation its parent extracts, such as `component`.
            case relation(String)
        }

        public var marking: Marking?
        /// The categories the extracted Observation carries (`observation-extract-category`).
        public var categories: [Concept]

        public init(marking: Marking?, categories: [Concept] = []) {
            self.marking = marking
            self.categories = categories
        }
    }
}
