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
    /// Which sample metadata the typed metadata extension preserves, by metadata key.
    ///
    /// Under every policy the sync identifier and version are identity, never metadata (see
    /// ``Options/syncIdentifier``), and the device metadata keys the guide maps to the recording Device follow
    /// ``Options/device``.
    public typealias MetadataPolicy = FactPolicy<String>
    /// Which facts of a sample's `HKSourceRevision` the source-revision extension states. See ``SourceFact``.
    public typealias SourcePolicy = FactPolicy<SourceFact>
    /// Which facts the recording Device states. See ``DeviceFact``.
    public typealias DevicePolicy = FactPolicy<DeviceFact>

    /// The HealthKit-specific choices of one exporter: how sources and physical units are stated, which metadata, source
    /// and device facts travel, and which disclosures the deployment authorizes.
    ///
    /// By default every metadata, source and device fact HealthKit supplies travels, and no clear identifier and no
    /// workout route does. ``nonIdentifying`` is the preset that omits the facts its three policies list.
    public struct Options: Sendable {
        /// The default options with ``metadata``, ``source`` and ``device`` set to their `nonIdentifying` policies.
        ///
        /// It omits the identifying Apple metadata keys, the source name, a source bundle identifier of the form
        /// `com.apple.health.<UUID>`, and the device name, local identifier, serial number and UDI identifiers. These
        /// still travel: the keyed `recording-device` unit identity that ``unitToken`` picks, every other source
        /// bundle identifier, such as an application's, custom metadata keys, and a writer that ``writer`` states.
        ///
        /// It is a plain value: every option, these three included, can be changed afterwards.
        public static var nonIdentifying: Options {
            var options = Options()
            options.metadata = .nonIdentifying
            options.source = .nonIdentifying
            options.device = .nonIdentifying
            return options
        }

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
        /// Discloses the clear HealthKit UUID as an identifier, on the primary output and on retraction targets. This is
        /// the only way it reaches the wire. See ``NativeIdentifierDisclosure``.
        ///
        /// ``HealthKitFHIRExporter`` refuses a system that is one of the deployment's identity systems, a system whose
        /// path cannot be extended and a type that is the `healthkit-sync-id` coding, each with its
        /// ``HealthKitFHIRExporter/ConfigurationError``.
        public var nativeIdentifier: NativeIdentifierDisclosure = .omit
        /// Discloses the exact `HKMetadataKeySyncIdentifier` text of a sample that carries a sync identifier and version,
        /// on the primary output, as an identifier whose system is the native identifier's system, then
        /// `healthkit-sync-identifier`, then the writing source's bundle identifier.
        ///
        /// It takes effect only while ``nativeIdentifier`` is authorized as well, because its system extends that one.
        /// Authorizing it discloses the bundle identifier of the application that wrote such a sample, even where
        /// ``writer`` states no writer. A bundle identifier that contains anything but ASCII letters, digits, hyphens
        /// and periods cannot name that system: the text is then withheld and `HKMetadataKeySyncIdentifier` is reported
        /// as a withheld key. While the text is not disclosed, it reaches the wire in no element: only the keyed
        /// writer-record identity represents it.
        public var syncIdentifier: Disclosure = .omit
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
        /// Which facts of the sample's `HKSourceRevision` the source-revision extension states. See ``SourceFact``.
        ///
        /// It governs only that extension, which a record carries when no writer is stated. The writer ``writer``
        /// states carries its name, bundle identifier, version and host under every policy. A bundle identifier other
        /// than a ``SourceFact/deviceBundleIdentifier``, such as an application's, is no fact a policy decides: the guide
        /// keeps it whenever the extension is stated, and only a policy that includes no fact, such as `.omit`, states
        /// no extension.
        public var source: SourcePolicy = .all
        /// Which facts the recording Device states, whether an `HKDevice` property or a device metadata key supplies
        /// them. See ``DeviceFact``.
        ///
        /// A device metadata key whose fact the policy omits is not preserved in the metadata extension either, and is
        /// never warned about. Under a policy that omits facts, a Device is stated only when at least one fact remains. ``unitToken`` enters only the
        /// keyed `recording-device` identity, so a Device without its local identifier still states its unit, and a
        /// record without a Device states none.
        public var device: DevicePolicy = .all
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
    /// It picks the token and nothing else: every `HKDevice` is a recording Device, stating each fact HealthKit supplies
    /// that ``Options/device`` includes. A token enters the keyed `recording-device` identity, scoped to the writing source's
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

    /// Discloses the clear HealthKit UUID as an identifier under a system scoped to one participant's HealthKit store.
    ///
    /// The system must name an authority and have no query and no fragment, as an `https` URL without them does, so
    /// that the segments of a sync identifier's system extend its path (see ``Options/syncIdentifier``).
    public struct NativeIdentifierDisclosure: Hashable, Sendable {
        enum Storage: Hashable, Sendable {
            case omit
            case derived
            case explicit(system: IdentifierSystem, type: GovernedSourceIdentifierDisclosurePolicy.IdentifierType?)
        }

        /// No clear identifier is emitted. The default.
        public static let omit = Self(storage: .omit)
        /// The identifier is emitted under a system the exporter derives from its repository scope: the scope's system,
        /// then a token keyed with the deployment's identity key, then `healthkit-native-record`.
        ///
        /// The token is an HMAC of the repository scope under the producer's `OpaqueIdentityScope` key, so the scope's
        /// value is not part of the system and cannot be confirmed from it without the key. The same key and repository
        /// scope always yield the same system, and another scope or another key yields another. A repository scope
        /// whose system cannot be extended is refused with
        /// ``HealthKitFHIRExporter/ConfigurationError/nativeIdentifierSystemNotExtensible(_:)``.
        public static let authorized = Self(storage: .derived)

        let storage: Storage

        /// Whether the clear HealthKit UUID is disclosed, under a derived or a stated system.
        public var isAuthorized: Bool {
            storage != .omit
        }

        /// The identifier is emitted under `system`, which the deployment owns and scopes to one participant's HealthKit
        /// store, with the optional `type`.
        public static func authorized(
            system: IdentifierSystem,
            type: GovernedSourceIdentifierDisclosurePolicy.IdentifierType? = nil
        ) -> Self {
            Self(storage: .explicit(system: system, type: type))
        }
    }

    /// One fact of a sample's `HKSourceRevision` that a policy decides, as the source-revision extension states it.
    ///
    /// Any other `HKSource.bundleIdentifier`, such as an application's, is no such fact: the guide lets a policy withhold
    /// `sourceBundleIdentifier` only where it is a ``deviceBundleIdentifier``, so the extension states every other one.
    public enum SourceFact: Hashable, Sendable, CaseIterable {
        /// `HKSource.name`. For an iPhone or Apple Watch it is the name the person gave the device.
        case name
        /// An `HKSource.bundleIdentifier` that is exactly `com.apple.health.` followed by a UUID in the 8-4-4-4-12
        /// hexadecimal form, which HealthKit assigns to one iPhone or Apple Watch.
        ///
        /// The match is by form and best effort. It decides only whether the source-revision extension states the
        /// `sourceBundleIdentifier` member, which is omitted as a whole and never shortened or rewritten. It classifies
        /// nothing else: the source is not treated as a device or as an application because of it, and the writer, the
        /// sync identifier's system and every keyed identity use the exact bundle identifier under every policy.
        case deviceBundleIdentifier
        /// `HKSourceRevision.version`.
        case version
        /// `HKSourceRevision.productType`.
        case productType
        /// `HKSourceRevision.operatingSystemVersion`.
        case operatingSystemVersion
    }

    /// One fact of the recording Device, whether an `HKDevice` property or a device metadata key supplies it.
    public enum DeviceFact: Hashable, Sendable, CaseIterable {
        /// `HKDevice.name` or `HKMetadataKeyDeviceName`, which can be a name a person gave the device.
        case name
        /// `HKDevice.manufacturer` or `HKMetadataKeyDeviceManufacturerName`.
        case manufacturer
        /// `HKDevice.model`.
        case model
        /// `HKDevice.hardwareVersion`.
        case hardwareVersion
        /// `HKDevice.firmwareVersion`.
        case firmwareVersion
        /// `HKDevice.softwareVersion`.
        case softwareVersion
        /// `HKDevice.localIdentifier`, as the clear `Device.identifier`.
        case localIdentifier
        /// `HKDevice.udiDeviceIdentifier` or `HKMetadataKeyUDIDeviceIdentifier`.
        case udiDeviceIdentifier
        /// `HKMetadataKeyUDIProductionIdentifier`.
        case udiProductionIdentifier
        /// `HKMetadataKeyDeviceSerialNumber`.
        case serialNumber
    }

    /// Which facts of one kind an export states: sample metadata keys, ``SourceFact`` or ``DeviceFact``.
    ///
    /// Every policy has the same four forms: ``all``, `nonIdentifying`, ``omit`` and ``custom(_:)``. A fact a policy
    /// omits is never warned about.
    public struct FactPolicy<Fact: Sendable>: Sendable {
        /// A decision about a single fact.
        public enum Decision: Sendable {
            /// The fact is included in the export.
            case include
            /// The fact is omitted from the export.
            case omit
        }

        private let decide: @Sendable (Fact) -> Decision

        init(_ decide: @escaping @Sendable (Fact) -> Decision) {
            self.decide = decide
        }

        func decision(for fact: Fact) -> Decision {
            decide(fact)
        }

        func includes(_ fact: Fact) -> Bool {
            decide(fact) == .include
        }
    }
}


@available(iOS 18, macOS 15, watchOS 11, *)
extension HealthKitFHIRExporter.FactPolicy where Fact: CaseIterable & Hashable {
    /// Every fact the policy includes, each decided once.
    var includedFacts: Set<Fact> {
        Set(Fact.allCases.filter(includes))
    }
}


@available(iOS 18, macOS 15, watchOS 11, *)
extension HealthKitFHIRExporter.FactPolicy {
    /// Every fact. The default.
    public static var all: Self {
        Self { _ in .include }
    }

    /// No fact. For metadata the record states no metadata extension, for the source no source-revision extension, and
    /// for the device no recording Device.
    public static var omit: Self {
        Self { _ in .omit }
    }

    /// A policy that decides each fact with `decide`.
    ///
    /// - parameter decide: A closure that decides one fact. For source and device facts it is called once per fact when
    ///   the exporter is created, so every record of the exporter gets the same answer. For metadata it is called once
    ///   for each metadata key present in each `HKSample`.
    public static func custom(_ decide: @escaping @Sendable (Fact) -> Decision) -> Self {
        Self(decide)
    }
}


@available(iOS 18, macOS 15, watchOS 11, *)
extension HealthKitFHIRExporter.FactPolicy where Fact == String {
    /// Every supported key except the identifying Apple keys: `HKMetadataKeyExternalUUID`,
    /// `HKMetadataKeyDeviceSerialNumber`, `HKMetadataKeyDeviceName`, `HKMetadataKeyUDIDeviceIdentifier`,
    /// `HKMetadataKeyUDIProductionIdentifier` and `HKMetadataKeyDigitalSignature`. Custom keys are preserved.
    public static var nonIdentifying: Self {
        let keys = identifyingKeys
        return Self { keys.contains($0) ? .omit : .include }
    }

    /// Well-known HealthKit metadata keys that map to values likely containing identifying information.
    private static var identifyingKeys: Set<String> {
        [
            HKMetadataKeyExternalUUID,
            HKMetadataKeyDeviceSerialNumber,
            HKMetadataKeyDeviceName,
            HKMetadataKeyUDIDeviceIdentifier,
            HKMetadataKeyUDIProductionIdentifier,
            HKMetadataKeyDigitalSignature
        ]
    }
}


@available(iOS 18, macOS 15, watchOS 11, *)
extension HealthKitFHIRExporter.FactPolicy where Fact == HealthKitFHIRExporter.SourceFact {
    /// Every fact except the source name and a bundle identifier of the form `com.apple.health.<UUID>`. Every other
    /// bundle identifier, such as an application's, still travels.
    public static var nonIdentifying: Self {
        Self { $0 == .name || $0 == .deviceBundleIdentifier ? .omit : .include }
    }
}


@available(iOS 18, macOS 15, watchOS 11, *)
extension HealthKitFHIRExporter.FactPolicy where Fact == HealthKitFHIRExporter.DeviceFact {
    /// Every fact except the device name, the local identifier, the serial number and the two UDI identifiers. The keyed
    /// `recording-device` unit identity that ``HealthKitFHIRExporter/Options/unitToken`` picks still travels.
    public static var nonIdentifying: Self {
        Self { fact in
            switch fact {
            case .name, .localIdentifier, .serialNumber, .udiDeviceIdentifier, .udiProductionIdentifier: .omit
            case .manufacturer, .model, .hardwareVersion, .firmwareVersion, .softwareVersion: .include
            }
        }
    }
}


@available(iOS 18, macOS 15, watchOS 11, *)
extension HealthKitFHIRExporter.NativeIdentifierDisclosure {
    /// The path segment that ends a derived native identifier system.
    private static let derivedSystemSegment = "healthkit-native-record"
    /// The source-context type that keys the store token. It is reserved for the token: no record states an identifier of
    /// this context type, so the token equals no identifier value.
    private static let storeContextType = "healthkit-store"

    /// The system of the store `repositoryScope` names: the scope's system without trailing slashes, then a token keyed
    /// with `identityScope`'s key, then `healthkit-native-record`. `nil` when the scope's system has no path to extend.
    ///
    /// The token is the digest of the keyed source-context identity of the store, so it is unpadded base64url text, and
    /// neither states the scope's value nor lets it be confirmed without the key.
    static func derivedSystem(in repositoryScope: BusinessIdentifier, identityScope: OpaqueIdentityScope) -> IdentifierSystem? {
        guard GovernedSourceIdentifierDisclosurePolicy.acceptsSyncIdentifierPath(repositoryScope.system),
              let store = try? identityScope.sourceContext(
                  adapterID: HealthKitAssembly.adapter.adapterID,
                  contextType: storeContextType,
                  repositoryScope: repositoryScope,
                  nativeContextID: derivedSystemSegment
              ),
              let token = store.identifier.value.split(separator: ":").last else {
            return nil
        }
        var base = repositoryScope.system.rawValue[...]
        while base.hasSuffix("/") {
            base.removeLast()
        }
        return try? IdentifierSystem("\(base)/\(token)/\(derivedSystemSegment)")
    }

    /// The disclosure the records of the store `repositoryScope` names state: the explicit system, or the derived one.
    /// A derived system that cannot be formed discloses nothing; ``HealthKitFHIRExporter`` refuses that configuration.
    func policy(in repositoryScope: BusinessIdentifier, identityScope: OpaqueIdentityScope) -> GovernedSourceIdentifierDisclosurePolicy {
        switch storage {
        case .omit:
            .omit
        case let .explicit(system, type):
            .authorized(system: system, type: type)
        case .derived:
            Self.derivedSystem(in: repositoryScope, identityScope: identityScope).map { .authorized(system: $0) } ?? .omit
        }
    }
}

#endif
