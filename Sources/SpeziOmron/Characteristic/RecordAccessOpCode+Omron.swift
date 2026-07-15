//
// This source file is part of the Stanford Spezi open-source project
//
// SPDX-FileCopyrightText: 2024 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

public import SpeziBluetoothServices


extension RecordAccessOpCode {
    /// Report the sequence number of the latest records.
    ///
    /// Reports the the sequence number of the latest records on the peripheral.
    /// The operator is [`null`](../../SpeziBluetoothServices/BluetoothServices.docc/BluetoothServices.md)
    /// and no operand is used.
    ///
    /// The number of stored records is returned using ``omronSequenceNumberOfLatestRecordsResponse``.
    /// Erroneous conditions are returned using the [`responseCode`](../../SpeziBluetoothServices/BluetoothServices.docc/BluetoothServices.md).
    public static let omronReportSequenceNumberOfLatestRecords = RecordAccessOpCode(rawValue: 0x10)
    /// Response returning the sequence number of the latest records.
    ///
    /// This is the response code to ``omronReportSequenceNumberOfLatestRecords``.
    /// The operator is [`null`](../../SpeziBluetoothServices/BluetoothServices.docc/BluetoothServices.md).
    /// The operand contains the number of stored records as a `UInt16`.
    public static let omronSequenceNumberOfLatestRecordsResponse = RecordAccessOpCode(rawValue: 0x11) // swiftlint:disable:this identifier_name
}
