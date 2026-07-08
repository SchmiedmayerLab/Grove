//
// This source file is part of the Stanford Spezi open-source project
//
// SPDX-FileCopyrightText: 2024 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import SpeziBluetooth


/// Support migration to the new variant appearance system.
@_spi(Migration)
@available(iOS 17, macOS 14, macCatalyst 17, visionOS 1, *)
public protocol DeviceVariantMigration {
    /// Select an appearance for an already paired device.
    ///
    /// This method is called when we detect a paired device with variants defined but not variantId associated with the device info (as it is for devices paired before the variant system was introduced).
    /// - Parameter deviceInfo: The device info for which to select an appearance.
    /// - Returns: Returns the `appearance` and an optional `variantId`.
    static func selectAppearance(for deviceInfo: PairedDeviceInfo) -> (appearance: Appearance, variantId: String?)
}
