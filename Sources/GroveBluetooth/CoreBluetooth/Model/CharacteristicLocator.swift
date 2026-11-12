//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2024 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//


@available(iOS 18, macOS 15, watchOS 11, *)
struct CharacteristicLocator {
    let serviceId: BTUUID
    let characteristicId: BTUUID
}


@available(iOS 18, macOS 15, watchOS 11, *)
extension CharacteristicLocator: Hashable, Sendable {}

@available(iOS 18, macOS 15, watchOS 11, *)
extension CharacteristicLocator: CustomStringConvertible, CustomDebugStringConvertible {
    public var description: String {
        "\(characteristicId)@\(serviceId)"
    }

    public var debugDescription: String {
        "CharacteristicLocator(service: \(serviceId), characteristic: \(characteristicId))"
    }
}
