//
//  WaniKaniModel.swift
//  riidaa
//
//  Created by GitHub Copilot on 2026/02/07.
//

import Foundation

// MARK: - WaniKani API Response Models
struct WaniKaniUser: Codable {
    let data: WaniKaniUserData
}

struct WaniKaniUserData: Codable {
    let level: Int
    let username: String
    let subscription: WaniKaniSubscription
}

struct WaniKaniSubscription: Codable {
    let active: Bool
    let type: String
    let maxLevelGranted: Int
    
    enum CodingKeys: String, CodingKey {
        case active
        case type
        case maxLevelGranted = "max_level_granted"
    }
}

struct WaniKaniAssignments: Codable {
    let data: [WaniKaniAssignmentData]
}

struct WaniKaniAssignmentData: Codable {
    let data: WaniKaniAssignment
}

struct WaniKaniAssignment: Codable {
    let subjectId: Int
    let subjectType: String
    let srsStage: Int
    let unlockedAt: String?
    
    enum CodingKeys: String, CodingKey {
        case subjectId = "subject_id"
        case subjectType = "subject_type"
        case srsStage = "srs_stage"
        case unlockedAt = "unlocked_at"
    }
}

struct WaniKaniSubjects: Codable {
    let data: [WaniKaniSubjectData]
}

struct WaniKaniSubjectData: Codable {
    let id: Int
    let object: String
    let data: WaniKaniSubject
}

struct WaniKaniSubject: Codable {
    let characters: String?
    let level: Int
}

// MARK: - WaniKani SRS Stage
enum WaniKaniSrsStage: Int, Codable {
    case apprentice1 = 1
    case apprentice2 = 2
    case apprentice3 = 3
    case apprentice4 = 4
    case guru1 = 5
    case guru2 = 6
    case master = 7
    case enlightened = 8
    case burned = 9
    
    var category: String {
        switch self {
        case .apprentice1, .apprentice2, .apprentice3, .apprentice4:
            return "Apprentice"
        case .guru1, .guru2:
            return "Guru"
        case .master:
            return "Master"
        case .enlightened:
            return "Enlightened"
        case .burned:
            return "Burned"
        }
    }
}

// MARK: - WaniKani Info for Storage
struct WaniKaniInfo: Codable {
    let apiToken: String
    let level: Int
    let username: String
    let lastSync: Date
    let kanjiBySrsStage: [String: Int] // kanji character -> SRS stage
    let kanjiLevels: [String: Int]? // kanji character -> WaniKani level (optional)

    enum CodingKeys: String, CodingKey {
        case apiToken, level, username, lastSync, kanjiBySrsStage, kanjiLevels
    }
    
    init(apiToken: String, level: Int, username: String, lastSync: Date, kanjiBySrsStage: [String: Int], kanjiLevels: [String: Int]?) {
        self.apiToken = apiToken
        self.level = level
        self.username = username
        self.lastSync = lastSync
        self.kanjiBySrsStage = kanjiBySrsStage
        self.kanjiLevels = kanjiLevels
    }
}

// MARK: - WaniKani API Service
class WaniKaniService {
    static let shared = WaniKaniService()
    private let baseURL = "https://api.wanikani.com/v2"
    
    private init() {}
    
    func fetchUserInfo(apiToken: String) async throws -> (level: Int, username: String) {
        let url = URL(string: "\(baseURL)/user")!
        var request = URLRequest(url: url)
        request.setValue("Bearer \(apiToken)", forHTTPHeaderField: "Authorization")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }
        
        let user = try JSONDecoder().decode(WaniKaniUser.self, from: data)
        return (user.data.level, user.data.username)
    }
    
    func fetchKanjiByLevel(apiToken: String) async throws -> [String: Int] {
        // Return mapping of kanji character -> level
        var kanjiLevels: [String: Int] = [:]
        var nextURL: String? = "\(baseURL)/subjects?types=kanji"
        
        while let urlString = nextURL {
            guard let url = URL(string: urlString) else { break }
            var request = URLRequest(url: url)
            request.setValue("Bearer \(apiToken)", forHTTPHeaderField: "Authorization")
            
            let (data, response) = try await URLSession.shared.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                throw URLError(.badServerResponse)
            }
            
            let decoder = JSONDecoder()
            let subjects = try decoder.decode(WaniKaniSubjects.self, from: data)
            
            // Process kanji from this page - map ID to character
            for subjectData in subjects.data {
                if subjectData.object == "kanji", let character = subjectData.data.characters {
                    kanjiLevels[character] = subjectData.data.level
                }
            }
            
            // Check for next page
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let pages = json["pages"] as? [String: Any],
               let next = pages["next_url"] as? String {
                nextURL = next
            } else {
                nextURL = nil
            }
        }
        
        return kanjiLevels
    }
    
    func fetchAssignments(apiToken: String) async throws -> [Int: Int] {
        var assignmentsBySubjectId: [Int: Int] = [:]
        var nextURL: String? = "\(baseURL)/assignments?subject_types=kanji"
        
        while let urlString = nextURL {
            guard let url = URL(string: urlString) else { break }
            var request = URLRequest(url: url)
            request.setValue("Bearer \(apiToken)", forHTTPHeaderField: "Authorization")
            
            let (data, response) = try await URLSession.shared.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                throw URLError(.badServerResponse)
            }
            
            let decoder = JSONDecoder()
            let assignments = try decoder.decode(WaniKaniAssignments.self, from: data)
            
            // Process assignments - map subject ID to SRS stage
            for assignmentData in assignments.data {
                if assignmentData.data.subjectType == "kanji" {
                    assignmentsBySubjectId[assignmentData.data.subjectId] = assignmentData.data.srsStage
                }
            }
            
            // Check for next page
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let pages = json["pages"] as? [String: Any],
               let next = pages["next_url"] as? String {
                nextURL = next
            } else {
                nextURL = nil
            }
        }
        
        return assignmentsBySubjectId
    }
    
    func syncWaniKani(apiToken: String) async throws -> WaniKaniInfo {
        let (level, username) = try await fetchUserInfo(apiToken: apiToken)
        let kanjiLevels = try await fetchKanjiByLevel(apiToken: apiToken)
        // fetchAssignments returns mapping subjectId -> srsStage; we need kanji characters for that mapping
        // Re-fetch subjects mapping id->character to map assignments -> character
        var kanjiById: [Int: String] = [:]
        var nextURL: String? = "\(baseURL)/subjects?types=kanji"
        while let urlString = nextURL {
            guard let url = URL(string: urlString) else { break }
            var request = URLRequest(url: url)
            request.setValue("Bearer \(apiToken)", forHTTPHeaderField: "Authorization")
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                throw URLError(.badServerResponse)
            }
            let decoder = JSONDecoder()
            let subjects = try decoder.decode(WaniKaniSubjects.self, from: data)
            for subjectData in subjects.data {
                if subjectData.object == "kanji", let character = subjectData.data.characters {
                    kanjiById[subjectData.id] = character
                }
            }
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let pages = json["pages"] as? [String: Any],
               let next = pages["next_url"] as? String {
                nextURL = next
            } else {
                nextURL = nil
            }
        }

        let assignmentsBySubjectId = try await fetchAssignments(apiToken: apiToken)

        // Map kanji characters to their SRS stages
        var kanjiBySrsStage: [String: Int] = [:]
        for (subjectId, character) in kanjiById {
            if let srsStage = assignmentsBySubjectId[subjectId] {
                kanjiBySrsStage[character] = srsStage
            }
        }
        
        print("📊 WaniKani Sync Complete:")
        print("  Username: \(username)")
        print("  Level: \(level)")
        print("  Total kanji subjects: \(kanjiById.count)")
        print("  Total active assignments: \(kanjiBySrsStage.count)")
        
        // Count by SRS stage
        var stageCounts: [String: Int] = [:]
        for (_, srsStage) in kanjiBySrsStage {
            if let stage = WaniKaniSrsStage(rawValue: srsStage) {
                let category = stage.category
                stageCounts[category, default: 0] += 1
            }
        }
        
        for (category, count) in stageCounts.sorted(by: { $0.key < $1.key }) {
            print("  \(category): \(count) kanji")
        }
        
        return WaniKaniInfo(
            apiToken: apiToken,
            level: level,
            username: username,
            lastSync: Date(),
            kanjiBySrsStage: kanjiBySrsStage,
            kanjiLevels: kanjiLevels
        )
    }
}
