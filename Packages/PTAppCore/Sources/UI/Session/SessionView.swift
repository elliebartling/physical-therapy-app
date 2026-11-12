import SwiftUI
import UIKit
import DataKit

public struct SessionView: View {
    @Bindable public var viewModel: SessionViewModel
    /// Called with the finished session's record, for the summary.
    public var onComplete: (SessionRecord) -> Void
    public var onEnd: () -> Void

    @State private var confirmingEnd = false
    @Environment(\.appAccent) private var accent
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    public init(viewModel: SessionViewModel, onComplete: @escaping (SessionRecord) -> Void,
                onEnd: @escaping () -> Void = {}) {
        self.viewModel = viewModel
        self.onComplete = onComplete
        self.onEnd = onEnd
    }

    public var body: some View {
        TimelineView(.periodic(from: .now, by: 0.25)) { context in
            let reading = TimerReading(display: viewModel.display,
                                       startedAt: viewModel.displayStartedAt,
                                       now: context.date)
            ZStack(alignment: .bottom) {
                AppColor.surface
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    .onTapGesture { togglePause() }

                TimerField(fraction: reading.fraction, color: accent)

                VStack(alignment: .leading, spacing: 0) {
                    header
                    titleBlock.padding(.top, 26)
                        .layoutPriority(-1) // the block above the timer gives way first
                    if let prompt = viewModel.ratingPrompt {
                        RatingPromptCard(exerciseName: prompt.exerciseName,
                                         onRate: { viewModel.rate($0) },
                                         onDismiss: { viewModel.dismissRatingPrompt() })
                            .padding(.top, 18)
                            .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                    Spacer(minLength: AppSpacing.s(2))
                    BigReading(reading: reading)
                        .layoutPriority(1)
                    controls.padding(.top, AppSpacing.s(3))
                }
                .padding(.horizontal, AppSpacing.screenPadding)
                .padding(.bottom, AppSpacing.s(1))
            }
        }
        .foregroundStyle(AppColor.ink)
        .opacity(viewModel.isComplete ? 0 : 1)
        .animation(reduceMotion ? nil : .smooth(duration: 0.3), value: viewModel.ratingPrompt)
        .task { await viewModel.run() }
        .task(id: viewModel.ratingPrompt?.id) {
            // An unanswered rating goes away on its own; it's always optional.
            guard viewModel.ratingPrompt != nil else { return }
            do {
                try await Task.sleep(for: .seconds(8))
                viewModel.dismissRatingPrompt()
            } catch {
                // Replaced by a newer prompt, or the view went away.
            }
        }
        .onChange(of: viewModel.isComplete) { _, complete in
            guard complete else { return }
            viewModel.endedEarly ? onEnd() : onComplete(viewModel.record)
        }
        .confirmationDialog("End this session?", isPresented: $confirmingEnd, titleVisibility: .visible) {
            Button("End session", role: .destructive) { viewModel.endEarly() }
            Button("Keep going", role: .cancel) {}
        } message: {
            Text("What you've done so far is saved.")
        }
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

    private var header: some View {
        VStack(spacing: 10) {
            HStack {
                Button { confirmingEnd = true } label: {
                    Image(systemName: "xmark")
                }
                .buttonStyle(GlassCircleButtonStyle())
                .accessibilityLabel("End session")
                Spacer()
                SectionLabel(String(format: "Exercise %02d / %02d", viewModel.exerciseIndex + 1, max(viewModel.totalExercises, 1)))
            }
            InkRule(weight: 2)
            ProgressSegments(total: viewModel.totalExercises, current: viewModel.exerciseIndex, accent: accent)
        }
        .padding(.top, AppSpacing.s(1))
    }

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 12) {
            if showsFigure {
                ExerciseFigure(art: viewModel.currentArt)
                    .frame(maxWidth: 96, maxHeight: 96, alignment: .leading)
                    .layoutPriority(-1) // yields to the title within this block
            }
            Text(viewModel.isResting ? "Rest" : viewModel.currentExerciseName)
                .font(AppFont.display(56, weight: .bold))
                .tracking(-2.6)
                .lineLimit(2)
                .minimumScaleFactor(0.6)
            Text(metaLine)
                .font(AppFont.mono(12, weight: .medium))
                .tracking(0.7)
                .foregroundStyle(AppColor.inkSecondary)
            if !viewModel.isResting, !viewModel.currentNotes.isEmpty {
                Text(viewModel.currentNotes)
                    .font(AppFont.body(15))
                    .foregroundStyle(AppColor.inkSecondary)
                    .lineLimit(3)
            }
        }
    }

    private var showsFigure: Bool {
        Self.showsFigure(art: viewModel.currentArt, isResting: viewModel.isResting,
                         dynamicTypeSize: dynamicTypeSize)
    }

    /// The timer outranks the picture. The figure appears only when a picture can exist
    /// (no reserved blank for `.none`/`.unmatched`), not during Rest, and not at accessibility
    /// sizes. `isAccessibilitySize` is deliberately coarse: it also drops the figure on
    /// large phones with room to spare, which is cheaper and safer than measuring space.
    static func showsFigure(art: ArtChoice, isResting: Bool, dynamicTypeSize: DynamicTypeSize) -> Bool {
        guard case .library = art else { return false }
        return !isResting && !dynamicTypeSize.isAccessibilitySize
    }

    private var metaLine: String {
        if viewModel.isResting {
            return "NEXT — SET \(viewModel.currentSet + 1)/\(viewModel.totalSets)"
        }
        var parts = ["SET \(viewModel.currentSet)/\(viewModel.totalSets)"]
        switch viewModel.currentSide {
        case .left: parts.append("LEFT SIDE")
        case .right: parts.append("RIGHT SIDE")
        case .both, .alternating: break
        }
        if case .hold = viewModel.display { parts.append("HOLD") }
        if viewModel.isPaused { parts.append("PAUSED") }
        return parts.joined(separator: " — ")
    }

    private var controls: some View {
        GlassEffectContainer(spacing: 6) {
            HStack(spacing: 6) {
                primaryButton
                Button {
                    Task { await viewModel.skipCurrentSet() }
                } label: {
                    Image(systemName: "arrow.right")
                }
                .buttonStyle(GlassCircleButtonStyle(diameter: 60))
                .accessibilityLabel("Skip to next step")
            }
        }
    }

    @ViewBuilder
    private var primaryButton: some View {
        if case .reps = viewModel.display, !viewModel.isPaused {
            Button {
                Task { await viewModel.completeCurrentSet() }
            } label: {
                primaryLabel("Done", systemImage: "checkmark")
            }
            .buttonStyle(InkGlassButtonStyle())
        } else {
            Button(action: togglePause) {
                primaryLabel(viewModel.isPaused ? "Resume" : "Pause",
                             systemImage: viewModel.isPaused ? "play.fill" : "pause.fill")
            }
            .buttonStyle(InkGlassButtonStyle())
        }
    }

    private func primaryLabel(_ title: String, systemImage: String) -> some View {
        HStack {
            Text(title)
            Spacer()
            Image(systemName: systemImage)
        }
        .font(AppFont.display(17, weight: .semibold))
        .padding(.horizontal, 22)
    }

    private func togglePause() {
        viewModel.isPaused ? viewModel.resume() : viewModel.pause()
    }
}

/// Seconds remaining and the fraction of the field to fill, for the current display.
struct TimerReading: Equatable {
    let display: SessionViewModel.Display
    let remaining: Int
    let total: Int
    let fraction: Double

    init(display: SessionViewModel.Display, startedAt: Date, now: Date) {
        self.display = display
        switch display {
        case .hold(let seconds), .rest(let seconds):
            let left = max(0, Double(seconds) - now.timeIntervalSince(startedAt))
            total = seconds
            remaining = Int(left.rounded(.up))
            fraction = seconds > 0 ? left / Double(seconds) : 0
        case .reps(let count):
            total = count
            remaining = count
            fraction = 0
        case .starting:
            total = 0
            remaining = 0
            fraction = 0
        }
    }
}

/// The block of accent color that drains from the bottom as time runs out.
private struct TimerField: View {
    let fraction: Double
    let color: Color
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Rectangle()
            .fill(color.fieldTone(for: colorScheme))
            .containerRelativeFrame(.vertical) { length, _ in length * 0.55 * CGFloat(fraction) }
            .frame(maxWidth: .infinity)
            .ignoresSafeArea(edges: .bottom)
            .animation(reduceMotion ? nil : .linear(duration: 0.25), value: fraction)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

private struct BigReading: View {
    let reading: TimerReading

    var body: some View {
        HStack(alignment: .lastTextBaseline, spacing: 12) {
            Text("\(reading.remaining)")
                .font(AppFont.display(176, weight: .bold))
                .tracking(-10)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .contentTransition(.numericText(countsDown: true))
            VStack(alignment: .leading, spacing: 4) {
                Text(unit)
                if let suffix {
                    Text(suffix)
                }
            }
            .font(AppFont.mono(12, weight: .medium))
            .tracking(0.7)
        }
        .opacity(reading.display == .starting ? 0 : 1)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    private var unit: String {
        if case .reps = reading.display { return "REPS" }
        return "SEC"
    }

    private var suffix: String? {
        switch reading.display {
        case .hold, .rest: return "OF \(reading.total)"
        case .reps, .starting: return nil
        }
    }

    private var accessibilityText: String {
        switch reading.display {
        case .hold: return "\(reading.remaining) of \(reading.total) seconds left"
        case .rest: return "Rest, \(reading.remaining) seconds left"
        case .reps(let count): return "\(count) reps"
        case .starting: return ""
        }
    }
}

private struct ProgressSegments: View {
    let total: Int
    let current: Int
    let accent: Color

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<max(total, 1), id: \.self) { index in
                Rectangle()
                    .fill(color(for: index))
                    .frame(height: 4)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Exercise \(current + 1) of \(max(total, 1))")
    }

    private func color(for index: Int) -> Color {
        if index < current { return AppColor.ink }
        if index == current { return accent }
        return AppColor.hairline
    }
}
