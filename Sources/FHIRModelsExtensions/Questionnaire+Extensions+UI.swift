//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2022 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

#if canImport(UIKit) && (os(iOS) || os(visionOS) || os(tvOS))

public import ModelsR4
#if os(iOS) || os(visionOS)
public import enum UIKit.UIKeyboardType
#endif
public import enum UIKit.UITextAutocapitalizationType
public import struct UIKit.UITextContentType


extension QuestionnaireItem {
#if os(iOS) || os(visionOS)
    /// The item's preferred keyboard type.
    public var keyboardType: UIKeyboardType? {
        switch keyboardTypeRawValue {
        case nil:
            nil
        case "default":
            .default
        case "asciiCapable":
            .asciiCapable
        case "numbersAndPunctuation":
            .numbersAndPunctuation
        case "URL":
            .URL
        case "url":
            .URL
        case "numberPad":
            .numberPad
        case "phonePad":
            .phonePad
        case "phone":
            .phonePad
        case "namePhonePad":
            .namePhonePad
        case "emailAddress":
            .emailAddress
        case "email":
            .emailAddress
        case "decimalPad":
            .decimalPad
        case "number":
            .decimalPad
        case "twitter":
            .twitter
        case "webSearch":
            .webSearch
        case "asciiCapableNumberPad":
            .asciiCapableNumberPad
        default:
            nil
        }
    }
#endif
    
    
#if os(iOS) || os(visionOS) || os(tvOS)
    /// The item's preferred autocapitalization behaviour.
    public var autocapitalizationType: UITextAutocapitalizationType? {
        switch autocapitalizeRawValue {
        case "none":
            UITextAutocapitalizationType.none
        case "sentences":
            .sentences
        case "words":
            .words
        // `allCharacters` is the retired iOS spelling of WHATWG's `characters`.
        case "characters", "allCharacters":
            .allCharacters
        default:
            nil
        }
    }

    /// The item's preferred text content type.
    ///
    /// Authored as WHATWG `autocomplete` detail tokens, which map onto
    /// `UITextContentType` here and onto Android autofill hints elsewhere.
    public var textContentType: UITextContentType? {
        switch autocompleteRawValue {
        case "name":
            return .name
        case "given-name":
            return .givenName
        case "additional-name":
            return .middleName
        case "family-name":
            return .familyName
        case "honorific-prefix":
            return .namePrefix
        case "honorific-suffix":
            return .nameSuffix
        case "nickname":
            return .nickname
        case "username":
            return .username
        case "new-password":
            return .newPassword
        case "current-password":
            return .password
        case "one-time-code":
            return .oneTimeCode
        case "organization-title":
            return .jobTitle
        case "organization":
            return .organizationName
        case "street-address":
            return .fullStreetAddress
        case "address-line1":
            return .streetAddressLine1
        case "address-line2":
            return .streetAddressLine2
        case "address-level1":
            return .addressState
        case "address-level2":
            return .addressCity
        // iOS models only the country name, so the code token resolves to it too.
        case "country", "country-name":
            return .countryName
        case "postal-code":
            return .postalCode
        case "tel":
            return .telephoneNumber
        case "email":
            return .emailAddress
        case "url":
            return .URL
        case "bday":
            if #available(iOS 17, visionOS 1, tvOS 17, *) {
                return .birthdate
            }
            return nil
        // `sex` and `photo` have no UIKit counterpart.
        default:
            return nil
        }
    }
#endif
}

#endif
