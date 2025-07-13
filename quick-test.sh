#!/bin/bash

echo "🔍 Quick Test: Preferences Window Debug"
echo "======================================"

# Check if app is running
if pgrep -f MacMount > /dev/null; then
    echo "✅ App is running"
    
    # Get the PID
    APP_PID=$(pgrep -f MacMount)
    echo "   PID: $APP_PID"
    
    echo ""
    echo "📝 Instructions:"
    echo "1. Click on the menu bar icon (should be visible)"
    echo "2. Try clicking 'Preferences...' - this should now trigger debug logs"
    echo "3. Try the '🔍 Debug Tests' menu items"
    echo "4. Watch this terminal for any output"
    echo ""
    echo "🔍 Expected behavior:"
    echo "- Dock icon should appear when you click Preferences"
    echo "- Debug logs should appear in system logs"
    echo "- Window should appear (if everything works)"
    echo ""
    echo "⚠️  If no debug logs appear, the method is still not being called"
    echo ""
    
    # Monitor for a bit
    echo "Monitoring system logs for 30 seconds..."
    echo "Press Ctrl+C to stop monitoring"
    
    # Try to capture logs (this might work better)
    timeout 30 log stream --predicate 'process == "MacMount"' 2>/dev/null || echo "Log streaming not available, check Console.app manually"
    
else
    echo "❌ App is not running"
    echo "Please run: open MacMount.app"
fi