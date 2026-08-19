//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2025 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

/// How a `Locale` should be matched against a ``LocalizationKey``.
///
/// ## Topics
///
/// ### Enumeration Cases
/// - ``requirePerfectMatch``
/// - ``preferLanguageMatch``
/// - ``preferRegionMatch``
/// - ``custom(_:)``
@available(iOS 18, macOS 15, watchOS 11, *)
public enum LocaleMatchingBehaviour: Sendable {
    /// Only perfect matches are allowed
    ///
    /// If no perfect match exists, but there does exist a match where e.g. the resource's language matches but its region doesn't, it will still get ignored.
    case requirePerfectMatch
    
    /// If no perfect match exists, prefer partial matches where the language matches but the region does not over those where the region matches but the language does not.
    ///
    /// When using this option, perfect matches will still always take precedence over partial ones.
    case preferLanguageMatch
    
    /// If no perfect match exists, prefer partial matches where the region matches but the language does not over those where the language matches but the region does not.
    ///
    /// When using this option, perfect matches will still always take precedence over partial ones.
    case preferRegionMatch
    
    /// The matching should happen based on a fully custom behaviour.
    ///
    /// - parameter match: A closure that determines how well two ``LocalizationKey``s match.
    ///     The closure should return a score in the range `0...1`; any values exceeding that range will get clamped.
    case custom(_ match: @Sendable (LocalizationKey, LocalizationKey) -> Double)
    
    /// The default matching behaviour
    @inlinable public static var `default`: Self {
        .preferLanguageMatch
    }
    
    var isRequirePerfectMatch: Bool {
        switch self {
        case .requirePerfectMatch:
            true
        case .preferLanguageMatch, .preferRegionMatch, .custom:
            false
        }
    }
}
