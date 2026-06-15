import SwiftUI
import SwiftData
import DataKit
import HistoryKit

public struct HomeView: View {
    @Bindable public var viewModel: HomeViewModel
    public var onStart: () -> Void
    public var onSettings: () -> Void
    public var onSetup: () -> Void

    public init(viewModel: HomeViewModel, onStart: @escaping () -> Void,
                onSettings: @escaping () -> Void, onSetup: @escaping () -> Void) {
        self.viewModel = viewModel
        self.onStart = onStart
        self.onSettings = onSettings
        self.onSetup = onSetup
    }

    public var body: some View {
        ZStack(alignment: .topTrailing) {
            AppColor.surface.ignoresSafeArea()

            if viewModel.hasRoutine {
                VStack(spacing: AppSpacing.s(4)) {
                    Spacer(minLength: AppSpacing.s(8))
                    streakBlock
                    HairlineDivider()
                    HeatmapView(matrix: viewModel.heatmap)
                    Spacer()
                    startButton
                }
                .padding(.horizontal, AppSpacing.screenPadding)
            } else {
                VStack(spacing: AppSpacing.s(3)) {
                    Text("No routine yet").font(AppFont.mono(28, weight: .medium))
                    Text("Set up your routine to begin.").font(AppFont.body(15))
                    Button("Set up", action: onSetup)
                        .buttonStyle(AccentButtonStyle())
                        .padding(.top, AppSpacing.s(2))
                }
                .padding(AppSpacing.screenPadding)
            }

            Button(action: onSettings) {
                Image(systemName: "gearshape")
                    .font(.system(size: 22, weight: .thin))
                    .foregroundStyle(AppColor.text)
            }
            .padding(AppSpacing.screenPadding)
        }
        .task { await viewModel.refresh() }
    }

    private var streakBlock: some View {
        VStack(spacing: AppSpacing.s(1)) {
            Text("\(viewModel.streak)")
                .font(AppFont.mono(120, weight: .bold))
                .foregroundStyle(AppColor.accent)
            Text("DAY STREAK").font(AppFont.mono(12, weight: .medium)).tracking(2)
        }
    }

    private var startButton: some View {
        Button("Start", action: onStart)
            .buttonStyle(AccentButtonStyle())
            .padding(.bottom, AppSpacing.s(6))
    }
}

private struct AccentButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(AppFont.mono(20, weight: .medium))
            .foregroundStyle(.black)
            .frame(maxWidth: .infinity)
            .padding(.vertical, AppSpacing.s(2))
            .background(AppColor.accent)
            .opacity(configuration.isPressed ? 0.8 : 1)
    }
}

struct HeatmapView: View {
    let matrix: HeatmapMatrix
    var body: some View {
        let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 7)
        LazyVGrid(columns: columns, spacing: 4) {
            ForEach(1...max(matrix.daysInMonth, 1), id: \.self) { day in
                Rectangle()
                    .fill(matrix.completedDayNumbers.contains(day) ? AppColor.accent : AppColor.hairline)
                    .aspectRatio(1, contentMode: .fit)
            }
        }
        .padding(.vertical, AppSpacing.s(2))
    }
}

#Preview("Home (empty)") {
    let c = try! ModelContainerFactory.inMemory()
    let vm = HomeViewModel(
        routineRepo: RoutineRepository(context: c.mainContext),
        sessionRepo: SessionRepository(context: c.mainContext)
    )
    HomeView(viewModel: vm, onStart: {}, onSettings: {}, onSetup: {})
        .modelContainer(c)
}
