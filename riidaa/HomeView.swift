//
//  ContentView.swift
//  riidaa
//
//  Created by Pierre on 2025/02/12.
//

import SwiftUI
import SwiftData

struct HomeView: View {

    var body: some View {
        TabView {
            MangaListView()
                .tabItem {
                    Label("List", systemImage: "book")
                }
            LookupsView()
                .tabItem {
                    Label("Lookups", systemImage: "magnifyingglass")
                }
            StatsTabView()
                .tabItem {
                    Label("Stats", systemImage: "chart.bar")
                }
            SettingsView()
                .tabItem {
                    Label("Settings", systemImage: "gearshape")
                }
        }
    }

}

#Preview {
    HomeView()
}
