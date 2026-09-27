//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
// SPDX-License-Identifier: MIT
//

import Foundation
import GroveHealthKitBulkExport
import Testing

@Suite
struct CheckpointWriteFailureTests {
    @Test(arguments: [
        (NSCocoaErrorDomain, CocoaError.fileWriteOutOfSpace.rawValue, CheckpointWriteFailure.Category.insufficientSpace),
        (NSCocoaErrorDomain, CocoaError.fileWriteNoPermission.rawValue, .accessDenied),
        (NSCocoaErrorDomain, CocoaError.fileWriteInvalidFileName.rawValue, .invalidDestination),
        (NSPOSIXErrorDomain, Int(POSIXError.ENOSPC.rawValue), .insufficientSpace),
        (NSPOSIXErrorDomain, Int(POSIXError.EBUSY.rawValue), .temporarilyUnavailable),
        (NSPOSIXErrorDomain, Int(POSIXError.EACCES.rawValue), .accessDenied),
        (NSPOSIXErrorDomain, Int(POSIXError.ENOTDIR.rawValue), .invalidDestination),
        ("CustomStorage", CocoaError.fileWriteOutOfSpace.rawValue, .unknown),
        (NSCocoaErrorDomain, CocoaError.fileWriteUnknown.rawValue, .unknown)
    ])
    func classifiesKnownErrorsWithoutGuessing(domain: String, code: Int, category: CheckpointWriteFailure.Category) {
        let error = NSError(domain: domain, code: code, userInfo: [NSLocalizedDescriptionKey: "Write failed"])
        let failure = CheckpointWriteFailure(error)
        #expect(failure.category == category)
        #expect(failure.domain == domain)
        #expect(failure.code == code)
        #expect(failure.message == "Write failed")
        #expect(failure.errorDescription == "Write failed")
    }

    @Test
    func equalityPreservesDistinctDiagnostics() {
        let first = CheckpointWriteFailure(NSError(domain: "Storage", code: 1, userInfo: [NSLocalizedDescriptionKey: "First failure"]))
        let equal = CheckpointWriteFailure(NSError(domain: "Storage", code: 1, userInfo: [NSLocalizedDescriptionKey: "First failure"]))
        let second = CheckpointWriteFailure(NSError(domain: "Storage", code: 1, userInfo: [NSLocalizedDescriptionKey: "Second failure"]))
        let differentCode = CheckpointWriteFailure(NSError(domain: "Storage", code: 2, userInfo: [NSLocalizedDescriptionKey: "First failure"]))
        let differentDomain = CheckpointWriteFailure(NSError(domain: "Other", code: 1, userInfo: [NSLocalizedDescriptionKey: "First failure"]))
        #expect(first == equal)
        #expect(Set([first, equal, second, differentCode, differentDomain]).count == 4)
        #expect(BulkExportPauseReason.failure(.checkpointWriteFailed(first)) != .failure(.checkpointWriteFailed(second)))
    }
}
