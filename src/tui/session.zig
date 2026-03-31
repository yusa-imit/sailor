const std = @import("std");
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const Event = @import("tui.zig").Event;

/// Session recording and playback for debugging TUI applications.
/// Records all events and frame states to a file that can be replayed later.
pub const SessionRecorder = struct {
    allocator: Allocator,
    events: ArrayList(RecordedEvent),
    start_time: i64,
    is_recording: bool,

    pub const RecordedEvent = struct {
        timestamp_ms: i64, // Milliseconds since recording started
        event: Event,
    };

    /// Initialize a new session recorder.
    ///
    /// Creates a recorder in stopped state (not recording).
    /// Call startRecording() to begin capturing events.
    ///
    /// Args:
    ///   allocator: Memory allocator for event storage
    ///
    /// Returns:
    ///   Initialized SessionRecorder
    pub fn init(allocator: Allocator) !SessionRecorder {
        return SessionRecorder{
            .allocator = allocator,
            .events = .{},
            .start_time = std.time.milliTimestamp(),
            .is_recording = false,
        };
    }

    /// Deinitialize the recorder and free all captured events.
    ///
    /// Must be called to prevent memory leaks.
    /// After this call, the recorder cannot be used.
    pub fn deinit(self: *SessionRecorder) void {
        self.events.deinit(self.allocator);
    }

    /// Start recording events.
    pub fn startRecording(self: *SessionRecorder) void {
        self.is_recording = true;
        self.start_time = std.time.milliTimestamp();
        self.events.clearRetainingCapacity();
    }

    /// Stop recording events.
    pub fn stopRecording(self: *SessionRecorder) void {
        self.is_recording = false;
    }

    /// Record an event with current timestamp.
    pub fn recordEvent(self: *SessionRecorder, event: Event) !void {
        if (!self.is_recording) return;

        const now = std.time.milliTimestamp();
        const elapsed = now - self.start_time;

        try self.events.append(self.allocator, .{
            .timestamp_ms = elapsed,
            .event = event,
        });
    }

    /// Save recorded session to a file.
    pub fn saveToFile(self: *SessionRecorder, path: []const u8) !void {
        const file = try std.fs.cwd().createFile(path, .{});
        defer file.close();

        var buf: std.ArrayList(u8) = .{};
        defer buf.deinit(self.allocator);
        const writer = buf.writer(self.allocator);

        // Write header
        try writer.print("# Sailor Session Recording\n", .{});
        try writer.print("# Events: {d}\n", .{self.events.items.len});
        try writer.print("# Duration: {d}ms\n", .{
            if (self.events.items.len > 0) self.events.items[self.events.items.len - 1].timestamp_ms else 0,
        });

        // Write events (one per line, JSON format)
        for (self.events.items) |recorded| {
            try writer.print("{{\"ts\":{d},\"event\":", .{recorded.timestamp_ms});
            try writeEvent(writer, recorded.event);
            try writer.print("}}\n", .{});
        }

        try file.writeAll(buf.items);
    }

    /// Load recorded session from a file.
    pub fn loadFromFile(allocator: Allocator, path: []const u8) !SessionRecorder {
        var recorder = try SessionRecorder.init(allocator);
        errdefer recorder.deinit();

        const file = try std.fs.cwd().openFile(path, .{});
        defer file.close();

        const content = try file.readToEndAlloc(allocator, 10 * 1024 * 1024); // 10MB max
        defer allocator.free(content);

        var lines = std.mem.tokenizeScalar(u8, content, '\n');

        while (lines.next()) |line| {
            // Skip comments and empty lines
            if (line.len == 0 or line[0] == '#') continue;

            // Parse JSON line
            if (try parseRecordedEvent(allocator, line)) |recorded| {
                try recorder.events.append(allocator, recorded);
            }
        }

        return recorder;
    }

    fn writeEvent(writer: anytype, event: Event) !void {
        switch (event) {
            .key => |k| try writer.print("{{\"type\":\"key\",\"key\":\"{s}\"}}", .{@tagName(k.code)}),
            .mouse => try writer.print("{{\"type\":\"mouse\"}}", .{}),
            .resize => |r| try writer.print("{{\"type\":\"resize\",\"width\":{d},\"height\":{d}}}", .{ r.width, r.height }),
            .gamepad => try writer.print("{{\"type\":\"gamepad\"}}", .{}),
            .touch => try writer.print("{{\"type\":\"touch\"}}", .{}),
        }
    }

    fn parseRecordedEvent(allocator: Allocator, line: []const u8) !?RecordedEvent {
        _ = allocator; // For future JSON parsing

        // Simple parser for now - just handle basic format
        // {"ts":123,"event":{"type":"key","key":"a"}}

        // Find timestamp
        const ts_start = std.mem.indexOf(u8, line, "\"ts\":") orelse return null;
        const ts_end = std.mem.indexOfPos(u8, line, ts_start, ",") orelse return null;
        const ts_str = line[ts_start + 5 .. ts_end];
        const timestamp_ms = try std.fmt.parseInt(i64, ts_str, 10);

        // Find event type
        const type_start = std.mem.indexOf(u8, line, "\"type\":\"") orelse return null;
        const type_end = std.mem.indexOfPos(u8, line, type_start + 8, "\"") orelse return null;
        const event_type = line[type_start + 8 .. type_end];

        const event: Event = if (std.mem.eql(u8, event_type, "key")) blk: {
            // Parse key event
            const key_start = std.mem.indexOf(u8, line, "\"key\":\"") orelse break :blk .{ .key = .{ .code = .enter } };
            const key_end = std.mem.indexOfPos(u8, line, key_start + 7, "\"") orelse break :blk .{ .key = .{ .code = .enter } };
            const key_str = line[key_start + 7 .. key_end];

            // Simple key mapping
            if (std.mem.eql(u8, key_str, "enter")) break :blk .{ .key = .{ .code = .enter } };
            if (std.mem.eql(u8, key_str, "esc")) break :blk .{ .key = .{ .code = .esc } };
            if (std.mem.eql(u8, key_str, "backspace")) break :blk .{ .key = .{ .code = .backspace } };
            if (std.mem.eql(u8, key_str, "up")) break :blk .{ .key = .{ .code = .up } };
            if (std.mem.eql(u8, key_str, "down")) break :blk .{ .key = .{ .code = .down } };
            if (std.mem.eql(u8, key_str, "left")) break :blk .{ .key = .{ .code = .left } };
            if (std.mem.eql(u8, key_str, "right")) break :blk .{ .key = .{ .code = .right } };

            break :blk .{ .key = .{ .code = .enter } }; // Default
        } else if (std.mem.eql(u8, event_type, "resize")) blk: {
            const width_start = std.mem.indexOf(u8, line, "\"width\":") orelse break :blk .{ .resize = .{ .width = 80, .height = 24 } };
            const width_end = std.mem.indexOfPos(u8, line, width_start, ",") orelse break :blk .{ .resize = .{ .width = 80, .height = 24 } };
            const width_str = line[width_start + 8 .. width_end];
            const width = try std.fmt.parseInt(u16, width_str, 10);

            const height_start = std.mem.indexOf(u8, line, "\"height\":") orelse break :blk .{ .resize = .{ .width = width, .height = 24 } };
            const height_end = std.mem.indexOfPos(u8, line, height_start, "}") orelse break :blk .{ .resize = .{ .width = width, .height = 24 } };
            const height_str = line[height_start + 9 .. height_end];
            const height = try std.fmt.parseInt(u16, height_str, 10);

            break :blk .{ .resize = .{ .width = width, .height = height } };
        } else {
            return null;
        };

        return RecordedEvent{
            .timestamp_ms = timestamp_ms,
            .event = event,
        };
    }
};

/// Session player for replaying recorded events.
pub const SessionPlayer = struct {
    recorder: SessionRecorder,
    current_index: usize,
    playback_start_time: i64,
    is_playing: bool,
    speed_multiplier: f32, // 1.0 = normal, 2.0 = 2x speed, 0.5 = half speed

    /// Initialize a new session player from a recorded session.
    ///
    /// The player starts in stopped state. Call startPlayback() to begin.
    /// Speed can be adjusted via speed_multiplier field (default 1.0).
    ///
    /// Args:
    ///   recorder: SessionRecorder containing captured events
    ///
    /// Returns:
    ///   SessionPlayer ready for playback
    pub fn init(recorder: SessionRecorder) SessionPlayer {
        return SessionPlayer{
            .recorder = recorder,
            .current_index = 0,
            .playback_start_time = 0,
            .is_playing = false,
            .speed_multiplier = 1.0,
        };
    }

    /// Deinitialize the player and free all recorded events.
    ///
    /// Must be called to prevent memory leaks.
    /// After this call, the player cannot be used.
    pub fn deinit(self: *SessionPlayer) void {
        self.recorder.deinit();
    }

    /// Start playback from the beginning.
    pub fn startPlayback(self: *SessionPlayer) void {
        self.is_playing = true;
        self.current_index = 0;
        self.playback_start_time = std.time.milliTimestamp();
    }

    /// Stop playback.
    pub fn stopPlayback(self: *SessionPlayer) void {
        self.is_playing = false;
    }

    /// Set playback speed (1.0 = normal).
    pub fn setSpeed(self: *SessionPlayer, multiplier: f32) void {
        self.speed_multiplier = multiplier;
    }

    /// Get next event to play, or null if not ready yet.
    /// Call this in your event loop to get events at the right time.
    pub fn getNextEvent(self: *SessionPlayer) ?Event {
        if (!self.is_playing) return null;
        if (self.current_index >= self.recorder.events.items.len) {
            self.is_playing = false;
            return null;
        }

        const recorded = self.recorder.events.items[self.current_index];
        const now = std.time.milliTimestamp();
        const elapsed = now - self.playback_start_time;

        // Adjust for speed multiplier
        const adjusted_elapsed = @as(i64, @intFromFloat(@as(f32, @floatFromInt(elapsed)) * self.speed_multiplier));

        if (adjusted_elapsed >= recorded.timestamp_ms) {
            self.current_index += 1;
            return recorded.event;
        }

        return null;
    }

    /// Skip to a specific timestamp in the recording.
    pub fn seekToTime(self: *SessionPlayer, target_ms: i64) void {
        self.current_index = 0;
        while (self.current_index < self.recorder.events.items.len) : (self.current_index += 1) {
            if (self.recorder.events.items[self.current_index].timestamp_ms >= target_ms) {
                break;
            }
        }
        self.playback_start_time = std.time.milliTimestamp() - target_ms;
    }

    /// Get progress percentage (0.0 to 1.0).
    pub fn getProgress(self: *SessionPlayer) f32 {
        if (self.recorder.events.items.len == 0) return 0.0;
        return @as(f32, @floatFromInt(self.current_index)) / @as(f32, @floatFromInt(self.recorder.events.items.len));
    }
};

// Tests
test "SessionRecorder: init and deinit" {
    const allocator = std.testing.allocator;
    var recorder = try SessionRecorder.init(allocator);
    defer recorder.deinit();

    try std.testing.expect(!recorder.is_recording);
    try std.testing.expectEqual(@as(usize, 0), recorder.events.items.len);
}

test "SessionRecorder: start and stop recording" {
    const allocator = std.testing.allocator;
    var recorder = try SessionRecorder.init(allocator);
    defer recorder.deinit();

    recorder.startRecording();
    try std.testing.expect(recorder.is_recording);

    recorder.stopRecording();
    try std.testing.expect(!recorder.is_recording);
}

test "SessionRecorder: record key events" {
    const allocator = std.testing.allocator;
    var recorder = try SessionRecorder.init(allocator);
    defer recorder.deinit();

    const tui = @import("tui.zig");

    recorder.startRecording();

    try recorder.recordEvent(.{ .key = .{ .code = .enter } });
    try recorder.recordEvent(.{ .key = .{ .code = .esc } });
    try recorder.recordEvent(.{ .key = .{ .code = .up } });

    try std.testing.expectEqual(@as(usize, 3), recorder.events.items.len);
    try std.testing.expectEqual(tui.KeyCode.enter, recorder.events.items[0].event.key.code);
    try std.testing.expectEqual(tui.KeyCode.esc, recorder.events.items[1].event.key.code);
    try std.testing.expectEqual(tui.KeyCode.up, recorder.events.items[2].event.key.code);
}

test "SessionRecorder: record resize events" {
    const allocator = std.testing.allocator;
    var recorder = try SessionRecorder.init(allocator);
    defer recorder.deinit();

    recorder.startRecording();
    try recorder.recordEvent(.{ .resize = .{ .width = 100, .height = 50 } });

    try std.testing.expectEqual(@as(usize, 1), recorder.events.items.len);
    try std.testing.expectEqual(@as(u16, 100), recorder.events.items[0].event.resize.width);
    try std.testing.expectEqual(@as(u16, 50), recorder.events.items[0].event.resize.height);
}

test "SessionRecorder: timestamps increase" {
    const allocator = std.testing.allocator;
    var recorder = try SessionRecorder.init(allocator);
    defer recorder.deinit();

    recorder.startRecording();

    try recorder.recordEvent(.{ .key = .{ .code = .enter } });
    std.Thread.sleep(2 * std.time.ns_per_ms); // Sleep 2ms
    try recorder.recordEvent(.{ .key = .{ .code = .esc } });

    try std.testing.expectEqual(@as(usize, 2), recorder.events.items.len);
    try std.testing.expect(recorder.events.items[1].timestamp_ms >= recorder.events.items[0].timestamp_ms);
}

test "SessionRecorder: save and load from file" {
    const allocator = std.testing.allocator;
    const tui = @import("tui.zig");

    // Record session
    var recorder1 = try SessionRecorder.init(allocator);
    defer recorder1.deinit();

    recorder1.startRecording();
    try recorder1.recordEvent(.{ .key = .{ .code = .enter } });
    try recorder1.recordEvent(.{ .resize = .{ .width = 80, .height = 24 } });
    try recorder1.recordEvent(.{ .key = .{ .code = .esc } });
    recorder1.stopRecording();

    // Save to file
    const test_file = "test_session.rec";
    try recorder1.saveToFile(test_file);
    defer std.fs.cwd().deleteFile(test_file) catch {};

    // Load from file
    var recorder2 = try SessionRecorder.loadFromFile(allocator, test_file);
    defer recorder2.deinit();

    try std.testing.expectEqual(@as(usize, 3), recorder2.events.items.len);
    try std.testing.expectEqual(tui.KeyCode.enter, recorder2.events.items[0].event.key.code);
    try std.testing.expectEqual(@as(u16, 80), recorder2.events.items[1].event.resize.width);
    try std.testing.expectEqual(tui.KeyCode.esc, recorder2.events.items[2].event.key.code);
}

test "SessionPlayer: init and playback control" {
    const allocator = std.testing.allocator;
    var recorder = try SessionRecorder.init(allocator);
    recorder.startRecording();
    try recorder.recordEvent(.{ .key = .{ .code = .enter } });
    recorder.stopRecording();

    var player = SessionPlayer.init(recorder);
    defer player.deinit();

    try std.testing.expect(!player.is_playing);

    player.startPlayback();
    try std.testing.expect(player.is_playing);

    player.stopPlayback();
    try std.testing.expect(!player.is_playing);
}

test "SessionPlayer: get next event timing" {
    const allocator = std.testing.allocator;
    const tui = @import("tui.zig");
    var recorder = try SessionRecorder.init(allocator);

    // Manually create events with specific timestamps
    try recorder.events.append(allocator, .{ .timestamp_ms = 0, .event = .{ .key = .{ .code = .enter } } });
    try recorder.events.append(allocator, .{ .timestamp_ms = 100, .event = .{ .key = .{ .code = .esc } } });

    var player = SessionPlayer.init(recorder);
    defer player.deinit();

    player.startPlayback();

    // First event should be available immediately
    if (player.getNextEvent()) |event| {
        try std.testing.expectEqual(tui.KeyCode.enter, event.key.code);
    }

    // Second event requires waiting
    const start = std.time.milliTimestamp();
    while (player.getNextEvent() == null) {
        if (std.time.milliTimestamp() - start > 200) break;
        std.Thread.sleep(10 * std.time.ns_per_ms);
    }
}

test "SessionPlayer: speed multiplier" {
    const allocator = std.testing.allocator;
    var recorder = try SessionRecorder.init(allocator);
    defer recorder.deinit();

    var player = SessionPlayer.init(recorder);
    defer player.deinit();

    player.setSpeed(2.0);
    try std.testing.expectEqual(@as(f32, 2.0), player.speed_multiplier);

    player.setSpeed(0.5);
    try std.testing.expectEqual(@as(f32, 0.5), player.speed_multiplier);
}

test "SessionPlayer: seek to time" {
    const allocator = std.testing.allocator;
    var recorder = try SessionRecorder.init(allocator);

    try recorder.events.append(allocator, .{ .timestamp_ms = 0, .event = .{ .key = .{ .code = .enter } } });
    try recorder.events.append(allocator, .{ .timestamp_ms = 100, .event = .{ .key = .{ .code = .esc } } });
    try recorder.events.append(allocator, .{ .timestamp_ms = 200, .event = .{ .key = .{ .code = .up } } });

    var player = SessionPlayer.init(recorder);
    defer player.deinit();

    player.seekToTime(150);
    try std.testing.expectEqual(@as(usize, 2), player.current_index);
}

test "SessionPlayer: get progress" {
    const allocator = std.testing.allocator;
    var recorder = try SessionRecorder.init(allocator);

    try recorder.events.append(allocator, .{ .timestamp_ms = 0, .event = .{ .key = .{ .code = .enter } } });
    try recorder.events.append(allocator, .{ .timestamp_ms = 100, .event = .{ .key = .{ .code = .esc } } });
    try recorder.events.append(allocator, .{ .timestamp_ms = 200, .event = .{ .key = .{ .code = .up } } });

    var player = SessionPlayer.init(recorder);
    defer player.deinit();

    try std.testing.expectEqual(@as(f32, 0.0), player.getProgress());

    player.current_index = 1;
    const progress = player.getProgress();
    try std.testing.expect(progress > 0.3 and progress < 0.4); // ~0.33

    player.current_index = 3;
    try std.testing.expectEqual(@as(f32, 1.0), player.getProgress());
}

test "SessionRecorder: clear on start recording" {
    const allocator = std.testing.allocator;
    var recorder = try SessionRecorder.init(allocator);
    defer recorder.deinit();

    recorder.startRecording();
    try recorder.recordEvent(.{ .key = .{ .code = .enter } });
    recorder.stopRecording();

    try std.testing.expectEqual(@as(usize, 1), recorder.events.items.len);

    // Start new recording should clear old events
    recorder.startRecording();
    try std.testing.expectEqual(@as(usize, 0), recorder.events.items.len);
}
