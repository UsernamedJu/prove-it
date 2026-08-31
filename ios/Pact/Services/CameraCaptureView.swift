import SwiftUI
import UIKit

/// Wraps `UIImagePickerController`'s camera source — SwiftUI has no native
/// live-camera-capture view of its own (`PhotosPicker` only reaches the
/// photo library), so this is the standard, well-established way to let
/// someone actually take a photo from inside the app, used for sending a
/// blind-reveal loser's proof photo to whoever won.
///
/// Falls back to the photo library when the camera itself isn't available
/// (every Simulator, and any device without one) rather than presenting a
/// picker that would just fail — this also means the surrounding flow can
/// still be exercised and verified without a real device's camera.
struct CameraCaptureView: UIViewControllerRepresentable {
    var onCapture: (UIImage?) -> Void

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = UIImagePickerController.isSourceTypeAvailable(.camera) ? .camera : .photoLibrary
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onCapture: onCapture) }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let onCapture: (UIImage?) -> Void
        init(onCapture: @escaping (UIImage?) -> Void) { self.onCapture = onCapture }

        func imagePickerController(_ picker: UIImagePickerController,
                                    didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            onCapture(info[.originalImage] as? UIImage)
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            onCapture(nil)
        }
    }
}
