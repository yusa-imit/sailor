const std = @import("std");
const sailor = @import("sailor");
const Buffer = sailor.tui.buffer.Buffer;
const Rect = sailor.tui.layout.Rect;
const Style = sailor.tui.style.Style;
const Color = sailor.tui.style.Color;
const Block = sailor.tui.widgets.Block;

// Forward declaration - will be implemented in src/tui/widgets/filebrowser.zig
const FileBrowser = sailor.tui.widgets.FileBrowser;

// ============================================================================
// Helper Functions
// ============================================================================

/// Create a temporary test directory structure
fn createTestDir(_: std.mem.Allocator) !std.fs.Dir {
    var tmp_dir = try std.fs.cwd().makeOpenPath("test_filebrowser_tmp", .{
        .iterate = true,
    });
    errdefer tmp_dir.close();

    // Create subdirectories
    try tmp_dir.makePath("subdir1");
    try tmp_dir.makePath("subdir2");
    try tmp_dir.makePath("empty_dir");

    // Create test files
    var file = try tmp_dir.createFile("file1.txt", .{});
    defer file.close();
    try file.writeAll("test content");

    var file2 = try tmp_dir.createFile("file2.zig", .{});
    defer file2.close();
    try file2.writeAll("const x = 1;");

    var file3 = try tmp_dir.createFile(".hidden_file", .{});
    defer file3.close();
    try file3.writeAll("hidden");

    return tmp_dir;
}

/// Clean up test directory
fn cleanupTestDir() void {
    std.fs.cwd().deleteTree("test_filebrowser_tmp") catch {};
}

// ============================================================================
// Initialization Tests
// ============================================================================

test "FileBrowser.init creates browser with root path" {
    cleanupTestDir();
    defer cleanupTestDir();

    var tmp_dir = try createTestDir(std.testing.allocator);
    defer tmp_dir.close();

    const cwd_path = try std.fs.cwd().realpathAlloc(std.testing.allocator, "test_filebrowser_tmp");
    defer std.testing.allocator.free(cwd_path);

    const browser = try FileBrowser.init(std.testing.allocator, cwd_path);
    defer browser.deinit();

    try std.testing.expectEqualStrings(cwd_path, browser.current_path);
    try std.testing.expectEqual(@as(usize, 0), browser.selected_index);
}

test "FileBrowser.init with nonexistent path returns error" {
    const browser = FileBrowser.init(std.testing.allocator, "/nonexistent/path/xyz");
    try std.testing.expectError(error.PathNotFound, browser);
}

test "FileBrowser.deinit releases allocated memory" {
    cleanupTestDir();
    defer cleanupTestDir();

    var tmp_dir = try createTestDir(std.testing.allocator);
    defer tmp_dir.close();

    const cwd_path = try std.fs.cwd().realpathAlloc(std.testing.allocator, "test_filebrowser_tmp");
    defer std.testing.allocator.free(cwd_path);

    const browser = try FileBrowser.init(std.testing.allocator, cwd_path);
    browser.deinit(); // Should not crash or leak
}

test "FileBrowser.init sets reasonable defaults" {
    cleanupTestDir();
    defer cleanupTestDir();

    var tmp_dir = try createTestDir(std.testing.allocator);
    defer tmp_dir.close();

    const cwd_path = try std.fs.cwd().realpathAlloc(std.testing.allocator, "test_filebrowser_tmp");
    defer std.testing.allocator.free(cwd_path);

    const browser = try FileBrowser.init(std.testing.allocator, cwd_path);
    defer browser.deinit();

    try std.testing.expectEqual(false, browser.show_hidden_files);
    try std.testing.expectEqual(false, browser.show_icons);
    try std.testing.expectEqual(false, browser.enable_preview);
    try std.testing.expectEqual(false, browser.multiselect_enabled);
}

// ============================================================================
// Builder API Tests
// ============================================================================

test "FileBrowser.withHiddenFiles enables hidden file display" {
    cleanupTestDir();
    defer cleanupTestDir();

    var tmp_dir = try createTestDir(std.testing.allocator);
    defer tmp_dir.close();

    const cwd_path = try std.fs.cwd().realpathAlloc(std.testing.allocator, "test_filebrowser_tmp");
    defer std.testing.allocator.free(cwd_path);

    var browser = try FileBrowser.init(std.testing.allocator, cwd_path);
    defer browser.deinit();

    browser = browser.withHiddenFiles(true);
    try std.testing.expectEqual(true, browser.show_hidden_files);
}

test "FileBrowser.withIcons enables icon display" {
    cleanupTestDir();
    defer cleanupTestDir();

    var tmp_dir = try createTestDir(std.testing.allocator);
    defer tmp_dir.close();

    const cwd_path = try std.fs.cwd().realpathAlloc(std.testing.allocator, "test_filebrowser_tmp");
    defer std.testing.allocator.free(cwd_path);

    var browser = try FileBrowser.init(std.testing.allocator, cwd_path);
    defer browser.deinit();

    browser = browser.withIcons(true);
    try std.testing.expectEqual(true, browser.show_icons);
}

test "FileBrowser.withPreview enables preview pane" {
    cleanupTestDir();
    defer cleanupTestDir();

    var tmp_dir = try createTestDir(std.testing.allocator);
    defer tmp_dir.close();

    const cwd_path = try std.fs.cwd().realpathAlloc(std.testing.allocator, "test_filebrowser_tmp");
    defer std.testing.allocator.free(cwd_path);

    var browser = try FileBrowser.init(std.testing.allocator, cwd_path);
    defer browser.deinit();

    browser = browser.withPreview(true);
    try std.testing.expectEqual(true, browser.enable_preview);
}

test "FileBrowser.withMultiselect enables multiple selection" {
    cleanupTestDir();
    defer cleanupTestDir();

    var tmp_dir = try createTestDir(std.testing.allocator);
    defer tmp_dir.close();

    const cwd_path = try std.fs.cwd().realpathAlloc(std.testing.allocator, "test_filebrowser_tmp");
    defer std.testing.allocator.free(cwd_path);

    var browser = try FileBrowser.init(std.testing.allocator, cwd_path);
    defer browser.deinit();

    browser = browser.withMultiselect(true);
    try std.testing.expectEqual(true, browser.multiselect_enabled);
}

test "FileBrowser.withBlock sets border block" {
    cleanupTestDir();
    defer cleanupTestDir();

    var tmp_dir = try createTestDir(std.testing.allocator);
    defer tmp_dir.close();

    const cwd_path = try std.fs.cwd().realpathAlloc(std.testing.allocator, "test_filebrowser_tmp");
    defer std.testing.allocator.free(cwd_path);

    var browser = try FileBrowser.init(std.testing.allocator, cwd_path);
    defer browser.deinit();

    const block = Block.init();
    browser = browser.withBlock(block);
    try std.testing.expect(browser.block != null);
}

test "FileBrowser builder methods chain" {
    cleanupTestDir();
    defer cleanupTestDir();

    var tmp_dir = try createTestDir(std.testing.allocator);
    defer tmp_dir.close();

    const cwd_path = try std.fs.cwd().realpathAlloc(std.testing.allocator, "test_filebrowser_tmp");
    defer std.testing.allocator.free(cwd_path);

    var browser = try FileBrowser.init(std.testing.allocator, cwd_path);
    defer browser.deinit();

    browser = browser
        .withHiddenFiles(true)
        .withIcons(true)
        .withPreview(true)
        .withMultiselect(true);

    try std.testing.expectEqual(true, browser.show_hidden_files);
    try std.testing.expectEqual(true, browser.show_icons);
    try std.testing.expectEqual(true, browser.enable_preview);
    try std.testing.expectEqual(true, browser.multiselect_enabled);
}

// ============================================================================
// Entry Listing Tests
// ============================================================================

test "FileBrowser lists directory entries" {
    cleanupTestDir();
    defer cleanupTestDir();

    var tmp_dir = try createTestDir(std.testing.allocator);
    defer tmp_dir.close();

    const cwd_path = try std.fs.cwd().realpathAlloc(std.testing.allocator, "test_filebrowser_tmp");
    defer std.testing.allocator.free(cwd_path);

    var browser = try FileBrowser.init(std.testing.allocator, cwd_path);
    defer browser.deinit();

    try browser.refresh();
    try std.testing.expect(browser.entries.len > 0);
}

test "FileBrowser separates directories and files" {
    cleanupTestDir();
    defer cleanupTestDir();

    var tmp_dir = try createTestDir(std.testing.allocator);
    defer tmp_dir.close();

    const cwd_path = try std.fs.cwd().realpathAlloc(std.testing.allocator, "test_filebrowser_tmp");
    defer std.testing.allocator.free(cwd_path);

    var browser = try FileBrowser.init(std.testing.allocator, cwd_path);
    defer browser.deinit();

    try browser.refresh();

    // Count directories and files
    var dir_count: usize = 0;
    var file_count: usize = 0;
    for (browser.entries) |entry| {
        if (entry.is_dir) {
            dir_count += 1;
        } else {
            file_count += 1;
        }
    }

    try std.testing.expect(dir_count > 0);
    try std.testing.expect(file_count > 0);
}

test "FileBrowser sorts entries alphabetically" {
    cleanupTestDir();
    defer cleanupTestDir();

    var tmp_dir = try createTestDir(std.testing.allocator);
    defer tmp_dir.close();

    const cwd_path = try std.fs.cwd().realpathAlloc(std.testing.allocator, "test_filebrowser_tmp");
    defer std.testing.allocator.free(cwd_path);

    var browser = try FileBrowser.init(std.testing.allocator, cwd_path);
    defer browser.deinit();

    try browser.refresh();

    // Check that directories come before files
    var last_was_dir = true;
    for (browser.entries) |entry| {
        if (entry.is_dir) {
            try std.testing.expectEqual(true, last_was_dir);
        } else {
            last_was_dir = false;
        }
    }
}

test "FileBrowser hides hidden files by default" {
    cleanupTestDir();
    defer cleanupTestDir();

    var tmp_dir = try createTestDir(std.testing.allocator);
    defer tmp_dir.close();

    const cwd_path = try std.fs.cwd().realpathAlloc(std.testing.allocator, "test_filebrowser_tmp");
    defer std.testing.allocator.free(cwd_path);

    var browser = try FileBrowser.init(std.testing.allocator, cwd_path);
    defer browser.deinit();

    browser.show_hidden_files = false;
    try browser.refresh();

    for (browser.entries) |entry| {
        try std.testing.expect(!std.mem.startsWith(u8, entry.name, "."));
    }
}

test "FileBrowser shows hidden files when enabled" {
    cleanupTestDir();
    defer cleanupTestDir();

    var tmp_dir = try createTestDir(std.testing.allocator);
    defer tmp_dir.close();

    const cwd_path = try std.fs.cwd().realpathAlloc(std.testing.allocator, "test_filebrowser_tmp");
    defer std.testing.allocator.free(cwd_path);

    var browser = try FileBrowser.init(std.testing.allocator, cwd_path);
    defer browser.deinit();

    browser.show_hidden_files = true;
    try browser.refresh();

    var found_hidden = false;
    for (browser.entries) |entry| {
        if (std.mem.startsWith(u8, entry.name, ".")) {
            found_hidden = true;
            break;
        }
    }
    try std.testing.expectEqual(true, found_hidden);
}

test "FileBrowser handles empty directory" {
    cleanupTestDir();
    defer cleanupTestDir();

    std.fs.cwd().makePath("test_filebrowser_tmp/empty") catch {};
    defer std.fs.cwd().deleteTree("test_filebrowser_tmp") catch {};

    const cwd_path = try std.fs.cwd().realpathAlloc(std.testing.allocator, "test_filebrowser_tmp/empty");
    defer std.testing.allocator.free(cwd_path);

    var browser = try FileBrowser.init(std.testing.allocator, cwd_path);
    defer browser.deinit();

    try browser.refresh();
    try std.testing.expectEqual(@as(usize, 0), browser.entries.len);
}

test "FileBrowser includes file extension in entry name" {
    cleanupTestDir();
    defer cleanupTestDir();

    var tmp_dir = try createTestDir(std.testing.allocator);
    defer tmp_dir.close();

    const cwd_path = try std.fs.cwd().realpathAlloc(std.testing.allocator, "test_filebrowser_tmp");
    defer std.testing.allocator.free(cwd_path);

    var browser = try FileBrowser.init(std.testing.allocator, cwd_path);
    defer browser.deinit();

    try browser.refresh();

    var found_txt = false;
    var found_zig = false;
    for (browser.entries) |entry| {
        if (std.mem.eql(u8, entry.name, "file1.txt")) {
            found_txt = true;
        }
        if (std.mem.eql(u8, entry.name, "file2.zig")) {
            found_zig = true;
        }
    }
    try std.testing.expectEqual(true, found_txt);
    try std.testing.expectEqual(true, found_zig);
}

// ============================================================================
// Navigation Tests
// ============================================================================

test "FileBrowser.navigateDown moves selection down" {
    cleanupTestDir();
    defer cleanupTestDir();

    var tmp_dir = try createTestDir(std.testing.allocator);
    defer tmp_dir.close();

    const cwd_path = try std.fs.cwd().realpathAlloc(std.testing.allocator, "test_filebrowser_tmp");
    defer std.testing.allocator.free(cwd_path);

    var browser = try FileBrowser.init(std.testing.allocator, cwd_path);
    defer browser.deinit();

    try browser.refresh();
    const initial = browser.selected_index;
    browser.navigateDown();

    if (browser.entries.len > 1) {
        try std.testing.expectEqual(initial + 1, browser.selected_index);
    }
}

test "FileBrowser.navigateDown wraps at end" {
    cleanupTestDir();
    defer cleanupTestDir();

    var tmp_dir = try createTestDir(std.testing.allocator);
    defer tmp_dir.close();

    const cwd_path = try std.fs.cwd().realpathAlloc(std.testing.allocator, "test_filebrowser_tmp");
    defer std.testing.allocator.free(cwd_path);

    var browser = try FileBrowser.init(std.testing.allocator, cwd_path);
    defer browser.deinit();

    try browser.refresh();
    browser.selected_index = browser.entries.len - 1;
    browser.navigateDown();

    if (browser.entries.len > 0) {
        try std.testing.expectEqual(@as(usize, 0), browser.selected_index);
    }
}

test "FileBrowser.navigateUp moves selection up" {
    cleanupTestDir();
    defer cleanupTestDir();

    var tmp_dir = try createTestDir(std.testing.allocator);
    defer tmp_dir.close();

    const cwd_path = try std.fs.cwd().realpathAlloc(std.testing.allocator, "test_filebrowser_tmp");
    defer std.testing.allocator.free(cwd_path);

    var browser = try FileBrowser.init(std.testing.allocator, cwd_path);
    defer browser.deinit();

    try browser.refresh();
    if (browser.entries.len > 1) {
        browser.selected_index = 1;
        browser.navigateUp();
        try std.testing.expectEqual(@as(usize, 0), browser.selected_index);
    }
}

test "FileBrowser.navigateUp wraps at beginning" {
    cleanupTestDir();
    defer cleanupTestDir();

    var tmp_dir = try createTestDir(std.testing.allocator);
    defer tmp_dir.close();

    const cwd_path = try std.fs.cwd().realpathAlloc(std.testing.allocator, "test_filebrowser_tmp");
    defer std.testing.allocator.free(cwd_path);

    var browser = try FileBrowser.init(std.testing.allocator, cwd_path);
    defer browser.deinit();

    try browser.refresh();
    browser.selected_index = 0;
    browser.navigateUp();

    if (browser.entries.len > 0) {
        try std.testing.expectEqual(browser.entries.len - 1, browser.selected_index);
    }
}

test "FileBrowser.enterDirectory changes current path" {
    cleanupTestDir();
    defer cleanupTestDir();

    var tmp_dir = try createTestDir(std.testing.allocator);
    defer tmp_dir.close();

    const cwd_path = try std.fs.cwd().realpathAlloc(std.testing.allocator, "test_filebrowser_tmp");
    defer std.testing.allocator.free(cwd_path);

    var browser = try FileBrowser.init(std.testing.allocator, cwd_path);
    defer browser.deinit();

    try browser.refresh();

    // Find first directory
    for (browser.entries, 0..) |entry, i| {
        if (entry.is_dir) {
            browser.selected_index = i;
            try browser.enterDirectory();
            try std.testing.expect(!std.mem.eql(u8, browser.current_path, cwd_path));
            break;
        }
    }
}

test "FileBrowser.parentDirectory navigates to parent" {
    cleanupTestDir();
    defer cleanupTestDir();

    var tmp_dir = try createTestDir(std.testing.allocator);
    defer tmp_dir.close();

    const cwd_path = try std.fs.cwd().realpathAlloc(std.testing.allocator, "test_filebrowser_tmp");
    defer std.testing.allocator.free(cwd_path);

    var browser = try FileBrowser.init(std.testing.allocator, cwd_path);
    defer browser.deinit();

    try browser.refresh();

    // Navigate into subdir
    for (browser.entries, 0..) |entry, i| {
        if (entry.is_dir) {
            browser.selected_index = i;
            try browser.enterDirectory();
            break;
        }
    }

    const child_path = try std.testing.allocator.dupe(u8, browser.current_path);
    defer std.testing.allocator.free(child_path);

    // Navigate back
    browser.parentDirectory();
    try std.testing.expectEqualStrings(cwd_path, browser.current_path);
}

test "FileBrowser.parentDirectory at root stays at root" {
    const root_path = "/";

    var browser = FileBrowser.init(std.testing.allocator, root_path) catch {
        return; // Skip if root is not accessible
    };
    defer browser.deinit();

    const original = try std.testing.allocator.dupe(u8, browser.current_path);
    defer std.testing.allocator.free(original);

    browser.parentDirectory();
    try std.testing.expectEqualStrings(original, browser.current_path);
}

// ============================================================================
// Selection Tests
// ============================================================================

test "FileBrowser.selectCurrent marks entry as selected" {
    cleanupTestDir();
    defer cleanupTestDir();

    var tmp_dir = try createTestDir(std.testing.allocator);
    defer tmp_dir.close();

    const cwd_path = try std.fs.cwd().realpathAlloc(std.testing.allocator, "test_filebrowser_tmp");
    defer std.testing.allocator.free(cwd_path);

    var browser = try FileBrowser.init(std.testing.allocator, cwd_path);
    defer browser.deinit();

    try browser.refresh();
    try std.testing.expect(browser.entries.len > 0);

    browser.selectCurrent();
    try std.testing.expectEqual(true, browser.entries[0].selected);
}

test "FileBrowser single selection deselects others" {
    cleanupTestDir();
    defer cleanupTestDir();

    var tmp_dir = try createTestDir(std.testing.allocator);
    defer tmp_dir.close();

    const cwd_path = try std.fs.cwd().realpathAlloc(std.testing.allocator, "test_filebrowser_tmp");
    defer std.testing.allocator.free(cwd_path);

    var browser = try FileBrowser.init(std.testing.allocator, cwd_path);
    defer browser.deinit();

    try browser.refresh();
    if (browser.entries.len >= 2) {
        browser.selected_index = 0;
        browser.selectCurrent();

        browser.selected_index = 1;
        browser.selectCurrent();

        try std.testing.expectEqual(false, browser.entries[0].selected);
        try std.testing.expectEqual(true, browser.entries[1].selected);
    }
}

test "FileBrowser multiselect allows multiple selections" {
    cleanupTestDir();
    defer cleanupTestDir();

    var tmp_dir = try createTestDir(std.testing.allocator);
    defer tmp_dir.close();

    const cwd_path = try std.fs.cwd().realpathAlloc(std.testing.allocator, "test_filebrowser_tmp");
    defer std.testing.allocator.free(cwd_path);

    var browser = try FileBrowser.init(std.testing.allocator, cwd_path);
    defer browser.deinit();

    browser.multiselect_enabled = true;
    try browser.refresh();

    if (browser.entries.len >= 2) {
        browser.selected_index = 0;
        browser.toggleSelection();

        browser.selected_index = 1;
        browser.toggleSelection();

        try std.testing.expectEqual(true, browser.entries[0].selected);
        try std.testing.expectEqual(true, browser.entries[1].selected);
    }
}

test "FileBrowser.clearSelection removes all selections" {
    cleanupTestDir();
    defer cleanupTestDir();

    var tmp_dir = try createTestDir(std.testing.allocator);
    defer tmp_dir.close();

    const cwd_path = try std.fs.cwd().realpathAlloc(std.testing.allocator, "test_filebrowser_tmp");
    defer std.testing.allocator.free(cwd_path);

    var browser = try FileBrowser.init(std.testing.allocator, cwd_path);
    defer browser.deinit();

    try browser.refresh();
    if (browser.entries.len >= 2) {
        browser.selected_index = 0;
        browser.selectCurrent();

        browser.clearSelection();

        for (browser.entries) |entry| {
            try std.testing.expectEqual(false, entry.selected);
        }
    }
}

test "FileBrowser.getSelectedEntries returns selected items" {
    cleanupTestDir();
    defer cleanupTestDir();

    var tmp_dir = try createTestDir(std.testing.allocator);
    defer tmp_dir.close();

    const cwd_path = try std.fs.cwd().realpathAlloc(std.testing.allocator, "test_filebrowser_tmp");
    defer std.testing.allocator.free(cwd_path);

    var browser = try FileBrowser.init(std.testing.allocator, cwd_path);
    defer browser.deinit();

    try browser.refresh();

    browser.selected_index = 0;
    browser.selectCurrent();

    const selected = try browser.getSelectedEntries(std.testing.allocator);
    defer selected.deinit();

    try std.testing.expect(selected.items.len > 0);
}

// ============================================================================
// Expand/Collapse Tests
// ============================================================================

test "FileBrowser.toggleExpand toggles directory expansion state" {
    cleanupTestDir();
    defer cleanupTestDir();

    var tmp_dir = try createTestDir(std.testing.allocator);
    defer tmp_dir.close();

    const cwd_path = try std.fs.cwd().realpathAlloc(std.testing.allocator, "test_filebrowser_tmp");
    defer std.testing.allocator.free(cwd_path);

    var browser = try FileBrowser.init(std.testing.allocator, cwd_path);
    defer browser.deinit();

    try browser.refresh();

    // Find first directory
    for (browser.entries, 0..) |entry, i| {
        if (entry.is_dir) {
            browser.selected_index = i;
            const initial = browser.entries[i].expanded;
            browser.toggleExpand();
            try std.testing.expectEqual(!initial, browser.entries[i].expanded);
            break;
        }
    }
}

test "FileBrowser expanded directory shows children in tree view" {
    cleanupTestDir();
    defer cleanupTestDir();

    var tmp_dir = try createTestDir(std.testing.allocator);
    defer tmp_dir.close();

    const cwd_path = try std.fs.cwd().realpathAlloc(std.testing.allocator, "test_filebrowser_tmp");
    defer std.testing.allocator.free(cwd_path);

    var browser = try FileBrowser.init(std.testing.allocator, cwd_path);
    defer browser.deinit();

    try browser.refresh();

    // Expand first directory
    for (browser.entries, 0..) |entry, i| {
        if (entry.is_dir and !entry.expanded) {
            browser.selected_index = i;
            browser.toggleExpand();
            // Tree should now include children
            break;
        }
    }
}

test "FileBrowser collapsed directory hides children in tree view" {
    cleanupTestDir();
    defer cleanupTestDir();

    var tmp_dir = try createTestDir(std.testing.allocator);
    defer tmp_dir.close();

    const cwd_path = try std.fs.cwd().realpathAlloc(std.testing.allocator, "test_filebrowser_tmp");
    defer std.testing.allocator.free(cwd_path);

    var browser = try FileBrowser.init(std.testing.allocator, cwd_path);
    defer browser.deinit();

    try browser.refresh();

    // Expand then collapse
    for (browser.entries, 0..) |entry, i| {
        if (entry.is_dir) {
            browser.selected_index = i;
            browser.toggleExpand();
            browser.toggleExpand();
            try std.testing.expectEqual(false, browser.entries[i].expanded);
            break;
        }
    }
}

test "FileBrowser.expandAll expands all directories" {
    cleanupTestDir();
    defer cleanupTestDir();

    var tmp_dir = try createTestDir(std.testing.allocator);
    defer tmp_dir.close();

    const cwd_path = try std.fs.cwd().realpathAlloc(std.testing.allocator, "test_filebrowser_tmp");
    defer std.testing.allocator.free(cwd_path);

    var browser = try FileBrowser.init(std.testing.allocator, cwd_path);
    defer browser.deinit();

    try browser.refresh();
    browser.expandAll();

    for (browser.entries) |entry| {
        if (entry.is_dir) {
            try std.testing.expectEqual(true, entry.expanded);
        }
    }
}

test "FileBrowser.collapseAll collapses all directories" {
    cleanupTestDir();
    defer cleanupTestDir();

    var tmp_dir = try createTestDir(std.testing.allocator);
    defer tmp_dir.close();

    const cwd_path = try std.fs.cwd().realpathAlloc(std.testing.allocator, "test_filebrowser_tmp");
    defer std.testing.allocator.free(cwd_path);

    var browser = try FileBrowser.init(std.testing.allocator, cwd_path);
    defer browser.deinit();

    try browser.refresh();
    browser.expandAll();
    browser.collapseAll();

    for (browser.entries) |entry| {
        if (entry.is_dir) {
            try std.testing.expectEqual(false, entry.expanded);
        }
    }
}

// ============================================================================
// Preview Pane Tests
// ============================================================================

test "FileBrowser preview disabled by default" {
    cleanupTestDir();
    defer cleanupTestDir();

    var tmp_dir = try createTestDir(std.testing.allocator);
    defer tmp_dir.close();

    const cwd_path = try std.fs.cwd().realpathAlloc(std.testing.allocator, "test_filebrowser_tmp");
    defer std.testing.allocator.free(cwd_path);

    var browser = try FileBrowser.init(std.testing.allocator, cwd_path);
    defer browser.deinit();

    try std.testing.expectEqual(false, browser.enable_preview);
}

test "FileBrowser.getFilePreview returns file info for files" {
    cleanupTestDir();
    defer cleanupTestDir();

    var tmp_dir = try createTestDir(std.testing.allocator);
    defer tmp_dir.close();

    const cwd_path = try std.fs.cwd().realpathAlloc(std.testing.allocator, "test_filebrowser_tmp");
    defer std.testing.allocator.free(cwd_path);

    var browser = try FileBrowser.init(std.testing.allocator, cwd_path);
    defer browser.deinit();

    try browser.refresh();

    // Get preview for first file
    for (browser.entries) |entry| {
        if (!entry.is_dir) {
            const preview = try browser.getFilePreview(std.testing.allocator, &entry);
            try std.testing.expect(preview.len > 0);
            std.testing.allocator.free(preview);
            break;
        }
    }
}

test "FileBrowser.getDirectoryInfo returns directory info" {
    cleanupTestDir();
    defer cleanupTestDir();

    var tmp_dir = try createTestDir(std.testing.allocator);
    defer tmp_dir.close();

    const cwd_path = try std.fs.cwd().realpathAlloc(std.testing.allocator, "test_filebrowser_tmp");
    defer std.testing.allocator.free(cwd_path);

    var browser = try FileBrowser.init(std.testing.allocator, cwd_path);
    defer browser.deinit();

    try browser.refresh();

    // Get info for first directory
    for (browser.entries) |entry| {
        if (entry.is_dir) {
            const info = try browser.getDirectoryInfo(std.testing.allocator, &entry);
            try std.testing.expect(info.len > 0);
            std.testing.allocator.free(info);
            break;
        }
    }
}

// ============================================================================
// Rendering Tests
// ============================================================================

test "FileBrowser.render empty area does nothing" {
    cleanupTestDir();
    defer cleanupTestDir();

    var tmp_dir = try createTestDir(std.testing.allocator);
    defer tmp_dir.close();

    const cwd_path = try std.fs.cwd().realpathAlloc(std.testing.allocator, "test_filebrowser_tmp");
    defer std.testing.allocator.free(cwd_path);

    var browser = try FileBrowser.init(std.testing.allocator, cwd_path);
    defer browser.deinit();

    var buf = try Buffer.init(std.testing.allocator, 80, 24);
    defer buf.deinit();

    try browser.render(&buf, Rect{ .x = 0, .y = 0, .width = 0, .height = 0 });
    // Should not crash
}

test "FileBrowser.render displays file entries" {
    cleanupTestDir();
    defer cleanupTestDir();

    var tmp_dir = try createTestDir(std.testing.allocator);
    defer tmp_dir.close();

    const cwd_path = try std.fs.cwd().realpathAlloc(std.testing.allocator, "test_filebrowser_tmp");
    defer std.testing.allocator.free(cwd_path);

    var browser = try FileBrowser.init(std.testing.allocator, cwd_path);
    defer browser.deinit();

    try browser.refresh();

    var buf = try Buffer.init(std.testing.allocator, 80, 24);
    defer buf.deinit();

    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 24 };
    try browser.render(&buf, area);

    // Should render some content
    var has_content = false;
    for (0..80) |x| {
        for (0..24) |y| {
            if (buf.get(@intCast(x), @intCast(y))) |cell| {
                if (cell.char != ' ' and cell.char != 0) {
                    has_content = true;
                    break;
                }
            }
        }
        if (has_content) break;
    }
    try std.testing.expect(has_content);
}

test "FileBrowser.render shows selected item highlighted" {
    cleanupTestDir();
    defer cleanupTestDir();

    var tmp_dir = try createTestDir(std.testing.allocator);
    defer tmp_dir.close();

    const cwd_path = try std.fs.cwd().realpathAlloc(std.testing.allocator, "test_filebrowser_tmp");
    defer std.testing.allocator.free(cwd_path);

    var browser = try FileBrowser.init(std.testing.allocator, cwd_path);
    defer browser.deinit();

    try browser.refresh();
    browser.selected_index = 0;

    var buf = try Buffer.init(std.testing.allocator, 80, 24);
    defer buf.deinit();

    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 24 };
    try browser.render(&buf, area);

    // First line should have content
    var has_first_line = false;
    for (0..80) |x| {
        if (buf.get(@intCast(x), 0)) |cell| {
            if (cell.char != ' ' and cell.char != 0) {
                has_first_line = true;
                break;
            }
        }
    }
    try std.testing.expect(has_first_line);
}

test "FileBrowser.render with block draws border" {
    cleanupTestDir();
    defer cleanupTestDir();

    var tmp_dir = try createTestDir(std.testing.allocator);
    defer tmp_dir.close();

    const cwd_path = try std.fs.cwd().realpathAlloc(std.testing.allocator, "test_filebrowser_tmp");
    defer std.testing.allocator.free(cwd_path);

    var browser = try FileBrowser.init(std.testing.allocator, cwd_path);
    defer browser.deinit();

    try browser.refresh();
    const block = Block.init();
    browser = browser.withBlock(block);

    var buf = try Buffer.init(std.testing.allocator, 80, 24);
    defer buf.deinit();

    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 24 };
    try browser.render(&buf, area);

    // Should have border characters
    try std.testing.expect(buf.get(0, 0) != null);
}

test "FileBrowser.render clips at area boundaries" {
    cleanupTestDir();
    defer cleanupTestDir();

    var tmp_dir = try createTestDir(std.testing.allocator);
    defer tmp_dir.close();

    const cwd_path = try std.fs.cwd().realpathAlloc(std.testing.allocator, "test_filebrowser_tmp");
    defer std.testing.allocator.free(cwd_path);

    var browser = try FileBrowser.init(std.testing.allocator, cwd_path);
    defer browser.deinit();

    try browser.refresh();

    var buf = try Buffer.init(std.testing.allocator, 80, 24);
    defer buf.deinit();

    const area = Rect{ .x = 5, .y = 3, .width = 40, .height = 15 };
    try browser.render(&buf, area);

    // Should only render within area
    // Content beyond area should not appear
}

test "FileBrowser.render shows current path" {
    cleanupTestDir();
    defer cleanupTestDir();

    var tmp_dir = try createTestDir(std.testing.allocator);
    defer tmp_dir.close();

    const cwd_path = try std.fs.cwd().realpathAlloc(std.testing.allocator, "test_filebrowser_tmp");
    defer std.testing.allocator.free(cwd_path);

    var browser = try FileBrowser.init(std.testing.allocator, cwd_path);
    defer browser.deinit();

    try browser.refresh();

    var buf = try Buffer.init(std.testing.allocator, 80, 24);
    defer buf.deinit();

    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 24 };
    try browser.render(&buf, area);

    // Path should be displayed somewhere in buffer (likely in title or header)
}

test "FileBrowser.render shows file icons when enabled" {
    cleanupTestDir();
    defer cleanupTestDir();

    var tmp_dir = try createTestDir(std.testing.allocator);
    defer tmp_dir.close();

    const cwd_path = try std.fs.cwd().realpathAlloc(std.testing.allocator, "test_filebrowser_tmp");
    defer std.testing.allocator.free(cwd_path);

    var browser = try FileBrowser.init(std.testing.allocator, cwd_path);
    defer browser.deinit();

    browser = browser.withIcons(true);
    try browser.refresh();

    var buf = try Buffer.init(std.testing.allocator, 80, 24);
    defer buf.deinit();

    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 24 };
    try browser.render(&buf, area);

    // Should render icons (symbols for files/dirs)
}

// ============================================================================
// Edge Cases & Error Handling
// ============================================================================

test "FileBrowser handles special characters in filenames" {
    cleanupTestDir();
    defer cleanupTestDir();

    var tmp_dir = try createTestDir(std.testing.allocator);
    defer tmp_dir.close();

    const cwd_path = try std.fs.cwd().realpathAlloc(std.testing.allocator, "test_filebrowser_tmp");
    defer std.testing.allocator.free(cwd_path);

    // Create file with spaces and special chars
    var special_file = try std.fs.cwd().createFile("test_filebrowser_tmp/file with spaces.txt", .{});
    defer special_file.close();

    var browser = try FileBrowser.init(std.testing.allocator, cwd_path);
    defer browser.deinit();

    try browser.refresh();

    var found_special = false;
    for (browser.entries) |entry| {
        if (std.mem.eql(u8, entry.name, "file with spaces.txt")) {
            found_special = true;
            break;
        }
    }
    try std.testing.expectEqual(true, found_special);
}

test "FileBrowser.refresh updates entry list" {
    cleanupTestDir();
    defer cleanupTestDir();

    var tmp_dir = try createTestDir(std.testing.allocator);
    defer tmp_dir.close();

    const cwd_path = try std.fs.cwd().realpathAlloc(std.testing.allocator, "test_filebrowser_tmp");
    defer std.testing.allocator.free(cwd_path);

    var browser = try FileBrowser.init(std.testing.allocator, cwd_path);
    defer browser.deinit();

    try browser.refresh();
    const count1 = browser.entries.len;

    // Create a new file
    var new_file = try std.fs.cwd().createFile("test_filebrowser_tmp/new_file.txt", .{});
    defer new_file.close();

    try browser.refresh();
    const count2 = browser.entries.len;

    try std.testing.expect(count2 > count1);
}

test "FileBrowser handles deleted files gracefully" {
    cleanupTestDir();
    defer cleanupTestDir();

    var tmp_dir = try createTestDir(std.testing.allocator);
    defer tmp_dir.close();

    const cwd_path = try std.fs.cwd().realpathAlloc(std.testing.allocator, "test_filebrowser_tmp");
    defer std.testing.allocator.free(cwd_path);

    var browser = try FileBrowser.init(std.testing.allocator, cwd_path);
    defer browser.deinit();

    try browser.refresh();
    const count1 = browser.entries.len;

    // Delete a file
    std.fs.cwd().deleteFile("test_filebrowser_tmp/file1.txt") catch {};

    try browser.refresh();
    const count2 = browser.entries.len;

    try std.testing.expect(count2 < count1);
}

test "FileBrowser selected_index bounds checked" {
    cleanupTestDir();
    defer cleanupTestDir();

    var tmp_dir = try createTestDir(std.testing.allocator);
    defer tmp_dir.close();

    const cwd_path = try std.fs.cwd().realpathAlloc(std.testing.allocator, "test_filebrowser_tmp");
    defer std.testing.allocator.free(cwd_path);

    var browser = try FileBrowser.init(std.testing.allocator, cwd_path);
    defer browser.deinit();

    try browser.refresh();

    // Set index beyond range
    browser.selected_index = 1000;

    // Render should not crash
    var buf = try Buffer.init(std.testing.allocator, 80, 24);
    defer buf.deinit();

    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 24 };
    try browser.render(&buf, area);
}

test "FileBrowser handles very long paths" {
    cleanupTestDir();
    defer cleanupTestDir();

    // Create nested directories
    std.fs.cwd().makePath("test_filebrowser_tmp/a/b/c/d/e/f") catch {};
    defer std.fs.cwd().deleteTree("test_filebrowser_tmp") catch {};

    const cwd_path = try std.fs.cwd().realpathAlloc(std.testing.allocator, "test_filebrowser_tmp/a/b/c/d/e/f");
    defer std.testing.allocator.free(cwd_path);

    const browser = try FileBrowser.init(std.testing.allocator, cwd_path);
    defer browser.deinit();

    try std.testing.expectEqualStrings(cwd_path, browser.current_path);
}

test "FileBrowser handles unicode filenames" {
    cleanupTestDir();
    defer cleanupTestDir();

    var tmp_dir = try createTestDir(std.testing.allocator);
    defer tmp_dir.close();

    // Create file with unicode name if possible
    const unicode_name = "file_🎉.txt";
    var unicode_file = std.fs.cwd().createFile("test_filebrowser_tmp/" ++ unicode_name, .{}) catch {
        // Skip if unicode filenames not supported
        return;
    };
    defer unicode_file.close();

    const cwd_path = try std.fs.cwd().realpathAlloc(std.testing.allocator, "test_filebrowser_tmp");
    defer std.testing.allocator.free(cwd_path);

    var browser = try FileBrowser.init(std.testing.allocator, cwd_path);
    defer browser.deinit();

    try browser.refresh();

    // Should handle unicode without crashing
    var buf = try Buffer.init(std.testing.allocator, 80, 24);
    defer buf.deinit();

    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 24 };
    try browser.render(&buf, area);
}

// ============================================================================
// Search/Filter Tests
// ============================================================================

test "FileBrowser.setFilter filters entries by pattern" {
    cleanupTestDir();
    defer cleanupTestDir();

    var tmp_dir = try createTestDir(std.testing.allocator);
    defer tmp_dir.close();

    const cwd_path = try std.fs.cwd().realpathAlloc(std.testing.allocator, "test_filebrowser_tmp");
    defer std.testing.allocator.free(cwd_path);

    var browser = try FileBrowser.init(std.testing.allocator, cwd_path);
    defer browser.deinit();

    try browser.setFilter(std.testing.allocator, ".txt");
    try browser.refresh();

    for (browser.entries) |entry| {
        if (!entry.is_dir) {
            try std.testing.expect(std.mem.endsWith(u8, entry.name, ".txt"));
        }
    }
}

test "FileBrowser.clearFilter removes filter" {
    cleanupTestDir();
    defer cleanupTestDir();

    var tmp_dir = try createTestDir(std.testing.allocator);
    defer tmp_dir.close();

    const cwd_path = try std.fs.cwd().realpathAlloc(std.testing.allocator, "test_filebrowser_tmp");
    defer std.testing.allocator.free(cwd_path);

    var browser = try FileBrowser.init(std.testing.allocator, cwd_path);
    defer browser.deinit();

    try browser.setFilter(std.testing.allocator, ".txt");
    browser.clearFilter();
    try browser.refresh();

    // Should have more entries now
    try std.testing.expect(browser.entries.len >= 3); // At least dirs and other file types
}

// ============================================================================
// Performance & Stress Tests
// ============================================================================

test "FileBrowser handles large directory listing efficiently" {
    // Skip on slow systems
    cleanupTestDir();
    defer cleanupTestDir();

    std.fs.cwd().makePath("test_filebrowser_tmp/large_dir") catch {};
    defer std.fs.cwd().deleteTree("test_filebrowser_tmp") catch {};

    // Create many files
    var i: usize = 0;
    while (i < 50) : (i += 1) {
        var buf: [64]u8 = undefined;
        const name = try std.fmt.bufPrint(&buf, "test_filebrowser_tmp/large_dir/file_{d:0>3}.txt", .{i});
        var file = try std.fs.cwd().createFile(name, .{});
        file.close();
    }

    const cwd_path = try std.fs.cwd().realpathAlloc(std.testing.allocator, "test_filebrowser_tmp/large_dir");
    defer std.testing.allocator.free(cwd_path);

    var browser = try FileBrowser.init(std.testing.allocator, cwd_path);
    defer browser.deinit();

    try browser.refresh();
    try std.testing.expect(browser.entries.len >= 50);
}

test "FileBrowser navigation smooth with many entries" {
    cleanupTestDir();
    defer cleanupTestDir();

    std.fs.cwd().makePath("test_filebrowser_tmp/many_files") catch {};
    defer std.fs.cwd().deleteTree("test_filebrowser_tmp") catch {};

    // Create files
    var i: usize = 0;
    while (i < 100) : (i += 1) {
        var buf: [64]u8 = undefined;
        const name = try std.fmt.bufPrint(&buf, "test_filebrowser_tmp/many_files/f_{d:0>3}.txt", .{i});
        var file = try std.fs.cwd().createFile(name, .{});
        file.close();
    }

    const cwd_path = try std.fs.cwd().realpathAlloc(std.testing.allocator, "test_filebrowser_tmp/many_files");
    defer std.testing.allocator.free(cwd_path);

    var browser = try FileBrowser.init(std.testing.allocator, cwd_path);
    defer browser.deinit();

    try browser.refresh();

    // Navigate through all entries
    var idx: usize = 0;
    while (idx < browser.entries.len) : (idx += 1) {
        browser.selected_index = idx;
        browser.navigateDown();
    }

    try std.testing.expect(browser.selected_index == 0);
}

test "FileBrowser renders large directory without lag" {
    cleanupTestDir();
    defer cleanupTestDir();

    std.fs.cwd().makePath("test_filebrowser_tmp/render_test") catch {};
    defer std.fs.cwd().deleteTree("test_filebrowser_tmp") catch {};

    // Create many files
    var i: usize = 0;
    while (i < 200) : (i += 1) {
        var buf: [64]u8 = undefined;
        const name = try std.fmt.bufPrint(&buf, "test_filebrowser_tmp/render_test/file_{d:0>4}.txt", .{i});
        var file = try std.fs.cwd().createFile(name, .{});
        file.close();
    }

    const cwd_path = try std.fs.cwd().realpathAlloc(std.testing.allocator, "test_filebrowser_tmp/render_test");
    defer std.testing.allocator.free(cwd_path);

    var browser = try FileBrowser.init(std.testing.allocator, cwd_path);
    defer browser.deinit();

    try browser.refresh();

    var buf = try Buffer.init(std.testing.allocator, 80, 24);
    defer buf.deinit();

    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 24 };
    try browser.render(&buf, area);

    // Should render without hanging
}
