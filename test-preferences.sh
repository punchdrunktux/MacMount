#!/bin/bash

# Test script for MacMount preferences window debug
# This script helps test the preferences window implementation

echo "🔍 MacMount Preferences Window Debug Test"
echo "=================================================="

# Kill any existing instance
echo "1. Stopping any existing MacMount instances..."
pkill -f MacMount || true
sleep 1

# Launch the app in background
echo "2. Launching MacMount..."
cd /Users/rob/dev.local/MacMount
./MacMount.app/Contents/MacOS/MacMount &
APP_PID=$!

echo "   App launched with PID: $APP_PID"
sleep 3

# Check if app is running
if ps -p $APP_PID > /dev/null; then
    echo "   ✅ App is running"
else
    echo "   ❌ App failed to start"
    exit 1
fi

echo ""
echo "3. Testing Debug Features"
echo "   - Look for the menu bar icon"
echo "   - Click on the menu bar icon to open the menu"
echo "   - Try clicking 'Preferences...' to test the main functionality"
echo "   - Try the '🔍 Debug Tests' menu for isolated testing"
echo ""

echo "4. Debug Test Options Available:"
echo "   - Test Activation Policy: Tests switching between .accessory and .regular"
echo "   - Test Window Creation: Tests window creation without policy changes"
echo "   - Test With Delays: Tests timing scenarios with delays"
echo "   - Test About Window: Tests the working About window for comparison"
echo ""

echo "5. Monitoring logs:"
echo "   Run in another terminal: log stream --predicate 'subsystem == \"MacMount\"' --style compact"
echo "   Or check Console.app and filter for 'MacMount'"
echo ""

# Wait for user input
echo "Press Enter to stop the app and view recent logs..."
read -r

echo ""
echo "6. Stopping app..."
kill $APP_PID 2>/dev/null || true
sleep 1

echo ""
echo "7. Recent logs (last 2 minutes):"
echo "================================="
log show --last 2m | grep -i macmount | head -20 || echo "No logs found. Try checking Console.app manually."

echo ""
echo "Test complete!"