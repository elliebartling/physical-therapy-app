import Foundation
import Observation
import WatchConnectivity

/// Receives routines from the phone (application context) and reports
/// completed sessions back (user info transfer, delivered when reachable).
@MainActor
@Observable
final class WatchStore: NSObject {
    static let shared = WatchStore()

    var routines: [RoutinePayload] = []

    private static let routinesKey = "routines"

    private override init() {
        super.init()
        loadCached()
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    private func loadCached() {
        guard let data = UserDefaults.standard.data(forKey: Self.routinesKey),
              let decoded = try? JSONDecoder().decode([RoutinePayload].self, from: data) else { return }
        routines = decoded
    }

    fileprivate func apply(context: [String: Any]) {
        guard let data = context[Self.routinesKey] as? Data,
              let decoded = try? JSONDecoder().decode([RoutinePayload].self, from: data) else { return }
        routines = decoded
        UserDefaults.standard.set(data, forKey: Self.routinesKey)
    }

    func sendCompleted(_ payload: CompletedSessionPayload) {
        guard let data = try? JSONEncoder().encode(payload) else { return }
        WCSession.default.transferUserInfo(["completedSession": data])
    }
}

extension WatchStore: WCSessionDelegate {
    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        guard activationState == .activated else { return }
        let context = session.receivedApplicationContext
        Task { @MainActor in
            self.apply(context: context)
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        Task { @MainActor in
            self.apply(context: applicationContext)
        }
    }
}
