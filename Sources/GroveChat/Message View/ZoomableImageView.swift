//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

#if os(iOS) || os(visionOS)
import SwiftUI
import UIKit


/// A picture that opens fitted to the screen and zooms the way Photos does: pinch up to four times that, double
/// tap between fitted and doubled, always centred.
@available(iOS 18, visionOS 2, *)
struct ZoomableImageView: UIViewRepresentable {
    /// The representable is updated before the view has a size, so the fit has to follow layout.
    final class ScrollView: UIScrollView {
        var onLayout: (() -> Void)?

        override func layoutSubviews() {
            super.layoutSubviews()
            onLayout?()
        }
    }

    final class Coordinator: NSObject, UIScrollViewDelegate {
        var imageView: UIImageView?
        var fitted = false
        private var fittedBounds = CGSize.zero
        private var isFitting = false

        /// Sizes the image to the scroll view and starts from the fitted scale; re-fits when the bounds change.
        ///
        /// The frame is only ever set at a zoom scale of 1: a zoomed scroll view scales its content view through its
        /// transform, and a frame assigned underneath that transform inflates the bounds by the inverse scale, which
        /// shows the picture at pixel size with no way to zoom back out. Assigning the zoom scale lays out again, so
        /// the method also guards against re-entering itself.
        func fit(_ scrollView: UIScrollView) {
            guard !isFitting, let imageView, let image = imageView.image, scrollView.bounds.size != .zero,
                  !fitted || scrollView.bounds.size != fittedBounds else {
                return
            }
            isFitting = true
            defer { isFitting = false }
            scrollView.minimumZoomScale = 1
            scrollView.maximumZoomScale = 1
            scrollView.zoomScale = 1
            imageView.frame = CGRect(origin: .zero, size: image.size)
            scrollView.contentSize = image.size
            let fittingScale = min(scrollView.bounds.width / image.size.width, scrollView.bounds.height / image.size.height)
            scrollView.minimumZoomScale = fittingScale
            scrollView.maximumZoomScale = fittingScale * ZoomableImageView.maximumZoomMultiplier
            scrollView.zoomScale = fittingScale
            center(scrollView)
            fitted = true
            fittedBounds = scrollView.bounds.size
        }

        func viewForZooming(in scrollView: UIScrollView) -> UIView? {
            imageView
        }

        func scrollViewDidZoom(_ scrollView: UIScrollView) {
            center(scrollView)
        }

        @objc
        func toggleZoom(_ gesture: UITapGestureRecognizer) {
            guard let scrollView = gesture.view as? UIScrollView else {
                return
            }
            if scrollView.zoomScale > scrollView.minimumZoomScale {
                scrollView.setZoomScale(scrollView.minimumZoomScale, animated: true)
            } else {
                let scale = scrollView.minimumZoomScale * 2
                let point = gesture.location(in: imageView)
                let size = CGSize(width: scrollView.bounds.width / scale, height: scrollView.bounds.height / scale)
                let origin = CGPoint(x: point.x - size.width / 2, y: point.y - size.height / 2)
                scrollView.zoom(to: CGRect(origin: origin, size: size), animated: true)
            }
        }

        /// Keeps a picture smaller than the view in its middle rather than in the top-left corner.
        private func center(_ scrollView: UIScrollView) {
            let horizontal = max(0, (scrollView.bounds.width - scrollView.contentSize.width) / 2)
            let vertical = max(0, (scrollView.bounds.height - scrollView.contentSize.height) / 2)
            scrollView.contentInset = UIEdgeInsets(top: vertical, left: horizontal, bottom: vertical, right: horizontal)
        }
    }

    private static let maximumZoomMultiplier: CGFloat = 4

    let image: UIImage

    func makeUIView(context: Context) -> ScrollView {
        let scrollView = ScrollView()
        scrollView.delegate = context.coordinator
        scrollView.onLayout = { [weak scrollView, coordinator = context.coordinator] in
            if let scrollView {
                coordinator.fit(scrollView)
            }
        }
        scrollView.showsVerticalScrollIndicator = false
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.contentInsetAdjustmentBehavior = .never
        scrollView.bouncesZoom = true
        let imageView = UIImageView(image: image)
        imageView.contentMode = .scaleAspectFit
        scrollView.addSubview(imageView)
        context.coordinator.imageView = imageView
        let doubleTap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.toggleZoom(_:)))
        doubleTap.numberOfTapsRequired = 2
        scrollView.addGestureRecognizer(doubleTap)
        return scrollView
    }

    func updateUIView(_ scrollView: ScrollView, context: Context) {
        let imageView = context.coordinator.imageView
        if imageView?.image !== image {
            imageView?.image = image
            context.coordinator.fitted = false
        }
        context.coordinator.fit(scrollView)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }
}
#endif
