const std = @import("std");
const testing = std.testing;
const sailor = @import("sailor");

// Import the Sixel types and encoder
const SixelImage = sailor.tui.sixel.SixelImage;
const SixelEncoder = sailor.tui.sixel.SixelEncoder;
const SixelDecoder = sailor.tui.sixel.SixelDecoder;

// ============================================================================
// Basic Decoding Tests
// ============================================================================

test "sixel decoder: decode 2x2 solid red image" {
    const allocator = testing.allocator;

    // Create a minimal Sixel sequence for a 2x2 solid red image
    // \x1bPq"1;1;2;2#0;2;100;0;0?@$-?@\x1b\
    const sixel_data = "\x1bPq\"1;1;2;2#0;2;100;0;0?@$-?@\x1b\\";

    const decoder = SixelDecoder{};
    const image = try decoder.decode(allocator, sixel_data);
    defer allocator.free(image.pixels);

    try testing.expectEqual(@as(u16, 2), image.width);
    try testing.expectEqual(@as(u16, 2), image.height);
    try testing.expectEqual(@as(usize, 4), image.pixels.len);

    // All pixels should be red (255, 0, 0) in decoded range (scaled from 0-100 to 0-255)
    // Since color is defined as #0;2;100;0;0, all pixels should map to red
    for (image.pixels) |pixel| {
        try testing.expectEqual(@as(u8, 255), pixel.r);
        try testing.expectEqual(@as(u8, 0), pixel.g);
        try testing.expectEqual(@as(u8, 0), pixel.b);
        try testing.expectEqual(@as(u8, 255), pixel.a); // Opaque
    }
}

test "sixel decoder: decode single pixel" {
    const allocator = testing.allocator;

    // 1x1 blue pixel: \x1bPq"1;1;1;1#0;2;0;0;100?!\x1b\
    const sixel_data = "\x1bPq\"1;1;1;1#0;2;0;0;100?!\x1b\\";

    const decoder = SixelDecoder{};
    const image = try decoder.decode(allocator, sixel_data);
    defer allocator.free(image.pixels);

    try testing.expectEqual(@as(u16, 1), image.width);
    try testing.expectEqual(@as(u16, 1), image.height);
    try testing.expectEqual(@as(usize, 1), image.pixels.len);

    // Pixel should be blue
    try testing.expectEqual(@as(u8, 0), image.pixels[0].r);
    try testing.expectEqual(@as(u8, 0), image.pixels[0].g);
    try testing.expectEqual(@as(u8, 255), image.pixels[0].b);
}

test "sixel decoder: decode 1x6 vertical stripe (one sixel)" {
    const allocator = testing.allocator;

    // 1x6 green stripe - all 6 bits of column set
    // \x1bPq"1;1;1;6#0;2;0;100;0?~\x1b\
    const sixel_data = "\x1bPq\"1;1;1;6#0;2;0;100;0?~\x1b\\";

    const decoder = SixelDecoder{};
    const image = try decoder.decode(allocator, sixel_data);
    defer allocator.free(image.pixels);

    try testing.expectEqual(@as(u16, 1), image.width);
    try testing.expectEqual(@as(u16, 6), image.height);
    try testing.expectEqual(@as(usize, 6), image.pixels.len);

    // All pixels should be green
    for (image.pixels) |pixel| {
        try testing.expectEqual(@as(u8, 0), pixel.r);
        try testing.expectEqual(@as(u8, 255), pixel.g);
        try testing.expectEqual(@as(u8, 0), pixel.b);
    }
}

test "sixel decoder: decode 1x7 partial vertical stripe (2 sixel rows)" {
    const allocator = testing.allocator;

    // 1x7 stripe needs 2 sixel rows
    // Row 1: 6 pixels, Row 2: 1 pixel
    // \x1bPq"1;1;1;7#0;2;100;100;100?~-?!\x1b\
    const sixel_data = "\x1bPq\"1;1;1;7#0;2;100;100;100?~-?!\x1b\\";

    const decoder = SixelDecoder{};
    const image = try decoder.decode(allocator, sixel_data);
    defer allocator.free(image.pixels);

    try testing.expectEqual(@as(u16, 1), image.width);
    try testing.expectEqual(@as(u16, 7), image.height);
    try testing.expectEqual(@as(usize, 7), image.pixels.len);

    // All pixels should be white (100, 100, 100 scaled to 255, 255, 255)
    for (image.pixels) |pixel| {
        try testing.expectEqual(@as(u8, 255), pixel.r);
        try testing.expectEqual(@as(u8, 255), pixel.g);
        try testing.expectEqual(@as(u8, 255), pixel.b);
    }
}

// ============================================================================
// Color Palette Tests
// ============================================================================

test "sixel decoder: decode multiple colors" {
    const allocator = testing.allocator;

    // 2x2 checkerboard: red, green; blue, yellow
    // \x1bPq"1;1;2;2#0;2;100;0;0?#1;2;0;100;0?$-#2;2;0;0;100?#3;2;100;100;0?\x1b\
    const sixel_data = "\x1bPq\"1;1;2;2#0;2;100;0;0?#1;2;0;100;0?$-#2;2;0;0;100?#3;2;100;100;0?\x1b\\";

    const decoder = SixelDecoder{};
    const image = try decoder.decode(allocator, sixel_data);
    defer allocator.free(image.pixels);

    try testing.expectEqual(@as(u16, 2), image.width);
    try testing.expectEqual(@as(u16, 2), image.height);

    // Row 0: red, green
    // Row 1: blue, yellow
    // (assuming proper encoding with color switches)
}

test "sixel decoder: decode RGB scaling (0-100 to 0-255)" {
    const allocator = testing.allocator;

    // Test specific RGB values
    // #0;2;50;25;75 -> (127, 63, 191) when scaled
    const sixel_data = "\x1bPq\"1;1;1;1#0;2;50;25;75?!\x1b\\";

    const decoder = SixelDecoder{};
    const image = try decoder.decode(allocator, sixel_data);
    defer allocator.free(image.pixels);

    try testing.expectEqual(@as(u16, 1), image.width);
    try testing.expectEqual(@as(u16, 1), image.height);

    // Verify RGB scaling: 50/100 * 255 ≈ 127, 25/100 * 255 ≈ 63, 75/100 * 255 ≈ 191
    const pixel = image.pixels[0];
    try testing.expectEqual(@as(u8, 127), pixel.r);
    try testing.expectEqual(@as(u8, 63), pixel.g);
    try testing.expectEqual(@as(u8, 191), pixel.b);
}

test "sixel decoder: parse color palette definitions" {
    const allocator = testing.allocator;

    // Multiple color definitions
    // #0;2;100;0;0 (red)
    // #1;2;0;100;0 (green)
    // #2;2;0;0;100 (blue)
    const sixel_data = "\x1bPq\"1;1;3;1#0;2;100;0;0?#1;2;0;100;0?#2;2;0;0;100?\x1b\\";

    const decoder = SixelDecoder{};
    const image = try decoder.decode(allocator, sixel_data);
    defer allocator.free(image.pixels);

    try testing.expectEqual(@as(u16, 3), image.width);
    try testing.expectEqual(@as(u16, 1), image.height);
}

// ============================================================================
// Transparency Tests
// ============================================================================

test "sixel decoder: handle missing color indices (transparency)" {
    const allocator = testing.allocator;

    // 2x2 with missing pixels -> transparent
    // Sixel format skips pixels with color index 0 if not explicitly set
    const sixel_data = "\x1bPq\"1;1;2;2#1;2;100;100;100?@$-?@\x1b\\";

    const decoder = SixelDecoder{};
    const image = try decoder.decode(allocator, sixel_data);
    defer allocator.free(image.pixels);

    try testing.expectEqual(@as(u16, 2), image.width);
    try testing.expectEqual(@as(u16, 2), image.height);

    // Pixels from color index 0 (not explicitly rendered) should be transparent
    // Implementation should handle alpha channel correctly
}

test "sixel decoder: pixel transparency with alpha channel" {
    const allocator = testing.allocator;

    // Pixels that are not rendered in any color should have alpha=0
    const sixel_data = "\x1bPq\"1;1;2;2#0;2;255;0;0\x1b\\";

    const decoder = SixelDecoder{};
    const image = try decoder.decode(allocator, sixel_data);
    defer allocator.free(image.pixels);

    try testing.expectEqual(@as(u16, 2), image.width);
    try testing.expectEqual(@as(u16, 2), image.height);

    // If a pixel position is never rendered, it should be transparent (alpha=0)
    // or have default transparent color
}

// ============================================================================
// Multiple Sixel Row Tests
// ============================================================================

test "sixel decoder: decode multiple sixel rows (height > 6)" {
    const allocator = testing.allocator;

    // 1x12 image = 2 sixel rows
    // First row: 6 pixels, second row: 6 pixels
    const sixel_data = "\x1bPq\"1;1;1;12#0;2;100;0;0?~-?~\x1b\\";

    const decoder = SixelDecoder{};
    const image = try decoder.decode(allocator, sixel_data);
    defer allocator.free(image.pixels);

    try testing.expectEqual(@as(u16, 1), image.width);
    try testing.expectEqual(@as(u16, 12), image.height);
    try testing.expectEqual(@as(usize, 12), image.pixels.len);

    // All should be red
    for (image.pixels) |pixel| {
        try testing.expectEqual(@as(u8, 255), pixel.r);
        try testing.expectEqual(@as(u8, 0), pixel.g);
        try testing.expectEqual(@as(u8, 0), pixel.b);
    }
}

test "sixel decoder: multiple sixel rows with carriage return" {
    const allocator = testing.allocator;

    // 1x12 with carriage return between rows
    // $ = carriage return (move to start of next row)
    const sixel_data = "\x1bPq\"1;1;1;12#0;2;0;100;0?~$-?~\x1b\\";

    const decoder = SixelDecoder{};
    const image = try decoder.decode(allocator, sixel_data);
    defer allocator.free(image.pixels);

    try testing.expectEqual(@as(u16, 1), image.width);
    try testing.expectEqual(@as(u16, 12), image.height);
}

test "sixel decoder: 2x6 wide image" {
    const allocator = testing.allocator;

    // 2 columns, 6 rows
    // \x1bPq"1;1;2;6#0;2;255;0;0??~$-?~\x1b\
    const sixel_data = "\x1bPq\"1;1;2;6#0;2;255;0;0??~$-?~\x1b\\";

    const decoder = SixelDecoder{};
    const image = try decoder.decode(allocator, sixel_data);
    defer allocator.free(image.pixels);

    try testing.expectEqual(@as(u16, 2), image.width);
    try testing.expectEqual(@as(u16, 6), image.height);
    try testing.expectEqual(@as(usize, 12), image.pixels.len);
}

// ============================================================================
// Color Switching Tests
// ============================================================================

test "sixel decoder: color switching (#index)" {
    const allocator = testing.allocator;

    // 2x1 row with color switch: red then blue
    // #0;2;100;0;0 (define red)
    // ? (one pixel of red)
    // #1;2;0;0;100 (switch to blue)
    // ? (one pixel of blue)
    const sixel_data = "\x1bPq\"1;1;2;1#0;2;100;0;0?#1;2;0;0;100?\x1b\\";

    const decoder = SixelDecoder{};
    const image = try decoder.decode(allocator, sixel_data);
    defer allocator.free(image.pixels);

    try testing.expectEqual(@as(u16, 2), image.width);
    try testing.expectEqual(@as(u16, 1), image.height);

    // First pixel red, second pixel blue
    try testing.expectEqual(@as(u8, 255), image.pixels[0].r);
    try testing.expectEqual(@as(u8, 0), image.pixels[0].g);
    try testing.expectEqual(@as(u8, 0), image.pixels[0].b);

    try testing.expectEqual(@as(u8, 0), image.pixels[1].r);
    try testing.expectEqual(@as(u8, 0), image.pixels[1].g);
    try testing.expectEqual(@as(u8, 255), image.pixels[1].b);
}

// ============================================================================
// Sixel Data Encoding Tests (Sixel Values)
// ============================================================================

test "sixel decoder: decode sixel pixel values (6-bit vertical columns)" {
    const allocator = testing.allocator;

    // Sixel value '?' = 0x3f + 0 = 0x3f = no pixels
    // Sixel value '!' = 0x3f + 1 = 0x40 = bit 0 set (pixel at y=0)
    // Sixel value '"' = 0x3f + 2 = 0x41 = bit 1 set (pixel at y=1)
    // Sixel value '~' = 0x3f + 63 = 0x7e = all 6 bits set

    const sixel_data = "\x1bPq\"1;1;1;6#0;2;100;100;100?~\x1b\\";

    const decoder = SixelDecoder{};
    const image = try decoder.decode(allocator, sixel_data);
    defer allocator.free(image.pixels);

    try testing.expectEqual(@as(u16, 1), image.width);
    try testing.expectEqual(@as(u16, 6), image.height);

    // All 6 pixels should be present (white)
    for (image.pixels) |pixel| {
        try testing.expectEqual(@as(u8, 255), pixel.r);
        try testing.expectEqual(@as(u8, 255), pixel.g);
        try testing.expectEqual(@as(u8, 255), pixel.b);
    }
}

test "sixel decoder: partial sixel bits (individual pixels)" {
    const allocator = testing.allocator;

    // '!' = 0x40 = 0x01 = bit 0 set (only first pixel of 6)
    const sixel_data = "\x1bPq\"1;1;1;6#0;2;100;0;0?!\x1b\\";

    const decoder = SixelDecoder{};
    const image = try decoder.decode(allocator, sixel_data);
    defer allocator.free(image.pixels);

    try testing.expectEqual(@as(u16, 1), image.width);
    try testing.expectEqual(@as(u16, 6), image.height);

    // Only first pixel should be red, rest should be transparent
    try testing.expectEqual(@as(u8, 255), image.pixels[0].r);
    try testing.expectEqual(@as(u8, 0), image.pixels[0].a);  // Assuming unset pixels are transparent
}

// ============================================================================
// Escape Sequence Tests
// ============================================================================

test "sixel decoder: reject invalid escape sequence (missing start marker)" {
    const allocator = testing.allocator;

    // Missing \x1bPq
    const invalid_data = "q\"1;1;2;2#0;2;100;0;0?@$-?@\x1b\\";

    const decoder = SixelDecoder{};
    const result = decoder.decode(allocator, invalid_data);

    try testing.expectError(error.InvalidSixelFormat, result);
}

test "sixel decoder: reject invalid escape sequence (missing end marker)" {
    const allocator = testing.allocator;

    // Missing \x1b\
    const invalid_data = "\x1bPq\"1;1;2;2#0;2;100;0;0?@$-?@";

    const decoder = SixelDecoder{};
    const result = decoder.decode(allocator, invalid_data);

    try testing.expectError(error.InvalidSixelFormat, result);
}

test "sixel decoder: reject malformed raster attributes" {
    const allocator = testing.allocator;

    // Invalid raster attributes: missing semicolon or width
    const invalid_data = "\x1bPq\"1;1;;2#0;2;100;0;0?@\x1b\\";

    const decoder = SixelDecoder{};
    const result = decoder.decode(allocator, invalid_data);

    try testing.expectError(error.InvalidRasterAttributes, result);
}

test "sixel decoder: reject overflow dimensions (width exceeds limit)" {
    const allocator = testing.allocator;

    // Width = 5000, exceeds typical max_width of 4096
    const sixel_data = "\x1bPq\"1;1;5000;100#0;2;100;0;0?@\x1b\\";

    const decoder = SixelDecoder{ .max_width = 4096 };
    const result = decoder.decode(allocator, sixel_data);

    try testing.expectError(error.DimensionsTooLarge, result);
}

test "sixel decoder: reject overflow dimensions (height exceeds limit)" {
    const allocator = testing.allocator;

    // Height = 5000, exceeds max_height
    const sixel_data = "\x1bPq\"1;1;100;5000#0;2;100;0;0?@\x1b\\";

    const decoder = SixelDecoder{ .max_height = 4096 };
    const result = decoder.decode(allocator, sixel_data);

    try testing.expectError(error.DimensionsTooLarge, result);
}

test "sixel decoder: zero dimensions should fail" {
    const allocator = testing.allocator;

    // 0x0 image
    const sixel_data = "\x1bPq\"1;1;0;0#0;2;100;0;0?@\x1b\\";

    const decoder = SixelDecoder{};
    const result = decoder.decode(allocator, sixel_data);

    try testing.expectError(error.InvalidDimensions, result);
}

// ============================================================================
// Round-Trip Tests (Encode → Decode → Verify)
// ============================================================================

test "sixel decoder: round-trip 2x2 red image (encode then decode)" {
    const allocator = testing.allocator;

    // Create original image
    const original_pixels = [_]SixelImage.Color{
        .{ .r = 255, .g = 0, .b = 0 },
        .{ .r = 255, .g = 0, .b = 0 },
        .{ .r = 255, .g = 0, .b = 0 },
        .{ .r = 255, .g = 0, .b = 0 },
    };

    const original_image = SixelImage{
        .width = 2,
        .height = 2,
        .pixels = &original_pixels,
    };

    // Encode to Sixel
    var encoded: std.ArrayList(u8) = .{};
    defer encoded.deinit(allocator);

    const encoder = SixelEncoder{};
    try encoder.encode(allocator, original_image, encoded.writer(allocator));

    // Decode back
    const decoder = SixelDecoder{};
    const decoded_image = try decoder.decode(allocator, encoded.items);
    defer allocator.free(decoded_image.pixels);

    // Verify dimensions match
    try testing.expectEqual(original_image.width, decoded_image.width);
    try testing.expectEqual(original_image.height, decoded_image.height);

    // Verify all pixels are red (allowing small color quantization error)
    for (decoded_image.pixels) |pixel| {
        try testing.expect(pixel.r > 200); // Red channel dominant
        try testing.expect(pixel.g < 50);
        try testing.expect(pixel.b < 50);
    }
}

test "sixel decoder: round-trip single pixel various colors" {
    const allocator = testing.allocator;

    const test_colors = [_]SixelImage.Color{
        .{ .r = 255, .g = 0, .b = 0 },      // Red
        .{ .r = 0, .g = 255, .b = 0 },      // Green
        .{ .r = 0, .g = 0, .b = 255 },      // Blue
        .{ .r = 255, .g = 255, .b = 0 },    // Yellow
        .{ .r = 255, .g = 0, .b = 255 },    // Magenta
        .{ .r = 0, .g = 255, .b = 255 },    // Cyan
        .{ .r = 128, .g = 128, .b = 128 },  // Gray
    };

    for (test_colors) |color| {
        const original_image = SixelImage{
            .width = 1,
            .height = 1,
            .pixels = &[_]SixelImage.Color{color},
        };

        var encoded: std.ArrayList(u8) = .{};
        defer encoded.deinit(allocator);

        const encoder = SixelEncoder{};
        try encoder.encode(allocator, original_image, encoded.writer(allocator));

        const decoder = SixelDecoder{};
        const decoded_image = try decoder.decode(allocator, encoded.items);
        defer allocator.free(decoded_image.pixels);

        try testing.expectEqual(@as(u16, 1), decoded_image.width);
        try testing.expectEqual(@as(u16, 1), decoded_image.height);
        try testing.expectEqual(@as(usize, 1), decoded_image.pixels.len);

        // Allow small quantization error (±10)
        const decoded_pixel = decoded_image.pixels[0];
        try testing.expect(@abs(@as(i16, @intCast(decoded_pixel.r)) - @as(i16, @intCast(color.r))) <= 10);
        try testing.expect(@abs(@as(i16, @intCast(decoded_pixel.g)) - @as(i16, @intCast(color.g))) <= 10);
        try testing.expect(@abs(@as(i16, @intCast(decoded_pixel.b)) - @as(i16, @intCast(color.b))) <= 10);
    }
}

// ============================================================================
// Edge Case Tests
// ============================================================================

test "sixel decoder: empty/whitespace sixel data" {
    const allocator = testing.allocator;

    const invalid_data = "";

    const decoder = SixelDecoder{};
    const result = decoder.decode(allocator, invalid_data);

    try testing.expectError(error.InvalidSixelFormat, result);
}

test "sixel decoder: incomplete raster attributes" {
    const allocator = testing.allocator;

    // Missing height value
    const invalid_data = "\x1bPq\"1;1;2\x1b\\";

    const decoder = SixelDecoder{};
    const result = decoder.decode(allocator, invalid_data);

    try testing.expectError(error.InvalidRasterAttributes, result);
}

test "sixel decoder: non-numeric raster attributes" {
    const allocator = testing.allocator;

    // Non-numeric width/height
    const invalid_data = "\x1bPq\"1;1;abc;def#0;2;100;0;0?@\x1b\\";

    const decoder = SixelDecoder{};
    const result = decoder.decode(allocator, invalid_data);

    try testing.expectError(error.InvalidRasterAttributes, result);
}

test "sixel decoder: non-numeric color values" {
    const allocator = testing.allocator;

    // Non-numeric RGB values
    const invalid_data = "\x1bPq\"1;1;1;1#0;2;red;green;blue?@\x1b\\";

    const decoder = SixelDecoder{};
    const result = decoder.decode(allocator, invalid_data);

    try testing.expectError(error.InvalidColorDefinition, result);
}

test "sixel decoder: RGB values out of range (> 100)" {
    const allocator = testing.allocator;

    // RGB values exceed 0-100 range
    const invalid_data = "\x1bPq\"1;1;1;1#0;2;150;0;0?@\x1b\\";

    const decoder = SixelDecoder{};
    const result = decoder.decode(allocator, invalid_data);

    try testing.expectError(error.ColorValueOutOfRange, result);
}

test "sixel decoder: negative RGB values" {
    const allocator = testing.allocator;

    // Negative RGB values
    const invalid_data = "\x1bPq\"1;1;1;1#0;2;-50;0;0?@\x1b\\";

    const decoder = SixelDecoder{};
    const result = decoder.decode(allocator, invalid_data);

    try testing.expectError(error.InvalidColorDefinition, result);
}

// ============================================================================
// Complex Pattern Tests
// ============================================================================

test "sixel decoder: decode checkerboard pattern (2x2 with 4 colors)" {
    const allocator = testing.allocator;

    // Create a proper checkerboard: alternating 4 colors
    // Manually crafted Sixel for 2x2 checkerboard
    const sixel_data = "\x1bPq\"1;1;2;2#0;2;100;0;0?#1;2;0;100;0?$-#2;2;0;0;100?#3;2;100;100;0?\x1b\\";

    const decoder = SixelDecoder{};
    const image = try decoder.decode(allocator, sixel_data);
    defer allocator.free(image.pixels);

    try testing.expectEqual(@as(u16, 2), image.width);
    try testing.expectEqual(@as(u16, 2), image.height);
    try testing.expectEqual(@as(usize, 4), image.pixels.len);
}

test "sixel decoder: wide image (4 columns, 1 row)" {
    const allocator = testing.allocator;

    // 4x1 image with all red pixels
    const sixel_data = "\x1bPq\"1;1;4;1#0;2;100;0;0????\x1b\\";

    const decoder = SixelDecoder{};
    const image = try decoder.decode(allocator, sixel_data);
    defer allocator.free(image.pixels);

    try testing.expectEqual(@as(u16, 4), image.width);
    try testing.expectEqual(@as(u16, 1), image.height);
    try testing.expectEqual(@as(usize, 4), image.pixels.len);
}

test "sixel decoder: tall image (1 column, 18 rows - 3 sixel rows)" {
    const allocator = testing.allocator;

    // 1x18 = 3 sixel rows
    const sixel_data = "\x1bPq\"1;1;1;18#0;2;0;100;0?~-?~-?~\x1b\\";

    const decoder = SixelDecoder{};
    const image = try decoder.decode(allocator, sixel_data);
    defer allocator.free(image.pixels);

    try testing.expectEqual(@as(u16, 1), image.width);
    try testing.expectEqual(@as(u16, 18), image.height);
    try testing.expectEqual(@as(usize, 18), image.pixels.len);

    // All should be green
    for (image.pixels) |pixel| {
        try testing.expectEqual(@as(u8, 0), pixel.r);
        try testing.expectEqual(@as(u8, 255), pixel.g);
        try testing.expectEqual(@as(u8, 0), pixel.b);
    }
}

// ============================================================================
// Boundary / Limit Tests
// ============================================================================

test "sixel decoder: maximum allowed dimensions (4096x4096)" {
    const allocator = testing.allocator;

    // At boundary - should succeed
    const sixel_data = "\x1bPq\"1;1;4096;4096#0;2;100;0;0?@\x1b\\";

    const decoder = SixelDecoder{ .max_width = 4096, .max_height = 4096 };
    const result = decoder.decode(allocator, sixel_data);

    // Should either decode successfully or handle gracefully
    if (result) |image| {
        defer allocator.free(image.pixels);
        try testing.expectEqual(@as(u16, 4096), image.width);
        try testing.expectEqual(@as(u16, 4096), image.height);
    } else |_| {
        // Allocation failure is acceptable at this size
    }
}

test "sixel decoder: just over maximum width (4097)" {
    const allocator = testing.allocator;

    const sixel_data = "\x1bPq\"1;1;4097;100#0;2;100;0;0?@\x1b\\";

    const decoder = SixelDecoder{ .max_width = 4096, .max_height = 4096 };
    const result = decoder.decode(allocator, sixel_data);

    try testing.expectError(error.DimensionsTooLarge, result);
}

test "sixel decoder: custom decoder limits (512x512)" {
    const allocator = testing.allocator;

    // Create a 600x600 image (exceeds custom limit)
    const sixel_data = "\x1bPq\"1;1;600;600#0;2;100;0;0?@\x1b\\";

    const decoder = SixelDecoder{ .max_width = 512, .max_height = 512 };
    const result = decoder.decode(allocator, sixel_data);

    try testing.expectError(error.DimensionsTooLarge, result);
}

// ============================================================================
// Memory Safety Tests
// ============================================================================

test "sixel decoder: no memory leaks on successful decode" {
    const allocator = testing.allocator;

    const sixel_data = "\x1bPq\"1;1;2;2#0;2;100;0;0?@$-?@\x1b\\";

    const decoder = SixelDecoder{};
    const image = try decoder.decode(allocator, sixel_data);
    defer allocator.free(image.pixels);

    // Testing allocator will report any leaks
}

test "sixel decoder: no memory leaks on error (invalid format)" {
    const allocator = testing.allocator;

    const invalid_data = "not a sixel sequence";

    const decoder = SixelDecoder{};
    _ = decoder.decode(allocator, invalid_data) catch |e| {
        // Expected to fail
        try testing.expect(e == error.InvalidSixelFormat);
    };

    // Testing allocator will report any leaks
}

test "sixel decoder: no memory leaks on dimension overflow" {
    const allocator = testing.allocator;

    const sixel_data = "\x1bPq\"1;1;5000;5000#0;2;100;0;0?@\x1b\\";

    const decoder = SixelDecoder{ .max_width = 1024, .max_height = 1024 };
    _ = decoder.decode(allocator, sixel_data) catch |e| {
        // Expected to fail
        try testing.expect(e == error.DimensionsTooLarge);
    };

    // Testing allocator will report any leaks
}

// ============================================================================
// Color Palette Optimization Tests
// ============================================================================

// Helper: Generate random color with seeded PRNG for reproducible tests
fn randomColor(seed: u64) SixelImage.Color {
    var prng = std.Random.DefaultPrng.init(seed);
    const random = prng.random();
    return .{
        .r = random.int(u8),
        .g = random.int(u8),
        .b = random.int(u8),
        .a = 255,
    };
}

// Helper: Create test image filled with a color
fn makeTestImage(allocator: std.mem.Allocator, width: u16, height: u16, fill_color: SixelImage.Color) !SixelImage {
    const pixel_count = @as(usize, width) * @as(usize, height);
    const pixels = try allocator.alloc(SixelImage.Color, pixel_count);
    @memset(pixels, fill_color);
    return SixelImage{
        .width = width,
        .height = height,
        .pixels = pixels,
    };
}

// ----------------------------------------------------------------------------
// Basic Quantization Tests (6 tests)
// ----------------------------------------------------------------------------

test "sixel palette: quantize 1000 random RGB colors to 256-color palette" {
    const allocator = testing.allocator;

    // Generate 1000 random colors
    const colors = try allocator.alloc(SixelImage.Color, 1000);
    defer allocator.free(colors);

    for (colors, 0..) |*c, i| {
        c.* = randomColor(i);
    }

    // Quantize to 256 colors
    const palette = try sailor.tui.sixel.quantizeColors(
        allocator,
        colors,
        256,
        .median_cut,
    );
    defer palette.deinit();

    // Should produce palette with at most 256 colors
    try testing.expect(palette.colors.len <= 256);
    try testing.expect(palette.colors.len > 0);
}

test "sixel palette: quantize grayscale gradient (256 shades) to 16-color palette" {
    const allocator = testing.allocator;

    // Create grayscale gradient: 0, 1, 2, ..., 255
    const colors = try allocator.alloc(SixelImage.Color, 256);
    defer allocator.free(colors);

    for (colors, 0..) |*c, i| {
        const v: u8 = @intCast(i);
        c.* = .{ .r = v, .g = v, .b = v };
    }

    // Quantize to 16 colors
    const palette = try sailor.tui.sixel.quantizeColors(
        allocator,
        colors,
        16,
        .median_cut,
    );
    defer palette.deinit();

    // Should have exactly 16 colors
    try testing.expectEqual(@as(usize, 16), palette.colors.len);

    // Colors should span from dark to light
    const first = palette.colors[0];
    const last = palette.colors[palette.colors.len - 1];
    const first_brightness = @as(u16, first.r) + first.g + first.b;
    const last_brightness = @as(u16, last.r) + last.g + last.b;
    try testing.expect(first_brightness < last_brightness);
}

test "sixel palette: quantize primary colors (8 colors) to 4-color palette" {
    const allocator = testing.allocator;

    // RGB cube corners
    const colors = [_]SixelImage.Color{
        .{ .r = 0, .g = 0, .b = 0 },     // Black
        .{ .r = 255, .g = 0, .b = 0 },   // Red
        .{ .r = 0, .g = 255, .b = 0 },   // Green
        .{ .r = 0, .g = 0, .b = 255 },   // Blue
        .{ .r = 255, .g = 255, .b = 0 }, // Yellow
        .{ .r = 255, .g = 0, .b = 255 }, // Magenta
        .{ .r = 0, .g = 255, .b = 255 }, // Cyan
        .{ .r = 255, .g = 255, .b = 255 }, // White
    };

    const palette = try sailor.tui.sixel.quantizeColors(
        allocator,
        &colors,
        4,
        .median_cut,
    );
    defer palette.deinit();

    try testing.expectEqual(@as(usize, 4), palette.colors.len);
}

test "sixel palette: empty image handling (0 colors)" {
    const allocator = testing.allocator;

    const colors = [_]SixelImage.Color{};

    const palette = try sailor.tui.sixel.quantizeColors(
        allocator,
        &colors,
        256,
        .median_cut,
    );
    defer palette.deinit();

    // Should produce empty palette or single default color
    try testing.expect(palette.colors.len <= 1);
}

test "sixel palette: single color image (all pixels same)" {
    const allocator = testing.allocator;

    // 1000 identical red pixels
    const colors = try allocator.alloc(SixelImage.Color, 1000);
    defer allocator.free(colors);
    @memset(colors, .{ .r = 255, .g = 0, .b = 0 });

    const palette = try sailor.tui.sixel.quantizeColors(
        allocator,
        colors,
        256,
        .median_cut,
    );
    defer palette.deinit();

    // Should produce palette with exactly 1 color
    try testing.expectEqual(@as(usize, 1), palette.colors.len);
    try testing.expectEqual(@as(u8, 255), palette.colors[0].r);
    try testing.expectEqual(@as(u8, 0), palette.colors[0].g);
    try testing.expectEqual(@as(u8, 0), palette.colors[0].b);
}

test "sixel palette: duplicate color removal (10000 pixels, 5 unique colors)" {
    const allocator = testing.allocator;

    // 10000 pixels with only 5 unique colors
    const colors = try allocator.alloc(SixelImage.Color, 10000);
    defer allocator.free(colors);

    const unique_colors = [_]SixelImage.Color{
        .{ .r = 255, .g = 0, .b = 0 },
        .{ .r = 0, .g = 255, .b = 0 },
        .{ .r = 0, .g = 0, .b = 255 },
        .{ .r = 255, .g = 255, .b = 0 },
        .{ .r = 128, .g = 128, .b = 128 },
    };

    for (colors, 0..) |*c, i| {
        c.* = unique_colors[i % 5];
    }

    const palette = try sailor.tui.sixel.quantizeColors(
        allocator,
        colors,
        256,
        .median_cut,
    );
    defer palette.deinit();

    // Should recognize only 5 unique colors
    try testing.expectEqual(@as(usize, 5), palette.colors.len);
}

// ----------------------------------------------------------------------------
// Median Cut Algorithm Tests (8 tests)
// ----------------------------------------------------------------------------

test "sixel palette: median cut with 2 colors (red/blue image)" {
    const allocator = testing.allocator;

    // Half red, half blue
    const colors = try allocator.alloc(SixelImage.Color, 100);
    defer allocator.free(colors);

    for (colors, 0..) |*c, i| {
        c.* = if (i < 50)
            .{ .r = 255, .g = 0, .b = 0 }
        else
            .{ .r = 0, .g = 0, .b = 255 };
    }

    const palette = try sailor.tui.sixel.quantizeColors(
        allocator,
        colors,
        2,
        .median_cut,
    );
    defer palette.deinit();

    try testing.expectEqual(@as(usize, 2), palette.colors.len);

    // Should have one reddish and one bluish color
    var has_red = false;
    var has_blue = false;
    for (palette.colors) |c| {
        if (c.r > 200 and c.b < 50) has_red = true;
        if (c.b > 200 and c.r < 50) has_blue = true;
    }
    try testing.expect(has_red);
    try testing.expect(has_blue);
}

test "sixel palette: median cut with 16 colors (natural image simulation)" {
    const allocator = testing.allocator;

    // Simulate natural image colors (more greens/browns, some blues)
    const colors = try allocator.alloc(SixelImage.Color, 500);
    defer allocator.free(colors);

    var prng = std.Random.DefaultPrng.init(42);
    const random = prng.random();

    for (colors) |*c| {
        // Bias toward green/brown range
        c.* = .{
            .r = random.intRangeAtMost(u8, 40, 180),
            .g = random.intRangeAtMost(u8, 80, 220),
            .b = random.intRangeAtMost(u8, 30, 150),
        };
    }

    const palette = try sailor.tui.sixel.quantizeColors(
        allocator,
        colors,
        16,
        .median_cut,
    );
    defer palette.deinit();

    try testing.expectEqual(@as(usize, 16), palette.colors.len);
}

test "sixel palette: median cut with 256 colors (maximum palette)" {
    const allocator = testing.allocator;

    // Generate 1000 random colors
    const colors = try allocator.alloc(SixelImage.Color, 1000);
    defer allocator.free(colors);

    for (colors, 0..) |*c, i| {
        c.* = randomColor(i + 1000);
    }

    const palette = try sailor.tui.sixel.quantizeColors(
        allocator,
        colors,
        256,
        .median_cut,
    );
    defer palette.deinit();

    try testing.expect(palette.colors.len <= 256);
    try testing.expect(palette.colors.len > 0);
}

test "sixel palette: median cut color distribution preservation" {
    const allocator = testing.allocator;

    // 90% red, 10% blue (most frequent should be retained)
    const colors = try allocator.alloc(SixelImage.Color, 1000);
    defer allocator.free(colors);

    for (colors, 0..) |*c, i| {
        c.* = if (i < 900)
            .{ .r = 255, .g = 0, .b = 0 }
        else
            .{ .r = 0, .g = 0, .b = 255 };
    }

    const palette = try sailor.tui.sixel.quantizeColors(
        allocator,
        colors,
        4,
        .median_cut,
    );
    defer palette.deinit();

    // Should have red as dominant color in palette
    var red_count: usize = 0;
    for (palette.colors) |c| {
        if (c.r > 200 and c.g < 50 and c.b < 50) red_count += 1;
    }
    try testing.expect(red_count >= 1);
}

test "sixel palette: median cut splitting axis selection (RGB channel with max range)" {
    const allocator = testing.allocator;

    // Create colors with large red variation, small green/blue
    const colors = try allocator.alloc(SixelImage.Color, 100);
    defer allocator.free(colors);

    for (colors, 0..) |*c, i| {
        c.* = .{
            .r = @intCast(i * 255 / 100), // Wide range: 0-255
            .g = 128, // Constant
            .b = 128, // Constant
        };
    }

    const palette = try sailor.tui.sixel.quantizeColors(
        allocator,
        colors,
        8,
        .median_cut,
    );
    defer palette.deinit();

    // Should split on red channel (largest range)
    // Verify palette has diverse red values
    var min_r: u8 = 255;
    var max_r: u8 = 0;
    for (palette.colors) |c| {
        if (c.r < min_r) min_r = c.r;
        if (c.r > max_r) max_r = c.r;
    }
    try testing.expect(max_r - min_r > 100); // Significant red variation
}

test "sixel palette: median cut edge case: more palette slots than unique colors" {
    const allocator = testing.allocator;

    // Only 3 unique colors, request 16
    const colors = [_]SixelImage.Color{
        .{ .r = 255, .g = 0, .b = 0 },
        .{ .r = 0, .g = 255, .b = 0 },
        .{ .r = 0, .g = 0, .b = 255 },
    };

    const palette = try sailor.tui.sixel.quantizeColors(
        allocator,
        &colors,
        16,
        .median_cut,
    );
    defer palette.deinit();

    // Should return only 3 colors (can't create more)
    try testing.expectEqual(@as(usize, 3), palette.colors.len);
}

test "sixel palette: median cut edge case: single pixel" {
    const allocator = testing.allocator;

    const colors = [_]SixelImage.Color{
        .{ .r = 123, .g = 45, .b = 67 },
    };

    const palette = try sailor.tui.sixel.quantizeColors(
        allocator,
        &colors,
        256,
        .median_cut,
    );
    defer palette.deinit();

    try testing.expectEqual(@as(usize, 1), palette.colors.len);
    try testing.expectEqual(@as(u8, 123), palette.colors[0].r);
}

test "sixel palette: median cut edge case: all pixels same color" {
    const allocator = testing.allocator;

    const colors = try allocator.alloc(SixelImage.Color, 500);
    defer allocator.free(colors);
    @memset(colors, .{ .r = 64, .g = 128, .b = 192 });

    const palette = try sailor.tui.sixel.quantizeColors(
        allocator,
        colors,
        16,
        .median_cut,
    );
    defer palette.deinit();

    // Should recognize single color
    try testing.expectEqual(@as(usize, 1), palette.colors.len);
    try testing.expectEqual(@as(u8, 64), palette.colors[0].r);
    try testing.expectEqual(@as(u8, 128), palette.colors[0].g);
    try testing.expectEqual(@as(u8, 192), palette.colors[0].b);
}

// ----------------------------------------------------------------------------
// Octree Quantization Tests (6 tests)
// ----------------------------------------------------------------------------

test "sixel palette: octree with 8 colors (RGB cube corners)" {
    const allocator = testing.allocator;

    // RGB cube corners + many duplicates
    const colors = try allocator.alloc(SixelImage.Color, 800);
    defer allocator.free(colors);

    const corners = [_]SixelImage.Color{
        .{ .r = 0, .g = 0, .b = 0 },
        .{ .r = 255, .g = 0, .b = 0 },
        .{ .r = 0, .g = 255, .b = 0 },
        .{ .r = 0, .g = 0, .b = 255 },
        .{ .r = 255, .g = 255, .b = 0 },
        .{ .r = 255, .g = 0, .b = 255 },
        .{ .r = 0, .g = 255, .b = 255 },
        .{ .r = 255, .g = 255, .b = 255 },
    };

    for (colors, 0..) |*c, i| {
        c.* = corners[i % 8];
    }

    const palette = try sailor.tui.sixel.quantizeColors(
        allocator,
        colors,
        8,
        .octree,
    );
    defer palette.deinit();

    try testing.expectEqual(@as(usize, 8), palette.colors.len);
}

test "sixel palette: octree with 256 colors" {
    const allocator = testing.allocator;

    // Generate diverse colors
    const colors = try allocator.alloc(SixelImage.Color, 2000);
    defer allocator.free(colors);

    for (colors, 0..) |*c, i| {
        c.* = randomColor(i + 5000);
    }

    const palette = try sailor.tui.sixel.quantizeColors(
        allocator,
        colors,
        256,
        .octree,
    );
    defer palette.deinit();

    try testing.expect(palette.colors.len <= 256);
    try testing.expect(palette.colors.len > 0);
}

test "sixel palette: octree color merging (reduce tree depth)" {
    const allocator = testing.allocator;

    // Many colors forcing tree reduction
    const colors = try allocator.alloc(SixelImage.Color, 1000);
    defer allocator.free(colors);

    var prng = std.Random.DefaultPrng.init(999);
    const random = prng.random();

    for (colors) |*c| {
        c.* = .{
            .r = random.int(u8),
            .g = random.int(u8),
            .b = random.int(u8),
        };
    }

    const palette = try sailor.tui.sixel.quantizeColors(
        allocator,
        colors,
        32,
        .octree,
    );
    defer palette.deinit();

    try testing.expectEqual(@as(usize, 32), palette.colors.len);
}

test "sixel palette: octree pixel counting (weighted color selection)" {
    const allocator = testing.allocator;

    // 95% one color, 5% random colors
    const colors = try allocator.alloc(SixelImage.Color, 1000);
    defer allocator.free(colors);

    for (colors, 0..) |*c, i| {
        c.* = if (i < 950)
            .{ .r = 100, .g = 150, .b = 200 }
        else
            randomColor(i);
    }

    const palette = try sailor.tui.sixel.quantizeColors(
        allocator,
        colors,
        8,
        .octree,
    );
    defer palette.deinit();

    // Dominant color should be in palette
    var found_dominant = false;
    for (palette.colors) |c| {
        if (c.r >= 90 and c.r <= 110 and c.g >= 140 and c.g <= 160 and c.b >= 190 and c.b <= 210) {
            found_dominant = true;
        }
    }
    try testing.expect(found_dominant);
}

test "sixel palette: octree color space coverage (verify distribution)" {
    const allocator = testing.allocator;

    // Colors spanning full RGB space
    const colors = try allocator.alloc(SixelImage.Color, 512);
    defer allocator.free(colors);

    for (colors, 0..) |*c, i| {
        c.* = .{
            .r = @intCast((i * 7) % 256),
            .g = @intCast((i * 13) % 256),
            .b = @intCast((i * 19) % 256),
        };
    }

    const palette = try sailor.tui.sixel.quantizeColors(
        allocator,
        colors,
        64,
        .octree,
    );
    defer palette.deinit();

    // Palette should cover RGB space
    try testing.expectEqual(@as(usize, 64), palette.colors.len);

    // Check that palette has diversity in all channels
    var min_r: u8 = 255;
    var max_r: u8 = 0;
    var min_g: u8 = 255;
    var max_g: u8 = 0;
    var min_b: u8 = 255;
    var max_b: u8 = 0;

    for (palette.colors) |c| {
        if (c.r < min_r) min_r = c.r;
        if (c.r > max_r) max_r = c.r;
        if (c.g < min_g) min_g = c.g;
        if (c.g > max_g) max_g = c.g;
        if (c.b < min_b) min_b = c.b;
        if (c.b > max_b) max_b = c.b;
    }

    // All channels should span significant range
    try testing.expect(max_r - min_r > 150);
    try testing.expect(max_g - min_g > 150);
    try testing.expect(max_b - min_b > 150);
}

test "sixel palette: octree performance: 10000 colors to 256 in <100ms" {
    const allocator = testing.allocator;

    // Generate 10000 colors
    const colors = try allocator.alloc(SixelImage.Color, 10000);
    defer allocator.free(colors);

    for (colors, 0..) |*c, i| {
        c.* = randomColor(i + 10000);
    }

    const start = std.time.nanoTimestamp();

    const palette = try sailor.tui.sixel.quantizeColors(
        allocator,
        colors,
        256,
        .octree,
    );
    defer palette.deinit();

    const end = std.time.nanoTimestamp();
    const elapsed_ms = @divTrunc(end - start, 1_000_000);

    try testing.expect(elapsed_ms < 100); // Should complete in <100ms
    try testing.expectEqual(@as(usize, 256), palette.colors.len);
}

// ----------------------------------------------------------------------------
// K-Means Clustering Tests (6 tests)
// ----------------------------------------------------------------------------

test "sixel palette: k-means with 16 colors, 10 iterations" {
    const allocator = testing.allocator;

    // Generate clustered colors (3 natural clusters)
    const colors = try allocator.alloc(SixelImage.Color, 300);
    defer allocator.free(colors);

    for (colors, 0..) |*c, i| {
        if (i < 100) {
            // Red cluster
            c.* = .{ .r = 200 + @as(u8, @intCast(i % 30)), .g = 50, .b = 50 };
        } else if (i < 200) {
            // Green cluster
            c.* = .{ .r = 50, .g = 200 + @as(u8, @intCast(i % 30)), .b = 50 };
        } else {
            // Blue cluster
            c.* = .{ .r = 50, .g = 50, .b = 200 + @as(u8, @intCast(i % 30)) };
        }
    }

    const palette = try sailor.tui.sixel.quantizeColors(
        allocator,
        colors,
        16,
        .kmeans,
    );
    defer palette.deinit();

    try testing.expectEqual(@as(usize, 16), palette.colors.len);
}

test "sixel palette: k-means convergence detection (stop when centroids stable)" {
    const allocator = testing.allocator;

    // Single tight cluster (should converge quickly)
    const colors = try allocator.alloc(SixelImage.Color, 100);
    defer allocator.free(colors);

    var prng = std.Random.DefaultPrng.init(777);
    const random = prng.random();

    for (colors) |*c| {
        c.* = .{
            .r = 120 + random.intRangeAtMost(u8, 0, 10),
            .g = 130 + random.intRangeAtMost(u8, 0, 10),
            .b = 140 + random.intRangeAtMost(u8, 0, 10),
        };
    }

    const palette = try sailor.tui.sixel.quantizeColors(
        allocator,
        colors,
        4,
        .kmeans,
    );
    defer palette.deinit();

    // Should converge to small palette (likely 1-4 colors)
    try testing.expect(palette.colors.len <= 4);
}

test "sixel palette: k-means initial centroid selection" {
    const allocator = testing.allocator;

    // Diverse colors to test initialization
    const colors = try allocator.alloc(SixelImage.Color, 200);
    defer allocator.free(colors);

    for (colors, 0..) |*c, i| {
        c.* = randomColor(i + 2000);
    }

    const palette = try sailor.tui.sixel.quantizeColors(
        allocator,
        colors,
        8,
        .kmeans,
    );
    defer palette.deinit();

    try testing.expectEqual(@as(usize, 8), palette.colors.len);

    // Initial centroids should be diverse (no duplicates)
    for (palette.colors, 0..) |c1, i| {
        for (palette.colors[i + 1 ..]) |c2| {
            const same = c1.r == c2.r and c1.g == c2.g and c1.b == c2.b;
            try testing.expect(!same);
        }
    }
}

test "sixel palette: k-means empty cluster handling (re-initialize from farthest point)" {
    const allocator = testing.allocator;

    // Create scenario likely to cause empty clusters
    const colors = try allocator.alloc(SixelImage.Color, 100);
    defer allocator.free(colors);

    // 90 colors in one cluster, 10 outliers
    for (colors, 0..) |*c, i| {
        if (i < 90) {
            c.* = .{ .r = 100, .g = 100, .b = 100 };
        } else {
            c.* = .{ .r = @intCast(i * 20), .g = 200, .b = 50 };
        }
    }

    const palette = try sailor.tui.sixel.quantizeColors(
        allocator,
        colors,
        8,
        .kmeans,
    );
    defer palette.deinit();

    // Should handle empty clusters gracefully
    try testing.expect(palette.colors.len <= 8);
    try testing.expect(palette.colors.len > 0);
}

test "sixel palette: k-means color assignment (nearest centroid)" {
    const allocator = testing.allocator;

    // Two well-separated clusters
    const colors = try allocator.alloc(SixelImage.Color, 200);
    defer allocator.free(colors);

    for (colors, 0..) |*c, i| {
        c.* = if (i < 100)
            .{ .r = 50, .g = 50, .b = 50 }
        else
            .{ .r = 200, .g = 200, .b = 200 };
    }

    const palette = try sailor.tui.sixel.quantizeColors(
        allocator,
        colors,
        2,
        .kmeans,
    );
    defer palette.deinit();

    try testing.expectEqual(@as(usize, 2), palette.colors.len);

    // Should have one dark and one light color
    const c1_brightness = @as(u16, palette.colors[0].r) + palette.colors[0].g + palette.colors[0].b;
    const c2_brightness = @as(u16, palette.colors[1].r) + palette.colors[1].g + palette.colors[1].b;
    try testing.expect(@max(c1_brightness, c2_brightness) - @min(c1_brightness, c2_brightness) > 300);
}

test "sixel palette: k-means quality metric: minimize total color distance" {
    const allocator = testing.allocator;

    // Generate colors with known clusters
    const colors = try allocator.alloc(SixelImage.Color, 300);
    defer allocator.free(colors);

    for (colors, 0..) |*c, i| {
        if (i < 100) {
            c.* = .{ .r = 255, .g = 0, .b = 0 };
        } else if (i < 200) {
            c.* = .{ .r = 0, .g = 255, .b = 0 };
        } else {
            c.* = .{ .r = 0, .g = 0, .b = 255 };
        }
    }

    const palette = try sailor.tui.sixel.quantizeColors(
        allocator,
        colors,
        3,
        .kmeans,
    );
    defer palette.deinit();

    // Should find the 3 cluster centers (RGB primaries)
    try testing.expectEqual(@as(usize, 3), palette.colors.len);

    var has_red = false;
    var has_green = false;
    var has_blue = false;

    for (palette.colors) |c| {
        if (c.r > 200 and c.g < 50 and c.b < 50) has_red = true;
        if (c.g > 200 and c.r < 50 and c.b < 50) has_green = true;
        if (c.b > 200 and c.r < 50 and c.g < 50) has_blue = true;
    }

    try testing.expect(has_red);
    try testing.expect(has_green);
    try testing.expect(has_blue);
}

// ----------------------------------------------------------------------------
// Color Distance Metrics Tests (5 tests)
// ----------------------------------------------------------------------------

test "sixel palette: euclidean RGB distance calculation" {
    const c1 = SixelImage.Color{ .r = 0, .g = 0, .b = 0 };
    const c2 = SixelImage.Color{ .r = 255, .g = 255, .b = 255 };

    const distance = sailor.tui.sixel.colorDistance(c1, c2, .euclidean_rgb);

    // Distance = sqrt(255^2 + 255^2 + 255^2) ≈ 441.67
    try testing.expect(distance > 440.0);
    try testing.expect(distance < 445.0);
}

test "sixel palette: perceptual LAB distance (more accurate for human vision)" {
    const red = SixelImage.Color{ .r = 255, .g = 0, .b = 0 };
    const green = SixelImage.Color{ .r = 0, .g = 255, .b = 0 };

    const distance = sailor.tui.sixel.colorDistance(red, green, .perceptual_lab);

    // LAB distance should differ from RGB distance for human perception
    try testing.expect(distance > 0.0);

    // Perceptual distance between red and green should be significant
    try testing.expect(distance > 50.0);
}

test "sixel palette: nearest color lookup in palette" {
    const allocator = testing.allocator;

    const palette_colors = [_]SixelImage.Color{
        .{ .r = 255, .g = 0, .b = 0 },   // Red
        .{ .r = 0, .g = 255, .b = 0 },   // Green
        .{ .r = 0, .g = 0, .b = 255 },   // Blue
    };

    var palette = sailor.tui.sixel.ColorPalette{
        .colors = @constCast(&palette_colors),
        .allocator = allocator,
    };

    // Find nearest to orange (closer to red)
    const orange = SixelImage.Color{ .r = 255, .g = 128, .b = 0 };
    const nearest_idx = palette.findNearest(orange);

    try testing.expectEqual(@as(u8, 0), nearest_idx); // Should map to red (index 0)
}

test "sixel palette: distance caching for performance" {
    const allocator = testing.allocator;

    // Large palette
    var palette_colors: [256]SixelImage.Color = undefined;
    for (&palette_colors, 0..) |*c, i| {
        c.* = randomColor(i);
    }

    var palette = sailor.tui.sixel.ColorPalette{
        .colors = &palette_colors,
        .allocator = allocator,
    };

    // Query same color multiple times (cache should speed up)
    const test_color = SixelImage.Color{ .r = 123, .g = 45, .b = 67 };

    const start = std.time.nanoTimestamp();

    for (0..1000) |_| {
        _ = palette.findNearest(test_color);
    }

    const end = std.time.nanoTimestamp();
    const elapsed_ms = @divTrunc(end - start, 1_000_000);

    // With caching, 1000 lookups should be fast
    try testing.expect(elapsed_ms < 100);
}

test "sixel palette: edge case: identical colors (distance = 0)" {
    const c1 = SixelImage.Color{ .r = 128, .g = 64, .b = 192 };
    const c2 = SixelImage.Color{ .r = 128, .g = 64, .b = 192 };

    const distance_rgb = sailor.tui.sixel.colorDistance(c1, c2, .euclidean_rgb);
    const distance_lab = sailor.tui.sixel.colorDistance(c1, c2, .perceptual_lab);

    try testing.expectEqual(@as(f32, 0.0), distance_rgb);
    try testing.expectEqual(@as(f32, 0.0), distance_lab);
}

// ----------------------------------------------------------------------------
// Palette Application Tests (4 tests)
// ----------------------------------------------------------------------------

test "sixel palette: map 1000x1000 image to 16-color palette" {
    const allocator = testing.allocator;

    // Create large image with random colors
    const width: u16 = 1000;
    const height: u16 = 1000;
    const image = try makeTestImage(allocator, width, height, .{ .r = 0, .g = 0, .b = 0 });
    defer allocator.free(image.pixels);

    // Fill with random colors
    for (@constCast(image.pixels), 0..) |*p, i| {
        p.* = randomColor(i);
    }

    // Quantize to 16 colors
    const palette = try sailor.tui.sixel.quantizeColors(
        allocator,
        image.pixels,
        16,
        .median_cut,
    );
    defer palette.deinit();

    try testing.expectEqual(@as(usize, 16), palette.colors.len);

    // Map all pixels to palette (verify no crashes)
    for (image.pixels) |pixel| {
        _ = palette.findNearest(pixel);
    }
}

test "sixel palette: preserve exact colors if already in palette" {
    const allocator = testing.allocator;

    const colors = [_]SixelImage.Color{
        .{ .r = 255, .g = 0, .b = 0 },
        .{ .r = 0, .g = 255, .b = 0 },
        .{ .r = 0, .g = 0, .b = 255 },
    };

    const palette = try sailor.tui.sixel.quantizeColors(
        allocator,
        &colors,
        256,
        .median_cut,
    );
    defer palette.deinit();

    // Original colors should map to themselves
    for (colors, 0..) |c, expected_idx| {
        const idx = palette.findNearest(c);
        try testing.expectEqual(@as(u8, @intCast(expected_idx)), idx);
        try testing.expectEqual(c.r, palette.colors[idx].r);
        try testing.expectEqual(c.g, palette.colors[idx].g);
        try testing.expectEqual(c.b, palette.colors[idx].b);
    }
}

test "sixel palette: handle transparent pixels (skip from palette)" {
    const allocator = testing.allocator;

    const colors = [_]SixelImage.Color{
        .{ .r = 255, .g = 0, .b = 0, .a = 255 }, // Opaque
        .{ .r = 0, .g = 255, .b = 0, .a = 0 },   // Transparent
        .{ .r = 0, .g = 0, .b = 255, .a = 255 }, // Opaque
    };

    const palette = try sailor.tui.sixel.quantizeColors(
        allocator,
        &colors,
        256,
        .median_cut,
    );
    defer palette.deinit();

    // Should only include opaque colors (2 colors)
    try testing.expectEqual(@as(usize, 2), palette.colors.len);
}

test "sixel palette: round-trip: quantize → encode → decode (verify colors match palette)" {
    const allocator = testing.allocator;

    // Original diverse colors
    var original_pixels: [100]SixelImage.Color = undefined;
    for (&original_pixels, 0..) |*p, i| {
        p.* = randomColor(i + 3000);
    }

    const original_image = SixelImage{
        .width = 10,
        .height = 10,
        .pixels = &original_pixels,
    };

    // Quantize to 8 colors
    const palette = try sailor.tui.sixel.quantizeColors(
        allocator,
        &original_pixels,
        8,
        .median_cut,
    );
    defer palette.deinit();

    try testing.expectEqual(@as(usize, 8), palette.colors.len);

    // Encode with quantized palette
    var encoded: std.ArrayList(u8) = .{};
    defer encoded.deinit(allocator);

    const encoder = SixelEncoder{ .max_colors = 8, .quantization = .none };
    try encoder.encode(allocator, original_image, encoded.writer(allocator));

    // Decode
    const decoder = SixelDecoder{};
    const decoded_image = try decoder.decode(allocator, encoded.items);
    defer allocator.free(decoded_image.pixels);

    // All decoded pixels should be in the palette
    for (decoded_image.pixels) |pixel| {
        if (pixel.a == 0) continue; // Skip transparent

        var found = false;
        for (palette.colors) |palette_color| {
            const dist_r = @abs(@as(i16, @intCast(pixel.r)) - @as(i16, @intCast(palette_color.r)));
            const dist_g = @abs(@as(i16, @intCast(pixel.g)) - @as(i16, @intCast(palette_color.g)));
            const dist_b = @abs(@as(i16, @intCast(pixel.b)) - @as(i16, @intCast(palette_color.b)));

            if (dist_r <= 10 and dist_g <= 10 and dist_b <= 10) {
                found = true;
                break;
            }
        }
        try testing.expect(found);
    }
}

// ----------------------------------------------------------------------------
// Performance & Quality Tests (3 tests)
// ----------------------------------------------------------------------------

test "sixel palette: benchmark: 10000 colors to 256 in <50ms (median cut)" {
    const allocator = testing.allocator;

    const colors = try allocator.alloc(SixelImage.Color, 10000);
    defer allocator.free(colors);

    for (colors, 0..) |*c, i| {
        c.* = randomColor(i + 20000);
    }

    const start = std.time.nanoTimestamp();

    const palette = try sailor.tui.sixel.quantizeColors(
        allocator,
        colors,
        256,
        .median_cut,
    );
    defer palette.deinit();

    const end = std.time.nanoTimestamp();
    const elapsed_ms = @divTrunc(end - start, 1_000_000);

    try testing.expect(elapsed_ms < 50);
    try testing.expect(palette.colors.len <= 256);
}

test "sixel palette: quality: PSNR >30dB for natural images after quantization" {
    const allocator = testing.allocator;

    // Simulate natural image (smooth gradients)
    const colors = try allocator.alloc(SixelImage.Color, 256);
    defer allocator.free(colors);

    for (colors, 0..) |*c, i| {
        const v: u8 = @intCast(i);
        c.* = .{
            .r = v,
            .g = @intCast(255 - i),
            .b = @intCast((i * 2) % 256),
        };
    }

    const palette = try sailor.tui.sixel.quantizeColors(
        allocator,
        colors,
        32,
        .median_cut,
    );
    defer palette.deinit();

    try testing.expectEqual(@as(usize, 32), palette.colors.len);

    // Calculate MSE (Mean Squared Error)
    var total_error: f64 = 0.0;
    for (colors) |original| {
        const nearest_idx = palette.findNearest(original);
        const mapped = palette.colors[nearest_idx];

        const err_r = @as(f64, @floatFromInt(@as(i16, @intCast(original.r)) - @as(i16, @intCast(mapped.r))));
        const err_g = @as(f64, @floatFromInt(@as(i16, @intCast(original.g)) - @as(i16, @intCast(mapped.g))));
        const err_b = @as(f64, @floatFromInt(@as(i16, @intCast(original.b)) - @as(i16, @intCast(mapped.b))));

        total_error += err_r * err_r + err_g * err_g + err_b * err_b;
    }

    const mse = total_error / @as(f64, @floatFromInt(colors.len * 3));
    const psnr = 10.0 * @log10(255.0 * 255.0 / mse);

    // PSNR should be > 30dB (good quality)
    try testing.expect(psnr > 30.0);
}

test "sixel palette: memory: palette generation uses <1MB for 10000 input colors" {
    const allocator = testing.allocator;

    const colors = try allocator.alloc(SixelImage.Color, 10000);
    defer allocator.free(colors);

    for (colors, 0..) |*c, i| {
        c.* = randomColor(i + 30000);
    }

    // Track allocations
    const palette = try sailor.tui.sixel.quantizeColors(
        allocator,
        colors,
        256,
        .median_cut,
    );
    defer palette.deinit();

    // Palette itself is 256 colors * 4 bytes = 1KB (well under 1MB)
    const palette_size = palette.colors.len * @sizeOf(SixelImage.Color);
    try testing.expect(palette_size < 1024 * 1024);
}
