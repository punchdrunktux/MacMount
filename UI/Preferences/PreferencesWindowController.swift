//
//  PreferencesWindowController.swift
//  MacMount
//
//  Window controller for preferences
//

import SwiftUI
import AppKit
import OSLog

class PreferencesWindowController: NSWindowController {
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "MacMount", category: "PreferencesWindowController")
    
    init(appState: AppState) {
        logger.info("🔍 PreferencesWindowController: Starting initialization")
        
        // Create the SwiftUI preferences view
        logger.info("🔍 PreferencesWindowController: Creating PreferencesView")
        let preferencesView = PreferencesView()
            .environmentObject(appState)
        
        // Create the hosting controller
        logger.info("🔍 PreferencesWindowController: Creating NSHostingController")
        let hostingController = NSHostingController(rootView: preferencesView)
        
        // Create the window with standard configuration
        logger.info("🔍 PreferencesWindowController: Creating NSWindow")
        let window = NSWindow(contentViewController: hostingController)
        window.title = "Preferences"
        window.setContentSize(NSSize(width: 700, height: 500))
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.center()
        
        // Initialize superclass with the window
        super.init(window: window)
        logger.info("🔍 PreferencesWindowController: Super.init completed")
        
        // Configure window for standard preferences
        window.isReleasedWhenClosed = false
        window.level = .normal // Use normal level like standard preference windows
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.titlebarAppearsTransparent = false
        window.titleVisibility = .visible
        
        // Debug window state
        logger.info("🔍 PreferencesWindowController: Window created successfully")
        logger.info("🔍 PreferencesWindowController: Window exists: \(self.window != nil)")
        let frameString = "\(window.frame)"
        logger.info("🔍 PreferencesWindowController: Window frame: \(frameString)")
        logger.info("🔍 PreferencesWindowController: Window level: \(window.level.rawValue)")
        logger.info("🔍 PreferencesWindowController: Window behavior: \(window.collectionBehavior.rawValue)")
        logger.info("🔍 PreferencesWindowController: Content view: \(window.contentView != nil)")
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func showWindow(_ sender: Any?) {
        logger.info("🔍 PreferencesWindowController: showWindow called")
        logger.info("🔍 PreferencesWindowController: Window exists before super: \(self.window != nil)")
        
        // Call super to ensure window is created if needed
        super.showWindow(sender)
        logger.info("🔍 PreferencesWindowController: After super.showWindow")
        
        // Debug window state
        if let window = self.window {
            let frameString = "\(window.frame)"
            logger.info("🔍 PreferencesWindowController: Window frame: \(frameString)")
            logger.info("🔍 PreferencesWindowController: Window isVisible: \(window.isVisible)")
            logger.info("🔍 PreferencesWindowController: Window isKeyWindow: \(window.isKeyWindow)")
            let screenName = window.screen?.localizedName ?? "none"
            logger.info("🔍 PreferencesWindowController: Window screen: \(screenName)")
            
            // Ensure window is visible and centered
            window.center()
            window.makeKeyAndOrderFront(nil)
            
            logger.info("🔍 PreferencesWindowController: After makeKeyAndOrderFront")
            logger.info("🔍 PreferencesWindowController: Window isVisible now: \(window.isVisible)")
            logger.info("🔍 PreferencesWindowController: Window isKeyWindow now: \(window.isKeyWindow)")
        } else {
            logger.error("🔴 PreferencesWindowController: Window is nil in showWindow")
        }
    }
}