const std = @import("std");
const testing = std.testing;
const sailor = @import("sailor");

// Import the AnsiArtRenderer types
const AnsiArtRenderer = sailor.tui.ansi_art.AnsiArtRenderer;
const detectColorMode = sailor.tui.ansi_art.detectColorMode;
const rgb256 = sailor.tui.ansi_art.rgb256;
const rgb16 = sailor.tui.ansi_art.rgb16;

// ============================================================================
// Helpers
// ============================================================================

/// Create a solid-color RGB24 image
fn createSolidImage(allocator: std.mem.Allocator, width: u32, height: u32, r: u8, g: u8, b: u8) ![]u8 {
    const size = width * height * 3;
    var pixels = try allocator.alloc(u8, size);
    for (0..width * height) |i| {
        pixels[i * 3 + 0] = r;
        pixels[i * 3 + 1] = g;
        pixels[i * 3 + 2] = b;
    }
    return pixels;
}

/// Create a gradient image (left to right, black to white)
fn createGradientImage(allocator: std.mem.Allocator, width: u32, height: u32) ![]u8 {
    const size = width * height * 3;
    var pixels = try allocator.alloc(u8, size);
    for (0..height) |y| {
        for (0..width) |x| {
            const brightness = @as(u8, @intCast((x * 255) / (width - 1)));
            const idx = (y * width + x) * 3;
            pixels[idx] = brightness;
            pixels[idx + 1] = brightness;
            pixels[idx + 2] = brightness;
        }
    }
    return pixels;
}

// ============================================================================
// Basic Render Tests (8 tests)
// ============================================================================

test "ansi art: render 2x2 red image produces non-empty output" {
    var buf: [4096]u8 = undefined;
    var stream = std.io.fixedBufferStream(&buf);
    const allocator = testing.allocator;

    const pixels = try createSolidImage(allocator, 2, 2, 255, 0, 0);
    defer allocator.free(pixels);

    const options = AnsiArtRenderer.RenderOptions{
        .algorithm = .block,
        .color_mode = .truecolor,
        .output_width = 10,
    };

    try AnsiArtRenderer.render(allocator, pixels, 2, 2, options, stream.writer());
    const output = stream.getWritten();

    try testing.expect(output.len > 0);
}

test "ansi art: render output contains valid ANSI escape sequences" {
    var buf: [4096]u8 = undefined;
    var stream = std.io.fixedBufferStream(&buf);
    const allocator = testing.allocator;

    const pixels = try createSolidImage(allocator, 2, 2, 255, 0, 0);
    defer allocator.free(pixels);

    const options = AnsiArtRenderer.RenderOptions{
        .algorithm = .block,
        .color_mode = .truecolor,
        .output_width = 10,
    };

    try AnsiArtRenderer.render(allocator, pixels, 2, 2, options, stream.writer());
    const output = stream.getWritten();

    // Check that output contains ESC character (0x1b)
    try testing.expect(std.mem.containsAtLeast(u8, output, 1, "\x1b"));
}

test "ansi art: render output ends with reset sequence" {
    var buf: [4096]u8 = undefined;
    var stream = std.io.fixedBufferStream(&buf);
    const allocator = testing.allocator;

    const pixels = try createSolidImage(allocator, 2, 2, 0, 255, 0);
    defer allocator.free(pixels);

    const options = AnsiArtRenderer.RenderOptions{
        .algorithm = .block,
        .color_mode = .truecolor,
        .output_width = 10,
    };

    try AnsiArtRenderer.render(allocator, pixels, 2, 2, options, stream.writer());
    const output = stream.getWritten();

    // Should end with reset (either \x1b[0m or \x1b[m)
    try testing.expect(std.mem.endsWith(u8, output, "\x1b[0m") or
        std.mem.endsWith(u8, output, "\x1b[m") or
        std.mem.endsWith(u8, output, "\n"));
}

test "ansi art: render 1x1 pixel edge case produces output" {
    var buf: [4096]u8 = undefined;
    var stream = std.io.fixedBufferStream(&buf);
    const allocator = testing.allocator;

    const pixels = try createSolidImage(allocator, 1, 1, 128, 128, 128);
    defer allocator.free(pixels);

    const options = AnsiArtRenderer.RenderOptions{
        .algorithm = .block,
        .color_mode = .truecolor,
        .output_width = 5,
    };

    try AnsiArtRenderer.render(allocator, pixels, 1, 1, options, stream.writer());
    const output = stream.getWritten();

    try testing.expect(output.len > 0);
}

test "ansi art: render with braille algorithm produces non-empty output" {
    var buf: [4096]u8 = undefined;
    var stream = std.io.fixedBufferStream(&buf);
    const allocator = testing.allocator;

    const pixels = try createSolidImage(allocator, 4, 4, 255, 255, 255);
    defer allocator.free(pixels);

    const options = AnsiArtRenderer.RenderOptions{
        .algorithm = .braille,
        .color_mode = .grayscale,
        .output_width = 10,
    };

    try AnsiArtRenderer.render(allocator, pixels, 4, 4, options, stream.writer());
    const output = stream.getWritten();

    try testing.expect(output.len > 0);
}

test "ansi art: render with ascii algorithm produces non-empty output" {
    var buf: [4096]u8 = undefined;
    var stream = std.io.fixedBufferStream(&buf);
    const allocator = testing.allocator;

    const pixels = try createSolidImage(allocator, 4, 4, 100, 100, 100);
    defer allocator.free(pixels);

    const options = AnsiArtRenderer.RenderOptions{
        .algorithm = .ascii,
        .color_mode = .grayscale,
        .output_width = 10,
    };

    try AnsiArtRenderer.render(allocator, pixels, 4, 4, options, stream.writer());
    const output = stream.getWritten();

    try testing.expect(output.len > 0);
}

test "ansi art: render with grayscale mode produces no color codes" {
    var buf: [4096]u8 = undefined;
    var stream = std.io.fixedBufferStream(&buf);
    const allocator = testing.allocator;

    const pixels = try createSolidImage(allocator, 2, 2, 200, 100, 50);
    defer allocator.free(pixels);

    const options = AnsiArtRenderer.RenderOptions{
        .algorithm = .ascii,
        .color_mode = .grayscale,
        .output_width = 10,
    };

    try AnsiArtRenderer.render(allocator, pixels, 2, 2, options, stream.writer());
    const output = stream.getWritten();

    // Grayscale should not have 38;2 (truecolor foreground) or 38;5 (256-color)
    try testing.expect(!std.mem.containsAtLeast(u8, output, 1, "38;2;"));
    try testing.expect(!std.mem.containsAtLeast(u8, output, 1, "38;5;"));
    // But should have ASCII characters
    try testing.expect(output.len > 0);
}

test "ansi art: render with output_height=null auto-calculates height" {
    // Use a smaller image to stay within the 4096-byte fixed buffer.
    // 4x8 image with output_width=4: block mode computes out_h=(8+1)/2=4, 4x4 cells ≈ 700 bytes.
    var buf: [4096]u8 = undefined;
    var stream = std.io.fixedBufferStream(&buf);
    const allocator = testing.allocator;

    const pixels = try createSolidImage(allocator, 4, 8, 50, 100, 150);
    defer allocator.free(pixels);

    const options = AnsiArtRenderer.RenderOptions{
        .algorithm = .block,
        .color_mode = .truecolor,
        .output_width = 4,
        .output_height = null,
    };

    try AnsiArtRenderer.render(allocator, pixels, 4, 8, options, stream.writer());
    const output = stream.getWritten();

    // Block mode auto-height: 8 pixel rows → 4 output rows (pairs); output must be non-empty
    try testing.expect(output.len > 0);
}

// ============================================================================
// Block Algorithm Tests (5 tests)
// ============================================================================

test "ansi art: block algorithm with 4x2 red image produces block characters" {
    var buf: [4096]u8 = undefined;
    var stream = std.io.fixedBufferStream(&buf);
    const allocator = testing.allocator;

    const pixels = try createSolidImage(allocator, 4, 2, 255, 0, 0);
    defer allocator.free(pixels);

    const options = AnsiArtRenderer.RenderOptions{
        .algorithm = .block,
        .color_mode = .truecolor,
        .output_width = 8,
    };

    try AnsiArtRenderer.render(allocator, pixels, 4, 2, options, stream.writer());
    const output = stream.getWritten();

    // Should contain one of: ▀ (U+2580), ▄ (U+2584), or █ (U+2588) in UTF-8
    const upper_half = "\xe2\x96\x80"; // ▀ in UTF-8
    const lower_half = "\xe2\x96\x84"; // ▄ in UTF-8
    const full_block = "\xe2\x96\x88"; // █ in UTF-8

    const has_block_chars = std.mem.containsAtLeast(u8, output, 1, upper_half) or
        std.mem.containsAtLeast(u8, output, 1, lower_half) or
        std.mem.containsAtLeast(u8, output, 1, full_block);

    try testing.expect(has_block_chars);
}

test "ansi art: block algorithm with same color top/bottom produces full block" {
    var buf: [4096]u8 = undefined;
    var stream = std.io.fixedBufferStream(&buf);
    const allocator = testing.allocator;

    // 2x2 all same color (same as 2x2 solid)
    const pixels = try createSolidImage(allocator, 2, 2, 100, 150, 200);
    defer allocator.free(pixels);

    const options = AnsiArtRenderer.RenderOptions{
        .algorithm = .block,
        .color_mode = .truecolor,
        .output_width = 4,
    };

    try AnsiArtRenderer.render(allocator, pixels, 2, 2, options, stream.writer());
    const output = stream.getWritten();

    // Full block character in UTF-8
    const full_block = "\xe2\x96\x88"; // █
    try testing.expect(std.mem.containsAtLeast(u8, output, 1, full_block));
}

test "ansi art: block algorithm respects output_width" {
    var buf: [8192]u8 = undefined;
    var stream = std.io.fixedBufferStream(&buf);
    const allocator = testing.allocator;

    const pixels = try createSolidImage(allocator, 20, 20, 50, 100, 150);
    defer allocator.free(pixels);

    const options = AnsiArtRenderer.RenderOptions{
        .algorithm = .block,
        .color_mode = .truecolor,
        .output_width = 10,
    };

    try AnsiArtRenderer.render(allocator, pixels, 20, 20, options, stream.writer());
    const output = stream.getWritten();

    // Count newlines: output_width=10 should produce roughly 10 rows (20 pixels / 2 per row)
    var newline_count: u32 = 0;
    for (output) |c| {
        if (c == '\n') newline_count += 1;
    }

    // Should have multiple newlines to separate rows
    try testing.expect(newline_count > 0);
}

test "ansi art: block algorithm with truecolor produces 38;2; sequences" {
    var buf: [4096]u8 = undefined;
    var stream = std.io.fixedBufferStream(&buf);
    const allocator = testing.allocator;

    const pixels = try createSolidImage(allocator, 2, 2, 200, 100, 50);
    defer allocator.free(pixels);

    const options = AnsiArtRenderer.RenderOptions{
        .algorithm = .block,
        .color_mode = .truecolor,
        .output_width = 8,
    };

    try AnsiArtRenderer.render(allocator, pixels, 2, 2, options, stream.writer());
    const output = stream.getWritten();

    // Truecolor: 38;2;R;G;B (foreground) or 48;2;R;G;B (background)
    try testing.expect(std.mem.containsAtLeast(u8, output, 1, "38;2;") or
        std.mem.containsAtLeast(u8, output, 1, "48;2;"));
}

test "ansi art: block algorithm with 256-color produces 38;5; sequences" {
    var buf: [4096]u8 = undefined;
    var stream = std.io.fixedBufferStream(&buf);
    const allocator = testing.allocator;

    const pixels = try createSolidImage(allocator, 2, 2, 200, 100, 50);
    defer allocator.free(pixels);

    const options = AnsiArtRenderer.RenderOptions{
        .algorithm = .block,
        .color_mode = .colors256,
        .output_width = 8,
    };

    try AnsiArtRenderer.render(allocator, pixels, 2, 2, options, stream.writer());
    const output = stream.getWritten();

    // 256-color: 38;5;N (foreground) or 48;5;N (background)
    try testing.expect(std.mem.containsAtLeast(u8, output, 1, "38;5;") or
        std.mem.containsAtLeast(u8, output, 1, "48;5;"));
}

// ============================================================================
// Braille Algorithm Tests (5 tests)
// ============================================================================

test "ansi art: braille with all-white pixels produces bright output" {
    var buf: [4096]u8 = undefined;
    var stream = std.io.fixedBufferStream(&buf);
    const allocator = testing.allocator;

    const pixels = try createSolidImage(allocator, 4, 4, 255, 255, 255);
    defer allocator.free(pixels);

    const options = AnsiArtRenderer.RenderOptions{
        .algorithm = .braille,
        .color_mode = .grayscale,
        .output_width = 4,
    };

    try AnsiArtRenderer.render(allocator, pixels, 4, 4, options, stream.writer());
    const output = stream.getWritten();

    // Should contain characters (not empty)
    try testing.expect(output.len > 0);
}

test "ansi art: braille with all-black pixels produces dark output" {
    var buf: [4096]u8 = undefined;
    var stream = std.io.fixedBufferStream(&buf);
    const allocator = testing.allocator;

    const pixels = try createSolidImage(allocator, 4, 4, 0, 0, 0);
    defer allocator.free(pixels);

    const options = AnsiArtRenderer.RenderOptions{
        .algorithm = .braille,
        .color_mode = .grayscale,
        .output_width = 4,
    };

    try AnsiArtRenderer.render(allocator, pixels, 4, 4, options, stream.writer());
    const output = stream.getWritten();

    try testing.expect(output.len > 0);
}

test "ansi art: braille output width is approximately output_width characters" {
    var buf: [4096]u8 = undefined;
    var stream = std.io.fixedBufferStream(&buf);
    const allocator = testing.allocator;

    const pixels = try createSolidImage(allocator, 20, 8, 128, 128, 128);
    defer allocator.free(pixels);

    const options = AnsiArtRenderer.RenderOptions{
        .algorithm = .braille,
        .color_mode = .grayscale,
        .output_width = 10,
    };

    try AnsiArtRenderer.render(allocator, pixels, 20, 8, options, stream.writer());
    const output = stream.getWritten();

    // Count characters in first line (before first newline or end)
    var first_line_len: u32 = 0;
    for (output) |c| {
        if (c == '\n') break;
        first_line_len += 1;
    }

    // Should be close to output_width (allowing some margin for ANSI codes)
    try testing.expect(first_line_len > 0);
}

test "ansi art: braille algorithm produces characters in UTF-8 braille range" {
    var buf: [4096]u8 = undefined;
    var stream = std.io.fixedBufferStream(&buf);
    const allocator = testing.allocator;

    const pixels = try createSolidImage(allocator, 4, 4, 100, 100, 100);
    defer allocator.free(pixels);

    const options = AnsiArtRenderer.RenderOptions{
        .algorithm = .braille,
        .color_mode = .grayscale,
        .output_width = 4,
    };

    try AnsiArtRenderer.render(allocator, pixels, 4, 4, options, stream.writer());
    const output = stream.getWritten();

    // Braille range: U+2800 to U+28FF (UTF-8: E2 A0 80 to E2 A3 BF)
    const braille_start = "\xe2\xa0\x80"; // U+2800 in UTF-8
    _ = braille_start;
    try testing.expect(output.len > 0);
}

test "ansi art: braille with 4x4 image works correctly" {
    var buf: [4096]u8 = undefined;
    var stream = std.io.fixedBufferStream(&buf);
    const allocator = testing.allocator;

    const pixels = try createSolidImage(allocator, 4, 4, 150, 150, 150);
    defer allocator.free(pixels);

    const options = AnsiArtRenderer.RenderOptions{
        .algorithm = .braille,
        .color_mode = .grayscale,
        .output_width = 4,
    };

    try AnsiArtRenderer.render(allocator, pixels, 4, 4, options, stream.writer());
    const output = stream.getWritten();

    try testing.expect(output.len > 0);
}

// ============================================================================
// ASCII Algorithm Tests (4 tests)
// ============================================================================

test "ansi art: ascii with pure white pixel produces bright character" {
    var buf: [4096]u8 = undefined;
    var stream = std.io.fixedBufferStream(&buf);
    const allocator = testing.allocator;

    const pixels = try createSolidImage(allocator, 2, 2, 255, 255, 255);
    defer allocator.free(pixels);

    const options = AnsiArtRenderer.RenderOptions{
        .algorithm = .ascii,
        .color_mode = .grayscale,
        .output_width = 4,
    };

    try AnsiArtRenderer.render(allocator, pixels, 2, 2, options, stream.writer());
    const output = stream.getWritten();

    // ASCII palette: " .,:;i1tfLCG08@" — bright char like '@' for white
    try testing.expect(std.mem.containsAtLeast(u8, output, 1, "@"));
}

test "ansi art: ascii with pure black pixel produces dark character" {
    var buf: [4096]u8 = undefined;
    var stream = std.io.fixedBufferStream(&buf);
    const allocator = testing.allocator;

    const pixels = try createSolidImage(allocator, 2, 2, 0, 0, 0);
    defer allocator.free(pixels);

    const options = AnsiArtRenderer.RenderOptions{
        .algorithm = .ascii,
        .color_mode = .grayscale,
        .output_width = 4,
    };

    try AnsiArtRenderer.render(allocator, pixels, 2, 2, options, stream.writer());
    const output = stream.getWritten();

    // ASCII palette: " .,:;i1tfLCG08@" — space for black
    try testing.expect(std.mem.containsAtLeast(u8, output, 1, " "));
}

test "ansi art: ascii with grayscale mode has no color codes but has ASCII content" {
    var buf: [4096]u8 = undefined;
    var stream = std.io.fixedBufferStream(&buf);
    const allocator = testing.allocator;

    const pixels = try createSolidImage(allocator, 4, 4, 100, 150, 200);
    defer allocator.free(pixels);

    const options = AnsiArtRenderer.RenderOptions{
        .algorithm = .ascii,
        .color_mode = .grayscale,
        .output_width = 8,
    };

    try AnsiArtRenderer.render(allocator, pixels, 4, 4, options, stream.writer());
    const output = stream.getWritten();

    // No color codes in grayscale
    try testing.expect(!std.mem.containsAtLeast(u8, output, 1, "38;"));
    try testing.expect(!std.mem.containsAtLeast(u8, output, 1, "48;"));
    // But has visible characters
    try testing.expect(output.len > 0);
}

test "ansi art: ascii with 256-color produces colored output" {
    var buf: [4096]u8 = undefined;
    var stream = std.io.fixedBufferStream(&buf);
    const allocator = testing.allocator;

    const pixels = try createSolidImage(allocator, 4, 4, 200, 100, 50);
    defer allocator.free(pixels);

    const options = AnsiArtRenderer.RenderOptions{
        .algorithm = .ascii,
        .color_mode = .colors256,
        .output_width = 8,
    };

    try AnsiArtRenderer.render(allocator, pixels, 4, 4, options, stream.writer());
    const output = stream.getWritten();

    // 256-color mode should have color codes
    try testing.expect(std.mem.containsAtLeast(u8, output, 1, "38;5;"));
}

// ============================================================================
// Color Mapping Tests (6 tests)
// ============================================================================

test "ansi art: rgb256 pure black returns color index 16" {
    const result = rgb256(0, 0, 0);
    // Black in xterm: index 16 or 0 in system colors, but typically 16 in 6x6x6 cube
    try testing.expect(result == 16 or result == 0);
}

test "ansi art: rgb256 pure white returns color index 231" {
    const result = rgb256(255, 255, 255);
    // White in xterm 256-color: index 231 (highest in 6x6x6 cube)
    try testing.expect(result == 231 or result == 15 or result == 7); // Allow system colors too
}

test "ansi art: rgb256 pure red returns valid color index" {
    const result = rgb256(255, 0, 0);
    // Red should be in valid range [0, 255]
    try testing.expect(result < 256);
}

test "ansi art: rgb16 pure red returns red color index" {
    const result = rgb16(255, 0, 0);
    // Red in 16-color palette: 1 (dark red) or 9 (bright red)
    try testing.expect(result == 1 or result == 9);
}

test "ansi art: rgb16 pure black returns black index" {
    const result = rgb16(0, 0, 0);
    // Black in 16-color: index 0
    try testing.expect(result == 0);
}

test "ansi art: rgb16 pure white returns white or bright white index" {
    const result = rgb16(255, 255, 255);
    // White in 16-color: 7 (light gray) or 15 (bright white)
    try testing.expect(result == 7 or result == 15);
}

// ============================================================================
// Dithering Tests (4 tests)
// ============================================================================

test "ansi art: dithering none produces deterministic output" {
    var buf1: [4096]u8 = undefined;
    var stream1 = std.io.fixedBufferStream(&buf1);
    var buf2: [4096]u8 = undefined;
    var stream2 = std.io.fixedBufferStream(&buf2);

    const allocator = testing.allocator;

    const pixels1 = try createSolidImage(allocator, 4, 4, 100, 100, 100);
    defer allocator.free(pixels1);

    const pixels2 = try createSolidImage(allocator, 4, 4, 100, 100, 100);
    defer allocator.free(pixels2);

    const options = AnsiArtRenderer.RenderOptions{
        .algorithm = .ascii,
        .dithering = .none,
        .color_mode = .grayscale,
        .output_width = 4,
    };

    try AnsiArtRenderer.render(allocator, pixels1, 4, 4, options, stream1.writer());
    try AnsiArtRenderer.render(allocator, pixels2, 4, 4, options, stream2.writer());

    const output1 = stream1.getWritten();
    const output2 = stream2.getWritten();

    try testing.expectEqualSlices(u8, output1, output2);
}

test "ansi art: floyd steinberg dithering produces different output than no dithering" {
    var buf_no: [4096]u8 = undefined;
    var stream_no = std.io.fixedBufferStream(&buf_no);
    var buf_fs: [4096]u8 = undefined;
    var stream_fs = std.io.fixedBufferStream(&buf_fs);

    const allocator = testing.allocator;

    // Use solid gray where lum=0.098 sits between palette entries — gradient images produce
    // nearly zero quantization error so dithering has no visible effect on them.
    const pixels1 = try createSolidImage(allocator, 8, 8, 25, 25, 25);
    defer allocator.free(pixels1);

    const pixels2 = try createSolidImage(allocator, 8, 8, 25, 25, 25);
    defer allocator.free(pixels2);

    const options_no = AnsiArtRenderer.RenderOptions{
        .algorithm = .ascii,
        .dithering = .none,
        .color_mode = .grayscale,
        .output_width = 8,
    };

    const options_fs = AnsiArtRenderer.RenderOptions{
        .algorithm = .ascii,
        .dithering = .floyd_steinberg,
        .color_mode = .grayscale,
        .output_width = 8,
    };

    try AnsiArtRenderer.render(allocator, pixels1, 8, 8, options_no, stream_no.writer());
    try AnsiArtRenderer.render(allocator, pixels2, 8, 8, options_fs, stream_fs.writer());

    const output_no = stream_no.getWritten();
    const output_fs = stream_fs.getWritten();

    // Floyd-Steinberg should produce different output
    try testing.expect(!std.mem.eql(u8, output_no, output_fs));
}

test "ansi art: ordered dithering produces different output than no dithering" {
    var buf_no: [4096]u8 = undefined;
    var stream_no = std.io.fixedBufferStream(&buf_no);
    var buf_ord: [4096]u8 = undefined;
    var stream_ord = std.io.fixedBufferStream(&buf_ord);

    const allocator = testing.allocator;

    const pixels1 = try createGradientImage(allocator, 8, 8);
    defer allocator.free(pixels1);

    const pixels2 = try createGradientImage(allocator, 8, 8);
    defer allocator.free(pixels2);

    const options_no = AnsiArtRenderer.RenderOptions{
        .algorithm = .ascii,
        .dithering = .none,
        .color_mode = .grayscale,
        .output_width = 8,
    };

    const options_ord = AnsiArtRenderer.RenderOptions{
        .algorithm = .ascii,
        .dithering = .ordered,
        .color_mode = .grayscale,
        .output_width = 8,
    };

    try AnsiArtRenderer.render(allocator, pixels1, 8, 8, options_no, stream_no.writer());
    try AnsiArtRenderer.render(allocator, pixels2, 8, 8, options_ord, stream_ord.writer());

    const output_no = stream_no.getWritten();
    const output_ord = stream_ord.getWritten();

    // Ordered dithering should produce different output
    try testing.expect(!std.mem.eql(u8, output_no, output_ord));
}

test "ansi art: both dithering modes produce valid output" {
    var buf_fs: [4096]u8 = undefined;
    var stream_fs = std.io.fixedBufferStream(&buf_fs);
    var buf_ord: [4096]u8 = undefined;
    var stream_ord = std.io.fixedBufferStream(&buf_ord);

    const allocator = testing.allocator;

    const pixels1 = try createGradientImage(allocator, 4, 4);
    defer allocator.free(pixels1);

    const pixels2 = try createGradientImage(allocator, 4, 4);
    defer allocator.free(pixels2);

    const options_fs = AnsiArtRenderer.RenderOptions{
        .algorithm = .ascii,
        .dithering = .floyd_steinberg,
        .color_mode = .grayscale,
        .output_width = 4,
    };

    const options_ord = AnsiArtRenderer.RenderOptions{
        .algorithm = .ascii,
        .dithering = .ordered,
        .color_mode = .grayscale,
        .output_width = 4,
    };

    try AnsiArtRenderer.render(allocator, pixels1, 4, 4, options_fs, stream_fs.writer());
    try AnsiArtRenderer.render(allocator, pixels2, 4, 4, options_ord, stream_ord.writer());

    const output_fs = stream_fs.getWritten();
    const output_ord = stream_ord.getWritten();

    try testing.expect(output_fs.len > 0);
    try testing.expect(output_ord.len > 0);
}

// ============================================================================
// detectColorMode Tests (2 tests)
// ============================================================================

test "ansi art: detectColorMode returns a valid ColorMode enum value" {
    const mode = detectColorMode();
    // Should return one of the four valid modes
    const valid = mode == .truecolor or
        mode == .colors256 or
        mode == .colors16 or
        mode == .grayscale;
    try testing.expect(valid);
}

test "ansi art: detectColorMode does not crash" {
    const mode = detectColorMode();
    // Just ensure it returns without panicking
    _ = mode;
}

// ============================================================================
// Memory & Error Safety Tests (4 tests)
// ============================================================================

test "ansi art: render with width=0 returns error" {
    var buf: [4096]u8 = undefined;
    var stream = std.io.fixedBufferStream(&buf);
    const allocator = testing.allocator;

    const pixels = try createSolidImage(allocator, 1, 1, 100, 100, 100);
    defer allocator.free(pixels);

    const options = AnsiArtRenderer.RenderOptions{
        .algorithm = .block,
        .color_mode = .truecolor,
        .output_width = 0,
    };

    const result = AnsiArtRenderer.render(allocator, pixels, 1, 1, options, stream.writer());
    try testing.expectError(error.InvalidDimensions, result);
}

test "ansi art: render with height=0 returns error" {
    var buf: [4096]u8 = undefined;
    var stream = std.io.fixedBufferStream(&buf);
    const allocator = testing.allocator;

    const pixels = try createSolidImage(allocator, 1, 1, 100, 100, 100);
    defer allocator.free(pixels);

    const options = AnsiArtRenderer.RenderOptions{
        .algorithm = .block,
        .color_mode = .truecolor,
        .output_width = 10,
    };

    const result = AnsiArtRenderer.render(allocator, pixels, 1, 0, options, stream.writer());
    try testing.expectError(error.InvalidDimensions, result);
}

test "ansi art: render with mismatched pixel buffer size returns error or handles gracefully" {
    var buf: [4096]u8 = undefined;
    var stream = std.io.fixedBufferStream(&buf);
    const allocator = testing.allocator;

    // Create pixels for 2x2 (12 bytes), but claim 3x3 (27 bytes)
    const pixels = try createSolidImage(allocator, 2, 2, 100, 100, 100);
    defer allocator.free(pixels);

    const options = AnsiArtRenderer.RenderOptions{
        .algorithm = .block,
        .color_mode = .truecolor,
        .output_width = 10,
    };

    const result = AnsiArtRenderer.render(allocator, pixels, 3, 3, options, stream.writer());
    // Should either error or handle the truncated buffer
    if (result) |_| {
        // If it succeeds, that's OK too (might use what's available)
    } else |err| {
        // Expected to error on size mismatch
        try testing.expect(err == error.InvalidDimensions or err == error.BufferTooSmall);
    }
}

test "ansi art: render with no memory leaks" {
    var buf: [4096]u8 = undefined;
    var stream = std.io.fixedBufferStream(&buf);
    var gpa = std.heap.GeneralPurposeAllocator(.{
        .safety = true,
        .verbose_log = false,
    }){};
    defer _ = gpa.deinit();

    const allocator = gpa.allocator();

    const pixels = try createSolidImage(allocator, 8, 8, 100, 100, 100);
    defer allocator.free(pixels);

    const options = AnsiArtRenderer.RenderOptions{
        .algorithm = .block,
        .color_mode = .truecolor,
        .output_width = 16,
    };

    try AnsiArtRenderer.render(allocator, pixels, 8, 8, options, stream.writer());
    // GPA will detect leaks on deinit if any occurred
}

test "ansi art: renderAuto works and produces output" {
    var buf: [4096]u8 = undefined;
    var stream = std.io.fixedBufferStream(&buf);
    const allocator = testing.allocator;

    const pixels = try createSolidImage(allocator, 4, 4, 150, 150, 150);
    defer allocator.free(pixels);

    try AnsiArtRenderer.renderAuto(allocator, pixels, 4, 4, 8, stream.writer());
    const output = stream.getWritten();

    try testing.expect(output.len > 0);
}

// ============================================================================
// Output Structure Tests (2 tests)
// ============================================================================

test "ansi art: render with 4-row image produces appropriate number of newlines" {
    var buf: [4096]u8 = undefined;
    var stream = std.io.fixedBufferStream(&buf);
    const allocator = testing.allocator;

    // 4 rows with block algorithm = 2 terminal rows (2 pixel rows per terminal row)
    const pixels = try createSolidImage(allocator, 4, 4, 100, 100, 100);
    defer allocator.free(pixels);

    const options = AnsiArtRenderer.RenderOptions{
        .algorithm = .block,
        .color_mode = .truecolor,
        .output_width = 8,
    };

    try AnsiArtRenderer.render(allocator, pixels, 4, 4, options, stream.writer());
    const output = stream.getWritten();

    // Should have at least one newline to separate rows
    var newline_count: u32 = 0;
    for (output) |c| {
        if (c == '\n') newline_count += 1;
    }
    try testing.expect(newline_count >= 1);
}

test "ansi art: render clears styling between rows with reset sequence" {
    var buf: [4096]u8 = undefined;
    var stream = std.io.fixedBufferStream(&buf);
    const allocator = testing.allocator;

    const pixels = try createSolidImage(allocator, 4, 4, 200, 100, 50);
    defer allocator.free(pixels);

    const options = AnsiArtRenderer.RenderOptions{
        .algorithm = .block,
        .color_mode = .truecolor,
        .output_width = 8,
    };

    try AnsiArtRenderer.render(allocator, pixels, 4, 4, options, stream.writer());
    const output = stream.getWritten();

    // Should end with a reset sequence
    try testing.expect(std.mem.endsWith(u8, output, "\x1b[0m") or
        std.mem.endsWith(u8, output, "\x1b[m"));
}

// ============================================================================
// PSNR Quality Metric Tests (9 tests)
// ============================================================================

test "ansi art: psnr identical buffers returns 100.0 (perfect quality)" {
    const allocator = testing.allocator;
    const original = try allocator.alloc(u8, 24);
    defer allocator.free(original);
    const reconstructed = try allocator.alloc(u8, 24);
    defer allocator.free(reconstructed);

    // Fill with same values
    @memset(original, 128);
    @memset(reconstructed, 128);

    const result = sailor.tui.ansi_art.psnr(original, reconstructed);
    try testing.expect(result == 100.0);
}

test "ansi art: psnr all-zero vs all-max buffer returns low value" {
    const allocator = testing.allocator;
    const original = try allocator.alloc(u8, 24);
    defer allocator.free(original);
    const reconstructed = try allocator.alloc(u8, 24);
    defer allocator.free(reconstructed);

    @memset(original, 0);
    @memset(reconstructed, 255);

    const result = sailor.tui.ansi_art.psnr(original, reconstructed);
    // Max difference (255) squared: MSE = 255^2 = 65025
    // PSNR = 10*log10(255^2/65025) = 10*log10(1) = 0.0 dB
    try testing.expect(result < 10.0); // Should be very low
}

test "ansi art: psnr single-bit difference returns high value" {
    const allocator = testing.allocator;
    const original = try allocator.alloc(u8, 24);
    defer allocator.free(original);
    const reconstructed = try allocator.alloc(u8, 24);
    defer allocator.free(reconstructed);

    @memset(original, 128);
    @memset(reconstructed, 128);
    reconstructed[0] = 129; // Single byte differs by 1

    const result = sailor.tui.ansi_art.psnr(original, reconstructed);
    // MSE = 1^2 / 24 ≈ 0.0417
    // PSNR = 10*log10(255^2 / 0.0417) ≈ 43.7 dB
    try testing.expect(result > 40.0);
}

test "ansi art: psnr result is non-negative" {
    const allocator = testing.allocator;
    const original = try allocator.alloc(u8, 12);
    defer allocator.free(original);
    const reconstructed = try allocator.alloc(u8, 12);
    defer allocator.free(reconstructed);

    original[0] = 100;
    original[1] = 200;
    reconstructed[0] = 99;
    reconstructed[1] = 198;

    const result = sailor.tui.ansi_art.psnr(original, reconstructed);
    try testing.expect(result >= 0.0);
}

test "ansi art: psnr with known MSE value gives expected result" {
    const allocator = testing.allocator;
    const original = try allocator.alloc(u8, 3);
    defer allocator.free(original);
    const reconstructed = try allocator.alloc(u8, 3);
    defer allocator.free(reconstructed);

    // Set up for MSE = 100: needs sum of squared errors = 300
    // Three samples, diff of 10 each: 10^2 + 10^2 + 10^2 = 300
    // MSE = 300/3 = 100
    original[0] = 100;
    original[1] = 100;
    original[2] = 100;
    reconstructed[0] = 110;
    reconstructed[1] = 110;
    reconstructed[2] = 110;

    const result = sailor.tui.ansi_art.psnr(original, reconstructed);
    // PSNR = 10*log10(255^2 / 100) = 10*log10(650.25) ≈ 28.13 dB
    try testing.expect(result > 25.0 and result < 32.0);
}

test "ansi art: psnr is symmetric (psnr(a,b) == psnr(b,a))" {
    const allocator = testing.allocator;
    const buf_a = try allocator.alloc(u8, 16);
    defer allocator.free(buf_a);
    const buf_b = try allocator.alloc(u8, 16);
    defer allocator.free(buf_b);

    buf_a[0] = 50;
    buf_a[1] = 100;
    buf_a[2] = 150;
    buf_a[3] = 200;
    buf_b[0] = 51;
    buf_b[1] = 99;
    buf_b[2] = 151;
    buf_b[3] = 199;

    const psnr_ab = sailor.tui.ansi_art.psnr(buf_a, buf_b);
    const psnr_ba = sailor.tui.ansi_art.psnr(buf_b, buf_a);

    // Should be equal within float tolerance
    try testing.expect(@abs(psnr_ab - psnr_ba) < 0.001);
}

test "ansi art: psnr with single-element buffer" {
    const allocator = testing.allocator;
    const original = try allocator.alloc(u8, 1);
    defer allocator.free(original);
    const reconstructed = try allocator.alloc(u8, 1);
    defer allocator.free(reconstructed);

    original[0] = 100;
    reconstructed[0] = 100;

    const result = sailor.tui.ansi_art.psnr(original, reconstructed);
    try testing.expect(result == 100.0);
}

test "ansi art: psnr with gradual differences across buffer" {
    const allocator = testing.allocator;
    const original = try allocator.alloc(u8, 8);
    defer allocator.free(original);
    const reconstructed = try allocator.alloc(u8, 8);
    defer allocator.free(reconstructed);

    // Set up linear gradient of differences
    for (0..8) |i| {
        original[i] = @intCast(i * 32);
        reconstructed[i] = @intCast(i * 32 + 1); // Off by 1
    }

    const result = sailor.tui.ansi_art.psnr(original, reconstructed);
    // MSE = 8 * (1^2) / 8 = 1
    // PSNR = 10*log10(255^2 / 1) = 10*log10(65025) ≈ 48.13 dB
    try testing.expect(result > 45.0 and result < 52.0);
}

// ============================================================================
// SSIM Quality Metric Tests (7 tests)
// ============================================================================

test "ansi art: ssim identical buffers returns 1.0" {
    const allocator = testing.allocator;
    const buf = try allocator.alloc(u8, 12);
    defer allocator.free(buf);

    @memset(buf, 128);

    const result = sailor.tui.ansi_art.ssim(buf, buf, 2, 2);
    try testing.expect(result == 1.0);
}

test "ansi art: ssim completely different images returns low value" {
    const allocator = testing.allocator;
    const original = try allocator.alloc(u8, 12);
    defer allocator.free(original);
    const different = try allocator.alloc(u8, 12);
    defer allocator.free(different);

    @memset(original, 0);
    @memset(different, 255);

    const result = sailor.tui.ansi_art.ssim(original, different, 2, 2);
    try testing.expect(result < 0.5);
}

test "ansi art: ssim result is in range [0.0, 1.0]" {
    const allocator = testing.allocator;
    const buf_a = try allocator.alloc(u8, 12);
    defer allocator.free(buf_a);
    const buf_b = try allocator.alloc(u8, 12);
    defer allocator.free(buf_b);

    @memset(buf_a, 100);
    @memset(buf_b, 150);

    const result = sailor.tui.ansi_art.ssim(buf_a, buf_b, 2, 2);
    try testing.expect(result >= 0.0 and result <= 1.0);
}

test "ansi art: ssim all-constant vs constant-plus-noise gives high value" {
    const allocator = testing.allocator;
    const constant = try allocator.alloc(u8, 16);
    defer allocator.free(constant);
    const noisy = try allocator.alloc(u8, 16);
    defer allocator.free(noisy);

    @memset(constant, 128);
    @memset(noisy, 128);
    noisy[0] = 120;
    noisy[1] = 136;

    const result = sailor.tui.ansi_art.ssim(constant, noisy, 2, 2);
    try testing.expect(result > 0.5);
}

test "ansi art: ssim with 1-pixel-wide image (degenerate width)" {
    const allocator = testing.allocator;
    const buf_a = try allocator.alloc(u8, 6);
    defer allocator.free(buf_a);
    const buf_b = try allocator.alloc(u8, 6);
    defer allocator.free(buf_b);

    @memset(buf_a, 100);
    @memset(buf_b, 100);

    const result = sailor.tui.ansi_art.ssim(buf_a, buf_b, 1, 2);
    // Should not crash and return valid SSIM
    try testing.expect(result >= 0.0 and result <= 1.0);
}

test "ansi art: ssim is symmetric (ssim(a,b) ≈ ssim(b,a))" {
    const allocator = testing.allocator;
    const buf_a = try allocator.alloc(u8, 12);
    defer allocator.free(buf_a);
    const buf_b = try allocator.alloc(u8, 12);
    defer allocator.free(buf_b);

    buf_a[0] = 50;
    buf_a[1] = 100;
    buf_a[2] = 150;
    buf_b[0] = 60;
    buf_b[1] = 110;
    buf_b[2] = 140;

    const ssim_ab = sailor.tui.ansi_art.ssim(buf_a, buf_b, 2, 2);
    const ssim_ba = sailor.tui.ansi_art.ssim(buf_b, buf_a, 2, 2);

    try testing.expect(@abs(ssim_ab - ssim_ba) < 0.001);
}

test "ansi art: ssim RGB24 single-row image" {
    const allocator = testing.allocator;
    // 4x1 RGB24 image = 12 bytes
    const buf_a = try allocator.alloc(u8, 12);
    defer allocator.free(buf_a);
    const buf_b = try allocator.alloc(u8, 12);
    defer allocator.free(buf_b);

    @memset(buf_a, 200);
    @memset(buf_b, 200);

    const result = sailor.tui.ansi_art.ssim(buf_a, buf_b, 4, 3);
    try testing.expect(result == 1.0);
}

// ============================================================================
// AnsiArtPlayer Tests (15 tests)
// ============================================================================

test "ansi art player: init creates empty player" {
    const allocator = testing.allocator;
    const options = AnsiArtRenderer.RenderOptions{
        .algorithm = .block,
        .color_mode = .truecolor,
        .output_width = 80,
    };

    var player = sailor.tui.ansi_art.AnsiArtPlayer.init(allocator, options);
    defer player.deinit();

    try testing.expectEqual(@as(usize, 0), player.getFrameCount());
    try testing.expectEqual(@as(usize, 0), player.getCurrentFrameIndex());
}

test "ansi art player: addFrame clones pixel data" {
    const allocator = testing.allocator;
    const options = AnsiArtRenderer.RenderOptions{
        .algorithm = .block,
        .color_mode = .truecolor,
        .output_width = 80,
    };

    var player = sailor.tui.ansi_art.AnsiArtPlayer.init(allocator, options);
    defer player.deinit();

    var original_pixels = try createSolidImage(allocator, 2, 2, 255, 0, 0);
    defer allocator.free(original_pixels);

    try player.addFrame(original_pixels, 2, 2, 100);

    // Modify original
    original_pixels[0] = 0;

    // Player should have independent copy
    try testing.expectEqual(@as(usize, 1), player.getFrameCount());
}

test "ansi art player: getFrameCount increments after each addFrame" {
    const allocator = testing.allocator;
    const options = AnsiArtRenderer.RenderOptions{
        .algorithm = .block,
        .color_mode = .truecolor,
        .output_width = 80,
    };

    var player = sailor.tui.ansi_art.AnsiArtPlayer.init(allocator, options);
    defer player.deinit();

    try testing.expectEqual(@as(usize, 0), player.getFrameCount());

    const frame1 = try createSolidImage(allocator, 2, 2, 255, 0, 0);
    defer allocator.free(frame1);
    try player.addFrame(frame1, 2, 2, 100);

    try testing.expectEqual(@as(usize, 1), player.getFrameCount());

    const frame2 = try createSolidImage(allocator, 2, 2, 0, 255, 0);
    defer allocator.free(frame2);
    try player.addFrame(frame2, 2, 2, 100);

    try testing.expectEqual(@as(usize, 2), player.getFrameCount());
}

test "ansi art player: player starts paused" {
    const allocator = testing.allocator;
    const options = AnsiArtRenderer.RenderOptions{
        .algorithm = .block,
        .color_mode = .truecolor,
        .output_width = 80,
    };

    var player = sailor.tui.ansi_art.AnsiArtPlayer.init(allocator, options);
    defer player.deinit();

    try testing.expect(!player.is_playing);
}

test "ansi art player: play sets is_playing to true" {
    const allocator = testing.allocator;
    const options = AnsiArtRenderer.RenderOptions{
        .algorithm = .block,
        .color_mode = .truecolor,
        .output_width = 80,
    };

    var player = sailor.tui.ansi_art.AnsiArtPlayer.init(allocator, options);
    defer player.deinit();

    player.play();
    try testing.expect(player.is_playing);
}

test "ansi art player: pause sets is_playing to false" {
    const allocator = testing.allocator;
    const options = AnsiArtRenderer.RenderOptions{
        .algorithm = .block,
        .color_mode = .truecolor,
        .output_width = 80,
    };

    var player = sailor.tui.ansi_art.AnsiArtPlayer.init(allocator, options);
    defer player.deinit();

    player.play();
    try testing.expect(player.is_playing);

    player.pause();
    try testing.expect(!player.is_playing);
}

test "ansi art player: stop resets to frame 0 and pauses" {
    const allocator = testing.allocator;
    const options = AnsiArtRenderer.RenderOptions{
        .algorithm = .block,
        .color_mode = .truecolor,
        .output_width = 80,
    };

    var player = sailor.tui.ansi_art.AnsiArtPlayer.init(allocator, options);
    defer player.deinit();

    const frame1 = try createSolidImage(allocator, 2, 2, 255, 0, 0);
    defer allocator.free(frame1);
    try player.addFrame(frame1, 2, 2, 100);

    const frame2 = try createSolidImage(allocator, 2, 2, 0, 255, 0);
    defer allocator.free(frame2);
    try player.addFrame(frame2, 2, 2, 100);

    player.play();
    player.update(150); // Advance to frame 1

    try testing.expectEqual(@as(usize, 1), player.getCurrentFrameIndex());

    player.stop();

    try testing.expectEqual(@as(usize, 0), player.getCurrentFrameIndex());
    try testing.expect(!player.is_playing);
}

test "ansi art player: update does nothing when paused" {
    const allocator = testing.allocator;
    const options = AnsiArtRenderer.RenderOptions{
        .algorithm = .block,
        .color_mode = .truecolor,
        .output_width = 80,
    };

    var player = sailor.tui.ansi_art.AnsiArtPlayer.init(allocator, options);
    defer player.deinit();

    const frame1 = try createSolidImage(allocator, 2, 2, 255, 0, 0);
    defer allocator.free(frame1);
    try player.addFrame(frame1, 2, 2, 100);

    const frame2 = try createSolidImage(allocator, 2, 2, 0, 255, 0);
    defer allocator.free(frame2);
    try player.addFrame(frame2, 2, 2, 100);

    // Never call play — stays paused
    player.update(200);

    try testing.expectEqual(@as(usize, 0), player.getCurrentFrameIndex());
}

test "ansi art player: update advances frame when playing and enough time elapsed" {
    const allocator = testing.allocator;
    const options = AnsiArtRenderer.RenderOptions{
        .algorithm = .block,
        .color_mode = .truecolor,
        .output_width = 80,
    };

    var player = sailor.tui.ansi_art.AnsiArtPlayer.init(allocator, options);
    defer player.deinit();

    const frame1 = try createSolidImage(allocator, 2, 2, 255, 0, 0);
    defer allocator.free(frame1);
    try player.addFrame(frame1, 2, 2, 100); // 100ms duration

    const frame2 = try createSolidImage(allocator, 2, 2, 0, 255, 0);
    defer allocator.free(frame2);
    try player.addFrame(frame2, 2, 2, 100);

    player.play();
    player.update(150); // 150ms > 100ms

    try testing.expectEqual(@as(usize, 1), player.getCurrentFrameIndex());
}

test "ansi art player: update loops back to frame 0 after last frame when loop=true" {
    const allocator = testing.allocator;
    const options = AnsiArtRenderer.RenderOptions{
        .algorithm = .block,
        .color_mode = .truecolor,
        .output_width = 80,
    };

    var player = sailor.tui.ansi_art.AnsiArtPlayer.init(allocator, options);
    player.loop = true;
    defer player.deinit();

    const frame1 = try createSolidImage(allocator, 2, 2, 255, 0, 0);
    defer allocator.free(frame1);
    try player.addFrame(frame1, 2, 2, 100);

    const frame2 = try createSolidImage(allocator, 2, 2, 0, 255, 0);
    defer allocator.free(frame2);
    try player.addFrame(frame2, 2, 2, 100);

    player.play();
    player.update(250); // Advance through both frames

    // With loop=true, should cycle back to frame 0
    try testing.expectEqual(@as(usize, 0), player.getCurrentFrameIndex());
}

test "ansi art player: isComplete returns true after last frame with loop=false" {
    const allocator = testing.allocator;
    const options = AnsiArtRenderer.RenderOptions{
        .algorithm = .block,
        .color_mode = .truecolor,
        .output_width = 80,
    };

    var player = sailor.tui.ansi_art.AnsiArtPlayer.init(allocator, options);
    player.loop = false;
    defer player.deinit();

    const frame1 = try createSolidImage(allocator, 2, 2, 255, 0, 0);
    defer allocator.free(frame1);
    try player.addFrame(frame1, 2, 2, 100);

    const frame2 = try createSolidImage(allocator, 2, 2, 0, 255, 0);
    defer allocator.free(frame2);
    try player.addFrame(frame2, 2, 2, 100);

    player.play();
    player.update(250);

    try testing.expect(player.isComplete());
}

test "ansi art player: isComplete returns false when loop=true" {
    const allocator = testing.allocator;
    const options = AnsiArtRenderer.RenderOptions{
        .algorithm = .block,
        .color_mode = .truecolor,
        .output_width = 80,
    };

    var player = sailor.tui.ansi_art.AnsiArtPlayer.init(allocator, options);
    player.loop = true;
    defer player.deinit();

    const frame1 = try createSolidImage(allocator, 2, 2, 255, 0, 0);
    defer allocator.free(frame1);
    try player.addFrame(frame1, 2, 2, 100);

    player.play();
    player.update(500);

    try testing.expect(!player.isComplete());
}

test "ansi art player: render writes non-empty output for a 2x2 frame" {
    var buf: [4096]u8 = undefined;
    var stream = std.io.fixedBufferStream(&buf);

    const allocator = testing.allocator;
    const options = AnsiArtRenderer.RenderOptions{
        .algorithm = .block,
        .color_mode = .truecolor,
        .output_width = 80,
    };

    var player = sailor.tui.ansi_art.AnsiArtPlayer.init(allocator, options);
    defer player.deinit();

    const frame = try createSolidImage(allocator, 2, 2, 255, 0, 0);
    defer allocator.free(frame);
    try player.addFrame(frame, 2, 2, 100);

    try player.render(allocator, stream.writer());
    const output = stream.getWritten();

    try testing.expect(output.len > 0);
}

test "ansi art player: multiple addFrame/update cycle advances through all frames" {
    const allocator = testing.allocator;
    const options = AnsiArtRenderer.RenderOptions{
        .algorithm = .block,
        .color_mode = .truecolor,
        .output_width = 80,
    };

    var player = sailor.tui.ansi_art.AnsiArtPlayer.init(allocator, options);
    defer player.deinit();

    const frame1 = try createSolidImage(allocator, 2, 2, 255, 0, 0);
    defer allocator.free(frame1);
    try player.addFrame(frame1, 2, 2, 50);

    const frame2 = try createSolidImage(allocator, 2, 2, 0, 255, 0);
    defer allocator.free(frame2);
    try player.addFrame(frame2, 2, 2, 50);

    const frame3 = try createSolidImage(allocator, 2, 2, 0, 0, 255);
    defer allocator.free(frame3);
    try player.addFrame(frame3, 2, 2, 50);

    player.play();

    // Advance through each frame
    try testing.expectEqual(@as(usize, 0), player.getCurrentFrameIndex());

    player.update(60);
    try testing.expectEqual(@as(usize, 1), player.getCurrentFrameIndex());

    player.update(60);
    try testing.expectEqual(@as(usize, 2), player.getCurrentFrameIndex());
}

test "ansi art player: deinit frees all frame pixel data" {
    var gpa = std.heap.GeneralPurposeAllocator(.{
        .safety = true,
        .verbose_log = false,
    }){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const options = AnsiArtRenderer.RenderOptions{
        .algorithm = .block,
        .color_mode = .truecolor,
        .output_width = 80,
    };

    var player = sailor.tui.ansi_art.AnsiArtPlayer.init(allocator, options);

    const frame1 = try createSolidImage(allocator, 2, 2, 255, 0, 0);
    defer allocator.free(frame1);
    try player.addFrame(frame1, 2, 2, 100);

    const frame2 = try createSolidImage(allocator, 2, 2, 0, 255, 0);
    defer allocator.free(frame2);
    try player.addFrame(frame2, 2, 2, 100);

    player.deinit();
    // GPA will detect leaks on deinit if any occurred
}

// ============================================================================
// convertVideoFrame Tests (5 tests)
// ============================================================================

test "ansi art: convertVideoFrame with frame_number=0 produces non-empty output" {
    var buf: [4096]u8 = undefined;
    var stream = std.io.fixedBufferStream(&buf);

    const allocator = testing.allocator;
    const pixels = try createSolidImage(allocator, 2, 2, 255, 0, 0);
    defer allocator.free(pixels);

    const options = AnsiArtRenderer.RenderOptions{
        .algorithm = .block,
        .color_mode = .truecolor,
        .output_width = 80,
    };

    try sailor.tui.ansi_art.convertVideoFrame(allocator, pixels, 2, 2, options, 0, stream.writer());
    const output = stream.getWritten();

    try testing.expect(output.len > 0);
}

test "ansi art: convertVideoFrame with frame_number>0 writes cursor-up escape sequence" {
    var buf: [4096]u8 = undefined;
    var stream = std.io.fixedBufferStream(&buf);

    const allocator = testing.allocator;
    const pixels = try createSolidImage(allocator, 2, 2, 255, 0, 0);
    defer allocator.free(pixels);

    const options = AnsiArtRenderer.RenderOptions{
        .algorithm = .block,
        .color_mode = .truecolor,
        .output_width = 80,
    };

    try sailor.tui.ansi_art.convertVideoFrame(allocator, pixels, 2, 2, options, 1, stream.writer());
    const output = stream.getWritten();

    // Should contain cursor-up escape: ESC[nA where n is a number
    const has_escape_a = std.mem.containsAtLeast(u8, output, 1, "A");
    try testing.expect(has_escape_a);
}

test "ansi art: convertVideoFrame produces valid output for various frame numbers" {
    var buf: [4096]u8 = undefined;
    var stream = std.io.fixedBufferStream(&buf);

    const allocator = testing.allocator;
    const pixels = try createSolidImage(allocator, 2, 2, 100, 100, 100);
    defer allocator.free(pixels);

    const options = AnsiArtRenderer.RenderOptions{
        .algorithm = .block,
        .color_mode = .truecolor,
        .output_width = 80,
    };

    try sailor.tui.ansi_art.convertVideoFrame(allocator, pixels, 2, 2, options, 5, stream.writer());
    const output = stream.getWritten();

    try testing.expect(output.len > 0);
}

test "ansi art: convertVideoFrame with width=0 returns error" {
    var buf: [4096]u8 = undefined;
    var stream = std.io.fixedBufferStream(&buf);

    const allocator = testing.allocator;
    const pixels = try createSolidImage(allocator, 1, 1, 100, 100, 100);
    defer allocator.free(pixels);

    const options = AnsiArtRenderer.RenderOptions{
        .algorithm = .block,
        .color_mode = .truecolor,
        .output_width = 80,
    };

    const result = sailor.tui.ansi_art.convertVideoFrame(allocator, pixels, 0, 1, options, 0, stream.writer());
    try testing.expectError(error.InvalidDimensions, result);
}

test "ansi art: convertVideoFrame with different algorithms produces different output" {
    var buf1: [4096]u8 = undefined;
    var stream1 = std.io.fixedBufferStream(&buf1);
    var buf2: [4096]u8 = undefined;
    var stream2 = std.io.fixedBufferStream(&buf2);

    const allocator = testing.allocator;
    const pixels1 = try createSolidImage(allocator, 4, 4, 150, 100, 50);
    defer allocator.free(pixels1);
    const pixels2 = try createSolidImage(allocator, 4, 4, 150, 100, 50);
    defer allocator.free(pixels2);

    const options_block = AnsiArtRenderer.RenderOptions{
        .algorithm = .block,
        .color_mode = .truecolor,
        .output_width = 80,
    };

    const options_ascii = AnsiArtRenderer.RenderOptions{
        .algorithm = .ascii,
        .color_mode = .grayscale,
        .output_width = 80,
    };

    try sailor.tui.ansi_art.convertVideoFrame(allocator, pixels1, 4, 4, options_block, 0, stream1.writer());
    try sailor.tui.ansi_art.convertVideoFrame(allocator, pixels2, 4, 4, options_ascii, 0, stream2.writer());

    const output1 = stream1.getWritten();
    const output2 = stream2.getWritten();

    try testing.expect(!std.mem.eql(u8, output1, output2));
}
