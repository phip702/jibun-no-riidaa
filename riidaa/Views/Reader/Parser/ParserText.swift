//
//  ParserText.swift
//  riidaa
//
//  Created by Pierre on 2025/04/18.
//

import SwiftUI

struct ParserText: View {
    
    @State var text: String
    @EnvironmentObject var settings: SettingsModel
    
    var body: some View {
        let _ = print("🔍 ParserText render - enabled: \(settings.wanikaniUnderlineEnabled), hasInfo: \(settings.wanikaniInfo != nil), text: '\(text.prefix(10))...'")
        
        if settings.wanikaniUnderlineEnabled, let wanikani = settings.wanikaniInfo {
            Text(attributedText(for: text, wanikani: wanikani))
        } else {
            Text("\(text)")
        }
    }
    
    private func attributedText(for text: String, wanikani: WaniKaniInfo) -> AttributedString {
        var result = AttributedString(text)
        
        print("🔍 WaniKani Debug:")
        print("  Level: \(wanikani.level)")
        print("  Total known kanji: \(wanikani.kanjiBySrsStage.count)")
        print("  Text to process: \(text)")
        
        // Process each character
        for (index, character) in text.enumerated() {
            let characterStr = String(character)
            
            // Check if this character has a WaniKani SRS stage
            if let srsStage = wanikani.kanjiBySrsStage[characterStr],
               let stage = WaniKaniSrsStage(rawValue: srsStage) {
                print("  ✓ Found \(stage.category) kanji: \(characterStr)")
                
                // Calculate the range for this character in the AttributedString
                let stringIndex = text.index(text.startIndex, offsetBy: index)
                let nextIndex = text.index(after: stringIndex)
                let range = stringIndex..<nextIndex
                
                // Apply color based on SRS stage (Tsurukame colors)
                if let attributedRange = Range(range, in: result) {
                    let color: Color
                    switch stage.category {
                    case "Apprentice":
                        color = Color(red: 0.867, green: 0, blue: 0.576) // #DD0093
                    case "Guru":
                        color = Color(red: 0.533, green: 0.176, blue: 0.62) // #882D9E
                    case "Master":
                        color = Color(red: 0.161, green: 0.302, blue: 0.859) // #294DDB
                    case "Enlightened":
                        color = Color(red: 0, green: 0.576, blue: 0.867) // #0093DD
                    case "Burned":
                        color = Color(red: 0.263, green: 0.263, blue: 0.263) // #434343
                    default:
                        color = .primary
                    }
                    result[attributedRange].foregroundColor = color
                }
            }
        }
        
        return result
    }
}

#Preview {
    ParserText(text: "blabla")
        .environmentObject(SettingsModel())
}

