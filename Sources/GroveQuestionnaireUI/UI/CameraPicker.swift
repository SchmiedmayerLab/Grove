//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

#if canImport(UIKit) && !os(watchOS) && !os(visionOS)
import SwiftUI
import UIKit


/// The system camera, handing back the picture it took as a JPEG in the temporary directory, or why it could not.
@available(iOS 18, *)
struct CameraPicker: UIViewControllerRepresentable {
    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        private let parent: CameraPicker

        init(parent: CameraPicker) {
            self.parent = parent
        }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            defer { parent.dismiss() }
            guard let image = info[.originalImage] as? UIImage, let data = image.jpegData(compressionQuality: 0.9) else {
                return
            }
            let url = FileManager.default.temporaryDirectory.appending(path: "photo-\(UUID().uuidString).jpg")
            parent.onCapture(Result { try data.write(to: url) }.map { url })
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
    }

    /// Whether the host has opted into camera capture and this device can provide it.
    static var isAvailable: Bool {
        guard let usageDescription = Bundle.main.object(forInfoDictionaryKey: "NSCameraUsageDescription") as? String,
              !usageDescription.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return false
        }
        return UIImagePickerController.isSourceTypeAvailable(.camera)
    }

    let onCapture: @MainActor (Result<URL, any Error>) -> Void

    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }
}
#endif
