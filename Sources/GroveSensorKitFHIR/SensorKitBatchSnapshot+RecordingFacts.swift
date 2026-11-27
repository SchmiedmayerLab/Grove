//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import GroveFHIRContract


extension SensorKitBatchSnapshot {
    struct RecordingFacts: Codable {
        let stableUnitToken: String?
        let tokenScope: String?
        let name: String?
        let manufacturer: String?
        let model: String?
        let productType: String?
        let systemName: String?
        let systemVersion: String?
        let hardwareVersion: String?
        let firmwareVersion: String?
        let softwareVersion: String?
        let localIdentifier: String?
        let udiDeviceIdentifier: String?
        let udiProductionIdentifier: String?
        let serialNumber: String?

        var strings: [String] {
            [
                stableUnitToken, tokenScope, name, manufacturer,
                model, productType, systemName, systemVersion,
                hardwareVersion, firmwareVersion, softwareVersion, localIdentifier,
                udiDeviceIdentifier, udiProductionIdentifier, serialNumber
            ].compactMap { $0 }
        }

        var value: RecordingDevice {
            var device = RecordingDevice()
            device.stableUnitToken = stableUnitToken
            device.tokenScope = tokenScope
            device.name = name
            device.manufacturer = manufacturer
            device.model = model
            device.productType = productType
            device.systemName = systemName
            device.systemVersion = systemVersion
            device.hardwareVersion = hardwareVersion
            device.firmwareVersion = firmwareVersion
            device.softwareVersion = softwareVersion
            device.localIdentifier = localIdentifier
            device.udiDeviceIdentifier = udiDeviceIdentifier
            device.udiProductionIdentifier = udiProductionIdentifier
            device.serialNumber = serialNumber
            return device
        }

        init(_ device: RecordingDevice) {
            stableUnitToken = device.stableUnitToken
            tokenScope = device.tokenScope
            name = device.name
            manufacturer = device.manufacturer
            model = device.model
            productType = device.productType
            systemName = device.systemName
            systemVersion = device.systemVersion
            hardwareVersion = device.hardwareVersion
            firmwareVersion = device.firmwareVersion
            softwareVersion = device.softwareVersion
            localIdentifier = device.localIdentifier
            udiDeviceIdentifier = device.udiDeviceIdentifier
            udiProductionIdentifier = device.udiProductionIdentifier
            serialNumber = device.serialNumber
        }
    }
}
