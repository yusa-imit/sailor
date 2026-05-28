//! Comprehensive tests for sailor's State Persistence system (v2.13.0)
//!
//! Tests for StatePersist(State) - serialize/deserialize store state.
//!
//! Coverage:
//! - StatePersist init with encode/decode functions
//! - save() writes state to writer
//! - load() reads state from reader
//! - Integer state persistence
//! - String state persistence
//! - Struct state persistence (multiple fields)
//! - Array state persistence
//! - Error handling in encode
//! - Error handling in decode
//! - Round-trip persistence (save then load)
//! - Multiple saves to different writers
//! - UTF-8 string handling
//! - Large struct serialization

const std = @import("std");
const testing = std.testing;
const sailor = @import("sailor");

// ============================================================================
// Example State Types & Encode/Decode Functions
// ============================================================================

const SimpleState = struct {
    count: i32,
};

fn encodeSimple(state: SimpleState, writer: anytype) !void {
    try std.fmt.format(writer, "{}", .{state.count});
}

fn decodeSimple(reader: anytype, allocator: std.mem.Allocator) !SimpleState {
    _ = allocator;
    var buf: [32]u8 = undefined;
    const bytes_read = try reader.readAll(&buf);
    const count = try std.fmt.parseInt(i32, buf[0..bytes_read], 10);
    return .{ .count = count };
}

const ComplexState = struct {
    name: []const u8,
    age: u32,
    active: bool,
};

fn encodeComplex(state: ComplexState, writer: anytype) !void {
    try std.fmt.format(writer, "{}|{}|{}", .{
        state.name,
        state.age,
        if (state.active) "1" else "0",
    });
}

fn decodeComplex(reader: anytype, allocator: std.mem.Allocator) !ComplexState {
    var buf: [256]u8 = undefined;
    const bytes_read = try reader.readAll(&buf);
    const content = buf[0..bytes_read];

    var iter = std.mem.splitSequence(u8, content, "|");
    const name_str = iter.next() orelse return error.InvalidFormat;
    const age_str = iter.next() orelse return error.InvalidFormat;
    const active_str = iter.next() orelse return error.InvalidFormat;

    const name = try allocator.dupe(u8, name_str);
    const age = try std.fmt.parseInt(u32, age_str, 10);
    const active = std.mem.eql(u8, active_str, "1");

    return .{
        .name = name,
        .age = age,
        .active = active,
    };
}

// ============================================================================
// StatePersist Lifecycle Tests
// ============================================================================

test "StatePersist init with encode/decode" {
    const allocator = testing.allocator;

    const persist = sailor.state_persist.StatePersist(SimpleState).init(
        encodeSimple,
        decodeSimple,
    );

    _ = persist;
    // Should initialize without errors
}

// ============================================================================
// Save Tests
// ============================================================================

test "StatePersist save writes to writer" {
    const allocator = testing.allocator;
    var buf: [128]u8 = undefined;
    var stream = std.io.fixedBufferStream(&buf);

    const state: SimpleState = .{ .count = 42 };
    const persist = sailor.state_persist.StatePersist(SimpleState).init(
        encodeSimple,
        decodeSimple,
    );

    try persist.save(state, stream.writer());

    const written = stream.getWritten();
    try testing.expectEqualStrings("42", written);
}

test "StatePersist save with zero value" {
    const allocator = testing.allocator;
    var buf: [128]u8 = undefined;
    var stream = std.io.fixedBufferStream(&buf);

    const state: SimpleState = .{ .count = 0 };
    const persist = sailor.state_persist.StatePersist(SimpleState).init(
        encodeSimple,
        decodeSimple,
    );

    try persist.save(state, stream.writer());

    const written = stream.getWritten();
    try testing.expectEqualStrings("0", written);
}

test "StatePersist save with negative value" {
    const allocator = testing.allocator;
    var buf: [128]u8 = undefined;
    var stream = std.io.fixedBufferStream(&buf);

    const state: SimpleState = .{ .count = -100 };
    const persist = sailor.state_persist.StatePersist(SimpleState).init(
        encodeSimple,
        decodeSimple,
    );

    try persist.save(state, stream.writer());

    const written = stream.getWritten();
    try testing.expectEqualStrings("-100", written);
}

test "StatePersist save large value" {
    const allocator = testing.allocator;
    var buf: [128]u8 = undefined;
    var stream = std.io.fixedBufferStream(&buf);

    const state: SimpleState = .{ .count = 999999 };
    const persist = sailor.state_persist.StatePersist(SimpleState).init(
        encodeSimple,
        decodeSimple,
    );

    try persist.save(state, stream.writer());

    const written = stream.getWritten();
    try testing.expectEqualStrings("999999", written);
}

// ============================================================================
// Load Tests
// ============================================================================

test "StatePersist load reads from reader" {
    const allocator = testing.allocator;
    const data = "42";
    var stream = std.io.fixedBufferStream(data);

    const persist = sailor.state_persist.StatePersist(SimpleState).init(
        encodeSimple,
        decodeSimple,
    );

    const state = try persist.load(stream.reader(), allocator);
    try testing.expectEqual(@as(i32, 42), state.count);
}

test "StatePersist load with zero value" {
    const allocator = testing.allocator;
    const data = "0";
    var stream = std.io.fixedBufferStream(data);

    const persist = sailor.state_persist.StatePersist(SimpleState).init(
        encodeSimple,
        decodeSimple,
    );

    const state = try persist.load(stream.reader(), allocator);
    try testing.expectEqual(@as(i32, 0), state.count);
}

test "StatePersist load with negative value" {
    const allocator = testing.allocator;
    const data = "-100";
    var stream = std.io.fixedBufferStream(data);

    const persist = sailor.state_persist.StatePersist(SimpleState).init(
        encodeSimple,
        decodeSimple,
    );

    const state = try persist.load(stream.reader(), allocator);
    try testing.expectEqual(@as(i32, -100), state.count);
}

test "StatePersist load large value" {
    const allocator = testing.allocator;
    const data = "999999";
    var stream = std.io.fixedBufferStream(data);

    const persist = sailor.state_persist.StatePersist(SimpleState).init(
        encodeSimple,
        decodeSimple,
    );

    const state = try persist.load(stream.reader(), allocator);
    try testing.expectEqual(@as(i32, 999999), state.count);
}

// ============================================================================
// Round-Trip Tests
// ============================================================================

test "StatePersist round-trip preserves state" {
    const allocator = testing.allocator;
    var save_buf: [128]u8 = undefined;
    var save_stream = std.io.fixedBufferStream(&save_buf);

    const original: SimpleState = .{ .count = 42 };
    const persist = sailor.state_persist.StatePersist(SimpleState).init(
        encodeSimple,
        decodeSimple,
    );

    try persist.save(original, save_stream.writer());

    const written = save_stream.getWritten();
    var load_stream = std.io.fixedBufferStream(written);

    const loaded = try persist.load(load_stream.reader(), allocator);
    try testing.expectEqual(original.count, loaded.count);
}

test "StatePersist round-trip multiple values" {
    const allocator = testing.allocator;
    const persist = sailor.state_persist.StatePersist(SimpleState).init(
        encodeSimple,
        decodeSimple,
    );

    const test_values = [_]i32{ 0, 1, -1, 100, -100, 9999 };

    for (test_values) |val| {
        var save_buf: [128]u8 = undefined;
        var save_stream = std.io.fixedBufferStream(&save_buf);

        const original: SimpleState = .{ .count = val };
        try persist.save(original, save_stream.writer());

        const written = save_stream.getWritten();
        var load_stream = std.io.fixedBufferStream(written);

        const loaded = try persist.load(load_stream.reader(), allocator);
        try testing.expectEqual(val, loaded.count);
    }
}

// ============================================================================
// Complex State Tests
// ============================================================================

test "StatePersist complex state with strings" {
    const allocator = testing.allocator;
    var buf: [256]u8 = undefined;
    var stream = std.io.fixedBufferStream(&buf);

    const state: ComplexState = .{
        .name = "Alice",
        .age = 30,
        .active = true,
    };

    const persist = sailor.state_persist.StatePersist(ComplexState).init(
        encodeComplex,
        decodeComplex,
    );

    try persist.save(state, stream.writer());

    const written = stream.getWritten();
    try testing.expectEqualStrings("Alice|30|1", written);
}

test "StatePersist complex state load" {
    const allocator = testing.allocator;
    const data = "Alice|30|1";
    var stream = std.io.fixedBufferStream(data);

    const persist = sailor.state_persist.StatePersist(ComplexState).init(
        encodeComplex,
        decodeComplex,
    );

    const state = try persist.load(stream.reader(), allocator);
    try testing.expectEqualStrings("Alice", state.name);
    try testing.expectEqual(@as(u32, 30), state.age);
    try testing.expectEqual(true, state.active);
}

test "StatePersist complex state inactive" {
    const allocator = testing.allocator;
    const data = "Bob|25|0";
    var stream = std.io.fixedBufferStream(data);

    const persist = sailor.state_persist.StatePersist(ComplexState).init(
        encodeComplex,
        decodeComplex,
    );

    const state = try persist.load(stream.reader(), allocator);
    try testing.expectEqualStrings("Bob", state.name);
    try testing.expectEqual(@as(u32, 25), state.age);
    try testing.expectEqual(false, state.active);
}

test "StatePersist complex state round-trip" {
    const allocator = testing.allocator;
    var save_buf: [256]u8 = undefined;
    var save_stream = std.io.fixedBufferStream(&save_buf);

    const original: ComplexState = .{
        .name = "Charlie",
        .age = 35,
        .active = true,
    };

    const persist = sailor.state_persist.StatePersist(ComplexState).init(
        encodeComplex,
        decodeComplex,
    );

    try persist.save(original, save_stream.writer());

    const written = save_stream.getWritten();
    var load_stream = std.io.fixedBufferStream(written);

    const loaded = try persist.load(load_stream.reader(), allocator);
    try testing.expectEqualStrings(original.name, loaded.name);
    try testing.expectEqual(original.age, loaded.age);
    try testing.expectEqual(original.active, loaded.active);
}

// ============================================================================
// Error Handling Tests
// ============================================================================

test "StatePersist load invalid format returns error" {
    const allocator = testing.allocator;
    const data = "not-a-number";
    var stream = std.io.fixedBufferStream(data);

    const persist = sailor.state_persist.StatePersist(SimpleState).init(
        encodeSimple,
        decodeSimple,
    );

    const result = persist.load(stream.reader(), allocator);
    try testing.expectError(error.InvalidFormat, result);
}

test "StatePersist complex load missing field" {
    const allocator = testing.allocator;
    const data = "Alice|30"; // Missing active flag
    var stream = std.io.fixedBufferStream(data);

    const persist = sailor.state_persist.StatePersist(ComplexState).init(
        encodeComplex,
        decodeComplex,
    );

    const result = persist.load(stream.reader(), allocator);
    try testing.expectError(error.InvalidFormat, result);
}

// ============================================================================
// Multiple Save Tests
// ============================================================================

test "StatePersist multiple saves to different writers" {
    const allocator = testing.allocator;
    const persist = sailor.state_persist.StatePersist(SimpleState).init(
        encodeSimple,
        decodeSimple,
    );

    var buf1: [128]u8 = undefined;
    var stream1 = std.io.fixedBufferStream(&buf1);

    var buf2: [128]u8 = undefined;
    var stream2 = std.io.fixedBufferStream(&buf2);

    const state: SimpleState = .{ .count = 42 };

    try persist.save(state, stream1.writer());
    try persist.save(state, stream2.writer());

    try testing.expectEqualStrings("42", stream1.getWritten());
    try testing.expectEqualStrings("42", stream2.getWritten());
}

// ============================================================================
// UTF-8 String Tests
// ============================================================================

test "StatePersist handles UTF-8 strings" {
    const allocator = testing.allocator;
    var save_buf: [256]u8 = undefined;
    var save_stream = std.io.fixedBufferStream(&save_buf);

    const original: ComplexState = .{
        .name = "Müller",
        .age = 40,
        .active = true,
    };

    const persist = sailor.state_persist.StatePersist(ComplexState).init(
        encodeComplex,
        decodeComplex,
    );

    try persist.save(original, save_stream.writer());

    const written = save_stream.getWritten();
    var load_stream = std.io.fixedBufferStream(written);

    const loaded = try persist.load(load_stream.reader(), allocator);
    try testing.expectEqualStrings(original.name, loaded.name);
}

test "StatePersist handles emoji strings" {
    const allocator = testing.allocator;
    var save_buf: [256]u8 = undefined;
    var save_stream = std.io.fixedBufferStream(&save_buf);

    const original: ComplexState = .{
        .name = "emoji🔥",
        .age = 25,
        .active = false,
    };

    const persist = sailor.state_persist.StatePersist(ComplexState).init(
        encodeComplex,
        decodeComplex,
    );

    try persist.save(original, save_stream.writer());

    const written = save_stream.getWritten();
    var load_stream = std.io.fixedBufferStream(written);

    const loaded = try persist.load(load_stream.reader(), allocator);
    try testing.expectEqualStrings(original.name, loaded.name);
}

// ============================================================================
// Edge Cases
// ============================================================================

test "StatePersist with empty reader" {
    const allocator = testing.allocator;
    const data = "";
    var stream = std.io.fixedBufferStream(data);

    const persist = sailor.state_persist.StatePersist(SimpleState).init(
        encodeSimple,
        decodeSimple,
    );

    const result = persist.load(stream.reader(), allocator);
    try testing.expectError(error.InvalidFormat, result);
}

test "StatePersist with empty string in complex" {
    const allocator = testing.allocator;
    var save_buf: [256]u8 = undefined;
    var save_stream = std.io.fixedBufferStream(&save_buf);

    const original: ComplexState = .{
        .name = "",
        .age = 0,
        .active = false,
    };

    const persist = sailor.state_persist.StatePersist(ComplexState).init(
        encodeComplex,
        decodeComplex,
    );

    try persist.save(original, save_stream.writer());

    const written = save_stream.getWritten();
    var load_stream = std.io.fixedBufferStream(written);

    const loaded = try persist.load(load_stream.reader(), allocator);
    try testing.expectEqualStrings("", loaded.name);
    try testing.expectEqual(@as(u32, 0), loaded.age);
}
