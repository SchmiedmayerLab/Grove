//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

#if canImport(HealthKit)

public import Foundation
public import GroveFHIRContract
public import HealthKit


/// The resolver behind ``HealthKitFHIRExporter/RecordingDevicePolicy/omit``.
@available(iOS 18, macOS 15, watchOS 11, *)
private struct OmittingRecordingDeviceResolver: RecordingDeviceResolver {
    func recordingDevice(for device: HKDevice) -> RecordingDevice? {
        nil
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
        /// The only way the clear HealthKit UUID reaches the wire: as an identifier under a system the
        /// deployment owns, on the primary output and on retraction targets.
        public var nativeIdentifier: GovernedSourceIdentifierDisclosurePolicy = .omit
        /// Whether a recording Device carries the UDI HealthKit supplies.
        public var udi: Disclosure = .omit
        /// Whether a workout route becomes a recording document; a route re-identifies readily.
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
    /// travel as its writer-record identity, scoped to the source's bundle identifier, under every policy.
    public enum WriterPolicy: Sendable {
        /// No writer is stated, and the Provenance names no author. The default.
        case omit
        /// A source whose bundle identifier is one of these, which the caller knows to be applications, is
        /// stated as that application, with its name, bundle identifier and `HKSourceRevision.version` and
        /// the host it ran on. Every other source states no writer. A listed source with a blank name or bundle
        /// identifier states none either, and one whose bundle identifier is not a valid Apple bundle identifier
        /// is refused with ``HealthKitConversionError/sourceApplicationInvalid``.
        case applications(Set<String>)
        /// The caller classifies each source. The closure must be a pure function of the source and stable
        /// across application versions: the context fingerprint records only that a closure classifies, so
        /// a closure whose answers change can restate a reserved event's writer differently on redelivery.
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
        /// The deployment's own resolver.
        case custom(any RecordingDeviceResolver)

        var resolver: any RecordingDeviceResolver {
            switch self {
            case .localIdentifier:
                HealthKitLocalIdentifierResolver()
            case .omit:
                OmittingRecordingDeviceResolver()
            case .custom(let resolver):
                resolver
            }
        }
    }

    /// How the converting application relates to the measurements it converts.
    public enum RolePolicy: Hashable, Sendable {
        /// The application assembled graphs from records it did not mediate.
        case assembler
        /// Samples this application wrote itself in the build it runs (the source bundle identifier equals the
        /// application's and the revision's version equals its build) are stated as mediated by it; every other
        /// sample is merely assembled.
        case gatewayForOwnWrites
        /// The converting application mediated every measurement.
        case gateway
        /// A distinct application mediated every measurement; it travels as a second application snapshot.
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
