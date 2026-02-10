import SwiftUI
import Charts

struct StatsHeatmapView: View {
    let contributions: [Contribution] // pass in immutable array to avoid @State issues

    // Default initializer for previews or normal usage
    init(contributions: [Contribution] = Contribution.generate()) {
        self.contributions = contributions
    }

    var body: some View {
        Chart {
            ForEach(contributions) { contribution in
                RectangleMark(
                    x: .value("Weekday", weekday(contribution.date)),
                    y: .value("Week", contribution.date, unit: .weekOfYear),
                    width: 10,
                    height: 10
                )
                .foregroundStyle(heatmapColor(for: contribution.count))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity) // fill available space
        .padding()
    }

    // MARK: - Helpers

    func weekday(_ date: Date) -> Int {
        let w = Calendar.current.component(.weekday, from: date)
        return (w == 1 ? 7 : w - 1) // Monday = 1 … Sunday = 7
    }

    func heatmapColor(for count: Int) -> Color {
        if count == 0 { return Color(.systemGray5) }
        return Color(.systemGreen).opacity(Double(count) / 10)
    }
}

// MARK: - Preview

struct StatsHeatmapView_Previews: PreviewProvider {
    static var previews: some View {
        TabView {
            NavigationStack {
                StatsHeatmapView() // your chart tab
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
