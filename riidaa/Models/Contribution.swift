import Foundation

struct Contribution: Identifiable {
    let date: Date
    let count: Int
    var id: Date { date }
}

extension Contribution {
    // Generates mock data for the last 365 days
    static func generateMockData(days: Int = 365) -> [Contribution] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        return (0..<days).map { offset in
            let date = calendar.date(byAdding: .day, value: -offset, to: today)!
            let count = Int.random(in: 0...10) // Replace with real data later
            return Contribution(date: date, count: count)
        }.reversed()
    }
}
