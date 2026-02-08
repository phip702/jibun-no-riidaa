import SwiftUI

struct LookupRow: Identifiable {
    let id = UUID()
    let dictionaryForm: String
    let reading: String?
    let lookupCount: Int64
}

struct LookupsView: View {

    @State private var rows: [LookupRow] = []

    var body: some View {
        NavigationStack {
            List {
                // Header labels
                HStack {
                    Text("Dictionary Form")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text("Reading")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .frame(width: 120, alignment: .leading)
                    Text("Count")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .frame(width: 60, alignment: .trailing)
                }
                .padding(.vertical, 6)

                ForEach(rows) { row in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(row.dictionaryForm)
                                .font(.body)
                        }
                        Spacer()
                        Text(row.reading ?? "")
                            .frame(width: 120, alignment: .leading)
                            .foregroundColor(.secondary)
                        Text(String(row.lookupCount))
                            .monospacedDigit()
                            .frame(width: 60, alignment: .trailing)
                    }
                    .padding(.vertical, 6)
                }
            }
            .navigationTitle("Lookups")
            .task {
                await loadLookups()
            }
            .refreshable {
                await loadLookups()
            }
        }
    }

    func loadLookups() async {
        var newRows: [LookupRow] = []
        let mgr = SQLiteManager.shared
        guard let db = mgr.getDatabase() else { return }

        let table = mgr.wordLookups
        let df = mgr.lookupDictionaryForm
        let rd = mgr.lookupReading
        let cnt = mgr.lookupCount

        do {
            let query = table.select(cnt, df, rd).order(cnt.desc)
            for row in try db.prepare(query) {
                let dictionaryForm = row[df]
                let reading = row[rd]
                let lookupCount = row[cnt]
                newRows.append(LookupRow(dictionaryForm: dictionaryForm, reading: reading, lookupCount: lookupCount))
            }
        } catch {
            print("Lookups load error: \(error)")
        }

        await MainActor.run {
            rows = newRows
        }
    }

}

#Preview {
    LookupsView()
}
