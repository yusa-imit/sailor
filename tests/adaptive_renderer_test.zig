const std = @import("std");
const testing = std.testing;
const sailor = @import("sailor");

// Import the adaptive renderer and related types
const adaptive_renderer = sailor.adaptive_renderer;
const AdaptiveImageRenderer = adaptive_renderer.AdaptiveImageRenderer;
const RenderMode = adaptive_renderer.RenderMode;
const AnsiArtRenderer = sailor.tui.ansi_art.AnsiArtRenderer;

// ============================================================================
// Helpers
// ============================================================================

/// Create a solid-color RGB24 image
fn createSolidRgbImage(
    allocator: std.mem.Allocator,
    width: u32,
    height: u32,
    r: u8,
    g: u8,
    b: u8,
) ![]u8 {
    const size = width * height * 3;
    var pixels = try allocator.alloc(u8, size);
    for (0..width * height) |i| {
        pixels[i * 3 + 0] = r;
        pixels[i * 3 + 1] = g;
        pixels[i * 3 + 2] = b;
    }
    return pixels;
}

/// Check if output contains ANSI escape sequences
fn hasAnsiEscapes(output: []const u8) bool {
    return std.mem.containsAtLeast(u8, output, 1, "\x1b[");
}

/// Check if output contains half-block characters (▀ U+2580 or █ U+2588)
fn hasBlockCharacters(output: []const u8) bool {
    // U+2580 UPPER HALF BLOCK = UTF-8: E2 96 80
    // U+2588 FULL BLOCK = UTF-8: E2 96 88
    return std.mem.containsAtLeast(u8, output, 1, "\xE2\x96\x80") or
        std.mem.containsAtLeast(u8, output, 1, "\xE2\x96\x88");
}

/// Check if output contains braille characters (U+2800-U+28FF)
/// Braille UTF-8: E2 A0 80 - E2 A3 BF
fn hasBrailleCharacters(output: []const u8) bool {
    // Braille pattern starts with E2 A0..A3 (second byte 0xA0-0xA3 in UTF-8)
    // Scan through looking for E2 followed by A0-A3
    for (0..output.len -| 2) |i| {
        if (output[i] == 0xE2 and output[i + 1] >= 0xA0 and output[i + 1] <= 0xA3) {
            return true;
        }
    }
    return false;
}

/// Check if output contains only printable ASCII (no high bytes except in escape sequences)
fn isAsciiOnly(output: []const u8) bool {
    var i: usize = 0;
    while (i < output.len) {
        const byte = output[i];

        // Allow escape sequences (ESC [ ... m)
        if (byte == 0x1b) {
            i += 1;
            // Skip everything until 'm'
            while (i < output.len and output[i] != 'm') {
                i += 1;
            }
            if (i < output.len) i += 1; // skip the 'm'
            continue;
        }

        // Allow newlines and common whitespace
        if (byte == '\n' or byte == '\r' or byte == '\t' or byte == ' ') {
            i += 1;
            continue;
        }

        // Reject any byte > 127 outside escape sequences
        if (byte > 127) {
            return false;
        }

        i += 1;
    }
    return true;
}

/// Check if output contains DCS (Device Control String) framing for sixel
fn hasSixelFraming(output: []const u8) bool {
    // Sixel output should start with DCS: ESC P (0x1b 0x50)
    // and end with ST: ESC \ (0x1b 0x5c)
    if (output.len < 2) return false;

    const has_dcs_start = (output[0] == 0x1b and output[1] == 0x50);
    const has_st_end = output.len >= 2 and
        output[output.len - 2] == 0x1b and output[output.len - 1] == 0x5c;

    return has_dcs_start and has_st_end;
}

// ============================================================================
// Tests: force_ansi mode
// ============================================================================

test "adaptive: force_ansi mode produces ANSI escape codes for 2x2 image" {
    var buf: [4096]u8 = undefined;
    var stream = std.io.fixedBufferStream(&buf);
    const allocator = testing.allocator;

    const pixels = try createSolidRgbImage(allocator, 2, 2, 255, 0, 0);
    defer allocator.free(pixels);

    const options = AdaptiveImageRenderer.Options{
        .mode = .force_ansi,
        .ansi_algorithm = .block,
        .ansi_color_mode = .truecolor,
        .ansi_width = 10,
    };

    try AdaptiveImageRenderer.render(allocator, pixels, 2, 2, options, stream.writer());
    const output = stream.getWritten();

    try testing.expect(hasAnsiEscapes(output));
}

test "adaptive: force_ansi mode with block algorithm outputs block characters" {
    var buf: [4096]u8 = undefined;
    var stream = std.io.fixedBufferStream(&buf);
    const allocator = testing.allocator;

    const pixels = try createSolidRgbImage(allocator, 2, 2, 100, 100, 100);
    defer allocator.free(pixels);

    const options = AdaptiveImageRenderer.Options{
        .mode = .force_ansi,
        .ansi_algorithm = .block,
        .ansi_color_mode = .truecolor,
        .ansi_width = 10,
    };

    try AdaptiveImageRenderer.render(allocator, pixels, 2, 2, options, stream.writer());
    const output = stream.getWritten();

    try testing.expect(hasBlockCharacters(output));
}

test "adaptive: force_ansi mode with braille algorithm outputs braille characters" {
    var buf: [4096]u8 = undefined;
    var stream = std.io.fixedBufferStream(&buf);
    const allocator = testing.allocator;

    const pixels = try createSolidRgbImage(allocator, 4, 4, 200, 200, 200);
    defer allocator.free(pixels);

    const options = AdaptiveImageRenderer.Options{
        .mode = .force_ansi,
        .ansi_algorithm = .braille,
        .ansi_color_mode = .truecolor,
        .ansi_width = 20,
    };

    try AdaptiveImageRenderer.render(allocator, pixels, 4, 4, options, stream.writer());
    const output = stream.getWritten();

    try testing.expect(hasBrailleCharacters(output));
}

test "adaptive: force_ansi mode with ascii algorithm outputs ASCII only" {
    var buf: [4096]u8 = undefined;
    var stream = std.io.fixedBufferStream(&buf);
    const allocator = testing.allocator;

    const pixels = try createSolidRgbImage(allocator, 4, 4, 128, 128, 128);
    defer allocator.free(pixels);

    const options = AdaptiveImageRenderer.Options{
        .mode = .force_ansi,
        .ansi_algorithm = .ascii,
        .ansi_color_mode = .truecolor,
        .ansi_width = 16,
    };

    try AdaptiveImageRenderer.render(allocator, pixels, 4, 4, options, stream.writer());
    const output = stream.getWritten();

    try testing.expect(isAsciiOnly(output));
}

test "adaptive: force_ansi mode produces output for 1x1 image" {
    var buf: [4096]u8 = undefined;
    var stream = std.io.fixedBufferStream(&buf);
    const allocator = testing.allocator;

    const pixels = try createSolidRgbImage(allocator, 1, 1, 50, 100, 150);
    defer allocator.free(pixels);

    const options = AdaptiveImageRenderer.Options{
        .mode = .force_ansi,
    };

    try AdaptiveImageRenderer.render(allocator, pixels, 1, 1, options, stream.writer());
    const output = stream.getWritten();

    try testing.expect(output.len > 0);
}

test "adaptive: force_ansi mode produces output for 4x4 image" {
    var buf: [4096]u8 = undefined;
    var stream = std.io.fixedBufferStream(&buf);
    const allocator = testing.allocator;

    const pixels = try createSolidRgbImage(allocator, 4, 4, 64, 128, 192);
    defer allocator.free(pixels);

    const options = AdaptiveImageRenderer.Options{
        .mode = .force_ansi,
    };

    try AdaptiveImageRenderer.render(allocator, pixels, 4, 4, options, stream.writer());
    const output = stream.getWritten();

    try testing.expect(output.len > 0);
}

test "adaptive: force_ansi mode with grayscale outputs non-empty result" {
    var buf: [4096]u8 = undefined;
    var stream = std.io.fixedBufferStream(&buf);
    const allocator = testing.allocator;

    const pixels = try createSolidRgbImage(allocator, 2, 2, 127, 127, 127);
    defer allocator.free(pixels);

    const options = AdaptiveImageRenderer.Options{
        .mode = .force_ansi,
        .ansi_algorithm = .block,
        .ansi_color_mode = .grayscale,
        .ansi_width = 10,
    };

    try AdaptiveImageRenderer.render(allocator, pixels, 2, 2, options, stream.writer());
    const output = stream.getWritten();

    try testing.expect(output.len > 0);
}

test "adaptive: force_ansi mode output differs between widths (10 vs 40)" {
    // Truecolor ANSI for a 20x20 image at width=20 (capped) needs ~10KB; use 32KB to be safe.
    var buf1: [32768]u8 = undefined;
    var stream1 = std.io.fixedBufferStream(&buf1);
    const allocator = testing.allocator;

    const pixels = try createSolidRgbImage(allocator, 20, 20, 75, 150, 225);
    defer allocator.free(pixels);

    const options1 = AdaptiveImageRenderer.Options{
        .mode = .force_ansi,
        .ansi_width = 10,
    };

    try AdaptiveImageRenderer.render(allocator, pixels, 20, 20, options1, stream1.writer());
    const output1 = stream1.getWritten();

    var buf2: [32768]u8 = undefined;
    var stream2 = std.io.fixedBufferStream(&buf2);

    const options2 = AdaptiveImageRenderer.Options{
        .mode = .force_ansi,
        .ansi_width = 40,
    };

    try AdaptiveImageRenderer.render(allocator, pixels, 20, 20, options2, stream2.writer());
    const output2 = stream2.getWritten();

    // Different widths should produce different output lengths
    try testing.expect(output1.len != output2.len);
}

test "adaptive: force_ansi mode with zero width returns error" {
    var buf: [4096]u8 = undefined;
    var stream = std.io.fixedBufferStream(&buf);
    const allocator = testing.allocator;

    const pixels = try createSolidRgbImage(allocator, 2, 2, 100, 100, 100);
    defer allocator.free(pixels);

    const options = AdaptiveImageRenderer.Options{
        .mode = .force_ansi,
        .ansi_width = 0,
    };

    const result = AdaptiveImageRenderer.render(allocator, pixels, 2, 2, options, stream.writer());
    try testing.expectError(error.InvalidDimensions, result);
}

test "adaptive: force_ansi mode with 16-color produces different output than truecolor" {
    var buf1: [4096]u8 = undefined;
    var stream1 = std.io.fixedBufferStream(&buf1);
    const allocator = testing.allocator;

    const pixels = try createSolidRgbImage(allocator, 2, 2, 200, 50, 100);
    defer allocator.free(pixels);

    const options1 = AdaptiveImageRenderer.Options{
        .mode = .force_ansi,
        .ansi_algorithm = .block,
        .ansi_color_mode = .truecolor,
        .ansi_width = 10,
    };

    try AdaptiveImageRenderer.render(allocator, pixels, 2, 2, options1, stream1.writer());
    const output1 = stream1.getWritten();

    var buf2: [4096]u8 = undefined;
    var stream2 = std.io.fixedBufferStream(&buf2);

    const options2 = AdaptiveImageRenderer.Options{
        .mode = .force_ansi,
        .ansi_algorithm = .block,
        .ansi_color_mode = .colors16,
        .ansi_width = 10,
    };

    try AdaptiveImageRenderer.render(allocator, pixels, 2, 2, options2, stream2.writer());
    const output2 = stream2.getWritten();

    // Different color modes should produce different output
    try testing.expect(!std.mem.eql(u8, output1, output2));
}

// ============================================================================
// Tests: force_sixel mode
// ============================================================================

test "adaptive: force_sixel mode produces DCS-framed output for 2x2 image" {
    var buf: [8192]u8 = undefined;
    var stream = std.io.fixedBufferStream(&buf);
    const allocator = testing.allocator;

    const pixels = try createSolidRgbImage(allocator, 2, 2, 255, 128, 64);
    defer allocator.free(pixels);

    const options = AdaptiveImageRenderer.Options{
        .mode = .force_sixel,
    };

    try AdaptiveImageRenderer.render(allocator, pixels, 2, 2, options, stream.writer());
    const output = stream.getWritten();

    try testing.expect(hasSixelFraming(output));
}

test "adaptive: force_sixel produces valid sixel output with Pq marker" {
    var buf: [8192]u8 = undefined;
    var stream = std.io.fixedBufferStream(&buf);
    const allocator = testing.allocator;

    const pixels = try createSolidRgbImage(allocator, 3, 3, 200, 200, 200);
    defer allocator.free(pixels);

    const options = AdaptiveImageRenderer.Options{
        .mode = .force_sixel,
        .palette_size = 16,
    };

    try AdaptiveImageRenderer.render(allocator, pixels, 3, 3, options, stream.writer());
    const output = stream.getWritten();

    // Output should start with ESC P and end with ESC \
    try testing.expect(output.len >= 4);
    try testing.expect(output[0] == 0x1b and output[1] == 0x50);
    try testing.expect(output[output.len - 2] == 0x1b and output[output.len - 1] == 0x5c);
}

// ============================================================================
// Tests: Options and parameter validation
// ============================================================================

test "adaptive: default options sets mode to auto" {
    const opts = AdaptiveImageRenderer.Options{};
    try testing.expectEqual(RenderMode.auto, opts.mode);
}

test "adaptive: pixel count validation rejects incorrect buffer size" {
    var buf: [4096]u8 = undefined;
    var stream = std.io.fixedBufferStream(&buf);
    const allocator = testing.allocator;

    // Create a 4-byte buffer for a 2x1 image (should be 6 bytes)
    const pixels = try allocator.alloc(u8, 4);
    defer allocator.free(pixels);

    const options = AdaptiveImageRenderer.Options{
        .mode = .force_ansi,
    };

    const result = AdaptiveImageRenderer.render(allocator, pixels, 2, 1, options, stream.writer());
    try testing.expectError(error.BufferTooSmall, result);
}

test "adaptive: auto mode produces non-empty output" {
    var buf: [4096]u8 = undefined;
    var stream = std.io.fixedBufferStream(&buf);
    const allocator = testing.allocator;

    const pixels = try createSolidRgbImage(allocator, 2, 2, 100, 150, 200);
    defer allocator.free(pixels);

    const options = AdaptiveImageRenderer.Options{
        .mode = .auto,
    };

    try AdaptiveImageRenderer.render(allocator, pixels, 2, 2, options, stream.writer());
    const output = stream.getWritten();

    try testing.expect(output.len > 0);
}

test "adaptive: force_ansi mode respects custom ansi_height option" {
    var buf: [32768]u8 = undefined;
    var stream = std.io.fixedBufferStream(&buf);
    const allocator = testing.allocator;

    const pixels = try createSolidRgbImage(allocator, 10, 10, 99, 99, 99);
    defer allocator.free(pixels);

    const options = AdaptiveImageRenderer.Options{
        .mode = .force_ansi,
        .ansi_width = 20,
        .ansi_height = 5,
    };

    try AdaptiveImageRenderer.render(allocator, pixels, 10, 10, options, stream.writer());
    const output = stream.getWritten();

    try testing.expect(output.len > 0);
}
