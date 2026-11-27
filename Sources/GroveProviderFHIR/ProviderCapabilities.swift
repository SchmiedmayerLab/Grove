//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

public import GroveFHIRContract
public import ModelsR4


/// The conversion support of each source token of the pinned provider catalog.
///
/// Support is neither proof of a connection nor consent nor a provider's qualification.
public enum ProviderCapabilities {
    /// A provider of the catalog.
    public enum Provider: String, CaseIterable, Sendable {
        /// The Google Health API.
        case googleHealthAPI = "google-health-api"
        /// Oura.
        case oura
        /// Withings.
        case withings

        var code: OpaqueIdentityScope.ProviderCode {
            switch self {
            case .googleHealthAPI: .googleHealthAPI
            case .oura: .oura
            case .withings: .withings
            }
        }
    }

    /// How the converter supports a source token.
    public enum Support: Sendable, Equatable {
        /// The converter produces structured Observations.
        case structured
        /// The converter produces a recording document of the native payload.
        case nativeRecording
        /// The guide admits the source, but the converter doesn't convert it yet.
        case notYetImplemented
        /// The guide admits no output for the source.
        case notAdmitted
        /// The source needs evidence a single record doesn't carry, such as the other half of a blood pressure pair.
        case requiresSourceEvidence
    }

    /// One element of a source row.
    public struct Element: Sendable {
        /// The element's path in the provider's payload.
        public let path: String
        /// The element's status in the guide.
        public let guideStatus: ProviderImplementationStatus
        /// The semantic profiles the element converts to.
        public let outputProfiles: [FHIRPrimitive<Canonical>]
    }

    /// One source row of the catalog.
    public struct Source: Sendable {
        /// The source's provider.
        public let provider: Provider
        /// The source token.
        public let token: String
        /// The source's status in the guide.
        public let guideStatus: ProviderImplementationStatus
        /// The source's elements.
        public let elements: [Element]
        /// Possible semantic output profiles; a connection must select consented elements before conversion.
        public var outputProfiles: [FHIRPrimitive<Canonical>] {
            var seen: Set<FHIRPrimitive<Canonical>> = []
            return elements.flatMap(\.outputProfiles).filter { seen.insert($0).inserted }
        }
        /// How the converter supports the source.
        public let conversionSupport: Support
        /// The source's actual temporal form, narrower than a semantic profile that admits both forms.
        public let effective: FHIRMeasurementDefinition.Effective?
    }

    /// Every catalog source row of a provider, including deliberately refused rows and the atomic Withings pressure pair.
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

    private static func support(provider: Provider, token: String, guideStatus: ProviderImplementationStatus) -> Support {
        guard ![.intentionallyUnsupported, .unmodeled, .deferred].contains(guideStatus) else {
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

    private static func effective(
        provider: Provider,
        token: String,
        guideStatus: ProviderImplementationStatus
    ) -> FHIRMeasurementDefinition.Effective? {
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
            if WithingsConversion.contract(type) != nil {
                return .structured
            }
            switch WithingsConversion.omissionReason(type) {
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
