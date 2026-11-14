//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import Foundation
import GroveFHIRContract
import GroveSensorKitFHIR
import ModelsR4
import Testing


struct SensorKitSleepIdentityTests {
    @Test
    func nativeIdentifierCannotClaimAReservedGraphNamespace() async throws {
        let record = SensorKitRecord.sleepSession(.init(
            sourceRecordID: .init(UUID()),
            session: DateInterval(start: SensorKitExporterFixtures.instant, duration: 0),
            nativeSessionIdentifier: try BusinessIdentifier(
                system: SensorFHIRIdentityTestSupport.identityScope.systems.sourceRecord, value: "native-session"
            )
        ))
        await #expect(throws: SensorKitConversionError.self) {
            try await SensorKitExporterFixtures.record(record)
        }
    }

    @Test(arguments: [0.0, 3600.0])
    func nativeIdentifierPreservesAcquisitionIdentity(duration: TimeInterval) async throws {
        let identity = SensorKitSourceRecordID(UUID())
        let session = DateInterval(start: SensorKitExporterFixtures.instant, duration: duration)
        let native = try BusinessIdentifier(
            system: IdentifierSystem("https://study.example.org/fhir/NamingSystem/sensorkit-sleep-session"),
            value: "Exact-Native-Identifier"
        )
        let without = try await SensorKitExporterFixtures.record(.sleepSession(.init(sourceRecordID: identity, session: session)))
        let with = try await SensorKitExporterFixtures.record(.sleepSession(.init(
            sourceRecordID: identity, session: session, nativeSessionIdentifier: native
        )))
        #expect(with.outputFullURLs == without.outputFullURLs)
        let observation = try #require(with.graph.bundle.entry?.compactMap { entry -> Observation? in
            if case .observation(let value)? = entry.resource { value } else { nil }
        }.first)
        let identifiers = observation.identifier?.filter { $0.system?.value?.url.absoluteString == native.system.rawValue }
        #expect(identifiers?.count == 1)
        #expect(identifiers?.first?.value?.value?.string == native.value)
        #expect(identifiers?.first?.type == nil)
    }
}
