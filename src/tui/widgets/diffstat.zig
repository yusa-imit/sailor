//! DiffStat Widget — displays file-level diff statistics with visual bar graphs.
//!
//! DiffStat visualizes changes across multiple files, showing insertion/deletion counts
//! with proportional bar graphs. Ideal for displaying git diff summaries or file change
//! statistics.
//!
//! ## Features
//! - File-level change statistics (insertions/deletions)
//! - Proportional bar rendering (customizable characters)
//! - Binary file support
//! - Configurable styling for insertions, deletions, and filenames
//! - Optional block borders
//! - Auto-width filename column or fixed width
//!
//! ## Usage
//! ```zig
//! var entries: [2]DiffStat.DiffStatEntry = .{
//!     .{ .filename = "main.zig", .insertions = 150, .deletions = 42 },
//!     .{ .filename = "lib.zig", .insertions = 50, .deletions = 10 },
//! };
//! const ds = DiffStat.init(&entries)
//!     .withBarWidth(25)
//!     .withInsertionStyle(Style{ .fg = Color.green });
//! ds.render(&buf, area);
//! ```

const std = @import("std");
const buffer_mod = @import("../buffer.zig");
const Buffer = buffer_mod.Buffer;
const layout_mod = @import("../layout.zig");
const Rect = layout_mod.Rect;
const style_mod = @import("../style.zig");
const Style = style_mod.Style;
const Color = style_mod.Color;
const block_mod = @import("block.zig");
const Block = block_mod.Block;

/// DiffStat widget — displays diff statistics with visual bars
pub const DiffStat = struct {
    /// Single entry in a DiffStat widget
    pub const DiffStatEntry = struct {
        filename: []const u8,
        insertions: u32,
        deletions: u32,
        binary: bool = false,
    };

    /// File entries to display
    entries: []const DiffStatEntry,

    /// Maximum width for filename column (null = auto from entries)
    max_filename_width: ?u16 = null,

    /// Width of the insertion/deletion bar
    bar_width: u16 = 20,

    /// Character to represent insertions
    insertion_char: u21 = '+',

    /// Character to represent deletions
    deletion_char: u21 = '-',

    /// Style for insertion characters
    insertion_style: Style = .{ .fg = Color.green },

    /// Style for deletion characters
    deletion_style: Style = .{ .fg = Color.red },

    /// Style for filename column
    filename_style: Style = .{},

    /// Style for count numbers
    count_style: Style = .{},

    /// Style for binary file indicator
    binary_style: Style = .{ .fg = Color.yellow },

    /// Optional block for borders
    block: ?Block = null,

    /// Initialize DiffStat with entries
    pub fn init(entries: []const DiffStatEntry) DiffStat {
        return .{
            .entries = entries,
        };
    }

    /// Sum all insertions across entries
    pub fn totalInsertions(self: DiffStat) u32 {
        var total: u32 = 0;
        for (self.entries) |entry| {
            total +|= entry.insertions;
        }
        return total;
    }

    /// Sum all deletions across entries
    pub fn totalDeletions(self: DiffStat) u32 {
        var total: u32 = 0;
        for (self.entries) |entry| {
            total +|= entry.deletions;
        }
        return total;
    }

    /// Count total number of files
    pub fn totalFiles(self: DiffStat) usize {
        return self.entries.len;
    }

    /// Compute maximum filename width from entries or max_filename_width cap
    pub fn computeMaxFilenameWidth(self: DiffStat) u16 {
        if (self.entries.len == 0) return 0;

        var max_width: u16 = 0;
        for (self.entries) |entry| {
            const filename_len = @as(u16, @intCast(entry.filename.len));
            if (filename_len > max_width) {
                max_width = filename_len;
            }
        }

        if (self.max_filename_width) |cap| {
            return @min(max_width, cap);
        }

        return max_width;
    }

    /// Compute maximum total changes (insertions + deletions) across entries
    pub fn computeMaxChanges(self: DiffStat) u32 {
        if (self.entries.len == 0) return 0;

        var max_changes: u32 = 0;
        for (self.entries) |entry| {
            const changes = entry.insertions +| entry.deletions;
            if (changes > max_changes) {
                max_changes = changes;
            }
        }

        return max_changes;
    }

    /// Builder method: set max filename width
    pub fn withMaxFilenameWidth(self: DiffStat, width: u16) DiffStat {
        var result = self;
        result.max_filename_width = width;
        return result;
    }

    /// Builder method: set bar width
    pub fn withBarWidth(self: DiffStat, width: u16) DiffStat {
        var result = self;
        result.bar_width = width;
        return result;
    }

    /// Builder method: set insertion character
    pub fn withInsertionChar(self: DiffStat, char: u21) DiffStat {
        var result = self;
        result.insertion_char = char;
        return result;
    }

    /// Builder method: set deletion character
    pub fn withDeletionChar(self: DiffStat, char: u21) DiffStat {
        var result = self;
        result.deletion_char = char;
        return result;
    }

    /// Builder method: set insertion style
    pub fn withInsertionStyle(self: DiffStat, new_style: Style) DiffStat {
        var result = self;
        result.insertion_style = new_style;
        return result;
    }

    /// Builder method: set deletion style
    pub fn withDeletionStyle(self: DiffStat, new_style: Style) DiffStat {
        var result = self;
        result.deletion_style = new_style;
        return result;
    }

    /// Builder method: set filename style
    pub fn withFilenameStyle(self: DiffStat, new_style: Style) DiffStat {
        var result = self;
        result.filename_style = new_style;
        return result;
    }

    /// Builder method: set count style
    pub fn withCountStyle(self: DiffStat, new_style: Style) DiffStat {
        var result = self;
        result.count_style = new_style;
        return result;
    }

    /// Builder method: set binary style
    pub fn withBinaryStyle(self: DiffStat, new_style: Style) DiffStat {
        var result = self;
        result.binary_style = new_style;
        return result;
    }

    /// Builder method: set block
    pub fn withBlock(self: DiffStat, new_block: Block) DiffStat {
        var result = self;
        result.block = new_block;
        return result;
    }

    /// Render the DiffStat widget
    pub fn render(self: DiffStat, buf: *Buffer, area: Rect) void {
        // Handle block if present
        var inner_area = area;
        if (self.block) |blk| {
            blk.render(buf, area);
            inner_area = blk.inner(area);
        }

        // Early exit if area too small
        if (inner_area.width == 0 or inner_area.height == 0) return;

        // Precompute dimensions
        const max_filename_width = self.computeMaxFilenameWidth();
        const max_changes = self.computeMaxChanges();

        // Render each entry
        for (self.entries, 0..) |entry, idx| {
            const row_y = inner_area.y + @as(u16, @intCast(idx));

            // Stop if we've run out of vertical space
            if (row_y >= inner_area.y + inner_area.height) break;

            var x = inner_area.x;

            // 1. Write filename (padded to max_filename_width)
            const filename_to_write = if (entry.filename.len > max_filename_width)
                entry.filename[0..max_filename_width]
            else
                entry.filename;

            buf.setString(x, row_y, filename_to_write, self.filename_style);

            // Pad filename to max width
            x += @as(u16, @intCast(filename_to_write.len));
            while (x < inner_area.x + max_filename_width and x < inner_area.x + inner_area.width) : (x += 1) {
                buf.set(x, row_y, .{ .char = ' ', .style = self.filename_style });
            }

            // Stop if we're out of horizontal space
            if (x + 3 > inner_area.x + inner_area.width) continue;

            // 2. Write pipe separator
            buf.set(x, row_y, .{ .char = ' ', .style = .{} });
            x += 1;

            if (x >= inner_area.x + inner_area.width) continue;

            buf.set(x, row_y, .{ .char = '|', .style = .{} });
            x += 1;

            if (x >= inner_area.x + inner_area.width) continue;

            buf.set(x, row_y, .{ .char = ' ', .style = .{} });
            x += 1;

            // 3. Handle binary vs. normal files
            if (entry.binary) {
                // Binary: show "Bin" padded to bar_width
                const bin_str = "Bin";
                buf.setString(x, row_y, bin_str, self.binary_style);
                x += @as(u16, @intCast(bin_str.len));

                // Pad with spaces to bar_width
                while (x < inner_area.x + max_filename_width + 3 + self.bar_width and
                    x < inner_area.x + inner_area.width) : (x += 1)
                {
                    buf.set(x, row_y, .{ .char = ' ', .style = .{} });
                }
            } else {
                // Normal: render insertion/deletion bar
                if (max_changes == 0) {
                    // No changes: just pad with spaces
                    while (x < inner_area.x + max_filename_width + 3 + self.bar_width and
                        x < inner_area.x + inner_area.width) : (x += 1)
                    {
                        buf.set(x, row_y, .{ .char = ' ', .style = .{} });
                    }
                } else {
                    // Calculate proportional columns using rounding
                    const insertion_cols = if (entry.insertions == 0)
                        0
                    else
                        @max(1, @min(self.bar_width, @as(u16, @intCast(
                            ((@as(u64, entry.insertions) * @as(u64, self.bar_width)) + (@as(u64, max_changes) / 2)) / @as(u64, max_changes)
                        ))));

                    const deletion_cols = if (entry.deletions == 0)
                        0
                    else
                        @max(1, @min(self.bar_width -| insertion_cols, @as(u16, @intCast(
                            ((@as(u64, entry.deletions) * @as(u64, self.bar_width)) + (@as(u64, max_changes) / 2)) / @as(u64, max_changes)
                        ))));

                    // Write insertion characters
                    var i: u16 = 0;
                    while (i < insertion_cols and x < inner_area.x + inner_area.width) : (i += 1) {
                        buf.set(x, row_y, .{ .char = self.insertion_char, .style = self.insertion_style });
                        x += 1;
                    }

                    // Write deletion characters
                    i = 0;
                    while (i < deletion_cols and x < inner_area.x + inner_area.width) : (i += 1) {
                        buf.set(x, row_y, .{ .char = self.deletion_char, .style = self.deletion_style });
                        x += 1;
                    }

                    // Pad remaining bar space with spaces
                    const used_cols = insertion_cols + deletion_cols;
                    i = used_cols;
                    while (i < self.bar_width and x < inner_area.x + inner_area.width) : (i += 1) {
                        buf.set(x, row_y, .{ .char = ' ', .style = .{} });
                        x += 1;
                    }
                }

                // 4. Write insertion count
                if (x < inner_area.x + inner_area.width) {
                    buf.set(x, row_y, .{ .char = ' ', .style = .{} });
                    x += 1;
                }

                if (x < inner_area.x + inner_area.width) {
                    buf.set(x, row_y, .{ .char = self.insertion_char, .style = self.count_style });
                    x += 1;
                }

                // Format insertion count
                if (entry.insertions > 0 and x < inner_area.x + inner_area.width) {
                    var count_buf: [20]u8 = undefined;
                    const count_str = std.fmt.bufPrint(&count_buf, "{}", .{entry.insertions}) catch "";
                    buf.setString(x, row_y, count_str, self.count_style);
                    x += @as(u16, @intCast(count_str.len));
                }

                // 5. Write deletion count
                if (x < inner_area.x + inner_area.width) {
                    buf.set(x, row_y, .{ .char = ' ', .style = .{} });
                    x += 1;
                }

                if (x < inner_area.x + inner_area.width) {
                    buf.set(x, row_y, .{ .char = self.deletion_char, .style = self.count_style });
                    x += 1;
                }

                // Format deletion count
                if (entry.deletions > 0 and x < inner_area.x + inner_area.width) {
                    var count_buf: [20]u8 = undefined;
                    const count_str = std.fmt.bufPrint(&count_buf, "{}", .{entry.deletions}) catch "";
                    buf.setString(x, row_y, count_str, self.count_style);
                }
            }
        }
    }
};
