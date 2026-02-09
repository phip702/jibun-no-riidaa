//
//  riidaaTests.swift
//  riidaaTests
//
//  Created by Pierre on 2025/02/12.
//

import Testing
import Foundation
@testable import riidaa

struct riidaaTests {

    @Test func example() async throws {
        // Write your test here and use APIs like `#expect(...)` to check expected conditions.
    }

    @Test func kanjiLookupInsertAndCount() async throws {
        let mgr = SQLiteManager.shared
        let fixedDate = Date()

        // Insert a kanji lookup (throws on DB errors)
        try mgr.insertKanjiLookupIfKanji("日", date: fixedDate)

        // Query counts over a broad range and assert presence
        let counts = mgr.kanjiLookupCounts(start: nil, end: nil)
        guard counts.contains(where: { $0.kanji == "日" && $0.count >= 1 }) else {
            throw NSError(domain: "riidaaTests", code: 1, userInfo: [NSLocalizedDescriptionKey: "Expected kanji \"日\" in counts"])
        }
    }

}
