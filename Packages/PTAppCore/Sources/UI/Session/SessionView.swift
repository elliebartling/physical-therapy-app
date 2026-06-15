import SwiftUI
import UIKit
import DataKit

public struct SessionView: View {
    @Bindable public var viewModel: SessionViewModel
    public var onComplete: () -> Void

    public init(viewModel: SessionViewModel, onComplete: @escaping () -> Void) {
        self.viewModel = viewModel
        self.onComplete = onComplete
    }

    public var body: some View {
        ZStack {
            AppColor.surface.ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture { viewModel.isPaused ? viewModel.resume() : viewModel.pause() }

            VStack(spacing: AppSpacing.s(4)) {
                Spacer()
                Text(viewModel.currentExerciseName.uppercased())
                    .font(AppFont.mono(20, weight: .medium))
                    .tracking(2)
                    .foregroundStyle(AppColor.text)

                Text("\(viewModel.currentSet) / \(viewModel.totalSets)")
                    .font(AppFont.mono(14, weight: .regular))
                    .foregroundStyle(.secondary)

                if viewModel.currentSide != .both {
                    Text(viewModel.currentSide == .left ? "L" : "R")
                        .font(AppFont.mono(36, weight: .bold))
                        .foregroundStyle(AppColor.accent)
                        .transition(.scale.combined(with: .opacity))
                        .id(viewModel.currentSide)
                }

                Spacer()

                HStack(spacing: AppSpacing.s(4)) {
                    Button(viewModel.isPaused ? "Resume" : "Pause") {
                        viewModel.isPaused ? viewModel.resume() : viewModel.pause()
                    }
                    Button("Done set") { Task { await viewModel.completeCurrentSet() } }
                    Button("Skip") { Task { await viewModel.skipCurrentSet() } }
                }
                .font(AppFont.mono(16, weight: .medium))
                .foregroundStyle(AppColor.text)
                .padding(.bottom, AppSpacing.s(4))
            }
            .padding(AppSpacing.screenPadding)
            .opacity(viewModel.isComplete ? 0 : 1)
        }
        .task { await viewModel.run() }
        .onChange(of: viewModel.isComplete) { _, complete in if complete { onComplete() } }
        .statusBarHidden()
        .onAppear { UIApplication.shared.isIdleTimerDisabled = true }
        .onDisappear { UIApplication.shared.isIdleTimerDisabled = false }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willResignActiveNotification)) { _ in
            viewModel.appWillResignActive()
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
            viewModel.appDidBecomeActive()
        }
    }
}
