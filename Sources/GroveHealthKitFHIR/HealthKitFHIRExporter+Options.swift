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
        ///
        /// For a sample that carries a sync identifier and version, authorizing it also discloses the exact
        /// `HKMetadataKeySyncIdentifier` text on the primary output, as a second identifier whose system is the
        /// authorized system, then `healthkit-sync-identifier`, then the writing source's bundle identifier. Authorizing
        /// it therefore discloses the bundle identifier of the application that wrote such a sample, even where
        /// ``writer`` states no writer. A bundle identifier that contains anything but ASCII letters, digits, hyphens
        /// and periods cannot name that system: the text is then withheld and `HKMetadataKeySyncIdentifier` is reported
        /// as a withheld key. While it is `.omit`, the sync identifier text reaches the wire in no element: only the
        /// keyed writer-record identity represents it. The authorized system is scoped to one participant's HealthKit
        /// store, which keeps equal sync identifiers of two participants apart.
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
        /// Which sample metadata without a faithful structured mapping the primary output preserves in its typed
        /// extension. See ``MetadataPolicy``.
        ///
        /// A key the policy excludes is counted in ``HealthKitFHIRExporter/Export/MetadataSummary``, separately from
        /// unsupported values, and never warned about. No policy changes a clinical mapping, the recording Device or the
        /// writer record.
        public var metadata: MetadataPolicy = .all
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
    /// number) refuses the record (HealthKit guide `mapping.md`, logical identity and revisions).
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

    /// Which sample metadata the typed metadata extension preserves.
    ///
    /// Under every policy the sync identifier and version are identity, never metadata (see
    /// ``Options/nativeIdentifier``), and the recording Device states the device metadata keys the guide maps to it.
    public struct MetadataPolicy: Sendable {
        /// A decision about a single metadata field
        public enum Decision: Sendable {
            /// The metadata field should be included in the export
            case include
            /// The metadata field should be omitted from the export
            case omit
        }
        
        private let _decide: @Sendable (_ key: String) -> Decision
        
        init(_ decide: @escaping @Sendable (_ key: String) -> Decision) {
            self._decide = decide
        }
        
        func evaluate(forEntryWithKey key: String) -> Decision {
            _decide(key)
        }
    }
}


extension HealthKitFHIRExporter.MetadataPolicy {
    /// Every supported key, custom and identifying keys included. The default.
    public static let all = Self { _ in .include }
    
    /// Every supported key except the identifying Apple keys: `HKMetadataKeyExternalUUID`,
    /// `HKMetadataKeyDeviceSerialNumber`, `HKMetadataKeyDeviceName`, `HKMetadataKeyUDIDeviceIdentifier`,
    /// `HKMetadataKeyUDIProductionIdentifier` and `HKMetadataKeyDigitalSignature`. Custom keys are preserved.
    public static let nonIdentifying = Self { key in
        Self.identifyingKeys.contains(key) ? .omit : .include
    }
    
    /// No key; the record states no metadata extension.
    public static let omit = Self { _ in .omit }
    
    /// Creates a new metadata policy using a custom decision closure.
    ///
    /// - parameter decide: A closure that gets called once for each metadata key present in an `HKSample`.
    public static func custom(_ decide: @escaping @Sendable (_ key: String) -> Decision) -> Self {
        Self(decide)
    }
}


extension HealthKitFHIRExporter.MetadataPolicy {
    /// Well-known HealthKit metadata keys that map to values likely containing identifying information.
    private static let identifyingKeys: Set<String> = [
        HKMetadataKeyExternalUUID,
        HKMetadataKeyDeviceSerialNumber,
        HKMetadataKeyDeviceName,
        HKMetadataKeyUDIDeviceIdentifier,
        HKMetadataKeyUDIProductionIdentifier,
        HKMetadataKeyDigitalSignature
    ]
}

#endif
