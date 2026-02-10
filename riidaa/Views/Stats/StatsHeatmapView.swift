import SwiftUI
import Charts

struct StatsHeatmapView: View {
    let contributions: [Contribution]
    @State private var selectedContribution: Contribution?
    
    // Use a Monday-start calendar
    var calendar: Calendar {
        var cal = Calendar.current
        cal.firstWeekday = 2 // Monday
        return cal
    }
    let today = Date()
    
    init(contributions: [Contribution] = Contribution.generate()) {
        self.contributions = contributions
    }
    
    var body: some View {
        VStack(alignment: .leading) {
            headerView
            
            Chart {
                ForEach(contributions) { contribution in
                    // Only draw if the date is NOT in the future
                    if contribution.date <= today {
                        RectangleMark(
                            x: .value("Weekday", weekday(contribution.date)),
                            y: .value("Weeks Ago", weeksAgo(from: contribution.date)),
                            width: 10,
                            height: 8
                        )
                        .foregroundStyle(heatmapColor(for: contribution.count))
                        .opacity(selectedContribution?.id == contribution.id ? 0.5 : 1.0)
                    }
                }
            }
            .chartYAxis(.hidden)
            // Reverse so week 0 is top
            .chartYScale(domain: .automatic(includesZero: true, reversed: true))
            .chartXAxis {
                AxisMarks(values: Array(1...7)) { value in
                    AxisValueLabel(formatWeekday(value.as(Int.self) ?? 0))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
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
    }
    
    // MARK: - The Logic Fix
    
    func weeksAgo(from date: Date) -> Int {
        let startOfToday = calendar.startOfDay(for: today)
        let startOfDate = calendar.startOfDay(for: date)
        
        // Find the Monday of the week for both dates
        let mondayOfToday = calendar.dateComponents([.calendar, .yearForWeekOfYear, .weekOfYear], from: startOfToday).date!
        let mondayOfDate = calendar.dateComponents([.calendar, .yearForWeekOfYear, .weekOfYear], from: startOfDate).date!
        
        let diff = calendar.dateComponents([.weekOfYear], from: mondayOfDate, to: mondayOfToday)
        return diff.weekOfYear ?? 0
    }
    
    func weekday(_ date: Date) -> Int {
        let w = calendar.component(.weekday, from: date)
        // Adjusting so Monday is 1, Sunday is 7 based on a Monday-start calendar
        return (w == 1 ? 7 : w - 1)
    }
    
    // MARK: - Handlers & Helpers
    
    private func handleTap(at location: CGPoint, proxy: ChartProxy, geometry: GeometryProxy) {
        let origin = geometry[proxy.plotAreaFrame].origin
        let locationInPlot = CGPoint(x: location.x - origin.x, y: location.y - origin.y)
        
        if let (day, weekOffset): (Int, Int) = proxy.value(at: locationInPlot) {
            selectedContribution = contributions.first { item in
                weeksAgo(from: item.date) == weekOffset && weekday(item.date) == day
            }
        }
    }
    
    func formatWeekday(_ day: Int) -> String {
        let labels = ["M", "T", "W", "T", "F", "S", "S"]
        return labels[day - 1]
    }
    
    func heatmapColor(for count: Int) -> Color {
        if count == 0 { return Color(.systemGray5) }
        return Color.green.opacity(Double(count) / 10.0)
    }
    
    var headerView: some View {
        HStack(spacing: 8) { // Adjust spacing to your liking
            if let selected = selectedContribution {
                Text(selected.date.formatted(date: .abbreviated, time: .omitted))
                Text("•") // Optional separator
                Text("\(selected.count) Pages")
            } else {
                Text("Activity")
                Text("•")
                Text("Last 52 Weeks")
            }
        }
        .font(.title2.bold()) // Applies to all Text inside the HStack
        .foregroundColor(.primary)
        .frame(maxWidth: .infinity, alignment: .leading) // Keeps everything left-aligned
        .padding(.bottom, 1)
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
