# datatui: Next Steps and Priorities

## 🎯 **IMMEDIATE NEXT STEPS (Order of Implementation)**

### 1. **Layout System** (🔥 CRITICAL - Phase 2)
**Why:** Required for any multi-widget application (file browser, process manager)
**Implementation:**
- Parse layout records from Nu (direction, panes with widget refs and sizes)
- Implement ratatui layout rendering with multiple widgets
- Support percentage ("30%"), fill ("*"), and fixed sizes

**Files to modify:**
- `src/commands.rs` - Update `RenderCommand` to handle layout records
- `src/widgets.rs` - Add layout parsing structs
- Add layout rendering logic in render command

### 2. **StatefulWidget Integration** (🔥 CRITICAL - Phase 2)
**Why:** Proper scrolling and selection within widgets
**Implementation:**
- Convert List widget to use ListState for proper selection
- Add scroll state management for Text widgets
- Store widget states in plugin alongside configurations

### 3. **Interactive Event Loop Support** (📈 HIGH - Phase 2)
**Why:** Enable keyboard navigation within widgets (j/k for lists, etc.)
**Implementation:**
- Add event routing to specific widgets
- Implement selection and scrolling event handlers
- Update widget states based on events

### 4. **Table Widget** (📈 HIGH - Phase 3)
**Why:** Essential for jjiles (commit tables) and nucess (process tables)
**Implementation:**
- Add WidgetConfig::Table variant
- Implement table rendering with headers, columns, selection
- Add sorting and column sizing

## 🌊 **MAJOR ARCHITECTURAL FEATURES**

### 5. **Streaming Data System** (Phase 3.5)
**Why:** Real-time data for nucess (process monitoring) and jjiles (live updates)
**Implementation:**
- `datatui stream {|| command}` command
- StreamId custom values
- Streaming text and table widgets
- Automatic stream cleanup

## 🛡️ **ROBUSTNESS & POLISH**

### 6. **Error Handling & Signal Management**
**Why:** Production-ready plugin that won't corrupt terminal
**Implementation:**
- Panic handlers that call `datatui terminate`
- SIGINT/SIGTERM signal handling
- Better error messages with context

### 7. **Performance Optimizations**
**Why:** Handle large datasets in jjiles (thousands of commits)
**Implementation:**
- Virtual scrolling for large lists/tables
- Widget render caching
- Memory usage optimization

## 📋 **DEVELOPMENT APPROACH**

### **For Layout System (Next Priority):**
1. Start with parsing simple horizontal/vertical layouts
2. Implement basic two-pane rendering (list + preview)
3. Add support for percentage and fixed sizing
4. Test with file browser example from EXAMPLES.md

### **For StatefulWidget Integration:**
1. Add widget state storage alongside configurations
2. Convert List widget to use ratatui's ListState
3. Add proper selection highlighting and scrolling
4. Update event handling to modify widget states

### **Testing Strategy:**
- Create test Nu scripts for each feature
- Validate against examples in EXAMPLES.md
- Test with realistic data sizes for performance

## 🎯 **SUCCESS METRICS**

- **File Browser**: Two-pane layout with list + preview working
- **Interactive Navigation**: j/k keys navigate lists properly
- **Table Display**: Process table with sortable columns
- **Real-time Updates**: Streaming process data updates

Once these features are implemented, the datatui plugin will be ready for integration with jjiles and nucess!