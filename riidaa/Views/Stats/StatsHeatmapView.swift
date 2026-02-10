import SwiftUI
import Charts

struct StatsHeatmapView: View {
    let contributions: [Contribution]
    let graphLabels: Color
    @State private var selectedContribution: Contribution?
    
    // 1. FIXED: Define monthStarts so the ForEach has a scope
    var monthStarts: [Contribution] {
        contributions.filter { isFirstOfMonth($0.date) }
    }
    
    var calendar: Calendar {
        var cal = Calendar.current
        cal.firstWeekday = 2 // Monday start
        return cal
    }
    let today = Date()
    
    init(contributions: [Contribution] = Contribution.generate(), graphLabels: Color = .primary) {
        self.contributions = contributions
        self.graphLabels = graphLabels
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            headerView
            
            HStack {
                Spacer()
                
                HStack(alignment: .center, spacing: 12) {
                    Chart {
                        // Activity Squares
                        ForEach(contributions) { contribution in
                            if contribution.date <= today {
                                let isSelected = selectedContribution?.id == contribution.id
                                
                                RectangleMark(
                                    x: .value("Weekday", weekday(contribution.date)),
                                    y: .value("Weeks Ago", weeksAgo(from: contribution.date)),
                                    width: 15, // Using 15 to match previous width request
                                    height: 10
                                )
                                .foregroundStyle(heatmapColor(for: contribution.count))
                                .cornerRadius(2)
                                .annotation(position: .overlay) {
                                    if isSelected {
                                        RoundedRectangle(cornerRadius: 2)
                                            .strokeBorder(Color.pink, lineWidth: 2)
                                            .frame(width: 15, height: 10)
                                    }
                                }
                            }
                        }
                        
                        // 2. FIXED: Correct RuleMark logic
                        ForEach(monthStarts) { ms in
                            // We use Double subtraction to position the line between the rows
                            RuleMark(y: .value("MonthStart", Double(weeksAgo(from: ms.date)) - 0.5))
                                .foregroundStyle(graphLabels.opacity(0.3))
                                .lineStyle(StrokeStyle(lineWidth: 1.0))
                                .annotation(position: .trailing, alignment: .leading, spacing: 10) {
                                    Text(formatMonth(ms.date))
                                        .font(.system(size: 11, weight: .bold, design: .rounded))
                                        .foregroundColor(graphLabels)
                                        .fixedSize()
                                }
                        }
                    }
                    .chartYAxis(.hidden)
                    .chartYScale(domain: .automatic(includesZero: true, reversed: true))
                    .chartXScale(domain: 0.5...7.5)
                    .chartXAxis {
                        AxisMarks(preset: .aligned, values: [1, 2, 3, 4, 5, 6, 7]) { value in
                            AxisValueLabel {
                                if let int = value.as(Int.self) {
                                    Text(formatWeekday(int))
                                        .font(.system(size: 12, weight: .bold, design: .rounded))
                                        .foregroundColor(graphLabels)
                                }
                            }
                        }
                    }
                    .frame(width: 7 * 20)
                    .padding(.trailing, 45) // Space for month labels
                    .chartOverlay { proxy in
                        GeometryReader { geometry in
                            Rectangle().fill(.clear).contentShape(Rectangle())
                                .onTapGesture { location in
                                    handleTap(at: location, proxy: proxy, geometry: geometry)
                                }
                        }
                    }

                    legendView
                }
                
                Spacer()
            }
        }
        .padding()
        .onAppear {
            setOrientation(.portrait)
        }
    }
    
    // MARK: - Subviews & Helpers

    var legendView: some View {
        VStack(spacing: 6) {
            Text("10+")
                .font(.system(size: 9, weight: .bold, design: .rounded))
                .foregroundColor(graphLabels)
            
            VStack(spacing: 4) {
                ForEach([10, 7, 5, 3, 1], id: \.self) { count in
                    RoundedRectangle(cornerRadius: 2)
                        .fill(heatmapColor(for: count))
                        .frame(width: 14, height: 14)
                }
                RoundedRectangle(cornerRadius: 2)
                    .fill(heatmapColor(for: 0))
                    .frame(width: 14, height: 14)
            }
            
            Text("0")
                .font(.system(size: 9, weight: .bold, design: .rounded))
                .foregroundColor(graphLabels)
        }
    }

    func isFirstOfMonth(_ date: Date) -> Bool {
        calendar.component(.day, from: date) == 1
    }

    func weeksAgo(from date: Date) -> Int {
        let startOfToday = calendar.startOfDay(for: today)
        let startOfDate = calendar.startOfDay(for: date)
        let mondayOfToday = calendar.dateComponents([.calendar, .yearForWeekOfYear, .weekOfYear], from: startOfToday).date!
        let mondayOfDate = calendar.dateComponents([.calendar, .yearForWeekOfYear, .weekOfYear], from: startOfDate).date!
        let diff = calendar.dateComponents([.weekOfYear], from: mondayOfDate, to: mondayOfToday)
        return diff.weekOfYear ?? 0
    }

    func weekday(_ date: Date) -> Int {
        let w = calendar.component(.weekday, from: date)
        return (w == 1 ? 7 : w - 1)
    }

    func formatWeekday(_ day: Int) -> String {
        let labels = ["月", "火", "水", "木", "金", "土", "日"]
        return labels[day - 1]
    }

    func formatMonth(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM"
        return formatter.string(from: date)
    }

    func heatmapColor(for count: Int) -> Color {
        if count == 0 { return Color(.systemGray6) }
        return Color.green.opacity(min(Double(count) / 10.0 + 0.1, 1.0))
    }

    private func handleTap(at location: CGPoint, proxy: ChartProxy, geometry: GeometryProxy) {
        let origin = geometry[proxy.plotAreaFrame].origin
        let locationInPlot = CGPoint(x: location.x - origin.x, y: location.y - origin.y)
        if let (day, weekOffset): (Int, Double) = proxy.value(at: locationInPlot) {
            let intWeek = Int(round(weekOffset))
            selectedContribution = contributions.first { item in
                weeksAgo(from: item.date) == intWeek && weekday(item.date) == day
            }
        }
    }

    func setOrientation(_ orientation: UIInterfaceOrientationMask) {
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene {
            let geometryPreferences = UIWindowScene.GeometryPreferences.iOS(interfaceOrientations: orientation)
            windowScene.requestGeometryUpdate(geometryPreferences)
        }
    }

    var headerView: some View {
        HStack(spacing: 8) {
            if let selected = selectedContribution {
                Text(selected.date.formatted(date: .abbreviated, time: .omitted))
                Text("•")
                Text("\(selected.count) Pages")
            } else {
                Text("Activity")
                Text("•")
                Text("Last 52 Weeks")
            }
        }
        .font(.headline)
        .foregroundColor(.primary)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}



// MARK: - Preview

struct StatsHeatmapView_Previews: PreviewProvider {
    static var previews: some View {
        TabView {
            NavigationStack {
                StatsHeatmapView() // your chart tab
                    .navigationTitle("Stats")
            }
            .tabItem {
                Label("Stats", systemImage: "chart.bar")
            }

            NavigationStack {
                HomeView() // another tab for realistic preview
            }
            .tabItem {
                Label("Home", systemImage: "house")
            }
        }
        .previewDevice("iPhone 14")
    }
}
