//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2022 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import Foundation


@available(iOS 18, macOS 15, watchOS 11, *)
enum AccessGuardError: LocalizedError {
    case storeCodeError
    case biometricsNotAvailable
    
    var errorDescription: String? {
        String(localized: "ACCESS_GUARD_ERROR_TITLE", bundle: .module)
    }
    
    var failureReason: String? {
        switch self {
        case .storeCodeError:
            return String(localized: "ACCESS_GUARD_ERROR_STORE_CODE_ERROR_REASON", bundle: .module)
        case .biometricsNotAvailable:
            return String(localized: "ACCESS_GUARD_ERROR_BIOMETRICS_NOT_AVAILABLE", bundle: .module)
        }
    }
}
