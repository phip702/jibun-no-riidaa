import Foundation

struct Contribution: Identifiable {
    let date: Date
    let count: Int
    var id: Date { date }
}

extension Contribution {
    static func generate(lastNDays: Int = 364) -> [Contribution] {
        var contributions = [Contribution]()
        let toDate = Date.now
        let fromDate = Calendar.current.date(byAdding: .day, value: -lastNDays, to: toDate)!

        var currentDate = toDate
        while currentDate >= fromDate { // decrementing from newest date until we pass the fromDate
            contributions.append(Contribution(date: currentDate, count: Int.random(in: 0...10)))
            currentDate = Calendar.current.date(byAdding: .day, value: -1, to: currentDate)!
        }

        return contributions
    }
}
