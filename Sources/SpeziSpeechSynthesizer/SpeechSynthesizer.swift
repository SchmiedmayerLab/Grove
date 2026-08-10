//
// This source file is part of the Stanford Spezi open-source project
//
// SPDX-FileCopyrightText: 2023 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

public import AVFoundation
public import Observation
public import Spezi


/// Produces synthesized speech from text utterances.
///
/// The Spezi `SpeechSynthesizer` encapsulates the functionality of Apple's `AVFoundation` framework, more specifically, the `AVSpeechSynthesizer`.
/// It provides methods to start and stop voice synthesizing and publishes the state of the process.
///
/// > Important: If your application is not yet configured to use Spezi, follow the [Spezi setup article](../Spezi/Spezi.docc/Initial%20Setup.md) to set up the core Spezi infrastructure.
///
/// The module needs to be registered in a Spezi-based application using the [`configuration`](../Spezi/Spezi.docc/Spezi.md)
/// in a [`SpeziAppDelegate`](../Spezi/Spezi.docc/Spezi.md):
/// ```swift
/// class ExampleAppDelegate: SpeziAppDelegate {
///     override var configuration: Configuration {
///         Configuration {
///             SpeechSynthesizer()
///             // ...
///         }
///     }
/// }
/// ```
/// > Tip: You can learn more about a [`Module` in the Spezi documentation](../Spezi/Spezi.docc/Module/Module.md).
///
/// ## Usage
///
/// ```swift
/// struct SpeechSynthesizerView: View {
///     // Get the `SpeechSynthesizer` from the SwiftUI `Environment`.
///     @Environment(SpeechSynthesizer.self) private var speechSynthesizer
///     // A textual message that will be synthesized to natural language speech.
///     private let message = "Hello, this is the SpeziSpeech framework!"
///
///     var body: some View {
///         Button("Playback") {
///             playbackButtonPressed()
///         }
///     }
///
///     private func playbackButtonPressed() {
///         if speechSynthesizer.isSpeaking {
///             speechSynthesizer.pause()
///         } else {
///             speechSynthesizer.speak(message)
///         }
///     }
/// }
/// ```
@available(iOS 18, macOS 15, watchOS 11, *)
@Observable
public final class SpeechSynthesizer: NSObject, Module, DefaultInitializable, EnvironmentAccessible,
                                      AVSpeechSynthesizerDelegate, @unchecked Sendable {
    /// The wrapped  `AVSpeechSynthesizer` instance.
    private let avSpeechSynthesizer = AVSpeechSynthesizer()


    /// A Boolean value that indicates whether the speech synthesizer is speaking or is in a paused state and has utterances to speak.
    public private(set) var isSpeaking = false
    /// A Boolean value that indicates whether a speech synthesizer is in a paused state.
    public private(set) var isPaused = false
    /// An Array of voices in the user's current locale.
    public var voices: [AVSpeechSynthesisVoice] {
        AVSpeechSynthesisVoice.speechVoices().filter {
            $0.language == AVSpeechSynthesisVoice.currentLanguageCode()
        }
    }

    override public required init() {
        super.init()
        avSpeechSynthesizer.delegate = self
    }


    /// Adds the text to the speech synthesizer’s queue.
    /// - Parameters:
    ///   - text: A string that contains the text to speak.
    ///   - language: Optional BCP 47 code that identifies the language and locale for a voice.
    public func speak(_ text: String, language: String? = nil) {
        let utterance = AVSpeechUtterance(string: text)

        if let language {
            utterance.voice = AVSpeechSynthesisVoice(language: language)
        }

        speak(utterance)
    }

    /// Adds the text to the speech synthesizer's queue.
    /// - Parameters:
    ///   - text: A string that contains the text to speak.
    ///   - voice: The `AVSpeechSynthesisVoice` to use.
    public func speak(_ text: String, voice: AVSpeechSynthesisVoice) {
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = voice
        speak(utterance)
    }

    /// Adds the utterance to the speech synthesizer’s queue.
    /// - Parameter utterance: An `AVSpeechUtterance` instance that contains text to speak.
    public func speak(_ utterance: AVSpeechUtterance) {
        avSpeechSynthesizer.speak(utterance)
    }

    /// Pauses the current output speech from the speech synthesizer.
    /// - Parameters:
    ///   - pauseMethod: Defines when the output should be stopped via the `AVSpeechBoundary`.
    public func pause(at pauseMethod: AVSpeechBoundary = .immediate) {
        if isSpeaking {
            avSpeechSynthesizer.pauseSpeaking(at: pauseMethod)
        }
    }

    /// Resumes the output of the speech synthesizer.
    public func continueSpeaking() {
        if isPaused {
            avSpeechSynthesizer.continueSpeaking()
        }
    }

    /// Stops the output by the speech synthesizer and cancels all unspoken utterances from the synthesizer’s queue.
    /// It is not possible to resume a stopped utterance.
    /// - Parameters:
    ///   - stopMethod: Defines when the output should be stopped via the `AVSpeechBoundary`.
    public func stop(at stopMethod: AVSpeechBoundary = .immediate) {
        if isSpeaking || isPaused {
            avSpeechSynthesizer.stopSpeaking(at: stopMethod)
        }
    }

    /// Requests permission for and fetches any personal voices the user may have created on the device.
    /// - Returns: An Array of personal voices
    public func getPersonalVoices() async -> [AVSpeechSynthesisVoice] {
        await withCheckedContinuation { continuation in
            AVSpeechSynthesizer.requestPersonalVoiceAuthorization { status in
                switch status {
                case .authorized:
                    let personalVoices = AVSpeechSynthesisVoice.speechVoices().filter {
                        $0.voiceTraits == .isPersonalVoice
                    }
                    continuation.resume(returning: personalVoices)
                default:
                    continuation.resume(returning: [])
                }
            }
        }
    }


    // MARK: - AVSpeechSynthesizerDelegate
    @_documentation(visibility: internal)
    public func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didStart utterance: AVSpeechUtterance) {
        isSpeaking = true
        isPaused = false
    }

    @_documentation(visibility: internal)
    public func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didPause utterance: AVSpeechUtterance) {
        isSpeaking = false
        isPaused = true
    }

    @_documentation(visibility: internal)
    public func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didContinue utterance: AVSpeechUtterance) {
        isSpeaking = true
        isPaused = false
    }

    @_documentation(visibility: internal)
    public func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        isSpeaking = false
        isPaused = false
    }

    @_documentation(visibility: internal)
    public func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        isSpeaking = false
        isPaused = false
    }
}
