//! Kitty graphics protocol support for high-performance image rendering.
//!
//! The Kitty graphics protocol is a modern terminal image protocol supporting:
//! - RGB24 and RGBA32 pixel formats
//! - Base64-encoded image data
//! - Direct display, virtual placements, and Unicode placeholders
//! - Image placement with positioning, scaling, and cropping
//! - 24-bit color without palette quantization (unlike Sixel)
//!
//! Reference: https://sw.kovidgoyal.net/kitty/graphics-protocol/
//!
//! ## Usage Example
//!
//! ```zig
//! const kitty = @import("kitty.zig");
//!
//! // Create an image from RGBA pixel data
//! var img = kitty.KittyImage{
//!     .width = 100,
//!     .height = 50,
//!     .pixels = rgba_buffer,
//!     .format = .rgba32,
//! };
//!
//! // Encode and write to terminal
//! var encoder = kitty.KittyEncoder.init(allocator);
//! defer encoder.deinit();
//! try encoder.encode(img, writer);
//! ```

const std = @import("std");
const builtin = @import("builtin");
const Allocator = std.mem.Allocator;

/// Pixel format for Kitty images
pub const PixelFormat = enum {
    /// 24-bit RGB (3 bytes per pixel)
    rgb24,
    /// 32-bit RGBA with alpha channel (4 bytes per pixel)
    rgba32,
};

/// Transmission medium for encoded image data
pub const TransmissionMedium = enum {
    /// Direct base64-encoded data in escape sequence (default)
    direct,
    /// Temporary file path (for large images)
    file,
    /// Shared memory object (fastest, requires OS support)
    shared_mem,
};

/// Kitty image structure
pub const KittyImage = struct {
    /// Image width in pixels
    width: u32,
    /// Image height in pixels
    height: u32,
    /// Pixel data in row-major order (RGB24 or RGBA32)
    pixels: []const u8,
    /// Pixel format (rgb24 or rgba32)
    format: PixelFormat = .rgba32,

    /// Get bytes per pixel based on format
    pub fn bytesPerPixel(self: KittyImage) u8 {
        return switch (self.format) {
            .rgb24 => 3,
            .rgba32 => 4,
        };
    }

    /// Validate image dimensions and pixel buffer size
    pub fn validate(self: KittyImage) !void {
        const expected_len = self.width * self.height * self.bytesPerPixel();
        if (self.pixels.len != expected_len) {
            return error.InvalidPixelBufferSize;
        }
    }
};

/// Kitty graphics encoder
pub const KittyEncoder = struct {
    allocator: Allocator,
    /// Maximum chunk size for base64 data (4096 bytes recommended by spec)
    chunk_size: usize = 4096,

    /// Initialize Kitty graphics encoder with allocator.
    pub fn init(allocator: Allocator) KittyEncoder {
        return .{ .allocator = allocator };
    }

    /// Free resources (currently a no-op).
    pub fn deinit(_: *KittyEncoder) void {
        // No state to clean up currently
    }

    /// Encode image to Kitty graphics protocol and write to output
    pub fn encode(
        self: *KittyEncoder,
        image: KittyImage,
        writer: anytype,
        transmission: TransmissionMedium,
    ) !void {
        try image.validate();

        // Encode pixel data to base64
        const encoder = std.base64.standard.Encoder;
        const encoded_len = encoder.calcSize(image.pixels.len);
        const encoded_data = try self.allocator.alloc(u8, encoded_len);
        defer self.allocator.free(encoded_data);

        _ = encoder.encode(encoded_data, image.pixels);

        // Write Kitty graphics control sequence with chunking
        try self.writeImageData(writer, image, encoded_data, transmission);
    }

    /// Write image data in chunks using Kitty graphics protocol
    fn writeImageData(
        self: *KittyEncoder,
        writer: anytype,
        image: KittyImage,
        encoded_data: []const u8,
        transmission: TransmissionMedium,
    ) !void {
        const format_code: u8 = switch (image.format) {
            .rgb24 => 24,
            .rgba32 => 32,
        };

        const transmission_code: u8 = switch (transmission) {
            .direct => 'd',
            .file => 'f',
            .shared_mem => 's',
        };

        var offset: usize = 0;
        var chunk_id: u32 = 0;

        while (offset < encoded_data.len) {
            const chunk_end = @min(offset + self.chunk_size, encoded_data.len);
            const chunk = encoded_data[offset..chunk_end];
            const is_first = chunk_id == 0;
            const is_last = chunk_end >= encoded_data.len;

            // Write control sequence: ESC _G <control data> ; <payload> ESC \
            try writer.writeAll("\x1b_G");

            // Write control data on first chunk
            if (is_first) {
                try writer.print("a=T,f={d},s={d},v={d},t={c}", .{
                    format_code,
                    image.width,
                    image.height,
                    transmission_code,
                });
            }

            // Add 'm' parameter for chunking (m=0: more data, m=1: last chunk)
            if (encoded_data.len > self.chunk_size) {
                if (is_first) try writer.writeAll(",");
                try writer.print("m={d}", .{@as(u8, if (is_last) 1 else 0)});
            }

            // Write payload
            try writer.writeAll(";");
            try writer.writeAll(chunk);
            try writer.writeAll("\x1b\\");

            offset = chunk_end;
            chunk_id += 1;
        }
    }

    /// Place a previously transmitted image at specific cell coordinates
    pub fn placeImage(
        _: *KittyEncoder,
        writer: anytype,
        image_id: u32,
        x: u16,
        y: u16,
        cols: ?u16,
        rows: ?u16,
    ) !void {
        // ESC _G a=p,i=<id>,X=<x>,Y=<y>[,c=<cols>,r=<rows>] ESC \
        try writer.writeAll("\x1b_Ga=p");
        try writer.print(",i={d},X={d},Y={d}", .{ image_id, x, y });
        if (cols) |c| try writer.print(",c={d}", .{c});
        if (rows) |r| try writer.print(",r={d}", .{r});
        try writer.writeAll("\x1b\\");
    }

    /// Delete image by ID
    pub fn deleteImage(_: *KittyEncoder, writer: anytype, image_id: u32) !void {
        // ESC _G a=d,i=<id> ESC \
        try writer.print("\x1b_Ga=d,i={d}\x1b\\", .{image_id});
    }

    /// Delete all images
    pub fn deleteAllImages(_: *KittyEncoder, writer: anytype) !void {
        // ESC _G a=d,d=a ESC \
        try writer.writeAll("\x1b_Ga=d,d=a\x1b\\");
    }
};

/// Detect if terminal supports Kitty graphics protocol
pub fn detectKittySupport() bool {
    const term_mod = @import("../term.zig");

    // Try XTGETTCAP query first (most reliable)
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Query "TN" (terminal name) capability with 100ms timeout
    // Kitty terminals typically identify as "xterm-kitty"
    const stdout_fd: std.posix.fd_t = if (builtin.os.tag == .windows) blk: {
        const handle = std.os.windows.GetStdHandle(std.os.windows.STD_OUTPUT_HANDLE) catch return false;
        break :blk @ptrCast(handle);
    } else
        std.posix.STDOUT_FILENO;

    if (term_mod.queryTerminalCapability(allocator, stdout_fd, "TN", 100)) |value| {
        defer allocator.free(value);
        const has_kitty = std.mem.indexOf(u8, value, "kitty") != null;
        if (has_kitty) return true;
    } else |_| {
        // XTGETTCAP failed - fall back to env vars
    }

    // Fallback: Check for TERM_PROGRAM=kitty or KITTY_WINDOW_ID environment variable
    // (Windows doesn't support std.posix.getenv - env vars are UTF-16)
    if (builtin.os.tag == .windows) {
        return false;
    } else {
        const term_program = std.posix.getenv("TERM_PROGRAM");
        if (term_program) |prog| {
            if (std.mem.eql(u8, prog, "kitty")) return true;
        }

        const kitty_window = std.posix.getenv("KITTY_WINDOW_ID");
        if (kitty_window != null) return true;

        // Check for TERM containing "kitty"
        const term = std.posix.getenv("TERM");
        if (term) |t| {
            if (std.mem.indexOf(u8, t, "kitty") != null) return true;
        }

        return false;
    }
}

// ============================================================================
// Tests
// ============================================================================

const testing = std.testing;
const fixedBufferStream = std.io.fixedBufferStream;

test "KittyImage: bytes per pixel" {
    const img_rgb = KittyImage{
        .width = 10,
        .height = 10,
        .pixels = &[_]u8{},
        .format = .rgb24,
    };
    try testing.expectEqual(@as(u8, 3), img_rgb.bytesPerPixel());

    const img_rgba = KittyImage{
        .width = 10,
        .height = 10,
        .pixels = &[_]u8{},
        .format = .rgba32,
    };
    try testing.expectEqual(@as(u8, 4), img_rgba.bytesPerPixel());
}

test "KittyImage: validate dimensions" {
    // Valid RGBA image
    const valid_pixels = [_]u8{0} ** (4 * 4 * 4); // 4x4 RGBA
    const valid_img = KittyImage{
        .width = 4,
        .height = 4,
        .pixels = &valid_pixels,
        .format = .rgba32,
    };
    try valid_img.validate();

    // Invalid: pixel buffer too small
    const invalid_pixels = [_]u8{0} ** 10;
    const invalid_img = KittyImage{
        .width = 4,
        .height = 4,
        .pixels = &invalid_pixels,
        .format = .rgba32,
    };
    try testing.expectError(error.InvalidPixelBufferSize, invalid_img.validate());
}

test "KittyEncoder: init and deinit" {
    var encoder = KittyEncoder.init(testing.allocator);
    defer encoder.deinit();
    try testing.expectEqual(@as(usize, 4096), encoder.chunk_size);
}

test "KittyEncoder: encode small RGBA image (direct)" {
    const pixels = [_]u8{
        255, 0, 0, 255, // Red pixel
        0, 255, 0, 255, // Green pixel
        0, 0, 255, 255, // Blue pixel
        255, 255, 255, 255, // White pixel
    };
    const img = KittyImage{
        .width = 2,
        .height = 2,
        .pixels = &pixels,
        .format = .rgba32,
    };

    var buf: [1024]u8 = undefined;
    var fbs = fixedBufferStream(&buf);
    var encoder = KittyEncoder.init(testing.allocator);
    defer encoder.deinit();

    try encoder.encode(img, fbs.writer(), .direct);

    const output = fbs.getWritten();
    // Should contain Kitty control sequence
    try testing.expect(std.mem.indexOf(u8, output, "\x1b_G") != null);
    try testing.expect(std.mem.indexOf(u8, output, "a=T") != null);
    try testing.expect(std.mem.indexOf(u8, output, "f=32") != null); // RGBA32
    try testing.expect(std.mem.indexOf(u8, output, "s=2") != null); // width
    try testing.expect(std.mem.indexOf(u8, output, "v=2") != null); // height
    try testing.expect(std.mem.indexOf(u8, output, "t=d") != null); // direct transmission
    try testing.expect(std.mem.indexOf(u8, output, "\x1b\\") != null);
}

test "KittyEncoder: encode RGB24 image" {
    const pixels = [_]u8{
        255, 0, 0, // Red
        0, 255, 0, // Green
        0, 0, 255, // Blue
    };
    const img = KittyImage{
        .width = 3,
        .height = 1,
        .pixels = &pixels,
        .format = .rgb24,
    };

    var buf: [1024]u8 = undefined;
    var fbs = fixedBufferStream(&buf);
    var encoder = KittyEncoder.init(testing.allocator);
    defer encoder.deinit();

    try encoder.encode(img, fbs.writer(), .direct);

    const output = fbs.getWritten();
    try testing.expect(std.mem.indexOf(u8, output, "f=24") != null); // RGB24
    try testing.expect(std.mem.indexOf(u8, output, "s=3") != null); // width
    try testing.expect(std.mem.indexOf(u8, output, "v=1") != null); // height
}

test "KittyEncoder: chunked encoding for large image" {
    const allocator = testing.allocator;
    // Create image larger than chunk_size (4096 bytes)
    // 64x64 RGBA = 16384 bytes, will need multiple chunks
    const pixels = try allocator.alloc(u8, 64 * 64 * 4);
    defer allocator.free(pixels);
    @memset(pixels, 128); // Gray image

    const img = KittyImage{
        .width = 64,
        .height = 64,
        .pixels = pixels,
        .format = .rgba32,
    };

    var buf = std.ArrayList(u8){};
    defer buf.deinit(allocator);
    var encoder = KittyEncoder.init(allocator);
    defer encoder.deinit();
    encoder.chunk_size = 4096;

    try encoder.encode(img, buf.writer(allocator), .direct);

    const output = buf.items;
    // Should have multiple chunks (m=0 for continuation, m=1 for last)
    const first_chunk = std.mem.indexOf(u8, output, "m=0");
    const last_chunk = std.mem.indexOf(u8, output, "m=1");
    try testing.expect(first_chunk != null);
    try testing.expect(last_chunk != null);
}

test "KittyEncoder: placeImage" {
    var buf: [256]u8 = undefined;
    var fbs = fixedBufferStream(&buf);
    var encoder = KittyEncoder.init(testing.allocator);
    defer encoder.deinit();

    try encoder.placeImage(fbs.writer(), 42, 10, 5, 20, 15);

    const output = fbs.getWritten();
    try testing.expect(std.mem.indexOf(u8, output, "\x1b_Ga=p") != null);
    try testing.expect(std.mem.indexOf(u8, output, "i=42") != null);
    try testing.expect(std.mem.indexOf(u8, output, "X=10") != null);
    try testing.expect(std.mem.indexOf(u8, output, "Y=5") != null);
    try testing.expect(std.mem.indexOf(u8, output, "c=20") != null);
    try testing.expect(std.mem.indexOf(u8, output, "r=15") != null);
}

test "KittyEncoder: placeImage without cols/rows" {
    var buf: [256]u8 = undefined;
    var fbs = fixedBufferStream(&buf);
    var encoder = KittyEncoder.init(testing.allocator);
    defer encoder.deinit();

    try encoder.placeImage(fbs.writer(), 42, 10, 5, null, null);

    const output = fbs.getWritten();
    try testing.expect(std.mem.indexOf(u8, output, "i=42") != null);
    try testing.expect(std.mem.indexOf(u8, output, "X=10") != null);
    try testing.expect(std.mem.indexOf(u8, output, "Y=5") != null);
    // Should NOT contain cols/rows
    try testing.expect(std.mem.indexOf(u8, output, "c=") == null);
    try testing.expect(std.mem.indexOf(u8, output, "r=") == null);
}

test "KittyEncoder: deleteImage" {
    var buf: [128]u8 = undefined;
    var fbs = fixedBufferStream(&buf);
    var encoder = KittyEncoder.init(testing.allocator);
    defer encoder.deinit();

    try encoder.deleteImage(fbs.writer(), 99);

    const output = fbs.getWritten();
    try testing.expectEqualStrings("\x1b_Ga=d,i=99\x1b\\", output);
}

test "KittyEncoder: deleteAllImages" {
    var buf: [128]u8 = undefined;
    var fbs = fixedBufferStream(&buf);
    var encoder = KittyEncoder.init(testing.allocator);
    defer encoder.deinit();

    try encoder.deleteAllImages(fbs.writer());

    const output = fbs.getWritten();
    try testing.expectEqualStrings("\x1b_Ga=d,d=a\x1b\\", output);
}

test "KittyEncoder: file transmission medium" {
    const pixels = [_]u8{255} ** 16; // 2x2 RGBA
    const img = KittyImage{
        .width = 2,
        .height = 2,
        .pixels = &pixels,
        .format = .rgba32,
    };

    var buf: [1024]u8 = undefined;
    var fbs = fixedBufferStream(&buf);
    var encoder = KittyEncoder.init(testing.allocator);
    defer encoder.deinit();

    try encoder.encode(img, fbs.writer(), .file);

    const output = fbs.getWritten();
    try testing.expect(std.mem.indexOf(u8, output, "t=f") != null); // file transmission
}

test "KittyEncoder: shared memory transmission medium" {
    const pixels = [_]u8{255} ** 16; // 2x2 RGBA
    const img = KittyImage{
        .width = 2,
        .height = 2,
        .pixels = &pixels,
        .format = .rgba32,
    };

    var buf: [1024]u8 = undefined;
    var fbs = fixedBufferStream(&buf);
    var encoder = KittyEncoder.init(testing.allocator);
    defer encoder.deinit();

    try encoder.encode(img, fbs.writer(), .shared_mem);

    const output = fbs.getWritten();
    try testing.expect(std.mem.indexOf(u8, output, "t=s") != null); // shared mem transmission
}

test "detectKittySupport: no environment variables" {
    // Skip when stdout is not a TTY (e.g., zig build test --listen=- mode)
    // detectKittySupport() writes escape sequences to STDOUT_FILENO which
    // would corrupt the --listen=- IPC pipe
    const term_mod = @import("../term.zig");
    if (!term_mod.isatty(std.posix.STDOUT_FILENO)) return error.SkipZigTest;
    _ = detectKittySupport();
}

test "KittyEncoder: zero-sized image validation" {
    const img = KittyImage{
        .width = 0,
        .height = 0,
        .pixels = &[_]u8{},
        .format = .rgba32,
    };
    try img.validate(); // 0*0*4 = 0 bytes, should be valid
}

test "KittyEncoder: single pixel image" {
    const pixels = [_]u8{ 255, 128, 64, 255 }; // 1x1 RGBA
    const img = KittyImage{
        .width = 1,
        .height = 1,
        .pixels = &pixels,
        .format = .rgba32,
    };

    var buf: [512]u8 = undefined;
    var fbs = fixedBufferStream(&buf);
    var encoder = KittyEncoder.init(testing.allocator);
    defer encoder.deinit();

    try encoder.encode(img, fbs.writer(), .direct);

    const output = fbs.getWritten();
    try testing.expect(std.mem.indexOf(u8, output, "s=1") != null);
    try testing.expect(std.mem.indexOf(u8, output, "v=1") != null);
}

test "KittyEncoder: wide image (1000x1 RGB24)" {
    const allocator = testing.allocator;
    const pixels = try allocator.alloc(u8, 1000 * 1 * 3);
    defer allocator.free(pixels);
    @memset(pixels, 200);

    const img = KittyImage{
        .width = 1000,
        .height = 1,
        .pixels = pixels,
        .format = .rgb24,
    };

    var buf = std.ArrayList(u8){};
    defer buf.deinit(allocator);
    var encoder = KittyEncoder.init(allocator);
    defer encoder.deinit();

    try encoder.encode(img, buf.writer(allocator), .direct);

    const output = buf.items;
    try testing.expect(std.mem.indexOf(u8, output, "s=1000") != null);
    try testing.expect(std.mem.indexOf(u8, output, "v=1") != null);
}

test "KittyEncoder: tall image (1x500 RGBA32)" {
    const allocator = testing.allocator;
    const pixels = try allocator.alloc(u8, 1 * 500 * 4);
    defer allocator.free(pixels);
    @memset(pixels, 50);

    const img = KittyImage{
        .width = 1,
        .height = 500,
        .pixels = pixels,
        .format = .rgba32,
    };

    var buf = std.ArrayList(u8){};
    defer buf.deinit(allocator);
    var encoder = KittyEncoder.init(allocator);
    defer encoder.deinit();

    try encoder.encode(img, buf.writer(allocator), .direct);

    const output = buf.items;
    try testing.expect(std.mem.indexOf(u8, output, "s=1") != null);
    try testing.expect(std.mem.indexOf(u8, output, "v=500") != null);
}

test "KittyEncoder: custom chunk size" {
    const pixels = [_]u8{255} ** (10 * 10 * 4); // 10x10 RGBA
    const img = KittyImage{
        .width = 10,
        .height = 10,
        .pixels = &pixels,
        .format = .rgba32,
    };

    var buf: [2048]u8 = undefined;
    var fbs = fixedBufferStream(&buf);
    var encoder = KittyEncoder.init(testing.allocator);
    defer encoder.deinit();
    encoder.chunk_size = 128; // Small chunk size to force multiple chunks

    try encoder.encode(img, fbs.writer(), .direct);

    const output = fbs.getWritten();
    // With small chunk size, should have chunking markers
    try testing.expect(output.len > 0);
}
