//
// This source file is part of the Stanford Spezi open-project
//
// SPDX-FileCopyrightText: 2024 Stanford University
//
// SPDX-License-Identifier: MIT
//

import SpeziBluetooth


@available(iOS 17, macOS 14, macCatalyst 17, visionOS 1, *)
extension ManufacturerIdentifier {
    /// Bluetooth manufacturer code for "Omron Healthcare Co., Ltd.".
    public static var omronHealthcareCoLtd: ManufacturerIdentifier {
        ManufacturerIdentifier(rawValue: 0x020E)
    }
}
