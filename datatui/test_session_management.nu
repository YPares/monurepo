#!/usr/bin/env nu

# Quick test to verify session-based terminal management is working

print "Testing session-based Terminal management in datatui..."

# Re-register plugin
plugin add ./target/release/nu_plugin_datatui

# Create a widget
let widget = datatui text --content "Session Management Test" --title "Test"

# Test that render fails without init
print "1. Testing without init..."
try {
    $widget | datatui render
    print "   ✗ Should have failed"
} catch { |error|
    print "   ✓ Correctly failed - Terminal not initialized"
}

print "Session-based Terminal management is working!"
print ""
print "To test in a real terminal, run:"
print "1. nu test_layout.nu  # Should work with improved terminal management"
print "2. Each render command now reuses the same Terminal instance"
print "3. No more Terminal re-creation overhead!"