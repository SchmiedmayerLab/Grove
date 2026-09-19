//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import Foundation
@testable import GroveSpeechRecognizer
import Speech
import Testing


private actor SpeechAuthorizationGate {
    private var pending: CheckedContinuation<Bool, Never>?

    func request() async -> Bool {
        await withCheckedContinuation { pending = $0 }
    }

    func waitForRequest() async {
        while pending == nil {
            await Task.yield()
        }
    }

    func resolve(_ authorized: Bool) {
        pending?.resume(returning: authorized)
        pending = nil
    }
}


private final class TestSpeechRecording: SpeechRecognitionRecording, @unchecked Sendable {
    private let lock = NSLock()
    private var callbacks: [@Sendable (SFSpeechRecognitionResult?, (any Error)?) -> Void] = []
    private var stops = 0
    let isAvailable = true

    var startCount: Int { lock.withLock { callbacks.count } }
    var stopCount: Int { lock.withLock { stops } }

    func start(
        result: @escaping @Sendable (SFSpeechRecognitionResult?, (any Error)?) -> Void,
        level: @escaping @Sendable (Float) -> Void
    ) throws {
        lock.withLock { callbacks.append(result) }
    }

    func stop() {
        lock.withLock { stops += 1 }
    }

    func fail(at index: Int) {
        let callback = lock.withLock { callbacks[index] }
        callback(nil, URLError(.cancelled))
    }

    func waitForStarts(_ count: Int) async {
        while startCount < count {
            await Task.yield()
        }
    }
}


@Suite("Speech recognizer lifecycle", .timeLimit(.minutes(1)))
struct SpeechRecognizerLifecycleTests {
    @Test("Stopping while authorization is pending finishes without starting audio")
    func stopPendingAuthorization() async throws {
        let authorization = SpeechAuthorizationGate()
        let recording = TestSpeechRecording()
        let recognizer = SpeechRecognizer(recording: recording, authorization: authorization.request)
        let consumer = Task {
            for try await _ in recognizer.start() {}
        }
        await authorization.waitForRequest()
        recognizer.stop()
        try await consumer.value
        await authorization.resolve(true)
        try await Task.sleep(for: .milliseconds(20))
        #expect(recording.startCount == 0)
        #expect(!recognizer.isRecording)
    }

    @Test("Cancelling a stream also cancels its pending authorization")
    func cancelPendingAuthorization() async throws {
        let authorization = SpeechAuthorizationGate()
        let recording = TestSpeechRecording()
        let recognizer = SpeechRecognizer(recording: recording, authorization: authorization.request)
        let consumer = Task {
            for try await _ in recognizer.start() {}
        }
        await authorization.waitForRequest()
        consumer.cancel()
        try await consumer.value
        await authorization.resolve(true)
        try await Task.sleep(for: .milliseconds(20))
        #expect(recording.startCount == 0)
        #expect(!recognizer.isRecording)
    }

    @Test("Callbacks from an earlier recording cannot stop a later recording")
    func staleRecordingCallback() async throws {
        let recording = TestSpeechRecording()
        let recognizer = SpeechRecognizer(recording: recording) { true }
        let first = Task {
            for try await _ in recognizer.start() {}
        }
        await recording.waitForStarts(1)
        recognizer.stop()
        try await first.value
        let second = Task {
            for try await _ in recognizer.start() {}
        }
        await recording.waitForStarts(2)
        recording.fail(at: 0)
        try await Task.sleep(for: .milliseconds(20))
        #expect(recognizer.isRecording)
        #expect(recording.stopCount == 1)
        recognizer.stop()
        try await second.value
    }

    @Test("A denied authorization never starts audio and reports the refusal")
    func deniedAuthorization() async {
        let recording = TestSpeechRecording()
        let recognizer = SpeechRecognizer(recording: recording) { false }
        await #expect(throws: SpeechRecognizerError.self) {
            for try await _ in recognizer.start() {}
        }
        #expect(recording.startCount == 0)
        #expect(!recognizer.isRecording)
    }
}
