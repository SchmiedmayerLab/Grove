//
// This source file is part of the Stanford Spezi open-source project
//
// SPDX-FileCopyrightText: 2022 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import Foundation
import SpeziFoundation
import SpeziScheduler


struct NonTrivialTaskContext: Hashable, Codable {
    // give it a bunch of fields to maximise the likelihood of something being out of order
    let field0: Int
    let field1: Int
    let field2: Int
    let field3: Int
    let field4: Int
    let field5: Int
    let field6: Int
    let field7: Int
    let field8: Int
    let field9: Int
}


@available(iOS 18, macOS 15, watchOS 11, visionOS 2, *)
extension Outcome {
    @Property var example: String?
}


@available(iOS 18, macOS 15, watchOS 11, visionOS 2, *)
extension Task.Context {
    @Property var example: String?
}


@available(iOS 18, macOS 15, watchOS 11, visionOS 2, *)
extension Task.Context {
    @Property var example2: String = "Hello World"
}

@available(iOS 18, macOS 15, watchOS 11, visionOS 2, *)
extension Task.Context {
    @Property(coding: .json)
    var nonTrivialExample: NonTrivialTaskContext?
}
