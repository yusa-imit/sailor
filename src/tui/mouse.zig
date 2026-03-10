//! Mouse event handling module
//!
//! Provides mouse event parsing and handling for TUI applications.
//! Supports standard mouse events (click, drag, scroll, double-click) via ANSI escape sequences.
//!
//! Terminal must support mouse tracking modes:
//! - CSI ? 1000 h — Enable basic mouse tracking (press/release)
//! - CSI ? 1002 h — Enable button-event tracking (drag)
//! - CSI ? 1003 h — Enable any-event tracking (motion)
//! - CSI ? 1006 h — Enable SGR extended mode (large terminals)

const std = @import("std");

/// Mouse button types
pub const MouseButton = enum {
    left,
    middle,
    right,
    none, // For move events
};

/// Mouse event types
pub const MouseEventType = enum {
    press, // Button pressed
    release, // Button released
    drag, // Button held while moving
    move, // Mouse moved without button
    scroll_up,
    scroll_down,
    double_click, // Detected based on timing
};

/// Mouse event with position and button info
pub const MouseEvent = struct {
    event_type: MouseEventType,
    button: MouseButton,
    x: u16, // Column (0-based)
    y: u16, // Row (0-based)
    modifiers: Modifiers = .{},
};

/// Keyboard modifiers for mouse events
pub const Modifiers = struct {
    shift: bool = false,
    alt: bool = false,
    ctrl: bool = false,
};

/// Mouse tracking mode
pub const TrackingMode = enum {
    off, // No mouse tracking
    click, // Track clicks only (press/release)
    drag, // Track clicks and drags
    move, // Track all mouse movement
};

/// Enable mouse tracking
pub fn enableTracking(writer: anytype, mode: TrackingMode) !void {
    switch (mode) {
        .off => try writer.writeAll("\x1b[?1000l\x1b[?1002l\x1b[?1003l"),
        .click => try writer.writeAll("\x1b[?1000h\x1b[?1006h"),
        .drag => try writer.writeAll("\x1b[?1002h\x1b[?1006h"),
        .move => try writer.writeAll("\x1b[?1003h\x1b[?1006h"),
    }
}

/// Disable mouse tracking
pub fn disableTracking(writer: anytype) !void {
    try enableTracking(writer, .off);
}

/// Parse SGR (1006) mouse event from escape sequence
/// Format: CSI < Cb ; Cx ; Cy (M or m)
/// M = press, m = release
/// Returns null if not a valid mouse sequence
pub fn parseSGR(seq: []const u8) ?MouseEvent {
    if (seq.len < 6) return null; // Minimum: "<0;0;0M"
    if (seq[0] != '<') return null;

    // Find semicolons
    var semicolon1: ?usize = null;
    var semicolon2: ?usize = null;
    for (seq[1..], 0..) |c, i| {
        if (c == ';') {
            if (semicolon1 == null) {
                semicolon1 = i + 1;
            } else if (semicolon2 == null) {
                semicolon2 = i + 1;
                break;
            }
        }
    }

    if (semicolon1 == null or semicolon2 == null) return null;

    const s1 = semicolon1.?;
    const s2 = semicolon2.?;

    // Parse button code
    const button_code = std.fmt.parseInt(u8, seq[1..s1], 10) catch return null;

    // Parse x coordinate
    const x = std.fmt.parseInt(u16, seq[s1 + 1 .. s2], 10) catch return null;

    // Parse y coordinate and terminator
    var y_end = s2 + 1;
    while (y_end < seq.len) : (y_end += 1) {
        const c = seq[y_end];
        if (c == 'M' or c == 'm') break;
    }
    if (y_end >= seq.len) return null;

    const y = std.fmt.parseInt(u16, seq[s2 + 1 .. y_end], 10) catch return null;
    const terminator = seq[y_end];

    // Decode button and modifiers
    const btn = button_code & 0x03;
    const shift = (button_code & 0x04) != 0;
    const alt = (button_code & 0x08) != 0;
    const ctrl = (button_code & 0x10) != 0;

    const button: MouseButton = switch (btn) {
        0 => .left,
        1 => .middle,
        2 => .right,
        3 => .none,
        else => .none,
    };

    // Detect scroll
    if (button_code >= 64 and button_code <= 65) {
        return MouseEvent{
            .event_type = if (button_code == 64) .scroll_up else .scroll_down,
            .button = .none,
            .x = if (x > 0) x - 1 else 0, // Convert 1-based to 0-based
            .y = if (y > 0) y - 1 else 0,
            .modifiers = .{ .shift = shift, .alt = alt, .ctrl = ctrl },
        };
    }

    // Detect drag (button 32-35)
    const is_drag = button_code >= 32 and button_code <= 35;

    const event_type: MouseEventType = if (is_drag)
        .drag
    else if (terminator == 'M')
        .press
    else
        .release;

    return MouseEvent{
        .event_type = event_type,
        .button = button,
        .x = if (x > 0) x - 1 else 0, // Convert 1-based to 0-based
        .y = if (y > 0) y - 1 else 0,
        .modifiers = .{ .shift = shift, .alt = alt, .ctrl = ctrl },
    };
}

/// Double-click detector
pub const DoubleClickDetector = struct {
    last_press_time: i64 = 0,
    last_press_x: u16 = 0,
    last_press_y: u16 = 0,
    last_press_button: MouseButton = .none,
    threshold_ms: i64 = 500, // Max time between clicks
    threshold_distance: u16 = 2, // Max pixel distance

    /// Check if this event is a double-click
    /// Call this on every press event
    pub fn checkDoubleClick(self: *DoubleClickDetector, event: MouseEvent, current_time_ms: i64) bool {
        if (event.event_type != .press) return false;

        const time_delta = current_time_ms - self.last_press_time;
        const same_button = event.button == self.last_press_button;

        const dx = if (event.x > self.last_press_x)
            event.x - self.last_press_x
        else
            self.last_press_x - event.x;

        const dy = if (event.y > self.last_press_y)
            event.y - self.last_press_y
        else
            self.last_press_y - event.y;

        const is_double_click = same_button and
            time_delta <= self.threshold_ms and
            dx <= self.threshold_distance and
            dy <= self.threshold_distance;

        // Update state
        self.last_press_time = current_time_ms;
        self.last_press_x = event.x;
        self.last_press_y = event.y;
        self.last_press_button = event.button;

        return is_double_click;
    }

    /// Reset detector state
    pub fn reset(self: *DoubleClickDetector) void {
        self.last_press_time = 0;
    }
};

// ============================================================================
// Tests
// ============================================================================

test "MouseEvent basic" {
    const event = MouseEvent{
        .event_type = .press,
        .button = .left,
        .x = 10,
        .y = 5,
    };
    try std.testing.expectEqual(MouseEventType.press, event.event_type);
    try std.testing.expectEqual(MouseButton.left, event.button);
    try std.testing.expectEqual(@as(u16, 10), event.x);
    try std.testing.expectEqual(@as(u16, 5), event.y);
}

test "parseSGR left click press" {
    const seq = "<0;15;8M";
    const event = parseSGR(seq).?;
    try std.testing.expectEqual(MouseEventType.press, event.event_type);
    try std.testing.expectEqual(MouseButton.left, event.button);
    try std.testing.expectEqual(@as(u16, 14), event.x); // 1-based → 0-based
    try std.testing.expectEqual(@as(u16, 7), event.y);
}

test "parseSGR left click release" {
    const seq = "<0;15;8m";
    const event = parseSGR(seq).?;
    try std.testing.expectEqual(MouseEventType.release, event.event_type);
    try std.testing.expectEqual(MouseButton.left, event.button);
}

test "parseSGR middle button" {
    const seq = "<1;20;10M";
    const event = parseSGR(seq).?;
    try std.testing.expectEqual(MouseButton.middle, event.button);
}

test "parseSGR right button" {
    const seq = "<2;30;15M";
    const event = parseSGR(seq).?;
    try std.testing.expectEqual(MouseButton.right, event.button);
}

test "parseSGR scroll up" {
    const seq = "<64;10;5M";
    const event = parseSGR(seq).?;
    try std.testing.expectEqual(MouseEventType.scroll_up, event.event_type);
    try std.testing.expectEqual(MouseButton.none, event.button);
}

test "parseSGR scroll down" {
    const seq = "<65;10;5M";
    const event = parseSGR(seq).?;
    try std.testing.expectEqual(MouseEventType.scroll_down, event.event_type);
}

test "parseSGR drag" {
    const seq = "<32;25;12M"; // Left button drag (32 = 0 + 32)
    const event = parseSGR(seq).?;
    try std.testing.expectEqual(MouseEventType.drag, event.event_type);
    try std.testing.expectEqual(MouseButton.left, event.button);
}

test "parseSGR with modifiers" {
    const seq = "<4;10;5M"; // Shift modifier (4 = 0 + 4)
    const event = parseSGR(seq).?;
    try std.testing.expect(event.modifiers.shift);
    try std.testing.expect(!event.modifiers.ctrl);
    try std.testing.expect(!event.modifiers.alt);
}

test "parseSGR invalid sequence" {
    try std.testing.expectEqual(@as(?MouseEvent, null), parseSGR(""));
    try std.testing.expectEqual(@as(?MouseEvent, null), parseSGR("<"));
    try std.testing.expectEqual(@as(?MouseEvent, null), parseSGR("<0"));
    try std.testing.expectEqual(@as(?MouseEvent, null), parseSGR("invalid"));
    try std.testing.expectEqual(@as(?MouseEvent, null), parseSGR("<abc;def;ghiM"));
}

test "DoubleClickDetector detects double click" {
    var detector = DoubleClickDetector{};

    const event1 = MouseEvent{
        .event_type = .press,
        .button = .left,
        .x = 10,
        .y = 5,
    };

    const event2 = MouseEvent{
        .event_type = .press,
        .button = .left,
        .x = 10,
        .y = 5,
    };

    // First click
    const is_double1 = detector.checkDoubleClick(event1, 1000);
    try std.testing.expect(!is_double1);

    // Second click within threshold
    const is_double2 = detector.checkDoubleClick(event2, 1200);
    try std.testing.expect(is_double2);
}

test "DoubleClickDetector rejects slow clicks" {
    var detector = DoubleClickDetector{};

    const event1 = MouseEvent{
        .event_type = .press,
        .button = .left,
        .x = 10,
        .y = 5,
    };

    const event2 = MouseEvent{
        .event_type = .press,
        .button = .left,
        .x = 10,
        .y = 5,
    };

    const is_double1 = detector.checkDoubleClick(event1, 1000);
    try std.testing.expect(!is_double1);

    // Too much time elapsed
    const is_double2 = detector.checkDoubleClick(event2, 2000);
    try std.testing.expect(!is_double2);
}

test "DoubleClickDetector rejects distant clicks" {
    var detector = DoubleClickDetector{};

    const event1 = MouseEvent{
        .event_type = .press,
        .button = .left,
        .x = 10,
        .y = 5,
    };

    const event2 = MouseEvent{
        .event_type = .press,
        .button = .left,
        .x = 20, // Far away
        .y = 5,
    };

    const is_double1 = detector.checkDoubleClick(event1, 1000);
    try std.testing.expect(!is_double1);

    const is_double2 = detector.checkDoubleClick(event2, 1100);
    try std.testing.expect(!is_double2);
}

test "DoubleClickDetector rejects different buttons" {
    var detector = DoubleClickDetector{};

    const event1 = MouseEvent{
        .event_type = .press,
        .button = .left,
        .x = 10,
        .y = 5,
    };

    const event2 = MouseEvent{
        .event_type = .press,
        .button = .right, // Different button
        .x = 10,
        .y = 5,
    };

    const is_double1 = detector.checkDoubleClick(event1, 1000);
    try std.testing.expect(!is_double1);

    const is_double2 = detector.checkDoubleClick(event2, 1100);
    try std.testing.expect(!is_double2);
}

test "DoubleClickDetector ignores non-press events" {
    var detector = DoubleClickDetector{};

    const event = MouseEvent{
        .event_type = .release,
        .button = .left,
        .x = 10,
        .y = 5,
    };

    const is_double = detector.checkDoubleClick(event, 1000);
    try std.testing.expect(!is_double);
}

test "DoubleClickDetector reset" {
    var detector = DoubleClickDetector{};

    const event = MouseEvent{
        .event_type = .press,
        .button = .left,
        .x = 10,
        .y = 5,
    };

    _ = detector.checkDoubleClick(event, 1000);
    try std.testing.expect(detector.last_press_time != 0);

    detector.reset();
    try std.testing.expectEqual(@as(i64, 0), detector.last_press_time);
}

test "enableTracking" {
    var buf: [128]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);
    const writer = fbs.writer();

    try enableTracking(writer, .click);
    const written = fbs.getWritten();
    try std.testing.expect(std.mem.indexOf(u8, written, "\x1b[?1000h") != null);
    try std.testing.expect(std.mem.indexOf(u8, written, "\x1b[?1006h") != null);
}

test "disableTracking" {
    var buf: [128]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);
    const writer = fbs.writer();

    try disableTracking(writer);
    const written = fbs.getWritten();
    try std.testing.expect(std.mem.indexOf(u8, written, "\x1b[?1000l") != null);
}
