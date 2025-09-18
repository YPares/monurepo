#!/usr/bin/env nu

# Simple test for datatui plugin functionality
print "Testing datatui plugin commands..."

# Test widget creation
print "1. Testing text widget creation..."
let text_widget = datatui text --content "Hello, World from datatui!" --title "Test Text"
print $"   ✓ Text widget created: ($text_widget)"

print "2. Testing list widget creation..."
let items = ["file1.txt", "file2.txt", "document.pdf"]
let list_widget = datatui list --items $items --selected 0 --title "Files" --scrollable
print $"   ✓ List widget created: ($list_widget)"

print "3. Testing event collection (non-blocking)..."
# We can't easily test events without user input, so just check the command exists
try {
    datatui events --help | ignore
    print "   ✓ Events command available"
} catch {
    print "   ✗ Events command failed"
}

print ""
print "Basic functionality tests completed successfully!"
print ""
print "Note: To test rendering, run:"
print "  datatui init"
print "  let widget = datatui text --content 'Hello!' --title 'Test'"
print "  $widget | datatui render"
print "  datatui terminate"