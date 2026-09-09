//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

#if os(iOS) || os(visionOS)
@testable import GroveChat
import SwiftUI
import Testing
import UIKit


@Suite("ZoomableImageView")
@MainActor
struct ZoomableImageViewTests {
    @Test("Opens fitted to its bounds and can zoom in from there")
    func opensFitted() throws {
        let image = UIGraphicsImageRenderer(size: CGSize(width: 1000, height: 500)).image { _ in }
        let controller = UIHostingController(rootView: ZoomableImageView(image: image))
        // SwiftUI only makes the representable's view once the hierarchy sits in a window.
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 300, height: 300))
        window.rootViewController = controller
        window.makeKeyAndVisible()
        controller.view.layoutIfNeeded()

        let scrollView = try #require(controller.view.firstSubview(of: UIScrollView.self))
        #expect(abs(scrollView.zoomScale - 0.3) < 0.001)
        #expect(abs(scrollView.minimumZoomScale - 0.3) < 0.001)
        #expect(abs(scrollView.maximumZoomScale - 1.2) < 0.001)
        #expect(scrollView.contentInset.top > 0, "A picture shorter than the view is centred vertically")
    }

    @Test("Fits again when its bounds change without inflating the picture")
    func refitsOnBoundsChange() throws {
        let image = UIGraphicsImageRenderer(size: CGSize(width: 1000, height: 500)).image { _ in }
        let controller = UIHostingController(rootView: ZoomableImageView(image: image))
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 300, height: 300))
        window.rootViewController = controller
        window.makeKeyAndVisible()
        controller.view.layoutIfNeeded()
        let scrollView = try #require(controller.view.firstSubview(of: UIScrollView.self))
        let imageView = try #require(scrollView.firstSubview(of: UIImageView.self))

        let firstBounds = scrollView.bounds.size
        window.frame = CGRect(x: 0, y: 0, width: 600, height: 300)
        controller.view.frame = window.bounds
        controller.view.layoutIfNeeded()

        let bounds = scrollView.bounds.size
        #expect(bounds != firstBounds)
        let fitting = min(bounds.width / image.size.width, bounds.height / image.size.height)
        #expect(abs(scrollView.zoomScale - fitting) < 0.001)
        #expect(abs(scrollView.minimumZoomScale - fitting) < 0.001)
        #expect(imageView.bounds.size == image.size, "The zoom lives in the scroll view's transform, not in the image view's bounds")
    }
}


extension UIView {
    fileprivate func firstSubview<View: UIView>(of type: View.Type) -> View? {
        for subview in subviews {
            if let match = subview as? View ?? subview.firstSubview(of: type) {
                return match
            }
        }
        return nil
    }
}
#endif
