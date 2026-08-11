//
// This source file is part of the Stanford Spezi open-source project
//
// SPDX-FileCopyrightText: 2023 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

public import Foundation


@inlinable
package func neverReturn() -> Never {
    // This is unfortunate but as far as I can see the only feasible way to return Never without calling a runtime crashing function, e.g. `fatalError()`.
    repeat {
        RunLoop.current.run()
    } while true
}
