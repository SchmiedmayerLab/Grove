//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2025 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

#if os(macOS) // macro tests can only be run on the host machine
import Foundation
import SwiftSyntaxMacroExpansion
import SwiftSyntaxMacros
import SwiftSyntaxMacrosGenericTestSupport
import Testing
import ThreadLocal
import ThreadLocalMacros

let testMacrosSpecs: [String: MacroSpec] = [
    "ThreadLocal": MacroSpec(type: ThreadLocalMacro.self)
]


@Suite
struct ThreadLocalMacroTests {
    @Test
    func simpleInt() {
        assertMacroExpansion(
            """
            @ThreadLocal static var counter: Int = 0
            """,
            expandedSource:
            """
            static var counter: Int {
                @available(*, noasync) get {
                    _counter._get(default: 0)
                }
                @available(*, noasync) set {
                    _counter._set(newValue)
                }
            }

            private static let _counter = ThreadLocal<Int>()
            """,
            macroSpecs: testMacrosSpecs,
            failureHandler: { Issue.record("\($0.message)") }
        )
    }

    @Test("Empty parentheses are the attribute without arguments")
    func emptyParentheses() {
        assertMacroExpansion(
            """
            @ThreadLocal() static var counter: Int = 0
            """,
            expandedSource:
            """
            static var counter: Int {
                @available(*, noasync) get {
                    _counter._get(default: 0)
                }
                @available(*, noasync) set {
                    _counter._set(newValue)
                }
            }

            private static let _counter = ThreadLocal<Int>()
            """,
            macroSpecs: testMacrosSpecs,
            failureHandler: { Issue.record("\($0.message)") }
        )
    }

    @Test
    func inlinable() {
        assertMacroExpansion(
            """
            @ThreadLocal @inlinable static var counter: Int = 0
            """,
            expandedSource:
            """
            @inlinable static var counter: Int {
                @available(*, noasync) get {
                    _counter._get(default: 0)
                }
                @available(*, noasync) set {
                    _counter._set(newValue)
                }
            }

            @usableFromInline internal static let _counter = ThreadLocal<Int>()
            """,
            macroSpecs: testMacrosSpecs,
            failureHandler: { Issue.record("\($0.message)") }
        )
    }

    @Test
    func customDeallocator() {
        assertMacroExpansion(
            """
            @ThreadLocal(deallocator: .custom(ZSTD_freeCCtx)) static var ctx: OpaquePointer = ZSTD_createCCtx()
            """,
            expandedSource:
            """
            static var ctx: OpaquePointer {
                @available(*, noasync) get {
                    _ctx._get(default: ZSTD_createCCtx())
                }
                @available(*, noasync) set {
                    _ctx._set(newValue)
                }
            }

            private static let _ctx = ThreadLocal<OpaquePointer>(_deallocator: .custom(ZSTD_freeCCtx))
            """,
            macroSpecs: testMacrosSpecs,
            failureHandler: { Issue.record("\($0.message)") }
        )
    }


    @Test
    func publicProperty() {
        assertMacroExpansion(
            """
            @ThreadLocal public static var counter: Int = 0
            """,
            expandedSource:
            """
            public static var counter: Int {
                @available(*, noasync) get {
                    _counter._get(default: 0)
                }
                @available(*, noasync) set {
                    _counter._set(newValue)
                }
            }

            private static let _counter = ThreadLocal<Int>()
            """,
            macroSpecs: testMacrosSpecs,
            failureHandler: { Issue.record("\($0.message)") }
        )
    }


    @Test
    func instanceProperty() {
        assertMacroExpansion(
            """
            @ThreadLocal(deallocator: .custom(ZSTD_freeCCtx)) var ctx: OpaquePointer = ZSTD_createCCtx()
            """,
            expandedSource:
            """
            var ctx: OpaquePointer = ZSTD_createCCtx()
            """,
            diagnostics: [
                DiagnosticSpec(message: "@ThreadLocal property 'ctx' must be static", line: 1, column: 1)
            ],
            macroSpecs: testMacrosSpecs,
            failureHandler: { Issue.record("\($0.message)") }
        )
    }


    @Test
    func nonMatchingDeallocator() {
        assertMacroExpansion(
            """
            @ThreadLocal(deallocator: .custom { _ = $0 as OpaquePointer }) static var counter: Int = 0
            """,
            expandedSource:
            """
            static var counter: Int {
                @available(*, noasync) get {
                    _counter._get(default: 0)
                }
                @available(*, noasync) set {
                    _counter._set(newValue)
                }
            }

            private static let _counter = ThreadLocal<Int>(_deallocator: .custom {
                    _ = $0 as OpaquePointer
                })
            """,
            macroSpecs: testMacrosSpecs,
            failureHandler: { Issue.record("\($0.message)") }
        )
    }

    @Test("An optional without an initializer stores its whole type and defaults to nil")
    func optionalWithoutDefault() {
        assertMacroExpansion(
            """
            @ThreadLocal static var counter: Int?
            """,
            expandedSource:
            """
            static var counter: Int? {
                @available(*, noasync) get {
                    _counter._get(default: nil)
                }
                @available(*, noasync) set {
                    _counter._set(newValue)
                }
            }

            private static let _counter = ThreadLocal<Int?>()
            """,
            macroSpecs: testMacrosSpecs,
            failureHandler: { Issue.record("\($0.message)") }
        )
    }

    @Test("An optional with an initializer stores its whole type, so nil stays a value")
    func optionalWithDefault() {
        assertMacroExpansion(
            """
            @ThreadLocal static var counter: Int? = 5
            """,
            expandedSource:
            """
            static var counter: Int? {
                @available(*, noasync) get {
                    _counter._get(default: 5)
                }
                @available(*, noasync) set {
                    _counter._set(newValue)
                }
            }

            private static let _counter = ThreadLocal<Int?>()
            """,
            macroSpecs: testMacrosSpecs,
            failureHandler: { Issue.record("\($0.message)") }
        )
    }

    @Test("Optional<T> is an optional too")
    func spelledOutOptional() {
        assertMacroExpansion(
            """
            @ThreadLocal static var counter: Optional<Int>
            """,
            expandedSource:
            """
            static var counter: Optional<Int> {
                @available(*, noasync) get {
                    _counter._get(default: nil)
                }
                @available(*, noasync) set {
                    _counter._set(newValue)
                }
            }

            private static let _counter = ThreadLocal<Optional<Int>>()
            """,
            macroSpecs: testMacrosSpecs,
            failureHandler: { Issue.record("\($0.message)") }
        )
    }

    @Test("T! stores T?, as T! is no generic argument")
    func implicitlyUnwrappedOptional() {
        assertMacroExpansion(
            """
            @ThreadLocal static var counter: Int!
            """,
            expandedSource:
            """
            static var counter: Int! {
                @available(*, noasync) get {
                    _counter._get(default: nil)
                }
                @available(*, noasync) set {
                    _counter._set(newValue)
                }
            }

            private static let _counter = ThreadLocal<Int?>()
            """,
            macroSpecs: testMacrosSpecs,
            failureHandler: { Issue.record("\($0.message)") }
        )
    }

    @Test("A non-optional without an initializer has no default and is rejected")
    func nonOptionalWithoutDefault() {
        assertMacroExpansion(
            """
            @ThreadLocal static var counter: Int
            """,
            expandedSource:
            """
            static var counter: Int {
                @available(*, noasync) get {
                    _counter._get(default: nil)
                }
                @available(*, noasync) set {
                    _counter._set(newValue)
                }
            }
            """,
            diagnostics: [
                DiagnosticSpec(message: "A non-optional type requires an initializer expression to provide a default value", line: 1, column: 25)
            ],
            macroSpecs: testMacrosSpecs,
            failureHandler: { Issue.record("\($0.message)") }
        )
    }
}
#endif
