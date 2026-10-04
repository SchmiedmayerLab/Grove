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


/// The unit a ``HealthKitFHIRExporter/RecordingDevicePolicy`` resolved for one sample before its event was reserved, so
/// the graph states the device the event's fingerprint covers without consulting the policy again.
@available(iOS 18, macOS 15, watchOS 11, *)
struct ResolvedRecordingDevice: RecordingDeviceResolver {
    let device: RecordingDevice?

    func recordingDevice(for _: HKDevice) -> RecordingDevice? {
        device
    }
}


@available(iOS 18, macOS 15, watchOS 11, *)
extension HealthKitFHIRExporter {
    /// The HealthKit-specific choices of one exporter: how sources, devices and identifiers are stated,
    /// and which disclosures the deployment authorizes. Every disclosure defaults to omission.
    public struct Options: Sendable {
        /// How the source that wrote a sample is stated: by default not at all. See ``WriterPolicy``.
        public var writer: WriterPolicy = .omit
        /// How the physical unit behind a sample's `HKDevice` is identified. See ``RecordingDevicePolicy``.
        public var recordingDevice: RecordingDevicePolicy = .localIdentifier
        /// How the converting application relates to each measurement. See ``RolePolicy``.
        public var role: RolePolicy = .assembler
        /// Discloses the clear HealthKit UUID as an identifier under a system the deployment owns, on the primary
        /// output and on retraction targets. Besides ``LegacyBundleID/healthKitUUID``, which repeats it as
        /// `Bundle.id`, this is the only way it reaches the wire.
        public var nativeIdentifier: GovernedSourceIdentifierDisclosurePolicy = .omit
        /// Whether a recording Device carries the UDI HealthKit supplies.
        public var udi: Disclosure = .omit
        /// Whether a workout route becomes a recording document; a route re-identifies readily.
        ///
        /// A route deletion is retracted only while this is `.authorized`: retraction follows the policy in force
        /// when the deletion is retracted, not the one a route was exported under. Switching from `.authorized` to
        /// `.omit` therefore leaves routes exported earlier live at the receiver, and switching to `.authorized`
        /// retracts routes deleted afterwards that were never exported, naming nodes the receiver never received.
        /// The guide asks a retraction to name the exact prior graph (HealthKit guide `implementation.md`,
        /// retracting a source record); keep one route policy for an installation's ledger to keep that true.
        public var route: Disclosure = .omit
        /// A deployment that still keys its receiver on `Bundle.id` can keep the old value there for the
        /// transition. See ``LegacyBundleID``.
        public var legacyBundleID: LegacyBundleID = .none

        public init() {}
    }

    /// How `HKSourceRevision.source`, the app or device that wrote a sample into HealthKit, is stated.
    ///
    /// `HKSourceRevision` does not say whether its source is an application or a device, and the HealthKit
    /// guide forbids classifying it from the bundle identifier's shape, the source name or the product type:
    /// a source nobody classified states no writer. Only the caller's explicit classification states one. The
    /// physical unit a sample was measured on is the recording Device, which ``RecordingDevicePolicy``
    /// resolves from `HKDevice` whatever this policy says. A sample's sync identifier and version likewise
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
        /// The caller classifies each source. The closure is consulted once per record and call, before the
        /// record's event is reserved, and the event's fingerprint covers its answer: an answer that changes for a
        /// reserved record takes a new sequence rather than restating that event's writer.
        case classify(@Sendable (HKSource) -> HealthKitWriter)

        /// The classification of one source under this policy.
        func classification(of source: HKSource) -> HealthKitWriter {
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

    /// How a sample's `HKDevice` resolves to one physical unit.
    public enum RecordingDevicePolicy: Sendable {
        /// Use HealthKit's per-unit `HKDevice.localIdentifier`; a device without one yields no recording
        /// Device and the export reports ``HealthKitConversionWarning/recordingDeviceOmitted(deviceName:)``.
        case localIdentifier
        /// Never emit a recording Device from `HKDevice`.
        case omit
        /// The deployment's own resolver. It is consulted once per record and call, before the record's event is
        /// reserved, and the event's fingerprint covers the device it names: a resolver whose answer changes for a
        /// reserved record takes a new sequence rather than restating that event's recording Device.
        case custom(any RecordingDeviceResolver)

        /// The unit this policy resolves `device` to.
        func recordingDevice(for device: HKDevice) -> RecordingDevice? {
            switch self {
            case .localIdentifier:
                HealthKitLocalIdentifierResolver().recordingDevice(for: device)
            case .omit:
                nil
            case .custom(let resolver):
                resolver.recordingDevice(for: device)
            }
        }
    }

    /// How the converting application relates to the measurements it converts.
    public enum RolePolicy: Hashable, Sendable {
        /// The application assembled graphs from records it did not mediate.
        case assembler
        /// Samples this application wrote in the build it states (the source's bundle identifier equals the
        /// application's, and `HKSourceRevision.version`, the source's `CFBundleVersion`, equals
        /// `ApplicationDevice.build`) are stated as mediated by it. Every other sample is merely assembled: one
        /// written by another build, one whose revision states no version, and every sample when the application
        /// states no build, which `ApplicationDevice(bundle:)` always reads from `CFBundleVersion`. The comparison
        /// uses the application the event froze. iOS lets an app reuse a build number in another release; an app
        /// that does so names the current release for such a sample.
        case gatewayForOwnWrites
        /// The converting application mediated every measurement.
        case gateway
        /// A distinct application mediated every measurement; an Observation names it through
        /// `observation-gatewayDevice`, so its graph carries it as a second application snapshot. Recording and
        /// clinical documents carry no gateway link under any role, so their graphs state no gateway application.
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

    /// What `Bundle.id` carries.
    ///
    /// The implementation guide forbids a source-native value as a resource id; receivers key on the
    /// identifiers inside the Bundle instead. The HealthKit UUID stays available only for deployments
    /// whose receiver has not moved yet.
    public enum LegacyBundleID: Hashable, Sendable {
        /// No `Bundle.id`.
        case none
        /// The uppercase HealthKit UUID, exactly as the earlier MyHeartCounts integration emitted it.
        @available(*, deprecated, message: "Transitional: violates the guide's Resource.id rule; key the receiver on identifiers instead.")
        case healthKitUUID
    }
}

#endif
