/// Integration tests for Sixel and Kitty graphics protocols with TUI system
const std = @import("std");
const testing = std.testing;
const sailor = @import("sailor");

const Buffer = sailor.tui.Buffer;
const Rect = sailor.tui.Rect;
const SixelImage = sailor.tui.sixel.SixelImage;
const SixelEncoder = sailor.tui.sixel.SixelEncoder;
const KittyImage = sailor.tui.kitty.KittyImage;
const KittyEncoder = sailor.tui.kitty.KittyEncoder;

// ============================================================================
// Sixel Integration Tests
// ============================================================================

test "Sixel image encoding in buffer cell" {
    const allocator = testing.allocator;

    // Create small test image
    const pixels = [_]SixelImage.Color{
        .{ .r = 255, .g = 0, .b = 0 }, // Red
        .{ .r = 0, .g = 255, .b = 0 }, // Green
        .{ .r = 0, .g = 0, .b = 255 }, // Blue
        .{ .r = 255, .g = 255, .b = 0 }, // Yellow
    };

    const image = SixelImage{
        .width = 2,
        .height = 2,
        .pixels = &pixels,
    };

    // Encode to string
    var output: std.ArrayList(u8) = .{};
    defer output.deinit(allocator);

    const encoder = SixelEncoder{};
    try encoder.encode(allocator, image, output.writer(allocator));

    // Verify valid Sixel sequence
    const result = output.items;
    try testing.expect(std.mem.startsWith(u8, result, "\x1bPq"));
    try testing.expect(std.mem.endsWith(u8, result, "\x1b\\"));
    try testing.expect(result.len > 20); // Should have color definitions and data
}

test "Sixel rendering with buffer writeAll" {
    const allocator = testing.allocator;

    var buf = try Buffer.init(allocator, .{ .width = 40, .height = 10 });
    defer buf.deinit(allocator);

    // Create minimal image
    const pixels = [_]SixelImage.Color{
        .{ .r = 255, .g = 255, .b = 255 },
    };

    const image = SixelImage{
        .width = 1,
        .height = 1,
        .pixels = &pixels,
    };

    var output: std.ArrayList(u8) = .{};
    defer output.deinit(allocator);

    const encoder = SixelEncoder{};
    try encoder.encode(allocator, image, output.writer(allocator));

    // Sixel data can be stored as ANSI sequence in buffer notes
    // (Buffer doesn't natively support image display, but can hold escape codes)
    try testing.expect(output.items.len > 0);
}

test "Sixel transparency with TUI color system" {
    const allocator = testing.allocator;

    const pixels = [_]SixelImage.Color{
        .{ .r = 255, .g = 0, .b = 0, .a = 255 }, // Opaque red
        .{ .r = 0, .g = 255, .b = 0, .a = 0 }, // Transparent green
    };

    const image = SixelImage{
        .width = 2,
        .height = 1,
        .pixels = &pixels,
    };

    var output: std.ArrayList(u8) = .{};
    defer output.deinit(allocator);

    const encoder = SixelEncoder{ .use_transparency = true };
    try encoder.encode(allocator, image, output.writer(allocator));

    // Should encode with transparency handling
    try testing.expect(output.items.len > 0);
}

test "Sixel large image chunking" {
    const allocator = testing.allocator;

    // Create 100x100 image (10,000 pixels)
    var pixels = try allocator.alloc(SixelImage.Color, 10000);
    defer allocator.free(pixels);

    for (pixels) |*p| {
        p.* = .{ .r = 128, .g = 128, .b = 128 };
    }

    const image = SixelImage{
        .width = 100,
        .height = 100,
        .pixels = pixels,
    };

    var output: std.ArrayList(u8) = .{};
    defer output.deinit(allocator);

    const encoder = SixelEncoder{};
    try encoder.encode(allocator, image, output.writer(allocator));

    // Should handle large image without error
    try testing.expect(output.items.len > 1000);
    try testing.expect(std.mem.startsWith(u8, output.items, "\x1bPq"));
}

test "Sixel palette quantization integration" {
    const allocator = testing.allocator;

    // Create image with many colors
    var pixels: [256]SixelImage.Color = undefined;
    for (&pixels, 0..) |*p, i| {
        p.* = .{
            .r = @intCast(i),
            .g = @intCast((i * 2) % 256),
            .b = @intCast((i * 3) % 256),
        };
    }

    const image = SixelImage{
        .width = 16,
        .height = 16,
        .pixels = &pixels,
    };

    var output: std.ArrayList(u8) = .{};
    defer output.deinit(allocator);

    const encoder = SixelEncoder{ .max_colors = 64 };
    try encoder.encode(allocator, image, output.writer(allocator));

    // Should quantize to 64 colors
    try testing.expect(output.items.len > 0);
}

// ============================================================================
// Kitty Integration Tests
// ============================================================================

test "Kitty image encoding in buffer" {
    const allocator = testing.allocator;

    // Create 2x2 RGBA image
    const pixels = [_]u8{
        255, 0, 0, 255, // Red
        0, 255, 0, 255, // Green
        0, 0, 255, 255, // Blue
        255, 255, 0, 255, // Yellow
    };

    const image = KittyImage{
        .width = 2,
        .height = 2,
        .pixels = &pixels,
        .format = .rgba32,
    };

    var output: std.ArrayList(u8) = .{};
    defer output.deinit(allocator);

    var encoder = KittyEncoder.init(allocator);
    defer encoder.deinit();

    try encoder.encode(image, output.writer(allocator), .direct);

    // Verify Kitty escape sequence
    const result = output.items;
    try testing.expect(std.mem.startsWith(u8, result, "\x1b_G"));
    try testing.expect(std.mem.endsWith(u8, result, "\x1b\\"));
}

test "Kitty RGB24 vs RGBA32 formats" {
    const allocator = testing.allocator;

    // RGB24 data (3 bytes per pixel)
    const rgb_pixels = [_]u8{
        255, 0, 0, // Red
        0, 255, 0, // Green
    };

    const rgb_image = KittyImage{
        .width = 2,
        .height = 1,
        .pixels = &rgb_pixels,
        .format = .rgb24,
    };

    var rgb_output: std.ArrayList(u8) = .{};
    defer rgb_output.deinit(allocator);

    var encoder = KittyEncoder.init(allocator);
    defer encoder.deinit();

    try encoder.encode(rgb_image, rgb_output.writer(allocator), .direct);

    // RGBA32 data (4 bytes per pixel)
    const rgba_pixels = [_]u8{
        255, 0, 0, 255, // Red
        0, 255, 0, 255, // Green
    };

    const rgba_image = KittyImage{
        .width = 2,
        .height = 1,
        .pixels = &rgba_pixels,
        .format = .rgba32,
    };

    var rgba_output: std.ArrayList(u8) = .{};
    defer rgba_output.deinit(allocator);

    try encoder.encode(rgba_image, rgba_output.writer(allocator), .direct);

    // Both should produce valid sequences
    try testing.expect(rgb_output.items.len > 0);
    try testing.expect(rgba_output.items.len > 0);
    try testing.expect(rgb_output.items.len < rgba_output.items.len); // RGBA has more data
}

test "Kitty image placement positioning" {
    const allocator = testing.allocator;

    var encoder = KittyEncoder.init(allocator);
    defer encoder.deinit();

    var output: std.ArrayList(u8) = .{};
    defer output.deinit(allocator);

    try encoder.placeImage(123, 10, 5, 20, 10, output.writer(allocator));

    const result = output.items;

    // Should contain placement parameters
    try testing.expect(std.mem.startsWith(u8, result, "\x1b_G"));
    try testing.expect(std.mem.indexOf(u8, result, "a=p") != null); // placement action
    try testing.expect(std.mem.indexOf(u8, result, "i=123") != null); // image ID
}

test "Kitty image deletion" {
    const allocator = testing.allocator;

    var encoder = KittyEncoder.init(allocator);
    defer encoder.deinit();

    var output: std.ArrayList(u8) = .{};
    defer output.deinit(allocator);

    try encoder.deleteImage(456, output.writer(allocator));

    const result = output.items;

    // Should contain deletion command
    try testing.expect(std.mem.startsWith(u8, result, "\x1b_G"));
    try testing.expect(std.mem.indexOf(u8, result, "a=d") != null); // delete action
    try testing.expect(std.mem.indexOf(u8, result, "i=456") != null); // image ID
}

test "Kitty delete all images" {
    const allocator = testing.allocator;

    var encoder = KittyEncoder.init(allocator);
    defer encoder.deinit();

    var output: std.ArrayList(u8) = .{};
    defer output.deinit(allocator);

    try encoder.deleteAllImages(output.writer(allocator));

    const result = output.items;

    // Should contain delete-all command
    try testing.expect(std.mem.startsWith(u8, result, "\x1b_G"));
    try testing.expect(std.mem.indexOf(u8, result, "a=d") != null);
    try testing.expect(std.mem.indexOf(u8, result, "d=a") != null); // delete all
}

test "Kitty large image chunking" {
    const allocator = testing.allocator;

    // Create 200x200 RGBA image (160,000 bytes)
    var pixels = try allocator.alloc(u8, 200 * 200 * 4);
    defer allocator.free(pixels);

    @memset(pixels, 128); // Gray fill

    const image = KittyImage{
        .width = 200,
        .height = 200,
        .pixels = pixels,
        .format = .rgba32,
    };

    var output: std.ArrayList(u8) = .{};
    defer output.deinit(allocator);

    var encoder = KittyEncoder.init(allocator);
    defer encoder.deinit();

    try encoder.encode(image, output.writer(allocator), .direct);

    // Should produce chunked output (multiple m=1 chunks, last m=0)
    const result = output.items;
    try testing.expect(std.mem.indexOf(u8, result, "m=1") != null); // more chunks
    try testing.expect(result.len > 10000); // Base64 encoded data is large
}

test "Kitty transmission medium selection" {
    const allocator = testing.allocator;

    const pixels = [_]u8{
        255, 255, 255, 255,
    };

    const image = KittyImage{
        .width = 1,
        .height = 1,
        .pixels = &pixels,
        .format = .rgba32,
    };

    var encoder = KittyEncoder.init(allocator);
    defer encoder.deinit();

    // Test direct transmission
    var direct_output: std.ArrayList(u8) = .{};
    defer direct_output.deinit(allocator);
    try encoder.encode(image, direct_output.writer(allocator), .direct);
    try testing.expect(std.mem.indexOf(u8, direct_output.items, "t=d") != null);

    // Test file transmission
    var file_output: std.ArrayList(u8) = .{};
    defer file_output.deinit(allocator);
    try encoder.encode(image, file_output.writer(allocator), .file);
    try testing.expect(std.mem.indexOf(u8, file_output.items, "t=f") != null);

    // Test shared memory transmission
    var shmem_output: std.ArrayList(u8) = .{};
    defer shmem_output.deinit(allocator);
    try encoder.encode(image, shmem_output.writer(allocator), .shared_mem);
    try testing.expect(std.mem.indexOf(u8, shmem_output.items, "t=s") != null);
}

// ============================================================================
// Cross-Protocol Comparison Tests
// ============================================================================

test "Sixel vs Kitty output size comparison" {
    const allocator = testing.allocator;

    // Create same 10x10 image for both protocols
    var pixels_rgba: [400]u8 = undefined; // 10*10*4
    for (0..100) |i| {
        pixels_rgba[i * 4] = 255; // R
        pixels_rgba[i * 4 + 1] = 128; // G
        pixels_rgba[i * 4 + 2] = 64; // B
        pixels_rgba[i * 4 + 3] = 255; // A
    }

    var pixels_sixel: [100]SixelImage.Color = undefined;
    for (&pixels_sixel) |*p| {
        p.* = .{ .r = 255, .g = 128, .b = 64 };
    }

    // Encode with Sixel
    const sixel_image = SixelImage{
        .width = 10,
        .height = 10,
        .pixels = &pixels_sixel,
    };

    var sixel_output: std.ArrayList(u8) = .{};
    defer sixel_output.deinit(allocator);

    const sixel_encoder = SixelEncoder{};
    try sixel_encoder.encode(allocator, sixel_image, sixel_output.writer(allocator));

    // Encode with Kitty
    const kitty_image = KittyImage{
        .width = 10,
        .height = 10,
        .pixels = &pixels_rgba,
        .format = .rgba32,
    };

    var kitty_output: std.ArrayList(u8) = .{};
    defer kitty_output.deinit(allocator);

    var kitty_encoder = KittyEncoder.init(allocator);
    defer kitty_encoder.deinit();

    try kitty_encoder.encode(kitty_image, kitty_output.writer(allocator), .direct);

    // Both should produce output, sizes will vary based on encoding
    try testing.expect(sixel_output.items.len > 0);
    try testing.expect(kitty_output.items.len > 0);

    // Kitty base64 encoding typically produces larger output than Sixel
    // (but Kitty has better color fidelity without palette quantization)
}

test "Graphics protocol capability detection" {
    // Test detection functions don't crash
    _ = sailor.tui.sixel.detectSixelSupport();
    _ = sailor.tui.kitty.detectKittySupport();

    // Both should return bool without error
}
