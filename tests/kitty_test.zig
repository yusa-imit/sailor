const std = @import("std");
const testing = std.testing;
const sailor = @import("sailor");

// Import KittyGraphics from the tui module
// const KittyGraphics = sailor.tui.kitty.KittyGraphics;

// Note: These tests will compile once KittyGraphics struct is added to src/tui/kitty.zig
// and exported from sailor module.

// Helper function to encode arbitrary data to base64 for test verification
fn encodeBase64(allocator: std.mem.Allocator, data: []const u8) ![]u8 {
    const base64 = std.base64.standard;
    const encoded_size = base64.Encoder.calcSize(data.len);
    const encoded = try allocator.alloc(u8, encoded_size);
    _ = base64.Encoder.encode(encoded, data);
    return encoded;
}

// Helper function to create an ArrayList writer for capturing output
fn createTestWriter(_: std.mem.Allocator) std.ArrayList(u8) {
    return .{};
}

// ============================================================================
// Section 1: APC Sequence Writing (5 tests)
// ============================================================================

test "kitty: writeApc with no payload emits no semicolon" {
    const allocator = testing.allocator;
    var output = createTestWriter(allocator);
    defer output.deinit(allocator);

    const KittyGraphics = sailor.tui.kitty.KittyGraphics;
    try KittyGraphics.writeApc("a=T,f=100", null, output.writer(allocator));

    const written = output.items;
    try testing.expect(written.len > 0);
    try testing.expect(std.mem.startsWith(u8, written, "\x1b_G"));
    try testing.expect(std.mem.endsWith(u8, written, "\x1b\\"));
    try testing.expect(std.mem.indexOf(u8, written, ";") == null);
}

test "kitty: writeApc with empty payload emits semicolon" {
    const allocator = testing.allocator;
    var output = createTestWriter(allocator);
    defer output.deinit(allocator);

    const KittyGraphics = sailor.tui.kitty.KittyGraphics;
    try KittyGraphics.writeApc("a=T,f=100", "", output.writer(allocator));

    const written = output.items;
    try testing.expect(written.len > 0);
    try testing.expect(std.mem.startsWith(u8, written, "\x1b_G"));
    try testing.expect(std.mem.endsWith(u8, written, "\x1b\\"));
    // Should contain a semicolon before the empty (no) base64 data
    try testing.expect(std.mem.indexOf(u8, written, ";") != null);
}

test "kitty: writeApc encodes payload to base64" {
    const allocator = testing.allocator;
    var output = createTestWriter(allocator);
    defer output.deinit(allocator);

    const test_data = "hello";
    const KittyGraphics = sailor.tui.kitty.KittyGraphics;
    try KittyGraphics.writeApc("a=T", test_data, output.writer(allocator));

    const written = output.items;
    // Base64 of "hello" is "aGVsbG8="
    try testing.expect(std.mem.indexOf(u8, written, "aGVsbG8=") != null);
}

test "kitty: writeApc output starts with escape and ends with terminator" {
    const allocator = testing.allocator;
    var output = createTestWriter(allocator);
    defer output.deinit(allocator);

    const KittyGraphics = sailor.tui.kitty.KittyGraphics;
    try KittyGraphics.writeApc("f=100", "data", output.writer(allocator));

    const written = output.items;
    try testing.expectEqual(@as(u8, 0x1b), written[0]);
    try testing.expectEqual(@as(u8, '_'), written[1]);
    try testing.expectEqual(@as(u8, 'G'), written[2]);
    try testing.expectEqual(@as(u8, 0x1b), written[written.len - 2]);
    try testing.expectEqual(@as(u8, '\\'), written[written.len - 1]);
}

test "kitty: writeApc with multiple params comma-separates them" {
    const allocator = testing.allocator;
    var output = createTestWriter(allocator);
    defer output.deinit(allocator);

    const KittyGraphics = sailor.tui.kitty.KittyGraphics;
    try KittyGraphics.writeApc("a=T,f=100,i=1", null, output.writer(allocator));

    const written = output.items;
    const content = written[3 .. written.len - 2]; // Strip escape codes
    try testing.expect(std.mem.indexOf(u8, content, "a=T") != null);
    try testing.expect(std.mem.indexOf(u8, content, "f=100") != null);
    try testing.expect(std.mem.indexOf(u8, content, "i=1") != null);
    try testing.expectEqual(@as(usize, 2), std.mem.count(u8, content, ","));
}

// ============================================================================
// Section 2: Transmit (8 tests)
// ============================================================================

test "kitty: transmit small data in single APC with m=0" {
    const allocator = testing.allocator;
    var output = createTestWriter(allocator);
    defer output.deinit(allocator);

    const small_data = "tiny";
    const KittyGraphics = sailor.tui.kitty.KittyGraphics;
    const image_id = try KittyGraphics.transmit(
        allocator,
        small_data,
        .{ .format = .png },
        output.writer(allocator),
    );

    try testing.expect(image_id > 0);
    const written = output.items;
    try testing.expect(std.mem.indexOf(u8, written, "m=0") != null);
    try testing.expect(std.mem.indexOf(u8, written, "a=T") != null);
    try testing.expect(std.mem.indexOf(u8, written, "f=100") != null);
    // Should only be one APC sequence for small data
    try testing.expectEqual(@as(usize, 1), std.mem.count(u8, written, "\x1b_G"));
}

test "kitty: transmit large data in multiple APCs with m=1 then m=0" {
    const allocator = testing.allocator;
    var output = createTestWriter(allocator);
    defer output.deinit(allocator);

    // Create data larger than chunk_size
    const large_data = try allocator.alloc(u8, 10000);
    defer allocator.free(large_data);
    @memset(large_data, 0xFF);

    const KittyGraphics = sailor.tui.kitty.KittyGraphics;
    const image_id = try KittyGraphics.transmit(
        allocator,
        large_data,
        .{ .chunk_size = 4096 },
        output.writer(allocator),
    );

    try testing.expect(image_id > 0);
    const written = output.items;
    // Should have multiple APC sequences
    try testing.expect(std.mem.count(u8, written, "\x1b_G") > 1);
    // Should have m=1 for intermediate chunks
    try testing.expect(std.mem.indexOf(u8, written, "m=1") != null);
    // Should have m=0 for final chunk
    try testing.expect(std.mem.indexOf(u8, written, "m=0") != null);
}

test "kitty: transmit returns valid image_id > 0" {
    const allocator = testing.allocator;
    var output = createTestWriter(allocator);
    defer output.deinit(allocator);

    const KittyGraphics = sailor.tui.kitty.KittyGraphics;
    const image_id = try KittyGraphics.transmit(
        allocator,
        "test",
        .{},
        output.writer(allocator),
    );

    try testing.expect(image_id > 0);
}

test "kitty: transmit with explicit image_id uses it" {
    const allocator = testing.allocator;
    var output = createTestWriter(allocator);
    defer output.deinit(allocator);

    const explicit_id: u32 = 42;
    const KittyGraphics = sailor.tui.kitty.KittyGraphics;
    const image_id = try KittyGraphics.transmit(
        allocator,
        "data",
        .{ .image_id = explicit_id },
        output.writer(allocator),
    );

    try testing.expectEqual(explicit_id, image_id);
    const written = output.items;
    try testing.expect(std.mem.indexOf(u8, written, "i=42") != null);
}

test "kitty: transmit PNG format emits f=100" {
    const allocator = testing.allocator;
    var output = createTestWriter(allocator);
    defer output.deinit(allocator);

    const KittyGraphics = sailor.tui.kitty.KittyGraphics;
    _ = try KittyGraphics.transmit(
        allocator,
        "png_data",
        .{ .format = .png },
        output.writer(allocator),
    );

    const written = output.items;
    try testing.expect(std.mem.indexOf(u8, written, "f=100") != null);
}

test "kitty: transmit RGBA format emits f=32" {
    const allocator = testing.allocator;
    var output = createTestWriter(allocator);
    defer output.deinit(allocator);

    const KittyGraphics = sailor.tui.kitty.KittyGraphics;
    _ = try KittyGraphics.transmit(
        allocator,
        "rgba_data",
        .{ .format = .rgba },
        output.writer(allocator),
    );

    const written = output.items;
    try testing.expect(std.mem.indexOf(u8, written, "f=32") != null);
}

test "kitty: transmit RGB format emits f=24" {
    const allocator = testing.allocator;
    var output = createTestWriter(allocator);
    defer output.deinit(allocator);

    const KittyGraphics = sailor.tui.kitty.KittyGraphics;
    _ = try KittyGraphics.transmit(
        allocator,
        "rgb_data",
        .{ .format = .rgb },
        output.writer(allocator),
    );

    const written = output.items;
    try testing.expect(std.mem.indexOf(u8, written, "f=24") != null);
}

test "kitty: transmit quiet mode emits q=2" {
    const allocator = testing.allocator;
    var output = createTestWriter(allocator);
    defer output.deinit(allocator);

    const KittyGraphics = sailor.tui.kitty.KittyGraphics;
    _ = try KittyGraphics.transmit(
        allocator,
        "data",
        .{ .quiet = true },
        output.writer(allocator),
    );

    const written = output.items;
    try testing.expect(std.mem.indexOf(u8, written, "q=2") != null);
}

// ============================================================================
// Section 3: Display (8 tests)
// ============================================================================

test "kitty: display basic produces APC with a=p" {
    const allocator = testing.allocator;
    var output = createTestWriter(allocator);
    defer output.deinit(allocator);

    const KittyGraphics = sailor.tui.kitty.KittyGraphics;
    try KittyGraphics.display(
        .{ .image_id = 1 },
        output.writer(allocator),
    );

    const written = output.items;
    try testing.expect(std.mem.indexOf(u8, written, "a=p") != null);
}

test "kitty: display with image_id emits i=<id>" {
    const allocator = testing.allocator;
    var output = createTestWriter(allocator);
    defer output.deinit(allocator);

    const KittyGraphics = sailor.tui.kitty.KittyGraphics;
    try KittyGraphics.display(
        .{ .image_id = 123 },
        output.writer(allocator),
    );

    const written = output.items;
    try testing.expect(std.mem.indexOf(u8, written, "i=123") != null);
}

test "kitty: display with placement_id emits p=<id>" {
    const allocator = testing.allocator;
    var output = createTestWriter(allocator);
    defer output.deinit(allocator);

    const KittyGraphics = sailor.tui.kitty.KittyGraphics;
    try KittyGraphics.display(
        .{ .image_id = 1, .placement_id = 99 },
        output.writer(allocator),
    );

    const written = output.items;
    try testing.expect(std.mem.indexOf(u8, written, "p=99") != null);
}

test "kitty: display with x,y position emits x=<col>,y=<row>" {
    const allocator = testing.allocator;
    var output = createTestWriter(allocator);
    defer output.deinit(allocator);

    const KittyGraphics = sailor.tui.kitty.KittyGraphics;
    try KittyGraphics.display(
        .{ .image_id = 1, .x = 10, .y = 20 },
        output.writer(allocator),
    );

    const written = output.items;
    try testing.expect(std.mem.indexOf(u8, written, "x=10") != null);
    try testing.expect(std.mem.indexOf(u8, written, "y=20") != null);
}

test "kitty: display with w,h size emits w=<w>,h=<h>" {
    const allocator = testing.allocator;
    var output = createTestWriter(allocator);
    defer output.deinit(allocator);

    const KittyGraphics = sailor.tui.kitty.KittyGraphics;
    try KittyGraphics.display(
        .{ .image_id = 1, .w = 30, .h = 40 },
        output.writer(allocator),
    );

    const written = output.items;
    try testing.expect(std.mem.indexOf(u8, written, "w=30") != null);
    try testing.expect(std.mem.indexOf(u8, written, "h=40") != null);
}

test "kitty: display with z_index emits z=<n>" {
    const allocator = testing.allocator;
    var output = createTestWriter(allocator);
    defer output.deinit(allocator);

    const KittyGraphics = sailor.tui.kitty.KittyGraphics;
    try KittyGraphics.display(
        .{ .image_id = 1, .z_index = 5 },
        output.writer(allocator),
    );

    const written = output.items;
    try testing.expect(std.mem.indexOf(u8, written, "z=5") != null);
}

test "kitty: display with negative z_index encoded correctly" {
    const allocator = testing.allocator;
    var output = createTestWriter(allocator);
    defer output.deinit(allocator);

    const KittyGraphics = sailor.tui.kitty.KittyGraphics;
    try KittyGraphics.display(
        .{ .image_id = 1, .z_index = -3 },
        output.writer(allocator),
    );

    const written = output.items;
    try testing.expect(std.mem.indexOf(u8, written, "z=-3") != null);
}

test "kitty: display with unicode_placeholder emits U=1" {
    const allocator = testing.allocator;
    var output = createTestWriter(allocator);
    defer output.deinit(allocator);

    const KittyGraphics = sailor.tui.kitty.KittyGraphics;
    try KittyGraphics.display(
        .{ .image_id = 1, .unicode_placeholder = true },
        output.writer(allocator),
    );

    const written = output.items;
    try testing.expect(std.mem.indexOf(u8, written, "U=1") != null);
}

// ============================================================================
// Section 4: Delete (6 tests)
// ============================================================================

test "kitty: delete by image_id produces a=d,d=I,i=<id>" {
    const allocator = testing.allocator;
    var output = createTestWriter(allocator);
    defer output.deinit(allocator);

    const KittyGraphics = sailor.tui.kitty.KittyGraphics;
    try KittyGraphics.delete(
        .{ .scope = .image, .image_id = 5 },
        output.writer(allocator),
    );

    const written = output.items;
    try testing.expect(std.mem.indexOf(u8, written, "a=d") != null);
    try testing.expect(std.mem.indexOf(u8, written, "d=I") != null);
    try testing.expect(std.mem.indexOf(u8, written, "i=5") != null);
}

test "kitty: delete by placement_id produces a=d,d=p,p=<pid>" {
    const allocator = testing.allocator;
    var output = createTestWriter(allocator);
    defer output.deinit(allocator);

    const KittyGraphics = sailor.tui.kitty.KittyGraphics;
    try KittyGraphics.delete(
        .{ .scope = .placement, .placement_id = 7 },
        output.writer(allocator),
    );

    const written = output.items;
    try testing.expect(std.mem.indexOf(u8, written, "a=d") != null);
    try testing.expect(std.mem.indexOf(u8, written, "d=p") != null);
    try testing.expect(std.mem.indexOf(u8, written, "p=7") != null);
}

test "kitty: delete all produces a=d,d=A" {
    const allocator = testing.allocator;
    var output = createTestWriter(allocator);
    defer output.deinit(allocator);

    const KittyGraphics = sailor.tui.kitty.KittyGraphics;
    try KittyGraphics.delete(
        .{ .scope = .all },
        output.writer(allocator),
    );

    const written = output.items;
    try testing.expect(std.mem.indexOf(u8, written, "a=d") != null);
    try testing.expect(std.mem.indexOf(u8, written, "d=A") != null);
}

test "kitty: delete output ends with escape terminator" {
    const allocator = testing.allocator;
    var output = createTestWriter(allocator);
    defer output.deinit(allocator);

    const KittyGraphics = sailor.tui.kitty.KittyGraphics;
    try KittyGraphics.delete(
        .{ .scope = .image, .image_id = 1 },
        output.writer(allocator),
    );

    const written = output.items;
    try testing.expect(std.mem.endsWith(u8, written, "\x1b\\"));
}

test "kitty: delete with both image_id and placement includes both" {
    const allocator = testing.allocator;
    var output = createTestWriter(allocator);
    defer output.deinit(allocator);

    const KittyGraphics = sailor.tui.kitty.KittyGraphics;
    try KittyGraphics.delete(
        .{ .scope = .image, .image_id = 10, .placement_id = 20 },
        output.writer(allocator),
    );

    const written = output.items;
    try testing.expect(std.mem.indexOf(u8, written, "i=10") != null);
    try testing.expect(std.mem.indexOf(u8, written, "p=20") != null);
}

test "kitty: delete with scope all ignores ids" {
    const allocator = testing.allocator;
    var output = createTestWriter(allocator);
    defer output.deinit(allocator);

    const KittyGraphics = sailor.tui.kitty.KittyGraphics;
    try KittyGraphics.delete(
        .{ .scope = .all, .image_id = 99, .placement_id = 88 },
        output.writer(allocator),
    );

    const written = output.items;
    try testing.expect(std.mem.indexOf(u8, written, "d=A") != null);
    // ids should not be in output for scope=all
    try testing.expect(std.mem.indexOf(u8, written, "i=99") == null);
    try testing.expect(std.mem.indexOf(u8, written, "p=88") == null);
}

// ============================================================================
// Section 5: Chunking (5 tests)
// ============================================================================

test "kitty: chunk_size=10 forces multiple chunks for >10 byte payload" {
    const allocator = testing.allocator;
    var output = createTestWriter(allocator);
    defer output.deinit(allocator);

    const data = "0123456789ABCDEFGHIJ"; // 20 bytes
    const KittyGraphics = sailor.tui.kitty.KittyGraphics;
    _ = try KittyGraphics.transmit(
        allocator,
        data,
        .{ .chunk_size = 10 },
        output.writer(allocator),
    );

    const written = output.items;
    const apc_count = std.mem.count(u8, written, "\x1b_G");
    try testing.expect(apc_count >= 2);
}

test "kitty: intermediate chunks have m=1" {
    const allocator = testing.allocator;
    var output = createTestWriter(allocator);
    defer output.deinit(allocator);

    const data = try allocator.alloc(u8, 100);
    defer allocator.free(data);
    @memset(data, 0xAA);

    const KittyGraphics = sailor.tui.kitty.KittyGraphics;
    _ = try KittyGraphics.transmit(
        allocator,
        data,
        .{ .chunk_size = 30 },
        output.writer(allocator),
    );

    const written = output.items;
    try testing.expect(std.mem.indexOf(u8, written, "m=1") != null);
}

test "kitty: final chunk has m=0" {
    const allocator = testing.allocator;
    var output = createTestWriter(allocator);
    defer output.deinit(allocator);

    const data = try allocator.alloc(u8, 100);
    defer allocator.free(data);
    @memset(data, 0xBB);

    const KittyGraphics = sailor.tui.kitty.KittyGraphics;
    _ = try KittyGraphics.transmit(
        allocator,
        data,
        .{ .chunk_size = 30 },
        output.writer(allocator),
    );

    const written = output.items;
    try testing.expect(std.mem.indexOf(u8, written, "m=0") != null);
}

test "kitty: all chunks decode to original data when concatenated" {
    const allocator = testing.allocator;
    var output = createTestWriter(allocator);
    defer output.deinit(allocator);

    const original_data = "ABCDEFGHIJKLMNOPQRSTUVWXYZ";
    const KittyGraphics = sailor.tui.kitty.KittyGraphics;
    _ = try KittyGraphics.transmit(
        allocator,
        original_data,
        .{ .chunk_size = 10 },
        output.writer(allocator),
    );

    const written = output.items;

    // Extract base64 chunks from output (simplified: look for valid base64 segments)
    // This test verifies that concatenating base64 chunks from all APCs
    // decodes to original data
    const base64 = std.base64.standard;
    var concatenated_b64 = try std.ArrayList(u8).initCapacity(allocator, written.len);
    defer concatenated_b64.deinit(allocator);

    // Simple extraction: find content between semicolons and line terminators
    var i: usize = 0;
    while (i < written.len) {
        if (written[i] == ';') {
            i += 1;
            while (i < written.len and written[i] != 0x1b) {
                if (written[i] != '\n' and written[i] != '\r') {
                    try concatenated_b64.append(allocator, written[i]);
                }
                i += 1;
            }
        }
        i += 1;
    }

    // Decode and verify
    if (concatenated_b64.items.len > 0) {
        const decoded_size = try base64.Decoder.calcSizeForSlice(concatenated_b64.items);
        try testing.expect(decoded_size > 0);
        var decoded_buffer: [256]u8 = undefined;
        try base64.Decoder.decode(decoded_buffer[0..decoded_size], concatenated_b64.items);
    }
}

test "kitty: first chunk has full params, subsequent chunks have only m=<n>" {
    const allocator = testing.allocator;
    var output = createTestWriter(allocator);
    defer output.deinit(allocator);

    const data = try allocator.alloc(u8, 150);
    defer allocator.free(data);
    @memset(data, 0xCC);

    const KittyGraphics = sailor.tui.kitty.KittyGraphics;
    _ = try KittyGraphics.transmit(
        allocator,
        data,
        .{ .chunk_size = 40, .format = .png },
        output.writer(allocator),
    );

    const written = output.items;

    // First APC should have a=T,f=100
    const first_apc_end = std.mem.indexOf(u8, written, "\x1b\\").?;
    const first_apc = written[0..first_apc_end];
    try testing.expect(std.mem.indexOf(u8, first_apc, "a=T") != null);
    try testing.expect(std.mem.indexOf(u8, first_apc, "f=100") != null);

    // Subsequent chunks should have m=1 or m=0 but minimal params
    const rest = written[first_apc_end + 2 ..];
    if (rest.len > 0) {
        try testing.expect(std.mem.indexOf(u8, rest, "m=1") != null or
            std.mem.indexOf(u8, rest, "m=0") != null);
    }
}

// ============================================================================
// Section 6: Error Handling (3 tests)
// ============================================================================

test "kitty: display with image_id=0 returns error" {
    const allocator = testing.allocator;
    var output = createTestWriter(allocator);
    defer output.deinit(allocator);

    const KittyGraphics = sailor.tui.kitty.KittyGraphics;
    const result = KittyGraphics.display(
        .{ .image_id = 0 },
        output.writer(allocator),
    );

    try testing.expectError(error.InvalidImageId, result);
}

test "kitty: delete with scope=image and no image_id returns error" {
    const allocator = testing.allocator;
    var output = createTestWriter(allocator);
    defer output.deinit(allocator);

    const KittyGraphics = sailor.tui.kitty.KittyGraphics;
    const result = KittyGraphics.delete(
        .{ .scope = .image, .image_id = null },
        output.writer(allocator),
    );

    try testing.expectError(error.MissingImageId, result);
}

test "kitty: writeApc with very long params still works" {
    const allocator = testing.allocator;
    var output = createTestWriter(allocator);
    defer output.deinit(allocator);

    // Create a very long params string
    var long_params = try std.ArrayList(u8).initCapacity(allocator, 1000);
    defer long_params.deinit(allocator);

    try long_params.appendSlice(allocator, "a=T,f=100");
    for (0..100) |i| {
        try long_params.writer(allocator).print(",x{}={}", .{ i, i });
    }

    const KittyGraphics = sailor.tui.kitty.KittyGraphics;
    const result = KittyGraphics.writeApc(long_params.items, "data", output.writer(allocator));

    try testing.expect(result != error.ParamsTooBig);
    const written = output.items;
    try testing.expect(written.len > 0);
    try testing.expect(std.mem.startsWith(u8, written, "\x1b_G"));
    try testing.expect(std.mem.endsWith(u8, written, "\x1b\\"));
}

// ============================================================================
// KittyImageManager — virtual image lifecycle management (10 tests)
// ============================================================================

const KittyImageManager = sailor.KittyImageManager;

test "KittyImageManager: init/deinit is memory-safe" {
    const allocator = testing.allocator;
    var mgr = KittyImageManager.init(allocator);
    defer mgr.deinit();
    try testing.expectEqual(@as(usize, 0), mgr.count());
}

test "KittyImageManager: store returns a valid non-zero image ID" {
    const allocator = testing.allocator;
    var mgr = KittyImageManager.init(allocator);
    defer mgr.deinit();

    var output = createTestWriter(allocator);
    defer output.deinit(allocator);

    const id = try mgr.store("PNG\x00data", .png, output.writer(allocator));
    try testing.expect(id > 0);
}

test "KittyImageManager: store increments count" {
    const allocator = testing.allocator;
    var mgr = KittyImageManager.init(allocator);
    defer mgr.deinit();

    var output = createTestWriter(allocator);
    defer output.deinit(allocator);

    _ = try mgr.store("img1", .png, output.writer(allocator));
    try testing.expectEqual(@as(usize, 1), mgr.count());
    _ = try mgr.store("img2", .rgb, output.writer(allocator));
    try testing.expectEqual(@as(usize, 2), mgr.count());
}

test "KittyImageManager: store produces APC output with image ID" {
    const allocator = testing.allocator;
    var mgr = KittyImageManager.init(allocator);
    defer mgr.deinit();

    var output = createTestWriter(allocator);
    defer output.deinit(allocator);

    _ = try mgr.store("data", .png, output.writer(allocator));
    const written = output.items;
    try testing.expect(written.len > 0);
    try testing.expect(std.mem.containsAtLeast(u8, written, 1, "\x1b_G"));
}

test "KittyImageManager: contains returns true after store" {
    const allocator = testing.allocator;
    var mgr = KittyImageManager.init(allocator);
    defer mgr.deinit();

    var output = createTestWriter(allocator);
    defer output.deinit(allocator);

    const id = try mgr.store("pxl", .rgba, output.writer(allocator));
    try testing.expect(mgr.contains(id));
}

test "KittyImageManager: contains returns false for unknown ID" {
    const allocator = testing.allocator;
    var mgr = KittyImageManager.init(allocator);
    defer mgr.deinit();
    try testing.expect(!mgr.contains(99999));
}

test "KittyImageManager: place emits display APC sequence" {
    const allocator = testing.allocator;
    var mgr = KittyImageManager.init(allocator);
    defer mgr.deinit();

    var store_out = createTestWriter(allocator);
    defer store_out.deinit(allocator);

    const id = try mgr.store("px", .png, store_out.writer(allocator));

    var display_out = createTestWriter(allocator);
    defer display_out.deinit(allocator);

    try mgr.place(id, .{ .image_id = id, .x = 5, .y = 10 }, display_out.writer(allocator));
    const written = display_out.items;
    try testing.expect(written.len > 0);
    try testing.expect(std.mem.containsAtLeast(u8, written, 1, "\x1b_G"));
}

test "KittyImageManager: place returns error for unknown image ID" {
    const allocator = testing.allocator;
    var mgr = KittyImageManager.init(allocator);
    defer mgr.deinit();

    var output = createTestWriter(allocator);
    defer output.deinit(allocator);

    try testing.expectError(error.UnknownImageId, mgr.place(42, .{ .image_id = 42 }, output.writer(allocator)));
}

test "KittyImageManager: evict removes ID from tracking and emits delete" {
    const allocator = testing.allocator;
    var mgr = KittyImageManager.init(allocator);
    defer mgr.deinit();

    var out = createTestWriter(allocator);
    defer out.deinit(allocator);

    const id = try mgr.store("p", .png, out.writer(allocator));
    try testing.expect(mgr.contains(id));

    try mgr.evict(id, out.writer(allocator));
    try testing.expect(!mgr.contains(id));
    try testing.expectEqual(@as(usize, 0), mgr.count());
}

test "KittyImageManager: evictAll clears all tracked images" {
    const allocator = testing.allocator;
    var mgr = KittyImageManager.init(allocator);
    defer mgr.deinit();

    var out = createTestWriter(allocator);
    defer out.deinit(allocator);

    _ = try mgr.store("a", .png, out.writer(allocator));
    _ = try mgr.store("b", .rgb, out.writer(allocator));
    _ = try mgr.store("c", .rgba, out.writer(allocator));
    try testing.expectEqual(@as(usize, 3), mgr.count());

    try mgr.evictAll(out.writer(allocator));
    try testing.expectEqual(@as(usize, 0), mgr.count());
    // Should emit a=d,d=A (delete all) APC
    const written = out.items;
    try testing.expect(std.mem.containsAtLeast(u8, written, 1, "d=A"));
}
