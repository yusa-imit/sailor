const std = @import("std");
const Allocator = std.mem.Allocator;
const buffer_mod = @import("../buffer.zig");
const Buffer = buffer_mod.Buffer;
const Cell = buffer_mod.Cell;
const layout_mod = @import("../layout.zig");
const Rect = layout_mod.Rect;
const style_mod = @import("../style.zig");
const Style = style_mod.Style;
const Color = style_mod.Color;
const Span = style_mod.Span;
const budget_mod = @import("../budget.zig");
const RenderBudget = budget_mod.RenderBudget;
const Event = @import("../tui.zig").Event;
const lazy_mod = @import("../lazy.zig");
const LazyBuffer = lazy_mod.LazyBuffer;

/// Debug overlay mode
pub const DebugMode = enum {
    /// Show layout rectangles for all rendered widgets
    layout_rects,
    /// Show render statistics (FPS, frame time, dirty cells)
    render_stats,
    /// Show event log (recent key/resize/mouse events)
    event_log,
    /// Show all information
    all,
};

/// Debug overlay widget for displaying TUI debugging information
pub const DebugOverlay = struct {
    /// Rectangles to highlight (for layout debugging)
    rects: std.ArrayList(DebugRect),
    /// Render statistics
    stats: RenderStats,
    /// Event log (circular buffer)
    events: std.ArrayList(EventLogEntry),
    max_events: usize,
    /// Display mode
    mode: DebugMode,
    /// Position on screen
    position: Position,
    allocator: Allocator,

    pub const Position = enum {
        top_left,
        top_right,
        bottom_left,
        bottom_right,
    };

    pub const DebugRect = struct {
        rect: Rect,
        label: []const u8,
        color: Color,
    };

    pub const RenderStats = struct {
        fps: f64 = 0.0,
        frame_time_ns: u64 = 0,
        dirty_cells: usize = 0,
        total_cells: usize = 0,
        skipped_frames: u64 = 0,
    };

    pub const EventLogEntry = struct {
        timestamp_ns: u64,
        event: Event,
    };

    /// Initialize debug overlay
    pub fn init(allocator: Allocator, mode: DebugMode, position: Position) DebugOverlay {
        return .{
            .rects = .{},
            .stats = .{},
            .events = .{},
            .max_events = 10, // Show last 10 events
            .mode = mode,
            .position = position,
            .allocator = allocator,
        };
    }

    /// Free debug overlay resources
    pub fn deinit(self: *DebugOverlay) void {
        self.rects.deinit(self.allocator);
        self.events.deinit(self.allocator);
    }

    /// Add rectangle to highlight
    pub fn addRect(self: *DebugOverlay, rect: Rect, label: []const u8, color: Color) !void {
        try self.rects.append(self.allocator, .{ .rect = rect, .label = label, .color = color });
    }

    /// Clear all rectangles
    pub fn clearRects(self: *DebugOverlay) void {
        self.rects.clearRetainingCapacity();
    }

    /// Update render statistics from budget
    pub fn updateStats(self: *DebugOverlay, budget: *const RenderBudget, lazy: ?*const LazyBuffer) void {
        self.stats.fps = budget.stats.fps();
        self.stats.frame_time_ns = budget.stats.avg_frame_ns;
        self.stats.skipped_frames = budget.stats.skipped_frames;

        if (lazy) |lb| {
            self.stats.dirty_cells = lb.countDirty();
            self.stats.total_cells = @as(usize, lb.buffer.width) * @as(usize, lb.buffer.height);
        }
    }

    /// Log an event
    pub fn logEvent(self: *DebugOverlay, event: Event) !void {
        const now = std.time.nanoTimestamp();
        const entry = EventLogEntry{ .timestamp_ns = @intCast(now), .event = event };

        if (self.events.items.len >= self.max_events) {
            // Circular buffer: remove oldest
            _ = self.events.orderedRemove(0);
        }

        try self.events.append(self.allocator, entry);
    }

    /// Clear event log
    pub fn clearEvents(self: *DebugOverlay) void {
        self.events.clearRetainingCapacity();
    }

    /// Render debug overlay
    pub fn render(self: DebugOverlay, buf: *Buffer, area: Rect) void {
        switch (self.mode) {
            .layout_rects => self.renderLayoutRects(buf, area),
            .render_stats => self.renderRenderStats(buf, area),
            .event_log => self.renderEventLog(buf, area),
            .all => {
                const third = area.height / 3;
                self.renderLayoutRects(buf, Rect{ .x = area.x, .y = area.y, .width = area.width, .height = third });
                self.renderRenderStats(buf, Rect{ .x = area.x, .y = area.y + third, .width = area.width, .height = third });
                self.renderEventLog(buf, Rect{ .x = area.x, .y = area.y + third * 2, .width = area.width, .height = third });
            },
        }
    }

    fn renderLayoutRects(self: DebugOverlay, buf: *Buffer, area: Rect) void {
        // Draw title
        const title = "Layout Rects";
        buf.setString(area.x + 1, area.y, title, .{ .fg = Color.yellow, .bold = true });

        // Draw each rectangle outline
        for (self.rects.items, 0..) |debug_rect, i| {
            const rect = debug_rect.rect;
            const color = debug_rect.color;

            // Draw border
            if (rect.height > 0) {
                // Top border
                var x = rect.x;
                while (x < rect.x + rect.width and x < buf.width) : (x += 1) {
                    buf.setChar(x, rect.y, '─', .{ .fg = color });
                }
                // Bottom border
                if (rect.height > 1) {
                    x = rect.x;
                    while (x < rect.x + rect.width and x < buf.width) : (x += 1) {
                        buf.setChar(x, rect.y + rect.height - 1, '─', .{ .fg = color });
                    }
                }
            }

            if (rect.width > 0) {
                // Left border
                var y = rect.y;
                while (y < rect.y + rect.height and y < buf.height) : (y += 1) {
                    buf.setChar(rect.x, y, '│', .{ .fg = color });
                }
                // Right border
                if (rect.width > 1) {
                    y = rect.y;
                    while (y < rect.y + rect.height and y < buf.height) : (y += 1) {
                        buf.setChar(rect.x + rect.width - 1, y, '│', .{ .fg = color });
                    }
                }
            }

            // Draw label at top-left corner
            if (rect.width > 2 and rect.height > 0) {
                var label_buf: [64]u8 = undefined;
                const label = std.fmt.bufPrint(&label_buf, "{s}[{}]", .{ debug_rect.label, i }) catch debug_rect.label;
                buf.setString(rect.x + 1, rect.y, label, .{ .fg = color, .bold = true });
            }
        }
    }

    fn renderRenderStats(self: DebugOverlay, buf: *Buffer, area: Rect) void {
        var line: u16 = 0;
        const title = "Render Stats";
        buf.setString(area.x + 1, area.y + line, title, .{ .fg = Color.cyan, .bold = true });
        line += 1;

        var line_buf: [128]u8 = undefined;

        // FPS
        if (area.y + line < area.y + area.height) {
            const fps_str = std.fmt.bufPrint(&line_buf, "FPS: {d:.1}", .{self.stats.fps}) catch "FPS: N/A";
            buf.setString(area.x + 1, area.y + line, fps_str, .{ .fg = Color.white });
            line += 1;
        }

        // Frame time
        if (area.y + line < area.y + area.height) {
            const frame_ms = @as(f64, @floatFromInt(self.stats.frame_time_ns)) / 1_000_000.0;
            const time_str = std.fmt.bufPrint(&line_buf, "Frame: {d:.2}ms", .{frame_ms}) catch "Frame: N/A";
            buf.setString(area.x + 1, area.y + line, time_str, .{ .fg = Color.white });
            line += 1;
        }

        // Dirty cells
        if (area.y + line < area.y + area.height and self.stats.total_cells > 0) {
            const pct = @as(f64, @floatFromInt(self.stats.dirty_cells)) / @as(f64, @floatFromInt(self.stats.total_cells)) * 100.0;
            const dirty_str = std.fmt.bufPrint(&line_buf, "Dirty: {}/{} ({d:.1}%)", .{ self.stats.dirty_cells, self.stats.total_cells, pct }) catch "Dirty: N/A";
            buf.setString(area.x + 1, area.y + line, dirty_str, .{ .fg = Color.white });
            line += 1;
        }

        // Skipped frames
        if (area.y + line < area.y + area.height) {
            const skip_str = std.fmt.bufPrint(&line_buf, "Skipped: {}", .{self.stats.skipped_frames}) catch "Skipped: N/A";
            buf.setString(area.x + 1, area.y + line, skip_str, .{ .fg = Color.white });
        }
    }

    fn renderEventLog(self: DebugOverlay, buf: *Buffer, area: Rect) void {
        var line: u16 = 0;
        const title = "Event Log";
        buf.setString(area.x + 1, area.y + line, title, .{ .fg = Color.magenta, .bold = true });
        line += 1;

        var line_buf: [128]u8 = undefined;

        // Show events from newest to oldest
        var i: usize = self.events.items.len;
        while (i > 0 and line < area.height) {
            i -= 1;
            const entry = self.events.items[i];

            const event_str = switch (entry.event) {
                .key => |k| switch (k.code) {
                    .char => |c| std.fmt.bufPrint(&line_buf, "Key: '{c}'", .{c}) catch "Key: ?",
                    .enter => "Key: Enter",
                    .backspace => "Key: Backspace",
                    .tab => "Key: Tab",
                    .esc => "Key: Esc",
                    .up => "Key: Up",
                    .down => "Key: Down",
                    .left => "Key: Left",
                    .right => "Key: Right",
                    else => "Key: Other",
                },
                .resize => |r| std.fmt.bufPrint(&line_buf, "Resize: {}x{}", .{ r.width, r.height }) catch "Resize: ?",
                .mouse => "Mouse",
                .gamepad => "Gamepad",
            };

            buf.setString(area.x + 1, area.y + line, event_str, .{ .fg = Color.white });
            line += 1;
        }
    }
};

test "DebugOverlay init" {
    const allocator = std.testing.allocator;
    var overlay = DebugOverlay.init(allocator, .all, .top_left);
    defer overlay.deinit();

    try std.testing.expectEqual(DebugMode.all, overlay.mode);
    try std.testing.expectEqual(DebugOverlay.Position.top_left, overlay.position);
}

test "DebugOverlay addRect" {
    const allocator = std.testing.allocator;
    var overlay = DebugOverlay.init(allocator, .layout_rects, .top_left);
    defer overlay.deinit();

    try overlay.addRect(Rect{ .x = 0, .y = 0, .width = 10, .height = 5 }, "Widget1", Color.red);
    try overlay.addRect(Rect{ .x = 10, .y = 0, .width = 10, .height = 5 }, "Widget2", Color.blue);

    try std.testing.expectEqual(@as(usize, 2), overlay.rects.items.len);
    try std.testing.expectEqual(@as(u16, 0), overlay.rects.items[0].rect.x);
    try std.testing.expectEqual(@as(u16, 10), overlay.rects.items[1].rect.x);
}

test "DebugOverlay clearRects" {
    const allocator = std.testing.allocator;
    var overlay = DebugOverlay.init(allocator, .layout_rects, .top_left);
    defer overlay.deinit();

    try overlay.addRect(Rect{ .x = 0, .y = 0, .width = 10, .height = 5 }, "Widget1", Color.red);
    overlay.clearRects();

    try std.testing.expectEqual(@as(usize, 0), overlay.rects.items.len);
}

test "DebugOverlay updateStats" {
    const allocator = std.testing.allocator;
    var overlay = DebugOverlay.init(allocator, .render_stats, .top_right);
    defer overlay.deinit();

    var budget = RenderBudget.init(60);
    budget.stats.recordFrame(16_666_666); // ~60fps

    overlay.updateStats(&budget, null);

    try std.testing.expect(overlay.stats.fps > 59.9);
    try std.testing.expect(overlay.stats.fps < 60.1);
}

test "DebugOverlay logEvent" {
    const allocator = std.testing.allocator;
    var overlay = DebugOverlay.init(allocator, .event_log, .bottom_left);
    defer overlay.deinit();

    try overlay.logEvent(.{ .key = .{ .code = .{ .char = 'a' } } });
    try overlay.logEvent(.{ .resize = .{ .width = 80, .height = 24 } });

    try std.testing.expectEqual(@as(usize, 2), overlay.events.items.len);
}

test "DebugOverlay event log circular buffer" {
    const allocator = std.testing.allocator;
    var overlay = DebugOverlay.init(allocator, .event_log, .bottom_right);
    defer overlay.deinit();

    overlay.max_events = 3;

    // Add 5 events (exceeds max)
    try overlay.logEvent(.{ .key = .{ .code = .{ .char = 'a' } } });
    try overlay.logEvent(.{ .key = .{ .code = .{ .char = 'b' } } });
    try overlay.logEvent(.{ .key = .{ .code = .{ .char = 'c' } } });
    try overlay.logEvent(.{ .key = .{ .code = .{ .char = 'd' } } });
    try overlay.logEvent(.{ .key = .{ .code = .{ .char = 'e' } } });

    // Should only have last 3
    try std.testing.expectEqual(@as(usize, 3), overlay.events.items.len);
    try std.testing.expectEqual(@as(u8, 'c'), overlay.events.items[0].event.key.code.char);
    try std.testing.expectEqual(@as(u8, 'd'), overlay.events.items[1].event.key.code.char);
    try std.testing.expectEqual(@as(u8, 'e'), overlay.events.items[2].event.key.code.char);
}

test "DebugOverlay clearEvents" {
    const allocator = std.testing.allocator;
    var overlay = DebugOverlay.init(allocator, .event_log, .top_left);
    defer overlay.deinit();

    try overlay.logEvent(.{ .key = .{ .code = .{ .char = 'a' } } });
    overlay.clearEvents();

    try std.testing.expectEqual(@as(usize, 0), overlay.events.items.len);
}

test "DebugOverlay render layout_rects" {
    const allocator = std.testing.allocator;
    var overlay = DebugOverlay.init(allocator, .layout_rects, .top_left);
    defer overlay.deinit();

    var buf = try Buffer.init(allocator, 40, 10);
    defer buf.deinit();

    try overlay.addRect(Rect{ .x = 2, .y = 2, .width = 10, .height = 5 }, "Test", Color.green);

    overlay.render(&buf, Rect{ .x = 0, .y = 0, .width = 40, .height = 10 });

    // Verify border characters are drawn
    const top_left = buf.getConst(2, 2).?;
    try std.testing.expectEqual(@as(u21, '─'), top_left.char);
}
