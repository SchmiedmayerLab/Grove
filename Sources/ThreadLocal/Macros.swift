//
// This source file is part of the ThreadLocal open-source project
//
// SPDX-FileCopyrightText: 2025 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//


/// Defines a thread-local static variable.
///
/// Thread-local variables are backed using pthreads thread-specific data.
///
/// ```swift
/// extension SomeType {
///     @ThreadLocal
///     private static var counter: Int = 0
/// }
/// ```
@attached(accessor, names: named(get), named(set))
@attached(peer, names: prefixed(_))
public macro ThreadLocal(
) = #externalMacro(module: "ThreadLocalMacros", type: "ThreadLocalMacro")


/// Defines a thread-local static variable that uses a non-default deallocator.
///
/// Thread-local variables are backed using pthreads thread-specific data.
///
/// Example: using `zstd` in multi-threaded applications.
/// In the snippet below, each thread calling `Data.zstdCompress()` will use its own compression context object,
/// making the function safe to be used from multiple threads in parallel.
///
/// ```swift
/// extension Data {
///     @ThreadLocal(deallocator: .custom(ZSTD_freeCCtx))
///     private static var cCtx: OpaquePointer = ZSTD_createCCtx()
///
///     func zstdCompress(level: Int) throws -> Data {
///         let result = ZSTD_compressCCtx(Self.cCtx, /*...*/)
///         // ...
///     }
/// }
/// ```
@attached(accessor, names: named(get), named(set))
@attached(peer, names: prefixed(_))
public macro ThreadLocal<Value>(
    deallocator: ThreadLocal<Value>.Deallocator
) = #externalMacro(module: "ThreadLocalMacros", type: "ThreadLocalMacro")
