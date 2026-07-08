//
// This source file is part of the Stanford Spezi open-source project
//
// SPDX-FileCopyrightText: 2024 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import SpeziBluetoothServices


@available(iOS 17, macOS 14, macCatalyst 17, visionOS 1, *)
extension RecordAccessControlPoint {
    /// Report the sequence number of the latest records.
    ///
    /// Reports the the sequence number of the latest records on the peripheral.
    /// The operator is [`null`](../../SpeziBluetoothServices/BluetoothServices.docc/BluetoothServices.md)
    /// and no operand is used.
    ///
    /// The number of stored records is returned using ``SpeziBluetoothServices/RecordAccessOpCode/omronSequenceNumberOfLatestRecordsResponse``.
    /// Erroneous conditions are returned using the [`responseCode`](../../SpeziBluetoothServices/BluetoothServices.docc/BluetoothServices.md).
    ///
    /// - Returns: The Record Access Control Point value.
    public static func reportSequenceNumberOfLatestRecords() -> RecordAccessControlPoint {
        RecordAccessControlPoint(opCode: .omronReportSequenceNumberOfLatestRecords, operator: .null)
    }
}
