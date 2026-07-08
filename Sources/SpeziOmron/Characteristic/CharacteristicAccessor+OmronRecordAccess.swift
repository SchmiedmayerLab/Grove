//
// This source file is part of the Stanford Spezi open-source project
//
// SPDX-FileCopyrightText: 2024 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import SpeziBluetooth
@_spi(APISupport)
import SpeziBluetoothServices


@available(iOS 17, macOS 14, macCatalyst 17, visionOS 1, *)
extension CharacteristicAccessor where Value == RecordAccessControlPoint<OmronRecordAccessOperand> {
    /// Send report stored records request.
    ///
    /// Send a request to request to report the stored records via notify of the respective measurement characteristic.
    /// Once all records were notified, the method returns.
    ///
    /// - Parameter content: Select the records the request applies to.
    /// - Throws: Throws a [`RecordAccessResponseFormatError`](../../SpeziBluetoothServices/BluetoothServices.docc/BluetoothServices.md)
    ///     if there was an unexpected response or a [`RecordAccessResponseCode`](../../SpeziBluetoothServices/BluetoothServices.docc/BluetoothServices.md)
    ///     if the request failed.
    public func reportStoredRecords(_ content: RecordAccessOperationContent<Value.Operand>) async throws {
        try await sendRequestExpectingGeneralResponse(.reportStoredRecords(content))
    }

    /// Request the number of stored records.
    ///
    /// - Parameter content: Select the records the request applies to.
    /// - Returns: The number of stored records.
    /// - Throws: Throws a [`RecordAccessResponseFormatError`](../../SpeziBluetoothServices/BluetoothServices.docc/BluetoothServices.md)
    ///     if there was an unexpected response or a [`RecordAccessResponseCode`](../../SpeziBluetoothServices/BluetoothServices.docc/BluetoothServices.md)
    ///     if the request failed.
    public func reportNumberOfStoredRecords(_ content: RecordAccessOperationContent<Value.Operand>) async throws -> UInt16 {
        try await sendRequestExpectingValueResponse(
            .reportNumberOfStoredRecords(content),
            expectingResponse: .numberOfStoredRecordsResponse
        ) { response in
            guard case let .numberOfRecords(value) = response.operand else {
                throw RecordAccessResponseFormatError(response: response, reason: .unexpectedOperand)
            }
            return value
        }
    }

    /// Request the sequence number of the latest records.
    ///
    /// - Returns: The sequence number of the latest record.
    /// - Throws: Throws a [`RecordAccessResponseFormatError`](../../SpeziBluetoothServices/BluetoothServices.docc/BluetoothServices.md)
    ///     if there was an unexpected response or a [`RecordAccessResponseCode`](../../SpeziBluetoothServices/BluetoothServices.docc/BluetoothServices.md)
    ///     if the request failed.
    public func reportSequenceNumberOfLatestRecords() async throws -> UInt16 {
        try await sendRequestExpectingValueResponse(
            .reportSequenceNumberOfLatestRecords(),
            expectingResponse: .omronSequenceNumberOfLatestRecordsResponse
        ) { response in
            guard case let .sequenceNumber(value) = response.operand else {
                throw RecordAccessResponseFormatError(response: response, reason: .unexpectedOperand)
            }
            return value
        }
    }
}
