//* graph inspired by https://artemnovichkov.com/blog/github-contribution-graph-swift-charts

import SwiftUI
import Charts

struct StatsHeatmapView: View {
    let contributions: [Contribution]

    private let calendar = Calendar.current

    @State private var selectedDate: Date? = nil

    private var colors: [Color] {
        let blue = Color(hex: "2950DB")
        return (0...10).map { index in
            index == 0 ? Color(.systemGray5) : blue.opacity(Double(index) / 10)
        }
    }

    struct DayItem: Identifiable {
        let id = UUID()
        let date: Date
        let count: Int
        let weekday: Int // 1..7 (Mon=1)
        let weekIndex: Int
    }

        struct DisplayDay: Identifiable {
            let id: UUID
            let date: Date
            let count: Int
            let weekday: Int
            let weekIndex: Int
            let mappedWeek: Int
        }

    private func prepareItems() -> (items: [DayItem], startDate: Date, maxWeek: Int, monthLabels: [(weekIndex: Int, label: String)]) {
        // Build 365-day range starting from today-364
        let today = calendar.startOfDay(for: Date())
        let startDate = calendar.date(byAdding: .day, value: -364, to: today)!

        // Map contributions array by date for quick lookup
        var lookup: [Date: Int] = [:]
        for c in contributions {
            let d = calendar.startOfDay(for: c.date)
            lookup[d] = c.count
        }

        var items: [DayItem] = []
        for offset in 0..<365 {
            let date = calendar.date(byAdding: .day, value: offset, to: startDate)!
            let rawWeekday = calendar.component(.weekday, from: date) // 1 = Sunday
            let weekday = ((rawWeekday + 5) % 7) + 1 // convert to Mon=1..Sun=7
            let dayOffset = offset
            let weekIndex = dayOffset / 7
            let count = lookup[date] ?? 0
            items.append(DayItem(date: date, count: count, weekday: weekday, weekIndex: weekIndex))
        }

        let maxWeek = items.map { $0.weekIndex }.max() ?? 0

        var monthLabels: [(Int, String)] = []
        var lastMonth: Int? = nil
        for week in 0...maxWeek {
            let repDate = calendar.date(byAdding: .day, value: week * 7, to: startDate) ?? startDate
            let month = calendar.component(.month, from: repDate)
            if month != lastMonth {
                let formatter = DateFormatter()
                formatter.dateFormat = "MMM"
                monthLabels.append((week, formatter.string(from: repDate)))
                lastMonth = month
            }
        }

        return (items, startDate, maxWeek, monthLabels)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Chart(contributions) { contribution in
                RectangleMark(
                    xStart: .value("Start week", contribution.date, unit: .weekOfYear),
                    xEnd: .value("End week", contribution.date, unit: .weekOfYear),
                    yStart: .value("Start weekday", weekday(for: contribution.date)),
                    yEnd: .value("End weekday", weekday(for: contribution.date) + 1)
                )
                .foregroundStyle(by: .value("Count", contribution.count))
                .cornerRadius(2)
            }
            .chartForegroundStyleScale(range: Gradient(colors: colors))
            .chartYScale(domain: 1...7)
            .frame(height: 220)
            .padding(.horizontal, 8)

            HStack(spacing: 6) {
                ForEach(0..<colors.count, id: \.self) { idx in
                    Rectangle()
                        .fill(colors[idx])
                        .frame(width: 20, height: 12)
                        .cornerRadius(2)
                }
            }
            .padding(.leading, 12)
        }
    }

    private func formattedDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        return formatter.string(from: date)
    }

    private func weekday(for date: Date) -> Int {
        let weekday = calendar.component(.weekday, from: date)
        return weekday == 1 ? 7 : (weekday - 1)
    }

    private func handleTap(location: CGPoint, proxy: ChartProxy, items: [DayItem], maxWeek: Int) {
        guard let xVal = proxy.value(atX: location.x, as: Double.self),
              let yVal = proxy.value(atY: location.y, as: Double.self) else {
            selectedDate = nil
            return
        }

        let weekday = Int(round(xVal))
        let mappedWeek = Int(round(yVal))
        let origWeek = maxWeek - mappedWeek

        if let found = items.first(where: { $0.weekIndex == origWeek && $0.weekday == weekday }) {
            selectedDate = found.date
        } else {
            selectedDate = nil
        }
    }
}

struct StatsHeatmapView_Previews: PreviewProvider {
    static var previews: some View {
        StatsHeatmapView(contributions: Contribution.generateMockData())
    }
}
