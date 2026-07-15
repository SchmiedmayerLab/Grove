//
// This source file is part of the Stanford XCTestExtensions open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

public import XCTest


extension XCUIElementQuery {
    /// Returns a new query that matches elements that meet the logical conditions of the provided predicate.
    ///
    /// - Note: This function is identical to `-[XCUIElementQuery matchingPredicate:]`, except that it takes a `String` and then implicitly creates an `NSPredicate` from that.
    ///
    /// - parameter predicateFormat: The predicate's format string
    /// - parameter args: The arguments that are substited into the predicate
    public func matching(_ predicateFormat: String, _ args: Any...) -> XCUIElementQuery {
        self.matching(NSPredicate(format: predicateFormat, argumentArray: args))
    }
    
    /// Matches the predicate.
    ///
    /// - Note: This function is identical to `-[XCUIElementQuery elementMatchingPredicate:]`, except that it takes a `String` and then implicitly creates an `NSPredicate` from that.
    ///
    /// - parameter predicateFormat: The predicate's format string
    /// - parameter args: The arguments that are substited into the predicate
    public func element(matching predicateFormat: String, _ args: Any...) -> XCUIElement {
        self.element(matching: NSPredicate(format: predicateFormat, argumentArray: args))
    }
    
    /// Returns a new query that matches elements containing a descendant that meets the logical conditions of the provided predicate.
    ///
    /// - Note: This function is identical to `-[XCUIElementQuery containingPredicate:]`, except that it takes a `String` and then implicitly creates an `NSPredicate` from that.
    ///
    /// - parameter predicateFormat: The predicate's format string
    /// - parameter args: The arguments that are substited into the predicate
    public func containing(_ predicateFormat: String, _ args: Any...) -> XCUIElementQuery {
        self.containing(NSPredicate(format: predicateFormat, argumentArray: args))
    }
}
