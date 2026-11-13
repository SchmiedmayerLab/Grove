//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

#if canImport(HealthKit)

public import GroveFHIRContract
public import HealthKit


@available(iOS 18, macOS 15, watchOS 11, *)
extension HealthKitFHIRExporter {
    /// The HealthKit-specific choices of one exporter: how sources and physical units are stated, and which disclosures
    /// the deployment authorizes. Every source and device fact HealthKit supplies travels: a consumer filters what it does
    /// not need.
    public struct Options: Sendable {
        /// Whether the source is stated as an author. A source no author states carries the source-revision facts instead.
        public var writer: WriterPolicy = .omit
        /// Which token proves the physical unit behind a sample's `HKDevice`. See ``UnitTokenPolicy``.
        ///
        /// The default, ``UnitTokenPolicy/localIdentifier``, asserts that the deployment has verified that
        /// `HKDevice.localIdentifier` is stable and names exactly one unit for what it acquires. A deployment that can't
        /// claim that uses
        /// ``UnitTokenPolicy/none`` or its own ``UnitTokenPolicy/custom(_:)`` token.
        public var unitToken: UnitTokenPolicy = .localIdentifier
        /// How the converting application relates to each measurement. See ``RolePolicy``.
        public var role: RolePolicy = .assembler
        /// Discloses the clear HealthKit UUID as an identifier under a system the deployment owns, on the primary
        /// output and on retraction targets. This is the only way it reaches the wire.
        public var nativeIdentifier: GovernedSourceIdentifierDisclosurePolicy = .omit
        /// Whether a workout route becomes a recording document; a route re-identifies readily.
        ///
        /// A route deletion is retracted only while this is `.authorized`: retraction follows the policy in force
        /// when the deletion is retracted, not the one a route was exported under. Switching from `.authorized` to
        /// `.omit` therefore leaves routes exported earlier live at the receiver, and switching to `.authorized`
        /// retracts routes deleted afterwards that were never exported, which discloses that they existed. The guide
        /// retracts a route only when the producer establishes that it disclosed it (HealthKit guide `implementation.md`,
        /// retracting a source record); keep one route policy for an installation to keep that true.
        public var route: Disclosure = .omit
        /// Preserve supported sample metadata in its typed extension by default.
        /// An explicit omission is reported separately from unsupported values and does not change clinical mappings.
        public var metadata: Disclosure = .authorized
        /// At most how many child tasks build one call's records at once; `nil`, the default, builds on one per active
        /// core, and `1` builds on the calling task alone. It changes how fast a call runs, never what it exports.
        public var maximumConcurrency: Int?
        /// Whether the exporter measures what its export calls cost, read through ``HealthKitFHIRExporter/throughput``.
        ///
        /// Off by default. Measuring changes no record byte.
        public var measuresThroughput = false

        public init() {}
    }

    /// How `HKSourceRevision.source`, the app or device that wrote a sample into HealthKit, is stated.
    ///
    /// `HKSourceRevision` does not say whether its source is an application or a device, and the HealthKit
    /// guide forbids classifying it from the bundle identifier's shape, the source name or the product type:
    /// a source nobody classified states no writer. Only the caller's explicit classification states one. The
    /// hardware a sample was measured on is the recording Device, which `HKDevice` states whatever this policy
    /// says. A sample's sync identifier and version likewise
    /// travel as its writer-record identity, scoped to the source's bundle identifier, under every policy; a
    /// malformed pair (a half pair, a blank or non-text identifier, a version that is not a non-negative integral
    /// number) refuses the record, a recording document too, although a document carries no writer-record identity
    /// (HealthKit guide `mapping.md`, logical identity and revisions).
    public enum WriterPolicy: Sendable {
        /// No writer is stated, and the Provenance names no author. The default.
        case omit
        /// A source whose bundle identifier is one of these, which the caller knows to be applications, is
        /// stated as that application, with its name, bundle identifier and `HKSourceRevision.version` and
        /// the host it ran on. Every other source states no writer. A listed source with a blank name or bundle
        /// identifier states none either, and one whose bundle identifier is not a valid Apple bundle identifier
        /// is refused with ``HealthKitConversionError/sourceApplicationInvalid``.
        case applications(Set<String>)
        /// The caller classifies each source. The closure is consulted for every input that names a record, an ECG's
        /// correlated symptoms included.
        case classify(@Sendable (HKSource) -> Classification)

        /// How the caller classifies the source (`HKSourceRevision.source`) of one sample, the answer of a
        /// ``classify(_:)`` closure.
        ///
        /// HealthKit does not say whether a source is an application or a device, so the classification is the
        /// caller's: Grove never infers it from the bundle identifier, the source name or the product type. Which
        /// physical unit measured the sample is `HKDevice`, which the recording Device carries separately.
        public enum Classification: Hashable, Sendable {
            /// The source is an application: it is stated with its name, bundle identifier and version, all copied
            /// from the sample's `HKSourceRevision`, and the host it ran on, as the record's writer and writer host
            /// snapshots and the Provenance author. A source with a blank name or bundle identifier states no writer, and
            /// one whose bundle identifier is not a valid Apple bundle identifier is refused with
            /// ``HealthKitConversionError/sourceApplicationInvalid``.
            case application
            /// No writer is stated, and the Provenance names no author.
            case omit
        }

        /// The classification of one source under this policy.
        func classification(of source: HKSource) -> Classification {
            switch self {
            case .omit:
                .omit
            case .applications(let bundleIdentifiers):
                bundleIdentifiers.contains(source.bundleIdentifier) ? .application : .omit
            case .classify(let classify):
                classify(source)
            }
        }
    }

    /// Which token, if any, proves the physical unit behind a sample's `HKDevice`.
    ///
    /// It picks the token and nothing else: every `HKDevice` is a recording Device, stating each fact HealthKit supplies,
    /// `localIdentifier` included. A token enters the keyed `recording-device` identity, scoped to the writing source's
    /// `HKSource.bundleIdentifier`, so a source without one states no unit. Facts alone never prove a unit.
    public enum UnitTokenPolicy: Sendable {
        /// `HKDevice.localIdentifier`, when the sample states one. It is local to the host that recorded the sample and
        /// writable by any application, so the same value from two writers names two units.
        ///
        /// Within one subject, only the writer scopes the token: a writer that states the same value for distinct units,
        /// on one host or on several, merges them into one identity. Choosing this policy asserts that the deployment has
        /// verified that the value is stable and names exactly one unit for what it acquires.
        case localIdentifier
        /// No token: no recording Device proves a physical unit.
        case none
        /// The deployment's own token, or `nil` when it has none for this device. It is consulted for the `HKDevice` of
        /// every input that names a record, an ECG's correlated symptoms included.
        case custom(@Sendable (HKDevice, HKSource) -> String?)

        /// The token this policy picks for `device`, which `source` wrote.
        func token(for device: HKDevice, source: HKSource) -> String? {
            switch self {
            case .localIdentifier:
                device.localIdentifier?.nonBlank
            case .none:
                nil
            case .custom(let token):
                token(device, source)?.nonBlank
            }
        }
    }

    /// How the converting application relates to the measurements it converts.
    public enum RolePolicy: Hashable, Sendable {
        /// The application assembled the records from source records it did not mediate.
        case assembler
        /// Samples this application wrote in the build it states (the source's bundle identifier equals the
        /// application's, and `HKSourceRevision.version`, the source's `CFBundleVersion`, equals
        /// `ApplicationDevice.build`) are stated as mediated by it. Every other sample is merely assembled: one
        /// written by another build, one whose revision states no version, and every sample when the application
        /// states no build, which `ApplicationDevice(bundle:)` always reads from `CFBundleVersion`. iOS lets an app reuse
        /// a build number in another release; an app that does so names the current release for such a sample.
        case gatewayForOwnWrites
        /// The converting application mediated every measurement.
        case gateway
        /// A distinct application mediated every measurement; an Observation names it through
        /// `observation-gatewayDevice`, so its record carries it as a second application snapshot. Recording and
        /// clinical documents carry no gateway link under any role, so their records state no gateway application.
        case gatewayApplication(ApplicationDevice)

        /// The role for one sample under this policy.
        func converterRole(for revision: HKSourceRevision, application: ApplicationDevice) -> ConverterRole {
            switch self {
            case .assembler:
                .assembler
            case .gatewayForOwnWrites:
                HealthKitAssembly.isSameBuild(revision, as: application) ? .gateway : .assembler
            case .gateway:
                .gateway
            case .gatewayApplication(let gateway):
                .gatewayApplication(gateway)
            }
        }
    }

    /// An explicit, caller-attested disclosure of information that identifies more readily than the
    /// measurement itself.
    public enum Disclosure: Hashable, Sendable {
        case omit
        case authorized
    }
}

#endif
