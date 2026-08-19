//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2024 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

public import ByteCoding
public import NIO


/// A data record of a EDF/BDF file.
public struct DataRecord<S: Sample> {
    /// The list of channels.
    public let channels: [Channel<S>]


    /// Create a new data record.
    /// - Parameter channels: The list of channels.
    public init(channels: [Channel<S>]) {
        self.channels = channels
    }
}


extension DataRecord: Hashable, Sendable {}

extension DataRecord: ByteEncodable {
    public func encode(to byteBuffer: inout ByteBuffer) {
        for channel in channels {
            channel.encode(to: &byteBuffer)
        }
    }
}
