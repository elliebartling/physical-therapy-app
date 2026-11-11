import SwiftUI
import UIKit
import PhotosUI
import DataKit

public struct SetupView: View {
    @Bindable public var viewModel: SetupViewModel
    public var onDone: () -> Void
    public var onCancel: () -> Void

    @State private var showScanner = false
    @State private var showBrainDump = false
    @State private var photoItems: [PhotosPickerItem] = []

    public init(viewModel: SetupViewModel, onDone: @escaping () -> Void, onCancel: @escaping () -> Void = {}) {
        self.viewModel = viewModel
        self.onDone = onDone
        self.onCancel = onCancel
    }

    public var body: some View {
        ZStack {
            AppColor.surface.ignoresSafeArea()
            content
        }
        .foregroundStyle(AppColor.ink)
        .fullScreenCover(isPresented: $showScanner) {
            DocumentScannerView(
                onScan: { pages in
                    showScanner = false
                    Task { await viewModel.parse(pages) }
                },
                onCancel: { showScanner = false }
            )
            .ignoresSafeArea()
        }
        .sheet(isPresented: $showBrainDump) {
            BrainDumpView(
                onSubmit: { text in
                    showBrainDump = false
                    Task { await viewModel.parse(transcript: text) }
                },
                onCancel: { showBrainDump = false }
            )
        }
        .onChange(of: photoItems) { _, items in
            guard !items.isEmpty else { return }
            Task { await loadAndParse(items) }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.phase {
        case .idle:
            sourcePicker
        case .parsing(let message):
            VStack(spacing: AppSpacing.s(2)) {
                ProgressView()
                Text(message).font(AppFont.mono(14, weight: .medium))
            }
        case .editing:
            if let editorVM = viewModel.editorVM {
                RoutineEditorView(viewModel: editorVM, onSave: { try? viewModel.commit() })
            } else {
                Text("Editor unavailable")
            }
        case .saved:
            VStack(alignment: .leading, spacing: AppSpacing.s(2)) {
                Spacer()
                Text("Saved.")
                    .font(AppFont.display(44, weight: .bold))
                    .tracking(-1.8)
                Spacer()
                Button(action: onDone) {
                    HStack {
                        Text("Done")
                        Spacer()
                        Image(systemName: "checkmark")
                    }
                    .font(AppFont.display(17, weight: .semibold))
                    .padding(.horizontal, 22)
                }
                .buttonStyle(InkGlassButtonStyle())
            }
            .padding(.horizontal, AppSpacing.screenPadding)
            .padding(.bottom, AppSpacing.s(1))
        case .failed(let message):
            failure(message)
        }
    }

    private var sourcePicker: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(spacing: 10) {
                HStack {
                    Button(action: onCancel) {
                        Image(systemName: "xmark")
                    }
                    .buttonStyle(GlassCircleButtonStyle())
                    .accessibilityLabel("Cancel")
                    Spacer()
                    SectionLabel("New routine")
                }
                InkRule(weight: 2)
            }
            .padding(.top, AppSpacing.s(1))

            Text("Add your routine")
                .font(AppFont.display(40, weight: .bold))
                .tracking(-1.6)
                .padding(.top, 22)
            Text("Scan the pages, pick screenshots, or just talk it through. Everything is read on this iPhone.")
                .font(AppFont.body(15))
                .foregroundStyle(AppColor.inkSecondary)
                .padding(.top, 10)

            sources.padding(.top, 24)

            Spacer()

            Button(action: viewModel.startManual) {
                Text("Enter manually instead")
                    .font(AppFont.display(16, weight: .semibold))
                    .underline()
                    .frame(minHeight: 44)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, AppSpacing.screenPadding)
        .padding(.bottom, AppSpacing.s(1))
    }

    private var sources: some View {
        let canScan = DocumentScannerView.isSupported
        let offset = canScan ? 1 : 0
        return VStack(spacing: 0) {
            if canScan {
                Button { showScanner = true } label: {
                    SourceRow(number: 1, title: "Scan pages",
                              detail: "Camera — as many pages as you have",
                              systemImage: "doc.viewfinder")
                }
                .buttonStyle(.plain)
            }
            PhotosPicker(selection: $photoItems, maxSelectionCount: 10,
                         selectionBehavior: .ordered, matching: .images) {
                SourceRow(number: 1 + offset, title: "Choose photos",
                          detail: "Screenshots or photos — up to 10",
                          systemImage: "photo.on.rectangle")
            }
            .buttonStyle(.plain)
            Button { showBrainDump = true } label: {
                SourceRow(number: 2 + offset, title: "Talk it through",
                          detail: "Describe your exercises out loud",
                          systemImage: "waveform")
            }
            .buttonStyle(.plain)
        }
        .overlay(alignment: .bottom) { HairlineDivider() }
    }

    private func failure(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.s(2)) {
            Spacer()
            Text("Couldn't read that")
                .font(AppFont.display(32, weight: .bold))
                .tracking(-1.2)
            Text(message)
                .font(AppFont.body(15))
                .foregroundStyle(AppColor.inkSecondary)
            Spacer()
            Button(action: viewModel.startOver) {
                HStack {
                    Text("Try again")
                    Spacer()
                    Image(systemName: "arrow.counterclockwise")
                }
                .font(AppFont.display(17, weight: .semibold))
                .padding(.horizontal, 22)
            }
            .buttonStyle(InkGlassButtonStyle())
            Button(action: viewModel.startManual) {
                Text("Enter manually instead")
                    .font(AppFont.display(16, weight: .semibold))
                    .underline()
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, AppSpacing.screenPadding)
        .padding(.bottom, AppSpacing.s(1))
    }

    /// Loads picked photos in the order they were selected, then reads them as one routine.
    private func loadAndParse(_ items: [PhotosPickerItem]) async {
        var images: [UIImage] = []
        for item in items {
            if let data = try? await item.loadTransferable(type: Data.self),
               let image = UIImage(data: data) {
                images.append(image)
            }
        }
        photoItems = []
        // An empty result (every photo failed to load) surfaces as a failure message.
        await viewModel.parse(images)
    }
}

private struct SourceRow: View {
    let number: Int
    let title: String
    let detail: String
    let systemImage: String

    var body: some View {
        HStack(spacing: 14) {
            Text(String(format: "%02d", number))
                .font(AppFont.mono(11))
                .foregroundStyle(AppColor.inkSecondary)
                .frame(width: 24, alignment: .leading)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(AppFont.display(20, weight: .semibold))
                    .tracking(-0.4)
                Text(detail.uppercased())
                    .font(AppFont.mono(10))
                    .tracking(0.6)
                    .foregroundStyle(AppColor.inkSecondary)
            }
            Spacer()
            Image(systemName: systemImage)
                .font(.system(size: 22))
                .accessibilityHidden(true)
        }
        .padding(.vertical, 18)
        .foregroundStyle(AppColor.ink)
        .contentShape(Rectangle())
        .overlay(alignment: .top) { HairlineDivider() }
    }
}
