//
//  LogTextView.swift
//  MacMount
//
//  NSTextView wrapper for multi-line selectable log display
//

import SwiftUI
import AppKit

/// A SwiftUI wrapper for NSTextView optimized for displaying selectable log entries
struct LogTextView: NSViewRepresentable {
    let attributedString: NSAttributedString
    let autoScroll: Bool
    @Binding var scrollToBottom: Bool
    
    func makeNSView(context: Context) -> NSScrollView {
        // Create scroll view first
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = false
        scrollView.borderType = .noBorder
        
        // Create text view with explicit frame
        let textView = NSTextView(frame: CGRect(x: 0, y: 0, width: 300, height: 300))
        textView.isEditable = false
        textView.isSelectable = true
        textView.isRichText = true
        textView.importsGraphics = false
        textView.drawsBackground = true
        textView.backgroundColor = NSColor.textBackgroundColor
        textView.textContainerInset = NSSize(width: 10, height: 10)
        textView.font = NSFont.monospacedSystemFont(ofSize: NSFont.smallSystemFontSize, weight: .regular)
        
        // Configure text container
        textView.textContainer?.containerSize = CGSize(width: scrollView.frame.width, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.lineFragmentPadding = 5
        
        // Configure text view sizing
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.maxSize = CGSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        
        // Set up automatic text layout
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        
        // Set the text view as document view
        scrollView.documentView = textView
        
        // Set initial empty text
        textView.string = ""
        
        return scrollView
    }
    
    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }
        
        // Store current selection before updating
        let selectedRanges = textView.selectedRanges
        
        // Update the text storage with the attributed string
        textView.textStorage?.setAttributedString(attributedString)
        
        // Force layout
        textView.layoutManager?.ensureLayout(for: textView.textContainer!)
        
        // Restore selection if it's still valid
        let newLength = textView.textStorage?.length ?? 0
        let validRanges = selectedRanges.compactMap { rangeValue -> NSRange? in
            let range = rangeValue.rangeValue
            if range.location + range.length <= newLength {
                return range
            }
            return nil
        }
        
        if !validRanges.isEmpty {
            textView.selectedRanges = validRanges.map { NSValue(range: $0) }
        }
        
        // Handle auto-scroll or manual scroll request
        if autoScroll || scrollToBottom {
            DispatchQueue.main.async {
                textView.scrollToEndOfDocument(nil)
                // Don't modify the binding from here - it can cause cycles
                if self.scrollToBottom {
                    DispatchQueue.main.async {
                        self.scrollToBottom = false
                    }
                }
            }
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator()
    }
    
    class Coordinator: NSObject {
        // Coordinator can be used for delegate methods if needed
    }
}

// MARK: - Helper Extensions

extension LogTextView {
    /// Creates an attributed string from log entries with appropriate styling
    static func createAttributedString(from logs: [ConnectionLogEntry], dateFormatter: DateFormatter) -> NSAttributedString {
        
        // Quick test - return plain text first
        if logs.isEmpty {
            return NSAttributedString(string: "No logs to display")
        }
        
        let result = NSMutableAttributedString()
        
        // Define paragraph style for consistent spacing
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineSpacing = 2
        paragraphStyle.paragraphSpacing = 0
        
        // Base attributes - ensure we have a foreground color
        let baseAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: NSFont.smallSystemFontSize, weight: .regular),
            .foregroundColor: NSColor.labelColor, // Explicitly set default color
            .paragraphStyle: paragraphStyle
        ]
        
        for (index, log) in logs.enumerated() {
            // Format timestamp
            let timestamp = dateFormatter.string(from: log.timestamp)
            
            // Format level with padding
            let level = log.level.rawValue.uppercased().padding(toLength: 7, withPad: " ", startingAt: 0)
            
            // Format server name with padding
            let serverName = log.serverName.padding(toLength: 20, withPad: " ", startingAt: 0)
            
            // Build log line
            let logLine = "[\(timestamp)] [\(level)] \(serverName): \(log.message)"
            
            // Add attempt number if present
            let fullLine = log.attemptNumber.map { "\(logLine) (Attempt \($0))" } ?? logLine
            
            // Create attributed string with color
            var attributes = baseAttributes
            attributes[.foregroundColor] = colorForLogLevel(log.level)
            
            let attributedLine = NSAttributedString(string: fullLine, attributes: attributes)
            result.append(attributedLine)
            
            // Add newline if not the last entry
            if index < logs.count - 1 {
                result.append(NSAttributedString(string: "\n", attributes: baseAttributes))
            }
        }
        
        
        return result
    }
    
    private static func colorForLogLevel(_ level: ConnectionLogEntry.LogLevel) -> NSColor {
        switch level {
        case .info:
            return NSColor.labelColor
        case .warning:
            return NSColor.systemOrange
        case .error:
            return NSColor.systemRed
        case .success:
            return NSColor.systemGreen
        }
    }
}