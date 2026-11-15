//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

public import GroveFHIRContract
public import ModelsR4


/// Conversion availability for exact pinned source tokens. This is not proof of connection, consent or provider qualification.
public enum ProviderCapabilities {
    public enum Provider: String, CaseIterable, Sendable {
        case googleHealthAPI = "google-health-api"
        case oura
        case withings
    }

    public enum Support: Sendable, Equatable {
        case structured
        case nativeRecording
        case notYetImplemented
        case notAdmitted
        case requiresSourceEvidence
    }

    public struct Element: Sendable {
        public let path: String
        public let guideStatus: String
        public let outputProfiles: [FHIRPrimitive<Canonical>]
    }

    public struct Source: Sendable {
        public let provider: Provider
        public let token: String
        public let guideStatus: String
        public let elements: [Element]
        /// Possible semantic output profiles; a connection must select consented elements before conversion.
        public var outputProfiles: [FHIRPrimitive<Canonical>] {
            var seen: Set<String> = []
            return elements.flatMap(\.outputProfiles).filter { seen.insert($0.value?.url.absoluteString ?? "").inserted }
        }
        public let conversionSupport: Support
        /// The source's actual temporal form, narrower than a semantic profile that admits both forms.
        public let effective: FHIRMeasurementDefinition.Effective?
    }

    /// Every catalog source row, including deliberately refused rows and the atomic Withings pressure pair.
    public static func sources(for provider: Provider) -> [Source] {
        ProviderContract.sources.filter { $0.provider == provider.rawValue }.map {
            Source(
                provider: provider,
                token: $0.token,
                guideStatus: $0.status,
                elements: $0.elements.map { Element(path: $0.path, guideStatus: $0.status, outputProfiles: $0.outputProfiles) },
                conversionSupport: support(provider: provider, token: $0.token, guideStatus: $0.status),
                effective: effective(provider: provider, token: $0.token, guideStatus: $0.status)
            )
        }
    }

    private static func support(provider: Provider, token: String, guideStatus: String) -> Support {
        guard guideStatus != "intentionally-unsupported", guideStatus != "unmodeled", guideStatus != "deferred" else {
            return .notAdmitted
        }
        switch provider {
        case .googleHealthAPI:
            switch token {
            case "heart-rate": return .nativeRecording
            case "steps", "distance", "active-energy-burned", "weight", "body-fat", "height", "vo2-max",
                "daily-oxygen-saturation", "heart-rate-variability", "daily-resting-heart-rate", "daily-respiratory-rate",
                "blood-glucose", "core-body-temperature", "floors", "basal-energy-burned", "sleep", "exercise":
                return .structured
            default: return .notYetImplemented
            }
        case .oura:
            switch token {
            case "heartrate": return .nativeRecording
            case "daily_activity", "sleep", "daily_spo2", "workout", "vO2_max", "daily_cardiovascular_age", "daily_readiness":
                return .structured
            default: return .notYetImplemented
            }
        case .withings:
            return withings(token)
        }
    }

    private static func effective(provider: Provider, token: String, guideStatus: String) -> FHIRMeasurementDefinition.Effective? {
        guard support(provider: provider, token: token, guideStatus: guideStatus) == .structured else {
            return nil
        }
        switch provider {
        case .withings: return token.hasPrefix("getmeas:") ? .dateTime : .period
        case .oura: return token == "vO2_max" ? .dateTime : .period
        case .googleHealthAPI:
            switch token {
            case "weight", "body-fat", "height", "vo2-max", "heart-rate-variability", "blood-glucose", "core-body-temperature":
                return .dateTime
            default: return .period
            }
        }
    }

    // The catalog's scalar, atomic-panel and native-recording branches retain distinct outcomes.
    private static func withings(_ token: String) -> Support {
        if token == "getmeas:9+10" {
            return .structured
        }
        if token.hasPrefix("getmeas:"), let type = Int(token.dropFirst("getmeas:".count)) {
            if type == 9 || type == 10 {
                return .requiresSourceEvidence
            }
            if WithingsFHIR.contract(type) != nil {
                return .structured
            }
            switch WithingsFHIR.omissionReason(type) {
            case .missingRequiredEvidence: return .requiresSourceEvidence
            case .notAdmitted: return .notAdmitted
            case .notYetImplemented: return .notYetImplemented
            }
        }
        switch token {
        case "activityIntraday", "sleepIntraday": return .nativeRecording
        case "getactivity:steps", "getactivity:distance", "getactivity:calories",
            "getsummary:deepsleepduration", "getsummary:remsleepduration", "getsummary:lightsleepduration",
            "getsummary:wakeupduration", "getsummary:hr_average", "getsummary:rr_average", "getworkouts:interval":
            return .structured
        default:
            return .notYetImplemented
        }
    }
}
