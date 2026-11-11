import Foundation
import AVFoundation
import Speech

/// Live speech-to-text. `start()` streams the transcript so far, growing as the person talks.
public protocol Dictating: AnyObject, Sendable {
    func requestAccess() async -> Bool
    func start() throws -> AsyncThrowingStream<String, Error>
    func stop()
}

public enum DictationError: Error, Equatable {
    case recognizerUnavailable
}

/// On-device dictation with `SFSpeechRecognizer`.
///
/// Deliberately not `@MainActor`: the audio tap and recognition callbacks run on
/// background queues, and a main-actor-isolated closure called there would trap.
public final class SpeechDictation: Dictating, @unchecked Sendable {
    private let recognizer: SFSpeechRecognizer?
    private let engine = AVAudioEngine()
    private let lock = NSLock()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?

    public init(locale: Locale = .current) {
        recognizer = SFSpeechRecognizer(locale: locale)
    }

    public func requestAccess() async -> Bool {
        let speech = await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
            SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0 == .authorized) }
        }
        guard speech else { return false }
        return await AVAudioApplication.requestRecordPermission()
    }

    public func start() throws -> AsyncThrowingStream<String, Error> {
        guard let recognizer, recognizer.isAvailable else { throw DictationError.recognizerUnavailable }
        stop()

        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.record, mode: .measurement, options: .duckOthers)
        try session.setActive(true, options: .notifyOthersOnDeactivation)

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.addsPunctuation = true
        if recognizer.supportsOnDeviceRecognition {
            request.requiresOnDeviceRecognition = true
        }

        let box = RequestBox(request)
        let input = engine.inputNode
        input.installTap(onBus: 0, bufferSize: 1024, format: input.outputFormat(forBus: 0)) { buffer, _ in
            box.request.append(buffer)
        }
        engine.prepare()
        try engine.start()

        let (stream, continuation) = AsyncThrowingStream<String, Error>.makeStream()
        let task = recognizer.recognitionTask(with: request) { result, error in
            if let result {
                continuation.yield(result.bestTranscription.formattedString)
                if result.isFinal { continuation.finish() }
            } else if let error {
                continuation.finish(throwing: error)
            }
        }
        lock.withLock {
            self.request = request
            self.task = task
        }
        return stream
    }

    /// Ends listening. Ending the audio (rather than cancelling the task) lets the
    /// recognizer deliver its final transcript before the stream finishes.
    public func stop() {
        // `task` stays referenced until the next start so it can finish delivering.
        let request = lock.withLock { () -> SFSpeechAudioBufferRecognitionRequest? in
            defer { self.request = nil }
            return self.request
        }
        guard let request else { return }
        if engine.isRunning { engine.stop() }
        engine.inputNode.removeTap(onBus: 0)
        request.endAudio()
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}

/// The audio tap runs on the render thread; the request is only appended to there,
/// which `SFSpeechAudioBufferRecognitionRequest` supports.
private final class RequestBox: @unchecked Sendable {
    let request: SFSpeechAudioBufferRecognitionRequest
    init(_ request: SFSpeechAudioBufferRecognitionRequest) { self.request = request }
}
