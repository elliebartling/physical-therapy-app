import SwiftUI
import Observation
import DataKit
import HistoryKit

/// An exercise another workout can stand in for, named by its lineage so the choice
/// carries over to a new sheet from the PT.
public struct CoverableExercise: Identifiable, Equatable, Sendable {
    public let lineage: UUID
    public let name: String
    public var id: UUID { lineage }

    public init(lineage: UUID, name: String) {
        self.lineage = lineage
        self.name = name
    }

    static func all(in routine: Routine?) -> [CoverableExercise] {
        routine?.orderedExercises.map { CoverableExercise(lineage: $0.lineageID, name: $0.name) } ?? []
    }
}

/// What one kind of workout covers. Every change is saved as it's made.
@MainActor
@Observable
public final class CoverageRuleEditorModel {
    public let activity: WorkoutActivity
    public let exercises: [CoverableExercise]
    public private(set) var rule: CoverageRule
    public private(set) var isSaved: Bool
    private let source: OtherWorkoutsSource

    public init(activity: WorkoutActivity, exercises: [CoverableExercise], source: OtherWorkoutsSource) {
        self.activity = activity
        self.exercises = exercises
        self.source = source
        let saved = source.rule(for: activity.id)
        self.rule = saved ?? CoverageRule(activity: activity)
        self.isSaved = saved != nil
    }

    public func covers(_ exercise: CoverableExercise) -> Bool {
        rule.exerciseLineages.contains(exercise.lineage)
    }

    public func toggle(_ exercise: CoverableExercise) {
        if covers(exercise) {
            rule.exerciseLineages.remove(exercise.lineage)
        } else {
            rule.exerciseLineages.insert(exercise.lineage)
        }
        save()
    }

    public var minimumMinutes: Int {
        get { rule.minimumMinutes }
        set { rule.minimumMinutes = min(max(newValue, 5), 180); save() }
    }

    public var asksFirst: Bool {
        get { rule.asksFirst }
        set { rule.asksFirst = newValue; save() }
    }

    /// Stops this kind of workout counting for anything.
    public func remove() {
        source.removeRule(for: activity.id)
        rule = CoverageRule(activity: activity)
        isSaved = false
    }

    private func save() {
        source.save(rule)
        isSaved = true
    }
}

/// Pick the exercises a kind of workout covers, how long it must be, and whether to ask first.
struct CoverageRuleEditor: View {
    @State private var model: CoverageRuleEditorModel
    @Environment(\.dismiss) private var dismiss

    init(model: CoverageRuleEditorModel) {
        _model = State(initialValue: model)
    }

    var body: some View {
        Form {
            Section {
                Text("Pick the exercises a \(model.activity.name.lowercased()) workout covers. Check with your PT if you're not sure: some exercises only help when they're done exactly as prescribed.")
                    .font(AppFont.body(15))
                    .foregroundStyle(AppColor.inkSecondary)
            }
            Section("Covers") {
                if model.exercises.isEmpty {
                    Text("Set up a routine first.")
                        .foregroundStyle(AppColor.inkSecondary)
                }
                ForEach(model.exercises) { exercise in
                    Button {
                        model.toggle(exercise)
                    } label: {
                        HStack {
                            Text(exercise.name)
                                .foregroundStyle(AppColor.ink)
                            Spacer()
                            if model.covers(exercise) {
                                Image(systemName: "checkmark")
                                    .font(.body.weight(.semibold))
                                    .foregroundStyle(AppColor.ink)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .accessibilityAddTraits(model.covers(exercise) ? .isSelected : [])
                }
            }
            Section {
                Stepper("At least \(model.minimumMinutes) min", value: $model.minimumMinutes, in: 5...180, step: 5)
                Toggle("Ask before counting", isOn: $model.asksFirst)
            } header: {
                Text("When")
            } footer: {
                Text(model.asksFirst
                     ? "Today offers to count it when one shows up in Apple Health."
                     : "Counted as soon as one shows up in Apple Health.")
            }
            if model.isSaved {
                Section {
                    Button("Stop counting \(model.activity.name.lowercased())", role: .destructive) {
                        model.remove()
                        dismiss()
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(AppColor.surface)
        .navigationTitle(model.activity.name)
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// Every kind of workout set to count toward the routine, and a way to add another.
struct CoverageRulesView: View {
    let source: OtherWorkoutsSource
    let exercises: [CoverableExercise]
    @State private var rules: [CoverageRule] = []
    @State private var adding: WorkoutActivity?

    var body: some View {
        Form {
            Section {
                ForEach(rules) { rule in
                    NavigationLink {
                        CoverageRuleEditor(model: CoverageRuleEditorModel(activity: rule.activity, exercises: exercises,
                                                                          source: source))
                    } label: {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(rule.activity.name)
                            Text(summary(of: rule))
                                .font(.footnote)
                                .foregroundStyle(AppColor.inkSecondary)
                        }
                    }
                }
                Menu {
                    ForEach(WorkoutActivity.catalog.filter { activity in !rules.contains { $0.activity.id == activity.id } }) { activity in
                        Button(activity.name) { adding = activity }
                    }
                } label: {
                    Label("Add a workout type", systemImage: "plus")
                }
            } footer: {
                Text("When one of these shows up in Apple Health, Today offers to count those exercises as done. Covered exercises show as covered, so your PT can tell.")
            }
        }
        .scrollContentBackground(.hidden)
        .background(AppColor.surface)
        .navigationTitle("Counts toward your routine")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(item: $adding) { activity in
            CoverageRuleEditor(model: CoverageRuleEditorModel(activity: activity, exercises: exercises, source: source))
        }
        .onAppear { rules = source.rules }
    }

    private func summary(of rule: CoverageRule) -> String {
        let count = exercises.filter { rule.exerciseLineages.contains($0.lineage) }.count
        guard count > 0 else { return "Covers nothing yet" }
        return "Covers \(count) \(count == 1 ? "exercise" : "exercises") — \(rule.minimumMinutes) min or more"
    }
}
