import SwiftUI
import Charts

struct StatsHeatmapView: View {
    let contributions: [Contribution]
    @State private var selectedContribution: Contribution?
    
    var calendar: Calendar {
        var cal = Calendar.current
        cal.firstWeekday = 2 // Monday start
        return cal
    }
    let today = Date()
    
    init(contributions: [Contribution] = Contribution.generate()) {
        self.contributions = contributions
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            headerView
            
            Chart {
                ForEach(contributions) { contribution in
                    if contribution.date <= today {
                        let isSelected = selectedContribution?.id == contribution.id
                        
                        // 1. The Activity Squares
                        RectangleMark(
                            x: .value("Weekday", weekday(contribution.date)),
                            y: .value("Weeks Ago", weeksAgo(from: contribution.date)),
                            width: 12,
                            height: 10
                        )
                        .foregroundStyle(heatmapColor(for: contribution.count))
                        .cornerRadius(2) // Slightly rounded like GitHub
//                        .opacity(selectedContribution?.id == contribution.id ? 0.5 : 1.0)
                        // --- ADD THE PINK BORDER HERE ---
                        .annotation(position: .overlay) {
                            if isSelected {
                                RoundedRectangle(cornerRadius: 2)
                                    .strokeBorder(Color.pink, lineWidth: 2) // strokeBorder keeps the border inside the square
                                    .frame(width: 12, height: 10)
                            }
                        }
                        
                        // 2. Subtle Month Divider
                        if isFirstOfMonth(contribution.date) {
                            RuleMark(
                                y: .value("Weeks Ago", Double(weeksAgo(from: contribution.date)) - 0.5)
                            )
                            // Hairline width with very low opacity
                            .lineStyle(StrokeStyle(lineWidth: 0.5))
                            .foregroundStyle(.secondary.opacity(0.2))
                            .annotation(position: .trailing, alignment: .leading, spacing: 8) {
                                Text(formatMonth(contribution.date))
                                    .font(.system(size: 10, weight: .medium, design: .rounded))
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }
            }
            .chartYAxis(.hidden)
            .chartYScale(domain: .automatic(includesZero: true, reversed: true))
            .chartXScale(domain: 0.5...7.5)
            .chartXAxis {
                AxisMarks(preset: .aligned, values: [1, 2, 3, 4, 5, 6, 7]) { value in
                    AxisValueLabel(formatWeekday(value.as(Int.self)!))
                        .font(.system(size: 10))
                }
            }
            .frame(width: 7 * 25) // Adjusted width for better spacing
            .chartOverlay { proxy in
                GeometryReader { geometry in
                    Rectangle().fill(.clear).contentShape(Rectangle())
                        .onTapGesture { location in
                            handleTap(at: location, proxy: proxy, geometry: geometry)
                        }
                }
            }
        }
        .padding()
        
        // Force Portrait when this view appears
        .onAppear {
            setOrientation(.portrait)
        }
}
    
    // MARK: - Logic Helpers
    // Helper function to set orientation
    func setOrientation(_ orientation: UIInterfaceOrientationMask) {
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene {
            let geometryPreferences = UIWindowScene.GeometryPreferences.iOS(interfaceOrientations: orientation)
            windowScene.requestGeometryUpdate(geometryPreferences)
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
        // Using a cleaner green scale
        return Color.green.opacity(min(Double(count) / 10.0 + 0.1, 1.0))
    }
    
    private func handleTap(at location: CGPoint, proxy: ChartProxy, geometry: GeometryProxy) {
        let origin = geometry[proxy.plotAreaFrame].origin
        let locationInPlot = CGPoint(x: location.x - origin.x, y: location.y - origin.y)
        
        if let (day, weekOffset): (Int, Int) = proxy.value(at: locationInPlot) {
            selectedContribution = contributions.first { item in
                weeksAgo(from: item.date) == weekOffset && weekday(item.date) == day
            }
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
