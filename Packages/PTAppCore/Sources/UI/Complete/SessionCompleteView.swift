import SwiftUI

public struct SessionCompleteView: View {
    public let newStreak: Int
    public let onDone: () -> Void

    @State private var summary: SessionSummaryViewModel?
    @State private var appeared = false
    @Environment(\.appAccent) private var accent
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// `summary` adds optional catch-up ratings, pain and a note; nil shows just the celebration.
    public init(newStreak: Int, summary: SessionSummaryViewModel? = nil, onDone: @escaping () -> Void) {
        self.newStreak = newStreak
        self._summary = State(initialValue: summary)
        self.onDone = onDone
    }

    public var body: some View {
        ZStack(alignment: .bottom) {
            AppColor.surface.ignoresSafeArea()
            // With the ratings list the field would cut across its rows, so it shows only
            // behind the plain celebration.
            if summary == nil { completionField }
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    header
                    Text("Nice work.")
                        .font(AppFont.display(56, weight: .bold))
                        .tracking(-2.4)
                        .padding(.top, 26)
                    streak.padding(.top, summary == nil ? 120 : 20)
                    if let summary {
                        SessionSummaryForm(viewModel: summary).padding(.top, 28)
                    }
                }
                .padding(.horizontal, AppSpacing.screenPadding)
                .padding(.bottom, AppSpacing.s(2))
            }
            .scrollIndicators(.hidden)
            .safeAreaInset(edge: .bottom) {
                doneButton
                    .padding(.horizontal, AppSpacing.screenPadding)
                    .padding(.bottom, AppSpacing.s(1))
            }
        }
        .foregroundStyle(AppColor.ink)
        .onAppear { appeared = true }
        .alert("Couldn't save",
               isPresented: Binding(get: { summary?.errorMessage != nil },
                                    set: { if !$0 { summary?.dismissError() } }),
               presenting: summary?.errorMessage) { _ in
            Button("OK", role: .cancel) {}
        } message: { Text($0) }
    }

    private var header: some View {
        VStack(spacing: 10) {
            HStack {
                SectionLabel("Session complete")
                Spacer()
            }
            InkRule(weight: 2)
        }
        .padding(.top, AppSpacing.s(1))
    }

    /// The timer field filling back up: the visual "done".
    private var completionField: some View {
        Rectangle()
            .fill(accent.fieldTone(for: colorScheme))
            .containerRelativeFrame(.vertical) { length, _ in length * (appeared ? 0.5 : 0) }
            .frame(maxWidth: .infinity)
            .ignoresSafeArea(edges: .bottom)
            .animation(reduceMotion ? nil : .smooth(duration: 0.6), value: appeared)
            .accessibilityHidden(true)
    }

    private var streak: some View {
        HStack(alignment: .lastTextBaseline, spacing: 12) {
            Text("\(newStreak)")
                .font(AppFont.display(summary == nil ? 176 : 96, weight: .bold))
                .tracking(summary == nil ? -10 : -5)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .scaleEffect(appeared || reduceMotion ? 1 : 0.6, anchor: .bottomLeading)
                .animation(.snappy(duration: 0.4), value: appeared)
            Text("DAY\nSTREAK")
                .font(AppFont.mono(12, weight: .medium))
                .tracking(0.7)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(newStreak)-day streak")
    }

    private var doneButton: some View {
        Button {
            if summary?.save() ?? true { onDone() }
        } label: {
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
}

/// Catch-up ratings, pain and a note. All optional; saved with Done.
private struct SessionSummaryForm: View {
    @Bindable var viewModel: SessionSummaryViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if viewModel.showsRatings {
                ratings.padding(.bottom, 28)
            }
            pain.padding(.bottom, 28)
            noteField
        }
    }

    private var ratings: some View {
        VStack(alignment: .leading, spacing: 0) {
            InkRule()
            SectionLabel("How did each feel?").padding(.vertical, 10)
            ForEach($viewModel.items) { $item in
                VStack(alignment: .leading, spacing: 8) {
                    Text(item.name)
                        .font(AppFont.display(16, weight: .medium))
                        .fixedSize(horizontal: false, vertical: true)
                    RatingChips(selection: item.rating) { item.rating = $0 }
                }
                .padding(.vertical, 12)
                .overlay(alignment: .top) { HairlineDivider() }
            }
        }
    }

    private var pain: some View {
        VStack(alignment: .leading, spacing: 8) {
            InkRule()
            HStack(alignment: .firstTextBaseline) {
                SectionLabel("Pain, 0–10")
                Spacer()
                Text(viewModel.painLevel.map(String.init) ?? "Not recorded")
                    .font(AppFont.mono(13, weight: .medium))
                    .monospacedDigit()
                if viewModel.painLevel != nil {
                    Button("Clear") { viewModel.painLevel = nil }
                        .font(AppFont.display(14, weight: .semibold))
                        .frame(minHeight: 44)
                        .buttonStyle(.plain)
                        .underline()
                }
            }
            .padding(.top, 10)
            Slider(
                value: Binding(get: { Double(viewModel.painLevel ?? 0) },
                               set: { viewModel.painLevel = Int($0.rounded()) }),
                in: 0...10, step: 1
            ) {
                Text("Pain")
            } minimumValueLabel: {
                Text("0").font(AppFont.mono(11))
            } maximumValueLabel: {
                Text("10").font(AppFont.mono(11))
            }
            .tint(AppColor.ink)
            .accessibilityValue(viewModel.painLevel.map { "\($0) out of 10" } ?? "Not recorded")
        }
    }

    private var noteField: some View {
        VStack(alignment: .leading, spacing: 10) {
            InkRule()
            SectionLabel("Note").padding(.top, 10)
            TextField("Anything to tell your PT?", text: $viewModel.note, axis: .vertical)
                .font(AppFont.body(16))
                .lineLimit(2...6)
                .padding(14)
                .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 18))
        }
    }
}
