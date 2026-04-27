//! Visual regression testing for sailor widgets
//!
//! Detects unintended visual changes by comparing Buffer outputs
//! and providing detailed diff reports with color-coded changes.

const std = @import("std");
const Allocator = std.mem.Allocator;
const tui = @import("../tui/tui.zig");
const Buffer = tui.Buffer;
const Cell = tui.Cell;
const Color = tui.style.Color;
const Style = tui.style.Style;

/// Change type for diff reporting
pub const ChangeType = enum {
    added,
    removed,
    modified,
};

/// A single change in the buffer
pub const Change = struct {
    row: u16,
    col: u16,
    change_type: ChangeType,
    old_cell: ?Cell,
    new_cell: ?Cell,

    /// Format change as human-readable string
    pub fn format(
        self: Change,
        comptime fmt: []const u8,
        options: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        _ = fmt;
        _ = options;

        const type_str = switch (self.change_type) {
            .added => "ADD",
            .removed => "DEL",
            .modified => "MOD",
        };

        try writer.print("[{s}] ({}, {}): ", .{ type_str, self.row, self.col });

        if (self.old_cell) |old| {
            try writer.print("'{u}'", .{old.char});
        } else {
            try writer.print("''", .{});
        }

        try writer.print(" -> ", .{});

        if (self.new_cell) |new| {
            try writer.print("'{u}'", .{new.char});
        } else {
            try writer.print("''", .{});
        }
    }
};

/// Visual diff result
pub const VisualDiff = struct {
    changes: std.ArrayList(Change),
    allocator: Allocator,

    /// Initialize empty diff
    pub fn init(allocator: Allocator) !VisualDiff {
        return .{
            .changes = try std.ArrayList(Change).initCapacity(allocator, 0),
            .allocator = allocator,
        };
    }

    /// Clean up resources
    pub fn deinit(self: *VisualDiff) void {
        self.changes.deinit(self.allocator);
    }

    /// Add a change to the diff
    pub fn addChange(self: *VisualDiff, change: Change) !void {
        try self.changes.append(self.allocator, change);
    }

    /// Check if there are any changes
    pub fn hasChanges(self: VisualDiff) bool {
        return self.changes.items.len > 0;
    }

    /// Get number of changes
    pub fn count(self: VisualDiff) usize {
        return self.changes.items.len;
    }

    /// Count changes by type
    pub fn countByType(self: VisualDiff, change_type: ChangeType) usize {
        var cnt: usize = 0;
        for (self.changes.items) |change| {
            if (change.change_type == change_type) {
                cnt += 1;
            }
        }
        return cnt;
    }

    /// Format diff as string for reporting
    pub fn format(
        self: VisualDiff,
        comptime fmt: []const u8,
        options: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        _ = fmt;
        _ = options;

        if (self.changes.items.len == 0) {
            try writer.writeAll("No visual changes detected.\n");
            return;
        }

        try writer.print("Visual changes detected: {} total\n", .{self.changes.items.len});
        try writer.print("  Added: {}\n", .{self.countByType(.added)});
        try writer.print("  Removed: {}\n", .{self.countByType(.removed)});
        try writer.print("  Modified: {}\n", .{self.countByType(.modified)});
        try writer.writeAll("\nChanges:\n");

        for (self.changes.items) |change| {
            try writer.writeAll("  ");
            try change.format("", .{}, writer);
            try writer.writeAll("\n");
        }
    }
};

/// Compare two buffers and generate visual diff
pub fn compareBuffers(allocator: Allocator, old: *const Buffer, new: *const Buffer) !VisualDiff {
    var diff = try VisualDiff.init(allocator);
    errdefer diff.deinit();

    // Buffers must have same dimensions
    if (old.width != new.width or old.height != new.height) {
        return error.BufferSizeMismatch;
    }

    // Compare each cell
    var row: u16 = 0;
    while (row < old.height) : (row += 1) {
        var col: u16 = 0;
        while (col < old.width) : (col += 1) {
            const old_cell = old.getConst(col, row) orelse continue;
            const new_cell = new.getConst(col, row);

            if (new_cell) |nc| {
                // Cell exists in both buffers
                if (!cellsEqual(old_cell, nc)) {
                    try diff.addChange(.{
                        .row = row,
                        .col = col,
                        .change_type = .modified,
                        .old_cell = old_cell,
                        .new_cell = nc,
                    });
                }
            } else {
                // Cell removed
                try diff.addChange(.{
                    .row = row,
                    .col = col,
                    .change_type = .removed,
                    .old_cell = old_cell,
                    .new_cell = null,
                });
            }
        }
    }

    return diff;
}

/// Check if two cells are equal
fn cellsEqual(a: Cell, b: Cell) bool {
    return a.char == b.char and
        stylesEqual(a.style, b.style);
}

/// Check if two styles are equal
fn stylesEqual(a: Style, b: Style) bool {
    // Compare colors
    if (!optionalColorsEqual(a.fg, b.fg)) return false;
    if (!optionalColorsEqual(a.bg, b.bg)) return false;

    // Compare modifiers
    return a.bold == b.bold and
        a.dim == b.dim and
        a.italic == b.italic and
        a.underline == b.underline and
        a.blink == b.blink and
        a.reverse == b.reverse and
        a.strikethrough == b.strikethrough;
}

/// Check if two optional colors are equal
fn optionalColorsEqual(a: ?Color, b: ?Color) bool {
    if (a == null and b == null) return true;
    if (a == null or b == null) return false;
    return colorsEqual(a.?, b.?);
}

/// Check if two colors are equal
fn colorsEqual(a: Color, b: Color) bool {
    // Handle tagged union comparison
    const a_tag = @as(std.meta.Tag(Color), a);
    const b_tag = @as(std.meta.Tag(Color), b);

    if (a_tag != b_tag) return false;

    return switch (a) {
        .reset, .black, .red, .green, .yellow, .blue, .magenta, .cyan, .white => true,
        .bright_black, .bright_red, .bright_green, .bright_yellow => true,
        .bright_blue, .bright_magenta, .bright_cyan, .bright_white => true,
        .indexed => |a_idx| a_idx == b.indexed,
        .rgb => |a_rgb| {
            const b_rgb = b.rgb;
            return a_rgb.r == b_rgb.r and a_rgb.g == b_rgb.g and a_rgb.b == b_rgb.b;
        },
    };
}

/// Side-by-side comparison formatter
pub const SideBySideComparison = struct {
    allocator: Allocator,
    old_buffer: *const Buffer,
    new_buffer: *const Buffer,
    diff: VisualDiff,

    /// Initialize side-by-side comparison
    pub fn init(allocator: Allocator, old_buffer: *const Buffer, new_buffer: *const Buffer) !SideBySideComparison {
        const diff = try compareBuffers(allocator, old_buffer, new_buffer);
        return .{
            .allocator = allocator,
            .old_buffer = old_buffer,
            .new_buffer = new_buffer,
            .diff = diff,
        };
    }

    /// Clean up resources
    pub fn deinit(self: *SideBySideComparison) void {
        self.diff.deinit();
    }

    /// Render side-by-side comparison to writer
    pub fn render(self: SideBySideComparison, writer: anytype) !void {
        try writer.writeAll("=== Visual Regression Comparison ===\n\n");

        // Summary
        try self.diff.format("", .{}, writer);
        try writer.writeAll("\n\n");

        // If no changes, done
        if (!self.diff.hasChanges()) return;

        try writer.writeAll("=== Side-by-Side View ===\n");
        try writer.writeAll("OLD                  NEW\n");
        try writer.writeAll("---                  ---\n");

        // Build set of changed rows for highlighting
        var changed_positions = std.AutoHashMap(struct { u16, u16 }, void).init(self.allocator);
        defer changed_positions.deinit();

        for (self.diff.changes.items) |change| {
            try changed_positions.put(.{ change.row, change.col }, {});
        }

        // Render each row side-by-side
        var row: u16 = 0;
        while (row < self.old_buffer.height) : (row += 1) {
            // Old buffer line
            var col: u16 = 0;
            while (col < self.old_buffer.width) : (col += 1) {
                if (self.old_buffer.getConst(col, row)) |cell| {
                    const is_changed = changed_positions.contains(.{ row, col });
                    if (is_changed) {
                        try writer.print("[{u}]", .{cell.char});
                    } else {
                        try writer.print("{u}", .{cell.char});
                    }
                } else {
                    try writer.writeAll(" ");
                }
            }

            try writer.writeAll(" | ");

            // New buffer line
            col = 0;
            while (col < self.new_buffer.width) : (col += 1) {
                if (self.new_buffer.getConst(col, row)) |cell| {
                    const is_changed = changed_positions.contains(.{ row, col });
                    if (is_changed) {
                        try writer.print("[{u}]", .{cell.char});
                    } else {
                        try writer.print("{u}", .{cell.char});
                    }
                } else {
                    try writer.writeAll(" ");
                }
            }

            try writer.writeAll("\n");
        }
    }
};

// ============================================================================
// Tests
// ============================================================================

test "VisualDiff init and deinit" {
    const allocator = std.testing.allocator;
    var diff = try VisualDiff.init(allocator);
    defer diff.deinit();

    try std.testing.expect(!diff.hasChanges());
    try std.testing.expectEqual(@as(usize, 0), diff.count());
}

test "VisualDiff addChange" {
    const allocator = std.testing.allocator;
    var diff = try VisualDiff.init(allocator);
    defer diff.deinit();

    try diff.addChange(.{
        .row = 5,
        .col = 10,
        .change_type = .modified,
        .old_cell = .{ .char = 'A', .style = .{} },
        .new_cell = .{ .char = 'B', .style = .{} },
    });

    try std.testing.expect(diff.hasChanges());
    try std.testing.expectEqual(@as(usize, 1), diff.count());
}

test "VisualDiff countByType" {
    const allocator = std.testing.allocator;
    var diff = try VisualDiff.init(allocator);
    defer diff.deinit();

    try diff.addChange(.{ .row = 0, .col = 0, .change_type = .added, .old_cell = null, .new_cell = .{ .char = 'X', .style = .{} } });
    try diff.addChange(.{ .row = 0, .col = 1, .change_type = .modified, .old_cell = .{ .char = 'A', .style = .{} }, .new_cell = .{ .char = 'B', .style = .{} } });
    try diff.addChange(.{ .row = 0, .col = 2, .change_type = .removed, .old_cell = .{ .char = 'C', .style = .{} }, .new_cell = null });

    try std.testing.expectEqual(@as(usize, 1), diff.countByType(.added));
    try std.testing.expectEqual(@as(usize, 1), diff.countByType(.modified));
    try std.testing.expectEqual(@as(usize, 1), diff.countByType(.removed));
}

test "cellsEqual identical cells" {
    const cell_a = Cell{ .char = 'A', .style = .{} };
    const cell_b = Cell{ .char = 'A', .style = .{} };

    try std.testing.expect(cellsEqual(cell_a, cell_b));
}

test "cellsEqual different char" {
    const cell_a = Cell{ .char = 'A', .style = .{} };
    const cell_b = Cell{ .char = 'B', .style = .{} };

    try std.testing.expect(!cellsEqual(cell_a, cell_b));
}

test "cellsEqual different style" {
    const cell_a = Cell{ .char = 'A', .style = .{ .bold = true } };
    const cell_b = Cell{ .char = 'A', .style = .{ .bold = false } };

    try std.testing.expect(!cellsEqual(cell_a, cell_b));
}

test "stylesEqual identical styles" {
    const style_a = Style{ .fg = .red, .bg = .blue, .bold = true };
    const style_b = Style{ .fg = .red, .bg = .blue, .bold = true };

    try std.testing.expect(stylesEqual(style_a, style_b));
}

test "stylesEqual different fg color" {
    const style_a = Style{ .fg = .red };
    const style_b = Style{ .fg = .green };

    try std.testing.expect(!stylesEqual(style_a, style_b));
}

test "stylesEqual different modifiers" {
    const style_a = Style{ .italic = true };
    const style_b = Style{ .italic = false };

    try std.testing.expect(!stylesEqual(style_a, style_b));
}

test "colorsEqual basic colors" {
    try std.testing.expect(colorsEqual(.red, .red));
    try std.testing.expect(!colorsEqual(.red, .green));
}

test "colorsEqual indexed colors" {
    try std.testing.expect(colorsEqual(.{ .indexed = 42 }, .{ .indexed = 42 }));
    try std.testing.expect(!colorsEqual(.{ .indexed = 42 }, .{ .indexed = 43 }));
}

test "colorsEqual rgb colors" {
    const color_a = Color{ .rgb = .{ .r = 255, .g = 128, .b = 64 } };
    const color_b = Color{ .rgb = .{ .r = 255, .g = 128, .b = 64 } };
    const color_c = Color{ .rgb = .{ .r = 255, .g = 128, .b = 65 } };

    try std.testing.expect(colorsEqual(color_a, color_b));
    try std.testing.expect(!colorsEqual(color_a, color_c));
}

test "compareBuffers identical buffers" {
    const allocator = std.testing.allocator;

    var buf1 = try Buffer.init(allocator, 10, 5);
    defer buf1.deinit();

    var buf2 = try Buffer.init(allocator, 10, 5);
    defer buf2.deinit();

    buf1.set(0, 0, .{ .char = 'A', .style = .{} });
    buf2.set(0, 0, .{ .char = 'A', .style = .{} });

    var diff = try compareBuffers(allocator, &buf1, &buf2);
    defer diff.deinit();

    try std.testing.expect(!diff.hasChanges());
}

test "compareBuffers different cells" {
    const allocator = std.testing.allocator;

    var buf1 = try Buffer.init(allocator, 10, 5);
    defer buf1.deinit();

    var buf2 = try Buffer.init(allocator, 10, 5);
    defer buf2.deinit();

    buf1.set(0, 0, .{ .char = 'A', .style = .{} });
    buf2.set(0, 0, .{ .char = 'B', .style = .{} });

    var diff = try compareBuffers(allocator, &buf1, &buf2);
    defer diff.deinit();

    try std.testing.expect(diff.hasChanges());
    try std.testing.expectEqual(@as(usize, 1), diff.count());
    try std.testing.expectEqual(ChangeType.modified, diff.changes.items[0].change_type);
}

test "compareBuffers size mismatch" {
    const allocator = std.testing.allocator;

    var buf1 = try Buffer.init(allocator, 10, 5);
    defer buf1.deinit();

    var buf2 = try Buffer.init(allocator, 12, 5);
    defer buf2.deinit();

    const result = compareBuffers(allocator, &buf1, &buf2);
    try std.testing.expectError(error.BufferSizeMismatch, result);
}

test "SideBySideComparison init and deinit" {
    const allocator = std.testing.allocator;

    var buf1 = try Buffer.init(allocator, 10, 3);
    defer buf1.deinit();

    var buf2 = try Buffer.init(allocator, 10, 3);
    defer buf2.deinit();

    var comparison = try SideBySideComparison.init(allocator, &buf1, &buf2);
    defer comparison.deinit();

    // Should have initialized diff
    try std.testing.expect(!comparison.diff.hasChanges());
}

test "SideBySideComparison render no changes" {
    const allocator = std.testing.allocator;

    var buf1 = try Buffer.init(allocator, 5, 2);
    defer buf1.deinit();

    var buf2 = try Buffer.init(allocator, 5, 2);
    defer buf2.deinit();

    var comparison = try SideBySideComparison.init(allocator, &buf1, &buf2);
    defer comparison.deinit();

    var output = try std.ArrayList(u8).initCapacity(allocator, 0);
    defer output.deinit(allocator);

    try comparison.render(output.writer(allocator));

    // Should mention no changes
    try std.testing.expect(std.mem.indexOf(u8, output.items, "No visual changes") != null);
}

test "SideBySideComparison render with changes" {
    const allocator = std.testing.allocator;

    var buf1 = try Buffer.init(allocator, 5, 2);
    defer buf1.deinit();

    var buf2 = try Buffer.init(allocator, 5, 2);
    defer buf2.deinit();

    // Add different content
    buf1.set(0, 0, .{ .char = 'A', .style = .{} });
    buf2.set(0, 0, .{ .char = 'B', .style = .{} });

    var comparison = try SideBySideComparison.init(allocator, &buf1, &buf2);
    defer comparison.deinit();

    var output = try std.ArrayList(u8).initCapacity(allocator, 0);
    defer output.deinit(allocator);

    try comparison.render(output.writer(allocator));

    // Should show changes
    try std.testing.expect(std.mem.indexOf(u8, output.items, "Visual changes detected") != null);
    try std.testing.expect(std.mem.indexOf(u8, output.items, "Side-by-Side") != null);
}

test "VisualDiff format output" {
    const allocator = std.testing.allocator;
    var diff = try VisualDiff.init(allocator);
    defer diff.deinit();

    try diff.addChange(.{
        .row = 2,
        .col = 5,
        .change_type = .modified,
        .old_cell = .{ .char = 'X', .style = .{} },
        .new_cell = .{ .char = 'Y', .style = .{} },
    });

    var output = try std.ArrayList(u8).initCapacity(allocator, 0);
    defer output.deinit(allocator);

    try diff.format("", .{}, output.writer(allocator));

    // Check output contains change information
    try std.testing.expect(std.mem.indexOf(u8, output.items, "Visual changes detected: 1 total") != null);
    try std.testing.expect(std.mem.indexOf(u8, output.items, "Modified: 1") != null);
}

test "Change format output" {
    const change = Change{
        .row = 3,
        .col = 7,
        .change_type = .added,
        .old_cell = null,
        .new_cell = .{ .char = 'Z', .style = .{} },
    };

    var buffer: [128]u8 = undefined;
    var fba = std.heap.FixedBufferAllocator.init(&buffer);
    const allocator = fba.allocator();

    var output = try std.ArrayList(u8).initCapacity(allocator, 0);
    defer output.deinit(allocator);

    try change.format("", .{}, output.writer(allocator));

    // Check output format
    try std.testing.expect(std.mem.indexOf(u8, output.items, "[ADD]") != null);
    try std.testing.expect(std.mem.indexOf(u8, output.items, "(3, 7)") != null);
}
