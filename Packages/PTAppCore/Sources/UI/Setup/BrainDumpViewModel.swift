import Foundation
import Observation

/// "Talk it through": dictate (or type) a description of the routine, then hand the text to the parser.
@MainActor
@Observable
public final class BrainDumpViewModel {
    /// Editable; dictation appends to whatever is already here.
    public var transcript = ""
    public private(set) var isListening = false
    public private(set) var errorMessage: String?

    private let dictation: Dictating
    private var textBeforeListening = ""
    private var listenTask: Task<Void, Never>?

    public init(dictation: Dictating = SpeechDictation()) {
        self.dictation = dictation
    }

    public var canSubmit: Bool {
        !transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    public func toggleListening() async {
        if isListening {
            stopListening()
        } else {
            await startListening()
        }
    }

    public func startListening() async {
        errorMessage = nil
        guard await dictation.requestAccess() else {
            errorMessage = "Eccentric needs microphone and speech recognition access to listen. You can turn them on in Settings, or type here instead."
            return
        }
        let stream: AsyncThrowingStream<String, Error>
        do {
            stream = try dictation.start()
        } catch {
            errorMessage = "Dictation isn't available right now. You can type your routine here instead."
            return
        }
        let trimmed = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        textBeforeListening = trimmed.isEmpty ? "" : trimmed + " "
        isListening = true
        listenTask = Task { [weak self] in
            do {
                for try await partial in stream {
                    self?.receive(partial)
                }
            } catch {
                self?.errorMessage = "Listening stopped. Anything heard so far is kept, and you can tap the mic to keep going."
            }
            self?.isListening = false
        }
    }

    public func stopListening() {
        dictation.stop()
    }

    /// Waits for any in-flight transcript to land. For tests and teardown.
    func waitForListeningToEnd() async {
        await listenTask?.value
    }

    private func receive(_ partial: String) {
        transcript = textBeforeListening + partial
    }
}
