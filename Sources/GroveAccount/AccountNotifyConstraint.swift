//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2023 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

public import Grove


/// A `Grove` Standard that allows to react to certain Account-based events.
///
/// Adopt this protocol in your Standard to respond to `Account` events.
///
/// ```swift
/// import Grove
/// import GroveAccount
///
/// actor MyStandard: Standard, AccountNotifyConstraint {
///     init() {}
///
///     func handleAccountEvent(_ event: AccountNotifications.Event) async {
///         switch event {
///         case .willLogOut(let details):
///             // handle deletion of associated user data
///         default:
///             break
///         }
///     }
/// }
/// ```
@available(iOS 18, macOS 15, watchOS 11, *)
public protocol AccountNotifyConstraint: Standard {
    /// Notifies the Standard that an event for the currently associated user occurred.
    ///
    /// For more information refer to ``AccountNotifications/Event``.
    func handleAccountEvent(_ event: AccountNotifications.Event) async
}
