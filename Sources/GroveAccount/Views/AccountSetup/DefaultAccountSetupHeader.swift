//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2023 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import GroveViews
public import SwiftUI


/// A view which provides the default title and subtitle text.
///
/// This view expects a ``Account`` object to be in the environment to dynamically
/// present the appropriate subtitle.
@available(iOS 18, macOS 15, watchOS 11, *)
public struct DefaultAccountSetupHeader: View {
    @Environment(Account.self)
    private var account
    @Environment(\.accountSetupState)
    private var setupState

    public var body: some View {
        PageHeader(title: LocalizedStringResource("ACCOUNT_WELCOME", bundle: .atURL(from: .module)), subtitle: subtitle, image: image)
    }

    private var image: Image {
        // swiftlint:disable:next accessibility_label_for_image
        Image(systemName: isSignedIn ? "person.crop.circle.badge.checkmark" : "person.crop.circle")
    }

    private var isSignedIn: Bool {
        guard case .presentingExistingAccount = setupState else {
            return false
        }
        return account.signedIn
    }

    private var subtitle: LocalizedStringResource {
        if isSignedIn {
            LocalizedStringResource("ACCOUNT_WELCOME_SIGNED_IN_SUBTITLE", bundle: .atURL(from: .module))
        } else {
            LocalizedStringResource("ACCOUNT_WELCOME_SUBTITLE", bundle: .atURL(from: .module))
        }
    }

    public init() {}
}


#if DEBUG
@available(iOS 18, macOS 15, watchOS 11, *)
#Preview {
    DefaultAccountSetupHeader()
        .previewWith {
            AccountConfiguration(service: InMemoryAccountService())
        }
}

@available(iOS 18, macOS 15, watchOS 11, *)
#Preview {
    DefaultAccountSetupHeader()
        .previewWith {
            AccountConfiguration(service: InMemoryAccountService(), activeDetails: .createMock(userId: "myUser", name: nil))
        }
}
#endif
