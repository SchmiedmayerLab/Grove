//
// This source file is part of the Stanford Spezi open-source project
//
// SPDX-FileCopyrightText: 2022 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import Contacts
import SpeziPersonalInfo
import SpeziViews
import SwiftUI


/// Display contact information as defined by a `Contact`.
///
/// This view represents the content define in a ``Contact``.
@available(iOS 18, macOS 15, watchOS 11, *)
public struct ContactView: View {
    private let contact: Contact
    
    @Namespace private var namespace
    
    @State private var contactGridWidth: CGFloat = 300
    @State private var contentElementWidth: CGFloat = 100
    
    
    private var contactOptions: (grid: some RandomAccessCollection<ContactOption>, leftOverStack: some RandomAccessCollection<ContactOption>) {
        let columnCount = max(Int(contactGridWidth / max(contentElementWidth, 64)), 1)
        let (numberOfRows, leftOverElements) = contact.contactOptions.count.quotientAndRemainder(dividingBy: columnCount)
        return (contact.contactOptions.dropLast(leftOverElements), contact.contactOptions.dropFirst(columnCount * numberOfRows))
    }

    private var subtitleText: Text {
        var text = Text(verbatim: "")
        if let title = contact.title {
            text = text + Text(verbatim: title) // swiftlint:disable:this shorthand_operator
        }
        if contact.title != nil && contact.organization != nil {
            text = text + Text(verbatim: " - ") // swiftlint:disable:this shorthand_operator
        }
        if let organization = contact.organization {
            text = text + Text(verbatim: organization) // swiftlint:disable:this shorthand_operator
        }
        return text
    }

    private var subtitleAccessibilityLabel: Text {
        var text: Text?
        if let title = contact.title {
            text = Text(verbatim: title)
        }

        if let organization = contact.organization {
            if let titleText = text {
                text = titleText + Text(" at \(organization)", bundle: .module, comment: "Accessibility label: ' at <organization>'")
            } else {
                text = Text(verbatim: organization)
            }
        }

        return text ?? Text(verbatim: "")
    }

    public var body: some View {
        VStack {
            header
            Divider()
            if let description = contact.description {
                Label(verbatim: description, textStyle: .subheadline)
                    .padding(.vertical, 4)
            }
            HorizontalGeometryReader { _ in
                contactSection
            }
                .onPreferenceChange(WidthPreferenceKey.self) { gridWidth in
                    contactGridWidth = gridWidth
                }
            addressButton
        }
    }

    private var header: some View {
        HStack(spacing: 0) {
            UserProfileView(name: contact.name) {
                contact.image
            }
                .frame(height: 40)
                .accessibilityHidden(true)
            Spacer()
                .frame(width: 16)
            VStack(alignment: .leading, spacing: 2) {
                let name = contact.name.formatted(.name(style: .long))
                Text(verbatim: name)
                    .font(.title3.bold())
                    .accessibilityLabel(Text("Contact: \(name)", bundle: .module, comment: "Accessibility Label"))
                    .accessibilityAddTraits(.isHeader)

                if contact.title != nil || contact.organization != nil {
                    HStack(spacing: 0) {
                        subtitleText
                            .lineLimit(1...2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .foregroundColor(Color(.secondaryLabel))
                    .font(.subheadline)
                    .accessibilityRepresentation {
                        subtitleAccessibilityLabel
                    }
                }
            }
            Spacer()
        }
            .frame(height: 60)
    }
    
    private var contactSection: some View {
        VStack(spacing: 8) {
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 95))],
                alignment: .center,
                spacing: 8
            ) {
                ForEach(contactOptions.grid, id: \.id) { contactOption in
                    HorizontalGeometryReader { elementWidth in
                        contactButton(contactOption)
                            .onPreferenceChange(WidthPreferenceKey.self) { elementWidth in
                                contentElementWidth = elementWidth
                            }
                    }
                }
            }
            if !contactOptions.leftOverStack.isEmpty {
                HStack(spacing: 8) {
                    ForEach(contactOptions.leftOverStack, id: \.id) { contactOption in
                        contactButton(contactOption)
                    }
                }
            }
        }
    }
    
    @ViewBuilder private var addressButton: some View {
        if let address = contact.address {
            Button(action: openMaps) {
                ZStack {
                    background
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Address", bundle: .module, comment: "Contact Button Title")
                                .foregroundColor(.accentColor)
                            Text(verbatim: CNPostalAddressFormatter().string(from: address))
                                .multilineTextAlignment(.leading)
                                .foregroundColor(Color(.label))
                        }
                            .font(.caption)
                        Spacer()
                        Image(systemName: "location.fill")
                            .foregroundColor(.accentColor)
                            .accessibilityHidden(true)
                    }
                    .padding(ProcessInfo.processInfo.operatingSystemVersion.majorVersion >= 26 ? 0 : 15)
                    .padding([.horizontal], ProcessInfo.processInfo.operatingSystemVersion.majorVersion >= 26 ? 32 : 0)
                    .padding([.vertical], ProcessInfo.processInfo.operatingSystemVersion.majorVersion >= 26 ? 15 : 0)
                }
                    .fixedSize(horizontal: false, vertical: true)
                    .contentShape(Rectangle())
            }
                .accessibilityLabel(Text(
                    "Address: \(Text(verbatim: CNPostalAddressFormatter().string(from: address)))",
                    bundle: .module,
                    comment: "Accessibility Label"
                ))
        } else {
            EmptyView()
        }
    }
    
    @ViewBuilder private var background: some View {
        if #available(iOS 26.0, watchOS 26.0, tvOS 26.0, macOS 26.0, macCatalyst 26.0, *) {
            RoundedRectangle(cornerRadius: 10)
                .foregroundStyle(Color(uiColor: .clear))
                .glassEffect(.regular)
                .glassEffectUnion(id: "Button", namespace: namespace)
        } else {
            RoundedRectangle(cornerRadius: 10)
                .foregroundStyle(Color(uiColor: .tertiarySystemFill))
        }
    }
    
    
    /// Display contact information.
    /// - Parameter contact: The `Contact` that should be displayed.
    public init(contact: Contact) {
        self.contact = contact
    }
    
    
    private func contactButton(_ contactOption: ContactOption) -> some View {
        Button(action: contactOption.action) {
            ZStack {
                background
                VStack(spacing: 8) {
                    contactOption.image
                        .font(.title3)
                    Text(contactOption.title)
                        .font(.caption)
                }
                    .foregroundColor(.accentColor)
                    .padding(.vertical, 10)
            }
                .fixedSize(horizontal: false, vertical: true)
                .contentShape(Rectangle())
        }
    }
    
    private func openMaps() {
        guard let address = contact.address,
              let addressString = CNPostalAddressFormatter().string(from: address).addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "maps://?address=\(addressString)"),
              UIApplication.shared.canOpenURL(url) else {
            return
        }
        UIApplication.shared.open(url)
    }
}


#if DEBUG
@available(iOS 18, macOS 15, watchOS 11, *)
struct ContactView_Previews: PreviewProvider {
    static var mock: Contact {
        Contact(
            name: PersonNameComponents(givenName: "Paul", familyName: "Schmiedmayer"),
            image: Image(systemName: "figure.wave.circle"),
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
                ContactOption(image: Image(systemName: "icloud.fill"), title: "Cloud", action: { })
            ]
        )
    }

    static let leland = Contact(
        name: PersonNameComponents(
            givenName: "Leland",
            familyName: "Stanford"
        ),
        image: Image(systemName: "figure.wave.circle"),
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
                image: Image(systemName: "safari.fill"),
                title: "Website",
                action: {}
            )
        ]
    )


    static var previews: some View {
        ContactView(contact: Self.leland)
        ContactView(contact: Self.mock)
    }
}
#endif
