//! MockTerminal — Programmable terminal implementation for testing TUI applications
//!
//! Provides a fake terminal that can:
//! - Queue and poll input events (keyboard, mouse, resize)
//! - Capture output written to the terminal
//! - Query terminal state (size, cursor position, output)
//! - Work with sailor.tui.Terminal interface
//!
//! This is a lightweight alternative to src/tui/test_utils.zig MockTerminal,
//! designed specifically for testing terminal-based applications without
//! requiring a real TTY.

const std = @import("std");
const Allocator = std.mem.Allocator;

// Import TUI types for compatibility
const tui = @import("../tui/tui.zig");
const Event = tui.Event;
const KeyEvent = tui.KeyEvent;
const KeyCode = tui.KeyCode;

/// Terminal size
pub const Size = struct {
    width: u16,
    height: u16,
};

/// MockTerminal provides a programmable terminal for testing
pub const MockTerminal = struct {
    size: Size,
    output: std.ArrayList(u8),
    event_queue: std.ArrayList(Event),
    allocator: Allocator,

    /// Initialize mock terminal with given dimensions
    pub fn init(allocator: Allocator, term_size: Size) MockTerminal {
        return MockTerminal{
            .size = term_size,
            .output = std.ArrayList(u8){},
            .event_queue = std.ArrayList(Event){},
            .allocator = allocator,
        };
    }

    /// Clean up resources
    pub fn deinit(self: *MockTerminal) void {
        self.output.deinit(self.allocator);
        self.event_queue.deinit(self.allocator);
    }

    /// Queue an event to be polled later
    pub fn queueEvent(self: *MockTerminal, event: Event) !void {
        try self.event_queue.append(self.allocator, event);
    }

    /// Convenience method to queue a key press event
    pub fn queueKey(self: *MockTerminal, code: KeyCode) !void {
        try self.queueEvent(.{ .key = .{ .code = code } });
    }

    /// Convenience method to queue a resize event
    pub fn queueResize(self: *MockTerminal, new_size: Size) !void {
        try self.queueEvent(.{ .resize = .{ .width = new_size.width, .height = new_size.height } });
    }

    /// Get all output written to the terminal
    pub fn getOutput(self: *const MockTerminal) []const u8 {
        return self.output.items;
    }

    /// Clear all captured output
    pub fn clearOutput(self: *MockTerminal) void {
        self.output.clearRetainingCapacity();
    }

    /// Get current terminal size
    pub fn getSize(self: *const MockTerminal) Size {
        return self.size;
    }

    /// Resize the terminal (updates size and queues resize event)
    pub fn resize(self: *MockTerminal, new_size: Size) !void {
        self.size = new_size;
        try self.queueResize(new_size);
    }

    /// Poll the next event from the queue (returns null if empty)
    pub fn pollEvent(self: *MockTerminal) ?Event {
        if (self.event_queue.items.len == 0) {
            return null;
        }
        return self.event_queue.orderedRemove(0);
    }

    /// Write output to the terminal (for capturing)
    pub fn write(self: *MockTerminal, data: []const u8) !void {
        try self.output.appendSlice(self.allocator, data);
    }

    /// Get a writer for output capture
    pub fn writer(self: *MockTerminal) std.ArrayList(u8).Writer {
        return self.output.writer(self.allocator);
    }
};

// ============================================================================
// Tests
// ============================================================================

test "MockTerminal init and deinit" {
    const allocator = std.testing.allocator;
    var term = MockTerminal.init(allocator, .{ .width = 80, .height = 24 });
    defer term.deinit();

    // Should initialize with given size
    try std.testing.expectEqual(@as(u16, 80), term.size.width);
    try std.testing.expectEqual(@as(u16, 24), term.size.height);

    // Output should be empty initially
    try std.testing.expectEqual(@as(usize, 0), term.output.items.len);

    // Event queue should be empty
    try std.testing.expectEqual(@as(usize, 0), term.event_queue.items.len);
}

test "MockTerminal queueEvent and pollEvent FIFO" {
    const allocator = std.testing.allocator;
    var term = MockTerminal.init(allocator, .{ .width = 80, .height = 24 });
    defer term.deinit();

    // Queue three events
    try term.queueEvent(.{ .key = .{ .code = .{ .char = 'a' } } });
    try term.queueEvent(.{ .key = .{ .code = .{ .char = 'b' } } });
    try term.queueEvent(.{ .key = .{ .code = .{ .char = 'c' } } });

    // Poll should return in FIFO order
    const ev1 = term.pollEvent().?;
    try std.testing.expectEqual('a', ev1.key.code.char);

    const ev2 = term.pollEvent().?;
    try std.testing.expectEqual('b', ev2.key.code.char);

    const ev3 = term.pollEvent().?;
    try std.testing.expectEqual('c', ev3.key.code.char);

    // Queue should now be empty
    try std.testing.expect(term.pollEvent() == null);
}

test "MockTerminal queueKey convenience" {
    const allocator = std.testing.allocator;
    var term = MockTerminal.init(allocator, .{ .width = 80, .height = 24 });
    defer term.deinit();

    // queueKey should be shorthand for queueEvent with key
    try term.queueKey(.{ .char = 'x' });
    try term.queueKey(.enter);
    try term.queueKey(.esc);

    const ev1 = term.pollEvent().?;
    try std.testing.expectEqual('x', ev1.key.code.char);

    const ev2 = term.pollEvent().?;
    try std.testing.expectEqual(KeyCode.enter, ev2.key.code);

    const ev3 = term.pollEvent().?;
    try std.testing.expectEqual(KeyCode.esc, ev3.key.code);
}

test "MockTerminal queueResize" {
    const allocator = std.testing.allocator;
    var term = MockTerminal.init(allocator, .{ .width = 80, .height = 24 });
    defer term.deinit();

    // Queue a resize event
    try term.queueResize(.{ .width = 100, .height = 30 });

    const ev = term.pollEvent().?;
    try std.testing.expectEqual(@as(u16, 100), ev.resize.width);
    try std.testing.expectEqual(@as(u16, 30), ev.resize.height);
}

test "MockTerminal getOutput captures written data" {
    const allocator = std.testing.allocator;
    var term = MockTerminal.init(allocator, .{ .width = 80, .height = 24 });
    defer term.deinit();

    // Write some data
    try term.write("Hello, ");
    try term.write("World!");

    // Should capture all written output
    const output = term.getOutput();
    try std.testing.expectEqualStrings("Hello, World!", output);
}

test "MockTerminal clearOutput resets captured data" {
    const allocator = std.testing.allocator;
    var term = MockTerminal.init(allocator, .{ .width = 80, .height = 24 });
    defer term.deinit();

    try term.write("Some data");
    try std.testing.expectEqual(@as(usize, 9), term.getOutput().len);

    term.clearOutput();
    try std.testing.expectEqual(@as(usize, 0), term.getOutput().len);
}

test "MockTerminal resize updates size" {
    const allocator = std.testing.allocator;
    var term = MockTerminal.init(allocator, .{ .width = 80, .height = 24 });
    defer term.deinit();

    // Resize should update the size
    try term.resize(.{ .width = 120, .height = 40 });

    const new_size = term.getSize();
    try std.testing.expectEqual(@as(u16, 120), new_size.width);
    try std.testing.expectEqual(@as(u16, 40), new_size.height);
}

test "MockTerminal resize queues resize event" {
    const allocator = std.testing.allocator;
    var term = MockTerminal.init(allocator, .{ .width = 80, .height = 24 });
    defer term.deinit();

    // Resize should also queue a resize event
    try term.resize(.{ .width = 100, .height = 30 });

    const ev = term.pollEvent().?;
    try std.testing.expectEqual(@as(u16, 100), ev.resize.width);
    try std.testing.expectEqual(@as(u16, 30), ev.resize.height);
}

test "MockTerminal multiple events maintain order" {
    const allocator = std.testing.allocator;
    var term = MockTerminal.init(allocator, .{ .width = 80, .height = 24 });
    defer term.deinit();

    // Queue mixed event types
    try term.queueKey(.{ .char = 'a' });
    try term.queueResize(.{ .width = 90, .height = 25 });
    try term.queueKey(.{ .char = 'b' });
    try term.queueKey(.enter);

    // Should maintain FIFO order
    const ev1 = term.pollEvent().?;
    try std.testing.expectEqual('a', ev1.key.code.char);

    const ev2 = term.pollEvent().?;
    try std.testing.expectEqual(@as(u16, 90), ev2.resize.width);

    const ev3 = term.pollEvent().?;
    try std.testing.expectEqual('b', ev3.key.code.char);

    const ev4 = term.pollEvent().?;
    try std.testing.expectEqual(KeyCode.enter, ev4.key.code);
}

test "MockTerminal empty queue returns null" {
    const allocator = std.testing.allocator;
    var term = MockTerminal.init(allocator, .{ .width = 80, .height = 24 });
    defer term.deinit();

    // Empty queue should return null
    try std.testing.expect(term.pollEvent() == null);

    // After queueing and polling all events, should be null again
    try term.queueKey(.{ .char = 'x' });
    _ = term.pollEvent();
    try std.testing.expect(term.pollEvent() == null);
}

test "MockTerminal output accumulation" {
    const allocator = std.testing.allocator;
    var term = MockTerminal.init(allocator, .{ .width = 80, .height = 24 });
    defer term.deinit();

    // Multiple writes should accumulate
    try term.write("Line 1\n");
    try term.write("Line 2\n");
    try term.write("Line 3");

    const output = term.getOutput();
    try std.testing.expectEqualStrings("Line 1\nLine 2\nLine 3", output);
}

test "MockTerminal writer interface" {
    const allocator = std.testing.allocator;
    var term = MockTerminal.init(allocator, .{ .width = 80, .height = 24 });
    defer term.deinit();

    // Should provide a writer interface
    const w = term.writer();
    try w.writeAll("Hello from writer");

    const output = term.getOutput();
    try std.testing.expectEqualStrings("Hello from writer", output);
}

test "MockTerminal getSize returns current size" {
    const allocator = std.testing.allocator;
    var term = MockTerminal.init(allocator, .{ .width = 60, .height = 20 });
    defer term.deinit();

    const size = term.getSize();
    try std.testing.expectEqual(@as(u16, 60), size.width);
    try std.testing.expectEqual(@as(u16, 20), size.height);
}

test "MockTerminal no memory leaks" {
    // Using testing.allocator which detects leaks
    const allocator = std.testing.allocator;
    var term = MockTerminal.init(allocator, .{ .width = 80, .height = 24 });

    // Queue some events
    try term.queueKey(.{ .char = 'a' });
    try term.queueKey(.{ .char = 'b' });
    try term.queueResize(.{ .width = 100, .height = 30 });

    // Write some output
    try term.write("Test output data");
    try term.write(" more data");

    // Deinit should free everything
    term.deinit();
    // If there are leaks, testing.allocator will catch them
}

test "MockTerminal edge case - zero size" {
    const allocator = std.testing.allocator;
    var term = MockTerminal.init(allocator, .{ .width = 0, .height = 0 });
    defer term.deinit();

    // Should handle zero size gracefully
    const size = term.getSize();
    try std.testing.expectEqual(@as(u16, 0), size.width);
    try std.testing.expectEqual(@as(u16, 0), size.height);
}

test "MockTerminal edge case - large event queue" {
    const allocator = std.testing.allocator;
    var term = MockTerminal.init(allocator, .{ .width = 80, .height = 24 });
    defer term.deinit();

    // Queue many events
    var i: usize = 0;
    while (i < 1000) : (i += 1) {
        try term.queueKey(.{ .char = 'x' });
    }

    // Should be able to poll them all
    var count: usize = 0;
    while (term.pollEvent()) |_| {
        count += 1;
    }
    try std.testing.expectEqual(@as(usize, 1000), count);
}

test "MockTerminal edge case - large output" {
    const allocator = std.testing.allocator;
    var term = MockTerminal.init(allocator, .{ .width = 80, .height = 24 });
    defer term.deinit();

    // Write large output
    var i: usize = 0;
    while (i < 100) : (i += 1) {
        try term.write("This is a line of text that will be written to the terminal output buffer.\n");
    }

    const output = term.getOutput();
    try std.testing.expect(output.len >= 7500); // Should capture all
}
