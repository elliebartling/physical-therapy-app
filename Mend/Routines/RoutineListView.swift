import SwiftUI
import SwiftData

struct RoutineListView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Routine.createdAt, order: .reverse) private var routines: [Routine]
    @State private var showingImport = false
    @State private var creatingManually = false

    var body: some View {
        NavigationStack {
            List {
                ForEach(routines) { routine in
                    NavigationLink {
                        RoutineDetailView(routine: routine)
                    } label: {
                        row(routine)
                    }
                }
                .onDelete(perform: delete)
            }
            .overlay {
                if routines.isEmpty {
                    ContentUnavailableView {
                        Label("No routines", systemImage: "doc.text.viewfinder")
                    } description: {
                        Text("Import a screenshot of your PT sheet to get started.")
                    } actions: {
                        Button("Import screenshots") { showingImport = true }
                            .buttonStyle(.borderedProminent)
                    }
                }
            }
            .navigationTitle("Routines")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button {
                            showingImport = true
                        } label: {
                            Label("Import from screenshots", systemImage: "doc.text.viewfinder")
                        }
                        Button {
                            creatingManually = true
                        } label: {
                            Label("New empty routine", systemImage: "square.and.pencil")
                        }
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $showingImport) {
                ImportView()
            }
            .sheet(isPresented: $creatingManually) {
                NavigationStack {
                    RoutineReviewView(
                        draft: RoutinePayload(name: "", exercises: [ExercisePayload(name: "")])
                    ) {
                        creatingManually = false
                    }
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Cancel") { creatingManually = false }
                        }
                    }
                }
            }
        }
    }

    private func row(_ routine: Routine) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(routine.name)
                    .font(.headline)
                Text("\(routine.exercises.count) exercises · \(routine.daysPerWeek)×/week")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if routine.isActive {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(Color.accentColor)
            }
        }
    }

    private func delete(at offsets: IndexSet) {
        for index in offsets {
            context.delete(routines[index])
        }
        try? context.save()
        PhoneConnectivity.shared.pushAllRoutines()
    }
}
