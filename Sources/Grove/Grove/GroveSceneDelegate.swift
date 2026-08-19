//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2023 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

#if canImport(SwiftUI)
import SwiftUI


#if os(iOS) || os(visionOS) || os(tvOS)
@available(iOS 18, macOS 15, watchOS 11, *)
class GroveSceneDelegate: NSObject, UISceneDelegate {
    @available(*, deprecated, message: "Propagate deprecation warning.")
    func sceneWillEnterForeground(_ scene: UIScene) {
        guard let delegate = GroveAppDelegate.appDelegate else {
            return
        }
        delegate.grove.lifecycleHandler.sceneWillEnterForeground(scene)
    }
    
    @available(*, deprecated, message: "Propagate deprecation warning.")
    func sceneDidBecomeActive(_ scene: UIScene) {
        guard let delegate = GroveAppDelegate.appDelegate else {
            return
        }
        delegate.grove.lifecycleHandler.sceneDidBecomeActive(scene)
    }
    
    @available(*, deprecated, message: "Propagate deprecation warning.")
    func sceneWillResignActive(_ scene: UIScene) {
        guard let delegate = GroveAppDelegate.appDelegate else {
            return
        }
        delegate.grove.lifecycleHandler.sceneWillResignActive(scene)
    }
    
    @available(*, deprecated, message: "Propagate deprecation warning.")
    func sceneDidEnterBackground(_ scene: UIScene) {
        guard let delegate = GroveAppDelegate.appDelegate else {
            return
        }
        delegate.grove.lifecycleHandler.sceneDidEnterBackground(scene)
    }
}
#endif
#endif
