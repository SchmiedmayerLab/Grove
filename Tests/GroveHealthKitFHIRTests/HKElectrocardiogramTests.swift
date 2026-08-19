//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2022 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

#if canImport(HealthKit)

import Foundation
@testable import GroveHealthKitFHIR
import HealthKit
import ModelsR4
import Testing


@Suite
struct HKElectrocardiogramTests {
    /// `HKElectrocardiogram` cannot be constructed outside HealthKit, so the voltage strip is exercised
    /// through the mapping function the conversion delegates to.
    private static let mapping = ECGTypeFHIRMapping.default

    private func measurements(_ samples: [(TimeInterval, Double)]) -> HKElectrocardiogram.VoltageMeasurements {
        samples.map { (time: $0.0, value: HKQuantity(unit: .voltUnit(with: .micro), doubleValue: $0.1)) }
    }

    private func sampledData(hertz: Double?, _ samples: [(TimeInterval, Double)]) throws -> SampledData {
        try HKElectrocardiogram.sampledVoltageData(
            samplingFrequency: hertz.map { HKQuantity(unit: .hertz(), doubleValue: $0) },
            voltageMeasurements: measurements(samples),
            mapping: Self.mapping
        )
    }

    @Test
    func electrocardiogramCategoryTests() {
        #expect(HKElectrocardiogram.SymptomsStatus.notSet.display == "not set")
        #expect(HKElectrocardiogram.SymptomsStatus.none.display == "none")
        #expect(HKElectrocardiogram.SymptomsStatus.present.display == "present")

        #expect(HKElectrocardiogram.Classification.notSet.display == "not set")
        #expect(HKElectrocardiogram.Classification.sinusRhythm.display == "sinus rhythm")
        #expect(HKElectrocardiogram.Classification.atrialFibrillation.display == "atrial fibrillation")
        #expect(HKElectrocardiogram.Classification.inconclusiveLowHeartRate.display == "inconclusive low heart rate")
        #expect(HKElectrocardiogram.Classification.inconclusiveHighHeartRate.display == "inconclusive high heart rate")
        #expect(HKElectrocardiogram.Classification.inconclusivePoorReading.display == "inconclusive poor reading")
        #expect(HKElectrocardiogram.Classification.inconclusiveOther.display == "inconclusive other")
        #expect(HKElectrocardiogram.Classification.unrecognized.display == "unrecognized")
    }

    @Test
    func wholeStripIsOneSampledData() throws {
        let data = try sampledData(hertz: 512, [(0, 10.5), (1 / 512, -3.5), (2 / 512, 0)])
        #expect(data.data?.value?.string == "10.5 -3.5 0.0")
        #expect(data.dimensions.value?.integer == 1)
        #expect(data.origin == Quantity(
            code: "uV",
            system: "http://unitsofmeasure.org".asFHIRURIPrimitive(),
            unit: "uV",
            value: 0.asFHIRDecimalPrimitive()
        ))
    }

    /// The strip's only time anchor: a stated rate divides exactly, whatever the consumer's float type.
    @Test
    func periodComesFromTheStatedSamplingFrequency() throws {
        let data = try sampledData(hertz: 512, [(0, 1), (1 / 512, 2)])
        #expect(data.period.value?.decimal == Decimal(string: "1.953125"))
    }

    /// 1000/512.4 and 1000/60 are non-terminating in `Decimal`; asserting 34 digits for a rate known to
    /// four is the wrong direction, so the quotient is rounded to six fraction digits.
    @Test(arguments: [(512.4, "1.9516"), (60.0, "16.666667")])
    func periodIsRoundedToSixFractionDigits(hertz: Double, expected: String) throws {
        let data = try sampledData(hertz: hertz, [(0, 1), (1 / hertz, 2)])
        let period = try #require(data.period.value?.decimal)
        #expect(period == (try #require(Decimal(string: expected))))
        #expect(period.description == expected)
    }

    /// Without a stated frequency the period is the mean interval: n samples span n-1 of them.
    @Test
    func periodFallsBackToTheMeasurementIntervals() throws {
        let data = try sampledData(hertz: nil, [(0, 1), (0.002, 2), (0.004, 3), (0.006, 4), (0.008, 5)])
        #expect(data.period.value?.decimal == Decimal(string: "2"))
    }

    @Test
    func aSingleMeasurementWithoutAFrequencyHasNoPeriod() {
        #expect(throws: GroveHealthKitFHIRError.self) {
            try sampledData(hertz: nil, [(0, 1)])
        }
    }

    /// `SampledData` carries no per-sample timing, so the values must be written in time order.
    @Test
    func measurementsAreOrderedByTime() throws {
        let data = try sampledData(hertz: 512, [(2 / 512, 3), (0, 1), (1 / 512, 2)])
        #expect(data.data?.value?.string == "1.0 2.0 3.0")
    }
}

#endif
