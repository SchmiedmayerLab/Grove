//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2025 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//
// Tests adopted from https://github.com/groue/Semaphore/blob/main/Sources/Semaphore/AsyncSemaphore.swift.
//

@testable import GroveFoundation
import Testing


@Suite
struct AnyAsyncSequenceTests {
    private func getCountingSequence<T: Sendable>(
        for range: Range<T>,
        interval: Duration = .seconds(0.01)
    ) -> AsyncStream<T> where T: Strideable, T.Stride: SignedInteger {
        let (stream, continuation) = AsyncStream.makeStream(of: T.self)
        Task {
            defer {
                continuation.finish()
            }
            do {
                for element in range {
                    try await Task.sleep(for: interval)
                    continuation.yield(element)
                }
            } catch {
                return
            }
        }
        return stream
    }
    
    private func collect<S: AsyncSequence>(_ sequence: S) async throws -> [S.Element] {
        var elements: [S.Element] = []
        for try await element in sequence {
            elements.append(element)
        }
        return elements
    }
    
    
    @Test
    func sequence0() async throws {
        let seq = getCountingSequence(for: 0..<500)
        #expect(try await collect(seq) == Array(0..<500))
    }
    
    
    @Test
    func sequence1A() async throws {
        let seq = AnyAsyncSequence(getCountingSequence(for: 0..<500))
        #expect(try await collect(seq) == Array(0..<500))
    }
    
    @Test
    @available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
    func sequence1B() async throws {
        let seq = AnyAsyncSequence(getCountingSequence(for: 0..<500))
        #expect(try await collect(seq) == Array(0..<500))
    }
    
    @Test
    @available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
    func sequence1C() async throws {
        let seq = AnyAsyncSequence(unsafelyAssumingDoesntThrow: getCountingSequence(for: 0..<500))
        #expect(try await collect(seq) == Array(0..<500))
    }
    
    
    @Test
    func sequence2A() async throws {
        let seq = AnyAsyncSequence(getCountingSequence(for: 0..<500).filter { $0 < 250 })
        #expect(try await collect(seq) == Array(0..<250))
    }
    
    @Test
    @available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
    func sequence2B() async throws {
        let seq = AnyAsyncSequence(getCountingSequence(for: 0..<500).filter { $0 < 250 })
        #expect(try await collect(seq) == Array(0..<250))
    }
    
    @Test
    @available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
    func sequence2C() async throws {
        let seq = AnyAsyncSequence(unsafelyAssumingDoesntThrow: getCountingSequence(for: 0..<500).filter { $0 < 250 })
        #expect(try await collect(seq) == Array(0..<250))
    }
    
    
    @Test
    func sequence3A() async throws {
        let seq = AnyAsyncSequence(getCountingSequence(for: 0..<500)).filter { $0 < 250 }
        #expect(try await collect(seq) == Array(0..<250))
    }
    
    @Test
    @available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
    func sequence3B() async throws {
        let seq = AnyAsyncSequence(getCountingSequence(for: 0..<500)).filter { $0 < 250 }
        #expect(try await collect(seq) == Array(0..<250))
    }
    
    @Test
    @available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
    func sequence3C() async throws {
        let seq = AnyAsyncSequence(unsafelyAssumingDoesntThrow: getCountingSequence(for: 0..<500)).filter { $0 < 250 }
        #expect(try await collect(seq) == Array(0..<250))
    }
}
