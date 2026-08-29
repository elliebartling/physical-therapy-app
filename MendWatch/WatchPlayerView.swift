import SwiftUI
import WatchKit

struct WatchPlayerView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(WatchStore.self) private var store
    @State private var engine: PlayerEngine
    @State private var workout = WatchWorkoutManager()
    @State private var started = false
    @State private var saved = false

    init(routine: RoutinePayload) {
        _engine = State(initialValue: PlayerEngine(routine: routine))
    }

    var body: some View {
        Group {
            if engine.isFinished {
                summaryView
            } else if let step = engine.currentStep {
                stepView(step)
            } else {
                ProgressView()
            }
        }
        .navigationBarBackButtonHidden(started && !engine.isFinished)
        .onAppear {
            guard !started else { return }
            started = true
            engine.onEvent = { event in
                switch event {
                case .stepStarted:
                    WKInterfaceDevice.current().play(.directionUp)
                case .countdownWarning:
                    WKInterfaceDevice.current().play(.click)
                case .stepCompleted:
                    WKInterfaceDevice.current().play(.success)
                case .finished:
                    WKInterfaceDevice.current().play(.notification)
                case .tick:
                    break
                }
            }
            Task { await workout.start() }
            engine.start()
        }
    }

    private func stepView(_ step: PlayerStep) -> some View {
        VStack(spacing: 6) {
            Text(step.title)
                .font(.headline)
                .lineLimit(2)
                .multilineTextAlignment(.center)
            Text(step.subtitle)
                .font(.caption2)
                .foregroundStyle(.secondary)

            switch step.goal {
            case .timed(let total):
                ZStack {
                    TimerRing(
                        progress: Double(engine.remainingSeconds) / Double(max(1, total)),
                        lineWidth: 6
                    )
                    Text(Format.clock(engine.remainingSeconds))
                        .font(.system(size: 28, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                }
                .frame(width: 84, height: 84)
                .onTapGesture {
                    engine.togglePause()
                    WKInterfaceDevice.current().play(.click)
                }
            case .reps(let count):
                Text("\(count) reps")
                    .font(.system(size: 26, weight: .semibold, design: .rounded))
                    .padding(.vertical, 8)
            }

            HStack(spacing: 8) {
                if case .reps = step.goal {
                    Button {
                        engine.completeCurrentStep()
                    } label: {
                        Image(systemName: "checkmark")
                    }
                    .buttonStyle(.borderedProminent)
                } else if engine.isPaused {
                    Button {
                        engine.togglePause()
                    } label: {
                        Image(systemName: "play.fill")
                    }
                    .buttonStyle(.borderedProminent)
                }
                Button {
                    engine.skipCurrentStep()
                } label: {
                    Image(systemName: "forward.end.fill")
                }
                .buttonStyle(.bordered)
            }
            .controlSize(.small)

            if workout.heartRate > 0 {
                Label("\(Int(workout.heartRate))", systemImage: "heart.fill")
                    .font(.caption2)
                    .foregroundStyle(.red)
            }
        }
        .padding(.horizontal, 4)
    }

    private var summaryView: some View {
        VStack(spacing: 10) {
            Image(systemName: "checkmark.circle.fill")
                .font(.title)
                .foregroundStyle(.green)
            Text("Session complete")
                .font(.headline)
            Text(Format.duration(Int(Date.now.timeIntervalSince(engine.startedAt))))
                .font(.caption)
                .foregroundStyle(.secondary)
            Button(saved ? "Saved" : "Save & finish") {
                finishAndSave()
            }
            .buttonStyle(.borderedProminent)
            .disabled(saved)
        }
    }

    private func finishAndSave() {
        saved = true
        let payload = engine.results(source: "watch")
        Task {
            await workout.end()
            store.sendCompleted(payload)
            dismiss()
        }
    }
}
