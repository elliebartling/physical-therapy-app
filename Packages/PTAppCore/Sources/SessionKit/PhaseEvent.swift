import Foundation
import DataKit

public enum PhaseEvent: Equatable, Sendable {
    case sessionStarted
    case exerciseStarted(exerciseID: UUID, index: Int, totalExercises: Int)
    case setStarted(setIndex: Int, totalSets: Int, side: Side)
    case rest(seconds: Int)
    case sideSwitch(to: Side)
    case exerciseCompleted(exerciseID: UUID)
    case sessionCompleted
    case paused
    case resumed
}
