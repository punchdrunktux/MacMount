//
//  MacMountApp.swift
//  MacMount
//
//  Main application entry point
//

import SwiftUI

@main
struct MacMountApp: App {
    @StateObject private var appState = AppState()
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @State private var showFirstRunSetup = false
    
    init() {
        // Check if this is first run in sandboxed environment
        checkFirstRun()
    }
    
    var body: some Scene {
        // Menu bar interface is handled by AppDelegate using SwiftUI
        // Assign appState to delegate when app starts
        Window("Hidden", id: "hidden") {
            EmptyView()
                .onAppear {
                    // Pass appState to the delegate for menu bar integration
                    appDelegate.appState = appState
                    // Recreate the menu now that appState is available
                    Task { @MainActor in
                        appDelegate.recreateMenuWithAppState()
                    }
                }
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1, height: 1)
        .windowResizability(.contentSize)
        
        
        // Preferences window is handled by AppDelegate via PreferencesWindowController
        
        // First-run setup window
        Window("Setup", id: "first-run-setup") {
            FirstRunSetupView()
                .onDisappear {
                    markFirstRunComplete()
                }
        }
        .windowResizability(.contentSize)
        .defaultPosition(.center)
        .commands {
            CommandGroup(replacing: .newItem) { }
            CommandGroup(replacing: .undoRedo) { }
            CommandGroup(replacing: .pasteboard) { }
            CommandGroup(replacing: .appSettings) {
                Button("Preferences...") {
                    if let delegate = NSApp.delegate {
                        delegate.perform(Selector(("showSettingsWindow:")), with: nil)
                    }
                }
                .keyboardShortcut(",", modifiers: .command)
            }
        }
    }
    
    // MARK: - First Run Check
    
    private func checkFirstRun() {
        let firstRunKey = "com.example.macmount.sandboxFirstRunComplete"
        let hasCompletedFirstRun = UserDefaults.standard.bool(forKey: firstRunKey)
        
        // Check if app is sandboxed
        let isSandboxed = ProcessInfo.processInfo.environment["APP_SANDBOX_CONTAINER_ID"] != nil
        
        if isSandboxed && !hasCompletedFirstRun {
            // Schedule showing first-run setup after app launches
            Task { @MainActor in
                self.showFirstRunSetup = true
                NSApp.activate(ignoringOtherApps: true)
                
                // Open the setup window
                if let window = NSApp.windows.first(where: { $0.identifier?.rawValue == "first-run-setup" }) {
                    window.makeKeyAndOrderFront(nil)
                } else {
                    // Create window if needed
                    NSWorkspace.shared.open(URL(string: "macmount://show-setup")!)
                }
            }
        }
    }
    
    private func markFirstRunComplete() {
        let firstRunKey = "com.example.macmount.sandboxFirstRunComplete"
        UserDefaults.standard.set(true, forKey: firstRunKey)
    }
}