/// Adaptive image rendering: Sixel graphics with automatic ANSI art fallback
///
/// Bridges Sixel graphics protocol (for rich terminal graphics) with ANSI art rendering
/// (for terminals without Sixel support). Automatically detects terminal capabilities
/// or allows explicit mode selection.
const std = @import("std");
const sixel = @import("sixel.zig");
const ansi_art = @import("ansi_art.zig");
const Allocator = std.mem.Allocator;

/// Rendering mode selection strategy
pub const RenderMode = enum {
    /// Auto-detect: uses Sixel if supported, falls back to ANSI art
    auto,
    /// Force Sixel output regardless of terminal support
    force_sixel,
    /// Force ANSI art output regardless of terminal support
    force_ansi,
};

/// Adaptive image renderer that bridges Sixel and ANSI art rendering
pub const AdaptiveImageRenderer = struct {
    /// Configuration options for rendering
    pub const Options = struct {
        /// Rendering mode: auto-detect, force Sixel, or force ANSI art
        mode: RenderMode = .auto,
        /// Palette size for Sixel quantization (2-256)
        palette_size: u8 = 16,
        /// ANSI art algorithm: block, braille, or ASCII
        ansi_algorithm: ansi_art.AnsiArtRenderer.Algorithm = .block,
        /// ANSI art color mode: truecolor, colors256, colors16, or grayscale
        ansi_color_mode: ansi_art.AnsiArtRenderer.ColorMode = .truecolor,
        /// ANSI art output width in character columns
        ansi_width: u32 = 80,
        /// ANSI art output height in character rows (optional, auto-calculated if null)
        ansi_height: ?u32 = null,
    };

    /// Render image to writer with adaptive fallback
    ///
    /// Args:
    ///   allocator: Memory allocator for temporary buffers
    ///   pixels_rgb: Raw RGB pixel data (3 bytes per pixel, row-major)
    ///   width: Image width in pixels
    ///   height: Image height in pixels
    ///   options: Rendering configuration
    ///   writer: Output writer (e.g., stdout)
    ///
    /// Returns:
    ///   error.InvalidPixelBuffer if pixels_rgb.len != width * height * 3
    ///   error.InvalidDimensions if width/height/ansi_width is zero (propagated from ANSI art)
    ///   Other errors from sixel or ANSI art rendering
    pub fn render(
        allocator: Allocator,
        pixels_rgb: []const u8,
        width: u32,
        height: u32,
        options: Options,
        writer: anytype,
    ) !void {
        // Validate pixel buffer size
        const expected_size = @as(usize, width) * height * 3;
        if (pixels_rgb.len != expected_size) {
            return error.BufferTooSmall;
        }

        // Determine which renderer to use
        const use_sixel = switch (options.mode) {
            .force_sixel => true,
            .force_ansi => false,
            .auto => sixel.detectSixelSupport(),
        };

        if (use_sixel) {
            // Sixel path: convert RGB bytes to SixelImage.Color array
            try renderViaSixel(allocator, pixels_rgb, width, height, options, writer);
        } else {
            // ANSI art fallback
            try renderViaAnsiArt(allocator, pixels_rgb, width, height, options, writer);
        }
    }

    /// Internal: Render via Sixel encoder
    fn renderViaSixel(
        allocator: Allocator,
        pixels_rgb: []const u8,
        width: u32,
        height: u32,
        options: Options,
        writer: anytype,
    ) !void {
        // Convert RGB bytes to SixelImage.Color array
        const pixel_count = @as(usize, width) * height;
        const colors = try allocator.alloc(sixel.SixelImage.Color, pixel_count);
        defer allocator.free(colors);

        for (0..pixel_count) |i| {
            colors[i] = sixel.SixelImage.Color.fromRgb(
                pixels_rgb[i * 3],
                pixels_rgb[i * 3 + 1],
                pixels_rgb[i * 3 + 2],
            );
        }

        const image = sixel.SixelImage{
            .width = @intCast(width),
            .height = @intCast(height),
            .pixels = colors,
        };

        const encoder = sixel.SixelEncoder{
            .max_colors = @min(256, @as(u16, options.palette_size)),
        };
        try encoder.encode(allocator, image, writer);
    }

    /// Internal: Render via ANSI art renderer
    fn renderViaAnsiArt(
        allocator: Allocator,
        pixels_rgb: []const u8,
        width: u32,
        height: u32,
        options: Options,
        writer: anytype,
    ) !void {
        try ansi_art.AnsiArtRenderer.render(
            allocator,
            pixels_rgb,
            width,
            height,
            .{
                .algorithm = options.ansi_algorithm,
                .color_mode = options.ansi_color_mode,
                .output_width = options.ansi_width,
                .output_height = options.ansi_height,
            },
            writer,
        );
    }
};
