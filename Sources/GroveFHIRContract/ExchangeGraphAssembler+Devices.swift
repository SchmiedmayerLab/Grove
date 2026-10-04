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
import ModelsR4


// MARK: - Devices

extension ExchangeGraphAssembler {
    struct ConverterSnapshots {
        let host: IdentifiedDevice
        let application: IdentifiedDevice
        let applicationURL: String
        /// A distinct application that mediated the measurement; `gatewayURL` names the converter itself when it did.
        let gateway: IdentifiedDevice?
        let gatewayURL: String?

        var identities: Set<RoledIdentifier> {
            Set([host.identity, application.identity] + (gateway.map { [$0.identity] } ?? []))
        }
    }

    struct RecordingSnapshot {
        let device: IdentifiedDevice
        let url: String
    }

    struct WriterSnapshots {
        let application: IdentifiedDevice
        let host: IdentifiedDevice
        let applicationURL: String
        /// The writer snapshots the graph carries as entries of their own: none when the converter
        /// already states the application, and the host only when the converter does not state it.
        let entries: [IdentifiedDevice]
    }

    /// The writer snapshots a graph carries as entries of their own. A snapshot the converter already
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

    func resolveDevices(for draft: ExchangeGraphDraft) throws -> Devices {
        // The guide defines observation-gatewayDevice for Observations only; a gateway snapshot that no
        // Observation names would connect to nothing (mobile-support.connected).
        let statesGateway = draft.outputs.contains { output in
            guard case .observation = output.resource else {
                return false
            }
            return output.links.contains(.gateway)
        }
        let converter = try converterSnapshots(
            event: draft.event,
            repositoryIDs: draft.repositoryIDs,
            role: draft.converterRole,
            statesGateway: statesGateway
        )
        let recording = try recordingSnapshot(draft.recordingDevice, event: draft.event, repositoryIDs: draft.repositoryIDs)
        let writer = try writerSnapshots(draft.writer, event: draft.event, repositoryIDs: draft.repositoryIDs, converter: converter)
        if draft.repositoryIDs[.recordingDevice] != nil, recording == nil {
            throw ExchangeAssemblyError.repositoryIDWithoutNode(.recordingDevice)
        }
        let writerEntries = Set(writer?.entries.map(\.identity) ?? [])
        if draft.repositoryIDs[.writer] != nil, !writerEntries.contains(where: { $0 == writer?.application.identity }) {
            throw ExchangeAssemblyError.repositoryIDWithoutNode(.writer)
        }
        if draft.repositoryIDs[.writerHost] != nil, !writerEntries.contains(where: { $0 == writer?.host.identity }) {
            throw ExchangeAssemblyError.repositoryIDWithoutNode(.writerHost)
        }
        return Devices(converter: converter, recording: recording, writer: writer)
    }

    private func converterSnapshots(
        event: ExchangeEventIdentifier,
        repositoryIDs: [ExchangeGraphNode: RepositoryID],
        role: ConverterRole,
        statesGateway: Bool
    ) throws -> ConverterSnapshots {
        let host = try hostSnapshot(envelope.host, event: event, repositoryID: repositoryIDs[.hostDevice])
        let application = try applicationSnapshot(
            envelope.application,
            event: event,
            parentURL: try host.identity.fullURLString,
            repositoryID: repositoryIDs[.applicationDevice]
        )
        let applicationURL = try application.identity.fullURLString
        switch role {
        case .assembler:
            return ConverterSnapshots(host: host, application: application, applicationURL: applicationURL, gateway: nil, gatewayURL: nil)
        case .gateway:
            return ConverterSnapshots(host: host, application: application, applicationURL: applicationURL, gateway: nil, gatewayURL: applicationURL)
        case .gatewayApplication(let gatewayApplication):
            guard statesGateway else {
                return ConverterSnapshots(host: host, application: application, applicationURL: applicationURL, gateway: nil, gatewayURL: nil)
            }
            let gateway = try applicationSnapshot(gatewayApplication, event: event, parentURL: nil, repositoryID: nil)
            return ConverterSnapshots(
                host: host,
                application: application,
                applicationURL: applicationURL,
                gateway: gateway,
                gatewayURL: try gateway.identity.fullURLString
            )
        }
    }

    private func recordingSnapshot(
        _ draft: ExchangeRecordingDeviceDraft?,
        event: ExchangeEventIdentifier,
        repositoryIDs: [ExchangeGraphNode: RepositoryID]
    ) throws -> RecordingSnapshot? {
        guard let draft else {
            return nil
        }
        let scope = envelope.identityScope
        let stable = try scope.recordingDevice(
            adapterID: envelope.adapter.adapterID,
            subject: envelope.subject.identifier,
            stableUnitToken: draft.device.stableUnitToken
        )
        let snapshot = try scope.deviceSnapshot(event: event, role: .recordingDevice, sourceDeviceToken: draft.device.stableUnitToken)
        var resource = draft.resource
        resource.id = repositoryIDs[.recordingDevice]?.primitive
        resource.identifier = [snapshot.fhirIdentifier, stable.fhirIdentifier]
        return RecordingSnapshot(device: IdentifiedDevice(resource: resource, identity: snapshot), url: try snapshot.fullURLString)
    }

    private func writerSnapshots(
        _ writer: ExchangeWriterDraft?,
        event: ExchangeEventIdentifier,
        repositoryIDs: [ExchangeGraphNode: RepositoryID],
        converter: ConverterSnapshots
    ) throws -> WriterSnapshots? {
        guard case let .application(application, hostDevice, statesVersion) = writer else {
            return nil
        }
        let host = try hostSnapshot(hostDevice, event: event, repositoryID: repositoryIDs[.writerHost])
        var snapshot = try applicationSnapshot(
            application,
            event: event,
            parentURL: try host.identity.fullURLString,
            repositoryID: repositoryIDs[.writer]
        )
        if !statesVersion {
            var resource = snapshot.resource
            resource.version = nil
            snapshot = IdentifiedDevice(resource: resource, identity: snapshot.identity)
        }
        return WriterSnapshots(
            application: snapshot,
            host: host,
            applicationURL: try snapshot.identity.fullURLString,
            entries: Self.writerEntries(application: snapshot, host: host, stated: converter.identities)
        )
    }


    private func hostSnapshot(_ host: HostDevice, event: ExchangeEventIdentifier, repositoryID: RepositoryID?) throws -> IdentifiedDevice {
        let identity = try envelope.identityScope.deviceSnapshot(event: event, role: .host, sourceDeviceToken: host.sourceDeviceToken)
        var resource = hostDevice(host)
        resource.id = repositoryID?.primitive
        resource.identifier = [identity.fhirIdentifier]
        return IdentifiedDevice(resource: resource, identity: identity)
    }

    private func applicationSnapshot(
        _ application: ApplicationDevice,
        event: ExchangeEventIdentifier,
        parentURL: String?,
        repositoryID: RepositoryID?
    ) throws -> IdentifiedDevice {
        let identity = try envelope.identityScope.deviceSnapshot(
            event: event,
            role: .application,
            sourceDeviceToken: application.sourceDeviceToken
        )
        var resource = applicationDevice(application)
        resource.id = repositoryID?.primitive
        resource.identifier = [identity.fhirIdentifier] + (resource.identifier ?? [])
        resource.parent = parentURL.map { Reference(reference: $0.asFHIRStringPrimitive()) }
        return IdentifiedDevice(resource: resource, identity: identity)
    }

    private func applicationDevice(_ application: ApplicationDevice) -> Device {
        var device = Device()
        device.meta = Meta(profile: [envelope.adapter.applicationDeviceProfile])
        device.status = FHIRPrimitive(.active)
        device.identifier = envelope.adapter.applicationIdentifier?(application).map { [$0] }
        device.deviceName = [DeviceDeviceName(name: application.name.asFHIRStringPrimitive(), type: FHIRPrimitive(.userFriendlyName))]
        var versions = [DeviceVersion(
            type: CodeableConcept(coding: [Coding(code: "531975", display: "MDC_ID_PROD_SPEC_SW", system: Canonicals.mdc)]),
            value: application.version.asFHIRStringPrimitive()
        )]
        if let build = application.build {
            versions.append(groveVersion("build", "Build", build))
        }
        device.version = versions
        return device
    }

    private func hostDevice(_ host: HostDevice) -> Device {
        var device = Device()
        device.meta = Meta(profile: [Profile.groveHostDevice])
        device.status = FHIRPrimitive(.active)
        if let name = host.name {
            device.deviceName = [DeviceDeviceName(name: name.asFHIRStringPrimitive(), type: FHIRPrimitive(.userFriendlyName))]
        }
        device.manufacturer = host.manufacturer?.asFHIRStringPrimitive()
        device.modelNumber = host.modelNumber?.asFHIRStringPrimitive()
        device.version = [groveVersion("os-version", "Operating system version", host.operatingSystemVersion)]
        return device
    }

    private func groveVersion(_ code: String, _ display: String, _ value: String) -> DeviceVersion {
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
