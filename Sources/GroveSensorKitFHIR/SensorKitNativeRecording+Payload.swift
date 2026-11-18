//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import Foundation
import GroveFHIRContract


extension SensorKitNativeRecording.Payload {
    var byteCount: Int {
        switch self {
        case .inline(let data), .sidecar(_, let data): data.count
        case .file(_, let file): file.byteCount
        }
    }

    var attachmentSHA1: Data {
        switch self {
        case .inline(let data), .sidecar(_, let data): data.attachmentSHA1
        case .file(_, let file): file.attachmentSHA1
        }
    }

    var sidecarPath: String? {
        switch self {
        case .inline: nil
        case .sidecar(let path, _), .file(let path, _): path
        }
    }
}
