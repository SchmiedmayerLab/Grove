//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import Foundation
import Speech


@available(iOS 18, macOS 15, watchOS 11, *)
final class SystemSpeechRecognitionRecording: SpeechRecognitionRecording, @unchecked Sendable {
    let recognizer: SFSpeechRecognizer?
    private let audioEngine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var hasTap = false

    var isAvailable: Bool { recognizer?.isAvailable == true }

    init(locale: Locale) {
        recognizer = SFSpeechRecognizer(locale: locale)
    }

    private static func level(of buffer: AVAudioPCMBuffer) -> Float {
        guard let channel = buffer.floatChannelData?[0], buffer.frameLength > 0 else {
            return 0
        }
        let frames = Int(buffer.frameLength)
        var sum: Float = 0
        for frame in 0..<frames {
            sum += channel[frame] * channel[frame]
        }
        let decibels = 20 * log10(max(sqrt(sum / Float(frames)), .leastNonzeroMagnitude))
        return min(max((decibels + 50) / 50, 0), 1)
    }

    func start(
        result: @escaping @Sendable (SFSpeechRecognitionResult?, (any Error)?) -> Void,
        level: @escaping @Sendable (Float) -> Void
    ) throws {
        guard let recognizer else {
            return
        }
        #if !os(macOS)
        let audioSession = AVAudioSession.sharedInstance()
        try audioSession.setCategory(.record, mode: .measurement, options: .duckOthers)
        try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
        #endif

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        self.request = request
        task = recognizer.recognitionTask(with: request, resultHandler: result)

        let inputNode = audioEngine.inputNode
        let format = inputNode.outputFormat(forBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
            // Capture this request, rather than reading mutable recognizer state from the audio thread.
            request.append(buffer)
            level(Self.level(of: buffer))
        }
        hasTap = true
        audioEngine.prepare()
        try audioEngine.start()
    }

    func stop() {
        audioEngine.stop()
        if hasTap {
            audioEngine.inputNode.removeTap(onBus: 0)
            hasTap = false
        }
        request?.endAudio()
        request = nil
        task?.cancel()
        task = nil
    }
}
