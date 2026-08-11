//
// This source file is part of the Stanford Spezi open-source project
//
// SPDX-FileCopyrightText: 2025 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

public import XCTest


extension XCUIElement {
    /// Determines the current selection value of a toggle or switch element.
    public var toggleState: Bool? { // swiftlint:disable:this discouraged_optional_boolean
        guard [XCUIElement.ElementType.switch, .toggle].contains(elementType) else {
            return nil
        }
        return switch value as? String {
        case "0": false
        case "1": true
        default: nil
        }
    }
    
    
    /// Toggles a toggle or switch element between "off" and "on".
    public func flipToggle() throws {
        // visionOS uses a different UI structure / hierarchy in its accessibility tree, as compared to iOS.
        // whereas on iOS, a UISwitch / SwiftUI Toggle is represented as a `switch` element with another nested `switch`
        // (which then is the one we need to operate on), visionOS instead has a single `switch` element, which then
        // contains a bunch of nested `other` elements, but for some reason simply swiping left/right on the `switch` itself
        // is sufficient to toggle it (despite the fact that, eg in a Form, it'll span the entire width of the row...)
        #if os(visionOS)
        let element = self
        #else
        let element = self.descendants(matching: .switch).element
        #endif
        
        XCTAssert(element.exists)
        
        #if os(visionOS)
        switch element.toggleState {
        case .none:
            throw NSError(domain: "edu.stanford.XCTestExtensions", code: 0, userInfo: [
                NSLocalizedDescriptionKey: "Unable to determine current value: '\(String(describing: value))'"
            ])
        case .some(true):
            element.swipeLeft()
        case .some(false):
            element.swipeRight()
        }
        #else
        element.coordinate(withNormalizedOffset: .init(dx: 0.5, dy: 0.5)).tap()
        #endif
    }
    
    
    /// Updates a toggle or switch element to the specified value.
    public func setToggleState(isOn newState: Bool) throws {
        guard let toggleState else {
            throw NSError(domain: "edu.stanford.XCTestExtensions", code: 0, userInfo: [
                NSLocalizedDescriptionKey: "Unable to determine current value: '\(String(describing: value))'"
            ])
        }
        if toggleState != newState {
            try flipToggle()
        }
    }
}
