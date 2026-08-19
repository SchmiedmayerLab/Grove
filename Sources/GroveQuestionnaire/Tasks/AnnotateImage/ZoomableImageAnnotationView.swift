//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

#if canImport(UIKit)
import PencilKit
import SwiftUI


/// A PencilKit canvas that keeps its backing image in the same zoomable coordinate space.
///
/// `PKCanvasView` provides the interaction model: one finger draws while a pinch or two-finger pan navigates.
@available(iOS 18, macOS 15, watchOS 11, *)
struct ZoomableImageAnnotationView: UIViewRepresentable {
    private static let maximumZoomMultiplier = CGFloat(5)

    let image: UIImage
    @Binding var drawing: PKDrawing
    let tool: PKInkingTool
    let isDrawingEnabled: Bool
    let contentInsets: UIEdgeInsets
    let history: AnnotationHistoryController

    func makeUIView(context: Context) -> AnnotationCanvasView {
        let canvasView = AnnotationCanvasView()
        canvasView.delegate = context.coordinator
        canvasView.backgroundColor = .clear
        canvasView.isOpaque = false
        canvasView.contentInsetAdjustmentBehavior = .never
        canvasView.showsHorizontalScrollIndicator = false
        canvasView.showsVerticalScrollIndicator = false
        canvasView.alwaysBounceHorizontal = false
        canvasView.alwaysBounceVertical = false
        canvasView.bouncesZoom = true
        canvasView.decelerationRate = .fast
        canvasView.drawingPolicy = .anyInput
        canvasView.panGestureRecognizer.minimumNumberOfTouches = 2
        canvasView.layoutHandler = { canvasView in
            context.coordinator.updateLayout(of: canvasView)
        }

        history.attach(to: canvasView, delegate: context.coordinator)
        context.coordinator.installImageView(in: canvasView)
        configure(canvasView, coordinator: context.coordinator)
        return canvasView
    }

    func updateUIView(_ canvasView: AnnotationCanvasView, context: Context) {
        context.coordinator.parent = self
        configure(canvasView, coordinator: context.coordinator)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    private func configure(_ canvasView: AnnotationCanvasView, coordinator: Coordinator) {
        if !history.isPerformingHistoryAction && canvasView.drawing != drawing {
            canvasView.drawing = drawing
        }
        canvasView.tool = tool
        canvasView.drawingPolicy = .anyInput
        canvasView.isDrawingEnabled = isDrawingEnabled
        canvasView.accessibilityLabel = String(localized: "Image annotation canvas", bundle: .module)
        canvasView.accessibilityHint = String(
            localized: "Draw with one finger. Pinch or drag with two fingers to move the image.",
            bundle: .module
        )
        canvasView.accessibilityIdentifier = "ImageAnnotationCanvas"
        coordinator.updateImage(in: canvasView)
        coordinator.updateLayout(of: canvasView)
    }
}


extension ZoomableImageAnnotationView {
    final class AnnotationCanvasView: PKCanvasView {
        var layoutHandler: ((AnnotationCanvasView) -> Void)?

        override func layoutSubviews() {
            super.layoutSubviews()
            layoutHandler?(self)
        }

        override func safeAreaInsetsDidChange() {
            super.safeAreaInsetsDidChange()
            layoutHandler?(self)
        }
    }

    @MainActor
    final class Coordinator: NSObject, PKCanvasViewDelegate, AnnotationHistoryControllerDelegate {
        var parent: ZoomableImageAnnotationView

        private let imageView = UIImageView()
        private var configuredImageSize = CGSize.zero
        private var configuredViewportSize = CGSize.zero
        private var configuredInsets = UIEdgeInsets.zero
        private var hasUserNavigated = false
        private var isUpdatingLayout = false

        init(parent: ZoomableImageAnnotationView) {
            self.parent = parent
            imageView.contentMode = .scaleAspectFit
            imageView.isUserInteractionEnabled = false
            imageView.isAccessibilityElement = false
        }

        func installImageView(in canvasView: AnnotationCanvasView) {
            canvasView.insertSubview(imageView, at: 0)
        }

        func updateImage(in canvasView: AnnotationCanvasView) {
            let imageSize = parent.imageSizeInPixels
            // The editor image is immutable for the sheet's lifetime. SwiftUI may still recreate
            // its UIImage wrapper when the drawing binding changes, which must not reset zoom.
            guard imageView.image == nil || configuredImageSize != imageSize else {
                return
            }

            imageView.image = parent.image
            imageView.frame = CGRect(origin: .zero, size: imageSize)
            canvasView.contentSize = imageSize
            configuredImageSize = imageSize
            configuredViewportSize = .zero
            hasUserNavigated = false
        }

        func updateLayout(of canvasView: AnnotationCanvasView) {
            guard !isUpdatingLayout,
                  canvasView.bounds.width > 0,
                  canvasView.bounds.height > 0,
                  configuredImageSize.width > 0,
                  configuredImageSize.height > 0 else {
                return
            }

            let viewportSize = canvasView.bounds.size
            let insets = effectiveContentInsets(for: canvasView)
            let layoutChanged = viewportSize != configuredViewportSize || insets != configuredInsets
            guard layoutChanged else {
                return
            }

            isUpdatingLayout = true
            defer { isUpdatingLayout = false }

            let availableSize = CGSize(
                width: max(viewportSize.width - insets.left - insets.right, 1),
                height: max(viewportSize.height - insets.top - insets.bottom, 1)
            )
            let minimumZoomScale = min(
                availableSize.width / configuredImageSize.width,
                availableSize.height / configuredImageSize.height
            )

            canvasView.minimumZoomScale = minimumZoomScale
            canvasView.maximumZoomScale = minimumZoomScale * ZoomableImageAnnotationView.maximumZoomMultiplier
            if !hasUserNavigated || canvasView.zoomScale < minimumZoomScale {
                canvasView.zoomScale = minimumZoomScale
            }
            updateContentInsets(of: canvasView)
            if !hasUserNavigated {
                canvasView.contentOffset = CGPoint(
                    x: -canvasView.contentInset.left,
                    y: -canvasView.contentInset.top
                )
            }

            configuredViewportSize = viewportSize
            configuredInsets = insets
        }

        func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
            let oldDrawing = parent.drawing
            let newDrawing = canvasView.drawing
            guard oldDrawing != newDrawing && !(oldDrawing.isEmpty && newDrawing.isEmpty) else {
                return
            }
            parent.drawing = newDrawing
            parent.history.drawingDidChange(from: oldDrawing)
        }

        func annotationHistoryDidRestore(_ drawing: PKDrawing) {
            if parent.drawing != drawing {
                parent.drawing = drawing
            }
        }

        func scrollViewDidZoom(_ scrollView: UIScrollView) {
            guard let canvasView = scrollView as? AnnotationCanvasView else {
                return
            }
            updateContentInsets(of: canvasView)
        }

        func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
            hasUserNavigated = true
        }

        func scrollViewWillBeginZooming(_ scrollView: UIScrollView, with view: UIView?) {
            hasUserNavigated = true
        }

        private func updateContentInsets(of canvasView: AnnotationCanvasView) {
            let scaledImageSize = CGSize(
                width: configuredImageSize.width * canvasView.zoomScale,
                height: configuredImageSize.height * canvasView.zoomScale
            )
            imageView.frame = CGRect(origin: .zero, size: scaledImageSize)
            let insets = effectiveContentInsets(for: canvasView)
            let availableWidth = canvasView.bounds.width - insets.left - insets.right
            let availableHeight = canvasView.bounds.height - insets.top - insets.bottom
            let horizontalPadding = max((availableWidth - scaledImageSize.width) / 2, 0)
            let verticalPadding = max((availableHeight - scaledImageSize.height) / 2, 0)

            canvasView.contentInset = UIEdgeInsets(
                top: insets.top + verticalPadding,
                left: insets.left + horizontalPadding,
                bottom: insets.bottom + verticalPadding,
                right: insets.right + horizontalPadding
            )
        }

        private func effectiveContentInsets(for canvasView: AnnotationCanvasView) -> UIEdgeInsets {
            UIEdgeInsets(
                top: parent.contentInsets.top + canvasView.safeAreaInsets.top,
                left: parent.contentInsets.left,
                bottom: parent.contentInsets.bottom + canvasView.safeAreaInsets.bottom,
                right: parent.contentInsets.right
            )
        }
    }
}


extension ZoomableImageAnnotationView {
    fileprivate var imageSizeInPixels: CGSize {
        image.size.applying(.identity.scaledBy(x: image.scale, y: image.scale))
    }
}
#endif
