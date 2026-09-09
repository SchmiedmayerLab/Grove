//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2023 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import GrovePersonalInfo
import GroveViews
import SwiftUI


/// A simple account summary displayed in the `AccountSetup` view when there is already a signed in user account.
@available(iOS 18, macOS 15, watchOS 11, *)
struct AccountSummaryBox: View {
    private let model: AccountDisplayModel

    var body: some View {
        HStack(spacing: 16) {
            profileImage
                .frame(width: 48, height: 48)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(headline)
                    .font(.headline)
                if let subheadline = model.accountSubheadline {
                    Text(subheadline)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
        }
        .accountCardRow()
        .accountCard()
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder private var profileImage: some View {
        if let profileViewName = model.profileViewName {
            UserProfileView(name: profileViewName)
        } else {
            Image(systemName: "person.crop.circle.fill") // swiftlint:disable:this accessibility_label_for_image
                .resizable()
                .aspectRatio(contentMode: .fit)
                .foregroundStyle(.tertiary)
        }
    }

    private var headline: String {
        model.accountHeadline ?? String(localized: "Anonymous User", bundle: .module)
    }

    /// Create a new `AccountSummaryBox`
    /// - Parameter details: The ``AccountDetails`` to render.
    init(details: AccountDetails) {
        self.model = AccountDisplayModel(details: details)
    }
}


#if DEBUG
@available(iOS 18, macOS 15, watchOS 11, *)
#Preview {
    AccountSummaryBox(details: .createMock())
        .padding(.horizontal, ViewSizing.innerHorizontalPadding)
}

@available(iOS 18, macOS 15, watchOS 11, *)
#Preview {
    AccountSummaryBox(details: .createMock(userId: "leland.stanford"))
        .padding(.horizontal, ViewSizing.innerHorizontalPadding)
}

@available(iOS 18, macOS 15, watchOS 11, *)
#Preview {
    AccountSummaryBox(details: .createMock(userId: "leland.stanford", name: nil))
        .padding(.horizontal, ViewSizing.innerHorizontalPadding)
}
#endif
