//* graph inspired by https://artemnovichkov.com/blog/github-contribution-graph-swift-charts

import SwiftUI
import Charts

struct StatsHeatmapView: View {
    let contributions: [Contribution]

    private let calendar = Calendar.current
    private let shortWeekdaySymbols = Calendar.current.shortWeekdaySymbols

    private var colors: [Color] {
        // Use the app's blue color as the max value
        let blue = Color(hex: "2950DB") // Replace with your app's hex if different
        return (0...10).map { index in
            index == 0 ? Color(.systemGray5) : blue.opacity(Double(index) / 10)
        }
    }

    struct DayItem: Identifiable {
        let id = UUID()
        let date: Date
        let count: Int
        let weekday: Int // 1..7 where 1 = Monday, 7 = Sunday
        let weekIndex: Int // 0..n starting from startDate
    }

    private func prepareItems() -> (items: [DayItem], startDate: Date, maxWeek: Int, monthLabels: [(weekIndex: Int, label: String)]) {
        guard !contributions.isEmpty else {
            let today = calendar.startOfDay(for: Date())
            let start = calendar.date(byAdding: .day, value: -364, to: today)!
            return ([], start, 0, [])
        }

        // contributions expected to already include all days for the last 365 days and be ordered.
        let sorted = contributions.sorted { $0.date < $1.date }
        let startDate = sorted.first!.date
        let items: [DayItem] = sorted.enumerated().map { idx, c in
            // compute weekday with Monday = 1 ... Sunday = 7
            let rawWeekday = calendar.component(.weekday, from: c.date) // 1 = Sunday
            let weekday = ((rawWeekday + 5) % 7) + 1
            let dayOffset = calendar.dateComponents([.day], from: startDate, to: c.date).day ?? 0
            let weekIndex = dayOffset / 7
            return DayItem(date: c.date, count: c.count, weekday: weekday, weekIndex: weekIndex)
        }

        let maxWeek = items.map { $0.weekIndex }.max() ?? 0

        // Build month labels at week indices where month changes
        var monthLabels: [(Int, String)] = []
        var lastMonth: Int? = nil
        for week in 0...maxWeek {
            let representativeDate = calendar.date(byAdding: .day, value: week * 7, to: startDate) ?? startDate
            let month = calendar.component(.month, from: representativeDate)
            if month != lastMonth {
                let formatter = DateFormatter()
                formatter.dateFormat = "MMM"
                monthLabels.append((week, formatter.string(from: representativeDate)))
                lastMonth = month
            }
        }

        return (items, startDate, maxWeek, monthLabels)
    }

    var body: some View {
        let prepared = prepareItems()
        let items = prepared.items
        let maxWeek = prepared.maxWeek

        // Compute sizes without GeometryReader so the view doesn't expand unexpectedly
        let desiredWeekWidth: CGFloat = 100
        let initialCellSize = desiredWeekWidth / 7.0
        let screenHeight = UIScreen.main.bounds.height
        let availableHeight = min(screenHeight * 0.65, 600)
        let rows = max(prepared.maxWeek + 1, 1)
        let cellSize = min(initialCellSize, availableHeight / CGFloat(rows))
        let totalHeight = cellSize * CGFloat(rows)

        Chart(items) { item in
            // Map weekIndex so that visually weeks increase downward while keeping chart domain ascending
            let mappedWeek = prepared.maxWeek - item.weekIndex
            RectangleMark(
                x: .value("Weekday", item.weekday),
                y: .value("Week", mappedWeek)
            )
            .foregroundStyle(by: .value("Count", item.count))
            .cornerRadius(2)
        }
        .chartForegroundStyleScale(range: Gradient(colors: colors))
        .chartXScale(domain: 1...7)
        .frame(width: desiredWeekWidth, height: totalHeight)
        .padding(.horizontal, 8)
        // Top axis: show only Monday (1) and Sunday (7)
        .chartXAxis {
            AxisMarks(position: .top, values: [1, 7]) { value in
                if let v = value.as(Int.self) {
                    AxisValueLabel {
                        Text(v == 1 ? "Mon" : "Sun")
                            .font(.caption)
                    }
                }
            }
        }
        // Left axis: month labels down the weeks (mapped positions)
        .chartYAxis {
            AxisMarks(position: .leading, values: prepared.monthLabels.map { maxWeek - $0.weekIndex }) { value in
                if let mappedWeekIdx = value.as(Int.self) {
                    let origWeek = maxWeek - mappedWeekIdx
                    if let label = prepared.monthLabels.first(where: { $0.weekIndex == origWeek })?.label {
                        AxisValueLabel {
                            Text(label).font(.caption)
                        }
                    }
                }
            }
        }
        // Keep domain ascending to avoid invalid Range; visual inversion is handled by mappedWeek above
        .chartYScale(domain: 0...Double(maxWeek))
    }
}

struct StatsHeatmapView_Previews: PreviewProvider {
    static var previews: some View {
        StatsHeatmapView(contributions: Contribution.generateMockData())
    }
}
