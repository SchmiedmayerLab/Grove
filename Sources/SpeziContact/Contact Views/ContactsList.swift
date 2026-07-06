//
// This source file is part of the Stanford Spezi open-source project
//
// SPDX-FileCopyrightText: 2022 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import SwiftUI


/// Display different `Contact`s in a card-like style in a scroll view.
///
/// You pass multiple ``Contact``s to the `ContactsList` to populate its content:
/// ```swift
/// ContactsList(contacts: [/* ... */])
///     .navigationTitle("Contacts")
///     .background(Color(.systemGroupedBackground))
/// ```
@available(iOS 16, *)
public struct ContactsList: View {
    private let contacts: [Contact]
    
    
    public var body: some View {
        List {
            ForEach(contacts, id: \.id) { contact in
                Section {
                    ContactView(contact: contact)
                        .buttonStyle(.plain) // ensure the whole list row doesn't render as a button
                }
            }
        }
    }
    
    
    /// Create a view displaying a list of  multiple `Contact`s.
    /// - Parameter contacts: The `Contact` instances to populate the list.
    public init(contacts: [Contact]) {
        self.contacts = contacts
    }
}


#if DEBUG
@available(iOS 16, *)
struct ContactsList_Previews: PreviewProvider {
    static var previews: some View {
        NavigationStack {
            ContactsList(
                contacts: [
                    ContactView_Previews.leland,
                    ContactView_Previews.mock
                ]
            )
                .navigationTitle(Text(verbatim: "Contacts"))
                .background(Color(.systemGroupedBackground))
        }
    }
}
#endif
