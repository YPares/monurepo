#!/usr/bin/env nu

# Simple test script for the datatui plugin

# Initialize the plugin (assuming it's been registered with Nu)
# In production, users would run: plugin add ./target/release/nu_plugin_datatui

plugin add ./target/release/nu_plugin_datatui
plugin use datatui

print "Testing datatui plugin..."

# Test 1: Simple text widget
print "Creating a text widget..."
let text_widget = datatui text --content "Hello, World from datatui!" --title "Test Text"
print $"Text widget created with ID: ($text_widget)"

# Render the text widget
print "Rendering text widget..."
$text_widget | datatui render

print "Text widget test complete!"

# Test 2: List widget
print "Creating a list widget..."
let files = (ls | get name | first 5)
let list_widget = datatui list --items $files --selected 0 --title "Files" --scrollable
print $"List widget created with ID: ($list_widget)"

# Render the list widget
print "Rendering list widget..."
$list_widget | datatui render

print "List widget test complete!"

print "All tests completed successfully!"
