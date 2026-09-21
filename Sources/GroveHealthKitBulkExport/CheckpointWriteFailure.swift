//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
// SPDX-License-Identifier: MIT
//

public import Foundation

/// A checkpoint-write failure with diagnostics and a recovery category.
public struct CheckpointWriteFailure: Error, Hashable, Sendable, LocalizedError {
    public enum Category: Hashable, Sendable {
        /// Free storage before retrying.
        case insufficientSpace
        /// Retry after storage becomes available; do not retry continuously.
        case temporarilyUnavailable
        /// Check permissions and protected-data availability before retrying.
        case accessDenied
        /// Correct the storage location before retrying.
        case invalidDestination
        /// Inspect the diagnostics before retrying.
        case unknown
    }

    public let category: Category
    public let domain: String
    public let code: Int
    public let message: String

    public var errorDescription: String? { message }

    /// Captures the error domain, code and message.
    public init(_ error: any Error) {
        let error = error as NSError
        domain = error.domain
        code = error.code
        message = error.localizedDescription
        category = Self.category(for: error)
    }

    private static func category(for error: NSError) -> Category {
        switch error.domain {
        case NSCocoaErrorDomain: category(for: CocoaError.Code(rawValue: error.code))
        case NSPOSIXErrorDomain: category(for: Int32(exactly: error.code).flatMap(POSIXError.Code.init(rawValue:)))
        default: .unknown
        }
    }

    private static func category(for code: CocoaError.Code) -> Category {
        switch code {
        case .fileWriteOutOfSpace: .insufficientSpace
        case .fileWriteNoPermission, .fileWriteVolumeReadOnly: .accessDenied
        case .fileNoSuchFile, .fileWriteInvalidFileName: .invalidDestination
        default: .unknown
        }
    }

    private static func category(for code: POSIXError.Code?) -> Category {
        switch code {
        case .ENOSPC, .EDQUOT: .insufficientSpace
        case .EAGAIN, .EBUSY: .temporarilyUnavailable
        case .EACCES, .EPERM, .EROFS: .accessDenied
        case .ENOENT, .ENOTDIR, .EISDIR, .ENAMETOOLONG: .invalidDestination
        default: .unknown
        }
    }
}
