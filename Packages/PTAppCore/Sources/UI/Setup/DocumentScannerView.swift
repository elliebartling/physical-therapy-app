import SwiftUI
import UIKit
import VisionKit

/// The system multi-page document scanner: edge detection, perspective correction,
/// and as many pages as the handout has.
public struct DocumentScannerView: UIViewControllerRepresentable {
    public var onScan: ([UIImage]) -> Void
    public var onCancel: () -> Void

    public init(onScan: @escaping ([UIImage]) -> Void, onCancel: @escaping () -> Void) {
        self.onScan = onScan
        self.onCancel = onCancel
    }

    public static var isSupported: Bool { VNDocumentCameraViewController.isSupported }

    public func makeUIViewController(context: Context) -> VNDocumentCameraViewController {
        let scanner = VNDocumentCameraViewController()
        scanner.delegate = context.coordinator
        return scanner
    }

    public func updateUIViewController(_ uiViewController: VNDocumentCameraViewController, context: Context) {}

    public func makeCoordinator() -> Coordinator { Coordinator(self) }

    public final class Coordinator: NSObject, VNDocumentCameraViewControllerDelegate {
        let parent: DocumentScannerView
        init(_ parent: DocumentScannerView) { self.parent = parent }

        public func documentCameraViewController(_ controller: VNDocumentCameraViewController,
                                                 didFinishWith scan: VNDocumentCameraScan) {
            let pages = (0..<scan.pageCount).map { scan.imageOfPage(at: $0) }
            parent.onScan(pages)
        }

        public func documentCameraViewControllerDidCancel(_ controller: VNDocumentCameraViewController) {
            parent.onCancel()
        }

        public func documentCameraViewController(_ controller: VNDocumentCameraViewController,
                                                 didFailWithError error: Error) {
            parent.onCancel()
        }
    }
}
