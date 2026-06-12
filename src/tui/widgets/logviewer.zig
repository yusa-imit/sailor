//! LogViewer Widget — Scrollable log display with search and tail mode
//!
//! A simple scrollable log viewer that displays a list of log entries with:
//! - Scroll navigation (scrollDown, scrollUp, pageDown, pageUp, goToTop, goToBottom)
//! - Text search with highlighting
//! - Tail mode (auto-scroll to bottom)
//! - Level coloring with customizable styles
//! - Optional block border
//! - Builder pattern for configuration

const std = @import("std");
const Buffer = @import("../buffer.zig").Buffer;
const Rect = @import("../layout.zig").Rect;
const Style = @import("../style.zig").Style;
const Color = @import("../style.zig").Color;
const Block = @import("block.zig").Block;

/// Log level for coloring
pub const LogLevel = enum {
    trace,
    debug,
    info,
    warn,
    err,
    fatal,

    /// Get default color for log level
    pub fn defaultColor(self: LogLevel) Color {
        return switch (self) {
            .trace => .bright_black,
            .debug => .cyan,
            .info => .green,
            .warn => .yellow,
            .err => .red,
            .fatal => .magenta,
        };
    }
};

/// Log entry with timestamp, level, message, and optional source
pub const LogEntry = struct {
    timestamp_ms: u64,
    level: LogLevel,
    message: []const u8,
    source: ?[]const u8 = null,
};

/// Log viewer widget — displays scrollable log entries with search and tail mode
pub const LogViewer = struct {
    entries: []const LogEntry,
    scroll_offset: usize = 0,
    search_query: []const u8 = "",
    tail_mode: bool = false,
    show_level_tags: bool = true,
    block: ?Block = null,
    level_style: Style = .{},
    search_style: Style = .{ .bg = .yellow, .fg = .black },
    default_style: Style = .{},

    /// Initialize a new log viewer with entries
    pub fn init(entries: []const LogEntry) LogViewer {
        return LogViewer{
            .entries = entries,
            .scroll_offset = 0,
            .search_query = "",
            .tail_mode = false,
            .show_level_tags = true,
            .block = null,
            .level_style = .{},
            .search_style = .{ .bg = .yellow, .fg = .black },
            .default_style = .{},
        };
    }

    /// Scroll down by 1 entry (clamps at entries.len - 1)
    pub fn scrollDown(self: *LogViewer) void {
        if (self.entries.len == 0) return;
        if (self.scroll_offset < self.entries.len - 1) {
            self.scroll_offset += 1;
        }
    }

    /// Scroll up by 1 entry (clamps at 0)
    pub fn scrollUp(self: *LogViewer) void {
        if (self.scroll_offset > 0) {
            self.scroll_offset -= 1;
        }
    }

    /// Page down (add page_size to scroll_offset, clamped)
    pub fn pageDown(self: *LogViewer, page_size: usize) void {
        if (self.entries.len == 0) return;
        const new_offset = self.scroll_offset + page_size;
        if (new_offset >= self.entries.len) {
            self.scroll_offset = self.entries.len - 1;
        } else {
            self.scroll_offset = new_offset;
        }
    }

    /// Page up (subtract page_size from scroll_offset, clamped)
    pub fn pageUp(self: *LogViewer, page_size: usize) void {
        if (self.entries.len == 0) return;
        if (self.scroll_offset < page_size) {
            self.scroll_offset = 0;
        } else {
            self.scroll_offset -= page_size;
        }
    }

    /// Go to first entry
    pub fn goToTop(self: *LogViewer) void {
        self.scroll_offset = 0;
    }

    /// Go to last entry
    pub fn goToBottom(self: *LogViewer) void {
        if (self.entries.len == 0) {
            self.scroll_offset = 0;
        } else {
            self.scroll_offset = self.entries.len - 1;
        }
    }

    /// Set search query (does not scroll)
    pub fn search(self: *LogViewer, query: []const u8) void {
        self.search_query = query;
    }

    /// Clear search query
    pub fn clearSearch(self: *LogViewer) void {
        self.search_query = "";
    }

    /// Set tail mode (auto-scroll to bottom when rendering)
    pub fn setTailMode(self: *LogViewer, enabled: bool) void {
        self.tail_mode = enabled;
    }

    /// Builder: set block border
    pub fn withBlock(self: LogViewer, block: Block) LogViewer {
        var result = self;
        result.block = block;
        return result;
    }

    /// Builder: set level style
    pub fn withLevelStyle(self: LogViewer, style: Style) LogViewer {
        var result = self;
        result.level_style = style;
        return result;
    }

    /// Builder: set search highlight style
    pub fn withSearchStyle(self: LogViewer, style: Style) LogViewer {
        var result = self;
        result.search_style = style;
        return result;
    }

    /// Builder: show/hide level tags
    pub fn withShowLevels(self: LogViewer, show: bool) LogViewer {
        var result = self;
        result.show_level_tags = show;
        return result;
    }

    /// Builder: set tail mode
    pub fn withTailMode(self: LogViewer, enabled: bool) LogViewer {
        var result = self;
        result.tail_mode = enabled;
        return result;
    }

    /// Render log viewer to buffer
    pub fn render(self: *LogViewer, buf: *Buffer, area: Rect) void {
        // Early return for zero-area
        if (area.width == 0 or area.height == 0) return;

        var content_area = area;

        // Render block border if present
        if (self.block) |block| {
            block.render(buf, area);
            // Shrink content area by 1 each side
            if (content_area.x + 1 >= content_area.x + content_area.width or
                content_area.y + 1 >= content_area.y + content_area.height)
            {
                return; // Content area too small
            }
            content_area.x += 1;
            content_area.y += 1;
            if (content_area.width >= 2) content_area.width -= 2;
            if (content_area.height >= 2) content_area.height -= 2;
            if (content_area.width == 0 or content_area.height == 0) return;
        }

        // Handle empty entries
        if (self.entries.len == 0) return;

        // Calculate starting index
        var start_idx: usize = 0;
        if (self.tail_mode) {
            // Tail mode: show latest N entries, calculate start from bottom
            const visible_height = content_area.height;
            if (self.entries.len <= visible_height) {
                start_idx = 0;
            } else {
                start_idx = self.entries.len - visible_height;
            }
        } else {
            // Normal mode: use scroll_offset
            start_idx = self.scroll_offset;
        }

        var row = content_area.y;
        const max_row = content_area.y + content_area.height;
        var entry_idx = start_idx;

        // Render visible entries
        while (entry_idx < self.entries.len and row < max_row) {
            const entry = self.entries[entry_idx];
            self.renderEntry(buf, entry, content_area.x, row, content_area.width);
            row += 1;
            entry_idx += 1;
        }
    }

    /// Render a single log entry line
    fn renderEntry(self: LogViewer, buf: *Buffer, entry: LogEntry, x: u16, y: u16, width: u16) void {
        if (width == 0) return;

        var col = x;
        const max_col = x + width;

        // Render level tag if enabled
        if (self.show_level_tags) {
            const tag = switch (entry.level) {
                .trace => "[TRACE]",
                .debug => "[DEBUG]",
                .info => "[INFO] ",
                .warn => "[WARN] ",
                .err => "[ERR]  ",
                .fatal => "[FATAL]",
            };
            const tag_len = @min(@as(u16, @intCast(tag.len)), max_col - col);
            if (tag_len > 0) {
                // Get level color, use level_style if set, otherwise use defaultColor
                var tag_style = self.level_style;
                if (tag_style.fg == null) {
                    tag_style.fg = entry.level.defaultColor();
                }
                buf.setString(col, y, tag[0..tag_len], tag_style);
                col += tag_len;
            }
        }

        // Render message text with search highlighting
        if (col < max_col) {
            renderMessageWithSearch(buf, entry.message, col, y, max_col - col, self.search_query, self.search_style, self.default_style);
        }
    }
};

/// Render message text with optional search highlighting
fn renderMessageWithSearch(
    buf: *Buffer,
    message: []const u8,
    x: u16,
    y: u16,
    width: u16,
    search_query: []const u8,
    search_style: Style,
    default_style: Style,
) void {
    if (width == 0 or message.len == 0) return;

    // If no search query, just render the message normally
    if (search_query.len == 0) {
        const msg_len = @min(@as(u16, @intCast(message.len)), width);
        buf.setString(x, y, message[0..msg_len], default_style);
        return;
    }

    // Search and highlight matching substrings (case-insensitive)
    var col = x;
    var msg_idx: usize = 0;

    while (msg_idx < message.len and col < x + width) {
        // Check if search_query matches at current position (case-insensitive)
        if (matchesAt(message, msg_idx, search_query)) {
            // Render matching substring with search_style
            const match_len = @min(@as(u16, @intCast(search_query.len)), x + width - col);
            if (match_len > 0) {
                buf.setString(col, y, message[msg_idx .. msg_idx + match_len], search_style);
                col += match_len;
                msg_idx += match_len;
            }
        } else {
            // Render single character with default style
            const char_len = std.unicode.utf8ByteSequenceLength(message[msg_idx]) catch 1;
            const actual_len = @min(@as(usize, char_len), message.len - msg_idx);
            const char_str = message[msg_idx .. msg_idx + actual_len];
            buf.setString(col, y, char_str, default_style);
            col += 1;
            msg_idx += actual_len;
        }
    }
}

/// Check if search_query matches at position in message (case-insensitive)
fn matchesAt(message: []const u8, pos: usize, query: []const u8) bool {
    if (query.len == 0) return false;
    if (pos + query.len > message.len) return false;

    return std.ascii.eqlIgnoreCase(message[pos .. pos + query.len], query);
}
