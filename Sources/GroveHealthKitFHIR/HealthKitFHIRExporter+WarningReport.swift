//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

#if canImport(HealthKit)

import Foundation
import GroveFHIRContract


@available(iOS 18, macOS 15, watchOS 11, *)
extension HealthKitFHIRExporter {
    /// The kinds of warning many exports raised, each with its HealthKit cause and how many samples of each type raised
    /// it: a summary to log once for a batch, where ``Export/warnings`` repeats each kind for every sample.
    ///
    /// ``add(_:)`` every export of the batch, then log ``description``. The report counts samples, not warnings: an
    /// export counts once for each code it raised, however many elements the code is located at, such as both ends of
    /// a Period written in UTC. It keeps no sample identity, so an export added twice counts twice. A refusal carries
    /// no warnings, so it adds nothing; its reason is its ``HealthKitConversionError``.
    public struct WarningReport: Sendable, CustomStringConvertible {
        /// One warning code and the samples that raised it.
        public struct Kind: Hashable, Sendable {
            /// The registered rule's code, such as `mobile-omission.source-offset`.
            public let code: String
            /// What the implementation guide says the rule means.
            public let reason: String
            /// What HealthKit supplied, or lacked, that raises the code, in plain words; the ``reason`` for a code
            /// this adapter does not raise.
            public let cause: String
            /// Every element the code was located at.
            public private(set) var locations: Set<String> = []
            /// How many samples raised the code, by HealthKit type identifier (``Export/Source/typeIdentifier``).
            public private(set) var sampleCountByType: [String: Int] = [:]

            /// How many samples raised the code.
            public var sampleCount: Int {
                sampleCountByType.values.reduce(0, +)
            }

            /// The block ``WarningReport/description`` renders for this kind.
            fileprivate var rendered: String {
                let types = sampleCountByType.sorted { lhs, rhs in
                    lhs.value == rhs.value ? lhs.key < rhs.key : lhs.value > rhs.value
                }
                let counts = types.map { "\($0.key) \(Self.formatted($0.value))" }.joined(separator: ", ")
                let samples = "\(Self.formatted(sampleCount)) \(sampleCount == 1 ? "sample" : "samples")"
                return "\(code) at \(locations.sorted().joined(separator: ", "))\n  \(cause) — \(samples): \(counts)"
            }

            fileprivate init(_ warning: ProducerDiagnostic) {
                code = warning.code
                reason = warning.reason
                cause = Self.cause(of: warning.code) ?? warning.reason
            }

            /// The HealthKit cause of each code this adapter raises, as its assembly decides to raise it.
            private static func cause(of code: String) -> String? {
                switch ExchangeGraphRule(rawValue: code) {
                case .mobileOmissionSourceOffset:
                    "Effective time written in UTC: the sample names no HKMetadataKeyTimeZone (nor, for blood pressure, "
                        + "do its members agree on one)"
                case .mobileOmissionRecordingDevice:
                    "No recording Device: the recording-device policy resolved the sample's HKDevice to no physical unit "
                        + "(by default, the device has no localIdentifier)"
                case .mobileOmissionUnmodeledMetadata:
                    "Metadata withheld: the sample, or a correlation member, workout event or workout activity it "
                        + "contains, carries metadata keys its graph does not represent"
                default:
                    nil
                }
            }

            /// `count` with grouped thousands, the same in every locale.
            private static func formatted(_ count: Int) -> String {
                count.formatted(.number.locale(Locale(identifier: "en_US")))
            }

            fileprivate mutating func add(_ warnings: [ProducerDiagnostic], of typeIdentifier: String) {
                locations.formUnion(warnings.map(\.location))
                sampleCountByType[typeIdentifier, default: 0] += 1
            }
        }

        private var kindsByCode: [String: Kind] = [:]

        /// Every kind raised so far, the most samples first, then by code.
        public var kinds: [Kind] {
            kindsByCode.values.sorted { lhs, rhs in
                lhs.sampleCount == rhs.sampleCount ? lhs.code < rhs.code : lhs.sampleCount > rhs.sampleCount
            }
        }

        /// Whether no export added so far raised a warning.
        public var isEmpty: Bool {
            kindsByCode.isEmpty
        }

        /// One block per kind, in ``kinds`` order: the code and every element it was located at, then its cause and
        /// how many samples raised it, in total and by type identifier, the most first, then by identifier.
        public var description: String {
            isEmpty ? "No warnings" : kinds.map(\.rendered).joined(separator: "\n")
        }

        /// An empty report.
        public init() {}

        /// Counts the warnings of `export`, its sample once for each code it raised.
        public mutating func add(_ export: Export) {
            for (code, warnings) in Dictionary(grouping: export.warnings, by: \.code) {
                kindsByCode[code, default: Kind(warnings[0])].add(warnings, of: export.source.typeIdentifier)
            }
        }
    }
}

#endif
