import SwiftUI
#if canImport(UIKit)
import UIKit
#else
import AppKit
#endif

enum DateRangeOption: String, CaseIterable, Identifiable {
    case last24h = "last_24h"
    case last7d = "last_7d"
    case last30d = "last_30d"
    case lastYear = "last_year"
    case allTime = "all_time"

    var id: String { rawValue }
    var label: String {
        switch self {
        case .last24h: return "Last 24 Hours"
        case .last7d: return "Last 7 Days"
        case .last30d: return "Last 30 Days"
        case .lastYear: return "Last Year"
        case .allTime: return "All Time"
        }
    }
    func cutoffDate() -> Date? {
        let now = Date()
        switch self {
        case .last24h: return Calendar.current.date(byAdding: .hour, value: -24, to: now)
        case .last7d: return Calendar.current.date(byAdding: .day, value: -7, to: now)
        case .last30d: return Calendar.current.date(byAdding: .day, value: -30, to: now)
        case .lastYear: return Calendar.current.date(byAdding: .year, value: -1, to: now)
        case .allTime: return nil
        }
    }
}

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
    @AppStorage("lookups_date_range") private var lookupsDateRangeRaw: String = DateRangeOption.last30d.rawValue
    private var selectedRange: DateRangeOption {
        get { DateRangeOption(rawValue: lookupsDateRangeRaw) ?? .last30d }
        set { lookupsDateRangeRaw = newValue.rawValue }
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                List {
                    Section(header:
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("Lookups")
                                    .font(.largeTitle)
                                    .bold()
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .lineLimit(1)
                                    .truncationMode(.tail)
                                    
                                Spacer()
                                Menu {
                                    ForEach(DateRangeOption.allCases) { opt in
                                        Button(opt.label) {
                                            lookupsDateRangeRaw = opt.rawValue
                                            Task { await loadLookups() }
                                        }
                                    }
                                } label: {
                                    Text(selectedRange.label)
                                        .font(.body)
                                        .bold()
                                        .frame(height: 40)
                                }
                            }

                            // Header labels
                            HStack {
                                Text("Dictionary Form")
                                    .font(.body)
                                    .bold()
                                    .foregroundColor(.primary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                Text("Reading")
                                    .font(.body)
                                    .bold()
                                    .foregroundColor(.primary)
                                    .frame(width: 120, alignment: .leading)
                                Text("Count")
                                    .font(.body)
                                    .bold()
                                    .foregroundColor(.primary)
                                    .frame(width: 60, alignment: .trailing)
                            }
                            .padding(.vertical, 6)
                        }
                        .frame(maxWidth: .infinity)
                        .background(
                            Group {
                                #if canImport(UIKit)
                                Color(UIColor.systemBackground)
                                #else
                                Color(NSColor.windowBackgroundColor)
                                #endif
                            }
                        )
                        .overlay(
                            Rectangle()
                                .frame(height: 1)
                                .foregroundColor(Color.primary.opacity(0.08)),
                            alignment: .bottom
                        )
                        .padding(.horizontal, 0)
                    ) {
                        ForEach(rows) { row in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(row.dictionaryForm)
                                .font(.body)
                                .bold()
                        }
                        Spacer()
                        Text(row.reading ?? "")
                            .font(.body)
                            .frame(width: 120, alignment: .leading)
                            .foregroundColor(.secondary)
                            .bold()
                        Text(String(row.lookupCount))
                            .font(.body)
                            .monospacedDigit()
                            .frame(width: 60, alignment: .trailing)
                            .bold()
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
                }
                .headerProminence(.increased)
                .listStyle(.plain)
                .bold()
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
    }

    func loadLookups() async {
        var newRows: [LookupRow] = []
        let mgr = SQLiteManager.shared
        guard let db = mgr.getDatabase() else { return }

        // Aggregate lookup_events by form and reading, returning counts
        do {
            // Compute cutoff ISO if the selected range has one
            let cutoffISO: String? = {
                if let cutoff = selectedRange.cutoffDate() {
                    return ISO8601DateFormatter().string(from: cutoff)
                } else {
                    return nil
                }
            }()

            var sql = """
            SELECT dictionaryForm, reading, COUNT(date) as lookupCount
            FROM lookup_events
            """
            if let cutoffISO = cutoffISO {
                sql += " WHERE date >= '\(cutoffISO)'"
            }
            sql += " GROUP BY dictionaryForm, reading ORDER BY lookupCount DESC;"

            for row in try db.prepare(sql) {
                // row columns: 0: dictionaryForm, 1: reading, 2: lookupCount
                let dictionaryForm = row[0] as? String ?? ""
                let reading = row[1] as? String
                let lookupCountAny = row[2]
                var lookupCount: Int64 = 0
                if let v = lookupCountAny as? Int64 {
                    lookupCount = v
                } else if let v = lookupCountAny as? Int {
                    lookupCount = Int64(v)
                }
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
