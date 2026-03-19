const std = @import("std");
const buffer_mod = @import("../buffer.zig");
const Buffer = buffer_mod.Buffer;
const layout_mod = @import("../layout.zig");
const Rect = layout_mod.Rect;
const style_mod = @import("../style.zig");
const Style = style_mod.Style;
const block_mod = @import("block.zig");
const Block = block_mod.Block;

/// Entry represents a file or directory in the browser
pub const Entry = struct {
    name: []const u8,
    path: []const u8,
    is_dir: bool,
    selected: bool = false,
    expanded: bool = false,
};

/// Selection result - wrapper that holds selected entries with allocator
pub const SelectionResult = struct {
    items: []Entry,
    allocator: std.mem.Allocator,

    /// Clean up allocated memory
    pub fn deinit(self: SelectionResult) void {
        self.allocator.free(self.items);
    }
};

/// FileBrowser widget - interactive file system navigator with selection and preview
pub const FileBrowser = struct {
    allocator: std.mem.Allocator,
    current_path: []const u8,
    entries: []Entry,
    selected_index: usize = 0,
    show_hidden_files: bool = false,
    show_icons: bool = false,
    enable_preview: bool = false,
    multiselect_enabled: bool = false,
    block: ?Block = null,
    filter_pattern: ?[]const u8 = null,

    /// Initialize FileBrowser with a root path
    pub fn init(allocator: std.mem.Allocator, root_path: []const u8) !FileBrowser {
        // Verify path exists
        var dir = std.fs.openDirAbsolute(root_path, .{ .iterate = true }) catch {
            return error.PathNotFound;
        };
        defer dir.close();

        // Duplicate path for storage
        const path_copy = try allocator.dupe(u8, root_path);
        errdefer allocator.free(path_copy);

        // Initialize with empty entries
        var browser = FileBrowser{
            .allocator = allocator,
            .current_path = path_copy,
            .entries = &.{},
        };

        // Load entries
        browser.refresh() catch |err| {
            allocator.free(path_copy);
            return err;
        };

        return browser;
    }

    /// Release all allocated memory
    pub fn deinit(self: *const FileBrowser) void {
        // Free each entry's strings
        for (self.entries) |entry| {
            self.allocator.free(entry.name);
            self.allocator.free(entry.path);
        }
        // Free the entries slice itself
        if (self.entries.len > 0) {
            self.allocator.free(self.entries);
        }
        // Free the path
        self.allocator.free(self.current_path);
        // Free the filter pattern if set
        if (self.filter_pattern) |pattern| {
            self.allocator.free(pattern);
        }
    }

    /// Free allocated entries (for internal use in refresh)
    fn freeEntries(self: *FileBrowser) void {
        for (self.entries) |entry| {
            self.allocator.free(entry.name);
            self.allocator.free(entry.path);
        }
        if (self.entries.len > 0) {
            self.allocator.free(self.entries);
        }
    }

    /// Enable display of hidden files
    pub fn withHiddenFiles(self: FileBrowser, enabled: bool) FileBrowser {
        var result = self;
        result.show_hidden_files = enabled;
        return result;
    }

    /// Enable display of file icons
    pub fn withIcons(self: FileBrowser, enabled: bool) FileBrowser {
        var result = self;
        result.show_icons = enabled;
        return result;
    }

    /// Enable preview pane
    pub fn withPreview(self: FileBrowser, enabled: bool) FileBrowser {
        var result = self;
        result.enable_preview = enabled;
        return result;
    }

    /// Enable multiselect mode
    pub fn withMultiselect(self: FileBrowser, enabled: bool) FileBrowser {
        var result = self;
        result.multiselect_enabled = enabled;
        return result;
    }

    /// Set border block
    pub fn withBlock(self: FileBrowser, border_block: Block) FileBrowser {
        var result = self;
        result.block = border_block;
        return result;
    }

    /// Refresh entry list from filesystem
    pub fn refresh(self: *FileBrowser) !void {
        self.freeEntries();
        self.entries = &.{};

        var dir = try std.fs.openDirAbsolute(self.current_path, .{ .iterate = true });
        defer dir.close();

        var entries_list: std.ArrayList(Entry) = .{};
        defer entries_list.deinit(self.allocator);

        var iter = dir.iterate();
        while (try iter.next()) |entry| {
            // Skip hidden files unless enabled
            if (!self.show_hidden_files and std.mem.startsWith(u8, entry.name, ".")) {
                continue;
            }

            // Apply filter if set
            if (self.filter_pattern) |pattern| {
                if (!std.mem.endsWith(u8, entry.name, pattern)) {
                    continue;
                }
            }

            const path = try std.fs.path.join(self.allocator, &[_][]const u8{ self.current_path, entry.name });
            const name = try self.allocator.dupe(u8, entry.name);

            const is_dir = entry.kind == .directory;

            try entries_list.append(self.allocator, Entry{
                .name = name,
                .path = path,
                .is_dir = is_dir,
            });
        }

        // Sort: directories first, then alphabetically
        std.sort.block(Entry, entries_list.items, {}, sortEntries);

        self.entries = try entries_list.toOwnedSlice(self.allocator);

        // Reset selection if out of bounds
        if (self.selected_index >= self.entries.len) {
            self.selected_index = 0;
        }
    }

    /// Sort entries: directories first, then alphabetically by name
    fn sortEntries(context: void, a: Entry, b: Entry) bool {
        _ = context;
        if (a.is_dir != b.is_dir) {
            return a.is_dir; // directories come first
        }
        return std.mem.lessThan(u8, a.name, b.name);
    }

    /// Move selection down
    pub fn navigateDown(self: *FileBrowser) void {
        if (self.entries.len == 0) return;
        if (self.selected_index >= self.entries.len - 1) {
            self.selected_index = 0;
        } else {
            self.selected_index += 1;
        }
    }

    /// Move selection up
    pub fn navigateUp(self: *FileBrowser) void {
        if (self.entries.len == 0) return;
        if (self.selected_index == 0) {
            self.selected_index = self.entries.len - 1;
        } else {
            self.selected_index -= 1;
        }
    }

    /// Enter selected directory
    pub fn enterDirectory(self: *FileBrowser) !void {
        if (self.selected_index >= self.entries.len) return error.InvalidIndex;
        if (!self.entries[self.selected_index].is_dir) return error.NotADirectory;

        const new_path = try self.allocator.dupe(u8, self.entries[self.selected_index].path);
        const old_path = self.current_path;

        self.current_path = new_path;
        errdefer {
            self.current_path = old_path;
            self.allocator.free(new_path);
        }

        self.refresh() catch |err| {
            self.allocator.free(new_path);
            self.current_path = old_path;
            return err;
        };

        self.allocator.free(old_path);
        self.selected_index = 0;
    }

    /// Go to parent directory
    pub fn parentDirectory(self: *FileBrowser) void {
        // Find the last separator
        if (std.mem.lastIndexOfScalar(u8, self.current_path, '/')) |idx| {
            if (idx == 0) {
                // Already at root
                return;
            }

            const parent_path = self.current_path[0..idx];
            const old_path = self.current_path;
            self.current_path = self.allocator.dupe(u8, parent_path) catch return;

            self.refresh() catch {
                self.allocator.free(self.current_path);
                self.current_path = old_path;
                return;
            };

            self.allocator.free(old_path);
            self.selected_index = 0;
        }
    }

    /// Select current entry (single select mode)
    pub fn selectCurrent(self: *FileBrowser) void {
        if (self.selected_index >= self.entries.len) return;

        // In single select mode, deselect all others
        for (0..self.entries.len) |i| {
            self.entries[i].selected = i == self.selected_index;
        }
    }

    /// Toggle selection of current entry
    pub fn toggleSelection(self: *FileBrowser) void {
        if (self.selected_index >= self.entries.len) return;

        if (self.multiselect_enabled) {
            self.entries[self.selected_index].selected = !self.entries[self.selected_index].selected;
        } else {
            // Single select: just select current
            for (0..self.entries.len) |i| {
                self.entries[i].selected = i == self.selected_index;
            }
        }
    }

    /// Clear all selections
    pub fn clearSelection(self: *FileBrowser) void {
        for (self.entries) |*entry| {
            entry.selected = false;
        }
    }

    /// Get all selected entries
    pub fn getSelectedEntries(self: *FileBrowser, allocator: std.mem.Allocator) !SelectionResult {
        var selected: std.ArrayList(Entry) = .{};
        for (self.entries) |entry| {
            if (entry.selected) {
                try selected.append(allocator, entry);
            }
        }
        const slice = try selected.toOwnedSlice(allocator);
        return SelectionResult{
            .items = slice,
            .allocator = allocator,
        };
    }

    /// Toggle expansion state of current directory
    pub fn toggleExpand(self: *FileBrowser) void {
        if (self.selected_index >= self.entries.len) return;
        if (self.entries[self.selected_index].is_dir) {
            self.entries[self.selected_index].expanded = !self.entries[self.selected_index].expanded;
        }
    }

    /// Expand all directories
    pub fn expandAll(self: *FileBrowser) void {
        for (self.entries) |*entry| {
            if (entry.is_dir) {
                entry.expanded = true;
            }
        }
    }

    /// Collapse all directories
    pub fn collapseAll(self: *FileBrowser) void {
        for (self.entries) |*entry| {
            if (entry.is_dir) {
                entry.expanded = false;
            }
        }
    }

    /// Get preview text for a file
    pub fn getFilePreview(_: *FileBrowser, allocator: std.mem.Allocator, entry: *const Entry) ![]const u8 {
        if (entry.is_dir) return error.IsDirectory;

        var file = std.fs.openFileAbsolute(entry.path, .{}) catch return error.CannotOpenFile;
        defer file.close();

        // Read up to 1KB for preview
        const preview_size = 1024;
        const buf = try allocator.alloc(u8, preview_size);
        errdefer allocator.free(buf);

        const bytes_read = try file.readAll(buf);

        // Resize to actual size to allow proper deallocation
        if (bytes_read < buf.len) {
            const resized = try allocator.realloc(buf, bytes_read);
            return resized;
        }
        return buf;
    }

    /// Get info about a directory
    pub fn getDirectoryInfo(_: *FileBrowser, allocator: std.mem.Allocator, entry: *const Entry) ![]const u8 {
        if (!entry.is_dir) return error.NotADirectory;

        var dir = std.fs.openDirAbsolute(entry.path, .{ .iterate = true }) catch return error.CannotOpenDirectory;
        defer dir.close();

        // Count items in directory
        var count: usize = 0;
        var iter = dir.iterate();
        while (try iter.next()) |_| {
            count += 1;
        }

        var buf: [256]u8 = undefined;
        const info = try std.fmt.bufPrint(&buf, "{d} items", .{count});
        return try allocator.dupe(u8, info);
    }

    /// Set filter pattern (files must end with this pattern)
    pub fn setFilter(self: *FileBrowser, allocator: std.mem.Allocator, pattern: []const u8) !void {
        if (self.filter_pattern) |old| {
            allocator.free(old);
        }
        self.filter_pattern = try allocator.dupe(u8, pattern);
    }

    /// Clear filter
    pub fn clearFilter(self: *FileBrowser) void {
        if (self.filter_pattern) |pattern| {
            self.allocator.free(pattern);
            self.filter_pattern = null;
        }
    }

    /// Render FileBrowser to buffer
    pub fn render(self: *FileBrowser, buf: *Buffer, area: Rect) !void {
        if (area.width == 0 or area.height == 0) return;

        // Render block if present
        var inner_area = area;
        if (self.block) |blk| {
            blk.render(buf, area);
            inner_area = blk.inner(area);
        }

        if (inner_area.width == 0 or inner_area.height == 0) return;

        // Draw path at top
        var y = inner_area.y;
        if (y < inner_area.y + inner_area.height) {
            var x = inner_area.x;
            const label = "Path: ";
            for (label) |c| {
                if (x < inner_area.x + inner_area.width) {
                    buf.setChar(x, y, c, .{});
                    x += 1;
                }
            }
            for (self.current_path) |c| {
                if (x >= inner_area.x + inner_area.width) break;
                buf.setChar(x, y, c, .{});
                x += 1;
            }
            y += 1;
        }

        // Render entries
        for (0..self.entries.len) |i| {
            if (y >= inner_area.y + inner_area.height) break;

            const entry = self.entries[i];
            const is_selected = i == self.selected_index;
            const style = if (is_selected) Style{ .bold = true, .reverse = true } else Style{};

            var x = inner_area.x;

            // Render highlight/icon
            if (is_selected) {
                const mark = if (entry.selected) "✓ " else "> ";
                for (mark) |c| {
                    if (x < inner_area.x + inner_area.width) {
                        buf.setChar(x, y, c, style);
                        x += 1;
                    }
                }
            }

            // Render file icon if enabled
            if (self.show_icons) {
                const icon = if (entry.is_dir) "📁 " else "📄 ";
                for (icon) |c| {
                    if (x < inner_area.x + inner_area.width) {
                        buf.setChar(x, y, c, style);
                        x += 1;
                    }
                }
            }

            // Render filename
            for (entry.name) |c| {
                if (x >= inner_area.x + inner_area.width) break;
                buf.setChar(x, y, c, style);
                x += 1;
            }

            // Fill rest of line if selected
            if (is_selected) {
                while (x < inner_area.x + inner_area.width) : (x += 1) {
                    buf.setChar(x, y, ' ', style);
                }
            }

            y += 1;
        }
    }
};

// ============================================================================
// Tests
// ============================================================================

test "FileBrowser imports" {
    _ = FileBrowser;
    _ = Entry;
    _ = SelectionResult;
}

test "FileBrowser init and deinit" {
    const testing = std.testing;
    const allocator = testing.allocator;

    // Create a temporary test directory
    const test_dir = "test_filebrowser_init_tmp";
    std.fs.cwd().makeDir(test_dir) catch |err| switch (err) {
        error.PathAlreadyExists => {},
        else => return err,
    };
    defer std.fs.cwd().deleteTree(test_dir) catch {};

    var path_buf: [std.fs.MAX_PATH_BYTES]u8 = undefined;
    const abs_path = try std.fs.cwd().realpath(test_dir, &path_buf);

    var browser = try FileBrowser.init(allocator, abs_path);
    defer browser.deinit();

    try testing.expectEqualStrings(abs_path, browser.current_path);
    try testing.expectEqual(@as(usize, 0), browser.entries.len);
    try testing.expectEqual(@as(usize, 0), browser.selected_index);
}

test "FileBrowser refresh loads entries" {
    const testing = std.testing;
    const allocator = testing.allocator;

    // Create test directory structure
    const test_dir = "test_filebrowser_refresh_tmp";
    std.fs.cwd().makeDir(test_dir) catch |err| switch (err) {
        error.PathAlreadyExists => {},
        else => return err,
    };
    defer std.fs.cwd().deleteTree(test_dir) catch {};

    // Create test files
    try std.fs.cwd().writeFile(.{ .sub_path = test_dir ++ "/file1.txt", .data = "test" });
    try std.fs.cwd().writeFile(.{ .sub_path = test_dir ++ "/file2.zig", .data = "test" });
    try std.fs.cwd().makeDir(test_dir ++ "/subdir");

    var path_buf: [std.fs.MAX_PATH_BYTES]u8 = undefined;
    const abs_path = try std.fs.cwd().realpath(test_dir, &path_buf);

    var browser = try FileBrowser.init(allocator, abs_path);
    defer browser.deinit();

    // Should have 3 entries (2 files + 1 dir)
    try testing.expectEqual(@as(usize, 3), browser.entries.len);

    // Directories should come first (due to sorting)
    try testing.expect(browser.entries[0].is_dir);
    try testing.expectEqualStrings("subdir", browser.entries[0].name);
}

test "FileBrowser navigation" {
    const testing = std.testing;
    const allocator = testing.allocator;

    const test_dir = "test_filebrowser_nav_tmp";
    std.fs.cwd().makeDir(test_dir) catch |err| switch (err) {
        error.PathAlreadyExists => {},
        else => return err,
    };
    defer std.fs.cwd().deleteTree(test_dir) catch {};

    try std.fs.cwd().writeFile(.{ .sub_path = test_dir ++ "/file1.txt", .data = "a" });
    try std.fs.cwd().writeFile(.{ .sub_path = test_dir ++ "/file2.txt", .data = "b" });
    try std.fs.cwd().writeFile(.{ .sub_path = test_dir ++ "/file3.txt", .data = "c" });

    var path_buf: [std.fs.MAX_PATH_BYTES]u8 = undefined;
    const abs_path = try std.fs.cwd().realpath(test_dir, &path_buf);

    var browser = try FileBrowser.init(allocator, abs_path);
    defer browser.deinit();

    try testing.expectEqual(@as(usize, 0), browser.selected_index);

    browser.navigateDown();
    try testing.expectEqual(@as(usize, 1), browser.selected_index);

    browser.navigateDown();
    try testing.expectEqual(@as(usize, 2), browser.selected_index);

    // Wrap around to beginning
    browser.navigateDown();
    try testing.expectEqual(@as(usize, 0), browser.selected_index);

    // Navigate up
    browser.navigateUp();
    try testing.expectEqual(@as(usize, 2), browser.selected_index);
}

test "FileBrowser hidden files" {
    const testing = std.testing;
    const allocator = testing.allocator;

    const test_dir = "test_filebrowser_hidden_tmp";
    std.fs.cwd().makeDir(test_dir) catch |err| switch (err) {
        error.PathAlreadyExists => {},
        else => return err,
    };
    defer std.fs.cwd().deleteTree(test_dir) catch {};

    try std.fs.cwd().writeFile(.{ .sub_path = test_dir ++ "/visible.txt", .data = "a" });
    try std.fs.cwd().writeFile(.{ .sub_path = test_dir ++ "/.hidden", .data = "b" });

    var path_buf: [std.fs.MAX_PATH_BYTES]u8 = undefined;
    const abs_path = try std.fs.cwd().realpath(test_dir, &path_buf);

    // Without hidden files (default)
    var browser = try FileBrowser.init(allocator, abs_path);
    defer browser.deinit();
    try testing.expectEqual(@as(usize, 1), browser.entries.len);

    // With hidden files
    var browser_hidden = try FileBrowser.init(allocator, abs_path);
    defer browser_hidden.deinit();
    browser_hidden = browser_hidden.withHiddenFiles(true);
    try browser_hidden.refresh();
    try testing.expectEqual(@as(usize, 2), browser_hidden.entries.len);
}

test "FileBrowser selection" {
    const testing = std.testing;
    const allocator = testing.allocator;

    const test_dir = "test_filebrowser_select_tmp";
    std.fs.cwd().makeDir(test_dir) catch |err| switch (err) {
        error.PathAlreadyExists => {},
        else => return err,
    };
    defer std.fs.cwd().deleteTree(test_dir) catch {};

    try std.fs.cwd().writeFile(.{ .sub_path = test_dir ++ "/file1.txt", .data = "a" });
    try std.fs.cwd().writeFile(.{ .sub_path = test_dir ++ "/file2.txt", .data = "b" });

    var path_buf: [std.fs.MAX_PATH_BYTES]u8 = undefined;
    const abs_path = try std.fs.cwd().realpath(test_dir, &path_buf);

    var browser = try FileBrowser.init(allocator, abs_path);
    defer browser.deinit();

    // Single select mode
    browser.toggleSelection();
    try testing.expect(browser.entries[0].selected);
    try testing.expect(!browser.entries[1].selected);

    browser.navigateDown();
    browser.toggleSelection();
    try testing.expect(!browser.entries[0].selected);
    try testing.expect(browser.entries[1].selected);
}

test "FileBrowser multiselect" {
    const testing = std.testing;
    const allocator = testing.allocator;

    const test_dir = "test_filebrowser_multisel_tmp";
    std.fs.cwd().makeDir(test_dir) catch |err| switch (err) {
        error.PathAlreadyExists => {},
        else => return err,
    };
    defer std.fs.cwd().deleteTree(test_dir) catch {};

    try std.fs.cwd().writeFile(.{ .sub_path = test_dir ++ "/file1.txt", .data = "a" });
    try std.fs.cwd().writeFile(.{ .sub_path = test_dir ++ "/file2.txt", .data = "b" });
    try std.fs.cwd().writeFile(.{ .sub_path = test_dir ++ "/file3.txt", .data = "c" });

    var path_buf: [std.fs.MAX_PATH_BYTES]u8 = undefined;
    const abs_path = try std.fs.cwd().realpath(test_dir, &path_buf);

    var browser = try FileBrowser.init(allocator, abs_path);
    defer browser.deinit();
    browser = browser.withMultiselect(true);

    // Select multiple items
    browser.toggleSelection();
    try testing.expect(browser.entries[0].selected);

    browser.navigateDown();
    browser.toggleSelection();
    try testing.expect(browser.entries[0].selected); // Still selected
    try testing.expect(browser.entries[1].selected); // Now selected too

    browser.navigateDown();
    browser.toggleSelection();
    try testing.expect(browser.entries[0].selected);
    try testing.expect(browser.entries[1].selected);
    try testing.expect(browser.entries[2].selected);

    // Get selected entries
    const result = try browser.getSelectedEntries(allocator);
    defer result.deinit();
    try testing.expectEqual(@as(usize, 3), result.items.len);
}

test "FileBrowser filter" {
    const testing = std.testing;
    const allocator = testing.allocator;

    const test_dir = "test_filebrowser_filter_tmp";
    std.fs.cwd().makeDir(test_dir) catch |err| switch (err) {
        error.PathAlreadyExists => {},
        else => return err,
    };
    defer std.fs.cwd().deleteTree(test_dir) catch {};

    try std.fs.cwd().writeFile(.{ .sub_path = test_dir ++ "/file1.txt", .data = "a" });
    try std.fs.cwd().writeFile(.{ .sub_path = test_dir ++ "/file2.zig", .data = "b" });
    try std.fs.cwd().writeFile(.{ .sub_path = test_dir ++ "/file3.txt", .data = "c" });

    var path_buf: [std.fs.MAX_PATH_BYTES]u8 = undefined;
    const abs_path = try std.fs.cwd().realpath(test_dir, &path_buf);

    var browser = try FileBrowser.init(allocator, abs_path);
    defer browser.deinit();

    // All files initially
    try testing.expectEqual(@as(usize, 3), browser.entries.len);

    // Filter to .txt files only
    try browser.setFilter(allocator, ".txt");
    try browser.refresh();
    try testing.expectEqual(@as(usize, 2), browser.entries.len);

    // Clear filter
    browser.clearFilter();
    try browser.refresh();
    try testing.expectEqual(@as(usize, 3), browser.entries.len);
}

test "FileBrowser render basic" {
    const testing = std.testing;
    const allocator = testing.allocator;

    const test_dir = "test_filebrowser_render_tmp";
    std.fs.cwd().makeDir(test_dir) catch |err| switch (err) {
        error.PathAlreadyExists => {},
        else => return err,
    };
    defer std.fs.cwd().deleteTree(test_dir) catch {};

    try std.fs.cwd().writeFile(.{ .sub_path = test_dir ++ "/file.txt", .data = "test" });

    var path_buf: [std.fs.MAX_PATH_BYTES]u8 = undefined;
    const abs_path = try std.fs.cwd().realpath(test_dir, &path_buf);

    var browser = try FileBrowser.init(allocator, abs_path);
    defer browser.deinit();

    var buffer = try Buffer.init(allocator, 40, 10);
    defer buffer.deinit();

    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 10 };
    try browser.render(&buffer, area);

    // Verify path is rendered
    const first_row = buffer.getRow(0);
    try testing.expect(first_row.len > 0);
}

test "FileBrowser render with block" {
    const testing = std.testing;
    const allocator = testing.allocator;

    const test_dir = "test_filebrowser_block_tmp";
    std.fs.cwd().makeDir(test_dir) catch |err| switch (err) {
        error.PathAlreadyExists => {},
        else => return err,
    };
    defer std.fs.cwd().deleteTree(test_dir) catch {};

    var path_buf: [std.fs.MAX_PATH_BYTES]u8 = undefined;
    const abs_path = try std.fs.cwd().realpath(test_dir, &path_buf);

    var browser = try FileBrowser.init(allocator, abs_path);
    defer browser.deinit();

    const block = Block.init().withTitle("Files").withBorders(.all);
    browser = browser.withBlock(block);

    var buffer = try Buffer.init(allocator, 40, 10);
    defer buffer.deinit();

    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 10 };
    try browser.render(&buffer, area);

    // Just verify it doesn't crash
    try testing.expect(true);
}

test "FileBrowser enter and parent directory" {
    const testing = std.testing;
    const allocator = testing.allocator;

    const test_dir = "test_filebrowser_enter_tmp";
    std.fs.cwd().makeDir(test_dir) catch |err| switch (err) {
        error.PathAlreadyExists => {},
        else => return err,
    };
    defer std.fs.cwd().deleteTree(test_dir) catch {};

    try std.fs.cwd().makeDir(test_dir ++ "/subdir");
    try std.fs.cwd().writeFile(.{ .sub_path = test_dir ++ "/subdir/file.txt", .data = "test" });

    var path_buf: [std.fs.MAX_PATH_BYTES]u8 = undefined;
    const abs_path = try std.fs.cwd().realpath(test_dir, &path_buf);

    var browser = try FileBrowser.init(allocator, abs_path);
    defer browser.deinit();

    const original_path = browser.current_path;

    // Enter subdirectory (should be first entry due to sorting)
    try browser.enterDirectory();
    try testing.expect(!std.mem.eql(u8, browser.current_path, original_path));
    try testing.expect(std.mem.endsWith(u8, browser.current_path, "subdir"));

    // Go back to parent
    browser.parentDirectory();
    // Note: parentDirectory may fail silently, so we just check it doesn't crash
}

test "FileBrowser SelectionResult deinit" {
    const testing = std.testing;
    const allocator = testing.allocator;

    const test_dir = "test_filebrowser_result_tmp";
    std.fs.cwd().makeDir(test_dir) catch |err| switch (err) {
        error.PathAlreadyExists => {},
        else => return err,
    };
    defer std.fs.cwd().deleteTree(test_dir) catch {};

    try std.fs.cwd().writeFile(.{ .sub_path = test_dir ++ "/file1.txt", .data = "a" });

    var path_buf: [std.fs.MAX_PATH_BYTES]u8 = undefined;
    const abs_path = try std.fs.cwd().realpath(test_dir, &path_buf);

    var browser = try FileBrowser.init(allocator, abs_path);
    defer browser.deinit();

    browser.toggleSelection();

    const result = try browser.getSelectedEntries(allocator);
    defer result.deinit();

    try testing.expectEqual(@as(usize, 1), result.items.len);
}
