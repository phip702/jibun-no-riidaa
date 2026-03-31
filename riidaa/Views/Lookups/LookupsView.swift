import SwiftUI
#if canImport(UIKit)
import UIKit
#else
import AppKit
#endif

enum DateRangeOption: String, CaseIterable, Identifiable {
    case lastHour = "last_1h"
    case last24h = "last_24h"
    case last7d = "last_7d"
    case last30d = "last_30d"
    case lastYear = "last_year"
    case allTime = "all_time"

    var id: String { rawValue }
    var label: String {
        switch self {
        case .lastHour: return "Last Hour"
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
        case .lastHour: return Calendar.current.date(byAdding: .hour, value: -1, to: now)
        case .last24h: return Calendar.current.date(byAdding: .hour, value: -24, to: now)
        case .last7d: return Calendar.current.date(byAdding: .day, value: -7, to: now)
        case .last30d: return Calendar.current.date(byAdding: .day, value: -30, to: now)
        case .lastYear: return Calendar.current.date(byAdding: .year, value: -1, to: now)
        case .allTime: return nil
        }
    }
}

enum LookupMode: String, CaseIterable, Identifiable {
    case word = "word"
    case kanji = "kanji"

    var id: String { rawValue }
    var label: String {
        switch self {
        case .word: return "Word"
        case .kanji: return "Kanji"
        }
    }
}

struct LookupRow: Identifiable {
    let id = UUID()
    let dictionaryForm: String
    let reading: String?
    let lookupCount: Int64
    // Optional WaniKani info (kanji-only rows)
    let wanikaniReading: String?
    let wanikaniMeaning: String?
    let wanikaniLevel: Int?
    let wanikaniSrsStage: Int?
}

struct LookupsView: View {

    // Minimum width for Kanji and Cnt columns
    private let colMinWidth: CGFloat = 40
    // Base font sizes for scaling with Dynamic Type
    @ScaledMetric private var baseHeaderSize: CGFloat = 12
    @ScaledMetric private var baseRowSize: CGFloat = 12

    @State private var rows: [LookupRow] = []
    @EnvironmentObject var settings: SettingsModel
    @State private var showCopied: Bool = false
    @State private var copiedText: String = ""
    @State private var selectedRow: LookupRow?
    @AppStorage("lookups_date_range") private var lookupsDateRangeRaw: String = DateRangeOption.last30d.rawValue
    @AppStorage("lookups_mode") private var lookupsModeRaw: String = LookupMode.word.rawValue
    private var selectedRange: DateRangeOption {
        get { DateRangeOption(rawValue: lookupsDateRangeRaw) ?? .last30d }
        set { lookupsDateRangeRaw = newValue.rawValue }
    }
    private var selectedMode: LookupMode {
        get { LookupMode(rawValue: lookupsModeRaw) ?? .word }
        set { lookupsModeRaw = newValue.rawValue }
    }

    private var sectionHeader: some View {
        VStack(alignment: .leading, spacing: 8) {
            let modeMenu = Menu {
                ForEach(LookupMode.allCases) { m in
                    Button(m.label) {
                        lookupsModeRaw = m.rawValue
                        Task { await loadLookups() }
                    }
                }
            } label: {
                Text(selectedMode.label)
                    .font(.title)
                    .bold()
                    .lineLimit(1)
                    .truncationMode(.tail)
            }

            let lookupsTitle = Text("Lookups")
                                .font(.title)
                                .bold()
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .lineLimit(1)
                                .truncationMode(.tail)
            let dateMenu = Menu {
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

            HStack(spacing: 8) {
                modeMenu
                lookupsTitle
                Spacer()
                dateMenu
            }

            // Header labels (switch for Word vs Kanji view)
            if selectedMode == .word {
                HStack {
                    Text("Dictionary Form")
                        .font(.system(size: baseHeaderSize, weight: .bold))
                        .foregroundColor(.primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text("Reading")
                        .font(.system(size: baseHeaderSize, weight: .bold))
                        .foregroundColor(.primary)
                        .frame(width: 120, alignment: .leading)
                    Text("Cnt")
                        .font(.system(size: baseHeaderSize, weight: .bold))
                        .foregroundColor(.primary)
                        .frame(width: 60, alignment: .trailing)
                }
                .padding(.vertical, 6)
            } else {
                HStack {
                    Text("Kanji")
                        .font(.system(size: baseHeaderSize, weight: .bold))
                        .foregroundColor(.primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                        .frame(width: 30, alignment: .leading)
                    Text("Lvl")
                        .font(.system(size: baseHeaderSize, weight: .bold))
                        .foregroundColor(.primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text("WK Meaning")
                        .font(.system(size: baseHeaderSize, weight: .bold))
                        .foregroundColor(.primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text("WK Reading")
                        .font(.system(size: baseHeaderSize, weight: .bold))
                        .foregroundColor(.primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text("Cnt")
                        .font(.system(size: baseHeaderSize, weight: .bold))
                        .foregroundColor(.primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                        .frame(width: 20, alignment: .trailing)
                }
                .padding(.vertical, 6)
            }
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
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                List {
                    Section(header: sectionHeader) {
                        ForEach(rows) { row in
                            HStack {
                                if selectedMode == .kanji {
                                    HStack(alignment: .center, spacing: 6) {
                                        // Kanji column: kanji itself (much bigger font)
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(row.dictionaryForm)
                                                .font(.system(size: 32, weight: .bold))
                                        }
                                        .frame(width: 30, alignment: .leading) // Kanji column width

                                        // Lvl column (dynamic font)
                                        VStack(alignment: .leading, spacing: 2) {
                                            if row.wanikaniLevel == nil && row.wanikaniSrsStage == nil {
                                                Text("n/a")
                                                    .font(.system(size: baseRowSize))
                                                    .foregroundColor(.secondary)
                                            } else {
                                                if let level = row.wanikaniLevel {
                                                    Text("Lvl \(level)")
                                                        .font(.system(size: baseRowSize))
                                                        .foregroundColor(.secondary)
                                                }
                                                if let s = row.wanikaniSrsStage, let stage = WaniKaniSrsStage(rawValue: s) {
                                                    Text(stage.category)
                                                        .font(.system(size: baseRowSize))
                                                        .foregroundColor(srsTextColor(row.wanikaniSrsStage))
                                                }
                                            }
                                        }
                                        .frame(maxWidth: .infinity, alignment: .leading)

                                        // Meaning column (dynamic font)
                                        Text(row.wanikaniMeaning ?? "")
                                            .font(.system(size: baseRowSize))
                                            .foregroundColor(.secondary)
                                            .frame(maxWidth: .infinity, alignment: .leading)

                                        // Reading column (dynamic font)
                                        Text(row.wanikaniReading ?? "")
                                            .font(.system(size: baseRowSize))
                                            .foregroundColor(.secondary)
                                            .lineLimit(1)
                                            .truncationMode(.tail)
                                            .frame(maxWidth: .infinity, alignment: .leading)

                                        // Count (dynamic font)
                                        Text(String(row.lookupCount))
                                            .font(.system(size: baseRowSize))
                                            .monospacedDigit()
                                            .frame(width: 20, alignment: .trailing) //count column width
                                            .bold()
                                    }
                                } else {
                                    VStack(alignment: .leading) {
                                        Text(row.dictionaryForm)
                                            .font(.system(size: baseRowSize * 1.6, weight: .bold))
                                    }
                                    Spacer()
                                    Text(row.reading ?? "")
                                        .font(.system(size: baseRowSize * 1.6))
                                        .frame(width: 120, alignment: .leading)
                                        .foregroundColor(.secondary)
                                        .bold()
                                    Text(String(row.lookupCount))
                                        .font(.system(size: baseRowSize))
                                        .monospacedDigit()
                                        .frame(width: 60, alignment: .trailing)
                                        .bold()
                                }
                            }
                            .padding(.vertical, 0)
                            .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
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
                                if selectedMode == .word {
                                    selectedRow = row
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
            .sheet(item: $selectedRow) { row in
                SelectedLookupView(dictionaryForm: row.dictionaryForm, reading: row.reading)
                    .environmentObject(settings)
            }
        }
    }

    func loadLookups() async {
        var newRows: [LookupRow] = []
        let mgr = SQLiteManager.shared
        guard let db = mgr.getDatabase() else { return }

        // Aggregate lookup_events by form and reading, returning counts
        do {
            if selectedMode == .kanji {
                // Use the manager helper to get kanji counts filtered by the selected date range
                let startDate = selectedRange.cutoffDate()
                let kanjiCounts = mgr.kanjiLookupCounts(start: startDate, end: nil)
                for (kanji, count) in kanjiCounts {
                    // Pull any available WaniKani info from settings (do not trigger a sync)
                    var wkReading: String? = nil
                    var wkMeaning: String? = nil
                    var wkLevel: Int? = nil
                    var wkSrsStage: Int? = nil

                    if let wanikani = settings.wanikaniInfo {
                        // Prefer per-kanji level if available, otherwise leave nil
                        if let lvl = wanikani.kanjiLevels?[kanji] {
                            wkLevel = lvl
                        }
                        if let s = wanikani.kanjiBySrsStage[kanji] {
                            wkSrsStage = s
                        }
                    }

                    // Try to find a local dictionary entry (WaniKani dictionary) for reading/meaning
                    // Use the higher-level API which returns TermDB objects and includes the dictionary metadata,
                    // then filter by dictionary title/attribution containing 'wanikani'. This is more robust
                    // than raw SQL and avoids issues with column types.
                    let candidatesArray = mgr.findTerms(texts: [kanji])
                    let candidates = candidatesArray as? [TermDB] ?? []
                    if !candidates.isEmpty {
                        if let match = candidates.first(where: { dic in
                            let titleLower = dic.dictionary.title.lowercased()
                            let attrLower = (dic.dictionary.attribution ?? "").lowercased()
                            return titleLower.contains("wanikani") || attrLower.contains("wanikani")
                        }) {
                            // importer maps the second field to `reading` (which for WaniKani is the English meaning)
                            wkMeaning = match.reading

                            // definitions is stored as Data; attempt to parse the stored JSON and extract any
                            // entry that looks like a Reading (e.g. "Reading: しち") or objects with `text`.
                            if let defData = match.definitions as Data? {
                                if let decoded = (try? JSONSerialization.jsonObject(with: defData)) as? [Any] {
                                    for entry in decoded {
                                        if let s = entry as? String {
                                            let lowered = s.lowercased()
                                            if lowered.hasPrefix("reading:") {
                                                if let idx = s.firstIndex(of: ":") {
                                                    let after = s[s.index(after: idx)...]
                                                    let trimmed = String(after).trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
                                                    wkReading = trimmed
                                                    break
                                                }
                                            }
                                        } else if let dict = entry as? [String: Any], let text = dict["text"] as? String {
                                            wkReading = text
                                            break
                                        }
                                    }
                                }
                            }
                        }
                    }

                    newRows.append(LookupRow(dictionaryForm: kanji, reading: nil, lookupCount: Int64(count), wanikaniReading: wkReading ?? "n/a", wanikaniMeaning: wkMeaning ?? "n/a", wanikaniLevel: wkLevel, wanikaniSrsStage: wkSrsStage))
                }
            } else {
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
                    newRows.append(LookupRow(dictionaryForm: dictionaryForm, reading: reading, lookupCount: lookupCount, wanikaniReading: nil, wanikaniMeaning: nil, wanikaniLevel: nil, wanikaniSrsStage: nil))
                }
            }
        } catch {
            print("Lookups load error: \(error)")
        }

        await MainActor.run {
            rows = newRows
        }
    }

    private func srsTextColor(_ srsStage: Int?) -> Color {
        guard let s = srsStage, let stage = WaniKaniSrsStage(rawValue: s) else {
            return Color.primary
        }
        switch stage {
        case .apprentice1, .apprentice2, .apprentice3, .apprentice4:
            return Color(red: 0.867, green: 0, blue: 0.576)
        case .guru1, .guru2:
            return Color(red: 0.533, green: 0.176, blue: 0.62)
        case .master:
            return Color(red: 0.161, green: 0.302, blue: 0.859)
        case .enlightened:
            return Color(red: 0, green: 0.576, blue: 0.867)
        case .burned:
            return Color(red: 0.263, green: 0.263, blue: 0.263)
        }
    }

}
