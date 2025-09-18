#!/usr/bin/env nu

# Demo script for datatui plugin

print "=== DATATUI PLUGIN DEMO ==="
print ""

print "This demo shows the current capabilities of the datatui plugin."
print "Note: Rendering commands will briefly take over the terminal."
print ""

# Demo 1: Text Widget
print "Demo 1: Text Widget"
print "-------------------"
print "Creating a text widget with title and content..."

let text_widget = datatui text --content "Welcome to datatui!

This is a text widget that can display multi-line content.
You can add titles, enable wrapping, and make content scrollable.

datatui is a Nushell plugin that bridges Nu's data processing
capabilities with rich terminal user interfaces." --title "Welcome" --wrap

print $"Text widget created: ($text_widget)"
print ""
print "Press any key to render the text widget..."
input

print "Initializing terminal and rendering..."
datatui init
$text_widget | datatui render
sleep 2sec
datatui terminate
print "Text widget demo complete!"
print ""

# Demo 2: List Widget
print "Demo 2: List Widget"
print "-------------------"
print "Creating a list widget with file names..."

let files = (ls | get name | first 10)
let list_widget = datatui list --items $files --selected 2 --title "Files in Current Directory" --scrollable

print $"List widget created: ($list_widget)"
print $"Items in list: ($files | length)"
print ""
print "Press any key to render the list widget..."
input

print "Initializing terminal and rendering..."
datatui init
$list_widget | datatui render
sleep 3sec
datatui terminate
print "List widget demo complete!"
print ""

# Demo 3: Event System (simplified demo)
print "Demo 3: Event System"
print "--------------------"
print "The event system can capture keyboard, mouse, and resize events."
print "For this demo, we'll just show the event structure:"

print ""
print "Example events that datatui can capture:"
print "• Key press: {type: 'key', key: 'j', modifiers: [], timestamp: 1234567890}"
print "• Mouse click: {type: 'mouse', x: 25, y: 10, button: 'left', timestamp: 1234567890}"
print "• Terminal resize: {type: 'resize', width: 120, height: 30, timestamp: 1234567890}"
print ""

print "=== DEMO COMPLETE ==="
print ""
print "The datatui plugin provides:"
print "✓ Text widgets with titles, wrapping, and scrolling"
print "✓ List widgets with selection and scrolling"
print "✓ Event collection for interactive applications"
print "✓ Terminal management (init/terminate)"
print ""
print "Future features will include:"
print "• Layout system for multiple widgets"
print "• Table widgets"
print "• Streaming data widgets"
print "• Mouse support"
print "• Theming and styling"
print ""
print "This plugin serves as the foundation for interactive tools like jjiles and nucess!"