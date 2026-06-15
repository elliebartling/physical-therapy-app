import SwiftUI
import DataKit

public struct SetupView: View {
    @Bindable public var viewModel: SetupViewModel
    public var onDone: () -> Void

    @State private var showCamera = false

    public init(viewModel: SetupViewModel, onDone: @escaping () -> Void) {
        self.viewModel = viewModel
        self.onDone = onDone
    }

    public var body: some View {
        ZStack {
            AppColor.surface.ignoresSafeArea()
            switch viewModel.phase {
            case .idle:
                idleView
            case .parsing:
                VStack(spacing: AppSpacing.s(2)) {
                    ProgressView()
                    Text("Reading your handout…").font(AppFont.mono(14, weight: .medium))
                }
            case .editing:
                if let editorVM = viewModel.editorVM {
                    RoutineEditorView(viewModel: editorVM, onSave: { try? viewModel.commit() })
                } else {
                    Text("Editor unavailable")
                }
            case .saved:
                VStack(spacing: AppSpacing.s(2)) {
                    Text("Saved").font(AppFont.mono(28, weight: .bold))
                    Button("Done", action: onDone).buttonStyle(.borderedProminent)
                }
            case .failed(let msg):
                VStack(spacing: AppSpacing.s(2)) {
                    Text("Couldn't parse").font(AppFont.mono(20, weight: .medium))
                    Text(msg).font(AppFont.body(13)).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    Button("Enter manually", action: viewModel.startManual)
                }
                .padding(AppSpacing.screenPadding)
            }
        }
        .fullScreenCover(isPresented: $showCamera) {
            CameraCaptureView(
                onImage: { img in showCamera = false; Task { await viewModel.parse(img) } },
                onCancel: { showCamera = false }
            )
        }
    }

    private var idleView: some View {
        VStack(spacing: AppSpacing.s(3)) {
            Text("Set up your routine").font(AppFont.mono(28, weight: .medium))
            Text("Take a photo of your PT handout, or enter it manually.")
                .font(AppFont.body(15)).multilineTextAlignment(.center)
            Button("Scan handout") { showCamera = true }
                .buttonStyle(.borderedProminent)
            Button("Enter manually", action: viewModel.startManual)
        }
        .padding(AppSpacing.screenPadding)
    }
}
