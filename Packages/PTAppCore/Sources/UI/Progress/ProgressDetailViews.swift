import SwiftUI
import HistoryKit

/// One exercise over time: anything worth raising, how it felt, what was prescribed
/// in each phase, and every time it came up.
struct ExerciseProgressView: View {
    let viewModel: ProgressViewModel
    let exerciseID: UUID

    var body: some View {
        ScrollView {
            if let row = viewModel.exercise(id: exerciseID) {
                content(row)
                    .padding(.horizontal, AppSpacing.screenPadding)
                    .padding(.bottom, AppSpacing.s(3))
            }
        }
        .background(AppColor.surface.ignoresSafeArea())
        .foregroundStyle(AppColor.ink)
        .navigationTitle("Exercise")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func content(_ row: ProgressViewModel.ExerciseRow) -> some View {
        let phases = viewModel.phases(forExercise: exerciseID)
        let showsPhases = phases.count > 1
        return VStack(alignment: .leading, spacing: 0) {
            ExerciseIllustration(art: row.art)
            Text(row.name)
                .font(AppFont.display(30, weight: .bold))
                .tracking(-1)
                .fixedSize(horizontal: false, vertical: true)
            Text(showsPhases ? "\(row.prescription) — PHASE \(phases.count)" : row.prescription)
                .font(AppFont.mono(13))
                .foregroundStyle(AppColor.inkSecondary)
                .padding(.top, 6)
            if let insight = viewModel.insight(forExercise: exerciseID) {
                InsightCard(insight: Self.retitled(insight)).padding(.top, 18)
            }
            SheetHowToView(sections: row.sheetHowTo)
            figures(row).padding(.top, 24)
            feel.padding(.top, 32)
            if showsPhases {
                PhaseList(phases: phases).padding(.top, 32)
            }
            timeline(number: showsPhases ? "03" : "02", showsPrescription: showsPhases).padding(.top, 32)
        }
    }

    /// On the exercise's own page the card names the trend, not the exercise.
    private static func retitled(_ insight: ProgressViewModel.Insight) -> ProgressViewModel.Insight {
        let title = insight.title.components(separatedBy: " — ").last ?? insight.title
        return ProgressViewModel.Insight(id: insight.id, title: title, detail: insight.detail,
                                         exerciseID: insight.exerciseID)
    }

    private func figures(_ row: ProgressViewModel.ExerciseRow) -> some View {
        HStack(alignment: .top, spacing: 12) {
            ProgressFigure(value: "\(row.stats.completed)", label: "Done")
            ProgressFigure(value: "\(row.stats.skipped)", label: "Skipped")
            ProgressFigure(value: row.stats.completionRate.map { $0.formatted(.percent.precision(.fractionLength(0))) } ?? "—",
                           label: "Done when due")
        }
        .overlay(alignment: .top) { InkRule() }
    }

    private var feel: some View {
        let marks = viewModel.marks(forExercise: exerciseID, count: 12)
        return VStack(alignment: .leading, spacing: 0) {
            ProgressSectionHeader(title: "01 — How it felt", trailing: marks.isEmpty ? nil : "Last \(marks.count)")
            if marks.isEmpty {
                Text("Not done yet.")
                    .font(AppFont.body(15))
                    .foregroundStyle(AppColor.inkSecondary)
            } else {
                MarkStrip(marks: marks)
                RatingLegend(showsMarks: true).padding(.top, 12)
            }
        }
    }

    private func timeline(number: String, showsPrescription: Bool) -> some View {
        let entries = viewModel.entries(forExercise: exerciseID)
        return VStack(alignment: .leading, spacing: 0) {
            ProgressSectionHeader(title: "\(number) — Every time")
            if entries.isEmpty {
                Text("Not done yet.")
                    .font(AppFont.body(15))
                    .foregroundStyle(AppColor.inkSecondary)
                    .padding(.vertical, 12)
            }
            ForEach(entries) { entry in
                EntryRow(entry: entry, showsPrescription: showsPrescription)
            }
        }
    }
}

/// What the PT prescribed in each phase.
private struct PhaseList: View {
    let phases: [ProgressViewModel.Phase]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ProgressSectionHeader(title: "02 — What your PT prescribed", trailing: "\(phases.count) phases")
            ForEach(phases) { phase in
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("PHASE \(phase.number)")
                            .font(AppFont.mono(11, weight: .medium))
                            .tracking(0.6)
                        Text(dates(phase))
                            .font(AppFont.mono(11))
                            .tracking(0.4)
                            .foregroundStyle(AppColor.inkSecondary)
                    }
                    Spacer(minLength: 8)
                    Text(phase.prescription)
                        .font(AppFont.display(17, weight: .medium))
                }
                .padding(.vertical, 11)
                .overlay(alignment: .top) { HairlineDivider() }
                .accessibilityElement(children: .combine)
            }
        }
    }

    private func dates(_ phase: ProgressViewModel.Phase) -> String {
        let start = phase.start.formatted(.dateTime.month(.abbreviated).day()).uppercased()
        guard let end = phase.end else { return "\(start) – NOW" }
        return "\(start) – \(end.formatted(.dateTime.month(.abbreviated).day()).uppercased())"
    }
}

/// One time an exercise came up.
private struct EntryRow: View {
    let entry: ProgressViewModel.ExerciseEntry
    let showsPrescription: Bool

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()))
                    .font(AppFont.body(15))
                if showsPrescription, let prescription = entry.prescription {
                    Text(prescription)
                        .font(AppFont.mono(11))
                        .foregroundStyle(AppColor.inkSecondary)
                }
            }
            Spacer(minLength: 8)
            Text(status.uppercased())
                .font(AppFont.mono(11, weight: .medium))
                .tracking(0.5)
                .foregroundStyle(entry.isDone ? AppColor.ink : AppColor.inkSecondary)
            MarkSquare(mark: entry.mark)
                .accessibilityHidden(true)
        }
        .padding(.vertical, 11)
        .overlay(alignment: .top) { HairlineDivider() }
        .accessibilityElement(children: .combine)
    }

    private var status: String {
        guard entry.isDone else { return "Skipped" }
        return entry.rating?.title ?? "Done"
    }
}

/// Every session, by month, newest first.
struct AllSessionsView: View {
    let viewModel: ProgressViewModel

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(viewModel.months) { month in
                    Text(month.title.uppercased())
                        .font(AppFont.mono(11, weight: .medium))
                        .tracking(0.7)
                        .foregroundStyle(AppColor.inkSecondary)
                        .padding(.top, 18)
                        .padding(.bottom, 4)
                        .accessibilityAddTraits(.isHeader)
                    ForEach(month.sessions) { session in
                        NavigationLink(value: ProgressScreen.Route.session(session.id)) {
                            SessionHistoryRow(row: session)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(.horizontal, AppSpacing.screenPadding)
            .padding(.bottom, AppSpacing.s(3))
        }
        .background(AppColor.surface.ignoresSafeArea())
        .foregroundStyle(AppColor.ink)
        .navigationTitle("All sessions")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct SessionHistoryRow: View {
    let row: ProgressViewModel.SessionRow

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(row.date.formatted(.dateTime.weekday(.abbreviated).day()).uppercased())
                .font(AppFont.mono(12, weight: .medium))
                .frame(width: 64, alignment: .leading)
            VStack(alignment: .leading, spacing: 3) {
                Text(row.isComplete ? "Complete" : "Partial")
                    .font(AppFont.display(16, weight: .medium))
                Text(detail)
                    .font(AppFont.mono(11))
                    .tracking(0.4)
                    .foregroundStyle(AppColor.inkSecondary)
            }
            Spacer(minLength: 8)
            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(AppColor.inkSecondary)
                .accessibilityHidden(true)
        }
        .padding(.vertical, 12)
        .contentShape(Rectangle())
        .overlay(alignment: .top) { HairlineDivider() }
        .accessibilityElement(children: .combine)
    }

    private var detail: String {
        var parts = [row.doneCount == 1 ? "1 EXERCISE" : "\(row.doneCount) EXERCISES"]
        parts.append(row.minutes.map { "\($0) MIN" } ?? "LOGGED")
        if let pain = row.painLevel { parts.append("PAIN \(pain)") }
        return parts.joined(separator: " — ")
    }
}

/// A plain-text summary to share with a PT or keep open at the visit.
struct VisitSummaryView: View {
    let summary: String
    let rangeTitle: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Covers \(rangeTitle.lowercased()). Change the range on Progress to cover more or less.")
                        .font(AppFont.body(15))
                        .foregroundStyle(AppColor.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(summary)
                        .font(AppFont.body(15))
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(16)
                        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 18))
                }
                .padding(.horizontal, AppSpacing.screenPadding)
                .padding(.vertical, AppSpacing.s(1))
            }
            .background(AppColor.surface.ignoresSafeArea())
            .foregroundStyle(AppColor.ink)
            .navigationTitle("For your visit")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    ShareLink(item: summary) {
                        Label("Share", systemImage: "square.and.arrow.up")
                    }
                }
            }
        }
    }
}

/// One session: what was done and skipped, and a way to delete it if it was logged by mistake.
struct SessionDetailView: View {
    let viewModel: ProgressViewModel
    let sessionID: UUID

    @State private var confirmingDelete = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            if let row = viewModel.session(id: sessionID) {
                VStack(alignment: .leading, spacing: 0) {
                    Text(row.date.formatted(.dateTime.weekday(.wide).day().month(.wide)))
                        .font(AppFont.display(30, weight: .bold))
                        .tracking(-1)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(summary(row))
                        .font(AppFont.mono(12))
                        .tracking(0.4)
                        .foregroundStyle(AppColor.inkSecondary)
                        .padding(.top, 6)
                    exercises(row).padding(.top, 24)
                    if row.painLevel != nil || row.note != nil {
                        notes(row).padding(.top, 24)
                    }
                    deleteButton.padding(.top, 32)
                }
                .padding(.horizontal, AppSpacing.screenPadding)
                .padding(.bottom, AppSpacing.s(3))
            }
        }
        .background(AppColor.surface.ignoresSafeArea())
        .foregroundStyle(AppColor.ink)
        .navigationTitle("Session")
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog("Delete this session?", isPresented: $confirmingDelete, titleVisibility: .visible) {
            Button("Delete session", role: .destructive) {
                if viewModel.deleteSession(id: sessionID) { dismiss() }
            }
            Button("Keep it", role: .cancel) {}
        } message: {
            Text("It's removed from your history and streak. A copy already saved to Apple Health stays there.")
        }
    }

    private func summary(_ row: ProgressViewModel.SessionRow) -> String {
        let status = row.isComplete ? "COMPLETE" : "PARTIAL"
        guard let minutes = row.minutes else { return "\(status) — LOGGED" }
        return "\(status) — \(minutes) MIN"
    }

    private func exercises(_ row: ProgressViewModel.SessionRow) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            InkRule()
            ForEach(row.items) { item in
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Image(systemName: item.isDone ? "checkmark.circle.fill" : "minus.circle")
                        .foregroundStyle(item.isDone ? AppColor.ink : AppColor.inkSecondary)
                        .accessibilityHidden(true)
                    Text(item.name)
                        .font(AppFont.display(16, weight: .medium))
                        .foregroundStyle(item.isDone ? AppColor.ink : AppColor.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 8)
                    if let rating = item.rating {
                        Text(rating.title.uppercased())
                            .font(AppFont.mono(11, weight: .medium))
                            .tracking(0.5)
                            .foregroundStyle(AppColor.inkSecondary)
                    }
                }
                .padding(.vertical, 11)
                .overlay(alignment: .top) { HairlineDivider() }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel([item.name, item.isDone ? "done" : "skipped", item.rating?.title]
                    .compactMap { $0 }.joined(separator: ", "))
            }
        }
    }

    private func notes(_ row: ProgressViewModel.SessionRow) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            InkRule()
            if let pain = row.painLevel {
                HStack {
                    SectionLabel("Pain")
                    Spacer()
                    Text("\(pain) / 10")
                        .font(AppFont.mono(13, weight: .medium))
                }
                .padding(.top, 10)
                .accessibilityElement(children: .combine)
            }
            if let note = row.note {
                SectionLabel("Note").padding(.top, 10)
                Text(note)
                    .font(AppFont.body(15))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var deleteButton: some View {
        Button(role: .destructive) {
            confirmingDelete = true
        } label: {
            Label("Delete session", systemImage: "trash")
                .font(AppFont.display(16, weight: .semibold))
                .frame(minHeight: 44)
        }
        .buttonStyle(.plain)
        .foregroundStyle(.red)
    }
}
