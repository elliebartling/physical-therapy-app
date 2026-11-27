import AVFoundation

/// Reads short announcements aloud, like what's next. Speech ducks other audio,
/// using the session set up for the cues.
public final class SpeechService {
    private let synthesizer = AVSpeechSynthesizer()

    public init() {}

    /// Says `text`, cutting off anything still being said.
    public func speak(_ text: String) {
        synthesizer.stopSpeaking(at: .immediate)
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: AVSpeechSynthesisVoice.currentLanguageCode())
        synthesizer.speak(utterance)
    }

    public func stop() {
        synthesizer.stopSpeaking(at: .immediate)
    }
}
