import SwiftUI
import DataKit

/// What a new sheet changes, shown before it replaces the current routine.
struct RoutineChangesView: View {
    let changes: RoutineChanges
    let currentPhase: Int
    let onReplace: () -> Void
    let onBack: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                header
                Text("What changed")
                    .font(AppFont.display(40, weight: .bold))
                    .tracking(-1.6)
                    .padding(.top, 22)
                Text(summary)
                    .font(AppFont.body(15))
                    .foregroundStyle(AppColor.inkSecondary)
                    .padding(.top, 10)
                list.padding(.top, 24)
            }
            .padding(.horizontal, AppSpacing.screenPadding)
            .padding(.bottom, AppSpacing.s(3))
        }
        .scrollIndicators(.hidden)
        .safeAreaInset(edge: .bottom) {
            Button(action: onReplace) {
                HStack {
                    Text("Replace Phase \(currentPhase)")
                    Spacer()
                    Image(systemName: "arrow.right")
                }
                .font(AppFont.display(17, weight: .semibold))
                .padding(.horizontal, 22)
            }
            .buttonStyle(InkGlassButtonStyle())
            .padding(.horizontal, AppSpacing.screenPadding)
            .padding(.bottom, AppSpacing.s(1))
        }
    }

    private var header: some View {
        VStack(spacing: 10) {
            HStack {
                Button(action: onBack) {
                    Image(systemName: "chevron.left")
                }
                .buttonStyle(GlassCircleButtonStyle())
                .accessibilityLabel("Back to editing")
                Spacer()
                SectionLabel("Phase \(currentPhase + 1)")
            }
            InkRule(weight: 2)
        }
        .padding(.top, AppSpacing.s(1))
    }

    /// "1 changed · 2 new · 1 removed · 4 the same", leaving out the zeros.
    var summary: String {
        let parts: [(Int, String)] = [
            (changes.count(.changed), "changed"),
            (changes.count(.added), "new"),
            (changes.count(.removed), "removed"),
            (changes.count(.unchanged), "the same"),
        ]
        let text = parts.filter { $0.0 > 0 }.map { "\($0.0) \($0.1)" }.joined(separator: " · ")
        let history = changes.count(.unchanged) + changes.count(.changed) > 0
            ? " Exercises with the same name keep their history."
            : ""
        return (text.isEmpty ? "No exercises." : text + ".") + history
    }

    private var list: some View {
        VStack(spacing: 0) {
            ForEach(changes.items) { item in
                ChangeRow(item: item)
            }
        }
        .overlay(alignment: .bottom) { HairlineDivider() }
    }
}

private struct ChangeRow: View {
    let item: RoutineChanges.Item

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                Text(item.name)
                    .font(AppFont.display(18, weight: .semibold))
                    .strikethrough(item.kind == .removed)
                    .foregroundStyle(item.kind == .removed ? AppColor.inkSecondary : AppColor.ink)
                Text(detail)
                    .font(AppFont.mono(12))
                    .foregroundStyle(AppColor.inkSecondary)
            }
            Spacer()
            Text(label.uppercased())
                .font(AppFont.mono(10, weight: .medium))
                .tracking(0.6)
                .foregroundStyle(item.kind == .unchanged ? AppColor.inkSecondary : AppColor.ink)
        }
        .padding(.vertical, 14)
        .overlay(alignment: .top) { HairlineDivider() }
        .accessibilityElement(children: .combine)
    }

    private var label: String {
        switch item.kind {
        case .unchanged: "Same"
        case .changed: "Changed"
        case .added: "New"
        case .removed: "Removed"
        }
    }

    private var detail: String {
        let before = item.before.map { Prescription.text(target: $0.target, side: $0.side) }
        let after = item.after.map { Prescription.text(target: $0.target, side: $0.side) }
        switch item.kind {
        case .changed:
            let restChanged = item.before?.restSeconds != item.after?.restSeconds
            let rest = restChanged ? " · rest \(item.after?.restSeconds ?? 0)s" : ""
            return "\(before ?? "") → \(after ?? "")\(rest)"
        case .removed: return before ?? ""
        case .unchanged, .added: return after ?? ""
        }
    }
}
