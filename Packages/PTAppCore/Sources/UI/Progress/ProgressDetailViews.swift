import SwiftUI

/// One exercise over time: how often it was done, and every time it came up.
struct ExerciseProgressView: View {
    let viewModel: ProgressViewModel
    let exerciseID: UUID

    var body: some View {
        ScrollView {
            if let row = viewModel.exercise(id: exerciseID) {
                VStack(alignment: .leading, spacing: 0) {
                    ExerciseIllustration(art: row.art)
                    Text(row.name)
                        .font(AppFont.display(30, weight: .bold))
                        .tracking(-1)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(row.prescription)
                        .font(AppFont.mono(13))
                        .foregroundStyle(AppColor.inkSecondary)
                        .padding(.top, 6)
                    SheetHowToView(sections: row.sheetHowTo)
                    figures(row).padding(.top, 24)
                    timeline.padding(.top, 28)
                }
                .padding(.horizontal, AppSpacing.screenPadding)
                .padding(.bottom, AppSpacing.s(3))
            }
        }
        .background(AppColor.surface.ignoresSafeArea())
        .foregroundStyle(AppColor.ink)
        .navigationTitle("Exercise")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func figures(_ row: ProgressViewModel.ExerciseRow) -> some View {
        HStack(alignment: .top, spacing: 0) {
            Figure(value: "\(row.stats.completed)", label: "Done")
            Figure(value: "\(row.stats.skipped)", label: "Skipped")
            Figure(value: row.stats.completionRate.map { $0.formatted(.percent.precision(.fractionLength(0))) } ?? "—",
                   label: "Done when due")
        }
        .overlay(alignment: .top) { InkRule() }
    }

    private var timeline: some View {
        let entries = viewModel.entries(forExercise: exerciseID)
        return VStack(alignment: .leading, spacing: 0) {
            SectionLabel("Every time").padding(.bottom, 6)
            if entries.isEmpty {
                Text("Not done yet.")
                    .font(AppFont.body(15))
                    .foregroundStyle(AppColor.inkSecondary)
                    .padding(.vertical, 12)
            }
            ForEach(entries) { entry in
                HStack {
                    Text(entry.date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)))
                        .font(AppFont.body(15))
                    Spacer()
                    if let rating = entry.rating {
                        Text(rating.title.uppercased())
                            .font(AppFont.mono(11, weight: .medium))
                            .tracking(0.5)
                            .foregroundStyle(AppColor.inkSecondary)
                    }
                    Label(entry.isDone ? "Done" : "Skipped",
                          systemImage: entry.isDone ? "checkmark.circle.fill" : "minus.circle")
                        .font(AppFont.mono(12, weight: .medium))
                        .foregroundStyle(entry.isDone ? AppColor.ink : AppColor.inkSecondary)
                }
                .padding(.vertical, 11)
                .overlay(alignment: .top) { HairlineDivider() }
                .accessibilityElement(children: .combine)
            }
        }
    }
}

private struct Figure: View {
    let value: String
    let label: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value)
                .font(AppFont.display(30, weight: .bold))
                .tracking(-1)
            Text(label.uppercased())
                .font(AppFont.mono(10))
                .tracking(0.6)
                .foregroundStyle(AppColor.inkSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 12)
        .accessibilityElement(children: .combine)
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
