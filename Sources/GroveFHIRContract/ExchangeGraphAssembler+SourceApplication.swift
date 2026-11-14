//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import ModelsR4


extension ExchangeGraphAssembler {
    /// The upstream author's supplied identity and release facts, without an invented host or lifecycle status.
    func sourceApplicationSnapshot(_ source: SourceApplicationDevice) throws -> IdentifiedDevice {
        let name = source.name?.asFHIRStringPrimitive() ?? FHIRPrimitive<FHIRString>(extension: [
            Extension(url: Canonicals.dataAbsentReason, value: .code(DataAbsentReason.unknown.rawValue.asFHIRStringPrimitive()))
        ])
        var resource = Device(
            deviceName: [DeviceDeviceName(name: name, type: FHIRPrimitive(.userFriendlyName))],
            identifier: source.identifiers.map(\.fhirIdentifier),
            meta: Meta(profile: [Profile.groveApplicationDevice])
        )
        let versions = Self.applicationVersions(version: source.version, build: source.build)
        resource.version = versions.isEmpty ? nil : versions
        return try IdentifiedDevice(
            keying: resource,
            role: .application,
            subject: envelope.subject.identifier,
            identityScope: envelope.identityScope
        )
    }
}
