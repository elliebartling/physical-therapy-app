import SwiftUI
import SwiftData
import UIKit

struct PlayerView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @State private var engine: PlayerEngine
    @State private var showingEndConfirm = false
    @State private var painLevel: Double = 0
    @State private var recordPain = false
    private let haptics = PlayerHaptics()

    init(routine: RoutinePayload) {
        _engine = State(initialValue: PlayerEngine(routine: routine))
    }

    var body: some View {
        NavigationStack {
            Group {
                if engine.isFinished {
                    summaryView
                } else if let step = engine.currentStep {
                    sessionView(step)
                } else {
                    ProgressView()
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if !engine.isFinished {
                    ToolbarItem(placement: .cancellationAction) {
                        Button {
                            showingEndConfirm = true
                        } label: {
                            Image(systemName: "xmark")
                        }
                    }
                }
            }
            .confirmationDialog("End this session?", isPresented: $showingEndConfirm, titleVisibility: .visible) {
                Button("End and save progress", role: .destructive) {
                    engine.endEarly()
                }
                Button("Discard session", role: .destructive) {
                    dismiss()
                }
                Button("Keep going", role: .cancel) {}
            }
        }
        .onAppear {
            engine.onEvent = { event in
                haptics.handle(event)
            }
            engine.start()
            UIApplication.shared.isIdleTimerDisabled = true
        }
        .onDisappear {
            UIApplication.shared.isIdleTimerDisabled = false
        }
    }

    // MARK: - Session

    private func sessionView(_ step: PlayerStep) -> some View {
        VStack(spacing: 0) {
            ProgressView(value: engine.progress)
                .tint(Color.accentColor)
                .padding(.horizontal)

            Spacer()

            VStack(spacing: 8) {
                Text(step.title)
                    .font(.largeTitle.bold())
                    .multilineTextAlignment(.center)
                Text(step.subtitle)
                    .font(.headline)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 24)

            Spacer()

            stepGoal(step)

            Spacer()

            if step.kind == .work, let details = step.exercise.details, !details.isEmpty {
                Text(details)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(4)
                    .padding(.horizontal, 32)
                Spacer()
            }

            controls(step)
                .padding(.horizontal, 24)
                .padding(.bottom, 12)
        }
    }

    @ViewBuilder
    private func stepGoal(_ step: PlayerStep) -> some View {
        switch step.goal {
        case .timed(let total):
            ZStack {
                TimerRing(
                    progress: Double(engine.remainingSeconds) / Double(max(1, total)),
                    lineWidth: 14
                )
                VStack(spacing: 4) {
                    Text(Format.clock(engine.remainingSeconds))
                        .font(.system(size: 64, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .contentTransition(.numericText(countsDown: true))
                    if engine.isPaused {
                        Text("Paused")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .frame(width: 250, height: 250)
        case .reps(let count):
            VStack(spacing: 0) {
                Text("\(count)")
                    .font(.system(size: 96, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                Text("reps")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func controls(_ step: PlayerStep) -> some View {
        HStack(spacing: 12) {
            switch step.goal {
            case .timed:
                Button {
                    engine.togglePause()
                } label: {
                    Label(engine.isPaused ? "Resume" : "Pause", systemImage: engine.isPaused ? "play.fill" : "pause.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            case .reps:
                Button {
                    engine.completeCurrentStep()
                } label: {
                    Label("Done", systemImage: "checkmark")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
            }

            Button {
                engine.skipCurrentStep()
            } label: {
                Image(systemName: "forward.end.fill")
                    .padding(.horizontal, 8)
            }
            .buttonStyle(.bordered)
        }
        .controlSize(.large)
    }

    // MARK: - Summary

    private var summaryView: some View {
        let payload = engine.results(source: "phone")
        let completed = payload.exercises.filter { !$0.skipped }.count

        return VStack(spacing: 28) {
            Spacer()
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 64))
                .foregroundStyle(Color.accentColor)
            VStack(spacing: 8) {
                Text("Session complete")
                    .font(.title2.weight(.semibold))
                Text("\(completed) of \(payload.exercises.count) exercises · \(Format.duration(Int(Date.now.timeIntervalSince(engine.startedAt))))")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            VStack(spacing: 12) {
                Toggle("Record pain level", isOn: $recordPain.animation())
                if recordPain {
                    VStack(spacing: 4) {
                        Slider(value: $painLevel, in: 0...10, step: 1)
                        Text("Pain: \(Int(painLevel)) / 10")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(20)
            .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 16))
            .padding(.horizontal, 24)

            Spacer()

            Button {
                saveSession()
            } label: {
                Label("Save session", systemImage: "heart.fill")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .padding(.horizontal, 24)
            .padding(.bottom, 16)
        }
    }

    private func saveSession() {
        let payload = engine.results(source: "phone")
        let log = SessionLog(from: payload, painLevel: recordPain ? Int(painLevel) : nil)
        context.insert(log)
        try? context.save()

        Task { @MainActor in
            do {
                try await HealthKitManager.shared.saveWorkout(
                    start: payload.startedAt,
                    end: payload.endedAt,
                    routineName: payload.routineName
                )
                log.savedToHealthKit = true
                try? context.save()
            } catch {
                // Session is still recorded locally; HealthKit can be retried later.
            }
        }
        dismiss()
    }
}

@MainActor
final class PlayerHaptics {
    private let notification = UINotificationFeedbackGenerator()
    private let impact = UIImpactFeedbackGenerator(style: .medium)

    func handle(_ event: PlayerEvent) {
        switch event {
        case .stepStarted:
            impact.impactOccurred()
        case .countdownWarning:
            notification.notificationOccurred(.warning)
        case .stepCompleted, .finished:
            notification.notificationOccurred(.success)
        case .tick:
            break
        }
    }
}
