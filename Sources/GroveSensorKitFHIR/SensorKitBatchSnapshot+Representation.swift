//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import Foundation
import GroveFHIRContract


extension SensorKitBatchSnapshot {
    struct Representation: Codable {
        let version: Int
        let application: ApplicationFacts
        let host: HostFacts
        let recording: RecordingFacts?
        let sources: [RecordingFacts]
        let sourcesSuppliedEverySample: Bool
        let timeZone: String
        let instant: Date

        func validateStringBounds() throws {
            guard sources.count <= 128 else { throw SnapshotError.capacityExceeded }
            let strings = application.strings + host.strings + (recording?.strings ?? []) + sources.flatMap(\.strings) + [timeZone]
            guard strings.allSatisfy({ $0.utf8.count <= 2048 }) else { throw SnapshotError.capacityExceeded }
        }
    }

    struct ApplicationFacts: Codable {
        let name: String
        let bundleIdentifier: String
        let version: String
        let build: String?
        var strings: [String] { [name, bundleIdentifier, version] + [build].compactMap { $0 } }

        init(_ device: ApplicationDevice) {
            name = device.name
            bundleIdentifier = device.bundleIdentifier
            version = device.version
            build = device.build
        }

        func value() throws -> ApplicationDevice {
            try ApplicationDevice(name: name, bundleIdentifier: bundleIdentifier, version: version, build: build)
        }
    }

    struct HostFacts: Codable {
        let operatingSystemName: String?
        let operatingSystemVersion: String
        let operatingSystemBuild: String?
        let productType: String?
        let model: String?
        let name: String?
        let manufacturer: String?
        var strings: [String] {
            [operatingSystemName, operatingSystemVersion, operatingSystemBuild, productType, model, name, manufacturer].compactMap { $0 }
        }

        init(_ device: HostDevice) {
            operatingSystemName = device.operatingSystemName
            operatingSystemVersion = device.operatingSystemVersion
            operatingSystemBuild = device.operatingSystemBuild
            productType = device.productType
            model = device.model
            name = device.name
            manufacturer = device.manufacturer
        }

        func value() throws -> HostDevice {
            try HostDevice(
                operatingSystemName: operatingSystemName,
                operatingSystemVersion: operatingSystemVersion,
                operatingSystemBuild: operatingSystemBuild,
                productType: productType,
                model: model,
                name: name,
                manufacturer: manufacturer
            )
        }
    }

    var representation: Representation {
        Representation(
            version: 1,
            application: ApplicationFacts(application),
            host: HostFacts(host),
            recording: recordingDevice.map(RecordingFacts.init),
            sources: sourceDevices.map(RecordingFacts.init),
            sourcesSuppliedEverySample: sourceDevicesSuppliedEverySample,
            timeZone: sourceTimeZone.identifier,
            instant: conversionInstant
        )
    }
}
