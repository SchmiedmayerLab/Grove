//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2025 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

public import Foundation


/// A Timed Walking Test's configuration
@available(iOS 18, macOS 15, watchOS 11, *)
public struct TimedWalkingTestConfiguration: Codable, Hashable, Sendable {
    /// The kind of a Timed Walking Test
    public enum Kind: UInt8, Codable, Hashable, CaseIterable, Sendable {
        /// A test that observes the user walking
        case walking
        /// A test that observes the user running
        case running
    }
    
    /// How long the test should be conducted
    public let duration: Duration
    /// The kind of test
    public let kind: Kind
    
    /// Creates a new Timed Walking Test configuration
    public init(duration: Duration, kind: Kind) {
        self.duration = duration
        self.kind = kind
    }
}


@available(iOS 18, macOS 15, watchOS 11, *)
extension TimedWalkingTestConfiguration {
    /// The six-minute walk test
    public static let sixMinuteWalkTest = TimedWalkingTestConfiguration(duration: .minutes(6), kind: .walking)
    
    /// The 12-minute run test, also known as the Cooper Test.
    public static let twelveMinuteRunTest = TimedWalkingTestConfiguration(duration: .minutes(12), kind: .running)
}


@available(iOS 18, macOS 15, watchOS 11, *)
extension StudyDefinition {
    /// Study Component which prompts the user to perform a Timed Walking Test
    public struct TimedWalkingTestComponent: Identifiable, StudyDefinitionElement {
        public var id: UUID
        public var test: TimedWalkingTestConfiguration
        
        public init(id: UUID, test: TimedWalkingTestConfiguration) {
            self.id = id
            self.test = test
        }
    }
}


#if canImport(Darwin)
@available(iOS 18, macOS 15, watchOS 11, *)
extension TimedWalkingTestConfiguration {
    /// A textual description of the Timed Walking Test, localized for the current locale.
    public var displayTitle: LocalizedStringResource {
        displayTitle(in: .autoupdatingCurrent)
    }

    /// A textual description of the Timed Walking Test, localized for the specified locale.
    ///
    /// The locale is applied to the embedded duration (number formatting and capitalization) as well as
    /// to the string resource itself; the formatters are per-call since they're locale-dependent.
    public func displayTitle(in locale: Locale) -> LocalizedStringResource {
        let durationInMin = duration.totalSeconds / 60
        let durationText: String
        if durationInMin.rounded() == durationInMin, durationInMin <= 10 { // whole number of minutes
            let fmt = NumberFormatter()
            fmt.numberStyle = .spellOut
            fmt.locale = locale
            durationText = fmt.string(from: NSNumber(value: Int(durationInMin))) ?? "\(Int(durationInMin))"
        } else {
            let fmt = NumberFormatter()
            fmt.numberStyle = .decimal
            fmt.minimumFractionDigits = 0
            fmt.maximumFractionDigits = 1
            fmt.locale = locale
            durationText = fmt.string(from: NSNumber(value: durationInMin)) ?? String(format: "%.1f", durationInMin)
        }
        var title: LocalizedStringResource = switch kind {
        case .walking:
            LocalizedStringResource("\(durationText.capitalized(with: locale))-Minute Walk Test", bundle: .module)
        case .running:
            LocalizedStringResource("\(durationText.capitalized(with: locale))-Minute Run Test", bundle: .module)
        }
        title.locale = locale
        return title
    }
}
#endif
