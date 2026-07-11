//
// This source file is part of the ThreadLocal open source project
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
}
#endif
