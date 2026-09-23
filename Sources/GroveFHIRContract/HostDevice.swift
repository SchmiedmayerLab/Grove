//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

public import Foundation


public enum HostDeviceError: Error, Equatable, Sendable {
    case blankOperatingSystemVersion
    case blankName
    case blankManufacturer
    case blankModelNumber
}


/// Event-time facts about the host a conversion runs on.
///
/// An application release and its host operating system have different lifecycles, so FHIR
/// represents them as two Device snapshots connected through `Device.parent`.
public struct HostDevice: Hashable, Sendable {
    /// The hardware model identifier `uname` reports, such as `iPhone17,1`.
    private static var hardwareModel: String? {
        var system = utsname()
        uname(&system)
        let machine = withUnsafeBytes(of: system.machine) { String(decoding: $0.prefix { $0 != 0 }, as: UTF8.self) }
        return machine.isBlank ? nil : machine
    }

    public let operatingSystemVersion: String
    public let name: String?
    public let manufacturer: String?
    public let modelNumber: String?

    /// The token the host's event-scoped Device snapshot identity is minted from:
    /// `<model number>|<operating-system version>`, such as `iPhone17,1|26.0`, the model empty when unknown.
    public var sourceDeviceToken: String {
        "\(modelNumber ?? "")|\(operatingSystemVersion)"
    }

    public init(
        operatingSystemVersion: String,
        name: String? = nil,
        manufacturer: String? = nil,
        modelNumber: String? = nil
    ) throws(HostDeviceError) {
        guard !operatingSystemVersion.isBlank else {
            throw .blankOperatingSystemVersion
        }
        guard name?.isBlank != true else {
            throw .blankName
        }
        guard manufacturer?.isBlank != true else {
            throw .blankManufacturer
        }
        guard modelNumber?.isBlank != true else {
            throw .blankModelNumber
        }
        self.operatingSystemVersion = operatingSystemVersion
        self.name = name
        self.manufacturer = manufacturer
        self.modelNumber = modelNumber
    }

    private init(uncheckedOperatingSystemVersion: String, modelNumber: String?) {
        self.operatingSystemVersion = uncheckedOperatingSystemVersion
        self.name = nil
        self.manufacturer = nil
        self.modelNumber = modelNumber
    }

    /// A snapshot of the current host: the hardware model `uname` reports and the operating-system version,
    /// which together form its ``sourceDeviceToken``.
    ///
    /// Capture and persist this with the exchange event: reconstructing it during a later retry,
    /// after an operating-system update, would describe a different snapshot.
    public static func current(processInfo: ProcessInfo = .processInfo) -> HostDevice {
        let version = processInfo.operatingSystemVersion
        return HostDevice(
            uncheckedOperatingSystemVersion: "\(version.majorVersion).\(version.minorVersion).\(version.patchVersion)",
            modelNumber: hardwareModel
        )
    }
}
