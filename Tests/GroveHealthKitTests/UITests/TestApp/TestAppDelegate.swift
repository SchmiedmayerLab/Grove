//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2022 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import Grove
@_spi(TestingSupport)
import GroveHealthKit
import GroveHealthKitBulkExport


class TestAppDelegate: GroveAppDelegate {
    override var configuration: Configuration {
        Configuration(standard: TestAppStandard()) { // swiftlint:disable:this closure_body_length
            HealthKit { // swiftlint:disable:this closure_body_length
                CollectSamples(
                    .electrocardiogram,
                    start: .manual,
                    continueInBackground: true
                )
                CollectSamples(
                    .stepCount,
                    start: .automatic,
                    continueInBackground: true
                )
                CollectSamples(
                    .pushCount,
                    start: .manual
                )
                CollectSamples(
                    .activeEnergyBurned
                )
                CollectSamples(.heartRate, start: .manual)
                CollectSamples(.heartRate, start: .manual)
                
                CollectSamples(.stairAscentSpeed, continueInBackground: true)
                CollectSamples(.stairDescentSpeed, continueInBackground: false)
                CollectSamples(.workout)
                if !HealthKit.needsBloodPressureAuthFlowFix {
                    CollectSamples(.bloodPressure, start: .automatic, continueInBackground: true)
                }
                
                RequestReadAccess(
                    quantity: [.bloodOxygen],
                    category: [.sleepAnalysis],
                    characteristic: Array {
                        HealthKitCharacteristic.activityMoveMode
                        HealthKitCharacteristic.biologicalSex
                        if !ProcessInfo.processInfo.arguments.contains("--disable-blood-type-auth-request") {
                            HealthKitCharacteristic.bloodType
                        }
                        HealthKitCharacteristic.dateOfBirth
                        HealthKitCharacteristic.fitzpatrickSkinType
                        HealthKitCharacteristic.wheelchairUse
                    },
                    other: [SampleType.workout, SampleType.audiogram, SampleType.gad7, SampleType.phq9]
                )
                
                RequestWriteAccess(
                    quantity: [.heartRate, .bloodOxygen, .stepCount, .height, .activeEnergyBurned, .pushCount, .distanceCycling],
                    category: [.sleepAnalysis],
                    other: [SampleType.gad7, SampleType.phq9]
                )
            }
            
            BulkHealthExporter()
        }
    }
}
