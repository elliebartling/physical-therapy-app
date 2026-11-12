import Foundation

/// The plan the routine follows: what's prescribed, without identity.
public struct ExerciseSpec: Equatable, Sendable {
    public var name: String
    public var target: ExerciseTarget
    public var side: Side
    public var restSeconds: Int

    public init(name: String, target: ExerciseTarget, side: Side, restSeconds: Int) {
        self.name = name
        self.target = target
        self.side = side
        self.restSeconds = restSeconds
    }

    public init(_ exercise: Exercise) {
        self.init(name: exercise.name, target: exercise.target, side: exercise.side, restSeconds: exercise.restSeconds)
    }
}

/// What a new sheet changes compared with the current routine. Exercises match by name,
/// ignoring case, spacing and punctuation, so "Clamshells" and "clam-shells " are the same.
public struct RoutineChanges: Equatable, Sendable {
    public enum Kind: Equatable, Sendable { case unchanged, changed, added, removed }

    public struct Item: Equatable, Sendable, Identifiable {
        public let id: Int
        public let kind: Kind
        /// The current version, for unchanged, changed and removed exercises.
        public let before: ExerciseSpec?
        /// The new version, for unchanged, changed and added exercises.
        public let after: ExerciseSpec?

        public var name: String { after?.name ?? before?.name ?? "" }
    }

    /// New exercises in their new order, then the removed ones in their old order.
    public let items: [Item]
    /// For each new exercise (by position), the position of the current exercise it continues.
    public let matches: [Int: Int]

    public func count(_ kind: Kind) -> Int { items.filter { $0.kind == kind }.count }

    /// Nothing differs: same exercises, same prescriptions, same order of appearance.
    public var isEmpty: Bool { items.allSatisfy { $0.kind == .unchanged } }

    public init(from current: [ExerciseSpec], to new: [ExerciseSpec]) {
        // Pair each new exercise with the first unused current one of the same name, so
        // two exercises with one name pair up in order.
        var unused: [String: [Int]] = [:]
        for (index, spec) in current.enumerated() {
            unused[Self.matchKey(spec.name), default: []].append(index)
        }
        var matches: [Int: Int] = [:]
        var items: [Item] = []
        for (newIndex, spec) in new.enumerated() {
            let key = Self.matchKey(spec.name)
            if var candidates = unused[key], !candidates.isEmpty {
                let oldIndex = candidates.removeFirst()
                unused[key] = candidates
                matches[newIndex] = oldIndex
                let before = current[oldIndex]
                let same = before.target == spec.target && before.side == spec.side
                    && before.restSeconds == spec.restSeconds
                items.append(Item(id: items.count, kind: same ? .unchanged : .changed, before: before, after: spec))
            } else {
                items.append(Item(id: items.count, kind: .added, before: nil, after: spec))
            }
        }
        let matchedOld = Set(matches.values)
        for (oldIndex, spec) in current.enumerated() where !matchedOld.contains(oldIndex) {
            items.append(Item(id: items.count, kind: .removed, before: spec, after: nil))
        }
        self.items = items
        self.matches = matches
    }

    /// Lowercased letters and digits only, so spacing and punctuation don't block a match.
    public static func matchKey(_ name: String) -> String {
        var key = String.UnicodeScalarView()
        for scalar in name.lowercased().unicodeScalars where CharacterSet.alphanumerics.contains(scalar) {
            key.append(scalar)
        }
        return String(key)
    }
}
