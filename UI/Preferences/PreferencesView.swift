//
//  PreferencesView.swift
//  MacMount
//
//  Main preferences window with tabs
//

import SwiftUI

struct PreferencesView: View {
    @EnvironmentObject var appState: AppState
    @State private var selectedTab = "servers"
    
    var body: some View {
        TabView(selection: $selectedTab) {
            ServerListView()
                .tabItem {
                    Label("Servers", systemImage: "server.rack")
                }
                .tag("servers")
            
            GeneralSettingsView()
                .tabItem {
                    Label("General", systemImage: "gear")
                }
                .tag("general")
            
            ConnectionLogsView()
                .tabItem {
                    Label("Logs", systemImage: "doc.text")
                }
                .tag("logs")
        }
        .frame(width: 800, height: 600)
    }
}