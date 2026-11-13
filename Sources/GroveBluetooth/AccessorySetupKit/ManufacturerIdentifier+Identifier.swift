//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2024 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

#if canImport(AccessorySetupKit) && !os(macOS)
public import AccessorySetupKit


@available(iOS 18, macOS 15, watchOS 11, *)
extension ManufacturerIdentifier {
    /// Retrieve the `ASBluetoothCompanyIdentifier` representation for the manufacturer identifier.
    @available(iOS 18.0, *)
    public var bluetoothCompanyIdentifier: ASBluetoothCompanyIdentifier {
        ASBluetoothCompanyIdentifier(rawValue)
    }
}
#endif
