//
// This source file is part of the Stanford Spezi open-source project
//
// SPDX-FileCopyrightText: 2025 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import DequeModule
public import Foundation


@available(iOS 18, macOS 15, watchOS 11, *)
extension StudyDefinition {
    /// A criterion which must be satisfied for a person to be able to participate in a study.
    public indirect enum ParticipationCriterion: StudyDefinitionElement {
        /// a criterion which evaluates to true if the user is at least of the specified age
        case ageAtLeast(Int)
        /// a criterion which evaluates to true if the user is from the specified region
        case isFromRegion(Locale.Region)
        /// a criterion which evaluates to true if the user speaks the specified language
        case speaksLanguage(Locale.Language)
        /// a criterion which evaluates to true based on a custom condition
        case custom(CustomCriterionKey)
        
        /// a criterion which evaluates to true iff its contained criterion evaluates to false.
        case not(ParticipationCriterion)
        /// a criterion which evaluates to true iff all of its contained criteria evaluate to true
        /// - Note: if the list of contained criteria is empty, the criterion will evaluate to true
        case all([ParticipationCriterion])
        /// a criterion which evaluates to true iff any of its contained criteria evaluates to true
        /// - Note: if the list of contained criteria is empty, the criterion will evaluate to false
        case any([ParticipationCriterion])
        
        /// Key used to identify a custom criterion.
        public struct CustomCriterionKey: Codable, Hashable, Sendable {
            /// The key's identifying value
            public let keyValue: String
            /// The key's user-visible display title
            public let displayTitle: String
            /// Creates a new key for a custom criterion
            public init(_ keyValue: String, displayTitle: String) {
                self.keyValue = keyValue
                self.displayTitle = displayTitle
            }
        }
        
        public static prefix func ! (rhs: Self) -> Self {
            .not(rhs)
        }
        public static func && (lhs: Self, rhs: Self) -> Self {
            .all([lhs, rhs])
        }
        public static func || (lhs: Self, rhs: Self) -> Self {
            .any([lhs, rhs])
        }
    }
}

@available(iOS 18, macOS 15, watchOS 11, *)
extension StudyDefinition.ParticipationCriterion: ExpressibleByBooleanLiteral {
    /// Creates a `Criterion` that always evaluates to a specified Boolean value.
    ///
    /// - parameter value: The Boolean value the criterion should evaluate to.
    public init(booleanLiteral value: Bool) {
        switch value {
        case true:
            self = .all([])
        case false:
            self = .any([])
        }
    }
}


// MARK: Criterion Eval

@available(iOS 18, macOS 15, watchOS 11, *)
extension StudyDefinition.ParticipationCriterion {
    /// Context against which the ``StudyDefinition/ParticipationCriterion`` are evaluated.
    public struct EvaluationEnvironment {
        let age: Int?
        let region: Locale.Region?
        let language: Locale.Language
        let enabledCustomKeys: Set<CustomCriterionKey>
        
        /// Creates a new evaluation environment, using the specified values.
        public init(
            age: Int?,
            region: Locale.Region?,
            language: Locale.Language,
            enabledCustomKeys: Set<CustomCriterionKey>
        ) {
            self.age = age
            self.region = region
            self.language = language
            self.enabledCustomKeys = enabledCustomKeys
        }
    }
    
    
    /// Determine whether the criteria are satisfied.
    public func evaluate(_ environment: EvaluationEnvironment) -> Bool {
        switch self {
        case .ageAtLeast(let minAge):
            if let age = environment.age {
                return age >= minAge
            } else {
                return false
            }
        case .isFromRegion(let allowedRegion):
            if let region = environment.region {
                return region == allowedRegion
            } else {
                return false
            }
        case .speaksLanguage(let language):
            return language == environment.language
        case .custom(let key):
            return environment.enabledCustomKeys.contains(key)
        case .not(let criterion):
            return !criterion.evaluate(environment)
        case .any(let criteria):
            return criteria.contains { $0.evaluate(environment) }
        case .all(let criteria):
            return criteria.allSatisfy { $0.evaluate(environment) }
        }
    }
}


@available(iOS 18, macOS 15, watchOS 11, *)
extension StudyDefinition.ParticipationCriterion {
    /// whether the criterion is a leaf element, i.e. doesn't contain any nested further criteria
    public var isLeaf: Bool {
        switch self {
        case .ageAtLeast, .isFromRegion, .speaksLanguage, .custom:
            true
        case .not, .any, .all:
            false
        }
    }
    
    /// The children of this node, if any.
    public var children: [Self] {
        switch self {
        case .ageAtLeast, .isFromRegion, .speaksLanguage, .custom:
            []
        case .not(let inner):
            [inner]
        case .any(let nested), .all(let nested):
            nested
        }
    }
    
    /// All leaf nodes.
    public var allLeafs: Set<Self> {
        reduce(into: []) { leafs, criterion in
            if criterion.isLeaf {
                leafs.insert(criterion)
            }
        }
    }
    
    /// Reduces the tree, using the specified closure.
    public func reduce<Result>(
        into initialResult: Result,
        _ visitor: (inout Result, Self) throws -> Void
    ) rethrows -> Result {
        var result = initialResult
        var deque: Deque<Self> = [self]
        while let node = deque.popFirst() {
            try visitor(&result, node)
            deque.append(contentsOf: node.children)
        }
        return result
    }
}
