//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import GroveFHIRContract


public enum SensorKitConversionError: Error, Equatable, Sendable {
    case invalidRecord(SensorKitRecordError)
    case invalidConverterApplication(String)
    case invalidReference(String)
    case duplicateResearchStudyReference
    case invalidIdentity(String)
    case repositoryIDWithoutStructuredOutput
    case repositoryIDWithoutRawOutput
    case repositoryIDWithoutRecordingDevice
    case payloadTooLarge(byteCount: Int)
    /// A dependency raised a failure this domain does not model, named by type.
    ///
    /// Only the type is carried: a failing FHIR date describes itself with the exact instant it
    /// could not convert, and that instant identifies a participant.
    case unexpectedConversionFailure(String)
}


extension SensorKitConversionError {
    /// Narrows any conversion failure to this published domain, so nothing unmodelled is
    /// relabelled as an identity failure.
    init(conversionFailure error: any Error) {
        switch error {
        case let error as SensorKitConversionError:
            self = error
        case let error as SensorKitRecordError:
            self = .invalidRecord(error)
        case let error as ExchangeIdentityError:
            self = .invalidIdentity(String(describing: error))
        case let error as ExchangeGraphError:
            self = .invalidIdentity(String(describing: error))
        default:
            self = .unexpectedConversionFailure(String(reflecting: type(of: error)))
        }
    }
}
