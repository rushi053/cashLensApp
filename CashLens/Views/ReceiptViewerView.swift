import SwiftUI
import UIKit

/// Full-screen receipt viewer presented from `AddExpenseView` (and any
/// future surface that wants to show a saved receipt). Supports:
///
/// * pinch-to-zoom (1× – 5×) with double-tap to toggle full / fit
/// * pan when zoomed
/// * native iOS share sheet (UIActivityViewController) for export
/// * destructive Delete with confirmation, surfaced through the
///   caller's `onDelete` closure so the form's storage layer remains
///   the single source of truth for cleanup
///
/// Presented as a `.fullScreenCover` so the image gets the whole
/// canvas — receipts often have small print and benefit from the extra
/// pixels.
struct ReceiptViewerView: View {
    let image: UIImage
    let onDismiss: () -> Void
    let onDelete: () -> Void

    @State private var scale: CGFloat = 1
    @State private var lastScale: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero
    @State private var showingDeleteConfirm = false
    @State private var showingShareSheet = false

    private let minScale: CGFloat = 1
    private let maxScale: CGFloat = 5

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            zoomableImage
                .ignoresSafeArea()

            VStack {
                topBar
                Spacer()
                bottomBar
            }
        }
        .statusBarHidden()
        .confirmationDialog(
            "Delete this receipt?",
            isPresented: $showingDeleteConfirm,
            titleVisibility: .visible
        ) {
            Button("Delete Receipt", role: .destructive) { onDelete() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes the receipt from this expense. The expense itself stays.")
        }
        .sheet(isPresented: $showingShareSheet) {
            ReceiptShareSheet(items: [image])
        }
    }

    // MARK: - Subviews

    private var zoomableImage: some View {
        Image(uiImage: image)
            .resizable()
            .scaledToFit()
            .scaleEffect(scale)
            .offset(offset)
            .gesture(
                MagnificationGesture()
                    .onChanged { value in
                        scale = clamp(lastScale * value, min: minScale, max: maxScale)
                    }
                    .onEnded { _ in
                        lastScale = scale
                        if scale <= minScale {
                            // Reset pan if the user zoomed back out — pan
                            // only makes sense when zoomed in.
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                                offset = .zero
                                lastOffset = .zero
                            }
                        }
                    }
            )
            .simultaneousGesture(
                DragGesture()
                    .onChanged { value in
                        // Only allow pan when zoomed past 1×, otherwise
                        // the gesture interferes with vertical-edge swipe
                        // expectations on a 1:1 image.
                        guard scale > minScale else { return }
                        offset = CGSize(
                            width: lastOffset.width + value.translation.width,
                            height: lastOffset.height + value.translation.height
                        )
                    }
                    .onEnded { _ in
                        lastOffset = offset
                    }
            )
            .onTapGesture(count: 2) {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                    if scale > minScale {
                        scale = minScale
                        lastScale = minScale
                        offset = .zero
                        lastOffset = .zero
                    } else {
                        // Quick double-tap zoom to ~2.4× — comfortable
                        // for reading receipt line items without having
                        // to two-finger pinch from cold.
                        scale = 2.4
                        lastScale = 2.4
                    }
                }
            }
            .accessibilityLabel("Receipt image. Double-tap to zoom.")
    }

    private var topBar: some View {
        HStack {
            Button {
                HapticManager.shared.lightTap()
                onDismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundColor(.white)
                    .frame(width: 40, height: 40)
                    .background(.ultraThinMaterial, in: Circle())
            }

            Spacer()

            Text("Receipt")
                .font(.system(size: 16, weight: .semibold, design: .rounded))
                .foregroundColor(.white.opacity(0.85))
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(.ultraThinMaterial, in: Capsule())

            Spacer()

            Button {
                HapticManager.shared.lightTap()
                showingShareSheet = true
            } label: {
                Image(systemName: "square.and.arrow.up")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(width: 40, height: 40)
                    .background(.ultraThinMaterial, in: Circle())
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, 12)
    }

    private var bottomBar: some View {
        HStack {
            Spacer()
            Button {
                HapticManager.shared.warning()
                showingDeleteConfirm = true
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "trash")
                        .font(.system(size: 14, weight: .semibold))
                    Text("Delete")
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                }
                .foregroundColor(.red)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(.ultraThinMaterial, in: Capsule())
            }
            Spacer()
        }
        .padding(.bottom, 32)
    }

    // MARK: - Helpers

    private func clamp(_ value: CGFloat, min lo: CGFloat, max hi: CGFloat) -> CGFloat {
        Swift.min(hi, Swift.max(lo, value))
    }
}

// MARK: - Share sheet wrapper

/// Tiny `UIViewControllerRepresentable` over `UIActivityViewController`.
/// Named `ReceiptShareSheet` to avoid collision with the existing
/// `ShareSheet` in `ExportDataView.swift` (which has the same shape but
/// is module-internal). Kept local so the receipt viewer's only
/// dependency surface is its own file.
private struct ReceiptShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
