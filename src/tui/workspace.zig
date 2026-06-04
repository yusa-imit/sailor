//! Workspace — Multi-Pane Layout Manager (v2.22.0)
//!
//! Workspace manages a collection of named panes with flexible sizing,
//! focus tracking, and keyboard navigation.

const std = @import("std");
const Allocator = std.mem.Allocator;
const Rect = @import("layout.zig").Rect;
const buffer_mod = @import("buffer.zig");
const Buffer = buffer_mod.Buffer;
const Cell = buffer_mod.Cell;
const Style = @import("style.zig").Style;
const Color = @import("style.zig").Color;
const symbols = @import("symbols.zig");

/// Describes a single pane in a workspace
pub const WorkspacePane = struct {
    id: []const u8,         // unique identifier
    flex: f64 = 1.0,        // relative size weight (proportional allocation)
    min_size: u16 = 3,      // minimum size in cells
    focusable: bool = true, // can receive focus
};

/// Layout direction for panes
pub const WorkspaceSplit = enum {
    horizontal, // left-to-right
    vertical,   // top-to-bottom
};

/// Multi-pane workspace with focus management
pub const Workspace = struct {
    panes: []const WorkspacePane,
    split: WorkspaceSplit = .horizontal,
    gap: u16 = 0,           // gap between panes (currently renders as border)
    focus_idx: usize = 0,   // which pane is focused

    /// Compute rects for all panes given total area.
    /// Returns slice of Rect (length = panes.len), allocated by caller's allocator.
    pub fn computeRects(self: Workspace, allocator: Allocator, area: Rect) ![]Rect {
        const pane_count = self.panes.len;
        if (pane_count == 0) {
            return try allocator.alloc(Rect, 0);
        }

        const rects = try allocator.alloc(Rect, pane_count);

        // Handle zero-area case
        if (self.split == .horizontal and area.width == 0) {
            for (rects) |*rect| {
                rect.* = Rect{ .x = area.x, .y = area.y, .width = 0, .height = area.height };
            }
            return rects;
        }

        if (self.split == .vertical and area.height == 0) {
            for (rects) |*rect| {
                rect.* = Rect{ .x = area.x, .y = area.y, .width = area.width, .height = 0 };
            }
            return rects;
        }

        // Calculate sizes based on flex weights
        var total_flex: f64 = 0.0;
        for (self.panes) |pane| {
            total_flex += pane.flex;
        }

        if (self.split == .horizontal) {
            // Horizontal split: distribute width by flex ratio
            const sizes: []u16 = try allocator.alloc(u16, pane_count);
            defer allocator.free(sizes);

            // Step 1: compute ideal sizes using round (not truncate) to avoid float precision issues
            var total_size: u32 = 0;
            for (self.panes, sizes) |pane, *size| {
                const ideal = @as(f64, @floatFromInt(area.width)) * (pane.flex / total_flex);
                size.* = @max(@as(u16, @intFromFloat(@round(ideal))), 1);
                total_size += size.*;
            }

            // Step 2: clamp to min_size and recalculate if needed
            var needs_adjustment = false;
            for (self.panes, sizes) |pane, *size| {
                const old_size = size.*;
                size.* = @max(size.*, pane.min_size);
                if (size.* != old_size) needs_adjustment = true;
            }

            // Step 3: if total exceeds available width, proportionally reduce
            if (needs_adjustment) {
                total_size = 0;
                for (sizes) |size| {
                    total_size += size;
                }

                if (total_size > area.width) {
                    // Reduce sizes proportionally while respecting min_size
                    var reduction_available: i32 = @intCast(total_size - area.width);

                    while (reduction_available > 0) {
                        var made_progress = false;
                        for (self.panes, sizes) |pane, *size| {
                            if (size.* > pane.min_size and reduction_available > 0) {
                                size.* -= 1;
                                reduction_available -= 1;
                                made_progress = true;
                            }
                        }
                        if (!made_progress) break; // All at min_size
                    }
                }
            }

            // Step 4: build rects (contiguous in x, full height)
            var x_pos: u16 = area.x;
            for (sizes, rects) |size, *rect| {
                rect.* = Rect{
                    .x = x_pos,
                    .y = area.y,
                    .width = size,
                    .height = area.height,
                };
                x_pos += size;
            }
        } else {
            // Vertical split: distribute height by flex ratio
            const sizes: []u16 = try allocator.alloc(u16, pane_count);
            defer allocator.free(sizes);

            // Step 1: compute ideal sizes using round (not truncate) to avoid float precision issues
            var total_size: u32 = 0;
            for (self.panes, sizes) |pane, *size| {
                const ideal = @as(f64, @floatFromInt(area.height)) * (pane.flex / total_flex);
                size.* = @max(@as(u16, @intFromFloat(@round(ideal))), 1);
                total_size += size.*;
            }

            // Step 2: clamp to min_size
            var needs_adjustment = false;
            for (self.panes, sizes) |pane, *size| {
                const old_size = size.*;
                size.* = @max(size.*, pane.min_size);
                if (size.* != old_size) needs_adjustment = true;
            }

            // Step 3: if total exceeds available height, proportionally reduce
            if (needs_adjustment) {
                total_size = 0;
                for (sizes) |size| {
                    total_size += size;
                }

                if (total_size > area.height) {
                    // Reduce sizes proportionally while respecting min_size
                    var reduction_available: i32 = @intCast(total_size - area.height);

                    while (reduction_available > 0) {
                        var made_progress = false;
                        for (self.panes, sizes) |pane, *size| {
                            if (size.* > pane.min_size and reduction_available > 0) {
                                size.* -= 1;
                                reduction_available -= 1;
                                made_progress = true;
                            }
                        }
                        if (!made_progress) break; // All at min_size
                    }
                }
            }

            // Step 4: build rects (contiguous in y, full width)
            var y_pos: u16 = area.y;
            for (sizes, rects) |size, *rect| {
                rect.* = Rect{
                    .x = area.x,
                    .y = y_pos,
                    .width = area.width,
                    .height = size,
                };
                y_pos += size;
            }
        }

        return rects;
    }

    /// Move focus to next focusable pane (wraps around)
    pub fn focusNext(self: *Workspace) void {
        if (self.panes.len <= 1) return;

        const start_idx = self.focus_idx;
        var idx = (self.focus_idx + 1) % self.panes.len;

        while (true) {
            if (self.panes[idx].focusable) {
                self.focus_idx = idx;
                return;
            }
            idx = (idx + 1) % self.panes.len;
            if (idx == start_idx) return; // Full loop, no focusable found
        }
    }

    /// Move focus to previous focusable pane (wraps around)
    pub fn focusPrev(self: *Workspace) void {
        if (self.panes.len <= 1) return;

        const start_idx = self.focus_idx;
        var idx = if (self.focus_idx == 0) self.panes.len - 1 else self.focus_idx - 1;

        while (true) {
            if (self.panes[idx].focusable) {
                self.focus_idx = idx;
                return;
            }
            idx = if (idx == 0) self.panes.len - 1 else idx - 1;
            if (idx == start_idx) return; // Full loop, no focusable found
        }
    }

    /// Focus pane by id. Returns false if not found.
    pub fn focusPane(self: *Workspace, id: []const u8) bool {
        for (self.panes, 0..) |pane, idx| {
            if (std.mem.eql(u8, pane.id, id)) {
                self.focus_idx = idx;
                return true;
            }
        }
        return false;
    }

    /// Get id of currently focused pane, or null if focus_idx is out of bounds
    pub fn getFocusedId(self: Workspace) ?[]const u8 {
        if (self.focus_idx >= self.panes.len) return null;
        return self.panes[self.focus_idx].id;
    }

    /// Check if a pane is currently focused
    pub fn isFocused(self: Workspace, id: []const u8) bool {
        if (self.focus_idx >= self.panes.len) return false;
        return std.mem.eql(u8, self.panes[self.focus_idx].id, id);
    }

    /// Render dividers between panes
    pub fn renderDividers(self: Workspace, buf: *Buffer, rects: []const Rect) void {
        if (rects.len <= 1) return;

        const divider_style = Style{ .fg = .bright_black };

        if (self.split == .horizontal) {
            // Draw vertical dividers at boundaries between panes
            for (rects[0 .. rects.len - 1]) |rect| {
                const divider_x = rect.x + rect.width;
                var y = rect.y;
                while (y < rect.y + rect.height and y < buf.height) : (y += 1) {
                    buf.set(divider_x, y, Cell.init('│', divider_style));
                }
            }
        } else {
            // Draw horizontal dividers at boundaries between panes
            for (rects[0 .. rects.len - 1]) |rect| {
                const divider_y = rect.y + rect.height;
                var x = rect.x;
                while (x < rect.x + rect.width and x < buf.width) : (x += 1) {
                    buf.set(x, divider_y, Cell.init('─', divider_style));
                }
            }
        }
    }
};
