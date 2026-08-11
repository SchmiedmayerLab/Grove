//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2022 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import Foundation
@testable import GroveAccessGuard
import GroveTesting
import Observation
import SwiftUI
import Testing

#if os(iOS)
@Test("AccessGuards observes scene lifecycle notifications")
@MainActor
@available(iOS 17, *)
func accessGuardsObservesSceneLifecycleNotifications() async {
    let accessGuards = AccessGuards {
        TestLifecycleAccessGuard()
    }
    // Resolve through Grove rather than calling `configure()` on a bare instance: the module reads its
    // `@Dependency(KeychainStorage.self)` during configuration, which traps if nothing injected it.
    withDependencyResolution {
        accessGuards
    }
    let model = accessGuards.model(for: AccessGuardIdentifier<TestLifecycleAccessGuard>.notificationLifecycleTest)

    let beforeBackground = Date()
    NotificationCenter.default.post(name: UIScene.didEnterBackgroundNotification, object: nil)
    await Task.yield()

    #expect(model.didEnterBackgroundCount == 1)
    #expect(accessGuards.lastEnteredBackground >= beforeBackground)

    NotificationCenter.default.post(name: UIScene.willEnterForegroundNotification, object: nil)
    await Task.yield()

    #expect(model.willEnterForegroundCount == 1)
    #expect(model.lastEnteredBackground == accessGuards.lastEnteredBackground)
}


@available(iOS 17, *)
private struct TestLifecycleAccessGuard: _AccessGuardConfig {
    let id: AccessGuardIdentifier<Self> = .notificationLifecycleTest
    let timeout: Duration = .seconds(1)

    // swiftlint:disable:next identifier_name
    func _makeUnlockView(model: TestLifecycleAccessGuardModel) -> EmptyView {
        EmptyView()
    }
}


@available(iOS 17, *)
@Observable
@MainActor
private final class TestLifecycleAccessGuardModel: _AnyAccessGuardModel {
    typealias UnlockInput = Void
    typealias UnlockResult = Void

    let config: TestLifecycleAccessGuard
    private(set) var isLocked = false
    private(set) var didEnterBackgroundCount = 0
    private(set) var willEnterForegroundCount = 0
    private(set) var lastEnteredBackground: Date?

    init(config: TestLifecycleAccessGuard, context: AccessGuards) {
        self.config = config
    }

    func lock() {
        isLocked = true
    }

    func unlock(_ input: Void) async throws {
        isLocked = false
    }

    func didEnterBackground() {
        didEnterBackgroundCount += 1
    }

    func willEnterForeground(lastEnteredBackground: Date) {
        willEnterForegroundCount += 1
        self.lastEnteredBackground = lastEnteredBackground
    }
}


@available(iOS 17, *)
extension AccessGuardIdentifier where AccessGuard == TestLifecycleAccessGuard {
    fileprivate static let notificationLifecycleTest = Self(value: "edu.stanford.spezi.accessGuard.lifecycleTest")
}
#endif
