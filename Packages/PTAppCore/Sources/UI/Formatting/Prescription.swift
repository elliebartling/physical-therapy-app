import Foundation
import DataKit

/// Compact prescription text, as printed in exercise tables: "3×10", "3×20s L/R".
enum Prescription {
    static func text(target: ExerciseTarget, side: Side) -> String {
        let base: String
        switch target {
        case .repsSets(let reps, let sets): base = "\(sets)×\(reps)"
        case .timeSets(let seconds, let sets): base = "\(sets)×\(seconds)s"
        }
        switch side {
        case .both: return base
        case .alternating: return base + " L/R"
        case .left: return base + " L"
        case .right: return base + " R"
        }
    }
}

/// Rough session length for display. Reps are counted at three seconds each; rest only
/// falls between sets, matching `SessionEngine`.
enum SessionEstimate {
    static let secondsPerRep = 3

    static func minutes(for exercises: [Exercise]) -> Int {
        let seconds = exercises.reduce(0) { total, exercise in
            let sets = exercise.target.totalSets
            let work: Int
            switch exercise.target {
            case .repsSets(let reps, _): work = reps * secondsPerRep
            case .timeSets(let s, _): work = s
            }
            return total + sets * work + max(0, sets - 1) * exercise.restSeconds
        }
        guard seconds > 0 else { return 0 }
        return max(1, Int((Double(seconds) / 60).rounded(.up)))
    }
}
