//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

public import GroveFHIRContract


/// A typed failure for one record; batch conversion never drops input silently.
public struct SensorRecordFailure: Error, Equatable, Sendable {
    public let nativeRecordID: String
    public let sourceTypeIdentifier: String
    public let reason: SensorConversionError
}


/// Why one source record could not be converted; every case reports one registry code.
public enum SensorConversionError: Error, Equatable, Sendable {
    case invalidExchangeIdentity(String)
    case repositoryIDWithoutRecordingDevice
    case payloadTooLarge(byteCount: Int)
    case exchangeIdentity(ExchangeIdentityError)
    case opaqueIdentity(OpaqueIdentityError)
    case exchangeGraph(ExchangeGraphError)
    /// A dependency raised a failure this domain does not model, named by type.
    ///
    /// Only the type is carried: a failing FHIR date conversion describes itself with the exact
    /// instant it could not convert, and that instant identifies a participant.
    case unexpectedConversionFailure(String)

    public var diagnostic: ProducerDiagnostic {
        switch self {
        case .exchangeGraph(let error):
            return error.diagnostic
        case .exchangeIdentity(let error):
            return error.diagnostic
        case .opaqueIdentity(let error):
            return error.diagnostic
        case .payloadTooLarge:
            return ExchangeGraphRule.mobileInputRecordingPayloadTooLarge.diagnostic
        case .invalidExchangeIdentity, .repositoryIDWithoutRecordingDevice, .unexpectedConversionFailure:
            return ExchangeGraphRule.mobileInputUnclassified.diagnostic
        }
    }
}


extension SensorConversionError {
    /// Narrows any conversion failure to this published domain, so the converter's typed
    /// throws stay exhaustive even when a dependency raises its own error.
    init(conversionFailure error: any Error) {
        switch error {
        case let error as SensorConversionError:
            self = error
        case let error as ExchangeIdentityError:
            self = .exchangeIdentity(error)
        case let error as OpaqueIdentityError:
            self = .opaqueIdentity(error)
        case let error as ExchangeGraphError:
            self = .exchangeGraph(error)
        default:
            self = .unexpectedConversionFailure(String(reflecting: type(of: error)))
        }
    }
}
