/// Sixel graphics protocol support for inline images in compatible terminals
/// Implements DEC Sixel graphics specification for rendering raster images
const std = @import("std");
const builtin = @import("builtin");
const Allocator = std.mem.Allocator;
const Writer = std.io.Writer;

/// Sixel image format parameters
pub const SixelImage = struct {
    width: u16,
    height: u16,
    pixels: []const Color, // Row-major RGBA pixel data

    pub const Color = struct {
        r: u8,
        g: u8,
        b: u8,
        a: u8 = 255, // Alpha channel (0=transparent, 255=opaque)

        /// Creates a Color from RGB components with opaque alpha (255).
        ///
        /// Args:
        ///   r: Red channel (0-255)
        ///   g: Green channel (0-255)
        ///   b: Blue channel (0-255)
        ///
        /// Returns:
        ///   Color with full opacity
        pub fn fromRgb(r: u8, g: u8, b: u8) Color {
            return .{ .r = r, .g = g, .b = b };
        }

        /// Creates a Color from RGBA components including transparency.
        ///
        /// Args:
        ///   r: Red channel (0-255)
        ///   g: Green channel (0-255)
        ///   b: Blue channel (0-255)
        ///   a: Alpha channel (0=transparent, 255=opaque)
        ///
        /// Returns:
        ///   Color with specified opacity
        pub fn fromRgba(r: u8, g: u8, b: u8, a: u8) Color {
            return .{ .r = r, .g = g, .b = b, .a = a };
        }
    };
};

/// Sixel encoder configuration
pub const SixelEncoder = struct {
    /// Maximum colors in palette (2-256, typically 256 for 24-bit color terminals)
    max_colors: u16 = 256,

    /// Use transparency (skip pixels with alpha < 128)
    use_transparency: bool = true,

    /// Color quantization algorithm
    quantization: QuantizationMethod = .median_cut,

    pub const QuantizationMethod = enum {
        median_cut, // Median cut algorithm (better quality)
        octree, // Octree quantization (faster)
        none, // No quantization (use existing palette)
    };

    /// Encode an image to Sixel format
    pub fn encode(self: SixelEncoder, allocator: Allocator, image: SixelImage, writer: anytype) !void {
        // Start Sixel sequence: ESC P q
        try writer.writeAll("\x1bPq");

        // Define raster attributes: "width;height
        try writer.print("\"1;1;{};{}", .{ image.width, image.height });

        // Build color palette
        const palette = try self.buildPalette(allocator, image);
        defer allocator.free(palette);

        // Define colors in palette: #index;2;r;g;b (RGB mode)
        for (palette, 0..) |color, i| {
            try writer.print("#{};2;{};{};{}", .{
                i,
                @as(u16, color.r) * 100 / 255,
                @as(u16, color.g) * 100 / 255,
                @as(u16, color.b) * 100 / 255,
            });
        }

        // Encode pixel data in sixels (groups of 6 vertical pixels)
        const sixel_height = (image.height + 5) / 6; // Round up to sixels

        var y: u16 = 0;
        while (y < sixel_height) : (y += 1) {
            try self.encodeSixelRow(allocator, image, palette, y, writer);
            if (y + 1 < sixel_height) {
                try writer.writeAll("-"); // Move to next sixel row
            }
        }

        // End Sixel sequence: ESC \
        try writer.writeAll("\x1b\\");
    }

    fn buildPalette(self: SixelEncoder, allocator: Allocator, image: SixelImage) ![]SixelImage.Color {
        if (self.quantization == .none) {
            // No quantization, collect unique colors (up to max_colors)
            var unique_colors: std.ArrayList(SixelImage.Color) = .{};
            defer unique_colors.deinit(allocator);

            for (image.pixels) |pixel| {
                if (self.use_transparency and pixel.a < 128) continue;

                var found = false;
                for (unique_colors.items) |existing| {
                    if (existing.r == pixel.r and existing.g == pixel.g and existing.b == pixel.b) {
                        found = true;
                        break;
                    }
                }

                if (!found) {
                    if (unique_colors.items.len >= self.max_colors) break;
                    try unique_colors.append(allocator, pixel);
                }
            }

            return try allocator.dupe(SixelImage.Color, unique_colors.items);
        }

        // Median cut quantization (simple implementation)
        return try self.medianCutQuantize(allocator, image);
    }

    fn medianCutQuantize(self: SixelEncoder, allocator: Allocator, image: SixelImage) ![]SixelImage.Color {
        // Simplified median cut: collect all opaque pixels, sort by dominant channel, split
        var pixels: std.ArrayList(SixelImage.Color) = .{};
        defer pixels.deinit(allocator);

        for (image.pixels) |pixel| {
            if (self.use_transparency and pixel.a < 128) continue;
            try pixels.append(allocator, pixel);
        }

        if (pixels.items.len == 0) {
            // All transparent, return single black color
            const black = try allocator.alloc(SixelImage.Color, 1);
            black[0] = .{ .r = 0, .g = 0, .b = 0 };
            return black;
        }

        // For simplicity, just take first max_colors unique pixels
        var palette: std.ArrayList(SixelImage.Color) = .{};
        defer palette.deinit(allocator);

        for (pixels.items) |pixel| {
            var found = false;
            for (palette.items) |existing| {
                if (existing.r == pixel.r and existing.g == pixel.g and existing.b == pixel.b) {
                    found = true;
                    break;
                }
            }

            if (!found) {
                if (palette.items.len >= self.max_colors) break;
                try palette.append(allocator, pixel);
            }
        }

        return try allocator.dupe(SixelImage.Color, palette.items);
    }

    fn encodeSixelRow(
        self: SixelEncoder,
        allocator: Allocator,
        image: SixelImage,
        palette: []const SixelImage.Color,
        sixel_y: u16,
        writer: anytype,
    ) !void {
        _ = allocator;

        // For each color in palette, encode run-length pixels
        for (palette, 0..) |color, color_idx| {
            // Select color: #index
            try writer.print("#{}", .{color_idx});

            var x: u16 = 0;
            while (x < image.width) {
                // Compute sixel value for this column (6 vertical pixels)
                var sixel_value: u8 = 0;
                var bit: u8 = 0;
                while (bit < 6) : (bit += 1) {
                    const pixel_y = sixel_y * 6 + bit;
                    if (pixel_y >= image.height) break;

                    const pixel_idx = @as(usize, pixel_y) * image.width + x;
                    const pixel = image.pixels[pixel_idx];

                    // Skip transparent pixels
                    if (self.use_transparency and pixel.a < 128) continue;

                    // Check if pixel matches this color
                    if (pixel.r == color.r and pixel.g == color.g and pixel.b == color.b) {
                        sixel_value |= (@as(u8, 1) << @intCast(bit));
                    }
                }

                // Encode sixel value as ASCII char (? = 0x3f + value)
                if (sixel_value > 0) {
                    try writer.writeByte(0x3f + sixel_value);
                }

                x += 1;
            }

            // Move to start of next row for next color: $
            if (color_idx + 1 < palette.len) {
                try writer.writeAll("$");
            }
        }
    }
};

/// Sixel decoder for parsing Sixel sequences back into images
pub const SixelDecoder = struct {
    /// Maximum allowed image width (prevents DoS via huge allocations)
    max_width: u16 = 4096,

    /// Maximum allowed image height
    max_height: u16 = 4096,

    /// Decode a Sixel sequence into an image
    pub fn decode(self: SixelDecoder, allocator: Allocator, data: []const u8) !SixelImage {
        // Validate Sixel sequence markers
        if (data.len < 5) return error.InvalidSixelFormat;
        if (!std.mem.startsWith(u8, data, "\x1bPq")) return error.InvalidSixelFormat;
        if (!std.mem.endsWith(u8, data, "\x1b\\")) return error.InvalidSixelFormat;

        // Extract payload (strip \x1bPq and \x1b\)
        const payload = data[3 .. data.len - 2];

        // Parse raster attributes: "Pan;Pad;Ph;Pv (width=Ph, height=Pv)
        var width: u16 = 0;
        var height: u16 = 0;
        var pos: usize = 0;

        if (std.mem.indexOfScalar(u8, payload, '"')) |raster_start| {
            pos = raster_start + 1;

            // Find end of raster attributes (first non-digit/semicolon char)
            var raster_end = pos;
            while (raster_end < payload.len) : (raster_end += 1) {
                const c = payload[raster_end];
                if (c != ';' and (c < '0' or c > '9')) break;
            }

            const raster_str = payload[pos..raster_end];
            var attr_parts = std.mem.tokenizeScalar(u8, raster_str, ';');

            // Skip Pan (aspect ratio) parameters if present
            _ = attr_parts.next() orelse return error.InvalidRasterAttributes;
            _ = attr_parts.next() orelse return error.InvalidRasterAttributes;

            // Parse width and height
            const width_str = attr_parts.next() orelse return error.InvalidRasterAttributes;
            const height_str = attr_parts.next() orelse return error.InvalidRasterAttributes;

            width = std.fmt.parseInt(u16, width_str, 10) catch return error.InvalidRasterAttributes;
            height = std.fmt.parseInt(u16, height_str, 10) catch return error.InvalidRasterAttributes;

            // Validate dimensions
            if (width == 0 or height == 0) return error.InvalidDimensions;
            if (width > self.max_width or height > self.max_height) return error.DimensionsTooLarge;

            pos = raster_end;
        } else {
            return error.InvalidRasterAttributes;
        }

        // Allocate pixel buffer (initialized to transparent black)
        const pixel_count = @as(usize, width) * @as(usize, height);
        const pixels = try allocator.alloc(SixelImage.Color, pixel_count);
        errdefer allocator.free(pixels);
        @memset(pixels, .{ .r = 0, .g = 0, .b = 0, .a = 0 }); // Transparent by default

        // Parse color palette and pixel data
        var palette: [256]SixelImage.Color = undefined;
        var current_color: u8 = 0;
        var x: u16 = 0;
        var y: u16 = 0; // Current sixel row (6-pixel units)

        while (pos < payload.len) {
            const c = payload[pos];
            pos += 1;

            switch (c) {
                '#' => {
                    // Color definition or selection: #index;2;r;g;b OR #index
                    const semicolon1 = std.mem.indexOfScalarPos(u8, payload, pos, ';') orelse {
                        // Just color selection: #index (no semicolon)
                        const num_end = pos;
                        while (num_end < payload.len and payload[num_end] >= '0' and payload[num_end] <= '9') : (pos += 1) {}
                        const index_str = payload[pos - 1 .. num_end];
                        current_color = std.fmt.parseInt(u8, index_str, 10) catch return error.InvalidColorDefinition;
                        continue;
                    };

                    const index_str = payload[pos..semicolon1];
                    const color_index = std.fmt.parseInt(u8, index_str, 10) catch return error.InvalidColorDefinition;
                    pos = semicolon1 + 1;

                    // Check if this is a definition (";2;r;g;b") or just selection
                    if (pos < payload.len and payload[pos] == '2') {
                        pos += 1; // Skip '2'
                        if (pos >= payload.len or payload[pos] != ';') return error.InvalidColorDefinition;
                        pos += 1; // Skip ';'

                        // Parse R
                        const semicolon2 = std.mem.indexOfScalarPos(u8, payload, pos, ';') orelse return error.InvalidColorDefinition;
                        const r_str = payload[pos..semicolon2];
                        const r_val = std.fmt.parseInt(u16, r_str, 10) catch return error.InvalidColorDefinition;
                        if (r_val > 100) return error.ColorValueOutOfRange;
                        pos = semicolon2 + 1;

                        // Parse G
                        const semicolon3 = std.mem.indexOfScalarPos(u8, payload, pos, ';') orelse return error.InvalidColorDefinition;
                        const g_str = payload[pos..semicolon3];
                        const g_val = std.fmt.parseInt(u16, g_str, 10) catch return error.InvalidColorDefinition;
                        if (g_val > 100) return error.ColorValueOutOfRange;
                        pos = semicolon3 + 1;

                        // Parse B (may end with any non-digit char)
                        var b_end = pos;
                        while (b_end < payload.len and payload[b_end] >= '0' and payload[b_end] <= '9') : (b_end += 1) {}
                        const b_str = payload[pos..b_end];
                        const b_val = std.fmt.parseInt(u16, b_str, 10) catch return error.InvalidColorDefinition;
                        if (b_val > 100) return error.ColorValueOutOfRange;
                        pos = b_end;

                        // Scale from 0-100 to 0-255
                        palette[color_index] = .{
                            .r = @intCast(r_val * 255 / 100),
                            .g = @intCast(g_val * 255 / 100),
                            .b = @intCast(b_val * 255 / 100),
                            .a = 255,
                        };
                    }

                    current_color = color_index;
                },
                '$' => {
                    // Carriage return (move to start of current sixel row)
                    x = 0;
                },
                '-' => {
                    // Line feed (move to next sixel row)
                    y += 1;
                    x = 0;
                },
                '?' ... '~' => {
                    // Sixel data: '?' (0x3f) represents 0, '~' (0x7e) represents 63
                    const sixel_value = c - 0x3f;

                    // Decode 6 vertical pixels
                    var bit: u8 = 0;
                    while (bit < 6) : (bit += 1) {
                        if ((sixel_value & (@as(u8, 1) << @as(u3, @intCast(bit)))) != 0) {
                            const pixel_y = y * 6 + bit;
                            if (pixel_y < height and x < width) {
                                const pixel_idx = @as(usize, pixel_y) * width + x;
                                pixels[pixel_idx] = palette[current_color];
                            }
                        }
                    }

                    x += 1;
                },
                else => {
                    // Ignore other characters (whitespace, unknown control codes)
                },
            }
        }

        return SixelImage{
            .width = width,
            .height = height,
            .pixels = pixels,
        };
    }
};

/// Detect if terminal supports Sixel graphics
pub fn detectSixelSupport() bool {
    const term_mod = @import("../term.zig");

    // Try XTGETTCAP query first (most reliable)
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Query "Sixel" capability with 100ms timeout
    const stdout_fd: std.posix.fd_t = if (builtin.os.tag == .windows) blk: {
        const handle = std.os.windows.GetStdHandle(std.os.windows.STD_OUTPUT_HANDLE) catch return false;
        break :blk @ptrCast(handle);
    } else
        std.posix.STDOUT_FILENO;

    if (term_mod.hasCapability(allocator, stdout_fd, "Sixel", 100)) |has_sixel| {
        if (has_sixel) return true;
    } else |_| {
        // XTGETTCAP failed (not a TTY, unsupported platform, etc.) - fall back to env vars
    }

    // Fallback: Check TERM environment variable for known Sixel-capable terminals
    // Windows doesn't support std.posix.getenv (env vars are UTF-16)
    if (builtin.os.tag == .windows) {
        return false;
    } else {
        const term = std.posix.getenv("TERM") orelse return false;

        const sixel_terms = [_][]const u8{
            "xterm-256color",
            "mlterm",
            "yaft",
            "foot",
            "wezterm",
            "contour",
        };

        for (sixel_terms) |known_term| {
            if (std.mem.eql(u8, term, known_term)) {
                return true;
            }
        }

        return false;
    }
}

// ============================================================================
// Tests
// ============================================================================

test "SixelImage Color creation" {
    const color1 = SixelImage.Color.fromRgb(255, 128, 64);
    try std.testing.expectEqual(@as(u8, 255), color1.r);
    try std.testing.expectEqual(@as(u8, 128), color1.g);
    try std.testing.expectEqual(@as(u8, 64), color1.b);
    try std.testing.expectEqual(@as(u8, 255), color1.a); // Default alpha

    const color2 = SixelImage.Color.fromRgba(100, 150, 200, 128);
    try std.testing.expectEqual(@as(u8, 128), color2.a);
}

test "SixelEncoder basic encode 2x2 solid image" {
    const allocator = std.testing.allocator;

    // Create 2x2 red image
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
    try encoder.encode(allocator, image, output.writer(allocator));

    const result = output.items;

    // Verify Sixel sequence markers
    try std.testing.expect(std.mem.startsWith(u8, result, "\x1bPq")); // Start
    try std.testing.expect(std.mem.endsWith(u8, result, "\x1b\\")); // End
    try std.testing.expect(std.mem.indexOf(u8, result, "\"1;1;2;2") != null); // Raster attrs
}

test "SixelEncoder transparency handling" {
    const allocator = std.testing.allocator;

    // Create 2x2 image with transparent pixel
    const pixels = [_]SixelImage.Color{
        .{ .r = 255, .g = 0, .b = 0, .a = 255 }, // Opaque red
        .{ .r = 0, .g = 255, .b = 0, .a = 0 }, // Transparent
        .{ .r = 0, .g = 0, .b = 255, .a = 255 }, // Opaque blue
        .{ .r = 255, .g = 255, .b = 255, .a = 64 }, // Semi-transparent (treated as transparent)
    };

    const image = SixelImage{
        .width = 2,
        .height = 2,
        .pixels = &pixels,
    };

    var output: std.ArrayList(u8) = .{};
    defer output.deinit(allocator);

    const encoder = SixelEncoder{ .use_transparency = true };
    try encoder.encode(allocator, image, output.writer(allocator));

    const result = output.items;

    // Should only encode opaque pixels
    try std.testing.expect(result.len > 0);
    try std.testing.expect(std.mem.startsWith(u8, result, "\x1bPq"));
}

test "SixelEncoder palette building" {
    const allocator = std.testing.allocator;

    const pixels = [_]SixelImage.Color{
        .{ .r = 255, .g = 0, .b = 0 }, // Red
        .{ .r = 0, .g = 255, .b = 0 }, // Green
        .{ .r = 0, .g = 0, .b = 255 }, // Blue
        .{ .r = 255, .g = 0, .b = 0 }, // Red again (duplicate)
    };

    const image = SixelImage{
        .width = 2,
        .height = 2,
        .pixels = &pixels,
    };

    const encoder = SixelEncoder{ .quantization = .none };
    const palette = try encoder.buildPalette(allocator, image);
    defer allocator.free(palette);

    // Should have 3 unique colors
    try std.testing.expectEqual(@as(usize, 3), palette.len);
}

test "SixelEncoder max colors limit" {
    const allocator = std.testing.allocator;

    // Create image with 10 unique colors
    var pixels: [10]SixelImage.Color = undefined;
    for (&pixels, 0..) |*p, i| {
        p.* = .{ .r = @intCast(i * 25), .g = 0, .b = 0 };
    }

    const image = SixelImage{
        .width = 10,
        .height = 1,
        .pixels = &pixels,
    };

    const encoder = SixelEncoder{ .max_colors = 5, .quantization = .none };
    const palette = try encoder.buildPalette(allocator, image);
    defer allocator.free(palette);

    // Should limit to 5 colors
    try std.testing.expectEqual(@as(usize, 5), palette.len);
}

test "SixelEncoder all transparent image" {
    const allocator = std.testing.allocator;

    const pixels = [_]SixelImage.Color{
        .{ .r = 0, .g = 0, .b = 0, .a = 0 },
        .{ .r = 0, .g = 0, .b = 0, .a = 0 },
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

    const result = output.items;

    // Should produce valid Sixel sequence with black palette
    try std.testing.expect(std.mem.startsWith(u8, result, "\x1bPq"));
    try std.testing.expect(std.mem.endsWith(u8, result, "\x1b\\"));
}

test "SixelEncoder 1x6 vertical stripe" {
    const allocator = std.testing.allocator;

    // Create 1x6 vertical stripe (fills one sixel column exactly)
    const pixels = [_]SixelImage.Color{
        .{ .r = 255, .g = 0, .b = 0 },
        .{ .r = 255, .g = 0, .b = 0 },
        .{ .r = 255, .g = 0, .b = 0 },
        .{ .r = 255, .g = 0, .b = 0 },
        .{ .r = 255, .g = 0, .b = 0 },
        .{ .r = 255, .g = 0, .b = 0 },
    };

    const image = SixelImage{
        .width = 1,
        .height = 6,
        .pixels = &pixels,
    };

    var output: std.ArrayList(u8) = .{};
    defer output.deinit(allocator);

    const encoder = SixelEncoder{};
    try encoder.encode(allocator, image, output.writer(allocator));

    const result = output.items;

    // Should encode full sixel (6 bits set = 63 + 0x3f = 0x7e = '~')
    try std.testing.expect(std.mem.indexOf(u8, result, "~") != null);
}

test "SixelEncoder 1x7 vertical stripe (partial sixel)" {
    const allocator = std.testing.allocator;

    // Create 1x7 stripe (needs 2 sixel rows)
    var pixels: [7]SixelImage.Color = undefined;
    for (&pixels) |*p| {
        p.* = .{ .r = 0, .g = 255, .b = 0 };
    }

    const image = SixelImage{
        .width = 1,
        .height = 7,
        .pixels = &pixels,
    };

    var output: std.ArrayList(u8) = .{};
    defer output.deinit(allocator);

    const encoder = SixelEncoder{};
    try encoder.encode(allocator, image, output.writer(allocator));

    const result = output.items;

    // Should have row separator '-'
    try std.testing.expect(std.mem.indexOf(u8, result, "-") != null);
}

test "detectSixelSupport with known terminal" {
    // Skip when stdout is not a TTY (e.g., zig build test --listen=- mode)
    // detectSixelSupport() writes escape sequences to STDOUT_FILENO which
    // would corrupt the --listen=- IPC pipe
    const term_mod = @import("../term.zig");
    if (!term_mod.isatty(std.posix.STDOUT_FILENO)) return error.SkipZigTest;
    _ = detectSixelSupport();
}

test "SixelEncoder color RGB scaling" {
    const allocator = std.testing.allocator;

    const pixels = [_]SixelImage.Color{
        .{ .r = 255, .g = 128, .b = 64 },
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

    const result = output.items;

    // Color definition should scale RGB to 0-100 range
    // r=255 → 100, g=128 → 50, b=64 → 25
    try std.testing.expect(std.mem.indexOf(u8, result, "#0;2;100;50;25") != null);
}

test "SixelEncoder multiple colors with run-length" {
    const allocator = std.testing.allocator;

    // Create 4x1 image: red, red, blue, blue
    const pixels = [_]SixelImage.Color{
        .{ .r = 255, .g = 0, .b = 0 },
        .{ .r = 255, .g = 0, .b = 0 },
        .{ .r = 0, .g = 0, .b = 255 },
        .{ .r = 0, .g = 0, .b = 255 },
    };

    const image = SixelImage{
        .width = 4,
        .height = 1,
        .pixels = &pixels,
    };

    var output: std.ArrayList(u8) = .{};
    defer output.deinit(allocator);

    const encoder = SixelEncoder{};
    try encoder.encode(allocator, image, output.writer(allocator));

    const result = output.items;

    // Should define at least 2 colors
    try std.testing.expect(std.mem.indexOf(u8, result, "#0;2;") != null);
    try std.testing.expect(std.mem.indexOf(u8, result, "#1;2;") != null);
}

test "SixelEncoder empty image (0x0)" {
    const allocator = std.testing.allocator;

    const image = SixelImage{
        .width = 0,
        .height = 0,
        .pixels = &[_]SixelImage.Color{},
    };

    var output: std.ArrayList(u8) = .{};
    defer output.deinit(allocator);

    const encoder = SixelEncoder{};
    try encoder.encode(allocator, image, output.writer(allocator));

    const result = output.items;

    // Should produce valid (but empty) Sixel sequence
    try std.testing.expect(std.mem.startsWith(u8, result, "\x1bPq"));
    try std.testing.expect(std.mem.endsWith(u8, result, "\x1b\\"));
}

test "SixelEncoder single pixel" {
    const allocator = std.testing.allocator;

    const pixels = [_]SixelImage.Color{
        .{ .r = 42, .g = 84, .b = 168 },
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

    const result = output.items;

    try std.testing.expect(std.mem.startsWith(u8, result, "\x1bPq"));
    try std.testing.expect(std.mem.indexOf(u8, result, "\"1;1;1;1") != null); // 1x1 raster
}

test "SixelEncoder no transparency mode" {
    const allocator = std.testing.allocator;

    const pixels = [_]SixelImage.Color{
        .{ .r = 255, .g = 0, .b = 0, .a = 0 }, // Fully transparent
        .{ .r = 0, .g = 255, .b = 0, .a = 64 }, // Semi-transparent
    };

    const image = SixelImage{
        .width = 2,
        .height = 1,
        .pixels = &pixels,
    };

    var output: std.ArrayList(u8) = .{};
    defer output.deinit(allocator);

    const encoder = SixelEncoder{ .use_transparency = false }; // Ignore alpha
    try encoder.encode(allocator, image, output.writer(allocator));

    const result = output.items;

    // Should encode all pixels regardless of alpha
    try std.testing.expect(result.len > 0);
}

test "SixelEncoder wide image (triggers multiple columns)" {
    const allocator = std.testing.allocator;

    // Create 8x1 alternating colors
    var pixels: [8]SixelImage.Color = undefined;
    for (&pixels, 0..) |*p, i| {
        p.* = if (i % 2 == 0)
            .{ .r = 255, .g = 0, .b = 0 }
        else
            .{ .r = 0, .g = 0, .b = 255 };
    }

    const image = SixelImage{
        .width = 8,
        .height = 1,
        .pixels = &pixels,
    };

    var output: std.ArrayList(u8) = .{};
    defer output.deinit(allocator);

    const encoder = SixelEncoder{};
    try encoder.encode(allocator, image, output.writer(allocator));

    const result = output.items;

    // Should produce valid Sixel with multiple pixel runs
    try std.testing.expect(std.mem.startsWith(u8, result, "\x1bPq"));
    try std.testing.expect(std.mem.indexOf(u8, result, "\"1;1;8;1") != null); // 8x1 raster
}

test "SixelEncoder tall image (multiple sixel rows)" {
    const allocator = std.testing.allocator;

    // Create 1x12 vertical stripe (2 sixel rows)
    var pixels: [12]SixelImage.Color = undefined;
    for (&pixels) |*p| {
        p.* = .{ .r = 128, .g = 128, .b = 128 };
    }

    const image = SixelImage{
        .width = 1,
        .height = 12,
        .pixels = &pixels,
    };

    var output: std.ArrayList(u8) = .{};
    defer output.deinit(allocator);

    const encoder = SixelEncoder{};
    try encoder.encode(allocator, image, output.writer(allocator));

    const result = output.items;

    // Should have row separator '-'
    try std.testing.expect(std.mem.indexOf(u8, result, "-") != null);
    try std.testing.expect(std.mem.indexOf(u8, result, "\"1;1;1;12") != null); // 1x12 raster
}
