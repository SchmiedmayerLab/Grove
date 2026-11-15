//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

#if os(iOS)

public import Foundation
public import GroveFoundation
public import SensorKit


// `SRHeadphoneSettings` exists only in the iOS 27 SDK.
#if compiler(>=6.4)
@available(iOS 27, *)
extension SRHeadphoneSettings: SensorKitSampleProtocol {
    /// Immutable typed settings, including explicit unsupported/disabled states and optional hearing assistance.
    public struct SafeRepresentation: SensorKitSampleSafeRepresentation {
        public struct HearingAssistance: Hashable, Sendable {
            public let hearingAidEnabled: SRHeadphoneSettings.SettingEnablement
            public let mediaAssistEnabled: SRHeadphoneSettings.SettingEnablement
            public let adjustMediaEnabled: SRHeadphoneSettings.SettingEnablement
            public let adjustVoiceEnabled: SRHeadphoneSettings.SettingEnablement
            public let hearingProtectionEnabled: SRHeadphoneSettings.SettingEnablement
            public let conversationBoostEnabled: SRHeadphoneSettings.SettingEnablement
            public let hearingAidAmplification: Double
            public let hearingAidBalance: Double
            public let hearingAidTone: Double
            public let ambientNoiseReduction: Double

            init(_ value: SRHeadphoneSettings.HearingAssistance) {
                hearingAidEnabled = value.hearingAidEnabled
                mediaAssistEnabled = value.mediaAssistEnabled
                adjustMediaEnabled = value.adjustMediaEnabled
                adjustVoiceEnabled = value.adjustVoiceEnabled
                hearingProtectionEnabled = value.hearingProtectionEnabled
                conversationBoostEnabled = value.conversationBoostEnabled
                hearingAidAmplification = value.hearingAidAmplification
                hearingAidBalance = value.hearingAidBalance
                hearingAidTone = value.hearingAidTone
                ambientNoiseReduction = value.ambientNoiseReduction
            }
        }

        public let timestamp: Date
        public let adaptiveAudioStrength: SRHeadphoneSettings.AdaptiveAudioStrength
        public let listeningMode: SRHeadphoneSettings.ListeningMode
        public let personalizedVolumeEnabled: SRHeadphoneSettings.SettingEnablement
        public let conversationAwarenessEnabled: SRHeadphoneSettings.SettingEnablement
        public let spatialAudioEnabled: SRHeadphoneSettings.SettingEnablement
        public let personalizedSpatialAudioEnabled: SRHeadphoneSettings.SettingEnablement
        public let hearingAssistance: HearingAssistance?

        public var timeRange: Range<Date> { timestamp..<timestamp }

        init(timestamp: Date, sample: SRHeadphoneSettings) {
            self.timestamp = timestamp
            adaptiveAudioStrength = sample.adaptiveAudioStrength
            listeningMode = sample.listeningMode
            personalizedVolumeEnabled = sample.personalizedVolumeEnabled
            conversationAwarenessEnabled = sample.conversationAwarenessEnabled
            spatialAudioEnabled = sample.spatialAudioEnabled
            personalizedSpatialAudioEnabled = sample.personalizedSpatialAudioEnabled
            hearingAssistance = sample.hearingAssistance.map(HearingAssistance.init)
        }
    }

    public static func processIntoSafeRepresentation(
        _ samples: some Sequence<(timestamp: Date, sample: SRHeadphoneSettings)>
    ) -> [SafeRepresentation] {
        samples.map { SafeRepresentation(timestamp: $0.timestamp, sample: $0.sample) }
    }
}


@available(iOS 27, *)
extension Sensor where Sample == SRHeadphoneSettings {
    /// Headphone configuration events, preserving every public setting and explicit availability state.
    @inlinable public static var headphoneSettings: Sensor<SRHeadphoneSettings> {
        Sensor(
            srSensor: .headphoneSettings,
            displayName: "Headphone Settings",
            dataQuarantineDuration: .hours(24),
            sensorKitFetchReturnType: .object
        )
    }
}
#endif

#endif
