//! Test Utilities for TUI Integration Testing
//!
//! Provides MockTerminal and EventSimulator for writing integration tests
//! without requiring a real TTY. Enables snapshot testing and event replay.

const std = @import("std");
const Allocator = std.mem.Allocator;

const tui_mod = @import("tui.zig");
const buffer_mod = @import("buffer.zig");
const Buffer = buffer_mod.Buffer;
const Rect = @import("layout.zig").Rect;
const Style = @import("style.zig").Style;

/// MockTerminal provides a fake terminal for testing without TTY
pub const MockTerminal = struct {
    width: u16,
    height: u16,
    current: Buffer,
    previous: Buffer,
    allocator: Allocator,
    events: std.ArrayListUnmanaged(tui_mod.Event),
    draw_calls: usize,

    /// Initialize mock terminal with given dimensions
    pub fn init(allocator: Allocator, width: u16, height: u16) !MockTerminal {
        var current = try Buffer.init(allocator, width, height);
        errdefer current.deinit();
        var previous = try Buffer.init(allocator, width, height);
        errdefer previous.deinit();

        return MockTerminal{
            .width = width,
            .height = height,
            .current = current,
            .previous = previous,
            .allocator = allocator,
            .events = .{},
            .draw_calls = 0,
        };
    }

    /// Clean up
    pub fn deinit(self: *MockTerminal) void {
        self.current.deinit();
        self.previous.deinit();
        self.events.deinit(self.allocator);
    }

    /// Get terminal size as Rect
    pub fn size(self: MockTerminal) Rect {
        return Rect.new(0, 0, self.width, self.height);
    }

    /// Clear terminal
    pub fn clear(self: *MockTerminal) void {
        self.current.clear();
    }

    /// Push an event to the queue
    pub fn pushEvent(self: *MockTerminal, event: tui_mod.Event) !void {
        try self.events.append(self.allocator, event);
    }

    /// Pop next event from queue (returns null if empty)
    pub fn pollEvent(self: *MockTerminal) ?tui_mod.Event {
        if (self.events.items.len == 0) return null;
        return self.events.orderedRemove(0);
    }

    /// Simulate a draw call
    pub fn draw(self: *MockTerminal) void {
        self.draw_calls += 1;
        // Swap buffers
        const temp = self.current;
        self.current = self.previous;
        self.previous = temp;
    }

    /// Get buffer content as string for snapshot testing
    pub fn getSnapshot(self: *MockTerminal, allocator: Allocator) ![]const u8 {
        var result = try std.ArrayList(u8).initCapacity(allocator, 0);
        errdefer result.deinit(allocator);

        var y: u16 = 0;
        while (y < self.height) : (y += 1) {
            var x: u16 = 0;
            while (x < self.width) : (x += 1) {
                const cell = self.current.getConst(x, y) orelse continue;
                var buf: [4]u8 = undefined;
                const len = try std.unicode.utf8Encode(cell.char, &buf);
                try result.appendSlice(allocator, buf[0..len]);
            }
            if (y < self.height - 1) {
                try result.append(allocator, '\n');
            }
        }

        return result.toOwnedSlice(allocator);
    }

    /// Assert buffer matches expected snapshot
    pub fn assertSnapshot(self: *MockTerminal, expected: []const u8) !void {
        const actual = try self.getSnapshot(self.allocator);
        defer self.allocator.free(actual);

        if (!std.mem.eql(u8, actual, expected)) {
            std.debug.print("\n=== SNAPSHOT MISMATCH ===\n", .{});
            std.debug.print("Expected:\n{s}\n", .{expected});
            std.debug.print("Actual:\n{s}\n", .{actual});
            return error.SnapshotMismatch;
        }
    }

    /// Get character at position
    pub fn getChar(self: *MockTerminal, x: u16, y: u16) ?u21 {
        const cell = self.current.getConst(x, y) orelse return null;
        return cell.char;
    }

    /// Get style at position
    pub fn getStyle(self: *MockTerminal, x: u16, y: u16) ?Style {
        const cell = self.current.getConst(x, y) orelse return null;
        return cell.style;
    }

    /// Resize the mock terminal
    pub fn resize(self: *MockTerminal, width: u16, height: u16) !void {
        self.current.deinit();
        self.previous.deinit();

        self.current = try Buffer.init(self.allocator, width, height);
        self.previous = try Buffer.init(self.allocator, width, height);
        self.width = width;
        self.height = height;

        try self.pushEvent(.{ .resize = .{ .width = width, .height = height } });
    }
};

/// EventSimulator generates and queues terminal events
pub const EventSimulator = struct {
    terminal: *MockTerminal,

    /// Create simulator for a mock terminal
    pub fn init(terminal: *MockTerminal) EventSimulator {
        return .{ .terminal = terminal };
    }

    /// Simulate typing a string
    pub fn typeString(self: *EventSimulator, str: []const u8) !void {
        for (str) |char| {
            try self.terminal.pushEvent(.{ .key = .{ .code = .{ .char = char } } });
        }
    }

    /// Simulate pressing Enter key
    pub fn pressEnter(self: *EventSimulator) !void {
        try self.terminal.pushEvent(.{ .key = .{ .code = .enter } });
    }

    /// Simulate pressing Backspace key
    pub fn pressBackspace(self: *EventSimulator) !void {
        try self.terminal.pushEvent(.{ .key = .{ .code = .backspace } });
    }

    /// Simulate pressing Tab key
    pub fn pressTab(self: *EventSimulator) !void {
        try self.terminal.pushEvent(.{ .key = .{ .code = .tab } });
    }

    /// Simulate pressing Escape key
    pub fn pressEscape(self: *EventSimulator) !void {
        try self.terminal.pushEvent(.{ .key = .{ .code = .esc } });
    }

    /// Simulate pressing arrow keys
    pub fn pressUp(self: *EventSimulator) !void {
        try self.terminal.pushEvent(.{ .key = .{ .code = .up } });
    }

    pub fn pressDown(self: *EventSimulator) !void {
        try self.terminal.pushEvent(.{ .key = .{ .code = .down } });
    }

    pub fn pressLeft(self: *EventSimulator) !void {
        try self.terminal.pushEvent(.{ .key = .{ .code = .left } });
    }

    pub fn pressRight(self: *EventSimulator) !void {
        try self.terminal.pushEvent(.{ .key = .{ .code = .right } });
    }

    /// Simulate pressing Home key
    pub fn pressHome(self: *EventSimulator) !void {
        try self.terminal.pushEvent(.{ .key = .{ .code = .home } });
    }

    /// Simulate pressing End key
    pub fn pressEnd(self: *EventSimulator) !void {
        try self.terminal.pushEvent(.{ .key = .{ .code = .end } });
    }

    /// Simulate pressing PageUp key
    pub fn pressPageUp(self: *EventSimulator) !void {
        try self.terminal.pushEvent(.{ .key = .{ .code = .page_up } });
    }

    /// Simulate pressing PageDown key
    pub fn pressPageDown(self: *EventSimulator) !void {
        try self.terminal.pushEvent(.{ .key = .{ .code = .page_down } });
    }

    /// Simulate pressing Delete key
    pub fn pressDelete(self: *EventSimulator) !void {
        try self.terminal.pushEvent(.{ .key = .{ .code = .delete } });
    }

    /// Simulate pressing Insert key
    pub fn pressInsert(self: *EventSimulator) !void {
        try self.terminal.pushEvent(.{ .key = .{ .code = .insert } });
    }

    /// Simulate pressing function key (F1-F12)
    pub fn pressFn(self: *EventSimulator, n: u8) !void {
        try self.terminal.pushEvent(.{ .key = .{ .code = .{ .f = n } } });
    }

    /// Simulate Ctrl+key combination
    pub fn pressCtrl(self: *EventSimulator, char: u8) !void {
        try self.terminal.pushEvent(.{
            .key = .{
                .code = .{ .char = char },
                .modifiers = .{ .ctrl = true },
            },
        });
    }

    /// Simulate Alt+key combination
    pub fn pressAlt(self: *EventSimulator, char: u8) !void {
        try self.terminal.pushEvent(.{
            .key = .{
                .code = .{ .char = char },
                .modifiers = .{ .alt = true },
            },
        });
    }

    /// Simulate Shift+key combination
    pub fn pressShift(self: *EventSimulator, char: u8) !void {
        try self.terminal.pushEvent(.{
            .key = .{
                .code = .{ .char = char },
                .modifiers = .{ .shift = true },
            },
        });
    }

    /// Simulate terminal resize
    pub fn resize(self: *EventSimulator, width: u16, height: u16) !void {
        try self.terminal.resize(width, height);
    }

    /// Simulate a custom key event
    pub fn pushKey(self: *EventSimulator, code: tui_mod.KeyCode, modifiers: tui_mod.Modifiers) !void {
        try self.terminal.pushEvent(.{ .key = .{ .code = code, .modifiers = modifiers } });
    }
};

// ============================================================================
// Tests
// ============================================================================

test "MockTerminal init and size" {
    var term = try MockTerminal.init(std.testing.allocator, 80, 24);
    defer term.deinit();

    const rect = term.size();
    try std.testing.expectEqual(@as(u16, 80), rect.width);
    try std.testing.expectEqual(@as(u16, 24), rect.height);
}

test "MockTerminal clear" {
    var term = try MockTerminal.init(std.testing.allocator, 20, 10);
    defer term.deinit();

    term.current.setChar(5, 5, 'X', .{});
    term.clear();

    const cell = term.current.getConst(5, 5).?;
    try std.testing.expectEqual(' ', cell.char);
}

test "MockTerminal event queue" {
    var term = try MockTerminal.init(std.testing.allocator, 80, 24);
    defer term.deinit();

    try term.pushEvent(.{ .key = .{ .code = .{ .char = 'a' } } });
    try term.pushEvent(.{ .key = .{ .code = .enter } });

    const event1 = term.pollEvent().?;
    try std.testing.expectEqual(tui_mod.KeyCode{ .char = 'a' }, event1.key.code);

    const event2 = term.pollEvent().?;
    try std.testing.expectEqual(tui_mod.KeyCode.enter, event2.key.code);

    const event3 = term.pollEvent();
    try std.testing.expect(event3 == null);
}

test "MockTerminal draw calls" {
    var term = try MockTerminal.init(std.testing.allocator, 80, 24);
    defer term.deinit();

    try std.testing.expectEqual(@as(usize, 0), term.draw_calls);
    term.draw();
    try std.testing.expectEqual(@as(usize, 1), term.draw_calls);
}

test "MockTerminal snapshot" {
    var term = try MockTerminal.init(std.testing.allocator, 5, 2);
    defer term.deinit();

    term.current.setString(0, 0, "Hello", .{});
    term.current.setString(0, 1, "World", .{});

    const snapshot = try term.getSnapshot(std.testing.allocator);
    defer std.testing.allocator.free(snapshot);

    try std.testing.expectEqualStrings("Hello\nWorld", snapshot);
}

test "MockTerminal assertSnapshot success" {
    var term = try MockTerminal.init(std.testing.allocator, 4, 2);
    defer term.deinit();

    term.current.setString(0, 0, "Test", .{});
    term.current.setString(0, 1, "    ", .{});

    try term.assertSnapshot("Test\n    ");
}

test "MockTerminal assertSnapshot failure" {
    var term = try MockTerminal.init(std.testing.allocator, 4, 1);
    defer term.deinit();

    term.current.setString(0, 0, "Fail", .{});

    const result = term.assertSnapshot("Pass");
    try std.testing.expectError(error.SnapshotMismatch, result);
}

test "MockTerminal getChar and getStyle" {
    var term = try MockTerminal.init(std.testing.allocator, 10, 5);
    defer term.deinit();

    const style = Style{ .fg = .red, .bold = true };
    term.current.setChar(3, 2, 'X', style);

    const char = term.getChar(3, 2).?;
    try std.testing.expectEqual('X', char);

    const retrieved_style = term.getStyle(3, 2).?;
    try std.testing.expectEqual(style.fg, retrieved_style.fg);
    try std.testing.expect(retrieved_style.bold);
}

test "MockTerminal resize" {
    var term = try MockTerminal.init(std.testing.allocator, 80, 24);
    defer term.deinit();

    try term.resize(100, 30);

    try std.testing.expectEqual(@as(u16, 100), term.width);
    try std.testing.expectEqual(@as(u16, 30), term.height);

    const event = term.pollEvent().?;
    try std.testing.expectEqual(@as(u16, 100), event.resize.width);
    try std.testing.expectEqual(@as(u16, 30), event.resize.height);
}

test "EventSimulator typeString" {
    var term = try MockTerminal.init(std.testing.allocator, 80, 24);
    defer term.deinit();

    var sim = EventSimulator.init(&term);
    try sim.typeString("abc");

    try std.testing.expectEqual(tui_mod.KeyCode{ .char = 'a' }, term.pollEvent().?.key.code);
    try std.testing.expectEqual(tui_mod.KeyCode{ .char = 'b' }, term.pollEvent().?.key.code);
    try std.testing.expectEqual(tui_mod.KeyCode{ .char = 'c' }, term.pollEvent().?.key.code);
}

test "EventSimulator navigation keys" {
    var term = try MockTerminal.init(std.testing.allocator, 80, 24);
    defer term.deinit();

    var sim = EventSimulator.init(&term);
    try sim.pressEnter();
    try sim.pressBackspace();
    try sim.pressTab();
    try sim.pressEscape();

    try std.testing.expectEqual(tui_mod.KeyCode.enter, term.pollEvent().?.key.code);
    try std.testing.expectEqual(tui_mod.KeyCode.backspace, term.pollEvent().?.key.code);
    try std.testing.expectEqual(tui_mod.KeyCode.tab, term.pollEvent().?.key.code);
    try std.testing.expectEqual(tui_mod.KeyCode.esc, term.pollEvent().?.key.code);
}

test "EventSimulator arrow keys" {
    var term = try MockTerminal.init(std.testing.allocator, 80, 24);
    defer term.deinit();

    var sim = EventSimulator.init(&term);
    try sim.pressUp();
    try sim.pressDown();
    try sim.pressLeft();
    try sim.pressRight();

    try std.testing.expectEqual(tui_mod.KeyCode.up, term.pollEvent().?.key.code);
    try std.testing.expectEqual(tui_mod.KeyCode.down, term.pollEvent().?.key.code);
    try std.testing.expectEqual(tui_mod.KeyCode.left, term.pollEvent().?.key.code);
    try std.testing.expectEqual(tui_mod.KeyCode.right, term.pollEvent().?.key.code);
}

test "EventSimulator home and end keys" {
    var term = try MockTerminal.init(std.testing.allocator, 80, 24);
    defer term.deinit();

    var sim = EventSimulator.init(&term);
    try sim.pressHome();
    try sim.pressEnd();

    try std.testing.expectEqual(tui_mod.KeyCode.home, term.pollEvent().?.key.code);
    try std.testing.expectEqual(tui_mod.KeyCode.end, term.pollEvent().?.key.code);
}

test "EventSimulator page keys" {
    var term = try MockTerminal.init(std.testing.allocator, 80, 24);
    defer term.deinit();

    var sim = EventSimulator.init(&term);
    try sim.pressPageUp();
    try sim.pressPageDown();

    try std.testing.expectEqual(tui_mod.KeyCode.page_up, term.pollEvent().?.key.code);
    try std.testing.expectEqual(tui_mod.KeyCode.page_down, term.pollEvent().?.key.code);
}

test "EventSimulator delete and insert keys" {
    var term = try MockTerminal.init(std.testing.allocator, 80, 24);
    defer term.deinit();

    var sim = EventSimulator.init(&term);
    try sim.pressDelete();
    try sim.pressInsert();

    try std.testing.expectEqual(tui_mod.KeyCode.delete, term.pollEvent().?.key.code);
    try std.testing.expectEqual(tui_mod.KeyCode.insert, term.pollEvent().?.key.code);
}

test "EventSimulator function keys" {
    var term = try MockTerminal.init(std.testing.allocator, 80, 24);
    defer term.deinit();

    var sim = EventSimulator.init(&term);
    try sim.pressFn(1);
    try sim.pressFn(12);

    const f1 = term.pollEvent().?;
    try std.testing.expectEqual(@as(u8, 1), f1.key.code.f);

    const f12 = term.pollEvent().?;
    try std.testing.expectEqual(@as(u8, 12), f12.key.code.f);
}

test "EventSimulator modifier keys" {
    var term = try MockTerminal.init(std.testing.allocator, 80, 24);
    defer term.deinit();

    var sim = EventSimulator.init(&term);
    try sim.pressCtrl('c');
    try sim.pressAlt('x');
    try sim.pressShift('a');

    const ctrl_c = term.pollEvent().?;
    try std.testing.expect(ctrl_c.key.modifiers.ctrl);
    try std.testing.expectEqual(@as(u8, 'c'), ctrl_c.key.code.char);

    const alt_x = term.pollEvent().?;
    try std.testing.expect(alt_x.key.modifiers.alt);
    try std.testing.expectEqual(@as(u8, 'x'), alt_x.key.code.char);

    const shift_a = term.pollEvent().?;
    try std.testing.expect(shift_a.key.modifiers.shift);
    try std.testing.expectEqual(@as(u8, 'a'), shift_a.key.code.char);
}

test "EventSimulator resize" {
    var term = try MockTerminal.init(std.testing.allocator, 80, 24);
    defer term.deinit();

    var sim = EventSimulator.init(&term);
    try sim.resize(120, 40);

    try std.testing.expectEqual(@as(u16, 120), term.width);
    try std.testing.expectEqual(@as(u16, 40), term.height);

    const event = term.pollEvent().?;
    try std.testing.expectEqual(@as(u16, 120), event.resize.width);
    try std.testing.expectEqual(@as(u16, 40), event.resize.height);
}

test "EventSimulator pushKey custom" {
    var term = try MockTerminal.init(std.testing.allocator, 80, 24);
    defer term.deinit();

    var sim = EventSimulator.init(&term);
    try sim.pushKey(.{ .char = 'q' }, .{ .ctrl = true, .alt = true });

    const event = term.pollEvent().?;
    try std.testing.expectEqual(@as(u8, 'q'), event.key.code.char);
    try std.testing.expect(event.key.modifiers.ctrl);
    try std.testing.expect(event.key.modifiers.alt);
    try std.testing.expect(!event.key.modifiers.shift);
}
