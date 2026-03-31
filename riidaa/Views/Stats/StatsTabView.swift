import SwiftUI
import Charts
import CoreData

struct StatsTabView: View {
    @State var stats: [(day: Date, count: Int)] = []
    @State private var showUpdated: Bool = false
    @State private var dragOffset: CGFloat = 0
    @State private var isRefreshing: Bool = false
    
    var body: some View {
        NavigationStack {
            GeometryReader { geo in
                ZStack(alignment: .bottom) {
                    VStack(spacing: 0) {
                        // Spinner appears above the content when pulling
                        if dragOffset > 40 || isRefreshing {
                            ProgressView()
                                .padding(.vertical, 12)
                        }
                        
                        StatsHeatmapView(contributions: stats.map { Contribution(date: $0.day, count: $0.count) })
                            .padding(.top, 8)
                            .padding(.bottom, 4)
                        Spacer()
                    }
                    .frame(minHeight: geo.size.height)
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 20)
                            .onChanged { value in
                                if !isRefreshing && value.translation.height > 0 {
                                    dragOffset = value.translation.height
                                }
                            }
                            .onEnded { value in
                                if !isRefreshing && dragOffset > 80 {
                                    isRefreshing = true
                                    withAnimation(.easeOut(duration: 0.25)) {
                                        dragOffset = 0
                                    }
                                    Task {
                                        try? await fetchPageRead()
                                        withAnimation(.easeOut(duration: 0.2)) {
                                            isRefreshing = false
                                        }
                                        withAnimation {
                                            showUpdated = true
                                        }
                                        try? await Task.sleep(nanoseconds: 1_000_000_000)
                                        withAnimation {
                                            showUpdated = false
                                        }
                                    }
                                } else {
                                    withAnimation(.easeOut(duration: 0.25)) {
                                        dragOffset = 0
                                    }
                                }
                            }
                    )

                    if showUpdated {
                        HStack(spacing: 12) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.white)
                            Text("Pages Read Stats Updated")
                                .foregroundColor(.white)
                                .lineLimit(1)
                                .bold()
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(Color.black.opacity(0.8))
                        .cornerRadius(12)
                        .padding(.bottom, 24)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                        .zIndex(1)
                    }
                }
            }
            .onAppear {
                Task { try? await fetchPageRead() }
            }
        }
        .tabItem {
            Image(systemName: "chart.bar")
            Text("Stats")
        }
    }
    
    func fetchPageRead() async throws {
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
