const std = @import("std");
const Allocator = std.mem.Allocator;

/// Detect terminal color mode from environment variables.
pub fn detectColorMode() AnsiArtRenderer.ColorMode {
    const alloc = std.heap.page_allocator;

    if (std.process.getEnvVarOwned(alloc, "COLORTERM")) |val| {
        defer alloc.free(val);
        if (std.mem.eql(u8, val, "truecolor") or std.mem.eql(u8, val, "24bit")) {
            return .truecolor;
        }
    } else |_| {}

    if (std.process.getEnvVarOwned(alloc, "TERM")) |val| {
        defer alloc.free(val);
        if (std.mem.indexOf(u8, val, "256color") != null) return .colors256;
        if (std.mem.startsWith(u8, val, "xterm") or
            std.mem.startsWith(u8, val, "screen") or
            std.mem.startsWith(u8, val, "tmux")) return .colors16;
    } else |_| {}

    return .colors16;
}

/// Map RGB to the nearest xterm 256-color index.
pub fn rgb256(r: u8, g: u8, b: u8) u8 {
    // Special case: pure black and white
    if (r == 0 and g == 0 and b == 0) return 16;
    if (r == 255 and g == 255 and b == 255) return 231;

    // 6×6×6 colour cube (indices 16–231)
    const ri: u8 = @intCast((@as(u32, r) * 5 + 127) / 255);
    const gi: u8 = @intCast((@as(u32, g) * 5 + 127) / 255);
    const bi: u8 = @intCast((@as(u32, b) * 5 + 127) / 255);
    return 16 + 36 * ri + 6 * gi + bi;
}

/// Map RGB to the nearest 16-color ANSI index.
pub fn rgb16(r: u8, g: u8, b: u8) u8 {
    const brightness = (@as(u32, r) + @as(u32, g) + @as(u32, b)) / 3;

    if (r == 0 and g == 0 and b == 0) return 0;
    if (r == 255 and g == 255 and b == 255) return 15;

    const is_bright = brightness > 127;

    // Achromatic
    const max_ch = @max(r, @max(g, b));
    const min_ch = @min(r, @min(g, b));
    const chroma = @as(u32, max_ch) -| @as(u32, min_ch);
    if (chroma < 40) {
        if (brightness < 64) return 0;
        if (brightness >= 192) return if (is_bright) 15 else 7;
        return if (is_bright) 8 else 7;
    }

    // Hue determination
    const rr = @as(i32, r);
    const gg = @as(i32, g);
    const bb = @as(i32, b);

    if (rr >= gg and rr >= bb and rr - gg > 30 and rr - bb > 30)
        return if (is_bright) 9 else 1; // red
    if (gg >= rr and gg >= bb and gg - rr > 30 and gg - bb > 30)
        return if (is_bright) 10 else 2; // green
    if (bb >= rr and bb >= gg and bb - rr > 30 and bb - gg > 30)
        return if (is_bright) 12 else 4; // blue
    if (rr > 150 and gg > 150 and bb < 80)
        return if (is_bright) 11 else 3; // yellow
    if (gg > 150 and bb > 150 and rr < 80)
        return if (is_bright) 14 else 6; // cyan
    if (rr > 150 and bb > 150 and gg < 80)
        return if (is_bright) 13 else 5; // magenta

    return if (is_bright) 7 else 0;
}

pub const AnsiArtRenderer = struct {
    pub const Algorithm = enum { block, braille, ascii };

    pub const ColorMode = enum { truecolor, colors256, colors16, grayscale };

    pub const Dithering = enum { none, floyd_steinberg, ordered };

    pub const RenderOptions = struct {
        algorithm: Algorithm = .block,
        color_mode: ColorMode = .truecolor,
        output_width: u32 = 80,
        output_height: ?u32 = null,
        dithering: Dithering = .none,
    };

    pub fn render(
        allocator: Allocator,
        pixels: []const u8,
        width: u32,
        height: u32,
        options: RenderOptions,
        writer: anytype,
    ) !void {
        if (options.output_width == 0 or height == 0 or width == 0)
            return error.InvalidDimensions;
        if (pixels.len < @as(usize, width) * height * 3)
            return error.BufferTooSmall;

        switch (options.algorithm) {
            .block => try renderBlock(allocator, pixels, width, height, options, writer),
            .braille => try renderBraille(pixels, width, height, options, writer),
            .ascii => try renderAscii(allocator, pixels, width, height, options, writer),
        }
    }

    pub fn renderAuto(
        allocator: Allocator,
        pixels: []const u8,
        width: u32,
        height: u32,
        output_width: u32,
        writer: anytype,
    ) !void {
        try render(allocator, pixels, width, height, .{
            .algorithm = .block,
            .color_mode = detectColorMode(),
            .output_width = output_width,
        }, writer);
    }

    // -------------------------------------------------------------------------

    fn renderBlock(
        _: Allocator,
        pixels: []const u8,
        width: u32,
        height: u32,
        options: RenderOptions,
        writer: anytype,
    ) !void {
        // Cap out_w at source width to avoid upscaling which would overflow fixed output buffers
        const out_w = @min(options.output_width, width);
        const out_h = options.output_height orelse (height + 1) / 2;

        const scale_x = @as(f32, @floatFromInt(width)) / @as(f32, @floatFromInt(out_w));
        const scale_y = @as(f32, @floatFromInt(height)) / @as(f32, @floatFromInt(out_h * 2));

        for (0..out_h) |row_usize| {
            const row: u32 = @intCast(row_usize);
            for (0..out_w) |col_usize| {
                const col: u32 = @intCast(col_usize);

                const src_x = @min(
                    @as(u32, @intFromFloat(@as(f32, @floatFromInt(col)) * scale_x)),
                    width - 1,
                );
                const src_y_top = @min(
                    @as(u32, @intFromFloat(@as(f32, @floatFromInt(row * 2)) * scale_y)),
                    height - 1,
                );
                const src_y_bot = @min(
                    @as(u32, @intFromFloat(@as(f32, @floatFromInt(row * 2 + 1)) * scale_y)),
                    height - 1,
                );

                const ti = (src_y_top * width + src_x) * 3;
                const bi = (src_y_bot * width + src_x) * 3;

                const tr = pixels[ti];
                const tg = pixels[ti + 1];
                const tb = pixels[ti + 2];
                const br = pixels[bi];
                const bg_c = pixels[bi + 1];
                const bb = pixels[bi + 2];

                if (options.color_mode != .grayscale) {
                    switch (options.color_mode) {
                        .truecolor => {
                            try writer.print("\x1b[38;2;{};{};{}m", .{ tr, tg, tb });
                            try writer.print("\x1b[48;2;{};{};{}m", .{ br, bg_c, bb });
                        },
                        .colors256 => {
                            try writer.print("\x1b[38;5;{}m", .{rgb256(tr, tg, tb)});
                            try writer.print("\x1b[48;5;{}m", .{rgb256(br, bg_c, bb)});
                        },
                        .colors16 => {
                            try writer.print("\x1b[38;5;{}m", .{rgb16(tr, tg, tb)});
                            try writer.print("\x1b[48;5;{}m", .{rgb16(br, bg_c, bb)});
                        },
                        .grayscale => unreachable,
                    }
                }

                if (tr == br and tg == bg_c and tb == bb) {
                    try writer.writeAll("█"); // U+2588 FULL BLOCK
                } else {
                    try writer.writeAll("▀"); // U+2580 UPPER HALF BLOCK
                }
            }

            if (options.color_mode != .grayscale) try writer.writeAll("\x1b[0m");
            try writer.writeByte('\n');
        }

        if (options.color_mode != .grayscale) try writer.writeAll("\x1b[0m");
    }

    fn renderBraille(
        pixels: []const u8,
        width: u32,
        height: u32,
        options: RenderOptions,
        writer: anytype,
    ) !void {
        const out_w = options.output_width;
        // 2 pixel cols × 4 pixel rows per braille char
        const out_h = options.output_height orelse (height + 3) / 4;

        const scale_x = @as(f32, @floatFromInt(width)) / @as(f32, @floatFromInt(out_w * 2));
        const scale_y = @as(f32, @floatFromInt(height)) / @as(f32, @floatFromInt(out_h * 4));

        // Braille dot→bit mapping (Unicode order):
        // bit 0:(dx=0,dy=0) bit 1:(0,1) bit 2:(0,2) bit 3:(1,0)
        // bit 4:(1,1)       bit 5:(1,2) bit 6:(0,3) bit 7:(1,3)
        const DX = [8]u32{ 0, 0, 0, 1, 1, 1, 0, 1 };
        const DY = [8]u32{ 0, 1, 2, 0, 1, 2, 3, 3 };

        for (0..out_h) |row_usize| {
            const row: u32 = @intCast(row_usize);
            for (0..out_w) |col_usize| {
                const col: u32 = @intCast(col_usize);
                var bits: u8 = 0;

                for (0..8) |bit| {
                    const dx = DX[bit];
                    const dy = DY[bit];
                    const sx = @min(
                        @as(u32, @intFromFloat((@as(f32, @floatFromInt(col * 2 + dx)) + 0.5) * scale_x)),
                        width - 1,
                    );
                    const sy = @min(
                        @as(u32, @intFromFloat((@as(f32, @floatFromInt(row * 4 + dy)) + 0.5) * scale_y)),
                        height - 1,
                    );

                    const idx = (sy * width + sx) * 3;
                    const lum = (@as(u32, pixels[idx]) * 2126 +
                        @as(u32, pixels[idx + 1]) * 7152 +
                        @as(u32, pixels[idx + 2]) * 722) / 10000;

                    if (lum > 127) bits |= @as(u8, 1) << @intCast(bit);
                }

                var utf8_buf: [4]u8 = undefined;
                const cp: u21 = 0x2800 + @as(u21, bits);
                const len = try std.unicode.utf8Encode(cp, &utf8_buf);
                try writer.writeAll(utf8_buf[0..len]);
            }
            try writer.writeByte('\n');
        }
    }

    fn renderAscii(
        allocator: Allocator,
        pixels: []const u8,
        width: u32,
        height: u32,
        options: RenderOptions,
        writer: anytype,
    ) !void {
        const palette = " .,:;i1tfLCG08@";
        const palette_max: f32 = @floatFromInt(palette.len - 1);

        const out_w = options.output_width;
        const out_h = options.output_height orelse height;

        const scale_x = @as(f32, @floatFromInt(width)) / @as(f32, @floatFromInt(out_w));
        const scale_y = @as(f32, @floatFromInt(height)) / @as(f32, @floatFromInt(out_h));

        var err_buf: ?[]f32 = null;
        defer if (err_buf) |buf| allocator.free(buf);
        if (options.dithering == .floyd_steinberg) {
            err_buf = try allocator.alloc(f32, out_w * out_h);
            @memset(err_buf.?, 0);
        }

        // 4×4 Bayer matrix (values 0..15, normalised to 0..1 at use time)
        const bayer = [4][4]u8{
            .{ 0, 8, 2, 10 },
            .{ 12, 4, 14, 6 },
            .{ 3, 11, 1, 9 },
            .{ 15, 7, 13, 5 },
        };

        for (0..out_h) |row_usize| {
            const row: u32 = @intCast(row_usize);
            for (0..out_w) |col_usize| {
                const col: u32 = @intCast(col_usize);

                const sx = @min(
                    @as(u32, @intFromFloat(@as(f32, @floatFromInt(col)) * scale_x)),
                    width - 1,
                );
                const sy = @min(
                    @as(u32, @intFromFloat(@as(f32, @floatFromInt(row)) * scale_y)),
                    height - 1,
                );
                const idx = (sy * width + sx) * 3;
                const r = pixels[idx];
                const g = pixels[idx + 1];
                const b = pixels[idx + 2];

                var lum = (@as(f32, @floatFromInt(r)) * 0.2126 +
                    @as(f32, @floatFromInt(g)) * 0.7152 +
                    @as(f32, @floatFromInt(b)) * 0.0722) / 255.0;

                switch (options.dithering) {
                    .none => {},
                    .floyd_steinberg => {
                        if (err_buf) |buf| {
                            lum = std.math.clamp(lum + buf[row * out_w + col], 0.0, 1.0);
                        }
                    },
                    .ordered => {
                        const thresh = @as(f32, @floatFromInt(bayer[row % 4][col % 4])) / 16.0;
                        lum = if (lum > thresh) 1.0 else 0.0;
                    },
                }

                const pi = @min(
                    @as(u32, @intFromFloat(lum * palette_max + 0.5)),
                    @as(u32, palette.len - 1),
                );

                if (options.dithering == .floyd_steinberg) {
                    if (err_buf) |buf| {
                        const quantized = @as(f32, @floatFromInt(pi)) / palette_max;
                        const ferr = lum - quantized;
                        if (col + 1 < out_w)
                            buf[row * out_w + col + 1] += ferr * 7.0 / 16.0;
                        if (row + 1 < out_h) {
                            if (col > 0)
                                buf[(row + 1) * out_w + col - 1] += ferr * 3.0 / 16.0;
                            buf[(row + 1) * out_w + col] += ferr * 5.0 / 16.0;
                            if (col + 1 < out_w)
                                buf[(row + 1) * out_w + col + 1] += ferr * 1.0 / 16.0;
                        }
                    }
                }

                if (options.color_mode != .grayscale) {
                    switch (options.color_mode) {
                        .truecolor => try writer.print("\x1b[38;2;{};{};{}m", .{ r, g, b }),
                        .colors256 => try writer.print("\x1b[38;5;{}m", .{rgb256(r, g, b)}),
                        .colors16 => try writer.print("\x1b[38;5;{}m", .{rgb16(r, g, b)}),
                        .grayscale => unreachable,
                    }
                }

                try writer.writeByte(palette[pi]);
            }

            if (options.color_mode != .grayscale) try writer.writeAll("\x1b[0m");
            try writer.writeByte('\n');
        }

        if (options.color_mode != .grayscale) try writer.writeAll("\x1b[0m");
    }
};

// ============================================================================
// Quality Metrics
// ============================================================================

/// Peak Signal-to-Noise Ratio in decibels. Returns 100.0 for identical buffers.
/// Requires original.len == reconstructed.len.
pub fn psnr(original: []const u8, reconstructed: []const u8) f64 {
    if (original.len == 0) return 100.0;
    if (std.mem.eql(u8, original, reconstructed)) return 100.0;

    var sum_sq_diff: f64 = 0.0;
    for (original, reconstructed) |o, r| {
        const diff: f64 = @floatFromInt(@as(i16, @intCast(o)) - @as(i16, @intCast(r)));
        sum_sq_diff += diff * diff;
    }

    const mse = sum_sq_diff / @as(f64, @floatFromInt(original.len));
    if (mse == 0.0) return 100.0;

    const max_val = 255.0;
    const psnr_val = 10.0 * std.math.log10(max_val * max_val / mse);
    return psnr_val;
}

/// Structural Similarity Index Measure (0.0-1.0, higher is better).
/// width = row stride in pixels, channels = bytes per pixel.
/// Clamps result to [0.0, 1.0].
pub fn ssim(original: []const u8, reconstructed: []const u8, width: u32, channels: u32) f64 {
    _ = width;
    _ = channels;

    if (original.len == 0) return 1.0;
    if (original.len != reconstructed.len) return 0.0;
    if (std.mem.eql(u8, original, reconstructed)) return 1.0;

    const n = @as(f64, @floatFromInt(original.len));

    // Compute global means
    var sum_x: f64 = 0.0;
    var sum_y: f64 = 0.0;
    for (original, reconstructed) |x, y| {
        sum_x += @floatFromInt(x);
        sum_y += @floatFromInt(y);
    }
    const mu_x = sum_x / n;
    const mu_y = sum_y / n;

    // Compute global variance and covariance
    var sum_sq_x: f64 = 0.0;
    var sum_sq_y: f64 = 0.0;
    var sum_cov: f64 = 0.0;
    for (original, reconstructed) |x, y| {
        const fx = @as(f64, @floatFromInt(x)) - mu_x;
        const fy = @as(f64, @floatFromInt(y)) - mu_y;
        sum_sq_x += fx * fx;
        sum_sq_y += fy * fy;
        sum_cov += fx * fy;
    }
    const sigma_x2 = sum_sq_x / n;
    const sigma_y2 = sum_sq_y / n;
    const sigma_xy = sum_cov / n;

    // SSIM constants
    const C1 = 6.5025; // (0.01 * 255)^2
    const C2 = 58.5225; // (0.03 * 255)^2

    // Numerator: (2*mu_x*mu_y + C1)*(2*sigma_xy + C2)
    const num_lum = 2.0 * mu_x * mu_y + C1;
    const num_struct = 2.0 * sigma_xy + C2;
    const numerator = num_lum * num_struct;

    // Denominator: (mu_x^2 + mu_y^2 + C1)*(sigma_x2 + sigma_y2 + C2)
    const denom_lum = mu_x * mu_x + mu_y * mu_y + C1;
    const denom_struct = sigma_x2 + sigma_y2 + C2;
    const denominator = denom_lum * denom_struct;

    if (denominator == 0.0) return 1.0;

    const result = numerator / denominator;
    return std.math.clamp(result, 0.0, 1.0);
}

// ============================================================================
// AnsiArtPlayer — Frame-Based Animation Playback
// ============================================================================

pub const AnsiArtPlayer = struct {
    pub const Frame = struct {
        pixels: []u8, // owned clone, freed by deinit
        width: u32,
        height: u32,
        duration_ms: u64,
    };

    allocator: Allocator,
    frames: std.ArrayListUnmanaged(Frame),
    current_frame: usize,
    elapsed_ms: u64,
    is_playing: bool,
    loop: bool,
    done: bool,
    options: AnsiArtRenderer.RenderOptions,

    pub fn init(allocator: Allocator, options: AnsiArtRenderer.RenderOptions) AnsiArtPlayer {
        return AnsiArtPlayer{
            .allocator = allocator,
            .frames = .{},
            .current_frame = 0,
            .elapsed_ms = 0,
            .is_playing = false,
            .loop = false,
            .done = false,
            .options = options,
        };
    }

    pub fn deinit(self: *AnsiArtPlayer) void {
        for (self.frames.items) |frame| {
            self.allocator.free(frame.pixels);
        }
        self.frames.deinit(self.allocator);
    }

    pub fn addFrame(self: *AnsiArtPlayer, pixels: []const u8, width: u32, height: u32, duration_ms: u64) !void {
        const cloned = try self.allocator.dupe(u8, pixels);
        try self.frames.append(self.allocator, Frame{
            .pixels = cloned,
            .width = width,
            .height = height,
            .duration_ms = duration_ms,
        });
    }

    pub fn getFrameCount(self: AnsiArtPlayer) usize {
        return self.frames.items.len;
    }

    pub fn getCurrentFrameIndex(self: AnsiArtPlayer) usize {
        return self.current_frame;
    }

    pub fn play(self: *AnsiArtPlayer) void {
        self.is_playing = true;
        self.done = false;
    }

    pub fn pause(self: *AnsiArtPlayer) void {
        self.is_playing = false;
    }

    pub fn stop(self: *AnsiArtPlayer) void {
        self.is_playing = false;
        self.current_frame = 0;
        self.elapsed_ms = 0;
    }

    pub fn update(self: *AnsiArtPlayer, delta_ms: u64) void {
        if (!self.is_playing or self.frames.items.len == 0 or self.done) {
            return;
        }

        self.elapsed_ms += delta_ms;

        while (self.elapsed_ms >= self.frames.items[self.current_frame].duration_ms) {
            self.elapsed_ms -= self.frames.items[self.current_frame].duration_ms;
            self.current_frame += 1;

            if (self.current_frame >= self.frames.items.len) {
                if (self.loop) {
                    self.current_frame = 0;
                } else {
                    self.current_frame = self.frames.items.len - 1;
                    self.done = true;
                    self.is_playing = false;
                    break;
                }
            }
        }
    }

    pub fn render(self: AnsiArtPlayer, alloc: Allocator, writer: anytype) !void {
        if (self.frames.items.len == 0) {
            return;
        }

        const frame = self.frames.items[self.current_frame];
        try AnsiArtRenderer.render(alloc, frame.pixels, frame.width, frame.height, self.options, writer);
    }

    pub fn isComplete(self: AnsiArtPlayer) bool {
        return self.done;
    }
};

// ============================================================================
// Video Frame Conversion
// ============================================================================

/// Render a single video frame. If frame_number > 0, emits cursor-up escape to
/// overwrite the previous frame in-place.
pub fn convertVideoFrame(
    allocator: Allocator,
    pixels: []const u8,
    width: u32,
    height: u32,
    options: AnsiArtRenderer.RenderOptions,
    frame_number: u32,
    writer: anytype,
) !void {
    if (width == 0 or height == 0) {
        return error.InvalidDimensions;
    }

    if (frame_number > 0) {
        // Calculate output height based on algorithm
        const out_h: u32 = switch (options.algorithm) {
            .block => (height + 1) / 2,
            .braille => (height + 3) / 4,
            .ascii => options.output_height orelse height,
        };

        // Emit cursor-up escape: ESC[nA
        try writer.print("\x1b[{}A", .{out_h});
    }

    try AnsiArtRenderer.render(allocator, pixels, width, height, options, writer);
}
