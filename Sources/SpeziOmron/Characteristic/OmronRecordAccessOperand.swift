//
// This source file is part of the Stanford Spezi open-source project
//
// SPDX-FileCopyrightText: 2024 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import NIOCore
import SpeziBluetoothServices


/// The Record Access Operand format for the Omron Record Access Control Point characteristic.
@available(iOS 17, macOS 14, macCatalyst 17, visionOS 1, *)
public enum OmronRecordAccessOperand {
    // REQUEST

    /// Specify filter criteria for supported requests.
    case sequenceNumberFilter(UInt16)

    // RESPONSE

    /// The general response operand used with the [`responseCode`](../../SpeziBluetoothServices/BluetoothServices.docc/BluetoothServices.md)
    /// operation.
    case generalResponse(RecordAccessGeneralResponse)
    /// Reports the number of records in the [`numberOfStoredRecordsResponse`](../../SpeziBluetoothServices/BluetoothServices.docc/BluetoothServices.md)
    /// operation.
    case numberOfRecords(UInt16)
    /// Reports the sequence number of the latest records in the ``SpeziBluetoothServices/RecordAccessOpCode/omronSequenceNumberOfLatestRecordsResponse`` operation.
    case sequenceNumber(UInt16)
}


@available(iOS 17, macOS 14, macCatalyst 17, visionOS 1, *)
extension OmronRecordAccessOperand: Hashable, Sendable {}


@available(iOS 17, macOS 14, macCatalyst 17, visionOS 1, *)
extension RecordAccessFilterType {
    static let omronSequenceNumber = RecordAccessFilterType(rawValue: 0x04)
}


@available(iOS 17, macOS 14, macCatalyst 17, visionOS 1, *)
extension OmronRecordAccessOperand: RecordAccessOperand {
    public var generalResponse: RecordAccessGeneralResponse? {
        guard case let .generalResponse(response) = self else {
            return nil
        }
        return response
    }

    public init?( // swiftlint:disable:this cyclomatic_complexity
        from byteBuffer: inout ByteBuffer,
        opCode: RecordAccessOpCode,
        operator: RecordAccessOperator
    ) {
        switch opCode {
        case .responseCode:
            guard let response = RecordAccessGeneralResponse(from: &byteBuffer) else {
                return nil
            }
            self = .generalResponse(response)
        case .reportStoredRecords, .deleteStoredRecords, .reportNumberOfStoredRecords:
            switch `operator` {
            case .lessThanOrEqualTo, .greaterThanOrEqual:
                guard let filterType = RecordAccessFilterType(from: &byteBuffer),
                      case .omronSequenceNumber = filterType,
                      let sequenceNumber = UInt16(from: &byteBuffer) else {
                    return nil
                }
                self = .sequenceNumberFilter(sequenceNumber)
            default:
                return nil
            }
        case .numberOfStoredRecordsResponse:
            guard let count = UInt16(from: &byteBuffer) else {
                return nil
            }
            self = .numberOfRecords(count)
        case .omronSequenceNumberOfLatestRecordsResponse:
            guard let sequenceNumber = UInt16(from: &byteBuffer) else {
                return nil
            }
            self = .sequenceNumber(sequenceNumber)
        default:
            return nil
        }
    }

    public func encode(to byteBuffer: inout ByteBuffer) {
        switch self {
        case let .generalResponse(response):
            response.encode(to: &byteBuffer)
        case let .sequenceNumberFilter(value):
            RecordAccessFilterType.omronSequenceNumber.encode(to: &byteBuffer)
            value.encode(to: &byteBuffer)
        case let .numberOfRecords(value), let .sequenceNumber(value):
            value.encode(to: &byteBuffer)
        }
    }
}


@available(iOS 17, macOS 14, macCatalyst 17, visionOS 1, *)
extension RecordAccessOperationContent where Operand == OmronRecordAccessOperand {
    /// Records that are greater than or equal to the specified sequence number.
    ///
    /// - Parameter sequenceNumber: The sequence number to use as a filter criteria.
    /// - Returns: The operation content.
    public static func greaterThanOrEqualTo(sequenceNumber: UInt16) -> RecordAccessOperationContent {
        RecordAccessOperationContent(operator: .greaterThanOrEqual, operand: .sequenceNumberFilter(sequenceNumber))
    }
}
