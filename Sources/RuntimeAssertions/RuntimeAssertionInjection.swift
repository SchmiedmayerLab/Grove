//
// This source file is part of the Stanford Spezi open-source project
//
// SPDX-FileCopyrightText: 2022 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

public import Foundation


@usableFromInline
package struct RuntimeAssertionInjection: Sendable {
    @usableFromInline package typealias AssertCall = @Sendable (() -> Bool, () -> String, StaticString, UInt) -> Void
    @usableFromInline package typealias PreconditionCall = @Sendable (() -> Bool, () -> String, StaticString, UInt) -> Void

    
    @usableFromInline @TaskLocal static var current: RuntimeAssertionInjection?

    
    @usableFromInline package let id: UUID
    @usableFromInline let assert: AssertCall
    @usableFromInline let precondition: PreconditionCall

    
    package init(
        id: UUID = UUID(),
        assert: @escaping AssertCall,
        precondition: @escaping PreconditionCall
    ) {
        self.id = id
        self.assert = assert
        self.precondition = precondition
    }
    
    package init(
        id: UUID = UUID(),
        assert: @escaping AssertCall
    ) {
        self.id = id
        self.assert = assert
        self.precondition = { @Sendable condition, message, file, line in
            Swift.precondition(condition(), message(), file: file, line: line)
        }
    }
    
    package init(
        id: UUID = UUID(),
        precondition: @escaping PreconditionCall
    ) {
        self.id = id
        self.assert = { @Sendable condition, message, file, line in
            Swift.assert(condition(), message(), file: file, line: line)
        }
        self.precondition = precondition
    }
    
    package init(
        id: UUID = UUID()
    ) {
        self.id = id
        self.assert = { @Sendable condition, message, file, line in
            Swift.assert(condition(), message(), file: file, line: line)
        }
        self.precondition = { @Sendable condition, message, file, line in
            Swift.precondition(condition(), message(), file: file, line: line)
        }
    }

    package func withInjection<T, E: Error>(_ block: () throws(E) -> T) throws(E) -> T {
        do {
            return try RuntimeAssertionInjection.$current.withValue(self) {
                try block()
            }
        } catch {
            guard let error = error as? E else {
                Swift.preconditionFailure("Unexpected error type \(type(of: error))")
            }
            throw error
        }
    }

    package func withInjection<T, E: Error>(_ block: () async throws(E) -> T) async throws(E) -> T {
        do {
            return try await RuntimeAssertionInjection.$current.withValue(self) {
                try await block()
            }
        } catch {
            guard let error = error as? E else {
                Swift.preconditionFailure("Unexpected error type \(type(of: error))")
            }
            throw error
        }
    }
}


extension RuntimeAssertionInjection {
    @inlinable
    static func assert(_ condition: () -> Bool, message: () -> String, file: StaticString, line: UInt) {
        if let current {
            current.assert(condition, message, file, line)
        } else {
            Swift.assert(condition(), message(), file: file, line: line)
        }
    }

    @inlinable
    static func precondition(_ condition: () -> Bool, message: () -> String, file: StaticString, line: UInt) {
        if let current {
            current.precondition(condition, message, file, line)
        } else {
            Swift.precondition(condition(), message(), file: file, line: line)
        }
    }
}
