//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

public import Foundation
public import GroveFHIRContract


/// The facts of one provider conversion.
///
/// Persist them with an acquisition before converting, so a retry reproduces the same record version. Connection
/// ownership, consent and upstream credentials remain the caller's responsibility.
public struct ProviderConversionContext: Sendable {
    /// A provider's complete key space, never inferred from the appearance of a native identifier.
    public enum Scope: Sendable {
        /// The key space of one provider account, as Withings and Google Health use.
        case account(BusinessIdentifier)
        /// The provider's global key space, as Oura uses.
        case global(BusinessIdentifier)

        var identifier: BusinessIdentifier {
            switch self {
            case .account(let value), .global(let value): value
            }
        }
    }

    /// The producer of the exchange records.
    public let producer: ExchangeProducer
    /// The key space of the source records.
    public let scope: Scope
    /// The persisted conversion instant.
    public let instant: Date
    /// The time zone in which the source states its dates.
    public let sourceTimeZone: TimeZone
    /// The device that recorded the source records, if known.
    public let recordingDevice: RecordingDevice?

    /// Creates the facts of a conversion.
    public init(
        producer: ExchangeProducer,
        scope: Scope,
        instant: Date,
        sourceTimeZone: TimeZone,
        recordingDevice: RecordingDevice? = nil
    ) {
        self.producer = producer
        self.scope = scope
        self.instant = instant
        self.sourceTimeZone = sourceTimeZone
        self.recordingDevice = recordingDevice
    }

    /// The opaque source identity conversion uses, for durable acquisition and retry bookkeeping.
    ///
    /// A recognized token identifies its native key space; it establishes neither conversion support nor consent.
    public func sourceIdentity(
        provider: ProviderCapabilities.Provider,
        sourceType: String,
        nativeRecordID: String
    ) throws -> SourceRecordIdentity {
        try sourceIdentity(providerCode: provider.code, sourceType: sourceType, nativeRecordID: nativeRecordID)
    }

    func sourceIdentity(
        providerCode: OpaqueIdentityScope.ProviderCode,
        sourceType: String,
        nativeRecordID: String
    ) throws -> SourceRecordIdentity {
        guard !nativeRecordID.isEmpty else {
            throw ProviderConversionError.invalidNativeIdentifier
        }
        guard ProviderContract.sources.contains(where: { $0.provider == providerCode.rawValue && $0.token == sourceType }) else {
            throw ProviderConversionError.invalidSourceType
        }
        try validateScope(of: providerCode)
        return try producer.identityScope.providerRecord(
            providerCode: providerCode,
            sourceType: sourceType,
            providerScope: scope.identifier,
            nativeRecordID: nativeRecordID
        )
    }

    /// Refuses a scope other than the provider's: an account for Withings and Google Health, the global one for Oura.
    func validateScope(of provider: OpaqueIdentityScope.ProviderCode) throws(ProviderConversionError) {
        switch (provider, scope) {
        case (.oura, .global), (.withings, .account), (.googleHealthAPI, .account):
            return
        default:
            throw .invalidScope
        }
    }

    /// The same facts with the time zone of a civil day.
    func forDay(_ day: ProviderCivilDay) -> Self {
        Self(producer: producer, scope: scope, instant: instant, sourceTimeZone: day.timeZone, recordingDevice: recordingDevice)
    }
}
