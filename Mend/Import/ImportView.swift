import SwiftUI
import PhotosUI

struct ImportView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var selectedItems: [PhotosPickerItem] = []
    @State private var phase: Phase = .pick

    enum Phase {
        case pick
        case working(String)
        case review(RoutinePayload)
        case failed(String)
    }

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("Import routine")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { dismiss() }
                    }
                }
        }
        .interactiveDismissDisabled(isWorking)
    }

    private var isWorking: Bool {
        if case .working = phase { return true }
        return false
    }

    @ViewBuilder
    private var content: some View {
        switch phase {
        case .pick:
            pickView
        case .working(let status):
            workingView(status)
        case .review(let draft):
            RoutineReviewView(draft: draft) { dismiss() }
        case .failed(let message):
            failedView(message)
        }
    }

    private var pickView: some View {
        VStack(spacing: 24) {
            Spacer()
            Image(systemName: "doc.text.viewfinder")
                .font(.system(size: 56))
                .foregroundStyle(Color.accentColor)
            VStack(spacing: 8) {
                Text("Screenshots in, routine out")
                    .font(.title3.weight(.semibold))
                Text("Pick screenshots or photos of your PT's exercise sheet. Mend reads them with on-device intelligence — nothing leaves your phone.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 24)

            if let warning = RoutineExtractor.availabilityMessage {
                Label(warning, systemImage: "exclamationmark.triangle")
                    .font(.footnote)
                    .foregroundStyle(.orange)
                    .padding(.horizontal, 24)
                    .multilineTextAlignment(.center)
            }

            Spacer()

            VStack(spacing: 12) {
                PhotosPicker(
                    selection: $selectedItems,
                    maxSelectionCount: 6,
                    matching: .images
                ) {
                    Label("Choose screenshots", systemImage: "photo.on.rectangle")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.borderedProminent)
                .disabled(RoutineExtractor.availabilityMessage != nil)

                Button("Enter manually instead") {
                    phase = .review(RoutinePayload(name: "", exercises: [ExercisePayload(name: "")]))
                }
                .font(.subheadline)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 16)
        }
        .onChange(of: selectedItems) { _, items in
            guard !items.isEmpty else { return }
            process(items)
        }
    }

    private func workingView(_ status: String) -> some View {
        VStack(spacing: 20) {
            ProgressView()
                .controlSize(.large)
            Text(status)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func failedView(_ message: String) -> some View {
        ContentUnavailableView {
            Label("Import didn't work", systemImage: "exclamationmark.triangle")
        } description: {
            Text(message)
        } actions: {
            Button("Try again") {
                selectedItems = []
                phase = .pick
            }
            .buttonStyle(.borderedProminent)
            Button("Enter manually") {
                phase = .review(RoutinePayload(name: "", exercises: [ExercisePayload(name: "")]))
            }
        }
    }

    private func process(_ items: [PhotosPickerItem]) {
        phase = .working("Reading screenshots…")
        Task { @MainActor in
            do {
                var pages: [String] = []
                for (index, item) in items.enumerated() {
                    phase = .working("Reading screenshot \(index + 1) of \(items.count)…")
                    guard let data = try await item.loadTransferable(type: Data.self) else { continue }
                    let text = try await OCRService.recognizeText(in: data)
                    if !text.isEmpty {
                        pages.append(text)
                    }
                }
                let combined = pages.joined(separator: "\n\n--- next page ---\n\n")
                guard combined.count > 20 else {
                    throw ExtractionError.noText
                }
                phase = .working("Structuring the routine…")
                let extracted = try await RoutineExtractor.extractRoutine(fromOCRText: combined)
                guard !extracted.exercises.isEmpty else {
                    throw ExtractionError.noText
                }
                phase = .review(extracted.payload)
            } catch {
                phase = .failed(error.localizedDescription)
            }
        }
    }
}
