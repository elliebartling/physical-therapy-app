import ActivityKit
import AppIntents
import LiveSession
import SwiftUI
import WidgetKit

@main
struct MendWidgetsBundle: WidgetBundle {
    var body: some Widget {
        SessionLiveActivity()
    }
}

/// A guided session on the Lock Screen and in the Dynamic Island: what's happening,
/// the countdown, and Pause and Next.
struct SessionLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: SessionActivityAttributes.self) { context in
            LockScreenView(context: context)
                .activityBackgroundTint(Color(.systemBackground).opacity(0.9))
                .activitySystemActionForegroundColor(.primary)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Text(context.state.title)
                        .font(.headline)
                        .lineLimit(2)
                        .padding(.leading, 4)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Countdown(state: context.state)
                        .font(.title2.weight(.bold).monospacedDigit())
                        .foregroundStyle(accent(context))
                        .padding(.trailing, 4)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    HStack(spacing: 12) {
                        Text(context.state.detail)
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        Spacer()
                        Controls(state: context.state)
                    }
                    .padding(.horizontal, 4)
                }
            } compactLeading: {
                Image(systemName: context.state.isPaused ? "pause.fill" : "figure.cooldown")
                    .foregroundStyle(accent(context))
            } compactTrailing: {
                Countdown(state: context.state)
                    .font(.caption.weight(.semibold).monospacedDigit())
                    .frame(maxWidth: 52)
            } minimal: {
                Countdown(state: context.state)
                    .font(.caption2.weight(.semibold).monospacedDigit())
                    .foregroundStyle(accent(context))
            }
        }
    }

    private func accent(_ context: ActivityViewContext<SessionActivityAttributes>) -> Color {
        Color(hex: context.attributes.accentHex)
    }
}

private struct LockScreenView: View {
    let context: ActivityViewContext<SessionActivityAttributes>

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(context.attributes.routineName.uppercased())
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
                Spacer()
                if context.state.isPaused {
                    Text("PAUSED")
                        .font(.caption2.monospaced().weight(.semibold))
                }
            }
            HStack(alignment: .lastTextBaseline, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(context.state.title)
                        .font(.title3.weight(.bold))
                        .lineLimit(2)
                    Text(context.state.detail)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                Countdown(state: context.state)
                    .font(.system(size: 40, weight: .bold).monospacedDigit())
            }
            ProgressView(value: context.state.progress)
                .tint(Color(hex: context.attributes.accentHex))
            Controls(state: context.state)
        }
        .padding(16)
    }
}

/// Seconds left (ticking on its own while running), reps, or nothing to count.
private struct Countdown: View {
    let state: SessionActivityAttributes.ContentState

    var body: some View {
        if let remaining = state.remainingSeconds {
            Text(Self.clock(remaining))
        } else if let endsAt = state.endsAt {
            Text(timerInterval: Date.now...max(endsAt, Date.now), countsDown: true)
                .multilineTextAlignment(.trailing)
        } else if let reps = state.reps {
            Text("\(reps)×")
        } else {
            Text("—")
        }
    }

    static func clock(_ seconds: Int) -> String {
        String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}

/// Pause or resume, and the next step.
private struct Controls: View {
    let state: SessionActivityAttributes.ContentState

    var body: some View {
        HStack(spacing: 10) {
            Button(intent: ToggleSessionPauseIntent()) {
                Label(state.isPaused ? "Resume" : "Pause",
                      systemImage: state.isPaused ? "play.fill" : "pause.fill")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity, minHeight: 36)
            }
            .buttonStyle(.bordered)
            Button(intent: NextSessionStepIntent()) {
                Label(state.reps != nil ? "Done" : "Next",
                      systemImage: state.reps != nil ? "checkmark" : "forward.fill")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity, minHeight: 36)
            }
            .buttonStyle(.borderedProminent)
        }
        .tint(.primary)
    }
}

private extension Color {
    init(hex: UInt32) {
        self.init(red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255)
    }
}
