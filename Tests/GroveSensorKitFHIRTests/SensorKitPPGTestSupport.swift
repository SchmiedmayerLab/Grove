//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import Foundation
import GroveSensorKitFHIR


enum SensorKitPPGTestSupport {
    static func recording(start: Date, recordCount: Int = 2) -> SensorKitPPGRecording {
        SensorKitPPGRecording(records: (0..<recordCount).map { index in
            SensorKitPPGRecording.Record(
                startDate: start,
                nanosecondsSinceStart: Int64(index) * 1_000_000_000,
                temperature: index.isMultiple(of: 2) ? 31.5 : nil,
                usage: ["foreground"],
                opticalSamples: [
                    .init(
                        emitter: 1,
                        activePhotodiodeIndexes: [1, 3],
                        signalIdentifier: 2,
                        nominalWavelength: 525,
                        effectiveWavelength: 524.5,
                        samplingFrequency: 128,
                        nanosecondsSinceStart: Int64(index) * 1_000_000_000 + 250_000_000,
                        conditions: ["signalSaturated"],
                        noiseTerms: .init(
                            whiteNoise: 0.1,
                            pinkNoise: 0.2,
                            backgroundNoise: 0.3,
                            backgroundNoiseOffset: 0.4
                        ),
                        normalizedReflectance: 0.75
                    )
                ],
                accelerometerSamples: [
                    .init(
                        nanosecondsSinceStart: Int64(index) * 1_000_000_000 + 500_000_000,
                        samplingFrequency: 64,
                        x: 0.1,
                        y: 0.2,
                        z: 0.3
                    )
                ]
            )
        })
    }
}
