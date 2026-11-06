//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

public import Foundation


/// What a record states about the host a conversion runs on.
///
/// An application release and its host operating system have different lifecycles, so FHIR
/// represents them as two Device snapshots connected through `Device.parent`.
public struct HostDevice: Hashable, Sendable {
    /// Why the stated host is not one a Device snapshot can name.
    public enum ValidationError: Error, Equatable, Sendable {
        case blankOperatingSystemName
        case blankOperatingSystemVersion
        case blankOperatingSystemBuild
        case blankProductType
        case blankModel
        case blankName
        case blankManufacturer
    }

    /// The hardware product type `uname` reports, such as `iPhone17,1`.
    private static var hardwareProductType: String? {
        var system = utsname()
        uname(&system)
        let machine = withUnsafeBytes(of: system.machine) { String(decoding: $0.prefix { $0 != 0 }, as: UTF8.self) }
        return machine.isBlank ? nil : machine
    }

    /// The operating-system build `sysctl` reports, such as `23A341`; `nil` where the platform has no `kern.osversion`.
    private static var operatingSystemBuild: String? {
        #if canImport(Darwin)
        var size = 0
        guard sysctlbyname("kern.osversion", nil, &size, nil, 0) == 0, size > 0 else {
            return nil
        }
        var bytes = [UInt8](repeating: 0, count: size)
        guard sysctlbyname("kern.osversion", &bytes, &size, nil, 0) == 0 else {
            return nil
        }
        let build = String(decoding: bytes.prefix { $0 != 0 }, as: UTF8.self)
        return build.isBlank ? nil : build
        #else
        return nil
        #endif
    }

    /// `UIDevice.systemName`, which the app captures on the main actor.
    public let operatingSystemName: String?
    public let operatingSystemVersion: String
    /// The operating-system build, `kern.osversion`.
    public let operatingSystemBuild: String?
    /// The hardware product type, such as `iPhone17,1`, which `Device.modelNumber` states.
    public let productType: String?
    /// `UIDevice.model`, such as `iPhone`.
    public let model: String?
    public let name: String?
    public let manufacturer: String?

    public init(
        operatingSystemName: String? = nil,
        operatingSystemVersion: String,
        operatingSystemBuild: String? = nil,
        productType: String? = nil,
        model: String? = nil,
        name: String? = nil,
        manufacturer: String? = nil
    ) throws(ValidationError) {
        guard operatingSystemName?.isBlank != true else {
            throw .blankOperatingSystemName
        }
        guard !operatingSystemVersion.isBlank else {
            throw .blankOperatingSystemVersion
        }
        guard operatingSystemBuild?.isBlank != true else {
            throw .blankOperatingSystemBuild
        }
        guard productType?.isBlank != true else {
            throw .blankProductType
        }
        guard model?.isBlank != true else {
            throw .blankModel
        }
        guard name?.isBlank != true else {
            throw .blankName
        }
        guard manufacturer?.isBlank != true else {
            throw .blankManufacturer
        }
        self.operatingSystemName = operatingSystemName
        self.operatingSystemVersion = operatingSystemVersion
        self.operatingSystemBuild = operatingSystemBuild
        self.productType = productType
        self.model = model
        self.name = name
        self.manufacturer = manufacturer
    }

    private init(uncheckedOperatingSystemVersion: String, operatingSystemBuild: String?, productType: String?) {
        self.operatingSystemName = nil
        self.operatingSystemVersion = uncheckedOperatingSystemVersion
        self.operatingSystemBuild = operatingSystemBuild
        self.productType = productType
        self.model = nil
        self.name = nil
        self.manufacturer = nil
    }

    /// A snapshot of the current host: the operating-system version and build, and the hardware product type.
    ///
    /// The facts `UIDevice` holds need the main actor, so an app that states them fills them in itself.
    public static func current(processInfo: ProcessInfo = .processInfo) -> HostDevice {
        let version = processInfo.operatingSystemVersion
        return HostDevice(
            uncheckedOperatingSystemVersion: "\(version.majorVersion).\(version.minorVersion).\(version.patchVersion)",
            operatingSystemBuild: operatingSystemBuild,
            productType: hardwareProductType
        )
    }
}
