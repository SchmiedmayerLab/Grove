//
// This source file is part of the Stanford Spezi open-source project
//
// SPDX-FileCopyrightText: 2025 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import Foundation
import Testing


func expectEqualIgnoringOrder<T>(
    _ lhs: Set<T>,
    _ rhs: Set<T>,
    sourceLocation: SourceLocation = #_sourceLocation
) {
    guard lhs != rhs else {
        return
    }
    let lhsOnly = lhs.subtracting(rhs)
    let rhsOnly = rhs.subtracting(lhs)
    var comment = "#lhs=\(lhs.count); #rhs=\(rhs.count)"
    comment.append("\nlhs contains \(lhsOnly.count) item(s) that are missing in rhs:")
    for item in lhsOnly {
        comment.append("\n- \(item)")
    }
    comment.append("\nrhs contains \(rhsOnly.count) item(s) that are missing in lhs:")
    for item in rhsOnly {
        comment.append("\n- \(item)")
    }
    Issue.record("\(comment)", sourceLocation: sourceLocation)
}
