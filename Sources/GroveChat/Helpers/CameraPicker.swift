//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

#if os(iOS)
import SwiftUI
import UIKit


/// Takes a photo with the camera.
///
/// SwiftUI has no camera picker of its own, so this wraps `UIImagePickerController` — whose camera source is not
/// deprecated, unlike its photo-library ones, and which remains the smallest correct way to reach the shutter.
@available(iOS 18, macOS 15, watchOS 11, *)
struct CameraPicker: UIViewControllerRepresentable {
    /// Bridges the picker's delegate callbacks back into SwiftUI.
    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        private let onCapture: (PlatformImage) -> Void
        private let onFinish: () -> Void

        init(onCapture: @escaping (PlatformImage) -> Void, onFinish: @escaping () -> Void) {
            self.onCapture = onCapture
            self.onFinish = onFinish
        }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            if let image = info[.originalImage] as? UIImage {
                onCapture(image)
            }
            onFinish()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            onFinish()
        }
    }


    /// Receives the photo that was taken.
    let onCapture: (PlatformImage) -> Void

    @Environment(\.dismiss) private var dismiss

    func makeCoordinator() -> Coordinator {
        Coordinator(onCapture: onCapture, onFinish: { dismiss() })
    }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let controller = UIImagePickerController()
        controller.sourceType = .camera
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ controller: UIImagePickerController, context: Context) {}
}
#endif
