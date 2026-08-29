import Foundation
import SwiftData
import WatchConnectivity

/// Pushes routines to the watch and receives completed watch sessions,
/// so compliance history stays unified on the phone.
final class PhoneConnectivity: NSObject, WCSessionDelegate {
    static let shared = PhoneConnectivity()
    private var container: ModelContainer?

    private override init() {
        super.init()
    }

    func configure(container: ModelContainer) {
        self.container = container
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        session.delegate = self
        session.activate()
    }

    @MainActor
    func pushAllRoutines() {
        guard let context = container?.mainContext else { return }
        let routines = (try? context.fetch(FetchDescriptor<Routine>())) ?? []
        pushRoutines(routines.map(\.payload))
    }

    func pushRoutines(_ payloads: [RoutinePayload]) {
        guard WCSession.isSupported(),
              WCSession.default.activationState == .activated,
              let data = try? JSONEncoder().encode(payloads) else { return }
        try? WCSession.default.updateApplicationContext(["routines": data])
    }

    // MARK: - WCSessionDelegate

    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        guard activationState == .activated else { return }
        Task { @MainActor in
            self.pushAllRoutines()
        }
    }

    func sessionDidBecomeInactive(_ session: WCSession) {}

    func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
    }

    func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        guard let data = userInfo["completedSession"] as? Data,
              let payload = try? JSONDecoder().decode(CompletedSessionPayload.self, from: data) else { return }
        Task { @MainActor in
            guard let context = self.container?.mainContext else { return }
            let id = payload.id
            let existing = (try? context.fetch(
                FetchDescriptor<SessionLog>(predicate: #Predicate { $0.id == id })
            )) ?? []
            guard existing.isEmpty else { return }
            // The watch already wrote its own HealthKit workout.
            context.insert(SessionLog(from: payload, savedToHealthKit: true))
            try? context.save()
        }
    }
}
