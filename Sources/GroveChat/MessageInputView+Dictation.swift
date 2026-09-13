//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//
import SwiftUI


@available(iOS 26, macOS 26, visionOS 26, *)
extension MessageInputView {
    /// What the composer becomes while it listens: a way out on the left, the voice as it is heard with the time
    /// it has taken in the middle, and the stop that keeps what was said on the right.
    ///
    /// The field itself steps aside for the duration; what is said is added to what was written once the
    /// recording stops, so a message can be typed and spoken by turns.
    var dictationRow: some View {
        HStack(alignment: .center, spacing: 8) {
            closeButton(Text("CANCEL_DICTATION", bundle: .module), cancelDictation)
            recordingPill
            Button(action: speechRecognizer.stop) {
                Image(systemName: "stop.fill")
                    .font(.system(size: 14, weight: .bold))
                    .accessibilityLabel(Text("STOP_DICTATION", bundle: .module))
                    .foregroundStyle(.white)
                    .frame(width: Self.controlSize, height: Self.controlSize)
                    .background(.red, in: .circle)
            }
            .buttonStyle(.plain)
        }
    }

    private var recordingPill: some View {
        HStack(spacing: 12) {
            DictationWaveform(levels: dictationLevels)
                .frame(maxWidth: .infinity)
                .frame(height: 20)
            if let dictationStart {
                TimelineView(.periodic(from: dictationStart, by: 1)) { timeline in
                    Text(Duration.seconds(max(0, timeline.date.timeIntervalSince(dictationStart))), format: .time(pattern: .minuteSecond))
                        .font(.body.monospacedDigit())
                        .foregroundStyle(.red)
                }
            }
        }
        .padding(.horizontal, 16)
        // A little taller than the field it stands in for, the way a recording pill is.
        .frame(height: Self.controlSize + 8)
        .glassEffect(.regular, in: .capsule)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text("RECORDING", bundle: .module))
        .accessibilityIdentifier("Recording")
    }

    func toggleDictation() {
        guard !speechRecognizer.isRecording else {
            speechRecognizer.stop()
            return
        }
        let written = message.trimmingCharacters(in: .whitespacesAndNewlines)
        dictationBase = written
        dictationLevels = []
        dictationStart = .now
        Task {
            // A failed or interrupted recognition simply ends dictation; the typed message is left untouched.
            do {
                for try await result in speechRecognizer.start() {
                    message = [written, result.bestTranscription.formattedString].filter { !$0.isEmpty }.joined(separator: " ")
                }
            } catch {
                speechRecognizer.stop()
            }
        }
    }

    /// Ends the recording and drops what it heard, leaving the message as it was written.
    private func cancelDictation() {
        speechRecognizer.stop()
        message = dictationBase
    }

    /// The plus of the attach button turned into a cross, in its place and on its glass.
    func closeButton(_ label: Text, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: "xmark")
                .font(.system(size: 17, weight: .medium))
                .accessibilityLabel(label)
                .foregroundStyle(.secondary)
                .frame(width: Self.controlSize, height: Self.controlSize)
                .contentTransition(.symbolEffect(.replace))
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.interactive(), in: .circle)
    }
}
