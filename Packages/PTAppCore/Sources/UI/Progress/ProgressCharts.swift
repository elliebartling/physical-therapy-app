import SwiftUI
import Charts
import DataKit
import HistoryKit

extension ExerciseRating {
    /// Ratings step up in ink weight; painful, the one to notice, takes the accent.
    func color(accent: Color) -> Color {
        switch self {
        case .easy: AppColor.ink.opacity(0.22)
        case .aboutRight: AppColor.ink.opacity(0.55)
        case .hard: AppColor.ink
        case .painful: accent
        }
    }
}

/// One time an exercise came up: filled with its rating, outlined if done without one,
/// dashed if skipped.
struct MarkSquare: View {
    let mark: ProgressViewModel.Mark
    @ScaledMetric(relativeTo: .caption) private var size: CGFloat = 14
    @Environment(\.appAccent) private var accent

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 3)
        Group {
            switch mark {
            case .rated(let rating):
                shape.fill(rating.color(accent: accent))
            case .done:
                shape.strokeBorder(AppColor.ink.opacity(0.55), lineWidth: 1.5)
            case .skipped:
                shape.strokeBorder(AppColor.inkSecondary, style: StrokeStyle(lineWidth: 1, dash: [2, 2]))
            }
        }
        .frame(width: size, height: size)
    }
}

/// A row of marks, oldest first, read out as a tally.
struct MarkStrip: View {
    let marks: [ProgressViewModel.Mark]

    var body: some View {
        HStack(spacing: 4) {
            ForEach(Array(marks.enumerated()), id: \.offset) { _, mark in
                MarkSquare(mark: mark)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Self.spoken(marks))
    }

    static func spoken(_ marks: [ProgressViewModel.Mark]) -> String {
        guard !marks.isEmpty else { return "Not done yet" }
        var parts = ExerciseRating.allCases.compactMap { rating -> String? in
            let count = marks.filter { $0 == .rated(rating) }.count
            return count == 0 ? nil : "\(count) \(rating.title.lowercased())"
        }
        let unrated = marks.filter { $0 == .done }.count
        if unrated > 0 { parts.append("\(unrated) not rated") }
        let skipped = marks.filter { $0 == .skipped }.count
        if skipped > 0 { parts.append("\(skipped) skipped") }
        return "Last \(marks.count) times: " + parts.joined(separator: ", ")
    }
}

/// What the colors mean.
struct RatingLegend: View {
    var showsMarks = false
    @Environment(\.appAccent) private var accent

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 104), alignment: .leading)], alignment: .leading, spacing: 8) {
            ForEach(ExerciseRating.allCases, id: \.self) { rating in
                item(rating.title) { MarkSquare(mark: .rated(rating)) }
            }
            if showsMarks {
                item("Not rated") { MarkSquare(mark: .done) }
                item("Skipped") { MarkSquare(mark: .skipped) }
            }
        }
        .accessibilityHidden(true)
    }

    private func item<Swatch: View>(_ title: String, @ViewBuilder swatch: () -> Swatch) -> some View {
        HStack(spacing: 6) {
            swatch()
            Text(title.uppercased())
                .font(AppFont.mono(10))
                .tracking(0.5)
                .foregroundStyle(AppColor.inkSecondary)
        }
    }
}

/// Days done and partly done, one column per week, this week last.
struct ConsistencyHeatmap: View {
    let weeks: [HeatmapWeek]
    var calendar: Calendar = .current
    @Environment(\.appAccent) private var accent

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Grid(alignment: .leading, horizontalSpacing: 3, verticalSpacing: 3) {
                ForEach(0..<7, id: \.self) { weekday in
                    GridRow {
                        Text(weekdaySymbols[weekday])
                            .font(AppFont.mono(9))
                            .foregroundStyle(AppColor.inkSecondary)
                            .frame(minWidth: 12, alignment: .leading)
                        ForEach(weeks) { week in
                            cell(week.days.indices.contains(weekday) ? week.days[weekday] : .rest)
                        }
                    }
                }
            }
            HStack {
                if let first = weeks.first {
                    Text(first.weekStart.formatted(.dateTime.month(.abbreviated).day()).uppercased())
                }
                Spacer()
                Text("THIS WEEK")
            }
            .font(AppFont.mono(9))
            .tracking(0.5)
            .foregroundStyle(AppColor.inkSecondary)
            .padding(.leading, 15)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(summary)
    }

    private func cell(_ state: DayState) -> some View {
        RoundedRectangle(cornerRadius: 2)
            .fill(fill(state))
            .overlay {
                if state == .future {
                    RoundedRectangle(cornerRadius: 2).strokeBorder(AppColor.hairline, lineWidth: 1)
                }
            }
            .aspectRatio(1, contentMode: .fit)
            .frame(maxWidth: 28)
    }

    private func fill(_ state: DayState) -> Color {
        switch state {
        case .done: accent
        case .partial: accent.opacity(0.35)
        case .rest: AppColor.hairline
        case .future: .clear
        }
    }

    /// Single-letter weekday names, starting on the calendar's first weekday.
    private var weekdaySymbols: [String] {
        let symbols = calendar.veryShortStandaloneWeekdaySymbols
        let first = (calendar.firstWeekday - 1) % symbols.count
        return Array(symbols[first...] + symbols[..<first])
    }

    private var summary: String {
        let days = weeks.flatMap(\.days)
        let done = days.filter { $0 == .done }.count
        let partial = days.filter { $0 == .partial }.count
        var text = "Last \(weeks.count) weeks: \(done) \(done == 1 ? "day" : "days") done"
        if partial > 0 { text += ", \(partial) partly done" }
        return text
    }
}

/// Pain recorded after each session, 0 to 10.
struct PainChart: View {
    let points: [PainPoint]

    var body: some View {
        Chart(points) { point in
            LineMark(x: .value("Date", point.date), y: .value("Pain", point.level))
                .foregroundStyle(AppColor.ink)
                .interpolationMethod(.monotone)
            PointMark(x: .value("Date", point.date), y: .value("Pain", point.level))
                .foregroundStyle(AppColor.ink)
                .symbolSize(24)
        }
        .chartYScale(domain: 0...10)
        .chartYAxis {
            AxisMarks(values: [0, 5, 10]) { _ in
                AxisGridLine().foregroundStyle(AppColor.hairline)
                AxisValueLabel().font(AppFont.mono(10))
            }
        }
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                AxisValueLabel(format: .dateTime.month(.abbreviated).day()).font(AppFont.mono(9))
            }
        }
        .frame(height: 140)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(summary)
    }

    private var summary: String {
        guard let first = points.first, let last = points.last else { return "No pain recorded" }
        let levels = points.map(\.level)
        return "Pain after sessions, \(points.count) readings. First \(first.level), latest \(last.level), "
            + "lowest \(levels.min() ?? 0), highest \(levels.max() ?? 0), out of 10."
    }
}

/// Ratings given each week, stacked.
struct RatingsChart: View {
    let weeks: [WeekRatings]
    @Environment(\.appAccent) private var accent

    var body: some View {
        Chart {
            ForEach(weeks) { week in
                ForEach(ExerciseRating.allCases, id: \.self) { rating in
                    BarMark(
                        x: .value("Week", week.weekStart, unit: .weekOfYear),
                        y: .value("Times", week.counts[rating] ?? 0)
                    )
                    .foregroundStyle(by: .value("Rating", rating.title))
                }
            }
        }
        .chartForegroundStyleScale(domain: ExerciseRating.allCases.map(\.title),
                                   range: ExerciseRating.allCases.map { $0.color(accent: accent) })
        .chartLegend(.hidden)
        .chartYAxis {
            AxisMarks(values: .automatic(desiredCount: 3)) { _ in
                AxisGridLine().foregroundStyle(AppColor.hairline)
                AxisValueLabel().font(AppFont.mono(10))
            }
        }
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                AxisValueLabel(format: .dateTime.month(.abbreviated).day()).font(AppFont.mono(9))
            }
        }
        .frame(height: 140)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(summary)
    }

    private var summary: String {
        let totals = ExerciseRating.allCases.compactMap { rating -> String? in
            let count = weeks.reduce(0) { $0 + ($1.counts[rating] ?? 0) }
            return count == 0 ? nil : "\(count) \(rating.title.lowercased())"
        }
        return "Ratings over \(weeks.count) weeks: " + totals.joined(separator: ", ")
    }
}

/// A big number with a small label, in a row of three.
struct ProgressFigure: View {
    let value: String
    let label: String
    var detail: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value)
                .font(AppFont.display(30, weight: .bold))
                .tracking(-1)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(label.uppercased())
                .font(AppFont.mono(10))
                .tracking(0.6)
                .foregroundStyle(AppColor.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
            if let detail {
                Text(detail.uppercased())
                    .font(AppFont.mono(10, weight: .medium))
                    .tracking(0.6)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 12)
        .accessibilityElement(children: .combine)
    }
}

/// Something worth telling a PT, with the accent rule down its side.
struct InsightCard: View {
    let insight: ProgressViewModel.Insight
    var showsTitle = true
    @Environment(\.appAccent) private var accent

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Rectangle()
                .fill(accent)
                .frame(width: 3)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                if showsTitle {
                    Text(insight.title.uppercased())
                        .font(AppFont.mono(11, weight: .medium))
                        .tracking(0.6)
                }
                Text(insight.detail)
                    .font(AppFont.body(15))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 10)
        .accessibilityElement(children: .combine)
    }
}

/// A numbered section: ink rule, label, optional note on the right.
struct ProgressSectionHeader: View {
    let title: String
    var trailing: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            InkRule()
            HStack(alignment: .firstTextBaseline) {
                SectionLabel(title)
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                if let trailing { SectionLabel(trailing) }
            }
            .padding(.top, 10)
            .padding(.bottom, 12)
        }
    }
}
