//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import FHIRModelsExtensions
import Foundation
import GroveFHIRContract
import ModelsR4


/// Content construction shared by the concrete provider converters; no token-to-field dispatch occurs here.
enum ProviderObservation {
    /// The effective time of an output: a Withings or civil-day time as a date, or an exact source timestamp.
    enum Effective {
        case instant(Date)
        case interval(Date, Date)
        case timestamp(ProviderTimestamp)
        case providerInterval(ProviderInterval)

        func value(timeZone: TimeZone) throws -> Observation.EffectiveX {
            switch self {
            case .timestamp(let timestamp):
                return try .dateTime(FHIRPrimitive(DateTime(timestamp.originalValue)))
            case .providerInterval(let interval):
                return try .period(Period(
                    end: FHIRPrimitive(DateTime(interval.end.originalValue)),
                    start: FHIRPrimitive(DateTime(interval.start.originalValue))
                ))
            case .instant(let date):
                return try .dateTime(FHIRPrimitive(ExchangeInstant.fhirDateTime(date, offsetIn: timeZone)))
            case let .interval(start, end):
                guard start < end else {
                    throw ProviderConversionError.invalidInterval
                }
                return try .period(
                    Period(
                        end: FHIRPrimitive(ExchangeInstant.fhirDateTime(end, offsetIn: timeZone)),
                        start: FHIRPrimitive(ExchangeInstant.fhirDateTime(start, offsetIn: timeZone))
                    )
                )
            }
        }
    }

    static func quantity(_ value: Decimal, contract: QuantityContract) throws -> Quantity {
        guard !value.isNaN, contract.valueDomain?.contains(value) ?? true else {
            throw ProviderConversionError.invalidQuantity(contract.code)
        }
        return Quantity(
            code: contract.code.asFHIRStringPrimitive(),
            system: contract.system.asFHIRURIPrimitive(),
            unit: contract.unit.asFHIRStringPrimitive(),
            value: FHIRPrimitive(FHIRDecimal(value))
        )
    }

    /// `seconds` in the contract's UCUM time unit, so the value always matches the quantity's `code`.
    ///
    /// The value is rounded half to even at four decimal places, so a duration that doesn't divide evenly, such as
    /// 25,230 seconds in hours (7.0083), states a short exact decimal instead of a 38-digit repeating one. Four places
    /// keep a sub-second resolution for minutes and about a third of a second for hours.
    static func duration(seconds: Decimal, in contract: MeasurementContract) throws -> Decimal {
        var value: Decimal
        switch contract.quantity?.code {
        case "s": value = seconds
        case "min": value = seconds / 60
        case "h": value = seconds / 3_600
        case "d": value = seconds / 86_400
        default: throw ProviderConversionError.invalidContract(contract.id)
        }
        var rounded = Decimal()
        NSDecimalRound(&rounded, &value, 4, .bankers)
        return rounded
    }

    static func coding(_ contract: CodingContract) -> Coding {
        Coding(
            code: contract.code.asFHIRStringPrimitive(),
            display: contract.display?.asFHIRStringPrimitive(),
            system: contract.system.asFHIRURIPrimitive()
        )
    }

    static func base(
        _ contract: MeasurementContract,
        adapter: FHIRPrimitive<Canonical>,
        effective: Effective,
        method: String? = nil,
        context: ProviderConversionContext
    ) throws -> Observation {
        switch (contract.effective, effective) {
        case (.dateTime, .instant), (.dateTime, .timestamp),
             (.period, .interval), (.period, .providerInterval), (.dateTimeOrPeriod, _): break
        default: throw ProviderConversionError.invalidContract(contract.id)
        }
        let codes = [contract.code] + contract.requiredCodings.filter { $0 != contract.code }
        var observation = Observation(
            code: CodeableConcept(coding: codes.map(coding)),
            status: .init(.final)
        )
        observation.meta = Meta(profile: [contract.profile, adapter])
        observation.effective = try effective.value(timeZone: context.sourceTimeZone)
        observation.category = contract.category.map { [CodeableConcept(coding: [coding($0)])] }
        if let fixed = contract.method {
            guard method == nil || method == fixed.code else { throw ProviderConversionError.invalidContract(contract.id) }
            observation.method = CodeableConcept(coding: [
                Coding(
                    code: fixed.code.asFHIRStringPrimitive(),
                    display: fixed.display.asFHIRStringPrimitive(),
                    system: Canonicals.aggregationMethodCodeSystem
                )
            ])
        } else if !contract.methodChoice.isEmpty {
            guard let method, contract.methodChoice.contains(method) else { throw ProviderConversionError.invalidContract(contract.id) }
            observation.method = CodeableConcept(coding: [
                Coding(
                    code: method.asFHIRStringPrimitive(),
                    system: Canonicals.aggregationMethodCodeSystem
                )
            ])
        } else if method != nil {
            throw ProviderConversionError.invalidContract(contract.id)
        }
        return observation
    }

    static func scalar(
        _ value: Decimal,
        contract: MeasurementContract,
        adapter: FHIRPrimitive<Canonical>,
        effective: Effective,
        method: String? = nil,
        context: ProviderConversionContext
    ) throws -> ExchangeOutputDraft {
        guard let quantityContract = contract.quantity else { throw ProviderConversionError.invalidContract(contract.id) }
        var observation = try base(contract, adapter: adapter, effective: effective, method: method, context: context)
        observation.value = try .quantity(quantity(value, contract: quantityContract))
        return ExchangeOutputDraft(role: contract.id, resource: .observation(observation))
    }

    static func workout(
        _ activity: ProviderWorkoutActivity?,
        adapter: FHIRPrimitive<Canonical>,
        effective: Effective,
        context: ProviderConversionContext
    ) throws -> ExchangeOutputDraft? {
        guard let activity else {
            return nil
        }
        let contract = MeasurementCatalog.workout
        guard let system = contract.resultCodeSystem else { throw ProviderConversionError.invalidContract(contract.id) }
        var observation = try base(contract, adapter: adapter, effective: effective, context: context)
        observation.value = .codeableConcept(
            CodeableConcept(coding: [
                Coding(code: activity.rawValue.asFHIRStringPrimitive(), system: system.asFHIRURIPrimitive())
            ])
        )
        return .init(role: contract.id, resource: .observation(observation))
    }

    static func assemble(
        provider: OpaqueIdentityScope.ProviderCode,
        token: String,
        nativeID: String,
        outputs: [ExchangeOutputDraft],
        omissions: [ProviderConversionResult.Omission] = [],
        context: ProviderConversionContext
    ) throws -> ProviderConversionResult {
        guard !nativeID.isEmpty else {
            throw ProviderConversionError.invalidNativeIdentifier
        }
        try context.validateScope(of: provider)
        guard !outputs.isEmpty else {
            return .init(sourceToken: token, record: nil, omissions: omissions)
        }
        let source = try context.sourceIdentity(providerCode: provider, sourceType: token, nativeRecordID: nativeID)
        let decorated = outputs.map { output in
            var output = output
            output.trailingExtensions += [
                Extension(url: Canonicals.providerExtension, value: .code(provider.rawValue.asFHIRStringPrimitive())),
                Extension(
                    url: Canonicals.providerSourceTypeExtension,
                    value: .code((provider.rawValue + "/" + token).asFHIRStringPrimitive())
                )
            ]
            return output
        }
        let adapter = ExchangeAdapterContract(
            adapterID: ProviderContract.adapterID,
            provenanceProfile: Profile.providersConversionProvenance,
            applicationDeviceProfile: Profile.groveApplicationDevice
        )
        let scope = ExchangeEnvelope.Scope(
            adapter: adapter,
            identityScope: context.producer.identityScope,
            subject: context.producer.subject,
            repositoryScope: context.scope.identifier
        )
        let draft = ExchangeRecordDraft(
            instant: context.instant,
            sourceRecord: source,
            outputs: decorated,
            recordingDevice: context.recordingDevice
        )
        let assembled = try ExchangeGraphAssembler(envelope: .init(scope: scope, facts: context.producer.facts)).assemble(draft)
        return .init(sourceToken: token, record: assembled.record, omissions: omissions)
    }
}
