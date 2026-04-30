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

/// Terminal capability flags for iTerm2 protocol
pub const ITerm2Capability = struct {
    /// Terminal supports iTerm2 inline images
    supports_inline_images: bool = false,
    /// Terminal emulator name (if detected)
    emulator: ?[]const u8 = null,

    /// Detect iTerm2 capability from environment variables.
    /// Checks TERM_PROGRAM for iTerm2, WezTerm, Hyper.
    pub fn detect(allocator: Allocator) ITerm2Capability {
        var cap = ITerm2Capability{};

        // Check TERM_PROGRAM environment variable
        if (std.process.getEnvVarOwned(allocator, "TERM_PROGRAM")) |term_program| {
            defer allocator.free(term_program);

            if (std.mem.eql(u8, term_program, "iTerm.app")) {
                cap.supports_inline_images = true;
                cap.emulator = "iTerm2";
            } else if (std.mem.eql(u8, term_program, "WezTerm")) {
                cap.supports_inline_images = true;
                cap.emulator = "WezTerm";
            } else if (std.mem.eql(u8, term_program, "Hyper")) {
                cap.supports_inline_images = true;
                cap.emulator = "Hyper";
            }
        } else |_| {
            // TERM_PROGRAM not set, assume no support
        }

        return cap;
    }
};

/// Image cache entry
const CacheEntry = struct {
    /// Base64-encoded image data
    data: []const u8,
    /// Size in bytes
    size: usize,
    /// Access timestamp (for LRU eviction)
    last_access: i64,
    /// Hash of original image data (for deduplication)
    hash: u64,
};

/// iTerm2 image cache for memory management
pub const ITerm2Cache = struct {
    allocator: Allocator,
    /// Cache entries keyed by image data hash
    entries: std.AutoHashMap(u64, CacheEntry),
    /// Current total cache size in bytes
    current_size: usize,
    /// Maximum cache size in bytes (default: 10 MB)
    max_size: usize,

    /// Initialize cache with allocator and optional max size.
    pub fn init(allocator: Allocator, max_size: ?usize) ITerm2Cache {
        return .{
            .allocator = allocator,
            .entries = std.AutoHashMap(u64, CacheEntry).init(allocator),
            .current_size = 0,
            .max_size = max_size orelse 10 * 1024 * 1024, // 10 MB default
        };
    }

    /// Free all cache resources.
    pub fn deinit(self: *ITerm2Cache) void {
        var it = self.entries.iterator();
        while (it.next()) |entry| {
            self.allocator.free(entry.value_ptr.data);
        }
        self.entries.deinit();
    }

    /// Get or add image to cache. Returns base64-encoded data.
    /// Evicts LRU entries if cache is full.
    pub fn getOrAdd(self: *ITerm2Cache, image_data: []const u8) ![]const u8 {
        const hash = std.hash.Wyhash.hash(0, image_data);

        // Check if already cached
        if (self.entries.getPtr(hash)) |entry| {
            entry.last_access = std.time.timestamp();
            return entry.data;
        }

        // Encode to base64
        const encoder = std.base64.standard.Encoder;
        const encoded_len = encoder.calcSize(image_data.len);
        const encoded_data = try self.allocator.alloc(u8, encoded_len);
        errdefer self.allocator.free(encoded_data);
        _ = encoder.encode(encoded_data, image_data);

        // Evict if necessary
        while (self.current_size + encoded_len > self.max_size and self.entries.count() > 0) {
            try self.evictLRU();
        }

        // Add to cache
        try self.entries.put(hash, .{
            .data = encoded_data,
            .size = encoded_len,
            .last_access = std.time.timestamp(),
            .hash = hash,
        });
        self.current_size += encoded_len;

        return encoded_data;
    }

    /// Evict least recently used entry.
    fn evictLRU(self: *ITerm2Cache) !void {
        var oldest_hash: u64 = 0;
        var oldest_time: i64 = std.math.maxInt(i64);

        var it = self.entries.iterator();
        while (it.next()) |entry| {
            if (entry.value_ptr.last_access < oldest_time) {
                oldest_time = entry.value_ptr.last_access;
                oldest_hash = entry.key_ptr.*;
            }
        }

        if (self.entries.fetchRemove(oldest_hash)) |kv| {
            self.current_size -= kv.value.size;
            self.allocator.free(kv.value.data);
        }
    }

    /// Clear all cached entries.
    pub fn clear(self: *ITerm2Cache) void {
        var it = self.entries.iterator();
        while (it.next()) |entry| {
            self.allocator.free(entry.value_ptr.data);
        }
        self.entries.clearRetainingCapacity();
        self.current_size = 0;
    }
};

/// iTerm2 inline images encoder
pub const ITerm2Encoder = struct {
    allocator: Allocator,
    /// Optional image cache for memory management
    cache: ?*ITerm2Cache,
    /// Terminal capability detection result
    capability: ITerm2Capability,

    /// Initialize iTerm2 encoder with allocator and optional cache.
    pub fn init(allocator: Allocator, cache: ?*ITerm2Cache) ITerm2Encoder {
        return .{
            .allocator = allocator,
            .cache = cache,
            .capability = ITerm2Capability.detect(allocator),
        };
    }

    /// Free resources (currently a no-op).
    pub fn deinit(_: *ITerm2Encoder) void {
        // No state to clean up currently
    }

    /// Check if terminal supports iTerm2 inline images.
    pub fn isSupported(self: ITerm2Encoder) bool {
        return self.capability.supports_inline_images;
    }

    /// Encode image to iTerm2 inline images protocol and write to output.
    ///
    /// Protocol format: ESC ] 1337 ; File = [args] : base64data BEL
    ///
    /// Returns error.UnsupportedTerminal if terminal doesn't support iTerm2 protocol.
    pub fn encode(
        self: *ITerm2Encoder,
        image: ITerm2Image,
        writer: anytype,
    ) !void {
        // Check terminal support
        if (!self.isSupported()) {
            return error.UnsupportedTerminal;
        }

        try image.validate();

        // Get base64-encoded data (from cache or encode new)
        const encoded_data = if (self.cache) |cache|
            try cache.getOrAdd(image.data)
        else blk: {
            // No cache, encode on the fly
            const encoder = std.base64.standard.Encoder;
            const encoded_len = encoder.calcSize(image.data.len);
            const data = try self.allocator.alloc(u8, encoded_len);
            errdefer self.allocator.free(data);
            _ = encoder.encode(data, image.data);
            break :blk data;
        };

        // Free temporary data if not cached
        defer if (self.cache == null) self.allocator.free(encoded_data);

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

    var encoder = ITerm2Encoder.init(testing.allocator, null);
    defer encoder.deinit();
    // Force capability to supported for testing
    encoder.capability.supports_inline_images = true;
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

    var encoder = ITerm2Encoder.init(testing.allocator, null);
    defer encoder.deinit();
    encoder.capability.supports_inline_images = true;
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

    var encoder = ITerm2Encoder.init(testing.allocator, null);
    defer encoder.deinit();
    encoder.capability.supports_inline_images = true;
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

    var encoder = ITerm2Encoder.init(testing.allocator, null);
    defer encoder.deinit();
    encoder.capability.supports_inline_images = true;
    try encoder.encode(img, writer);

    const output = fbs.getWritten();

    // Auto dimensions should not output width/height parameters
    try testing.expect(std.mem.indexOf(u8, output, "width=") == null);
    try testing.expect(std.mem.indexOf(u8, output, "height=") == null);
}

test "ITerm2Encoder init and deinit" {
    var encoder = ITerm2Encoder.init(testing.allocator, null);
    encoder.deinit();
}

test "ITerm2Encoder unsupported terminal" {
    var buf: [1024]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);
    const writer = fbs.writer();

    const png_header = [_]u8{ 0x89, 0x50, 0x4e, 0x47 };
    const img = ITerm2Image{
        .data = &png_header,
    };

    var encoder = ITerm2Encoder.init(testing.allocator, null);
    defer encoder.deinit();
    // Force unsupported
    encoder.capability.supports_inline_images = false;

    try testing.expectError(error.UnsupportedTerminal, encoder.encode(img, writer));
}

test "ITerm2Cache init and deinit" {
    var cache = ITerm2Cache.init(testing.allocator, null);
    defer cache.deinit();
}

test "ITerm2Cache getOrAdd - single image" {
    var cache = ITerm2Cache.init(testing.allocator, null);
    defer cache.deinit();

    const png_header = [_]u8{ 0x89, 0x50, 0x4e, 0x47 };
    const encoded = try cache.getOrAdd(&png_header);

    // Should return base64-encoded data
    try testing.expect(encoded.len > 0);

    // Second call should return same data
    const encoded2 = try cache.getOrAdd(&png_header);
    try testing.expectEqualStrings(encoded, encoded2);
}

test "ITerm2Cache eviction" {
    // Small cache (100 bytes) to force eviction
    var cache = ITerm2Cache.init(testing.allocator, 100);
    defer cache.deinit();

    const img1 = [_]u8{ 0x89, 0x50, 0x4e, 0x47, 0x01, 0x02, 0x03 };
    const img2 = [_]u8{ 0x89, 0x50, 0x4e, 0x47, 0x04, 0x05, 0x06 };

    _ = try cache.getOrAdd(&img1);
    _ = try cache.getOrAdd(&img2);

    // Cache should have evicted oldest entry
    try testing.expect(cache.entries.count() <= 2);
    try testing.expect(cache.current_size <= 100);
}

test "ITerm2Cache clear" {
    var cache = ITerm2Cache.init(testing.allocator, null);
    defer cache.deinit();

    const png_header = [_]u8{ 0x89, 0x50, 0x4e, 0x47 };
    _ = try cache.getOrAdd(&png_header);

    try testing.expect(cache.entries.count() == 1);
    try testing.expect(cache.current_size > 0);

    cache.clear();

    try testing.expect(cache.entries.count() == 0);
    try testing.expect(cache.current_size == 0);
}

test "ITerm2Encoder with cache" {
    var cache = ITerm2Cache.init(testing.allocator, null);
    defer cache.deinit();

    var buf: [1024]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);
    const writer = fbs.writer();

    const png_header = [_]u8{ 0x89, 0x50, 0x4e, 0x47 };
    const img = ITerm2Image{
        .data = &png_header,
    };

    var encoder = ITerm2Encoder.init(testing.allocator, &cache);
    defer encoder.deinit();
    encoder.capability.supports_inline_images = true;
    try encoder.encode(img, writer);

    // Verify cache was used
    try testing.expect(cache.entries.count() == 1);
}
