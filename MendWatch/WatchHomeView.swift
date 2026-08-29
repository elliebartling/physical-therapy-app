import SwiftUI

struct WatchHomeView: View {
    @Environment(WatchStore.self) private var store

    var body: some View {
        NavigationStack {
            Group {
                if store.routines.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "iphone.and.arrow.forward")
                            .font(.title2)
                            .foregroundStyle(.secondary)
                        Text("Import a routine on your iPhone and it will appear here.")
                            .font(.footnote)
                            .multilineTextAlignment(.center)
                            .foregroundStyle(.secondary)
                    }
                    .padding()
                } else {
                    List(store.routines) { routine in
                        NavigationLink {
                            WatchPlayerView(routine: routine)
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(routine.name)
                                    .font(.headline)
                                Text("\(routine.exercises.count) exercises · ~\(Format.duration(routine.estimatedSeconds))")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Mend")
        }
    }
}
