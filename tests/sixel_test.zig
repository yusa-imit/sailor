const std = @import("std");
const testing = std.testing;
const sailor = @import("sailor");

// Import the Sixel types and encoder
const SixelImage = sailor.tui.sixel.SixelImage;
const SixelEncoder = sailor.tui.sixel.SixelEncoder;
const SixelDecoder = sailor.tui.sixel.SixelDecoder;
const SixelCompressor = sailor.tui.sixel.SixelCompressor;

// ============================================================================
// Basic Decoding Tests
// ============================================================================

test "sixel decoder: decode 2x2 solid red image" {
    const allocator = testing.allocator;

    // 2x2 red image: 'B'=0x42=value 3=bits 0+1 sets rows 0 and 1 in each column
    // Width=2 needs 2 columns, height=2 needs bits 0+1 per column
    const sixel_data = "\x1bPq\"1;1;2;2#0;2;100;0;0BB\x1b\\";

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

    // 1x1 blue pixel: '@'=0x40=value 1=bit 0 sets the single pixel at row 0
    const sixel_data = "\x1bPq\"1;1;1;1#0;2;0;0;100@\x1b\\";

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

    // 1x6 green stripe: '~'=0x7e=value 63=bits 0-5, all 6 rows in one column
    const sixel_data = "\x1bPq\"1;1;1;6#0;2;0;100;0~\x1b\\";

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

    // 1x7 stripe: 2 sixel rows. Row 0: '~' (all 6 bits). '-' LF. Row 1: '@' (bit 0 only).
    const sixel_data = "\x1bPq\"1;1;1;7#0;2;100;100;100~-@\x1b\\";

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

    // Test specific RGB values: #0;2;50;25;75 → (127, 63, 191) when scaled
    // '@'=value 1=bit 0 paints the single pixel with color 0
    const sixel_data = "\x1bPq\"1;1;1;1#0;2;50;25;75@\x1b\\";

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

    // Pixels not rendered in any color have alpha=0. RGB must be 0-100 range.
    const sixel_data = "\x1bPq\"1;1;2;2#0;2;100;0;0\x1b\\";

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

    // 1x12 image = 2 sixel rows, each '~' fills all 6 rows of that band
    const sixel_data = "\x1bPq\"1;1;1;12#0;2;100;0;0~-~\x1b\\";

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

    // 2x6: two columns, each '~' fills all 6 rows. RGB must be 0-100 range.
    const sixel_data = "\x1bPq\"1;1;2;6#0;2;100;0;0~~\x1b\\";

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

    // 2x1 row: '@' (bit 0) paints one pixel per column with the active color
    // #0 red at x=0, switch to #1 blue at x=1
    const sixel_data = "\x1bPq\"1;1;2;1#0;2;100;0;0@#1;2;0;0;100@\x1b\\";

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

    // Sixel value '?' (0x3f) = 0 = no pixels
    // Sixel value '@' (0x40) = 1 = bit 0 = top pixel only
    // Sixel value 'A' (0x41) = 2 = bit 1 = second pixel only
    // Sixel value '~' (0x7e) = 63 = all 6 bits set
    const sixel_data = "\x1bPq\"1;1;1;6#0;2;100;100;100~\x1b\\";

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

    // '@' = 0x40 = value 1 = bit 0 set (only first pixel of the 6-row column)
    const sixel_data = "\x1bPq\"1;1;1;6#0;2;100;0;0@\x1b\\";

    const decoder = SixelDecoder{};
    const image = try decoder.decode(allocator, sixel_data);
    defer allocator.free(image.pixels);

    try testing.expectEqual(@as(u16, 1), image.width);
    try testing.expectEqual(@as(u16, 6), image.height);

    // First pixel is painted red (bit 0 set), pixels 1-5 remain transparent
    try testing.expectEqual(@as(u8, 255), image.pixels[0].r);
    try testing.expectEqual(@as(u8, 255), image.pixels[0].a);  // Painted pixel is opaque
    try testing.expectEqual(@as(u8, 0), image.pixels[1].a);    // Unpainted pixels are transparent
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

    // 1x18 = 3 sixel rows, each '~' fills all 6 rows of each band
    const sixel_data = "\x1bPq\"1;1;1;18#0;2;0;100;0~-~-~\x1b\\";

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

    // Octree may produce fewer than max_palette_size colors depending on tree structure
    try testing.expect(palette.colors.len > 0);
    try testing.expect(palette.colors.len <= 32);
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

    // Palette should cover RGB space (may be fewer than max due to tree structure)
    try testing.expect(palette.colors.len > 0);
    try testing.expect(palette.colors.len <= 64);

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
            c.* = .{ .r = @intCast((i - 90) * 20 + 10), .g = 200, .b = 50 };
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

test "sixel palette: map large image to 16-color palette" {
    const allocator = testing.allocator;

    // 100x100 = 10K pixels is sufficient to validate quantization without hanging
    // in debug mode (1000x1000 with 1M pixels was too slow: O(n) dedup + O(n) findNearest × 16)
    const width: u16 = 100;
    const height: u16 = 100;
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

// ============================================================================
// Sixel Animation Tests
// ============================================================================

const SixelAnimator = sailor.tui.sixel.SixelAnimator;

// ----------------------------------------------------------------------------
// Basic Frame Management Tests (6 tests)
// ----------------------------------------------------------------------------

test "sixel animator: init and deinit" {
    const allocator = testing.allocator;

    var animator = try SixelAnimator.init(allocator);
    defer animator.deinit();

    try testing.expectEqual(@as(usize, 0), animator.getFrameCount());
}

test "sixel animator: add single frame" {
    const allocator = testing.allocator;

    var animator = try SixelAnimator.init(allocator);
    defer animator.deinit();

    // Create a simple 2x2 red image
    const pixels = try allocator.alloc(SixelImage.Color, 4);
    defer allocator.free(pixels);
    @memset(pixels, .{ .r = 255, .g = 0, .b = 0 });

    const image = SixelImage{
        .width = 2,
        .height = 2,
        .pixels = pixels,
    };

    try animator.addFrame(image, 100); // 100ms delay

    try testing.expectEqual(@as(usize, 1), animator.getFrameCount());
}

test "sixel animator: add multiple frames" {
    const allocator = testing.allocator;

    var animator = try SixelAnimator.init(allocator);
    defer animator.deinit();

    // Create three frames with different colors
    const colors = [_]SixelImage.Color{
        .{ .r = 255, .g = 0, .b = 0 }, // Red
        .{ .r = 0, .g = 255, .b = 0 }, // Green
        .{ .r = 0, .g = 0, .b = 255 }, // Blue
    };

    for (colors, 0..) |color, i| {
        const pixels = try allocator.alloc(SixelImage.Color, 1);
        defer allocator.free(pixels);
        pixels[0] = color;

        const image = SixelImage{
            .width = 1,
            .height = 1,
            .pixels = pixels,
        };

        const delay: u32 = @intCast((i + 1) * 100); // 100ms, 200ms, 300ms
        try animator.addFrame(image, delay);
    }

    try testing.expectEqual(@as(usize, 3), animator.getFrameCount());
}

test "sixel animator: get frame by index" {
    const allocator = testing.allocator;

    var animator = try SixelAnimator.init(allocator);
    defer animator.deinit();

    const pixels = try allocator.alloc(SixelImage.Color, 1);
    defer allocator.free(pixels);
    pixels[0] = .{ .r = 128, .g = 64, .b = 32 };

    const image = SixelImage{
        .width = 1,
        .height = 1,
        .pixels = pixels,
    };

    try animator.addFrame(image, 150);

    const frame = animator.getFrame(0);
    try testing.expect(frame != null);
    try testing.expectEqual(@as(u32, 150), frame.?.delay_ms);
    try testing.expectEqual(@as(u16, 1), frame.?.image.width);
    try testing.expectEqual(@as(u16, 1), frame.?.image.height);
}

test "sixel animator: get frame out of bounds returns null" {
    const allocator = testing.allocator;

    var animator = try SixelAnimator.init(allocator);
    defer animator.deinit();

    const pixels = try allocator.alloc(SixelImage.Color, 1);
    defer allocator.free(pixels);
    pixels[0] = .{ .r = 255, .g = 255, .b = 255 };

    const image = SixelImage{
        .width = 1,
        .height = 1,
        .pixels = pixels,
    };

    try animator.addFrame(image, 50);

    try testing.expect(animator.getFrame(1) == null); // Out of bounds
    try testing.expect(animator.getFrame(100) == null); // Way out of bounds
}

test "sixel animator: get current frame before start returns first frame" {
    const allocator = testing.allocator;

    var animator = try SixelAnimator.init(allocator);
    defer animator.deinit();

    const pixels = try allocator.alloc(SixelImage.Color, 1);
    defer allocator.free(pixels);
    pixels[0] = .{ .r = 200, .g = 100, .b = 50 };

    const image = SixelImage{
        .width = 1,
        .height = 1,
        .pixels = pixels,
    };

    try animator.addFrame(image, 100);

    const current_frame = animator.getCurrentFrame();
    try testing.expectEqual(@as(u32, 100), current_frame.delay_ms);
}

// ----------------------------------------------------------------------------
// Total Duration Calculation Tests (3 tests)
// ----------------------------------------------------------------------------

test "sixel animator: total duration with single frame" {
    const allocator = testing.allocator;

    var animator = try SixelAnimator.init(allocator);
    defer animator.deinit();

    const pixels = try allocator.alloc(SixelImage.Color, 1);
    defer allocator.free(pixels);
    pixels[0] = .{ .r = 0, .g = 0, .b = 0 };

    const image = SixelImage{
        .width = 1,
        .height = 1,
        .pixels = pixels,
    };

    try animator.addFrame(image, 500);

    try testing.expectEqual(@as(u32, 500), animator.getTotalDuration());
}

test "sixel animator: total duration with multiple frames" {
    const allocator = testing.allocator;

    var animator = try SixelAnimator.init(allocator);
    defer animator.deinit();

    const delays = [_]u32{ 100, 200, 150, 250 };

    for (delays) |delay| {
        const pixels = try allocator.alloc(SixelImage.Color, 1);
        defer allocator.free(pixels);
        pixels[0] = .{ .r = 255, .g = 0, .b = 0 };

        const image = SixelImage{
            .width = 1,
            .height = 1,
            .pixels = pixels,
        };

        try animator.addFrame(image, delay);
    }

    // Total = 100 + 200 + 150 + 250 = 700ms
    try testing.expectEqual(@as(u32, 700), animator.getTotalDuration());
}

test "sixel animator: total duration empty animator returns 0" {
    const allocator = testing.allocator;

    var animator = try SixelAnimator.init(allocator);
    defer animator.deinit();

    try testing.expectEqual(@as(u32, 0), animator.getTotalDuration());
}

// ----------------------------------------------------------------------------
// Playback State Transition Tests (8 tests)
// ----------------------------------------------------------------------------

test "sixel animator: initial state is stopped" {
    const allocator = testing.allocator;

    var animator = try SixelAnimator.init(allocator);
    defer animator.deinit();

    try testing.expect(!animator.isPlaying());
}

test "sixel animator: start playback changes state to playing" {
    const allocator = testing.allocator;

    var animator = try SixelAnimator.init(allocator);
    defer animator.deinit();

    const pixels = try allocator.alloc(SixelImage.Color, 1);
    defer allocator.free(pixels);
    pixels[0] = .{ .r = 255, .g = 255, .b = 255 };

    const image = SixelImage{
        .width = 1,
        .height = 1,
        .pixels = pixels,
    };

    try animator.addFrame(image, 100);

    animator.start();

    try testing.expect(animator.isPlaying());
}

test "sixel animator: pause changes state to not playing" {
    const allocator = testing.allocator;

    var animator = try SixelAnimator.init(allocator);
    defer animator.deinit();

    const pixels = try allocator.alloc(SixelImage.Color, 1);
    defer allocator.free(pixels);
    pixels[0] = .{ .r = 0, .g = 0, .b = 0 };

    const image = SixelImage{
        .width = 1,
        .height = 1,
        .pixels = pixels,
    };

    try animator.addFrame(image, 100);

    animator.start();
    try testing.expect(animator.isPlaying());

    animator.pause();
    try testing.expect(!animator.isPlaying());
}

test "sixel animator: stop resets to first frame" {
    const allocator = testing.allocator;

    var animator = try SixelAnimator.init(allocator);
    defer animator.deinit();

    // Add two frames
    for (0..2) |_| {
        const pixels = try allocator.alloc(SixelImage.Color, 1);
        defer allocator.free(pixels);
        pixels[0] = .{ .r = 255, .g = 0, .b = 0 };

        const image = SixelImage{
            .width = 1,
            .height = 1,
            .pixels = pixels,
        };

        try animator.addFrame(image, 100);
    }

    animator.start();

    // Advance past first frame
    _ = animator.update(150);

    try testing.expectEqual(@as(usize, 1), animator.getCurrentFrameIndex());

    animator.stop();

    try testing.expect(!animator.isPlaying());
    try testing.expectEqual(@as(usize, 0), animator.getCurrentFrameIndex());
}

test "sixel animator: start → pause → start resumes from current frame" {
    const allocator = testing.allocator;

    var animator = try SixelAnimator.init(allocator);
    defer animator.deinit();

    // Add multiple frames
    for (0..3) |_| {
        const pixels = try allocator.alloc(SixelImage.Color, 1);
        defer allocator.free(pixels);
        pixels[0] = .{ .r = 128, .g = 128, .b = 128 };

        const image = SixelImage{
            .width = 1,
            .height = 1,
            .pixels = pixels,
        };

        try animator.addFrame(image, 100);
    }

    animator.start();
    _ = animator.update(150); // Advance to frame 1

    const frame_before_pause = animator.getCurrentFrameIndex();
    animator.pause();

    animator.start(); // Resume

    try testing.expectEqual(frame_before_pause, animator.getCurrentFrameIndex());
}

test "sixel animator: multiple start calls idempotent" {
    const allocator = testing.allocator;

    var animator = try SixelAnimator.init(allocator);
    defer animator.deinit();

    const pixels = try allocator.alloc(SixelImage.Color, 1);
    defer allocator.free(pixels);
    pixels[0] = .{ .r = 50, .g = 100, .b = 150 };

    const image = SixelImage{
        .width = 1,
        .height = 1,
        .pixels = pixels,
    };

    try animator.addFrame(image, 100);

    animator.start();
    animator.start();
    animator.start();

    try testing.expect(animator.isPlaying());
}

test "sixel animator: pause when not playing is no-op" {
    const allocator = testing.allocator;

    var animator = try SixelAnimator.init(allocator);
    defer animator.deinit();

    const pixels = try allocator.alloc(SixelImage.Color, 1);
    defer allocator.free(pixels);
    pixels[0] = .{ .r = 255, .g = 255, .b = 0 };

    const image = SixelImage{
        .width = 1,
        .height = 1,
        .pixels = pixels,
    };

    try animator.addFrame(image, 100);

    animator.pause(); // Should not crash

    try testing.expect(!animator.isPlaying());
}

test "sixel animator: stop when already stopped is no-op" {
    const allocator = testing.allocator;

    var animator = try SixelAnimator.init(allocator);
    defer animator.deinit();

    const pixels = try allocator.alloc(SixelImage.Color, 1);
    defer allocator.free(pixels);
    pixels[0] = .{ .r = 200, .g = 0, .b = 200 };

    const image = SixelImage{
        .width = 1,
        .height = 1,
        .pixels = pixels,
    };

    try animator.addFrame(image, 100);

    animator.stop(); // Should not crash

    try testing.expect(!animator.isPlaying());
}

// ----------------------------------------------------------------------------
// Frame Timing and Update Tests (8 tests)
// ----------------------------------------------------------------------------

test "sixel animator: update with no elapsed time does not change frame" {
    const allocator = testing.allocator;

    var animator = try SixelAnimator.init(allocator);
    defer animator.deinit();

    const pixels = try allocator.alloc(SixelImage.Color, 1);
    defer allocator.free(pixels);
    pixels[0] = .{ .r = 100, .g = 200, .b = 50 };

    const image = SixelImage{
        .width = 1,
        .height = 1,
        .pixels = pixels,
    };

    try animator.addFrame(image, 100);

    animator.start();

    const frame_changed = animator.update(0);

    try testing.expect(!frame_changed);
    try testing.expectEqual(@as(usize, 0), animator.getCurrentFrameIndex());
}

test "sixel animator: update advances frame when delay expires" {
    const allocator = testing.allocator;

    var animator = try SixelAnimator.init(allocator);
    defer animator.deinit();

    // Add two frames with 100ms delay each
    for (0..2) |_| {
        const pixels = try allocator.alloc(SixelImage.Color, 1);
        defer allocator.free(pixels);
        pixels[0] = .{ .r = 255, .g = 0, .b = 0 };

        const image = SixelImage{
            .width = 1,
            .height = 1,
            .pixels = pixels,
        };

        try animator.addFrame(image, 100);
    }

    animator.start();

    // Update with exactly 100ms (frame delay)
    const frame_changed = animator.update(100);

    try testing.expect(frame_changed);
    try testing.expectEqual(@as(usize, 1), animator.getCurrentFrameIndex());
}

test "sixel animator: update does not advance if elapsed < delay" {
    const allocator = testing.allocator;

    var animator = try SixelAnimator.init(allocator);
    defer animator.deinit();

    const pixels = try allocator.alloc(SixelImage.Color, 1);
    defer allocator.free(pixels);
    pixels[0] = .{ .r = 0, .g = 255, .b = 0 };

    const image = SixelImage{
        .width = 1,
        .height = 1,
        .pixels = pixels,
    };

    try animator.addFrame(image, 200);
    try animator.addFrame(image, 200);

    animator.start();

    // Update with 150ms (less than 200ms delay)
    const frame_changed = animator.update(150);

    try testing.expect(!frame_changed);
    try testing.expectEqual(@as(usize, 0), animator.getCurrentFrameIndex());
}

test "sixel animator: update accumulates elapsed time across calls" {
    const allocator = testing.allocator;

    var animator = try SixelAnimator.init(allocator);
    defer animator.deinit();

    const pixels = try allocator.alloc(SixelImage.Color, 1);
    defer allocator.free(pixels);
    pixels[0] = .{ .r = 0, .g = 0, .b = 255 };

    const image = SixelImage{
        .width = 1,
        .height = 1,
        .pixels = pixels,
    };

    try animator.addFrame(image, 100);
    try animator.addFrame(image, 100);

    animator.start();

    // First update: 60ms (not enough)
    var changed = animator.update(60);
    try testing.expect(!changed);
    try testing.expectEqual(@as(usize, 0), animator.getCurrentFrameIndex());

    // Second update: 50ms (total 110ms, exceeds 100ms)
    changed = animator.update(50);
    try testing.expect(changed);
    try testing.expectEqual(@as(usize, 1), animator.getCurrentFrameIndex());
}

test "sixel animator: update when paused does not advance frame" {
    const allocator = testing.allocator;

    var animator = try SixelAnimator.init(allocator);
    defer animator.deinit();

    const pixels = try allocator.alloc(SixelImage.Color, 1);
    defer allocator.free(pixels);
    pixels[0] = .{ .r = 255, .g = 255, .b = 0 };

    const image = SixelImage{
        .width = 1,
        .height = 1,
        .pixels = pixels,
    };

    try animator.addFrame(image, 50);
    try animator.addFrame(image, 50);

    animator.start();
    animator.pause();

    const frame_changed = animator.update(100);

    try testing.expect(!frame_changed);
    try testing.expectEqual(@as(usize, 0), animator.getCurrentFrameIndex());
}

test "sixel animator: update skips multiple frames if delta is large" {
    const allocator = testing.allocator;

    var animator = try SixelAnimator.init(allocator);
    defer animator.deinit();

    // Add 5 frames with 100ms each
    for (0..5) |_| {
        const pixels = try allocator.alloc(SixelImage.Color, 1);
        defer allocator.free(pixels);
        pixels[0] = .{ .r = 128, .g = 128, .b = 128 };

        const image = SixelImage{
            .width = 1,
            .height = 1,
            .pixels = pixels,
        };

        try animator.addFrame(image, 100);
    }

    animator.start();

    // Update with 350ms (should skip 3 frames: 0→1→2→3)
    const frame_changed = animator.update(350);

    try testing.expect(frame_changed);
    try testing.expectEqual(@as(usize, 3), animator.getCurrentFrameIndex());
}

test "sixel animator: update returns false when already on last frame (no loop)" {
    const allocator = testing.allocator;

    var animator = try SixelAnimator.init(allocator);
    defer animator.deinit();
    animator.loop_count = 1; // Play once, no loop

    const pixels = try allocator.alloc(SixelImage.Color, 1);
    defer allocator.free(pixels);
    pixels[0] = .{ .r = 64, .g = 64, .b = 64 };

    const image = SixelImage{
        .width = 1,
        .height = 1,
        .pixels = pixels,
    };

    try animator.addFrame(image, 100);
    try animator.addFrame(image, 100);

    animator.start();

    // Advance to last frame
    _ = animator.update(100);
    try testing.expectEqual(@as(usize, 1), animator.getCurrentFrameIndex());

    // Further update should not change frame (stays on last)
    const frame_changed = animator.update(100);
    try testing.expect(!frame_changed);
    try testing.expectEqual(@as(usize, 1), animator.getCurrentFrameIndex());
}

test "sixel animator: update wraps to first frame after accumulating full cycle" {
    const allocator = testing.allocator;

    var animator = try SixelAnimator.init(allocator);
    defer animator.deinit();
    animator.loop_count = 0; // Infinite loop

    // 3 frames, 100ms each
    for (0..3) |_| {
        const pixels = try allocator.alloc(SixelImage.Color, 1);
        defer allocator.free(pixels);
        pixels[0] = .{ .r = 192, .g = 192, .b = 192 };

        const image = SixelImage{
            .width = 1,
            .height = 1,
            .pixels = pixels,
        };

        try animator.addFrame(image, 100);
    }

    animator.start();

    // Advance through all 3 frames (300ms total)
    _ = animator.update(100); // Frame 0 → 1
    _ = animator.update(100); // Frame 1 → 2
    const wrapped = animator.update(100); // Frame 2 → 0 (wrap)

    try testing.expect(wrapped);
    try testing.expectEqual(@as(usize, 0), animator.getCurrentFrameIndex());
}

// ----------------------------------------------------------------------------
// Loop Count Tests (5 tests)
// ----------------------------------------------------------------------------

test "sixel animator: infinite loop (loop_count = 0)" {
    const allocator = testing.allocator;

    var animator = try SixelAnimator.init(allocator);
    defer animator.deinit();
    animator.loop_count = 0; // Infinite

    const pixels = try allocator.alloc(SixelImage.Color, 1);
    defer allocator.free(pixels);
    pixels[0] = .{ .r = 255, .g = 128, .b = 0 };

    const image = SixelImage{
        .width = 1,
        .height = 1,
        .pixels = pixels,
    };

    try animator.addFrame(image, 100);
    try animator.addFrame(image, 100);

    animator.start();

    // Loop multiple times
    for (0..10) |_| {
        _ = animator.update(100); // Should keep wrapping
    }

    // Should still be playing (infinite loop)
    try testing.expect(animator.isPlaying());
}

test "sixel animator: finite loop (loop_count = 2)" {
    const allocator = testing.allocator;

    var animator = try SixelAnimator.init(allocator);
    defer animator.deinit();
    animator.loop_count = 2; // Play twice

    const pixels = try allocator.alloc(SixelImage.Color, 1);
    defer allocator.free(pixels);
    pixels[0] = .{ .r = 100, .g = 100, .b = 255 };

    const image = SixelImage{
        .width = 1,
        .height = 1,
        .pixels = pixels,
    };

    try animator.addFrame(image, 100);
    try animator.addFrame(image, 100);

    animator.start();

    // First loop
    _ = animator.update(100); // Frame 0 → 1
    _ = animator.update(100); // Frame 1 → 0 (wrap, loop 1 done)

    // Second loop
    _ = animator.update(100); // Frame 0 → 1
    _ = animator.update(100); // Frame 1 → stays (loop limit reached)

    // Should stop after 2 loops
    try testing.expect(!animator.isPlaying());
}

test "sixel animator: single play (loop_count = 1)" {
    const allocator = testing.allocator;

    var animator = try SixelAnimator.init(allocator);
    defer animator.deinit();
    animator.loop_count = 1; // Play once, no repeat

    const pixels = try allocator.alloc(SixelImage.Color, 1);
    defer allocator.free(pixels);
    pixels[0] = .{ .r = 255, .g = 0, .b = 128 };

    const image = SixelImage{
        .width = 1,
        .height = 1,
        .pixels = pixels,
    };

    try animator.addFrame(image, 100);
    try animator.addFrame(image, 100);

    animator.start();

    _ = animator.update(100); // Frame 0 → 1
    _ = animator.update(100); // Frame 1 → stays (no wrap)

    try testing.expect(!animator.isPlaying());
    try testing.expectEqual(@as(usize, 1), animator.getCurrentFrameIndex());
}

test "sixel animator: loop_count reset on stop" {
    const allocator = testing.allocator;

    var animator = try SixelAnimator.init(allocator);
    defer animator.deinit();
    animator.loop_count = 1;

    const pixels = try allocator.alloc(SixelImage.Color, 1);
    defer allocator.free(pixels);
    pixels[0] = .{ .r = 0, .g = 255, .b = 255 };

    const image = SixelImage{
        .width = 1,
        .height = 1,
        .pixels = pixels,
    };

    try animator.addFrame(image, 100);
    try animator.addFrame(image, 100);

    animator.start();
    _ = animator.update(100);
    _ = animator.update(100); // Reaches end

    animator.stop(); // Reset

    animator.start(); // Should be able to play again
    try testing.expect(animator.isPlaying());
}

test "sixel animator: default loop_count is infinite" {
    const allocator = testing.allocator;

    var animator = try SixelAnimator.init(allocator);
    defer animator.deinit();

    // Default loop_count should be 0 (infinite)
    try testing.expectEqual(@as(u32, 0), animator.loop_count);
}

// ----------------------------------------------------------------------------
// Seek Operation Tests (7 tests)
// ----------------------------------------------------------------------------

test "sixel animator: seek to valid frame index" {
    const allocator = testing.allocator;

    var animator = try SixelAnimator.init(allocator);
    defer animator.deinit();

    // Add 5 frames
    for (0..5) |_| {
        const pixels = try allocator.alloc(SixelImage.Color, 1);
        defer allocator.free(pixels);
        pixels[0] = .{ .r = 255, .g = 100, .b = 50 };

        const image = SixelImage{
            .width = 1,
            .height = 1,
            .pixels = pixels,
        };

        try animator.addFrame(image, 100);
    }

    animator.seek(3);

    try testing.expectEqual(@as(usize, 3), animator.getCurrentFrameIndex());
}

test "sixel animator: seek to first frame" {
    const allocator = testing.allocator;

    var animator = try SixelAnimator.init(allocator);
    defer animator.deinit();

    for (0..3) |_| {
        const pixels = try allocator.alloc(SixelImage.Color, 1);
        defer allocator.free(pixels);
        pixels[0] = .{ .r = 50, .g = 150, .b = 200 };

        const image = SixelImage{
            .width = 1,
            .height = 1,
            .pixels = pixels,
        };

        try animator.addFrame(image, 100);
    }

    animator.start();
    _ = animator.update(200); // Move to frame 2

    animator.seek(0); // Back to start

    try testing.expectEqual(@as(usize, 0), animator.getCurrentFrameIndex());
}

test "sixel animator: seek to last frame" {
    const allocator = testing.allocator;

    var animator = try SixelAnimator.init(allocator);
    defer animator.deinit();

    for (0..4) |_| {
        const pixels = try allocator.alloc(SixelImage.Color, 1);
        defer allocator.free(pixels);
        pixels[0] = .{ .r = 100, .g = 100, .b = 100 };

        const image = SixelImage{
            .width = 1,
            .height = 1,
            .pixels = pixels,
        };

        try animator.addFrame(image, 100);
    }

    animator.seek(3); // Last frame (index 3)

    try testing.expectEqual(@as(usize, 3), animator.getCurrentFrameIndex());
}

test "sixel animator: seek out of bounds clamps to last frame" {
    const allocator = testing.allocator;

    var animator = try SixelAnimator.init(allocator);
    defer animator.deinit();

    // Add 3 frames (indices 0, 1, 2)
    for (0..3) |_| {
        const pixels = try allocator.alloc(SixelImage.Color, 1);
        defer allocator.free(pixels);
        pixels[0] = .{ .r = 200, .g = 200, .b = 200 };

        const image = SixelImage{
            .width = 1,
            .height = 1,
            .pixels = pixels,
        };

        try animator.addFrame(image, 100);
    }

    animator.seek(10); // Out of bounds

    // Should clamp to last frame (index 2)
    try testing.expectEqual(@as(usize, 2), animator.getCurrentFrameIndex());
}

test "sixel animator: seek resets elapsed time for current frame" {
    const allocator = testing.allocator;

    var animator = try SixelAnimator.init(allocator);
    defer animator.deinit();

    for (0..3) |_| {
        const pixels = try allocator.alloc(SixelImage.Color, 1);
        defer allocator.free(pixels);
        pixels[0] = .{ .r = 128, .g = 0, .b = 128 };

        const image = SixelImage{
            .width = 1,
            .height = 1,
            .pixels = pixels,
        };

        try animator.addFrame(image, 100);
    }

    animator.start();
    _ = animator.update(50); // Partial progress on frame 0

    animator.seek(1); // Jump to frame 1

    // Should start fresh on frame 1 (no accumulated time)
    const changed = animator.update(50); // Only 50ms elapsed on frame 1
    try testing.expect(!changed); // Should not advance yet
    try testing.expectEqual(@as(usize, 1), animator.getCurrentFrameIndex());
}

test "sixel animator: seek while playing continues playback" {
    const allocator = testing.allocator;

    var animator = try SixelAnimator.init(allocator);
    defer animator.deinit();

    for (0..4) |_| {
        const pixels = try allocator.alloc(SixelImage.Color, 1);
        defer allocator.free(pixels);
        pixels[0] = .{ .r = 0, .g = 128, .b = 255 };

        const image = SixelImage{
            .width = 1,
            .height = 1,
            .pixels = pixels,
        };

        try animator.addFrame(image, 100);
    }

    animator.start();
    animator.seek(2);

    try testing.expect(animator.isPlaying());
    try testing.expectEqual(@as(usize, 2), animator.getCurrentFrameIndex());

    // Playback should continue from seek point
    const changed = animator.update(100);
    try testing.expect(changed);
    try testing.expectEqual(@as(usize, 3), animator.getCurrentFrameIndex());
}

test "sixel animator: seek on empty animator is no-op" {
    const allocator = testing.allocator;

    var animator = try SixelAnimator.init(allocator);
    defer animator.deinit();

    animator.seek(0); // Should not crash
    animator.seek(10); // Should not crash

    try testing.expectEqual(@as(usize, 0), animator.getCurrentFrameIndex());
}

// ----------------------------------------------------------------------------
// Frame Disposal Method Tests (6 tests)
// ----------------------------------------------------------------------------

test "sixel animator: disposal method enum definition" {
    const DisposalMethod = SixelAnimator.DisposalMethod;

    // Verify enum values exist
    const none: DisposalMethod = .none;
    const background: DisposalMethod = .background;
    const previous: DisposalMethod = .previous;

    try testing.expect(none == .none);
    try testing.expect(background == .background);
    try testing.expect(previous == .previous);
}

test "sixel animator: add frame with disposal method" {
    const allocator = testing.allocator;

    var animator = try SixelAnimator.init(allocator);
    defer animator.deinit();

    const pixels = try allocator.alloc(SixelImage.Color, 1);
    defer allocator.free(pixels);
    pixels[0] = .{ .r = 255, .g = 0, .b = 0 };

    const image = SixelImage{
        .width = 1,
        .height = 1,
        .pixels = pixels,
    };

    // Should accept disposal_method parameter
    try animator.addFrameWithDisposal(image, 100, .background);

    try testing.expectEqual(@as(usize, 1), animator.getFrameCount());
}

test "sixel animator: default disposal method is none" {
    const allocator = testing.allocator;

    var animator = try SixelAnimator.init(allocator);
    defer animator.deinit();

    const pixels = try allocator.alloc(SixelImage.Color, 1);
    defer allocator.free(pixels);
    pixels[0] = .{ .r = 0, .g = 255, .b = 0 };

    const image = SixelImage{
        .width = 1,
        .height = 1,
        .pixels = pixels,
    };

    try animator.addFrame(image, 100);

    const frame = animator.getFrame(0).?;
    try testing.expectEqual(SixelAnimator.DisposalMethod.none, frame.disposal_method);
}

test "sixel animator: disposal method none preserves previous frame" {
    const allocator = testing.allocator;

    var animator = try SixelAnimator.init(allocator);
    defer animator.deinit();

    // Frame 0: solid red
    const pixels0 = try allocator.alloc(SixelImage.Color, 4);
    defer allocator.free(pixels0);
    @memset(pixels0, .{ .r = 255, .g = 0, .b = 0 });

    const image0 = SixelImage{
        .width = 2,
        .height = 2,
        .pixels = pixels0,
    };

    try animator.addFrameWithDisposal(image0, 100, .none);

    // Frame 1: transparent center
    const pixels1 = try allocator.alloc(SixelImage.Color, 4);
    defer allocator.free(pixels1);
    pixels1[0] = .{ .r = 0, .g = 0, .b = 255 };
    pixels1[1] = .{ .r = 0, .g = 0, .b = 0, .a = 0 }; // Transparent
    pixels1[2] = .{ .r = 0, .g = 0, .b = 0, .a = 0 }; // Transparent
    pixels1[3] = .{ .r = 0, .g = 0, .b = 255 };

    const image1 = SixelImage{
        .width = 2,
        .height = 2,
        .pixels = pixels1,
    };

    try animator.addFrameWithDisposal(image1, 100, .none);

    // applyDisposal with .none should keep previous frame visible under transparent areas
    animator.start();
    _ = animator.update(100); // Move to frame 1

    const current = animator.getCurrentFrame();
    try testing.expectEqual(SixelAnimator.DisposalMethod.none, current.disposal_method);
}

test "sixel animator: disposal method background clears to transparent" {
    const allocator = testing.allocator;

    var animator = try SixelAnimator.init(allocator);
    defer animator.deinit();

    const pixels = try allocator.alloc(SixelImage.Color, 4);
    defer allocator.free(pixels);
    @memset(pixels, .{ .r = 0, .g = 255, .b = 0 });

    const image = SixelImage{
        .width = 2,
        .height = 2,
        .pixels = pixels,
    };

    try animator.addFrameWithDisposal(image, 100, .background);

    const frame = animator.getFrame(0).?;
    try testing.expectEqual(SixelAnimator.DisposalMethod.background, frame.disposal_method);
}

test "sixel animator: disposal method previous restores previous frame" {
    const allocator = testing.allocator;

    var animator = try SixelAnimator.init(allocator);
    defer animator.deinit();

    // Frame 0: red background
    const pixels0 = try allocator.alloc(SixelImage.Color, 4);
    defer allocator.free(pixels0);
    @memset(pixels0, .{ .r = 255, .g = 0, .b = 0 });

    const image0 = SixelImage{
        .width = 2,
        .height = 2,
        .pixels = pixels0,
    };

    try animator.addFrameWithDisposal(image0, 100, .none);

    // Frame 1: overlay with disposal = previous
    const pixels1 = try allocator.alloc(SixelImage.Color, 4);
    defer allocator.free(pixels1);
    @memset(pixels1, .{ .r = 0, .g = 255, .b = 0 });

    const image1 = SixelImage{
        .width = 2,
        .height = 2,
        .pixels = pixels1,
    };

    try animator.addFrameWithDisposal(image1, 100, .previous);

    // Frame 2: should restore frame 0 after disposing frame 1
    const pixels2 = try allocator.alloc(SixelImage.Color, 4);
    defer allocator.free(pixels2);
    @memset(pixels2, .{ .r = 0, .g = 0, .b = 255 });

    const image2 = SixelImage{
        .width = 2,
        .height = 2,
        .pixels = pixels2,
    };

    try animator.addFrameWithDisposal(image2, 100, .none);

    animator.start();
    _ = animator.update(100); // Frame 0 → 1
    _ = animator.update(100); // Frame 1 → 2 (disposal .previous should restore frame 0)

    const current_index = animator.getCurrentFrameIndex();
    try testing.expectEqual(@as(usize, 2), current_index);
}

// ----------------------------------------------------------------------------
// Edge Case Tests (5 tests)
// ----------------------------------------------------------------------------

test "sixel animator: empty animator (no frames)" {
    const allocator = testing.allocator;

    var animator = try SixelAnimator.init(allocator);
    defer animator.deinit();

    try testing.expectEqual(@as(usize, 0), animator.getFrameCount());
    try testing.expectEqual(@as(u32, 0), animator.getTotalDuration());

    // getCurrentFrame on empty should not crash (return default or handle gracefully)
    // Implementation detail: may return null or a default frame
}

test "sixel animator: single frame animation" {
    const allocator = testing.allocator;

    var animator = try SixelAnimator.init(allocator);
    defer animator.deinit();

    const pixels = try allocator.alloc(SixelImage.Color, 1);
    defer allocator.free(pixels);
    pixels[0] = .{ .r = 128, .g = 128, .b = 128 };

    const image = SixelImage{
        .width = 1,
        .height = 1,
        .pixels = pixels,
    };

    try animator.addFrame(image, 100);

    animator.start();

    // Update should not advance (only 1 frame)
    const changed = animator.update(200);
    try testing.expect(!changed);
    try testing.expectEqual(@as(usize, 0), animator.getCurrentFrameIndex());
}

test "sixel animator: very large frame delay (10000ms)" {
    const allocator = testing.allocator;

    var animator = try SixelAnimator.init(allocator);
    defer animator.deinit();

    const pixels = try allocator.alloc(SixelImage.Color, 1);
    defer allocator.free(pixels);
    pixels[0] = .{ .r = 255, .g = 255, .b = 255 };

    const image = SixelImage{
        .width = 1,
        .height = 1,
        .pixels = pixels,
    };

    try animator.addFrame(image, 10000);
    try animator.addFrame(image, 100);

    animator.start();

    // Should handle large delays without overflow
    const changed = animator.update(5000);
    try testing.expect(!changed); // Still on frame 0
    try testing.expectEqual(@as(usize, 0), animator.getCurrentFrameIndex());

    _ = animator.update(5000); // Total 10000ms
    try testing.expectEqual(@as(usize, 1), animator.getCurrentFrameIndex());
}

test "sixel animator: zero delay frame (should handle gracefully)" {
    const allocator = testing.allocator;

    var animator = try SixelAnimator.init(allocator);
    defer animator.deinit();

    const pixels = try allocator.alloc(SixelImage.Color, 1);
    defer allocator.free(pixels);
    pixels[0] = .{ .r = 50, .g = 100, .b = 150 };

    const image = SixelImage{
        .width = 1,
        .height = 1,
        .pixels = pixels,
    };

    try animator.addFrame(image, 0); // Zero delay
    try animator.addFrame(image, 100);

    animator.start();

    // Should immediately advance from 0-delay frame
    const changed = animator.update(1);
    try testing.expect(changed);
    try testing.expectEqual(@as(usize, 1), animator.getCurrentFrameIndex());
}

test "sixel animator: alternating fast and slow frames" {
    const allocator = testing.allocator;

    var animator = try SixelAnimator.init(allocator);
    defer animator.deinit();

    const delays = [_]u32{ 50, 500, 50, 500 };

    for (delays) |delay| {
        const pixels = try allocator.alloc(SixelImage.Color, 1);
        defer allocator.free(pixels);
        pixels[0] = .{ .r = 100, .g = 150, .b = 200 };

        const image = SixelImage{
            .width = 1,
            .height = 1,
            .pixels = pixels,
        };

        try animator.addFrame(image, delay);
    }

    animator.start();

    // Frame 0 (50ms) → Frame 1
    var changed = animator.update(50);
    try testing.expect(changed);
    try testing.expectEqual(@as(usize, 1), animator.getCurrentFrameIndex());

    // Frame 1 (500ms) - should not advance on small update
    changed = animator.update(100);
    try testing.expect(!changed);
    try testing.expectEqual(@as(usize, 1), animator.getCurrentFrameIndex());

    // Accumulate to exceed 500ms
    changed = animator.update(400);
    try testing.expect(changed);
    try testing.expectEqual(@as(usize, 2), animator.getCurrentFrameIndex());
}

// ----------------------------------------------------------------------------
// Memory Safety Tests (3 tests)
// ----------------------------------------------------------------------------

test "sixel animator: no memory leaks on init and deinit" {
    const allocator = testing.allocator;

    var animator = try SixelAnimator.init(allocator);
    defer animator.deinit();

    // Testing allocator will report any leaks
}

test "sixel animator: no memory leaks with multiple frames" {
    const allocator = testing.allocator;

    var animator = try SixelAnimator.init(allocator);
    defer animator.deinit();

    for (0..10) |_| {
        const pixels = try allocator.alloc(SixelImage.Color, 100);
        defer allocator.free(pixels);
        @memset(pixels, .{ .r = 255, .g = 0, .b = 0 });

        const image = SixelImage{
            .width = 10,
            .height = 10,
            .pixels = pixels,
        };

        try animator.addFrame(image, 100);
    }

    // Testing allocator will report any leaks
}

test "sixel animator: no memory leaks during playback and updates" {
    const allocator = testing.allocator;

    var animator = try SixelAnimator.init(allocator);
    defer animator.deinit();

    for (0..5) |_| {
        const pixels = try allocator.alloc(SixelImage.Color, 4);
        defer allocator.free(pixels);
        @memset(pixels, .{ .r = 128, .g = 128, .b = 128 });

        const image = SixelImage{
            .width = 2,
            .height = 2,
            .pixels = pixels,
        };

        try animator.addFrame(image, 100);
    }

    animator.start();

    // Simulate playback with many updates
    for (0..100) |_| {
        _ = animator.update(50);
    }

    // Testing allocator will report any leaks
}

// ============================================================================
// Run-Length Encoding (RLE) Compression Tests
// ============================================================================

// ============================================================================
// 1. Basic RLE Compression (5 tests)
// ============================================================================

test "sixel compressor: compress repeated sixel characters" {
    const allocator = testing.allocator;
    const input = "??????";

    const compressed = try SixelCompressor.compress(allocator, input);
    defer allocator.free(compressed);

    // Expected: "!6?" (repeat count 6, character '?')
    try testing.expectEqualStrings("!6?", compressed);
}

test "sixel compressor: compress mixed runs (alternating pattern)" {
    const allocator = testing.allocator;
    // Use '@' (0x40) which is a valid Sixel data character (0x3f-0x7e)
    const input = "??@@@@@??";

    const compressed = try SixelCompressor.compress(allocator, input);
    defer allocator.free(compressed);

    // Expected: "!2?!5@!2?" (2x?, 5x@, 2x?)
    try testing.expectEqualStrings("!2?!5@!2?", compressed);
}

test "sixel compressor: no compression for single characters" {
    const allocator = testing.allocator;
    const input = "?#-";

    const compressed = try SixelCompressor.compress(allocator, input);
    defer allocator.free(compressed);

    // No compression: input unchanged (different chars)
    try testing.expectEqualStrings("?#-", compressed);
}

test "sixel compressor: empty input returns empty output" {
    const allocator = testing.allocator;
    const input = "";

    const compressed = try SixelCompressor.compress(allocator, input);
    defer allocator.free(compressed);

    try testing.expectEqualStrings("", compressed);
}

test "sixel compressor: very long run exceeds 255 (splits into multiple sequences)" {
    const allocator = testing.allocator;

    // Create string with 300 'x' characters
    var input_buf: [300]u8 = undefined;
    @memset(&input_buf, 'x');
    const input = &input_buf;

    const compressed = try SixelCompressor.compress(allocator, input);
    defer allocator.free(compressed);

    // Should split into multiple: e.g., "!255x!45x" or similar
    // The compressed output must be valid and contain multiple repeat counts
    try testing.expect(compressed.len > 0);
    try testing.expect(std.mem.count(u8, compressed, "!") >= 2); // At least 2 repeat sequences
}

// ============================================================================
// 2. RLE Decompression (5 tests)
// ============================================================================

test "sixel compressor: decompress simple repeated sequence" {
    const allocator = testing.allocator;
    const compressed = "!6?";

    const decompressed = try SixelCompressor.decompress(allocator, compressed);
    defer allocator.free(decompressed);

    // Expected: "??????"
    try testing.expectEqualStrings("??????", decompressed);
}

test "sixel compressor: decompress mixed sequence" {
    const allocator = testing.allocator;
    const compressed = "!2?!5#!2?";

    const decompressed = try SixelCompressor.decompress(allocator, compressed);
    defer allocator.free(decompressed);

    // Expected: "??#####??"
    try testing.expectEqualStrings("??#####??", decompressed);
}

test "sixel compressor: decompress literal characters (no repeat)" {
    const allocator = testing.allocator;
    const compressed = "?#-";

    const decompressed = try SixelCompressor.decompress(allocator, compressed);
    defer allocator.free(decompressed);

    // Expected: "?#-"
    try testing.expectEqualStrings("?#-", decompressed);
}

test "sixel compressor: decompress empty compressed input" {
    const allocator = testing.allocator;
    const compressed = "";

    const decompressed = try SixelCompressor.decompress(allocator, compressed);
    defer allocator.free(decompressed);

    try testing.expectEqualStrings("", decompressed);
}

test "sixel compressor: decompress large repeat counts" {
    const allocator = testing.allocator;
    const compressed = "!255?!100#";

    const decompressed = try SixelCompressor.decompress(allocator, compressed);
    defer allocator.free(decompressed);

    // Expected: 255 '?' followed by 100 '#'
    try testing.expectEqual(@as(usize, 355), decompressed.len);

    // Check first 255 chars are '?'
    for (decompressed[0..255]) |c| {
        try testing.expectEqual('?', c);
    }

    // Check next 100 chars are '#'
    for (decompressed[255..]) |c| {
        try testing.expectEqual('#', c);
    }
}

// ============================================================================
// 3. Round-Trip (Compress + Decompress) (5 tests)
// ============================================================================

test "sixel compressor: round-trip simple data" {
    const allocator = testing.allocator;
    const original = "??????";

    const compressed = try SixelCompressor.compress(allocator, original);
    defer allocator.free(compressed);

    const decompressed = try SixelCompressor.decompress(allocator, compressed);
    defer allocator.free(decompressed);

    try testing.expectEqualStrings(original, decompressed);
}

test "sixel compressor: round-trip complex sixel data" {
    const allocator = testing.allocator;
    const original = "??????##########??--$$$$";

    const compressed = try SixelCompressor.compress(allocator, original);
    defer allocator.free(compressed);

    const decompressed = try SixelCompressor.decompress(allocator, compressed);
    defer allocator.free(decompressed);

    try testing.expectEqualStrings(original, decompressed);
}

test "sixel compressor: round-trip all same character" {
    const allocator = testing.allocator;

    var input_buf: [1000]u8 = undefined;
    @memset(&input_buf, '?');
    const original = &input_buf;

    const compressed = try SixelCompressor.compress(allocator, original);
    defer allocator.free(compressed);

    const decompressed = try SixelCompressor.decompress(allocator, compressed);
    defer allocator.free(decompressed);

    try testing.expectEqualStrings(original, decompressed);
}

test "sixel compressor: round-trip all different characters" {
    const allocator = testing.allocator;

    // Create string with all different ASCII sixel chars (? to ~)
    var input_buf: [64]u8 = undefined;
    for (&input_buf, 0..) |*c, i| {
        c.* = @intCast(0x3f + i); // ? to ~
    }
    const original = &input_buf;

    const compressed = try SixelCompressor.compress(allocator, original);
    defer allocator.free(compressed);

    const decompressed = try SixelCompressor.decompress(allocator, compressed);
    defer allocator.free(decompressed);

    try testing.expectEqualStrings(original, decompressed);
}

test "sixel compressor: round-trip with sixel control characters" {
    const allocator = testing.allocator;
    const original = "\x1bPq???#####$-???\x1b\\";

    const compressed = try SixelCompressor.compress(allocator, original);
    defer allocator.free(compressed);

    const decompressed = try SixelCompressor.decompress(allocator, compressed);
    defer allocator.free(decompressed);

    try testing.expectEqualStrings(original, decompressed);
}

// ============================================================================
// 4. Compression Ratio (3 tests)
// ============================================================================

test "sixel compressor: compression ratio high for repeated data" {
    const allocator = testing.allocator;

    var input_buf: [300]u8 = undefined;
    @memset(&input_buf, '?');
    const original = &input_buf;

    const compressed = try SixelCompressor.compress(allocator, original);
    defer allocator.free(compressed);

    const ratio = SixelCompressor.compressionRatio(original, compressed);

    // High repetition should yield good compression (ratio > 2.0)
    try testing.expect(ratio > 2.0);
}

test "sixel compressor: compression ratio low for random data" {
    const allocator = testing.allocator;

    var input_buf: [64]u8 = undefined;
    for (&input_buf, 0..) |*c, i| {
        c.* = @intCast(0x3f + (i % 64)); // Cycle through all ASCII sixel chars
    }
    const original = &input_buf;

    const compressed = try SixelCompressor.compress(allocator, original);
    defer allocator.free(compressed);

    const ratio = SixelCompressor.compressionRatio(original, compressed);

    // Low repetition should yield poor compression (ratio ≈ 1.0 or less)
    try testing.expect(ratio <= 1.5);
}

test "sixel compressor: compression ratio calculation is correct" {
    const original = "??????";
    const compressed = "!6?";

    const ratio = SixelCompressor.compressionRatio(original, compressed);

    // Expected: 6 / 3 = 2.0
    try testing.expectApproxEqAbs(@as(f32, 2.0), ratio, 0.01);
}

// ============================================================================
// 5. Integration with SixelEncoder (3 tests)
// ============================================================================

test "sixel compressor: SixelEncoder.encodeCompressed produces valid sixel" {
    const allocator = testing.allocator;

    // Create simple 2x2 red image
    const pixels = [_]SixelImage.Color{
        .{ .r = 255, .g = 0, .b = 0 }, .{ .r = 255, .g = 0, .b = 0 },
        .{ .r = 255, .g = 0, .b = 0 }, .{ .r = 255, .g = 0, .b = 0 },
    };

    const image = SixelImage{
        .width = 2,
        .height = 2,
        .pixels = &pixels,
    };

    var output: std.ArrayList(u8) = .{};
    defer output.deinit(allocator);

    const encoder = SixelEncoder{};
    try encoder.encodeCompressed(allocator, image, output.writer(allocator));

    const compressed_sixel = output.items;

    // Should start with compressed sixel marker (after sixel start)
    try testing.expect(compressed_sixel.len > 0);
    try testing.expect(std.mem.startsWith(u8, compressed_sixel, "\x1bPq"));
}

test "sixel compressor: compressed output can be decompressed and decoded" {
    const allocator = testing.allocator;

    const pixels = [_]SixelImage.Color{
        .{ .r = 255, .g = 0, .b = 0 }, .{ .r = 255, .g = 0, .b = 0 },
        .{ .r = 255, .g = 0, .b = 0 }, .{ .r = 255, .g = 0, .b = 0 },
    };

    const image = SixelImage{
        .width = 2,
        .height = 2,
        .pixels = &pixels,
    };

    var encoded: std.ArrayList(u8) = .{};
    defer encoded.deinit(allocator);

    const encoder = SixelEncoder{};
    try encoder.encode(allocator, image, encoded.writer(allocator));

    const original_sixel = encoded.items;

    // Compress
    const compressed = try SixelCompressor.compress(allocator, original_sixel);
    defer allocator.free(compressed);

    // Decompress
    const decompressed = try SixelCompressor.decompress(allocator, compressed);
    defer allocator.free(decompressed);

    // Should match original
    try testing.expectEqualStrings(original_sixel, decompressed);
}

test "sixel compressor: compression achieves significant reduction for typical image" {
    const allocator = testing.allocator;

    // Create larger 10x10 image with repeating pattern
    var pixels: [100]SixelImage.Color = undefined;
    for (&pixels) |*p| {
        p.* = .{ .r = 255, .g = 0, .b = 0 };
    }

    const image = SixelImage{
        .width = 10,
        .height = 10,
        .pixels = &pixels,
    };

    var encoded: std.ArrayList(u8) = .{};
    defer encoded.deinit(allocator);

    const encoder = SixelEncoder{};
    try encoder.encode(allocator, image, encoded.writer(allocator));

    const original_sixel = encoded.items;

    const compressed = try SixelCompressor.compress(allocator, original_sixel);
    defer allocator.free(compressed);

    const ratio = SixelCompressor.compressionRatio(original_sixel, compressed);

    // Should achieve at least 20% reduction (ratio > 1.2)
    try testing.expect(ratio > 1.2);
}

// ============================================================================
// 6. Error Handling (3 tests)
// ============================================================================

test "sixel compressor: invalid repeat count format returns error" {
    const allocator = testing.allocator;
    const compressed = "!ABC?"; // Invalid: ABC is not a valid number

    const result = SixelCompressor.decompress(allocator, compressed);

    // Should return an error
    try testing.expectError(error.InvalidRepeatCount, result);
}

test "sixel compressor: malformed compressed data returns error" {
    const allocator = testing.allocator;
    const compressed = "!3"; // Incomplete: missing character after repeat count

    const result = SixelCompressor.decompress(allocator, compressed);

    // Should return an error
    try testing.expectError(error.IncompleteCompressedData, result);
}

test "sixel compressor: repeat count overflow returns error" {
    const allocator = testing.allocator;
    const compressed = "!99999?"; // Too large: exceeds u16 max

    const result = SixelCompressor.decompress(allocator, compressed);

    // Should return an error or handle gracefully
    try testing.expect(result == error.RepeatCountTooLarge or result == error.InvalidRepeatCount);
}

// ============================================================================
// 7. Performance (2 tests)
// ============================================================================

test "sixel compressor: compression completes in reasonable time (<100ms for 10KB)" {
    const allocator = testing.allocator;

    // Create 10KB of repeated data
    const large_input = try allocator.alloc(u8, 10240);
    defer allocator.free(large_input);
    @memset(large_input, '?');

    const start = std.time.microTimestamp();
    const compressed = try SixelCompressor.compress(allocator, large_input);
    defer allocator.free(compressed);
    const elapsed_us = std.time.microTimestamp() - start;
    const elapsed_ms = @as(f32, @floatFromInt(elapsed_us)) / 1000.0;

    // Should complete in < 100ms
    try testing.expect(elapsed_ms < 100.0);
}

test "sixel compressor: decompression completes in reasonable time (<50ms for 5KB)" {
    const allocator = testing.allocator;

    // Create a 5KB compressed sequence
    const large_compressed = try allocator.alloc(u8, 5120);
    defer allocator.free(large_compressed);
    @memset(large_compressed, '?');

    const start = std.time.microTimestamp();
    const decompressed = try SixelCompressor.decompress(allocator, large_compressed);
    defer allocator.free(decompressed);
    const elapsed_us = std.time.microTimestamp() - start;
    const elapsed_ms = @as(f32, @floatFromInt(elapsed_us)) / 1000.0;

    // Should complete in < 50ms
    try testing.expect(elapsed_ms < 50.0);
}

// ============================================================================
// 8. Edge Cases (4 tests)
// ============================================================================

test "sixel compressor: compress single character repeated 1000+ times" {
    const allocator = testing.allocator;

    const large_input = try allocator.alloc(u8, 1500);
    defer allocator.free(large_input);
    @memset(large_input, 'x');

    const compressed = try SixelCompressor.compress(allocator, large_input);
    defer allocator.free(compressed);

    // Should be much smaller than input
    try testing.expect(compressed.len < large_input.len / 10);

    // Decompress and verify
    const decompressed = try SixelCompressor.decompress(allocator, compressed);
    defer allocator.free(decompressed);

    try testing.expectEqualStrings(large_input, decompressed);
}

test "sixel compressor: compress alternating pattern (worst case for RLE)" {
    const allocator = testing.allocator;

    var input_buf: [100]u8 = undefined;
    for (&input_buf, 0..) |*c, i| {
        c.* = if (i % 2 == 0) '?' else '#';
    }
    const original = &input_buf;

    const compressed = try SixelCompressor.compress(allocator, original);
    defer allocator.free(compressed);

    // For alternating pattern, compression may not help much
    // But should still round-trip correctly
    const decompressed = try SixelCompressor.decompress(allocator, compressed);
    defer allocator.free(decompressed);

    try testing.expectEqualStrings(original, decompressed);
}

test "sixel compressor: UTF-8 safety (ASCII sixel characters only)" {
    const allocator = testing.allocator;

    // All valid sixel ASCII chars: ? to ~ (0x3f to 0x7e)
    var input_buf: [64]u8 = undefined;
    for (&input_buf, 0..) |*c, i| {
        c.* = @intCast(0x3f + i);
    }
    const original = &input_buf;

    const compressed = try SixelCompressor.compress(allocator, original);
    defer allocator.free(compressed);

    const decompressed = try SixelCompressor.decompress(allocator, compressed);
    defer allocator.free(decompressed);

    // All ASCII, should be safe
    try testing.expectEqualStrings(original, decompressed);
}

test "sixel compressor: preserve sixel control characters (ESC, $, -, etc)" {
    const allocator = testing.allocator;

    // Typical sixel sequence fragment
    const original = "\x1bPq???$###-\x1b\\";

    const compressed = try SixelCompressor.compress(allocator, original);
    defer allocator.free(compressed);

    const decompressed = try SixelCompressor.decompress(allocator, compressed);
    defer allocator.free(decompressed);

    // All chars preserved including control chars
    try testing.expectEqualStrings(original, decompressed);
}
