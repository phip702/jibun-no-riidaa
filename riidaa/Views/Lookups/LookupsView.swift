import SwiftUI
#if canImport(UIKit)
import UIKit
#else
import AppKit
#endif

struct LookupRow: Identifiable {
    let id = UUID()
    let dictionaryForm: String
    let reading: String?
    let lookupCount: Int64
}

struct LookupsView: View {

    @State private var rows: [LookupRow] = []
    @State private var showCopied: Bool = false
    @State private var copiedText: String = ""

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
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
                    .contentShape(Rectangle())
                    .onTapGesture {
                        // Copy dictionary form to clipboard
                        let toCopy = row.dictionaryForm
#if canImport(UIKit)
                        UIPasteboard.general.string = toCopy
#else
                        let pb = NSPasteboard.general
                        pb.clearContents()
                        pb.setString(toCopy, forType: .string)
#endif
                        copiedText = toCopy
                        withAnimation {
                            showCopied = true
                        }
                        Task {
                            try? await Task.sleep(nanoseconds: 1_600_000_000) // 1.6s
                            withAnimation {
                                showCopied = false
                            }
                        }
                    }
                    .accessibilityAddTraits(.isButton)
                    .accessibilityLabel("Copy \(row.dictionaryForm) to clipboard")
                }
                }
                .navigationTitle("Lookups")
                .task {
                    await loadLookups()
                }
                .refreshable {
                    await loadLookups()
                }

                // Toast / Copied indicator
                if showCopied {
                    HStack(spacing: 12) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.white)
                        Text("Copied \(copiedText)")
                            .foregroundColor(.white)
                            .lineLimit(1)
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
