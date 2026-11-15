//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

#if canImport(CryptoKit)
import CryptoKit
#else
import Crypto
#endif
import Foundation
import GroveFHIRContract
@testable import GroveProviderFHIR
import ModelsR4
import Testing


@Suite
struct WithingsFHIRTests {
    static let date = Date(timeIntervalSince1970: 1_800_000_000)

    static func context(account: String = "account-one") throws -> ProviderConversionContext {
        let scope = try OpaqueIdentityScope(
            root: "https://study.example.org/identity",
            keyID: "provider-test",
            epoch: KeyEpoch(1),
            key: SymmetricKey(data: Data(repeating: 0x43, count: 32))
        )
        let producer = try ExchangeProducer(
            identityScope: scope,
            subject: .logical(BusinessIdentifier(system: "https://study.example.org/participant", value: "one")),
            application: ApplicationDevice(name: "Provider worker", bundleIdentifier: "org.example.provider-worker", version: "1"),
            host: HostDevice(operatingSystemVersion: "1", productType: "server", name: "Worker", manufacturer: "Example")
        )
        return try ProviderConversionContext(
            producer: producer,
            scope: .account(BusinessIdentifier(system: "https://study.example.org/provider-account", value: account)),
            instant: date.addingTimeInterval(60),
            sourceTimeZone: #require(TimeZone(secondsFromGMT: 0))
        )
    }

    @Test("Exact provider scaling preserves decimal values and refuses overflow")
    func exactScaling() throws {
        #expect(try WithingsMeasureGroup.Measure(type: 1, value: 72_501, unit: -3).scaled() == Decimal(string: "72.501"))
        #expect(try WithingsMeasureGroup.Measure(type: 4, value: 175, unit: -2).scaled(additionalExponent: 2) == 175)
        #expect(throws: ProviderConversionError.decimalOverflow) {
            try WithingsMeasureGroup.Measure(type: 1, value: 1, unit: Int.max).scaled()
        }
        #expect(throws: ProviderConversionError.decimalOverflow) {
            try WithingsMeasureGroup.Measure(type: 1, value: 1, unit: -1_000).scaled()
        }
    }

    @Test("Pressure and heart rate in one group have separate stable source records")
    func pressureAndHeartRate() throws {
        let group = WithingsMeasureGroup(
            id: "group-one",
            date: Self.date,
            measures: [
                .init(type: 10, value: 120, unit: 0),
                .init(type: 9, value: 80, unit: 0),
                .init(type: 11, value: 72, unit: 0)
            ]
        )
        let context = try Self.context()
        let results = try WithingsFHIR.convert(group, context: context)
        #expect(results.map(\.sourceToken) == ["getmeas:9+10", "getmeas:11"])
        let records = results.compactMap(\.record)
        try #require(records.count == 2)
        #expect(records[0].sourceRecord != records[1].sourceRecord)
        let acquisitionIdentity = try context.sourceIdentity(provider: .withings, sourceType: "getmeas:9+10", nativeRecordID: group.id)
        #expect(acquisitionIdentity.identifier.identifier == records[0].sourceRecord)
        #expect(throws: ProviderConversionError.invalidSourceType) {
            try context.sourceIdentity(provider: .withings, sourceType: "unrecognized-source", nativeRecordID: group.id)
        }
        #expect(try WithingsFHIR.convert(group, context: context).compactMap(\.record?.json) == records.map(\.json))
        let other = try WithingsFHIR.convert(group, context: Self.context(account: "account-two"))
        #expect(other.compactMap(\.record?.sourceRecord) != records.map(\.sourceRecord))
        let bundle = try JSONDecoder().decode(ModelsR4.Bundle.self, from: records[0].json)
        let pressure = try #require(bundle.entry?.compactMap { $0.resource?.get() as? Observation }.first)
        #expect(pressure.component?.count == 2)
        #expect(pressure.issued == nil)
    }

    @Test("An unpaired pressure, ambiguous type, and undocumented AF value never produce a fabricated measurement")
    func missingOrConflictingEvidence() throws {
        let context = try Self.context()
        let unpaired = try WithingsFHIR.convert(.init(id: "one", date: Self.date, measures: [.init(type: 9, value: 80, unit: 0)]), context: context)
        #expect(unpaired.first?.record == nil)
        #expect(unpaired.first?.omissions.first?.reason == .missingRequiredEvidence)
        #expect(throws: ProviderConversionError.conflictingMeasurement(1)) {
            try WithingsFHIR.convert(
                .init(
                    id: "one",
                    date: Self.date,
                    measures: [
                        .init(type: 1, value: 70, unit: 0), .init(type: 1, value: 71, unit: 0)
                    ]
                ),
                context: context
            )
        }
        let refused = try WithingsFHIR.convert(
            .init(
                id: "one",
                date: Self.date,
                measures: [
                    .init(type: 130, value: 1, unit: 0), .init(type: 174, value: 10, unit: 0)
                ]
            ),
            context: context
        )
        #expect(refused.allSatisfy { $0.record == nil })
        #expect(refused.map(\.omissions.first?.reason) == [.missingRequiredEvidence, .notAdmitted])
    }

    @Test("Every advertised structured Withings source has a positive conversion fixture")
    func structuredCoverage() throws {
        let context = try Self.context()
        let types = [1, 4, 5, 6, 8, 11, 54, 71, 73, 76, 77, 88, 91, 123, 155, 167, 168, 169, 170]
        let measures =
            types.map { type in WithingsMeasureGroup.Measure(type: type, value: 50, unit: 0) }
            + [.init(type: 9, value: 80, unit: 0), .init(type: 10, value: 120, unit: 0)]
        var results = try WithingsFHIR.convert(.init(id: "group", date: Self.date, measures: measures), context: context)
        var activity = WithingsSummary.Activity()
        activity.steps = 1_000
        activity.distance = 750
        activity.calories = 100
        let day = try ProviderCivilDay(year: 2026, month: 11, day: 1, timeZone: context.sourceTimeZone)
        results += try WithingsFHIR.convert(.activity(id: "activity", day: day, values: activity), context: context)
        var sleep = WithingsSummary.Sleep()
        sleep.deepSleepDuration = 3_600
        sleep.remSleepDuration = 7_200
        sleep.lightSleepDuration = 14_400
        sleep.wakeupDuration = 3_600
        sleep.averageHeartRate = 60
        sleep.averageRespiratoryRate = 15
        let interval = DateInterval(start: Self.date.addingTimeInterval(-28_800), end: Self.date)
        results += try WithingsFHIR.convert(.sleep(id: "sleep", interval: interval, values: sleep), context: context)
        results += try WithingsFHIR.convert(
            .workout(id: "workout", interval: interval, activity: #require(.init(rawValue: "walking"))),
            context: context
        )
        let advertised = ProviderCapabilities.sources(for: .withings).filter { $0.conversionSupport == .structured }
        #expect(Set(results.map(\.sourceToken)) == Set(advertised.map(\.token)))
        #expect(results.allSatisfy { $0.record != nil && $0.omissions.isEmpty })
        try ProviderFixtures.write(results, provider: "withings")
    }

    @Test("A supported type without a converter and a type missing its evidence stay visible without fabricated values")
    func unconvertedTypesAreOmitted() throws {
        let results = try WithingsFHIR.convert(
            .init(
                id: "group",
                date: Self.date,
                measures: [
                    .init(type: 196, value: 70, unit: 0),
                    .init(type: 135, value: 100, unit: 0)
                ]
            ),
            context: Self.context()
        )
        #expect(results.allSatisfy { $0.record == nil })
        #expect(results.first { $0.sourceToken == "getmeas:196" }?.omissions.first?.reason == .notYetImplemented)
        #expect(ProviderCapabilities.sources(for: .withings).first { $0.token == "getmeas:196" }?.conversionSupport == .notYetImplemented)
        #expect(results.first { $0.sourceToken == "getmeas:135" }?.omissions.first?.reason == .missingRequiredEvidence)
    }
}
