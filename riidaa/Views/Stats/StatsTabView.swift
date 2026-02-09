import SwiftUI
import Charts
import CoreData

struct StatsTabView: View {
    @State var stats: [(day: Date, count: Int)] = []
    
    var body: some View {
        NavigationStack {
            VStack {
                Text("Stats")
                    .font(.largeTitle)
                    .padding(.top)
                StatsHeatmapView(contributions: stats.map { Contribution(date: $0.day, count: $0.count) })
                    .padding(.top, 8)
                    .padding(.bottom, 4)
                Spacer()
            }
            .onAppear {
                try? fetchPageRead()
            }
        }
        .tabItem {
            Image(systemName: "chart.bar")
            Text("Stats")
        }
    }
    
    func fetchPageRead() throws {
        let request = NSFetchRequest<MangaPageModel>(entityName: "MangaPageModel")
        request.predicate = NSPredicate(format: "read_at != nil")
        let pages = try CoreDataManager.shared.container.viewContext.fetch(request)
        let calendar = Calendar.current
        var results: [Date: Int] = [:]
        for page in pages {
            guard let readAt = page.read_at else { continue }
            let day = calendar.startOfDay(for: readAt as Date)
            results[day, default: 0] += 1
        }
        // Fill in all days for the last 365 days, starting from today - 364 days (top left)
        let today = calendar.startOfDay(for: Date())
        let startDate = calendar.date(byAdding: .day, value: -364, to: today)!
        let days = (0..<365).map { offset in
            calendar.date(byAdding: .day, value: offset, to: startDate)!
        }
        self.stats = days.map { day in
            (day: day, count: results[day] ?? 0)
        }
    }
}
