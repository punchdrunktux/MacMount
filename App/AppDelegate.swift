//
//  AppDelegate.swift
//  MacMount
//
//  Application delegate for lifecycle management
//

import SwiftUI
import ServiceManagement
import OSLog

class AppDelegate: NSObject, NSApplicationDelegate {
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "MacMount", category: "AppDelegate")
    private var preferencesWindowController: PreferencesWindowController?
    private var statusItem: NSStatusItem?
    var popover: NSPopover?
    weak var appState: AppState?
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        logger.info("MacMount launched successfully")
        logger.logToFile("Application launched - Log file: \(LoggingUtility.shared.currentLogPath)")
        
        // Create status bar menu
        setupStatusBarMenu()
        
        // Hide from dock (menu bar app)
        NSApp.setActivationPolicy(.accessory)
        
        // Set up launch at login
        // Commented out for testing to avoid permissions popup
        // setupLaunchAtLogin()
        
        // Check for crash recovery
        Task {
            await checkForCrashRecovery()
        }
    }
    
    func applicationWillTerminate(_ notification: Notification) {
        logger.info("MacMount terminating")
        
        // Record clean shutdown
        CrashRecoveryManager.shared.recordCleanShutdown()
    }
    
    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        return true
    }
    
    // Handle Settings window
    @objc func showSettingsWindow(_ sender: Any?) {
        logger.info("🔵 showSettingsWindow: Starting")
        logger.logToFile("🔵 showSettingsWindow: Starting")
        logger.info("🔵 showSettingsWindow: Current activation policy: \(NSApp.activationPolicy().rawValue)")
        logger.logToFile("🔵 showSettingsWindow: Current activation policy: \(NSApp.activationPolicy().rawValue)")
        logger.info("🔵 showSettingsWindow: AppState available: \(self.appState != nil)")
        logger.logToFile("🔵 showSettingsWindow: AppState available: \(self.appState != nil)")
        
        // Step 1: Create or retrieve the preferences window controller
        if preferencesWindowController == nil {
            logger.info("🔵 showSettingsWindow: Creating new window controller")
            guard let appState = appState else {
                logger.error("🔴 showSettingsWindow: Cannot create preferences window - appState is nil")
            logger.errorToFile("🔴 showSettingsWindow: Cannot create preferences window - appState is nil")
                return
            }
            preferencesWindowController = PreferencesWindowController(appState: appState)
            logger.info("🔵 showSettingsWindow: Window controller created")
        } else {
            logger.info("🔵 showSettingsWindow: Using existing window controller")
        }
        
        // Step 2: Verify window exists
        guard let windowController = preferencesWindowController else {
            logger.error("🔴 showSettingsWindow: Window controller is nil after creation")
            logger.errorToFile("🔴 showSettingsWindow: Window controller is nil after creation")
            return
        }
        
        logger.info("🔵 showSettingsWindow: Window exists: \(windowController.window != nil)")
        
        // Step 3: Change activation policy (following About window pattern)
        logger.info("🔵 showSettingsWindow: Changing activation policy to regular")
        NSApp.setActivationPolicy(.regular)
        
        // Step 4: Activate app (following About window pattern)
        logger.info("🔵 showSettingsWindow: Activating app")
        NSApp.activate(ignoringOtherApps: true)
        
        // Step 5: Show the window
        logger.info("🔵 showSettingsWindow: Calling showWindow")
        windowController.showWindow(nil)
        
        // Step 6: Ensure window is key and front
        if let window = windowController.window {
            let frameString = "\(window.frame)"
            logger.info("🔵 showSettingsWindow: Window frame: \(frameString)")
            logger.info("🔵 showSettingsWindow: Window isVisible: \(window.isVisible)")
            logger.info("🔵 showSettingsWindow: Window isKeyWindow: \(window.isKeyWindow)")
            
            window.makeKeyAndOrderFront(nil)
            logger.info("🔵 showSettingsWindow: Called makeKeyAndOrderFront")
            
            // Monitor window closing to return to accessory mode
            NotificationCenter.default.removeObserver(self, name: NSWindow.willCloseNotification, object: window)
            NotificationCenter.default.addObserver(
                forName: NSWindow.willCloseNotification,
                object: window,
                queue: .main
            ) { [weak self] _ in
                self?.logger.info("🔵 Preferences window closed - returning to accessory mode")
                NSApp.setActivationPolicy(.accessory)
            }
        } else {
            logger.error("🔴 showSettingsWindow: Window is nil after showWindow call")
            logger.errorToFile("🔴 showSettingsWindow: Window is nil after showWindow call")
        }
        
        logger.info("🔵 showSettingsWindow: Completed")
        logger.logToFile("🔵 showSettingsWindow: Completed")
    }
    
    // MARK: - Status Bar Menu Setup
    
    func recreateMenuWithAppState() {
        guard let statusItem = self.statusItem else { return }
        logger.info("Recreating popover with appState now available")
        
        // Clear existing menu
        statusItem.menu = nil
        
        // Update button action
        if let button = statusItem.button {
            button.action = #selector(togglePopover(_:))
            button.target = self
        }
        
        // Recreate popover with SwiftUI content
        if let appState = appState {
            let menuContent = MenuBarContentView(appDelegate: self)
                .environmentObject(appState)
            
            let popover = NSPopover()
            popover.contentSize = NSSize(width: 320, height: 400)
            popover.behavior = .transient
            popover.contentViewController = NSHostingController(rootView: menuContent)
            
            self.popover = popover
            
            // Update icon based on connection status
            setupStatusIconUpdates(statusItem: statusItem, appState: appState)
            
            logger.info("SwiftUI popover recreated successfully with appState")
        }
    }
    
    private func setupStatusBarMenu() {
        logger.info("Setting up SwiftUI-based status bar menu")
        
        let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        
        // Configure the status bar button with proper icon
        if let button = statusItem.button {
            // Start with default disconnected icon
            button.image = NSImage(systemSymbolName: "externaldrive.badge.xmark", accessibilityDescription: "MacMount")
            button.image?.isTemplate = true // Use template image for proper dark mode support
            button.toolTip = "MacMount"
            button.imagePosition = .imageOnly
            
            // Remove any title text
            button.title = ""
            
            logger.info("Status bar button configured with proper icon")
        } else {
            logger.error("Could not get status item button")
        }
        
        // Set up button action
        if let button = statusItem.button {
            button.action = #selector(togglePopover(_:))
            button.target = self
        }
        
        // Set up SwiftUI popover content
        if let appState = appState {
            let menuContent = MenuBarContentView(appDelegate: self)
                .environmentObject(appState)
            
            let popover = NSPopover()
            popover.contentSize = NSSize(width: 320, height: 400)
            popover.behavior = .transient
            popover.contentViewController = NSHostingController(rootView: menuContent)
            
            self.popover = popover
            
            // Update icon based on connection status
            setupStatusIconUpdates(statusItem: statusItem, appState: appState)
            
            logger.info("SwiftUI popover setup complete")
        } else {
            logger.warning("AppState not available, setting up basic menu")
            setupBasicMenu(statusItem: statusItem)
        }
        
        // Store reference to prevent deallocation
        self.statusItem = statusItem
        logger.info("Status item configuration complete")
    }
    
    private func setupStatusIconUpdates(statusItem: NSStatusItem, appState: AppState) {
        // Observe connection status changes to update the icon
        Task { @MainActor in
            // Create a publisher for the connection status
            let statusPublisher = appState.$overallStatus
            
            for await status in statusPublisher.values {
                if let button = statusItem.button {
                    let iconName = status.iconName
                    let newImage = NSImage(systemSymbolName: iconName, accessibilityDescription: status.description)
                    newImage?.isTemplate = true
                    button.image = newImage
                    button.toolTip = "MacMount - \(status.description)"
                    
                    logger.debug("Updated status bar icon to: \(iconName)")
                }
            }
        }
    }
    
    private func setupBasicMenu(statusItem: NSStatusItem) {
        let menu = NSMenu()
        
        // Add preferences item
        let preferencesItem = NSMenuItem(title: "Preferences...", action: #selector(showSettingsWindow(_:)), keyEquivalent: ",")
        preferencesItem.target = self
        menu.addItem(preferencesItem)
        
        menu.addItem(NSMenuItem.separator())
        
        // Add quit item
        let quitItem = NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quitItem)
        
        statusItem.menu = menu
        
        logger.info("Basic menu setup complete (AppState not available)")
    }
    
    // MARK: - Popover Management
    
    @objc private func togglePopover(_ sender: AnyObject) {
        logger.logToFile("🔵 togglePopover called")
        if let button = statusItem?.button {
            if popover?.isShown == true {
                logger.logToFile("🔵 Closing popover")
                popover?.performClose(sender)
            } else {
                logger.logToFile("🔵 Showing popover")
                logger.logToFile("🔵 Popover exists: \(popover != nil)")
                logger.logToFile("🔵 Popover content controller: \(popover?.contentViewController != nil)")
                popover?.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
                popover?.contentViewController?.view.window?.makeKey()
            }
        } else {
            logger.logToFile("🔴 No status button found")
        }
    }
    
    
    // Commented out for testing to avoid permissions popup
    /*
    private func setupLaunchAtLogin() {
        // For macOS 13.0+, use the new Service Management API
        if #available(macOS 13.0, *) {
            do {
                try SMAppService.mainApp.register()
                logger.info("Registered for launch at login")
            } catch {
                logger.error("Failed to register for launch at login: \(error)")
            }
        } else {
            // For older versions, use the legacy API
            let launchAtLogin = UserDefaults.standard.bool(forKey: "LaunchAtLogin")
            SMLoginItemSetEnabled("com.example.MacMountHelper" as CFString, launchAtLogin)
        }
    }
    */
    
    private func checkForCrashRecovery() async {
        if CrashRecoveryManager.shared.checkForPreviousCrash() {
            logger.warning("Detected unclean shutdown, performing recovery")
            await CrashRecoveryManager.shared.performRecovery()
        } else {
            logger.info("Clean startup detected")
        }
        
        // Record this startup
        CrashRecoveryManager.shared.recordStartup()
    }
}