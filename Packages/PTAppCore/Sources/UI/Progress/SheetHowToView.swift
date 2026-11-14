import SwiftUI
import DataKit

/// The handout's own instruction blocks, in sheet order: heading, then body.
/// Headings are shown as printed on the sheet, whatever they are.
struct SheetHowToView: View {
    let sections: [HowToSection]

    var body: some View {
        if !sections.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(sections) { section in
                    block(section)
                }
            }
            // Inside the conditional, so an empty list leaves no gap.
            .padding(.top, 20)
        }
    }

    private func block(_ section: HowToSection) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HairlineDivider()
            if !section.heading.isEmpty {
                Text(section.heading)
                    .font(.caption.weight(.medium))
                    .tracking(0.7)
                    .foregroundStyle(AppColor.inkSecondary)
                    .padding(.top, 10)
                    .accessibilityAddTraits(.isHeader)
            }
            Text(section.body)
                .font(.body)
                .foregroundStyle(AppColor.ink)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, 14)
        }
        .accessibilityElement(children: .combine)
    }
}
