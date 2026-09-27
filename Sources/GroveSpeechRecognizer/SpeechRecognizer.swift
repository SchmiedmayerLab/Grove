//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2023 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

public import Foundation
public import Grove
public import Observation
import os
public import Speech


/// Initiate and manage speech recognition.
///
/// The Grove `SpeechRecognizer` encapsulates the functionality of Apple's `Speech` framework, more specifically, the `SFSpeechRecognizer`.
/// It provides methods to start and stop voice recognition and publishes the state of recognition and its availability.
///
/// > Important: If your application is not yet configured to use Grove, follow the [Grove setup article](../Grove/Grove.docc/Initial-Setup.md) to set up the core Grove infrastructure.
///
/// The module needs to be registered in a Grove-based application using the [`configuration`](../Grove/Grove.docc/Grove.md)
/// in a [`GroveAppDelegate`](../Grove/Grove.docc/Grove.md):
/// ```swift
/// class ExampleAppDelegate: GroveAppDelegate {
///     override var configuration: Configuration {
///         Configuration {
///             SpeechRecognizer()
///             // ...
///         }
///     }
/// }
/// ```
/// > Tip: You can learn more about a [`Module` in the Grove documentation](../Grove/Grove.docc/Module/Module.md).
///
/// ## Usage
///
/// ```swift
/// struct SpeechRecognizerView: View {
///     // Get the `SpeechRecognizer` from the SwiftUI `Environment`.
///     @Environment(SpeechRecognizer.self) private var speechRecognizer
///     // The transcribed message from the user's voice input.
///     @State private var message = ""
///
///     var body: some View {
///         VStack {
///             Button("Record") {
///                 microphoneButtonPressed()
///             }
///                 .padding(.bottom)
///
///             Text(message)
///         }
///
///     }
///
///     private func microphoneButtonPressed() {
///         if speechRecognizer.isRecording {
///            // If speech is currently recognized, stop the transcribing.
///            speechRecognizer.stop()
///         } else {
///            // If the recognizer is idle, start a new recording.
///            Task {
///               do {
///                  // The `speechRecognizer.start()` function returns an `AsyncThrowingStream` that yields the transcribed text.
///                  for try await result in speechRecognizer.start() {
///                      // Access the string-based result of the transcribed result
///                      message = result.bestTranscription.formattedString
///                  }
///             }
///         }
///     }
/// }
/// ```
@available(iOS 18, macOS 15, watchOS 11, *)
@Observable
public final class SpeechRecognizer: NSObject, Module, DefaultInitializable, EnvironmentAccessible, SFSpeechRecognizerDelegate, @unchecked Sendable {
    typealias ResultStream = AsyncThrowingStream<SFSpeechRecognitionResult, any Error>

    private struct Session {
        let id: UUID
        let continuation: ResultStream.Continuation
        var authorizationTask: Task<Void, Never>?
    }

    private static let logger = Logger(subsystem: "org.grovealliance", category: "GroveSpeech")

    @ObservationIgnored private let lock = NSRecursiveLock()
    @ObservationIgnored private let recording: any SpeechRecognitionRecording
    @ObservationIgnored private let authorization: @Sendable () async -> Bool
    @ObservationIgnored private var session: Session?
    @ObservationIgnored private var recordingValue = false
    @ObservationIgnored private var availableValue: Bool
    @ObservationIgnored private var levelValue: Float = 0

    /// Indicates whether speech recognition is currently recording audio.
    public private(set) var isRecording: Bool {
        get {
            access(keyPath: \.isRecording)
            return lock.withLock { recordingValue }
        }
        set { withMutation(keyPath: \.isRecording) { lock.withLock { recordingValue = newValue } } }
    }

    /// Indicates the availability of the speech recognition service.
    public private(set) var isAvailable: Bool {
        get {
            access(keyPath: \.isAvailable)
            return lock.withLock { availableValue }
        }
        set { withMutation(keyPath: \.isAvailable) { lock.withLock { availableValue = newValue } } }
    }

    /// How loud the microphone hears the speaker, from 0 (silence) to 1; 0 while stopped.
    public private(set) var level: Float {
        get {
            access(keyPath: \.level)
            return lock.withLock { levelValue }
        }
        set { withMutation(keyPath: \.level) { lock.withLock { levelValue = newValue } } }
    }

    /// Initializes a new instance of `SpeechRecognizer`.
    override public required convenience init() {
        self.init(locale: .current)
    }

    /// Initializes speech recognition for the specified locale.
    public convenience init(locale: Locale = .current) {
        self.init(recording: SystemSpeechRecognitionRecording(locale: locale), authorization: Self.systemAuthorization)
    }

    init(recording: any SpeechRecognitionRecording, authorization: @escaping @Sendable () async -> Bool) {
        self.recording = recording
        self.authorization = authorization
        self.availableValue = recording.isAvailable
        super.init()
        (recording as? SystemSpeechRecognitionRecording)?.recognizer?.delegate = self
    }

    private static func systemAuthorization() async -> Bool {
        let speech = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status)
            }
        }
        guard speech == .authorized else {
            return false
        }
        #if os(macOS)
        return true
        #else
        return await AVAudioApplication.requestRecordPermission()
        #endif
    }


    /// Asks for the permissions recognition needs, the first time; whether both were granted.
    ///
    /// ``start()`` asks on its own. Ask ahead of it to keep the prompts away from the moment of speaking.
    public func requestAuthorization() async -> Bool {
        await authorization()
    }

    /// Starts recognition after authorization, yielding its partial and final results.
    ///
    /// Calling ``stop()`` or cancelling the stream also cancels a start waiting for permission.
    public func start() -> AsyncThrowingStream<SFSpeechRecognitionResult, any Error> {
        AsyncThrowingStream { continuation in
            lock.withLock {
                guard session == nil else {
                    Self.logger.warning("Speech recognition is already starting or recording; stopping the existing session.")
                    stop()
                    continuation.finish()
                    return
                }
                let id = UUID()
                session = Session(id: id, continuation: continuation)
                continuation.onTermination = { [weak self] _ in
                    self?.finish(id: id)
                }
                session?.authorizationTask = Task { @MainActor [weak self] in
                    guard let self else {
                        continuation.finish()
                        return
                    }
                    let authorized = await requestAuthorization()
                    beginRecording(id: id, authorized: authorized)
                }
            }
        }
    }

    /// Stops the current recording or pending authorization and finishes its result stream.
    public func stop() {
        finish()
    }

    private func beginRecording(id: UUID, authorized: Bool) {
        lock.withLock {
            guard session?.id == id, !Task.isCancelled else {
                return
            }
            guard authorized else {
                finish(id: id, error: SpeechRecognizerError.notAuthorized)
                return
            }
            guard isAvailable else {
                finish(id: id)
                return
            }
            do {
                try recording.start { [weak self] result, error in
                    Task { @MainActor in
                        self?.receive(result, error: error, id: id)
                    }
                } level: { [weak self] level in
                    Task { @MainActor in
                        self?.updateLevel(level, id: id)
                    }
                }
                if session?.id == id {
                    isRecording = true
                }
            } catch {
                finish(id: id, error: error)
            }
        }
    }

    private func receive(_ result: SFSpeechRecognitionResult?, error: (any Error)?, id: UUID) {
        lock.withLock {
            guard let session, session.id == id else {
                return
            }
            if let result {
                session.continuation.yield(result)
            }
            if error != nil || result?.isFinal == true {
                finish(id: id, error: error)
            }
        }
    }

    private func updateLevel(_ level: Float, id: UUID) {
        lock.withLock {
            guard session?.id == id, isRecording else {
                return
            }
            self.level = level
        }
    }

    private func finish(id: UUID? = nil, error: (any Error)? = nil) {
        lock.withLock {
            guard let current = session, id == nil || current.id == id else {
                return
            }
            // Invalidate before cancelling either task: late callbacks belong to this session, never its successor.
            session = nil
            current.authorizationTask?.cancel()
            recording.stop()
            isRecording = false
            level = 0
            current.continuation.finish(throwing: error)
        }
    }


    @_documentation(visibility: internal)
    public func speechRecognizer(_ speechRecognizer: SFSpeechRecognizer, availabilityDidChange available: Bool) {
        lock.withLock {
            guard (recording as? SystemSpeechRecognitionRecording)?.recognizer == speechRecognizer else {
                return
            }
            isAvailable = available
            if !available {
                stop()
            }
        }
    }
}


/// Necessary `Sendable` conformance for Swift 6 language mode.
///
/// - Note: Wrapping the `SFSpeechRecognitionResult` in a custom `Sendable` struct is not desired as it would break API.
extension SFSpeechRecognitionResult: @retroactive @unchecked Sendable {}
