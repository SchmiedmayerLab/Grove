//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2022 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import GroveContact
import SwiftUI


struct ContactsTestsView: View {
    @MainActor static let leland = Contact(
        name: PersonNameComponents(
            givenName: "Leland",
            familyName: "Stanford"
        ),
        image: Image(systemName: "figure.wave.circle"), // swiftlint:disable:this accessibility_label_for_image
        title: "University Founder",
        description: """
                     Amasa Leland Stanford (March 9, 1824 – June 21, 1893) was an American industrialist and politician. [...] \
                     He and his wife Jane were also the founders of Stanford University, which they named after their late son.
                     [https://en.wikipedia.org/wiki/Leland_Stanford]
                     """,
        organization: "Stanford University",
        address: {
            let address = CNMutablePostalAddress()
            address.country = "USA"
            address.state = "CA"
            address.postalCode = "94305"
            address.city = "Stanford"
            address.street = "450 Serra Mall"
            return address
        }(),
        contactOptions: [
            .call("+1 (650) 723-2300"),
            .text("+1 (650) 723-2300"),
            .email(addresses: ["contact@stanford.edu"]),
            ContactOption(
                image: Image(systemName: "safari.fill"), // swiftlint:disable:this accessibility_label_for_image
                title: "Website",
                action: {
                    if let url = URL(string: "https://stanford.edu") {
                        UIApplication.shared.open(url)
                    }
                }
            )
        ]
    )

    @MainActor static let mock = Contact(
        name: PersonNameComponents(givenName: "Paul", familyName: "Schmiedmayer"),
        image: Image(systemName: "figure.wave.circle"), // swiftlint:disable:this accessibility_label_for_image
        title: "A Title",
        description: """
        This is a description of a contact that will be displayed. It might even be longer than what has to be displayed in the contact card.
        Why is this text so long, how much can you tell about one person?
        """,
        organization: "Stanford University",
        address: {
            let address = CNMutablePostalAddress()
            address.country = "USA"
            address.state = "CA"
            address.postalCode = "94305"
            address.city = "Stanford"
            address.street = "450 Serra Mall"
            return address
        }(),
        contactOptions: [
            .call("+1 (234) 567-891"),
            .call("+1 (234) 567-892"),
            .text("+1 (234) 567-893"),
            .email(addresses: ["lelandstanford@stanford.edu"], subject: "Hi Leland!"),
            // swiftlint:disable:next accessibility_label_for_image
            ContactOption(image: Image(systemName: "icloud.fill"), title: "Cloud", action: { })
        ]
    )


    /// The study team the documentation shows, in place of the fixtures the tests read.
    @MainActor static let studyTeam: [Contact] = [
        Contact(
            name: PersonNameComponents(givenName: "Leland", familyName: "Stanford"),
            image: Image(systemName: "figure.wave.circle"), // swiftlint:disable:this accessibility_label_for_image
            title: "Principal Investigator",
            description: "Leads the Heart Health Study and answers questions about what taking part involves.",
            organization: "Stanford University",
            address: stanford,
            contactOptions: [
                .call("+1 (650) 723-2300"),
                .email(addresses: ["lelandstanford@stanford.edu"], subject: "Heart Health Study"),
                .text("+1 (650) 723-2300")
            ]
        ),
        Contact(
            name: PersonNameComponents(givenName: "Jane", familyName: "Stanford"),
            image: Image(systemName: "person.crop.circle"), // swiftlint:disable:this accessibility_label_for_image
            title: "Study Coordinator",
            description: "First point of contact for scheduling, devices and anything that stops working.",
            organization: "Stanford University",
            address: stanford,
            contactOptions: [
                .call("+1 (650) 723-2300"),
                .text("+1 (650) 723-2300"),
                .email(addresses: ["janestanford@stanford.edu"], subject: "Heart Health Study")
            ]
        )
    ]

    private static var stanford: CNMutablePostalAddress {
        let address = CNMutablePostalAddress()
        address.country = "USA"
        address.state = "CA"
        address.postalCode = "94305"
        address.city = "Stanford"
        address.street = "450 Serra Mall"
        return address
    }

    private static var isDocumentation: Bool {
        ProcessInfo.processInfo.arguments.contains("--documentation")
    }

    var body: some View {
        ContactsList(contacts: Self.isDocumentation ? Self.studyTeam : [ContactsTestsView.mock, ContactsTestsView.leland])
            .navigationTitle(Self.isDocumentation ? "Study Team" : "Contacts")
            .background(Color(.systemGroupedBackground))
    }
}


#if DEBUG
struct ContactsTestsView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationStack {
            ContactsList(contacts: [ContactsTestsView.mock, ContactsTestsView.mock, ContactsTestsView.mock])
        }
    }
}
#endif
