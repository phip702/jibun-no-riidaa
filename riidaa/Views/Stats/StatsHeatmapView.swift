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
        let prepared = prepareItems()
        let items = prepared.items
        let maxWeek = prepared.maxWeek

        // Precompute display items and other values to simplify Chart closures
        let displayItems = items.map { it in
            DisplayDay(id: it.id, date: it.date, count: it.count, weekday: it.weekday, weekIndex: it.weekIndex, mappedWeek: maxWeek - it.weekIndex)
        }
        let gradient = Gradient(colors: colors)
        let monthAxisValues = prepared.monthLabels.map { maxWeek - $0.weekIndex }

        // sizing: full week's width = 100
        let desiredWeekWidth: CGFloat = 100
        let initialCellSize = desiredWeekWidth / 7.0
        let screenHeight = UIScreen.main.bounds.height
        let availableHeight = min(screenHeight * 0.65, 600)
        let rows = max(maxWeek + 1, 1)
        let cellSize = min(initialCellSize, availableHeight / CGFloat(rows))
        let totalHeight = cellSize * CGFloat(rows)

        VStack(alignment: .leading, spacing: 6) {

            Chart(displayItems) { d in
                RectangleMark(
                    x: .value("Weekday", d.weekday),
                    y: .value("Week", d.mappedWeek)
                )
                .foregroundStyle(by: .value("Count", d.count))
                .cornerRadius(2)
                .annotation(position: .overlay) {
                    if let sel = selectedDate, Calendar.current.isDate(sel, inSameDayAs: d.date) {
                        RoundedRectangle(cornerRadius: 2)
                            .stroke(Color.pink, lineWidth: 2)
                            .frame(width: cellSize, height: cellSize)
                    } else {
                        EmptyView()
                    }
                }
            }
            .chartForegroundStyleScale(range: gradient)
            .chartXScale(domain: 1...7)
            .chartYScale(domain: 0...Double(maxWeek))
            .frame(width: desiredWeekWidth, height: totalHeight)
            .padding(.horizontal, 8)
            .chartOverlay { proxy in
                GeometryReader { geo in
                    Rectangle()
                        .fill(Color.clear)
                        .contentShape(Rectangle())
                        .gesture(DragGesture(minimumDistance: 0).onEnded { value in
                            let plotFrame = geo[proxy.plotAreaFrame]
                            let locationInPlot = CGPoint(x: value.location.x - plotFrame.minX, y: value.location.y - plotFrame.minY)
                            handleTap(location: locationInPlot, proxy: proxy, items: items, maxWeek: maxWeek)
                        })
                }
            }

            // Selected day display and legend
            VStack(alignment: .leading, spacing: 4) {
                if let selDate = selectedDate, let sel = items.first(where: { Calendar.current.isDate($0.date, inSameDayAs: selDate) }) {
                    Text("\(sel.count) \(formattedDate(sel.date))")
                        .font(.subheadline)
                        .bold()
                }

                HStack(spacing: 6) {
                    ForEach(0..<colors.count, id: \.self) { idx in
                        Rectangle()
                            .fill(colors[idx])
                            .frame(width: 20, height: 12)
                            .cornerRadius(2)
                    }
                }
            }
            .padding(.leading, 12)
        }
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
            AxisMarks(position: .leading, values: monthAxisValues) { value in
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
    }

    private func formattedDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        return formatter.string(from: date)
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
