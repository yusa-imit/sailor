//! Keybinding Map & Bar — v2.21.0
//!
//! Manages key-to-action mappings and renders them as help text in a status bar.
//!
//! ## Design
//! - KeybindingEntry: immutable struct with key, action, and description
//! - KeybindingMap: stores entries and provides lookup by action name
//! - KeybindingBar: renders a help bar showing "[key] description" for each binding
//! - No allocator required (all data is caller-owned)
//!
//! ## Usage
//! ```zig
//! const entries = [_]KeybindingMap.KeybindingEntry{
//!     .{ .key = "C-s", .action = "save", .desc = "Save file" },
//!     .{ .key = "C-q", .action = "quit", .desc = "Quit" },
//! };
//! var map = KeybindingMap.register(&entries);
//! if (map.lookup("save")) |entry| {
//!     // Found: entry.key = "C-s", entry.desc = "Save file"
//! }
//!
//! const bar = KeybindingBar{ .map = map };
//! bar.render(&buffer, area);
//! ```

const std = @import("std");
const buffer_mod = @import("buffer.zig");
const Buffer = buffer_mod.Buffer;
const Cell = buffer_mod.Cell;
const layout_mod = @import("layout.zig");
const Rect = layout_mod.Rect;
const style_mod = @import("style.zig");
const Style = style_mod.Style;

/// Map of keybinding entries for registration and lookup
pub const KeybindingMap = struct {
    /// Single keybinding entry (nested for ergonomic KeybindingMap.KeybindingEntry access)
    pub const KeybindingEntry = struct {
        /// Key combination (e.g., "C-s", "M-x", "Enter")
        key: []const u8,
        /// Action name (e.g., "save", "quit", "delete")
        action: []const u8,
        /// Human-readable description (e.g., "Save file")
        desc: []const u8,
    };

    /// Slice of keybinding entries (caller-owned, must outlive this map)
    entries: []const KeybindingEntry = &.{},

    /// Register a set of keybindings from a slice.
    /// entries must outlive the returned KeybindingMap.
    pub fn register(entries: []const KeybindingEntry) KeybindingMap {
        return .{ .entries = entries };
    }

    /// Look up a keybinding entry by action name
    /// Returns the entry if found, null otherwise
    pub fn lookup(self: KeybindingMap, action: []const u8) ?KeybindingEntry {
        for (self.entries) |entry| {
            if (std.mem.eql(u8, entry.action, action)) {
                return entry;
            }
        }
        return null;
    }
};

/// Keybinding bar widget for rendering help text
pub const KeybindingBar = struct {
    /// The keybinding map to render
    map: KeybindingMap = .{},
    /// Style for the bar background
    style: Style = .{},

    /// Set the keybinding map and return a new bar
    pub fn withMap(self: KeybindingBar, map: KeybindingMap) KeybindingBar {
        var copy = self;
        copy.map = map;
        return copy;
    }

    /// Render the keybinding bar to the buffer
    pub fn render(self: KeybindingBar, buf: *Buffer, area: Rect) void {
        // Early return for zero-area
        if (area.width == 0 or area.height == 0) return;

        const y = area.y;

        // Fill the entire row with background style
        var x: u16 = 0;
        while (x < area.width) : (x += 1) {
            buf.set(area.x + x, y, Cell{ .char = ' ', .style = self.style });
        }

        // Render each keybinding entry
        var x_pos = area.x;
        for (self.map.entries) |entry| {
            if (x_pos >= area.x + area.width) break;

            // Render "[key] desc" format
            // Format: "[C-s] Save file"

            // Write opening bracket
            if (x_pos < area.x + area.width) {
                buf.set(x_pos, y, Cell{ .char = '[', .style = self.style });
                x_pos += 1;
            }

            // Write key
            for (entry.key) |ch| {
                if (x_pos >= area.x + area.width) break;
                buf.set(x_pos, y, Cell{ .char = ch, .style = self.style });
                x_pos += 1;
            }

            // Write closing bracket
            if (x_pos < area.x + area.width) {
                buf.set(x_pos, y, Cell{ .char = ']', .style = self.style });
                x_pos += 1;
            }

            // Write space
            if (x_pos < area.x + area.width) {
                buf.set(x_pos, y, Cell{ .char = ' ', .style = self.style });
                x_pos += 1;
            }

            // Write description
            for (entry.desc) |ch| {
                if (x_pos >= area.x + area.width) break;
                buf.set(x_pos, y, Cell{ .char = ch, .style = self.style });
                x_pos += 1;
            }

            // Write spacing between entries
            if (x_pos < area.x + area.width) {
                buf.set(x_pos, y, Cell{ .char = ' ', .style = self.style });
                x_pos += 1;
            }
            if (x_pos < area.x + area.width) {
                buf.set(x_pos, y, Cell{ .char = ' ', .style = self.style });
                x_pos += 1;
            }
        }
    }
};
