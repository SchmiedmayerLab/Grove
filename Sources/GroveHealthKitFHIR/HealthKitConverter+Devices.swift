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
    static func applicationDevice(_ application: HealthKitApplication) -> Device {
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

    static func hostDevice(_ host: HealthKitHostDevice) -> Device {
        var device = Device()
        device.meta = Meta(profile: [Profile.groveHostDevice])
        device.status = FHIRPrimitive(.active)
        if let name = host.name?.nonEmpty {
            device.deviceName = [DeviceDeviceName(
                name: name.asFHIRStringPrimitive(),
                type: FHIRPrimitive(.userFriendlyName)
            )]
        }
        device.manufacturer = host.manufacturer?.nonEmpty?.asFHIRStringPrimitive()
        device.modelNumber = host.modelNumber?.nonEmpty?.asFHIRStringPrimitive()
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

    static func recordingDevice(
        for healthKitDevice: HKDevice?,
        context: HealthKitConversionContext
    ) throws -> IdentifiedDevice? {
        guard let healthKitDevice else {
            return nil
        }
        var device = Device()
        device.meta = Meta(profile: [Profile.groveRecordingDevice])
        device.status = FHIRPrimitive(.active)
        if let name = healthKitDevice.name?.nonEmpty {
            device.deviceName = [DeviceDeviceName(
                name: name.asFHIRStringPrimitive(),
                type: FHIRPrimitive(.userFriendlyName)
            )]
        }
        device.manufacturer = healthKitDevice.manufacturer?.nonEmpty?.asFHIRStringPrimitive()
        device.modelNumber = healthKitDevice.model?.nonEmpty?.asFHIRStringPrimitive()
        var versions: [DeviceVersion] = []
        versions.appendVersion(healthKitDevice.hardwareVersion, code: "531974", display: "MDC_ID_PROD_SPEC_HW")
        versions.appendVersion(healthKitDevice.firmwareVersion, code: "531976", display: "MDC_ID_PROD_SPEC_FW")
        versions.appendVersion(healthKitDevice.softwareVersion, code: "531975", display: "MDC_ID_PROD_SPEC_SW")
        device.version = versions.isEmpty ? nil : versions

        if context.udiDisclosurePolicy == .authorizedUDI,
           let udi = healthKitDevice.udiDeviceIdentifier?.nonEmpty {
            device.udiCarrier = [DeviceUdiCarrier(deviceIdentifier: udi.asFHIRStringPrimitive())]
        }
        guard let sourceDeviceToken = context.recordingDeviceStableUnitToken?.nonEmpty
            ?? healthKitDevice.localIdentifier?.nonEmpty else {
            // Model/version facts cannot identify a physical unit. Without governed stable
            // instance evidence the shared recording Device is omitted rather than merged.
            return nil
        }
        let stableIdentity = try context.identityScope.recordingDevice(
            adapterID: HealthKitConverter.adapterID,
            subject: context.subjectIdentity,
            stableUnitToken: sourceDeviceToken
        )
        let snapshotIdentity = try context.identityScope.deviceSnapshot(
            eventIdentifier: context.eventIdentifier,
            deviceRole: .recordingDevice,
            sourceDeviceToken: sourceDeviceToken
        )
        device.identifier = [snapshotIdentity.fhirIdentifier, stableIdentity.fhirIdentifier]
        return IdentifiedDevice(resource: device, identity: snapshotIdentity)
    }

    static func sourceAuthor(
        for revision: HKSourceRevision,
        classification: HealthKitSourceActor,
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
        guard let name = revision.source.name.nonEmpty,
              let bundleIdentifier = revision.source.bundleIdentifier.nonEmpty else {
            return nil
        }
        guard isValidAppleBundleIdentifier(bundleIdentifier) else {
            throw HealthKitConversionError.invalidSourceApplication("bundleIdentifier")
        }
        var device = applicationDevice(HealthKitApplication(
            name: name,
            bundleIdentifier: bundleIdentifier,
            version: revision.version?.nonEmpty ?? "unknown"
        ))
        if revision.version?.nonEmpty == nil {
            device.version = nil
        }
        let host = HealthKitHostDevice(
            sourceDeviceToken: revision.productType?.nonEmpty ?? bundleIdentifier,
            operatingSystemVersion: operatingSystemVersion(revision.operatingSystemVersion),
            modelNumber: revision.productType?.nonEmpty
        )
        let hostIdentity = try context.identityScope.deviceSnapshot(
            eventIdentifier: context.eventIdentifier,
            deviceRole: .host,
            sourceDeviceToken: host.sourceDeviceToken
        )
        var hostResource = hostDevice(host)
        hostResource.identifier = [hostIdentity.fhirIdentifier]
        let hostURL = try ExchangeIdentity.fullURL(for: hostIdentity)

        let identity = try context.identityScope.deviceSnapshot(
            eventIdentifier: context.eventIdentifier,
            deviceRole: .application,
            sourceDeviceToken: bundleIdentifier
        )
        device.identifier = [identity.fhirIdentifier] + (device.identifier ?? [])
        device.parent = Reference(reference: hostURL.asFHIRStringPrimitive())
        return SourceAuthorDevices(
            author: IdentifiedDevice(resource: device, identity: identity),
            host: IdentifiedDevice(resource: hostResource, identity: hostIdentity)
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
        guard let value = value?.nonEmpty else {
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


extension String {
    fileprivate var nonEmpty: String? {
        trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : self
    }
}

#endif
