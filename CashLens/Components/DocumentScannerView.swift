import SwiftUI
import VisionKit

/// SwiftUI wrapper around `VNDocumentCameraViewController` — Apple's
/// native receipt/document scanner. Auto-detects edges, perspective-
/// corrects, supports multi-page, and finishes by handing back a
/// `VNDocumentCameraScan`.
///
/// We currently take **page 1 only** of any multi-page scan. The
/// `Expense.receiptImagePath` field is single-image; supporting
/// multi-image attachments per expense (e.g. CVS-style 4-foot receipts
/// or hotel folios) is a v2.1 enhancement that would need a model
/// migration. For v1, taking the first page covers the dominant use
/// case (single-receipt photos for tax/reimbursement) without locking us
/// out of the future migration.
///
/// Presented as a `.fullScreenCover` from the receipt section in
/// `AddExpenseView`. The scanner is genuinely full-screen; presenting
/// inside a `.sheet` clips the camera viewfinder badly.
struct DocumentScannerView: UIViewControllerRepresentable {

    /// Called on the main actor with the captured image when the user
    /// taps Save in the scanner. The presenting view is responsible for
    /// kicking off `ReceiptStorage.save(_:)` on a background task and
    /// updating its own form state.
    let onCapture: (UIImage) -> Void

    /// Called when the user taps Cancel or the scanner fails to
    /// initialise (no camera, denied permission). Presenting view
    /// should dismiss the cover.
    let onDismiss: () -> Void

    func makeUIViewController(context: Context) -> VNDocumentCameraViewController {
        let controller = VNDocumentCameraViewController()
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ uiViewController: VNDocumentCameraViewController, context: Context) {
        // No reactive updates — the controller manages its own state
        // through the delegate callbacks below.
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    final class Coordinator: NSObject, VNDocumentCameraViewControllerDelegate {
        let parent: DocumentScannerView

        init(parent: DocumentScannerView) {
            self.parent = parent
        }

        func documentCameraViewController(_ controller: VNDocumentCameraViewController,
                                          didFinishWith scan: VNDocumentCameraScan) {
            // Take page 1 only for v1. See the type-level doc above for why.
            guard scan.pageCount > 0 else {
                parent.onDismiss()
                return
            }
            let image = scan.imageOfPage(at: 0)
            parent.onCapture(image)
        }

        func documentCameraViewControllerDidCancel(_ controller: VNDocumentCameraViewController) {
            parent.onDismiss()
        }

        func documentCameraViewController(_ controller: VNDocumentCameraViewController,
                                          didFailWithError error: Error) {
            // The most common failure is "user denied camera permission" —
            // in that case the system has already shown the standard
            // settings prompt, so dismissing the cover quietly is the
            // right move. Logged for diagnostics; no user-facing alert
            // because Apple's prompt is the right surface for this.
            print("DocumentScannerView failed: \(error.localizedDescription)")
            parent.onDismiss()
        }
    }
}

/// Returns true if VisionKit's document camera is supported on the
/// current device. False on simulator and on the rare Mac Catalyst
/// configurations without a camera. We use this to fall back to the
/// library-only path silently rather than presenting a broken scanner.
extension DocumentScannerView {
    static var isSupported: Bool {
        VNDocumentCameraViewController.isSupported
    }
}
