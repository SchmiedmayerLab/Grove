//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

// Literal formatting follows FHIR resource shape.
// swiftlint:disable multiline_literal_brackets

import Foundation
package import ModelsR4


// MARK: - Devices

extension ExchangeGraphAssembler {
    struct ConverterSnapshots {
        let host: IdentifiedDevice
        let application: IdentifiedDevice
        /// A distinct application that mediated the measurement; `gatewayURL` names the converter itself when it did.
        let gateway: IdentifiedDevice?
        let gatewayURL: String?

        var identities: Set<RoledIdentifier> {
            Set([host.identity, application.identity] + (gateway.map { [$0.identity] } ?? []))
        }
    }

    struct WriterSnapshots {
        let application: IdentifiedDevice
        let host: IdentifiedDevice
        /// The writer snapshots the record carries as entries of their own: none when the converter
        /// already states the application, and the host only when the converter does not state it.
        let entries: [IdentifiedDevice]
    }

    /// The writer snapshots a record carries as entries of their own. A snapshot the converter already
    /// states is that entry, and the host of a writer that is the converter's application has nothing
    /// to connect to.
    package static func writerEntries(
        application: IdentifiedDevice,
        host: IdentifiedDevice,
        stated: Set<RoledIdentifier>
    ) -> [IdentifiedDevice] {
        guard !stated.contains(application.identity) else {
            return []
        }
        return [host].filter { !stated.contains($0.identity) } + [application]
    }

    func resolveDevices(for draft: ExchangeRecordDraft) throws -> Devices {
        // The guide defines observation-gatewayDevice for Observations only; a gateway snapshot that no
        // Observation names would connect to nothing (mobile-support.connected).
        let statesGateway = draft.outputs.contains { output in
            guard case .observation = output.resource else {
                return false
            }
            return output.links.contains(.gateway)
        }
        let converter = try converterSnapshots(role: draft.converterRole, statesGateway: statesGateway)
        let recording = try draft.recordingDevice.map(recordingSnapshot)
        var stated = Set([recording?.identity].compactMap { $0 })
        let sources = try draft.sourceDevices.map(recordingSnapshot).filter { stated.insert($0.identity).inserted }
        let writer = try writerSnapshots(draft.writer, converter: converter)
        return Devices(converter: converter, recording: recording, sources: sources, writer: writer)
    }

    /// The converting application's snapshot and its host's, which every record of the envelope shares.
    func applicationSnapshots() throws(ExchangeIdentityError) -> (host: IdentifiedDevice, application: IdentifiedDevice) {
        let host = try hostSnapshot(envelope.host)
        return (host, try applicationSnapshot(envelope.application, parentURL: host.url))
    }

    private func converterSnapshots(role: ConverterRole, statesGateway: Bool) throws -> ConverterSnapshots {
        let (host, application) = try applicationSnapshots()
        switch role {
        case .assembler:
            return ConverterSnapshots(host: host, application: application, gateway: nil, gatewayURL: nil)
        case .gateway:
            return ConverterSnapshots(host: host, application: application, gateway: nil, gatewayURL: application.url)
        case .gatewayApplication(let gatewayApplication) where gatewayApplication.isSameRelease(as: envelope.application):
            // The named gateway is the converting application itself, as under `.gateway`.
            return ConverterSnapshots(host: host, application: application, gateway: nil, gatewayURL: application.url)
        case .gatewayApplication(let gatewayApplication):
            guard statesGateway else {
                return ConverterSnapshots(host: host, application: application, gateway: nil, gatewayURL: nil)
            }
            let gateway = try applicationSnapshot(gatewayApplication, parentURL: nil)
            return ConverterSnapshots(host: host, application: application, gateway: gateway, gatewayURL: gateway.url)
        }
    }

    /// The recording Device of `device`: every fact it states, then its unit identity when it has a token, then its key.
    private func recordingSnapshot(_ device: RecordingDevice) throws -> IdentifiedDevice {
        let scope = envelope.identityScope
        var resource = Self.recordingDevice(device, localIdentifierSystem: scope.systems.deviceLocalIdentifier)
        if let token = device.stableUnitToken?.nonBlank {
            let unit = try scope.recordingDevice(
                adapterID: envelope.adapter.adapterID,
                subject: envelope.subject.identifier,
                tokenScope: device.tokenScope ?? "",
                stableUnitToken: token
            )
            resource.identifier = [unit.fhirIdentifier] + (resource.identifier ?? [])
        }
        return try IdentifiedDevice(keying: resource, role: .recordingDevice, subject: envelope.subject.identifier, identityScope: scope)
    }

    private func writerSnapshots(_ writer: ExchangeWriterDraft?, converter: ConverterSnapshots) throws -> WriterSnapshots? {
        guard let writer else {
            return nil
        }
        let host = try hostSnapshot(writer.host)
        let snapshot = try applicationSnapshot(writer.application, parentURL: host.url, statesVersion: writer.statesVersion)
        return WriterSnapshots(
            application: snapshot,
            host: host,
            entries: Self.writerEntries(application: snapshot, host: host, stated: converter.identities)
        )
    }

    private func hostSnapshot(_ host: HostDevice) throws(ExchangeIdentityError) -> IdentifiedDevice {
        try IdentifiedDevice(
            keying: Self.hostDevice(host),
            role: .host,
            subject: envelope.subject.identifier,
            identityScope: envelope.identityScope
        )
    }

    private func applicationSnapshot(
        _ application: ApplicationDevice,
        parentURL: String?,
        statesVersion: Bool = true
    ) throws(ExchangeIdentityError) -> IdentifiedDevice {
        var resource = Self.applicationDevice(
            name: application.name,
            version: application.version,
            build: application.build,
            profile: envelope.adapter.applicationDeviceProfile
        )
        if !statesVersion {
            let versions = resource.version?.filter { version in
                version.type?.coding?.contains { $0.system == Canonicals.mdc && $0.code == "531975" } != true
            }
            resource.version = versions?.isEmpty == false ? versions : nil
        }
        resource.identifier = envelope.adapter.applicationIdentifier?(application).map { [$0] }
        resource.parent = parentURL.map { Reference(reference: $0.asFHIRStringPrimitive()) }
        return try IdentifiedDevice(
            keying: resource,
            role: .application,
            subject: envelope.subject.identifier,
            identityScope: envelope.identityScope
        )
    }
}


extension ApplicationDevice {
    /// Whether `other` states the same release of the same application.
    fileprivate func isSameRelease(as other: ApplicationDevice) -> Bool {
        bundleIdentifier == other.bundleIdentifier && version == other.version && build == other.build
    }
}


// MARK: - Device Bodies

extension ExchangeGraphAssembler {
    /// The body of an application Device snapshot as every record states it: the profile, the status, the user-friendly
    /// name, the version, and the build when there is one.
    ///
    /// The caller adds any clear identifiers and the parent host, then keys it. The assembler states the converting
    /// application and the writer this way, and Questionnaire its writer, which names its own identifier and may state
    /// no host.
    package static func applicationDevice(
        name: String,
        version: String,
        build: String?,
        profile: FHIRPrimitive<Canonical>
    ) -> Device {
        var device = Device()
        device.meta = Meta(profile: [profile])
        device.status = FHIRPrimitive(.active)
        device.deviceName = [DeviceDeviceName(name: name.asFHIRStringPrimitive(), type: FHIRPrimitive(.userFriendlyName))]
        var versions = [DeviceVersion(
            type: CodeableConcept(coding: [Coding(code: "531975", display: "MDC_ID_PROD_SPEC_SW", system: Canonicals.mdc)]),
            value: version.asFHIRStringPrimitive()
        )]
        if let build {
            versions.append(groveVersion("build", "Build", build))
        }
        device.version = versions
        return device
    }

    /// The body of a host Device snapshot as every record states it: the profile, the status, the name and model name,
    /// the manufacturer and product type, and the operating system's version, name and build.
    ///
    /// The caller keys it.
    package static func hostDevice(_ host: HostDevice) -> Device {
        var device = Device()
        device.meta = Meta(profile: [Profile.groveHostDevice])
        device.status = FHIRPrimitive(.active)
        device.deviceName = nonEmpty(deviceNames(name: host.name, modelName: host.model))
        device.manufacturer = host.manufacturer?.asFHIRStringPrimitive()
        device.modelNumber = host.productType?.asFHIRStringPrimitive()
        var versions = [groveVersion("os-version", "Operating system version", host.operatingSystemVersion)]
        if let name = host.operatingSystemName {
            versions.append(groveVersion("os-name", "Operating system name", name))
        }
        if let build = host.operatingSystemBuild {
            versions.append(groveVersion("os-build", "Operating system build", build))
        }
        device.version = versions
        return device
    }

    /// The body of a recording Device as every record states it: the profile, the status and every fact `device` sets.
    ///
    /// The caller adds the unit identity when there is one, then keys it.
    ///
    /// - Parameter localIdentifierSystem: The deployment's system for the clear local identifier.
    package static func recordingDevice(_ device: RecordingDevice, localIdentifierSystem: IdentifierSystem) -> Device {
        var resource = Device()
        resource.meta = Meta(profile: [Profile.groveRecordingDevice])
        resource.status = FHIRPrimitive(.active)
        let model = device.model?.nonBlank
        let productType = device.productType?.nonBlank
        resource.deviceName = nonEmpty(deviceNames(name: device.name?.nonBlank, modelName: productType == nil ? nil : model))
        resource.manufacturer = device.manufacturer?.nonBlank?.asFHIRStringPrimitive()
        resource.modelNumber = (productType ?? model)?.asFHIRStringPrimitive()
        resource.serialNumber = device.serialNumber?.nonBlank?.asFHIRStringPrimitive()
        resource.version = nonEmpty(recordingVersions(of: device))
        if let localIdentifier = device.localIdentifier?.nonBlank {
            resource.identifier = [Identifier(
                system: localIdentifierSystem.uri,
                type: CodeableConcept(coding: [Coding(code: "device-local-identifier", system: Canonicals.groveDeviceIdentifierType)]),
                value: localIdentifier.asFHIRStringPrimitive()
            )]
        }
        resource.udiCarrier = udiCarrier(of: device).map { [$0] }
        return resource
    }

    private static func recordingVersions(of device: RecordingDevice) -> [DeviceVersion] {
        var versions: [DeviceVersion] = []
        for (value, code, display) in [
            (device.hardwareVersion, "531974", "MDC_ID_PROD_SPEC_HW"),
            (device.firmwareVersion, "531976", "MDC_ID_PROD_SPEC_FW"),
            (device.softwareVersion, "531975", "MDC_ID_PROD_SPEC_SW")
        ] {
            if let value = value?.nonBlank {
                versions.append(DeviceVersion(
                    type: CodeableConcept(coding: [Coding(
                        code: code.asFHIRStringPrimitive(),
                        display: display.asFHIRStringPrimitive(),
                        system: Canonicals.mdc
                    )]),
                    value: value.asFHIRStringPrimitive()
                ))
            }
        }
        if let name = device.systemName?.nonBlank {
            versions.append(groveVersion("os-name", "Operating system name", name))
        }
        if let version = device.systemVersion?.nonBlank {
            versions.append(groveVersion("os-version", "Operating system version", version))
        }
        return versions
    }

    /// `Device.udiCarrier`; R4 has no element for the raw production identifier, so an extension carries it.
    private static func udiCarrier(of device: RecordingDevice) -> DeviceUdiCarrier? {
        let identifier = device.udiDeviceIdentifier?.nonBlank
        let production = device.udiProductionIdentifier?.nonBlank
        guard identifier != nil || production != nil else {
            return nil
        }
        var carrier = DeviceUdiCarrier(deviceIdentifier: identifier?.asFHIRStringPrimitive())
        carrier.extension = production.map { [Extension(url: Canonicals.udiProductionIdentifier, value: .string($0.asFHIRStringPrimitive()))] }
        return carrier
    }

    private static func deviceNames(name: String?, modelName: String?) -> [DeviceDeviceName] {
        var names: [DeviceDeviceName] = []
        if let name {
            names.append(DeviceDeviceName(name: name.asFHIRStringPrimitive(), type: FHIRPrimitive(.userFriendlyName)))
        }
        if let modelName {
            names.append(DeviceDeviceName(name: modelName.asFHIRStringPrimitive(), type: FHIRPrimitive(.modelName)))
        }
        return names
    }

    /// `elements`, or `nil` for an element FHIR forbids stating empty.
    private static func nonEmpty<Element>(_ elements: [Element]) -> [Element]? { // swiftlint:disable:this discouraged_optional_collection
        elements.isEmpty ? nil : elements
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
}

// swiftlint:enable multiline_literal_brackets
