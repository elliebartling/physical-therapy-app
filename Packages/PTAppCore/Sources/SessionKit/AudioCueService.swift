import AVFoundation

public final class AudioCueService {
    public enum Cue { case setStart, rest, exerciseDone, sessionDone }

    private let session = AVAudioSession.sharedInstance()
    private var players: [Cue: AVAudioPlayer] = [:]

    public init() {
        try? session.setCategory(.playback, options: [.mixWithOthers, .duckOthers])
        try? session.setActive(true)
        loadTones()
    }

    public func play(_ cue: Cue) {
        players[cue]?.currentTime = 0
        players[cue]?.play()
    }

    private func loadTones() {
        let mapping: [Cue: String] = [
            .setStart: "tone_set_start",
            .rest: "tone_rest",
            .exerciseDone: "tone_exercise_done",
            .sessionDone: "tone_session_done",
        ]
        for (cue, name) in mapping {
            guard let url = Bundle.module.url(forResource: name, withExtension: "wav") else { continue }
            players[cue] = try? AVAudioPlayer(contentsOf: url)
            players[cue]?.prepareToPlay()
        }
    }
}
