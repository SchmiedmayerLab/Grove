//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

// Device and Provenance literals follow the FHIR resource shape they build.
// swiftlint:disable multiline_literal_brackets

#if canImport(HealthKit)

import FHIRModelsExtensions
import Foundation
import GroveFHIRContract
import GroveHealthKit
import HealthKit
import ModelsR4


@available(iOS 18, macOS 15, watchOS 11, *)
extension HealthKitConverter {
    struct ResolvedRecordingDevice {
        let device: IdentifiedDevice?
        let warning: HealthKitConversionWarning?
    }

    static func applicationDevice(_ application: ApplicationDevice) -> Device {
        var device = Device()
        device.meta = Meta(profile: [HealthKitContract.applicationDeviceProfile])
        device.status = FHIRPrimitive(.active)
        device.identifier = [Identifier(
            system: HealthKitContract.appleBundleIdentifierSystem,
            type: CodeableConcept(coding: [Coding(
                code: HealthKitContract.appleBundleIdentifierTypeCode.asFHIRStringPrimitive(),
                system: HealthKitContract.appleBundleIdentifierTypeSystem
            )]),
            value: application.bundleIdentifier.asFHIRStringPrimitive()
        )]
        device.deviceName = [DeviceDeviceName(
            name: application.name.asFHIRStringPrimitive(),
            type: FHIRPrimitive(.userFriendlyName)
        )]
        device.version = [DeviceVersion(
            type: CodeableConcept(coding: [Coding(
                code: "531975",
                display: "MDC_ID_PROD_SPEC_SW",
                system: Canonicals.mdc
            )]),
            value: application.version.asFHIRStringPrimitive()
        )]
        if let build = application.build {
            device.version?.append(groveVersion("build", "Build", build))
        }
        // The operating-system version is a host snapshot fact, not application software.
        return device
    }

    static func hostDevice(_ host: HostDevice) -> Device {
        var device = Device()
        device.meta = Meta(profile: [Profile.groveHostDevice])
        device.status = FHIRPrimitive(.active)
        if let name = host.name {
            device.deviceName = [DeviceDeviceName(
                name: name.asFHIRStringPrimitive(),
                type: FHIRPrimitive(.userFriendlyName)
            )]
        }
        device.manufacturer = host.manufacturer?.asFHIRStringPrimitive()
        device.modelNumber = host.modelNumber?.asFHIRStringPrimitive()
        device.version = [groveVersion(
            "os-version",
            "Operating system version",
            host.operatingSystemVersion
        )]
        return device
    }

    private static func groveVersion(_ code: String, _ display: String, _ value: String) -> DeviceVersion {
        DeviceVersion(
            type: CodeableConcept(coding: [Coding(
                code: code.asFHIRStringPrimitive(),
                display: display.asFHIRStringPrimitive(),
                system: Canonicals.groveApplicationVersionType
            )]),
            value: value.asFHIRStringPrimitive()
        )
    }

    /// The application snapshot the converter states about itself, or about a distinct gateway application.
    static func applicationSnapshot(
        _ application: ApplicationDevice,
        parentURL: String?,
        repositoryID: RepositoryID?,
        context: HealthKitConversionContext
    ) throws -> IdentifiedDevice {
        let identity = try context.identityScope.deviceSnapshot(
            event: context.eventIdentifier,
            role: .application,
            sourceDeviceToken: application.bundleIdentifier
        )
        var resource = applicationDevice(application)
        resource.id = repositoryID?.primitive
        resource.identifier = [identity.fhirIdentifier] + (resource.identifier ?? [])
        resource.parent = parentURL.map { Reference(reference: $0.asFHIRStringPrimitive()) }
        return IdentifiedDevice(resource: resource, identity: identity)
    }

    static func hostSnapshot(
        _ host: HostDevice,
        sourceDeviceToken: String,
        repositoryID: RepositoryID?,
        context: HealthKitConversionContext
    ) throws -> IdentifiedDevice {
        let identity = try context.identityScope.deviceSnapshot(
            event: context.eventIdentifier,
            role: .host,
            sourceDeviceToken: sourceDeviceToken
        )
        var resource = hostDevice(host)
        resource.id = repositoryID?.primitive
        resource.identifier = [identity.fhirIdentifier]
        return IdentifiedDevice(resource: resource, identity: identity)
    }

    static func recordingDevice(
        for healthKitDevice: HKDevice?,
        context: HealthKitConversionContext
    ) throws -> ResolvedRecordingDevice {
        guard let healthKitDevice else {
            return ResolvedRecordingDevice(device: nil, warning: nil)
        }
        guard let recorder = context.options.recordingDevice.recordingDevice(for: healthKitDevice) else {
            // Model and version facts cannot identify a physical unit, so the shared recording
            // Device is omitted rather than merged, and the omission is reported.
            return ResolvedRecordingDevice(
                device: nil,
                warning: .recordingDeviceOmitted(deviceName: healthKitDevice.name?.nonBlank)
            )
        }
        var device = Device()
        device.meta = Meta(profile: [Profile.groveRecordingDevice])
        device.status = FHIRPrimitive(.active)
        device.id = context.repositoryID(.recordingDevice)?.primitive
        if let name = recorder.name ?? healthKitDevice.name?.nonBlank {
            device.deviceName = [DeviceDeviceName(
                name: name.asFHIRStringPrimitive(),
                type: FHIRPrimitive(.userFriendlyName)
            )]
        }
        device.manufacturer = (recorder.manufacturer ?? healthKitDevice.manufacturer?.nonBlank)?.asFHIRStringPrimitive()
        device.modelNumber = (recorder.modelNumber ?? healthKitDevice.model?.nonBlank)?.asFHIRStringPrimitive()
        var versions: [DeviceVersion] = []
        versions.appendVersion(healthKitDevice.hardwareVersion, code: "531974", display: "MDC_ID_PROD_SPEC_HW")
        versions.appendVersion(healthKitDevice.firmwareVersion, code: "531976", display: "MDC_ID_PROD_SPEC_FW")
        versions.appendVersion(healthKitDevice.softwareVersion, code: "531975", display: "MDC_ID_PROD_SPEC_SW")
        device.version = versions.isEmpty ? nil : versions

        if context.options.udiDisclosure == .authorizedUDI,
           let udi = healthKitDevice.udiDeviceIdentifier?.nonBlank {
            device.udiCarrier = [DeviceUdiCarrier(deviceIdentifier: udi.asFHIRStringPrimitive())]
        }
        let stableIdentity = try context.identityScope.recordingDevice(
            adapterID: HealthKitConverter.adapterID,
            subject: context.subjectIdentity,
            stableUnitToken: recorder.stableUnitToken
        )
        let snapshotIdentity = try context.identityScope.deviceSnapshot(
            event: context.eventIdentifier,
            role: .recordingDevice,
            sourceDeviceToken: recorder.stableUnitToken
        )
        device.identifier = [snapshotIdentity.fhirIdentifier, stableIdentity.fhirIdentifier]
        return ResolvedRecordingDevice(
            device: IdentifiedDevice(resource: device, identity: snapshotIdentity),
            warning: nil
        )
    }

    static func sourceAuthor(
        for revision: HKSourceRevision,
        classification: HealthKitWriter,
        context: HealthKitConversionContext
    ) throws -> SourceAuthorDevices? {
        switch classification {
        case .application:
            return try sourceApplicationAuthor(for: revision, context: context)
        case .device:
            // The graph envelope reuses its recording Device as the author. A second Device keyed
            // from application, model, or record identifiers would falsely claim a physical unit.
            return nil
        }
    }

    private static func sourceApplicationAuthor(
        for revision: HKSourceRevision,
        context: HealthKitConversionContext
    ) throws -> SourceAuthorDevices? {
        guard let name = revision.source.name.nonBlank,
              let bundleIdentifier = revision.source.bundleIdentifier.nonBlank else {
            return nil
        }
        let application: ApplicationDevice
        let host: HostDevice
        do {
            application = try ApplicationDevice(
                name: name,
                bundleIdentifier: bundleIdentifier,
                version: revision.version?.nonBlank ?? "unknown"
            )
            host = try HostDevice(
                operatingSystemVersion: operatingSystemVersion(revision.operatingSystemVersion),
                modelNumber: revision.productType?.nonBlank
            )
        } catch {
            throw HealthKitConversionError.sourceApplicationInvalid
        }
        let hostSnapshot = try hostSnapshot(
            host,
            sourceDeviceToken: revision.productType?.nonBlank ?? bundleIdentifier,
            repositoryID: context.repositoryID(.sourceAuthorHost),
            context: context
        )
        let hostURL = try hostSnapshot.identity.fullURLString
        let identity = try context.identityScope.deviceSnapshot(
            event: context.eventIdentifier,
            role: .application,
            sourceDeviceToken: bundleIdentifier
        )
        var device = applicationDevice(application)
        if revision.version?.nonBlank == nil {
            device.version = nil
        }
        device.id = context.repositoryID(.sourceAuthor)?.primitive
        device.identifier = [identity.fhirIdentifier] + (device.identifier ?? [])
        device.parent = Reference(reference: hostURL.asFHIRStringPrimitive())
        return SourceAuthorDevices(
            author: IdentifiedDevice(resource: device, identity: identity),
            host: hostSnapshot
        )
    }

    private static func operatingSystemVersion(_ version: OperatingSystemVersion) -> String {
        "\(version.majorVersion).\(version.minorVersion).\(version.patchVersion)"
    }

    static func provenance(
        sourceIdentifier: Identifier,
        targetURL: String,
        converterURL: String,
        sourceAuthorURL: String?,
        recordedAt: Date
    ) throws -> Provenance {
        let author = sourceAuthorURL.map { url in
            ProvenanceAgent(
                type: CodeableConcept(coding: [Coding(
                    code: "author",
                    display: "Author",
                    system: Canonicals.provenanceParticipantType
                )]),
                who: Reference(reference: url.asFHIRStringPrimitive())
            )
        }
        var entity = ProvenanceEntity(
            role: FHIRPrimitive(.source),
            what: Reference(identifier: sourceIdentifier)
        )
        entity.agent = author.map { [$0] }
        return Provenance(
            activity: CodeableConcept(coding: [Coding(
                code: "transform",
                display: "Transform/Translate Record Lifecycle Event",
                system: Canonicals.isoLifecycleEvent
            )]),
            agent: [ProvenanceAgent(
                type: CodeableConcept(coding: [Coding(
                    code: "assembler",
                    display: "Assembler",
                    system: Canonicals.provenanceParticipantType
                )]),
                who: Reference(reference: converterURL.asFHIRStringPrimitive())
            )],
            entity: [entity],
            meta: Meta(profile: [HealthKitContract.conversionProvenanceProfile]),
            occurred: .dateTime(FHIRPrimitive(try DateTime(date: recordedAt))),
            recorded: FHIRPrimitive(try Instant(date: recordedAt)),
            target: [Reference(reference: targetURL.asFHIRStringPrimitive())]
        )
    }
}


extension Array where Element == DeviceVersion {
    fileprivate mutating func appendVersion(_ value: String?, code: String, display: String) {
        guard let value = value?.nonBlank else {
            return
        }
        append(DeviceVersion(
            type: CodeableConcept(coding: [Coding(
                code: code.asFHIRStringPrimitive(),
                display: display.asFHIRStringPrimitive(),
                system: Canonicals.mdc
            )]),
            value: value.asFHIRStringPrimitive()
        ))
    }
}

#endif
