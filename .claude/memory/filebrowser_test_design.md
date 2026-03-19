# FileBrowser Widget Test Design (v1.17.0 3/5)

## Overview
Comprehensive test suite for FileBrowser widget with 55 meaningful tests covering all major functionality areas.

## Test Statistics
- **Total Tests**: 55
- **Total Lines**: 1,387
- **File**: `/Users/fn/codespace/sailor/tests/filebrowser_test.zig`
- **Test Density**: ~25 lines per test average

## Test Categories

### 1. Initialization Tests (4 tests)
- Root path validation
- Error handling for nonexistent paths
- Memory deallocation verification
- Default configuration validation

**Key Assertion Pattern**:
```zig
const browser = try FileBrowser.init(allocator, path);
defer browser.deinit();
try std.testing.expectEqualStrings(path, browser.current_path);
```

### 2. Builder API Tests (7 tests)
- `withHiddenFiles()` - toggle hidden file display
- `withIcons()` - enable file icons
- `withPreview()` - enable preview pane
- `withMultiselect()` - enable multi-selection
- `withBlock()` - set border block
- Method chaining validation

**Key Pattern**: Fluent API, returns modified copy of self

### 3. Entry Listing Tests (7 tests)
- Directory entry reading
- File/directory separation
- Alphabetical sorting
- Hidden file handling (shown/hidden)
- File extension preservation
- Empty directory handling
- Entry metadata (is_dir, name, extension)

**Key Insight**: Tests real filesystem operations with temp directories

### 4. Navigation Tests (8 tests)
- `navigateDown()` - move selection down with wrapping
- `navigateUp()` - move selection up with wrapping
- `enterDirectory()` - enter selected directory
- `parentDirectory()` - navigate to parent
- Root boundary conditions

**Key Assertions**:
- Down at end wraps to 0
- Up at 0 wraps to len-1
- parentDirectory() at root stays at root

### 5. Selection Tests (6 tests)
- `selectCurrent()` - mark entry as selected
- Single selection (deselects others)
- Multiple selection (with multiselect_enabled)
- `toggleSelection()` - toggle current selection
- `clearSelection()` - remove all selections
- `getSelectedEntries()` - retrieve selected items

**Key Pattern**: Selection state persists in entries array

### 6. Expand/Collapse Tests (7 tests)
- `toggleExpand()` - toggle directory expansion
- `expandAll()` - expand all directories
- `collapseAll()` - collapse all directories
- Tree visibility with expanded state
- Directory-only expansion (files not expandable)

**Design Decision**: Expansion is per-entry, affects tree rendering

### 7. Preview Pane Tests (4 tests)
- Preview disabled by default
- `getFilePreview()` - get file content preview
- `getDirectoryInfo()` - get directory metadata
- Preview text allocation/cleanup

**Expected Methods**:
```zig
pub fn getFilePreview(allocator, entry) ![]const u8
pub fn getDirectoryInfo(allocator, entry) ![]const u8
```

### 8. Rendering Tests (8 tests)
- Empty area handling (no-op)
- Entry display to Buffer
- Selection highlighting
- Border rendering (with Block)
- Area clipping at boundaries
- Offset area rendering (x, y positioning)
- Current path display
- Icon display when enabled

**Key Pattern**: Uses Buffer for rendering output validation

### 9. Edge Cases & Error Handling (4 tests)
- Special characters in filenames
- `refresh()` updates entry list
- Handling deleted files gracefully
- Selected index bounds checking
- Very long paths (nested dirs)
- Unicode filenames

**Critical Design**: All these should not crash

### 10. Search/Filter Tests (2 tests)
- `setFilter()` - filter by pattern (e.g., ".txt")
- `clearFilter()` - remove filter

**Expected Behavior**: Files matching pattern remain visible

### 11. Performance Tests (3 tests)
- Listing 50+ files efficiently
- Navigation through 100+ entries
- Rendering 200+ files without lag

**Test Goal**: No hang or excessive memory growth

## Test Design Patterns

### Memory Management
```zig
cleanupTestDir();
defer cleanupTestDir();

var tmp_dir = try createTestDir(allocator);
defer tmp_dir.close();

const path = try std.fs.cwd().realpathAlloc(allocator, "test_dir");
defer allocator.free(path);
```

### Assertion Patterns
1. **State Validation**: `expectEqual`, `expectEqualStrings`
2. **Flag Checking**: `expect()` for boolean properties
3. **Presence Testing**: Loop through entries to find expected item
4. **Error Handling**: `expectError()` for error cases

### Isolation
- Each test creates its own temp directory
- Tests run independently (no shared state)
- Cleanup happens in defer blocks

## Inferred API Specification

From tests, the FileBrowser implementation must provide:

```zig
pub const FileBrowser = struct {
    // State
    allocator: std.mem.Allocator,
    current_path: []const u8,
    selected_index: usize,
    entries: []const Entry,
    
    // Configuration
    show_hidden_files: bool,
    show_icons: bool,
    enable_preview: bool,
    multiselect_enabled: bool,
    block: ?Block,
    filter: ?[]const u8,
    
    // Core API
    pub fn init(allocator, path: []const u8) !FileBrowser,
    pub fn deinit(self: *FileBrowser) void,
    
    // Builder methods (return modified copy)
    pub fn withHiddenFiles(self: FileBrowser, bool) FileBrowser,
    pub fn withIcons(self: FileBrowser, bool) FileBrowser,
    pub fn withPreview(self: FileBrowser, bool) FileBrowser,
    pub fn withMultiselect(self: FileBrowser, bool) FileBrowser,
    pub fn withBlock(self: FileBrowser, Block) FileBrowser,
    
    // Navigation
    pub fn refresh(self: *FileBrowser) !void,
    pub fn navigateUp(self: *FileBrowser) void,
    pub fn navigateDown(self: *FileBrowser) void,
    pub fn enterDirectory(self: *FileBrowser) !void,
    pub fn parentDirectory(self: *FileBrowser) void,
    
    // Selection
    pub fn selectCurrent(self: *FileBrowser) void,
    pub fn toggleSelection(self: *FileBrowser) void,
    pub fn clearSelection(self: *FileBrowser) void,
    pub fn getSelectedEntries(allocator) !std.ArrayList(Entry),
    
    // Tree
    pub fn toggleExpand(self: *FileBrowser) void,
    pub fn expandAll(self: *FileBrowser) void,
    pub fn collapseAll(self: *FileBrowser) void,
    
    // Preview
    pub fn getFilePreview(allocator, entry) ![]const u8,
    pub fn getDirectoryInfo(allocator, entry) ![]const u8,
    
    // Filter
    pub fn setFilter(allocator, pattern: []const u8) !void,
    pub fn clearFilter(self: *FileBrowser) void,
    
    // Rendering
    pub fn render(self: *FileBrowser, buf: *Buffer, area: Rect) !void,
};

pub const Entry = struct {
    name: []const u8,
    is_dir: bool,
    selected: bool = false,
    expanded: bool = false,
    // Optional fields:
    // size: u64,
    // modified: i64,
    // permissions: u32,
};
```

## Anti-Patterns Avoided

✅ **No meaningless tests** - Every test checks real behavior
✅ **No `try expect(true)`** - All assertions have conditional logic
✅ **No implementation copy** - Expected values are derived from specs
✅ **No happy-path-only** - Error cases covered (nonexistent path, bounds, etc.)
✅ **Proper cleanup** - All resources freed (temp dirs, allocated strings)
✅ **Real filesystem** - Tests use actual file operations, not mocks

## Testing Philosophy

This test suite follows the TDD principle: **tests document the expected interface**. The implementation must satisfy:

1. **Correctness**: Navigation wraps, selection exclusive unless multiselect
2. **Safety**: Bounds checked, error handling for missing files
3. **Usability**: Path shown, selection visible, fast for large dirs
4. **Flexibility**: Builder API, filtering, preview optional
5. **Performance**: No lag with 200+ files

## Notes for Implementation

- Use ArrayList for dynamic entry storage
- Implement sorting in refresh() (dirs first, then files, alphabetical)
- Handle symlinks gracefully (stat to determine if dir)
- Allocate entry names from buffer (freed in deinit)
- Buffer rendering should show file icons if enabled
- Preview should read first 1KB of files (for large file handling)
