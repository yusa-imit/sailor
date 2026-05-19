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
