//
//  WaniKaniView.swift
//  riidaa
//
//  Created by GitHub Copilot on 2026/02/07.
//

import SwiftUI

struct WaniKaniView: View {
    
    @EnvironmentObject var settings: SettingsModel
    @State private var apiToken: String = ""
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showSuccess = false
    
    var body: some View {
        Form {
            Section(header: Text("WaniKani Integration")) {
                if let wanikani = settings.wanikaniInfo {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Username:")
                                .foregroundColor(.secondary)
                            Spacer()
                            Text(wanikani.username)
                                .fontWeight(.medium)
                        }
                        
                        HStack {
                            Text("Current Level:")
                                .foregroundColor(.secondary)
                            Spacer()
                            Text("\(wanikani.level)")
                                .fontWeight(.medium)
                                .foregroundColor(.blue)
                        }
                        
                        HStack {
                            Text("Last Sync:")
                                .foregroundColor(.secondary)
                            Spacer()
                            Text(wanikani.lastSync, style: .relative)
                                .foregroundColor(.secondary)
                        }
                        
                        Divider()
                            .padding(.vertical, 4)
                        
                        Text("SRS Progress:")
                            .foregroundColor(.secondary)
                            .font(.caption)
                        
                        ForEach(srsStageBreakdown(wanikani), id: \.category) { item in
                            HStack {
                                Circle()
                                    .fill(item.color)
                                    .frame(width: 10, height: 10)
                                Text(item.category)
                                    .font(.subheadline)
                                Spacer()
                                Text("\(item.count)")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                            }
                        }
                        
                        HStack {
                            Text("Total:")
                                .font(.subheadline)
                                .fontWeight(.medium)
                            Spacer()
                            Text("\(totalKanjiCount(wanikani))")
                                .font(.subheadline)
                                .fontWeight(.medium)
                        }
                    }
                    .padding(.vertical, 4)
                    
                    Toggle("Color Known Kanji", isOn: $settings.wanikaniUnderlineEnabled)
                        .tint(.blue)
                    
                    Button(action: {
                        Task {
                            await syncWaniKani(apiToken: wanikani.apiToken)
                        }
                    }) {
                        HStack {
                            if isLoading {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle())
                                    .scaleEffect(0.8)
                            }
                            Text(isLoading ? "Syncing..." : "Sync Now")
                                .foregroundColor(isLoading ? .secondary : .blue)
                        }
                    }
                    .disabled(isLoading)
                    
                    Button(action: {
                        settings.wanikaniInfo = nil
                        apiToken = ""
                    }) {
                        Text("Disconnect WaniKani")
                            .foregroundColor(.red)
                    }
                } else {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Connect your WaniKani account to underline kanji that are at or below your current level.")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        
                        SecureField("API Token", text: $apiToken)
                            .textFieldStyle(.roundedBorder)
                            .autocapitalization(.none)
                            .disableAutocorrection(true)
                        
                        Button(action: {
                            Task {
                                await syncWaniKani(apiToken: apiToken)
                            }
                        }) {
                            HStack {
                                Spacer()
                                if isLoading {
                                    ProgressView()
                                        .progressViewStyle(CircularProgressViewStyle())
                                        .scaleEffect(0.8)
                                        .tint(.white)
                                }
                                Text(isLoading ? "Connecting..." : "Connect")
                                    .fontWeight(.medium)
                                Spacer()
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(apiToken.isEmpty || isLoading)
                    }
                    .padding(.vertical, 4)
                }
                
                if let error = errorMessage {
                    Text(error)
                        .foregroundColor(.red)
                        .font(.caption)
                }
                
                if showSuccess {
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                        Text("Successfully synced!")
                            .foregroundColor(.green)
                    }
                }
            }
            
            Section(header: Text("How to Get Your API Token")) {
                VStack(alignment: .leading, spacing: 12) {
                    Text("1. Log in to WaniKani")
                    Text("2. Go to Settings → API Tokens")
                    Text("3. Generate a new token")
                    Text("4. Copy and paste it above")
                    
                    Link("Open WaniKani API Settings", destination: URL(string: "https://www.wanikani.com/settings/personal_access_tokens")!)
                        .font(.subheadline)
                }
                .font(.caption)
                .foregroundColor(.secondary)
            }
            
            Section(header: Text("About")) {
                Text("WaniKani is a kanji learning system that teaches kanji progressively through 60 levels. When enabled, kanji at or below your current level will be underlined while reading.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .navigationTitle("WaniKani")
        .navigationBarTitleDisplayMode(.inline)
    }
    
    private func totalKanjiCount(_ info: WaniKaniInfo) -> Int {
        return info.kanjiBySrsStage.count
    }
    
    private func srsStageBreakdown(_ info: WaniKaniInfo) -> [(category: String, count: Int, color: Color)] {
        var stageCounts: [String: Int] = [:]
        for (_, srsStage) in info.kanjiBySrsStage {
            if let stage = WaniKaniSrsStage(rawValue: srsStage) {
                let category = stage.category
                stageCounts[category, default: 0] += 1
            }
        }
        
        let colorMap: [String: Color] = [
            "Apprentice": Color(red: 0.867, green: 0, blue: 0.576),
            "Guru": Color(red: 0.533, green: 0.176, blue: 0.62),
            "Master": Color(red: 0.161, green: 0.302, blue: 0.859),
            "Enlightened": Color(red: 0, green: 0.576, blue: 0.867),
            "Burned": Color(red: 0.263, green: 0.263, blue: 0.263)
        ]
        
        let order = ["Apprentice", "Guru", "Master", "Enlightened", "Burned"]
        return order.compactMap { category in
            if let count = stageCounts[category], let color = colorMap[category] {
                return (category, count, color)
            }
            return nil
        }
    }
    
    private func syncWaniKani(apiToken: String) async {
        guard !apiToken.isEmpty else { return }
        
        isLoading = true
        errorMessage = nil
        showSuccess = false
        
        do {
            let info = try await WaniKaniService.shared.syncWaniKani(apiToken: apiToken)
            await MainActor.run {
                print("💾 Saving WaniKani info to settings...")
                settings.wanikaniInfo = info
                print("✅ WaniKani info saved!")
                print("  Color enabled: \(settings.wanikaniUnderlineEnabled)")
                print("  Info level: \(settings.wanikaniInfo?.level ?? -1)")
                print("  Info kanji count: \(settings.wanikaniInfo?.kanjiBySrsStage.count ?? 0)")
                self.apiToken = ""
                showSuccess = true
                isLoading = false
                
                // Hide success message after 3 seconds
                Task {
                    try? await Task.sleep(nanoseconds: 3_000_000_000)
                    await MainActor.run {
                        showSuccess = false
                    }
                }
            }
        } catch {
            await MainActor.run {
                errorMessage = "Failed to sync: \(error.localizedDescription)"
                isLoading = false
            }
        }
    }
}

#Preview {
    NavigationStack {
        WaniKaniView()
            .environmentObject(SettingsModel())
    }
}
