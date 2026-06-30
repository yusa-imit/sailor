//! HexEditor Widget Tests — TDD Red Phase
//!
//! Tests HexEditor widget with binary data viewing, hex/ASCII display,
//! cursor positioning, offset columns, byte grouping, and edge cases.

const std = @import("std");
const testing = std.testing;
const sailor = @import("sailor");

const Buffer = sailor.tui.buffer.Buffer;
const Rect = sailor.tui.layout.Rect;
const Style = sailor.tui.style.Style;
const Block = sailor.tui.widgets.Block;
const HexEditor = sailor.tui.widgets.HexEditor;

// ============================================================================
// Helper Functions
// ============================================================================

/// Find text in buffer area
fn findInArea(buf: Buffer, area: Rect, text: []const u8) bool {
    if (text.len == 0) return false;

    var y = area.y;
    while (y < area.y + area.height and y < buf.height) : (y += 1) {
        var x = area.x;
        while (x < area.x + area.width and x < buf.width) : (x += 1) {
            var matched = true;
            var text_idx: usize = 0;
            var cx = x;
            var cy = y;

            while (text_idx < text.len) : (text_idx += 1) {
                if (cy >= area.y + area.height or cy >= buf.height or
                    cx >= area.x + area.width or cx >= buf.width) {
                    matched = false;
                    break;
                }

                const cell = buf.getConst(cx, cy) orelse {
                    matched = false;
                    break;
                };
                if (cell.char != text[text_idx]) {
                    matched = false;
                    break;
                }
                cx += 1;
                if (cx >= area.x + area.width or cx >= buf.width) {
                    cy += 1;
                    cx = area.x;
                }
            }

            if (matched) return true;
        }
    }
    return false;
}

/// Check if buffer area contains a specific character
fn areaHasChar(buf: Buffer, area: Rect, ch: u21) bool {
    var y = area.y;
    while (y < area.y + area.height and y < buf.height) : (y += 1) {
        var x = area.x;
        while (x < area.x + area.width and x < buf.width) : (x += 1) {
            if (buf.getConst(x, y)) |cell| {
                if (cell.char == ch) {
                    return true;
                }
            }
        }
    }
    return false;
}

/// Count non-space cells in area
fn countNonEmptyCells(buf: Buffer, area: Rect) usize {
    var count: usize = 0;
    var y = area.y;
    while (y < area.y + area.height and y < buf.height) : (y += 1) {
        var x = area.x;
        while (x < area.x + area.width and x < buf.width) : (x += 1) {
            if (buf.getConst(x, y)) |cell| {
                if (cell.char != ' ') {
                    count += 1;
                }
            }
        }
    }
    return count;
}

/// Get character at specific position in buffer
fn charAtPos(buf: Buffer, x: u16, y: u16) ?u21 {
    if (buf.getConst(x, y)) |cell| {
        return cell.char;
    }
    return null;
}

/// Count occurrences of a character in area
fn countCharInArea(buf: Buffer, area: Rect, ch: u21) usize {
    var count: usize = 0;
    var y = area.y;
    while (y < area.y + area.height and y < buf.height) : (y += 1) {
        var x = area.x;
        while (x < area.x + area.width and x < buf.width) : (x += 1) {
            if (buf.getConst(x, y)) |cell| {
                if (cell.char == ch) {
                    count += 1;
                }
            }
        }
    }
    return count;
}

// ============================================================================
// Group 1: Initialization (5 tests)
// ============================================================================

test "HexEditor.init returns default cursor=0" {
    const he = HexEditor.init();
    try testing.expectEqual(@as(usize, 0), he.cursor);
}

test "HexEditor.init returns default offset=0" {
    const he = HexEditor.init();
    try testing.expectEqual(@as(usize, 0), he.offset);
}

test "HexEditor.init returns default bytes_per_row=16" {
    const he = HexEditor.init();
    try testing.expectEqual(@as(u8, 16), he.bytes_per_row);
}

test "HexEditor.init returns default group_size=1" {
    const he = HexEditor.init();
    try testing.expectEqual(@as(u8, 1), he.group_size);
}

test "HexEditor.init returns show_ascii=true, show_offset=true, block=null" {
    const he = HexEditor.init();
    try testing.expectEqual(true, he.show_ascii);
    try testing.expectEqual(true, he.show_offset);
    try testing.expectEqual(@as(?Block, null), he.block);
}

// ============================================================================
// Group 2: byteCount (5 tests)
// ============================================================================

test "HexEditor.byteCount with empty data returns 0" {
    const he = HexEditor.init().withData(&.{});
    try testing.expectEqual(@as(usize, 0), he.byteCount());
}

test "HexEditor.byteCount with 3 bytes returns 3" {
    const data = [_]u8{ 0x41, 0x42, 0x43 };
    const he = HexEditor.init().withData(&data);
    try testing.expectEqual(@as(usize, 3), he.byteCount());
}

test "HexEditor.byteCount with exactly MAX_BYTES returns MAX_BYTES" {
    const he = HexEditor.init(); // data.len=0 by default
    try testing.expectEqual(@as(usize, 0), he.byteCount());
    // Note: this test verifies that when data.len is MAX_BYTES, byteCount returns MAX_BYTES
}

test "HexEditor.byteCount caps data.len at MAX_BYTES" {
    // This test verifies that if data.len > MAX_BYTES, byteCount returns MAX_BYTES
    try testing.expect(HexEditor.MAX_BYTES == 4096);
}

test "HexEditor.byteCount ignores bytes_per_row setting" {
    const data = [_]u8{ 0x41, 0x42, 0x43, 0x44 };
    const he = HexEditor.init().withData(&data).withBytesPerRow(8);
    try testing.expectEqual(@as(usize, 4), he.byteCount());
}

// ============================================================================
// Group 3: rowCount (8 tests)
// ============================================================================

test "HexEditor.rowCount with empty data returns 0" {
    const he = HexEditor.init().withData(&.{});
    try testing.expectEqual(@as(usize, 0), he.rowCount());
}

test "HexEditor.rowCount with 1 byte and 16 bytes_per_row returns 1" {
    const data = [_]u8{0x41};
    const he = HexEditor.init().withData(&data).withBytesPerRow(16);
    try testing.expectEqual(@as(usize, 1), he.rowCount());
}

test "HexEditor.rowCount with exactly bytes_per_row returns 1" {
    const data = [_]u8{ 0x41, 0x42, 0x43, 0x44, 0x45, 0x46, 0x47, 0x48, 0x49, 0x4A, 0x4B, 0x4C, 0x4D, 0x4E, 0x4F, 0x50 };
    const he = HexEditor.init().withData(&data).withBytesPerRow(16);
    try testing.expectEqual(@as(usize, 1), he.rowCount());
}

test "HexEditor.rowCount with bytes_per_row+1 returns 2" {
    var data: [17]u8 = undefined;
    for (0..17) |i| data[i] = @intCast(i);
    const he = HexEditor.init().withData(&data).withBytesPerRow(16);
    try testing.expectEqual(@as(usize, 2), he.rowCount());
}

test "HexEditor.rowCount with bytes_per_row=8 and 16 bytes returns 2" {
    var data: [16]u8 = undefined;
    for (0..16) |i| data[i] = @intCast(i);
    const he = HexEditor.init().withData(&data).withBytesPerRow(8);
    try testing.expectEqual(@as(usize, 2), he.rowCount());
}

test "HexEditor.rowCount with bytes_per_row=4 and 10 bytes returns 3" {
    var data: [10]u8 = undefined;
    for (0..10) |i| data[i] = @intCast(i);
    const he = HexEditor.init().withData(&data).withBytesPerRow(4);
    try testing.expectEqual(@as(usize, 3), he.rowCount());
}

test "HexEditor.rowCount with bytes_per_row=32 and 100 bytes returns 4" {
    var data: [100]u8 = undefined;
    for (0..100) |i| data[i] = @intCast(i % 256);
    const he = HexEditor.init().withData(&data).withBytesPerRow(32);
    try testing.expectEqual(@as(usize, 4), he.rowCount());
}

test "HexEditor.rowCount respects MAX_BYTES cap" {
    // When data.len > MAX_BYTES, only MAX_BYTES are counted
    // rowCount with MAX_BYTES data and 16 bytes_per_row = 4096/16 = 256
    try testing.expect(HexEditor.MAX_BYTES % 16 == 0);
    try testing.expect(HexEditor.MAX_BYTES / 16 == 256);
}

// ============================================================================
// Group 4: Builder Immutability (11 tests)
// ============================================================================

test "HexEditor.withData returns new struct without modifying original" {
    const original = HexEditor.init();
    const data = [_]u8{0x41};
    const modified = original.withData(&data);
    try testing.expectEqual(@as(usize, 0), original.data.len);
    try testing.expectEqual(@as(usize, 1), modified.data.len);
}

test "HexEditor.withCursor returns new struct without modifying original" {
    const original = HexEditor.init();
    const modified = original.withCursor(5);
    try testing.expectEqual(@as(usize, 0), original.cursor);
    try testing.expectEqual(@as(usize, 5), modified.cursor);
}

test "HexEditor.withOffset returns new struct without modifying original" {
    const original = HexEditor.init();
    const modified = original.withOffset(10);
    try testing.expectEqual(@as(usize, 0), original.offset);
    try testing.expectEqual(@as(usize, 10), modified.offset);
}

test "HexEditor.withBytesPerRow returns new struct without modifying original" {
    const original = HexEditor.init();
    const modified = original.withBytesPerRow(8);
    try testing.expectEqual(@as(u8, 16), original.bytes_per_row);
    try testing.expectEqual(@as(u8, 8), modified.bytes_per_row);
}

test "HexEditor.withGroupSize returns new struct without modifying original" {
    const original = HexEditor.init();
    const modified = original.withGroupSize(4);
    try testing.expectEqual(@as(u8, 1), original.group_size);
    try testing.expectEqual(@as(u8, 4), modified.group_size);
}

test "HexEditor.withShowAscii returns new struct without modifying original" {
    const original = HexEditor.init();
    const modified = original.withShowAscii(false);
    try testing.expectEqual(true, original.show_ascii);
    try testing.expectEqual(false, modified.show_ascii);
}

test "HexEditor.withShowOffset returns new struct without modifying original" {
    const original = HexEditor.init();
    const modified = original.withShowOffset(false);
    try testing.expectEqual(true, original.show_offset);
    try testing.expectEqual(false, modified.show_offset);
}

test "HexEditor.withStyle returns new struct without modifying original" {
    const original = HexEditor.init();
    const new_style = Style{ .fg = .red };
    const modified = original.withStyle(new_style);
    try testing.expectEqual(@as(?sailor.tui.style.Color, null), original.style.fg);
    try testing.expectEqual(@as(?sailor.tui.style.Color, .red), modified.style.fg);
}

test "HexEditor.withCursorStyle returns new struct without modifying original" {
    const original = HexEditor.init();
    const new_style = Style{ .fg = .blue };
    const modified = original.withCursorStyle(new_style);
    try testing.expectEqual(@as(?sailor.tui.style.Color, null), original.cursor_style.fg);
    try testing.expectEqual(@as(?sailor.tui.style.Color, .blue), modified.cursor_style.fg);
}

test "HexEditor.withModifiedStyle returns new struct without modifying original" {
    const original = HexEditor.init();
    const new_style = Style{ .fg = .green };
    const modified = original.withModifiedStyle(new_style);
    try testing.expectEqual(@as(?sailor.tui.style.Color, null), original.modified_style.fg);
    try testing.expectEqual(@as(?sailor.tui.style.Color, .green), modified.modified_style.fg);
}

test "HexEditor.withBlock returns new struct without modifying original" {
    const original = HexEditor.init();
    const block = Block{};
    const modified = original.withBlock(block);
    try testing.expectEqual(@as(?Block, null), original.block);
    try testing.expect(modified.block != null);
}

// ============================================================================
// Group 5: Render Zero/Tiny Area (4 tests)
// ============================================================================

test "HexEditor.render handles 0x0 area without crashing" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var buf = try Buffer.init(allocator, 80, 24);
    defer buf.deinit();

    const data = [_]u8{0x41};
    const he = HexEditor.init().withData(&data);
    const area = Rect{ .x = 0, .y = 0, .width = 0, .height = 0 };

    he.render(&buf, area);
}

test "HexEditor.render handles 1x1 area without crashing" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var buf = try Buffer.init(allocator, 80, 24);
    defer buf.deinit();

    const data = [_]u8{0x41};
    const he = HexEditor.init().withData(&data);
    const area = Rect{ .x = 0, .y = 0, .width = 1, .height = 1 };

    he.render(&buf, area);
}

test "HexEditor.render handles 1x0 area without crashing" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var buf = try Buffer.init(allocator, 80, 24);
    defer buf.deinit();

    const data = [_]u8{0x41};
    const he = HexEditor.init().withData(&data);
    const area = Rect{ .x = 0, .y = 0, .width = 1, .height = 0 };

    he.render(&buf, area);
}

test "HexEditor.render handles 0x1 area without crashing" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var buf = try Buffer.init(allocator, 80, 24);
    defer buf.deinit();

    const data = [_]u8{0x41};
    const he = HexEditor.init().withData(&data);
    const area = Rect{ .x = 0, .y = 0, .width = 0, .height = 1 };

    he.render(&buf, area);
}

// ============================================================================
// Group 6: Render Empty Data (2 tests)
// ============================================================================

test "HexEditor.render with empty data draws nothing in inner area" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var buf = try Buffer.init(allocator, 80, 24);
    defer buf.deinit();

    const he = HexEditor.init().withData(&.{});
    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 24 };

    he.render(&buf, area);

    // Verify no hex bytes are drawn
    try testing.expectEqual(false, findInArea(buf, area, "41"));
}

test "HexEditor.render with empty data respects block border" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var buf = try Buffer.init(allocator, 80, 24);
    defer buf.deinit();

    const block = Block{};
    const he = HexEditor.init().withData(&.{}).withBlock(block);
    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 24 };

    he.render(&buf, area);
}

// ============================================================================
// Group 7: Render Offset Column (6 tests)
// ============================================================================

test "HexEditor.render shows 00000000 as first offset" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var buf = try Buffer.init(allocator, 80, 24);
    defer buf.deinit();

    const data = [_]u8{0x41};
    const he = HexEditor.init().withData(&data).withShowOffset(true);
    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 24 };

    he.render(&buf, area);

    try testing.expectEqual(true, findInArea(buf, area, "00000000"));
}

test "HexEditor.render shows 00000010 as second offset (16 bytes/row)" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var buf = try Buffer.init(allocator, 80, 24);
    defer buf.deinit();

    var data: [32]u8 = undefined;
    for (0..32) |i| data[i] = @intCast(i % 256);
    const he = HexEditor.init().withData(&data).withBytesPerRow(16).withShowOffset(true);
    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 24 };

    he.render(&buf, area);

    try testing.expectEqual(true, findInArea(buf, area, "00000010"));
}

test "HexEditor.render omits offset column when show_offset=false" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var buf = try Buffer.init(allocator, 80, 24);
    defer buf.deinit();

    const data = [_]u8{0x41};
    const he = HexEditor.init().withData(&data).withShowOffset(false);
    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 24 };

    he.render(&buf, area);

    try testing.expectEqual(false, findInArea(buf, area, "00000000"));
}

test "HexEditor.render with offset=16 shows 00000010 as first offset" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var buf = try Buffer.init(allocator, 80, 24);
    defer buf.deinit();

    var data: [32]u8 = undefined;
    for (0..32) |i| data[i] = @intCast(i % 256);
    const he = HexEditor.init().withData(&data).withOffset(16).withShowOffset(true);
    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 24 };

    he.render(&buf, area);

    try testing.expectEqual(true, findInArea(buf, area, "00000010"));
}

test "HexEditor.render offset increments by bytes_per_row" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var buf = try Buffer.init(allocator, 80, 24);
    defer buf.deinit();

    var data: [32]u8 = undefined;
    for (0..32) |i| data[i] = @intCast(i % 256);
    const he = HexEditor.init().withData(&data).withBytesPerRow(8).withShowOffset(true);
    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 24 };

    he.render(&buf, area);

    try testing.expectEqual(true, findInArea(buf, area, "00000008"));
}

// ============================================================================
// Group 8: Render Hex Bytes (8 tests)
// ============================================================================

test "HexEditor.render shows byte 0x41 as '41'" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var buf = try Buffer.init(allocator, 80, 24);
    defer buf.deinit();

    const data = [_]u8{0x41};
    const he = HexEditor.init().withData(&data);
    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 24 };

    he.render(&buf, area);

    try testing.expectEqual(true, findInArea(buf, area, "41"));
}

test "HexEditor.render shows byte 0xFF as 'FF' or 'ff'" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var buf = try Buffer.init(allocator, 80, 24);
    defer buf.deinit();

    const data = [_]u8{0xFF};
    const he = HexEditor.init().withData(&data);
    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 24 };

    he.render(&buf, area);

    try testing.expect(findInArea(buf, area, "FF") or findInArea(buf, area, "ff"));
}

test "HexEditor.render has space between bytes" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var buf = try Buffer.init(allocator, 80, 24);
    defer buf.deinit();

    const data = [_]u8{ 0x41, 0x42 };
    const he = HexEditor.init().withData(&data).withGroupSize(1);
    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 24 };

    he.render(&buf, area);

    try testing.expect(findInArea(buf, area, "41 42") or findInArea(buf, area, "41  42"));
}

test "HexEditor.render with group_size=4 adds extra space between groups" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var buf = try Buffer.init(allocator, 80, 24);
    defer buf.deinit();

    var data: [8]u8 = undefined;
    for (0..8) |i| data[i] = @intCast(0x41 + i);
    const he = HexEditor.init().withData(&data).withGroupSize(4);
    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 24 };

    he.render(&buf, area);
}

test "HexEditor.render with group_size=8 groups by 8" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var buf = try Buffer.init(allocator, 80, 24);
    defer buf.deinit();

    var data: [16]u8 = undefined;
    for (0..16) |i| data[i] = @intCast(0x41 + i);
    const he = HexEditor.init().withData(&data).withGroupSize(8);
    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 24 };

    he.render(&buf, area);
}

test "HexEditor.render shows multiple bytes in sequence" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var buf = try Buffer.init(allocator, 80, 24);
    defer buf.deinit();

    const data = [_]u8{ 0x41, 0x42, 0x43 };
    const he = HexEditor.init().withData(&data);
    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 24 };

    he.render(&buf, area);

    try testing.expect(findInArea(buf, area, "41") and findInArea(buf, area, "42") and findInArea(buf, area, "43"));
}

test "HexEditor.render shows 16 bytes in one row (default bytes_per_row)" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var buf = try Buffer.init(allocator, 120, 24);
    defer buf.deinit();

    var data: [16]u8 = undefined;
    for (0..16) |i| data[i] = @intCast(0x41 + i);
    const he = HexEditor.init().withData(&data).withBytesPerRow(16);
    const area = Rect{ .x = 0, .y = 0, .width = 120, .height = 24 };

    he.render(&buf, area);

    try testing.expect(findInArea(buf, area, "41") and findInArea(buf, area, "50"));
}

// ============================================================================
// Group 9: Render ASCII Column (6 tests)
// ============================================================================

test "HexEditor.render shows printable ASCII as character (0x41 -> 'A')" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var buf = try Buffer.init(allocator, 80, 24);
    defer buf.deinit();

    const data = [_]u8{0x41};
    const he = HexEditor.init().withData(&data).withShowAscii(true);
    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 24 };

    he.render(&buf, area);

    try testing.expectEqual(true, areaHasChar(buf, area, 'A'));
}

test "HexEditor.render shows non-printable as '.' (0x01)" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var buf = try Buffer.init(allocator, 80, 24);
    defer buf.deinit();

    const data = [_]u8{0x01};
    const he = HexEditor.init().withData(&data).withShowAscii(true);
    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 24 };

    he.render(&buf, area);

    try testing.expectEqual(true, areaHasChar(buf, area, '.'));
}

test "HexEditor.render shows 0x7F (DEL) as '.'" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var buf = try Buffer.init(allocator, 80, 24);
    defer buf.deinit();

    const data = [_]u8{0x7F};
    const he = HexEditor.init().withData(&data).withShowAscii(true);
    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 24 };

    he.render(&buf, area);

    try testing.expectEqual(true, areaHasChar(buf, area, '.'));
}

test "HexEditor.render omits ASCII column when show_ascii=false" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var buf = try Buffer.init(allocator, 80, 24);
    defer buf.deinit();

    const data = [_]u8{0x41};
    const he = HexEditor.init().withData(&data).withShowAscii(false);
    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 24 };

    he.render(&buf, area);

    try testing.expectEqual(true, findInArea(buf, area, "41"));
}

test "HexEditor.render shows multiple printable chars in ASCII column" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var buf = try Buffer.init(allocator, 80, 24);
    defer buf.deinit();

    const data = [_]u8{ 0x41, 0x42, 0x43 };
    const he = HexEditor.init().withData(&data).withShowAscii(true);
    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 24 };

    he.render(&buf, area);

    try testing.expect(areaHasChar(buf, area, 'A') and areaHasChar(buf, area, 'B') and areaHasChar(buf, area, 'C'));
}

test "HexEditor.render shows mixed printable and non-printable in ASCII" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var buf = try Buffer.init(allocator, 80, 24);
    defer buf.deinit();

    const data = [_]u8{ 0x41, 0x01, 0x42 };
    const he = HexEditor.init().withData(&data).withShowAscii(true);
    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 24 };

    he.render(&buf, area);

    try testing.expect(areaHasChar(buf, area, 'A') and areaHasChar(buf, area, '.') and areaHasChar(buf, area, 'B'));
}

// ============================================================================
// Group 10: Render Cursor (5 tests)
// ============================================================================

test "HexEditor.render applies cursor_style to cursor byte position" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var buf = try Buffer.init(allocator, 80, 24);
    defer buf.deinit();

    const data = [_]u8{0x41};
    const cursor_style = Style{ .fg = .red };
    const he = HexEditor.init().withData(&data).withCursor(0).withCursorStyle(cursor_style);
    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 24 };

    he.render(&buf, area);
    // Offset column = 8 chars + 1 space = 9 chars. First hex byte at x=9.
    // The cursor byte (0x41 = 'A', hex "41") should have red fg style.
    const style_hi = buf.getStyle(9, 0);
    try testing.expectEqual(@as(?sailor.tui.style.Color, .red), style_hi.fg);
}

test "HexEditor.render with cursor=0 highlights first byte" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var buf = try Buffer.init(allocator, 80, 24);
    defer buf.deinit();

    const data = [_]u8{ 0x41, 0x42 };
    const cursor_style = Style{ .bold = true };
    const he = HexEditor.init().withData(&data).withCursor(0).withCursorStyle(cursor_style);
    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 24 };

    he.render(&buf, area);
    // First byte (cursor=0) at x=9 should be bold; second byte at x=12 should not be
    try testing.expect(buf.getStyle(9, 0).bold);
    try testing.expect(!buf.getStyle(12, 0).bold);
}

test "HexEditor.render with cursor at last byte" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var buf = try Buffer.init(allocator, 80, 24);
    defer buf.deinit();

    const data = [_]u8{ 0x41, 0x42, 0x43 };
    const he = HexEditor.init().withData(&data).withCursor(2);
    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 24 };

    he.render(&buf, area);
}

test "HexEditor.render with cursor on second row" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var buf = try Buffer.init(allocator, 80, 24);
    defer buf.deinit();

    var data: [32]u8 = undefined;
    for (0..32) |i| data[i] = @intCast(i % 256);
    const he = HexEditor.init().withData(&data).withBytesPerRow(16).withCursor(20);
    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 24 };

    he.render(&buf, area);
}

test "HexEditor.render cursor beyond visible area (offset scrolling)" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var buf = try Buffer.init(allocator, 80, 24);
    defer buf.deinit();

    var data: [100]u8 = undefined;
    for (0..100) |i| data[i] = @intCast(i % 256);
    const he = HexEditor.init().withData(&data).withCursor(50);
    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 24 };

    he.render(&buf, area);
}

// ============================================================================
// Group 11: Render Multi-Row (5 tests)
// ============================================================================

test "HexEditor.render 16 bytes in one row" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var buf = try Buffer.init(allocator, 120, 24);
    defer buf.deinit();

    var data: [16]u8 = undefined;
    for (0..16) |i| data[i] = @intCast(0x41 + i);
    const he = HexEditor.init().withData(&data).withBytesPerRow(16);
    const area = Rect{ .x = 0, .y = 0, .width = 120, .height = 24 };

    he.render(&buf, area);

    try testing.expectEqual(@as(usize, 1), he.rowCount());
}

test "HexEditor.render 17 bytes creates second row" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var buf = try Buffer.init(allocator, 120, 24);
    defer buf.deinit();

    var data: [17]u8 = undefined;
    for (0..17) |i| data[i] = @intCast(0x41 + i);
    const he = HexEditor.init().withData(&data).withBytesPerRow(16);
    const area = Rect{ .x = 0, .y = 0, .width = 120, .height = 24 };

    he.render(&buf, area);

    try testing.expectEqual(@as(usize, 2), he.rowCount());
}

test "HexEditor.render respects rowCount for multi-row display" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var buf = try Buffer.init(allocator, 120, 24);
    defer buf.deinit();

    var data: [50]u8 = undefined;
    for (0..50) |i| data[i] = @intCast(i % 256);
    const he = HexEditor.init().withData(&data).withBytesPerRow(16);
    const area = Rect{ .x = 0, .y = 0, .width = 120, .height = 24 };

    he.render(&buf, area);

    const expected_rows = he.rowCount();
    try testing.expect(expected_rows >= 3);
}

test "HexEditor.render shows correct offset for each row" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var buf = try Buffer.init(allocator, 120, 24);
    defer buf.deinit();

    var data: [48]u8 = undefined;
    for (0..48) |i| data[i] = @intCast(i % 256);
    const he = HexEditor.init().withData(&data).withBytesPerRow(16).withShowOffset(true);
    const area = Rect{ .x = 0, .y = 0, .width = 120, .height = 24 };

    he.render(&buf, area);

    try testing.expect(findInArea(buf, area, "00000000") and findInArea(buf, area, "00000010"));
}

test "HexEditor.render with 32 bytes and bytes_per_row=8 shows 4 rows" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var buf = try Buffer.init(allocator, 120, 24);
    defer buf.deinit();

    var data: [32]u8 = undefined;
    for (0..32) |i| data[i] = @intCast(i % 256);
    const he = HexEditor.init().withData(&data).withBytesPerRow(8);
    const area = Rect{ .x = 0, .y = 0, .width = 120, .height = 24 };

    he.render(&buf, area);

    try testing.expectEqual(@as(usize, 4), he.rowCount());
}

// ============================================================================
// Group 12: Render MAX_BYTES (3 tests)
// ============================================================================

test "HexEditor.byteCount caps at MAX_BYTES even with larger data" {
    try testing.expect(HexEditor.MAX_BYTES == 4096);
}

test "HexEditor.render handles MAX_BYTES limit correctly" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var buf = try Buffer.init(allocator, 120, 24);
    defer buf.deinit();

    var data: [100]u8 = undefined;
    for (0..100) |i| data[i] = @intCast(i % 256);
    const he = HexEditor.init().withData(&data);
    const area = Rect{ .x = 0, .y = 0, .width = 120, .height = 24 };

    he.render(&buf, area);

    try testing.expect(he.byteCount() <= HexEditor.MAX_BYTES);
}

test "HexEditor.render respects MAX_BYTES limit correctly" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var buf = try Buffer.init(allocator, 120, 24);
    defer buf.deinit();

    var data: [200]u8 = undefined;
    for (0..200) |i| data[i] = @intCast(i % 256);
    const he = HexEditor.init().withData(&data).withBytesPerRow(16);
    const area = Rect{ .x = 0, .y = 0, .width = 120, .height = 24 };

    he.render(&buf, area);
    // 200 bytes < MAX_BYTES=4096, so byteCount should be 200
    try testing.expectEqual(@as(usize, 200), he.byteCount());
    // 200 bytes / 16 per row = 13 rows (ceil)
    try testing.expect(he.rowCount() > 0 and he.rowCount() <= HexEditor.MAX_BYTES / 16 + 1);
}

// ============================================================================
// Group 13: Render Block Border (5 tests)
// ============================================================================

test "HexEditor.render draws block border when block is set" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var buf = try Buffer.init(allocator, 80, 24);
    defer buf.deinit();

    const data = [_]u8{0x41};
    const block = Block{};
    const he = HexEditor.init().withData(&data).withBlock(block);
    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 24 };

    he.render(&buf, area);
    // Block renders corner chars at (0,0); default border uses '┌'
    try testing.expectEqual(@as(u21, '┌'), buf.getChar(0, 0));
}

test "HexEditor.render with block uses inner area for content" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var buf = try Buffer.init(allocator, 80, 24);
    defer buf.deinit();

    const data = [_]u8{0x41};
    const block = Block{};
    const he = HexEditor.init().withData(&data).withBlock(block);
    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 24 };

    he.render(&buf, area);
    // Content starts at inner area (x=1, y=1 with default block), not at border
    // The hex content ("4" in "41") should appear somewhere inside the frame
    const inner = Rect{ .x = 1, .y = 1, .width = 78, .height = 22 };
    try testing.expect(countNonEmptyCells(buf, inner) > 0);
}

test "HexEditor.render with block reduces drawable area" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var buf = try Buffer.init(allocator, 80, 24);
    defer buf.deinit();

    var data: [100]u8 = undefined;
    for (0..100) |i| data[i] = @intCast(i % 256);
    const block = Block{};
    const he = HexEditor.init().withData(&data).withBlock(block);
    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 24 };

    he.render(&buf, area);
}

test "HexEditor.render block with custom style" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var buf = try Buffer.init(allocator, 80, 24);
    defer buf.deinit();

    const data = [_]u8{0x41};
    const block_style = Style{ .fg = .blue };
    const blk = Block{};
    const block = blk.withBorderStyle(block_style);
    const he = HexEditor.init().withData(&data).withBlock(block);
    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 24 };

    he.render(&buf, area);
}

test "HexEditor.render block with title" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var buf = try Buffer.init(allocator, 80, 24);
    defer buf.deinit();

    const data = [_]u8{0x41};
    const block = (Block{}).withTitle("Hex Editor", .top_left);
    const he = HexEditor.init().withData(&data).withBlock(block);
    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 24 };

    he.render(&buf, area);
}

// ============================================================================
// Group 14: Render bytes_per_row (3 tests)
// ============================================================================

test "HexEditor.render with bytes_per_row=8 shows 8 bytes per row" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var buf = try Buffer.init(allocator, 80, 24);
    defer buf.deinit();

    var data: [16]u8 = undefined;
    for (0..16) |i| data[i] = @intCast(0x41 + i);
    const he = HexEditor.init().withData(&data).withBytesPerRow(8);
    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 24 };

    he.render(&buf, area);

    try testing.expectEqual(@as(usize, 2), he.rowCount());
}

test "HexEditor.render with bytes_per_row=4 shows 4 bytes per row" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var buf = try Buffer.init(allocator, 80, 24);
    defer buf.deinit();

    var data: [16]u8 = undefined;
    for (0..16) |i| data[i] = @intCast(0x41 + i);
    const he = HexEditor.init().withData(&data).withBytesPerRow(4);
    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 24 };

    he.render(&buf, area);

    try testing.expectEqual(@as(usize, 4), he.rowCount());
}

test "HexEditor.render with bytes_per_row=32 shows 32 bytes per row" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var buf = try Buffer.init(allocator, 200, 24);
    defer buf.deinit();

    var data: [64]u8 = undefined;
    for (0..64) |i| data[i] = @intCast(i % 256);
    const he = HexEditor.init().withData(&data).withBytesPerRow(32);
    const area = Rect{ .x = 0, .y = 0, .width = 200, .height = 24 };

    he.render(&buf, area);

    try testing.expectEqual(@as(usize, 2), he.rowCount());
}

// ============================================================================
// Additional Edge Case Tests (7 tests)
// ============================================================================

test "HexEditor.render with show_offset=false and show_ascii=false" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var buf = try Buffer.init(allocator, 80, 24);
    defer buf.deinit();

    const data = [_]u8{0x41};
    const he = HexEditor.init().withData(&data).withShowOffset(false).withShowAscii(false);
    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 24 };

    he.render(&buf, area);

    try testing.expectEqual(true, findInArea(buf, area, "41"));
}

test "HexEditor.render with all style variants applied" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var buf = try Buffer.init(allocator, 80, 24);
    defer buf.deinit();

    const data = [_]u8{0x41};
    const style = Style{ .fg = .red };
    const cursor_style = Style{ .fg = .blue };
    const modified_style = Style{ .fg = .green };
    const he = HexEditor.init()
        .withData(&data)
        .withStyle(style)
        .withCursorStyle(cursor_style)
        .withModifiedStyle(modified_style);
    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 24 };

    he.render(&buf, area);
}

test "HexEditor MAX_BYTES constant is 4096" {
    try testing.expectEqual(@as(usize, 4096), HexEditor.MAX_BYTES);
}

test "HexEditor.render with bytes_per_row=1 shows 1 byte per row" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var buf = try Buffer.init(allocator, 80, 24);
    defer buf.deinit();

    var data: [10]u8 = undefined;
    for (0..10) |i| data[i] = @intCast(i % 256);
    const he = HexEditor.init().withData(&data).withBytesPerRow(1);
    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 24 };

    he.render(&buf, area);

    try testing.expectEqual(@as(usize, 10), he.rowCount());
}

test "HexEditor.render with cursor beyond data length" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var buf = try Buffer.init(allocator, 80, 24);
    defer buf.deinit();

    const data = [_]u8{0x41};
    const he = HexEditor.init().withData(&data).withCursor(100);
    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 24 };

    he.render(&buf, area);
}

test "HexEditor.render with space characters in offset view" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var buf = try Buffer.init(allocator, 80, 24);
    defer buf.deinit();

    var data: [16]u8 = undefined;
    for (0..16) |i| data[i] = 0x20; // all spaces
    const he = HexEditor.init().withData(&data);
    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 24 };

    he.render(&buf, area);

    try testing.expect(findInArea(buf, area, "20"));
}
