//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2024 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import GroveViews
import SwiftUI


extension ImageReference {
#if canImport(UIKit)
    func uiImageScaledForAccessorySetupKit() -> UIImage {
        let image: UIImage
        let isSymbol: Bool

        if let uiImage {
            image = uiImage
            isSymbol = isSystemImage
        } else {
            guard let sensor = UIImage(systemName: "sensor") else {
                preconditionFailure("UIImage with systemName 'sensor' is not available.")
            }
            isSymbol = true
            image = sensor
        }

        if isSymbol {
            guard let configuredImage = image
                .applyingSymbolConfiguration(.init(font: .systemFont(ofSize: 256), scale: .large))?
                .withTintColor(UIColor.tintColor, renderingMode: .alwaysTemplate) else {
                preconditionFailure("Failed to apply symbol configuration to UIImage: \(image).")
            }

            return configuredImage
        } else {
            return image
        }
    }
#endif
}
