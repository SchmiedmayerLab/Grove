//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import Foundation
import Speech


/// Audio resources accessed only while the recognizer holds its lifecycle lock.
@available(iOS 18, macOS 15, watchOS 11, *)
protocol SpeechRecognitionRecording: Sendable {
    var isAvailable: Bool { get }
    func start(
        result: @escaping @Sendable (SFSpeechRecognitionResult?, (any Error)?) -> Void,
        level: @escaping @Sendable (Float) -> Void
    ) throws
    func stop()
}
