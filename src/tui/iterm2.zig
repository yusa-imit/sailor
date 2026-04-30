//! iTerm2 inline images protocol support (OSC 1337).
//!
//! The iTerm2 inline images protocol allows rendering images directly in the terminal using
//! OSC 1337 escape sequences. This protocol is supported by iTerm2, WezTerm, and Hyper.
//!
//! Protocol format: `\x1b]1337;File=[args]:base64data\x07`
//!
//! Supported features:
//! - PNG, JPEG, GIF, BMP image formats
//! - Width/height specification (pixels, percent, cells)
//! - Preserve aspect ratio option
//! - Inline positioning (cursor moves to end of image)
//! - Base64-encoded image data
//!
//! Reference: https://iterm2.com/documentation-images.html
//!
//! ## Usage Example
//!
//! ```zig
//! const iterm2 = @import("iterm2.zig");
//!
//! // Load PNG file data
//! const png_data = try std.fs.cwd().readFileAlloc(allocator, "image.png", 10 * 1024 * 1024);
//! defer allocator.free(png_data);
//!
//! // Create image with options
//! var img = iterm2.ITerm2Image{
//!     .data = png_data,
//!     .name = "image.png",
//!     .width = .{ .cells = 40 },
//!     .height = .auto,
//!     .preserve_aspect_ratio = true,
//! };
//!
//! // Encode and write to terminal
//! var encoder = iterm2.ITerm2Encoder.init(allocator);
//! defer encoder.deinit();
//! try encoder.encode(img, writer);
//! ```

const std = @import("std");
const Allocator = std.mem.Allocator;

/// Size specification for image dimensions
pub const SizeSpec = union(enum) {
    /// Automatic sizing (preserve aspect ratio based on other dimension)
    auto,
    /// Size in pixels
    pixels: u32,
    /// Size in terminal cells (character columns/rows)
    cells: u32,
    /// Size as percentage of terminal width/height (1-100)
    percent: u8,

    /// Write size spec as iTerm2 parameter value to writer
    pub fn write(self: SizeSpec, writer: anytype) !void {
        switch (self) {
            .auto => {}, // No output for auto
            .pixels => |px| try writer.print("{}px", .{px}),
            .cells => |c| try writer.print("{}", .{c}),
            .percent => |p| try writer.print("{}%", .{p}),
        }
    }
};

/// iTerm2 inline image structure
pub const ITerm2Image = struct {
    /// Image file data (PNG, JPEG, GIF, or BMP)
    data: []const u8,
    /// Optional filename (helps terminal identify format)
    name: ?[]const u8 = null,
    /// Image width specification (auto, pixels, cells, or percent)
    width: SizeSpec = .auto,
    /// Image height specification (auto, pixels, cells, or percent)
    height: SizeSpec = .auto,
    /// Preserve aspect ratio when resizing
    preserve_aspect_ratio: bool = true,
    /// Inline display (true) or block display (false)
    is_inline: bool = true,

    /// Validate image data is non-empty
    pub fn validate(self: ITerm2Image) !void {
        if (self.data.len == 0) {
            return error.EmptyImageData;
        }
        // Validate percent values
        if (self.width == .percent and (self.width.percent == 0 or self.width.percent > 100)) {
            return error.InvalidPercentage;
        }
        if (self.height == .percent and (self.height.percent == 0 or self.height.percent > 100)) {
            return error.InvalidPercentage;
        }
    }
};

/// iTerm2 inline images encoder
pub const ITerm2Encoder = struct {
    allocator: Allocator,

    /// Initialize iTerm2 encoder with allocator.
    pub fn init(allocator: Allocator) ITerm2Encoder {
        return .{ .allocator = allocator };
    }

    /// Free resources (currently a no-op).
    pub fn deinit(_: *ITerm2Encoder) void {
        // No state to clean up currently
    }

    /// Encode image to iTerm2 inline images protocol and write to output.
    ///
    /// Protocol format: ESC ] 1337 ; File = [args] : base64data BEL
    pub fn encode(
        self: *ITerm2Encoder,
        image: ITerm2Image,
        writer: anytype,
    ) !void {
        try image.validate();

        // Encode image data to base64
        const encoder = std.base64.standard.Encoder;
        const encoded_len = encoder.calcSize(image.data.len);
        const encoded_data = try self.allocator.alloc(u8, encoded_len);
        defer self.allocator.free(encoded_data);

        _ = encoder.encode(encoded_data, image.data);

        // Write OSC 1337 sequence: ESC ] 1337 ; File = [args] : base64data BEL
        try writer.writeAll("\x1b]1337;File=");

        // Write file arguments
        var has_arg = false;

        // inline parameter (default is 1, only write if false)
        if (!image.is_inline) {
            try writer.writeAll("inline=0");
            has_arg = true;
        } else {
            try writer.writeAll("inline=1");
            has_arg = true;
        }

        // name parameter (base64-encoded)
        if (image.name) |name| {
            if (has_arg) try writer.writeAll(";");
            const name_encoder = std.base64.standard.Encoder;
            const name_encoded_len = name_encoder.calcSize(name.len);
            const name_encoded = try self.allocator.alloc(u8, name_encoded_len);
            defer self.allocator.free(name_encoded);
            _ = name_encoder.encode(name_encoded, name);
            try writer.print("name={s}", .{name_encoded});
            has_arg = true;
        }

        // width parameter
        if (image.width != .auto) {
            if (has_arg) try writer.writeAll(";");
            try writer.writeAll("width=");
            try image.width.write(writer);
            has_arg = true;
        }

        // height parameter
        if (image.height != .auto) {
            if (has_arg) try writer.writeAll(";");
            try writer.writeAll("height=");
            try image.height.write(writer);
            has_arg = true;
        }

        // preserveAspectRatio parameter (default is 1, only write if false)
        if (!image.preserve_aspect_ratio) {
            if (has_arg) try writer.writeAll(";");
            try writer.writeAll("preserveAspectRatio=0");
            has_arg = true;
        }

        // Write base64 data after colon
        try writer.writeAll(":");
        try writer.writeAll(encoded_data);

        // Terminate with BEL (0x07)
        try writer.writeAll("\x07");
    }
};

// ============================================================================
// Tests
// ============================================================================

const testing = std.testing;

test "ITerm2Image validate - empty data" {
    const img = ITerm2Image{ .data = &[_]u8{} };
    try testing.expectError(error.EmptyImageData, img.validate());
}

test "ITerm2Image validate - invalid percent (0%)" {
    const img = ITerm2Image{
        .data = &[_]u8{0x89, 0x50, 0x4e, 0x47}, // PNG header
        .width = .{ .percent = 0 },
    };
    try testing.expectError(error.InvalidPercentage, img.validate());
}

test "ITerm2Image validate - invalid percent (101%)" {
    const img = ITerm2Image{
        .data = &[_]u8{0x89, 0x50, 0x4e, 0x47}, // PNG header
        .width = .{ .percent = 101 },
    };
    try testing.expectError(error.InvalidPercentage, img.validate());
}

test "ITerm2Image validate - valid image" {
    const img = ITerm2Image{
        .data = &[_]u8{0x89, 0x50, 0x4e, 0x47}, // PNG header
        .width = .{ .cells = 40 },
        .height = .{ .percent = 50 },
    };
    try img.validate();
}

test "SizeSpec write - auto" {
    var buf: [32]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);
    const spec: SizeSpec = .auto;
    try spec.write(fbs.writer());
    try testing.expectEqualStrings("", fbs.getWritten());
}

test "SizeSpec write - pixels" {
    var buf: [32]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);
    const spec: SizeSpec = .{ .pixels = 800 };
    try spec.write(fbs.writer());
    try testing.expectEqualStrings("800px", fbs.getWritten());
}

test "SizeSpec write - cells" {
    var buf: [32]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);
    const spec: SizeSpec = .{ .cells = 40 };
    try spec.write(fbs.writer());
    try testing.expectEqualStrings("40", fbs.getWritten());
}

test "SizeSpec write - percent" {
    var buf: [32]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);
    const spec: SizeSpec = .{ .percent = 75 };
    try spec.write(fbs.writer());
    try testing.expectEqualStrings("75%", fbs.getWritten());
}

test "ITerm2Encoder encode - minimal image" {
    var buf: [1024]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);
    const writer = fbs.writer();

    const png_header = [_]u8{ 0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a };
    const img = ITerm2Image{
        .data = &png_header,
    };

    var encoder = ITerm2Encoder.init(testing.allocator);
    defer encoder.deinit();
    try encoder.encode(img, writer);

    const output = fbs.getWritten();

    // Check OSC 1337 prefix
    try testing.expect(std.mem.startsWith(u8, output, "\x1b]1337;File="));

    // Check inline=1 parameter
    try testing.expect(std.mem.indexOf(u8, output, "inline=1") != null);

    // Check BEL terminator
    try testing.expect(std.mem.endsWith(u8, output, "\x07"));

    // Check base64 data is present after colon
    try testing.expect(std.mem.indexOf(u8, output, ":") != null);
}

test "ITerm2Encoder encode - with all parameters" {
    var buf: [2048]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);
    const writer = fbs.writer();

    const png_header = [_]u8{ 0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a };
    const img = ITerm2Image{
        .data = &png_header,
        .name = "test.png",
        .width = .{ .cells = 40 },
        .height = .{ .percent = 50 },
        .preserve_aspect_ratio = false,
        .is_inline = false,
    };

    var encoder = ITerm2Encoder.init(testing.allocator);
    defer encoder.deinit();
    try encoder.encode(img, writer);

    const output = fbs.getWritten();

    // Check all parameters are present
    try testing.expect(std.mem.indexOf(u8, output, "inline=0") != null);
    try testing.expect(std.mem.indexOf(u8, output, "width=40") != null);
    try testing.expect(std.mem.indexOf(u8, output, "height=50%") != null);
    try testing.expect(std.mem.indexOf(u8, output, "preserveAspectRatio=0") != null);
    try testing.expect(std.mem.indexOf(u8, output, "name=") != null);
}

test "ITerm2Encoder encode - width pixels" {
    var buf: [1024]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);
    const writer = fbs.writer();

    const png_header = [_]u8{ 0x89, 0x50, 0x4e, 0x47 };
    const img = ITerm2Image{
        .data = &png_header,
        .width = .{ .pixels = 800 },
    };

    var encoder = ITerm2Encoder.init(testing.allocator);
    defer encoder.deinit();
    try encoder.encode(img, writer);

    const output = fbs.getWritten();
    try testing.expect(std.mem.indexOf(u8, output, "width=800px") != null);
}

test "ITerm2Encoder encode - auto dimensions" {
    var buf: [1024]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);
    const writer = fbs.writer();

    const png_header = [_]u8{ 0x89, 0x50, 0x4e, 0x47 };
    const img = ITerm2Image{
        .data = &png_header,
        .width = .auto,
        .height = .auto,
    };

    var encoder = ITerm2Encoder.init(testing.allocator);
    defer encoder.deinit();
    try encoder.encode(img, writer);

    const output = fbs.getWritten();

    // Auto dimensions should not output width/height parameters
    try testing.expect(std.mem.indexOf(u8, output, "width=") == null);
    try testing.expect(std.mem.indexOf(u8, output, "height=") == null);
}

test "ITerm2Encoder init and deinit" {
    var encoder = ITerm2Encoder.init(testing.allocator);
    encoder.deinit();
}
