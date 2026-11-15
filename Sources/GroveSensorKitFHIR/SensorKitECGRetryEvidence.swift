//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

#if os(iOS)
import Foundation
import GroveSensorKit


@available(iOS 17.4, *)
extension SensorKitECGSession {
    /// Exact fixed-width facts absent from the established native JSON, in the client retry framing order.
    var groveRetryEvidenceSupplement: Data {
        var supplement = Data()
        for word in [
            startDate.timeIntervalSince1970.bitPattern,
            frequency.converted(to: .hertz).value.bitPattern,
            UInt64(bitPattern: Int64(lead.rawValue)),
            UInt64(bitPattern: Int64(guidance.rawValue))
        ] {
            withUnsafeBytes(of: word.bigEndian) { supplement.append(contentsOf: $0) }
        }
        return supplement
    }
}
#endif
