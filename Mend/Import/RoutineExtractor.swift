import Foundation
import FoundationModels

@Generable
struct ExtractedRoutine {
    @Guide(description: "A short, human-friendly name for this routine, e.g. 'Knee Rehab — Phase 2'. Invent one from context if the sheet has no title.")
    var name: String

    @Guide(description: "How many days per week the routine is prescribed (1-7). Use 7 if the sheet says daily or doesn't say.")
    var daysPerWeek: Int

    @Guide(description: "General instructions or precautions from the clinician that apply to the whole routine, if any.")
    var notes: String?

    var exercises: [ExtractedExercise]
}

@Generable
struct ExtractedExercise {
    @Guide(description: "The exercise name as written on the sheet.")
    var name: String

    @Guide(description: "Step-by-step instructions or cues for performing the exercise, if present.")
    var details: String?

    @Guide(description: "Number of sets. Use 1 if not stated.")
    var sets: Int

    @Guide(description: "Repetitions per set for rep-based exercises. Omit for purely time-based holds.")
    var reps: Int?

    @Guide(description: "Hold or duration in seconds for time-based exercises, e.g. 30 for a 30-second plank. Omit for rep-based exercises.")
    var holdSeconds: Int?

    @Guide(description: "Rest between sets in seconds. Use 30 if not stated.")
    var restSeconds: Int

    @Guide(description: "True if the exercise is performed separately on each side (left/right, each leg, each arm).")
    var isPerSide: Bool

    @Guide(description: "Equipment needed, e.g. 'resistance band', if any.")
    var equipment: String?
}

enum ExtractionError: LocalizedError {
    case modelUnavailable(String)
    case noText

    var errorDescription: String? {
        switch self {
        case .modelUnavailable(let message):
            return message
        case .noText:
            return "Couldn't find readable text in those screenshots. Try a clearer photo, or enter the routine manually."
        }
    }
}

enum RoutineExtractor {
    /// Nil when the on-device model is ready; otherwise a user-facing explanation.
    static var availabilityMessage: String? {
        switch SystemLanguageModel.default.availability {
        case .available:
            return nil
        case .unavailable(.deviceNotEligible):
            return "This device doesn't support Apple Intelligence, which Mend uses to read routine screenshots. You can still enter exercises manually."
        case .unavailable(.appleIntelligenceNotEnabled):
            return "Turn on Apple Intelligence in Settings to import routines from screenshots."
        case .unavailable(.modelNotReady):
            return "Apple Intelligence is still downloading its model. Try again in a few minutes."
        case .unavailable:
            return "The on-device model isn't available right now. You can still enter exercises manually."
        }
    }

    static func extractRoutine(fromOCRText text: String) async throws -> ExtractedRoutine {
        if let message = availabilityMessage {
            throw ExtractionError.modelUnavailable(message)
        }
        let session = LanguageModelSession(instructions: """
            You convert OCR text from physical therapy exercise sheets into structured routines. \
            The text may contain OCR noise; use judgement to reconstruct exercise names, sets, reps, \
            hold times, and rest periods. Convert minutes to seconds. If an exercise says 'each side', \
            'each leg', or similar, mark it per-side. Only include real exercises — ignore page headers, \
            footers, clinic contact details, and appointment information.
            """)
        let response = try await session.respond(
            to: "Here is the OCR text from the exercise sheet(s):\n\n\(text)",
            generating: ExtractedRoutine.self
        )
        return response.content
    }
}

extension ExtractedRoutine {
    var payload: RoutinePayload {
        RoutinePayload(
            id: UUID(),
            name: name,
            daysPerWeek: min(max(daysPerWeek, 1), 7),
            clinicianNotes: notes,
            exercises: exercises.map { exercise in
                ExercisePayload(
                    name: exercise.name,
                    details: exercise.details,
                    sets: max(1, exercise.sets),
                    reps: exercise.reps,
                    holdSeconds: exercise.holdSeconds,
                    restSeconds: max(0, exercise.restSeconds),
                    isPerSide: exercise.isPerSide,
                    equipment: exercise.equipment
                )
            }
        )
    }
}
