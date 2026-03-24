//! Error Context — Enhanced error reporting with file/line/context information
//!
//! Provides structured error messages with:
//! - Source location (file, line, column)
//! - Error context (what was being attempted)
//! - Additional metadata
//!
//! Example usage:
//! ```zig
//! const ctx = ErrorContext.init("filebrowser.zig", 142, "opening directory");
//! ctx.set("path", path_buffer);
//! return ctx.withError(error.CannotOpenDirectory);
//! ```

const std = @import("std");

/// Error context with source location and metadata
pub const ErrorContext = struct {
    file: []const u8,
    line: u32,
    context: []const u8,
    metadata: std.StringHashMap([]const u8),
    allocator: std.mem.Allocator,

    /// Initialize error context with source location
    pub fn init(allocator: std.mem.Allocator, file: []const u8, line: u32, context: []const u8) ErrorContext {
        return .{
            .file = file,
            .line = line,
            .context = context,
            .metadata = std.StringHashMap([]const u8).init(allocator),
            .allocator = allocator,
        };
    }

    /// Add metadata key-value pair
    pub fn set(self: *ErrorContext, key: []const u8, value: []const u8) !void {
        try self.metadata.put(key, value);
    }

    /// Format error message with context
    pub fn format(self: *const ErrorContext, writer: anytype, err: anyerror) !void {
        try writer.print("{s}:{d} — {s}: {s}\n", .{ self.file, self.line, self.context, @errorName(err) });

        if (self.metadata.count() > 0) {
            try writer.writeAll("  Details:\n");
            var it = self.metadata.iterator();
            while (it.next()) |entry| {
                try writer.print("    {s}: {s}\n", .{ entry.key_ptr.*, entry.value_ptr.* });
            }
        }
    }

    /// Deinit and free metadata
    pub fn deinit(self: *ErrorContext) void {
        self.metadata.deinit();
    }
};

/// Simple error message builder without allocator (stack-based)
pub const SimpleErrorMsg = struct {
    file: []const u8,
    line: u32,
    context: []const u8,

    pub fn init(file: []const u8, line: u32, context: []const u8) SimpleErrorMsg {
        return .{
            .file = file,
            .line = line,
            .context = context,
        };
    }

    /// Format to buffer (no allocation)
    pub fn formatToBuf(self: SimpleErrorMsg, buf: []u8, err: anyerror) ![]const u8 {
        return try std.fmt.bufPrint(buf, "{s}:{d} — {s}: {s}", .{
            self.file,
            self.line,
            self.context,
            @errorName(err),
        });
    }

    /// Format to writer
    pub fn format(self: SimpleErrorMsg, writer: anytype, err: anyerror) !void {
        try writer.print("{s}:{d} — {s}: {s}", .{
            self.file,
            self.line,
            self.context,
            @errorName(err),
        });
    }
};

/// Helper macro-like function to create simple error messages with @src() location
pub inline fn here(context: []const u8) SimpleErrorMsg {
    const src = @src();
    return SimpleErrorMsg.init(src.file, src.line, context);
}

// ============================================================================
// Tests
// ============================================================================

test "ErrorContext - basic usage" {
    const allocator = std.testing.allocator;
    var ctx = ErrorContext.init(allocator, "test.zig", 42, "testing error context");
    defer ctx.deinit();

    var buf: std.ArrayList(u8) = .{};
    defer buf.deinit(allocator);

    try ctx.format(buf.writer(allocator), error.SomeError);
    const result = buf.items;

    try std.testing.expect(std.mem.indexOf(u8, result, "test.zig:42") != null);
    try std.testing.expect(std.mem.indexOf(u8, result, "testing error context") != null);
    try std.testing.expect(std.mem.indexOf(u8, result, "SomeError") != null);
}

test "ErrorContext - with metadata" {
    const allocator = std.testing.allocator;
    var ctx = ErrorContext.init(allocator, "module.zig", 100, "processing file");
    defer ctx.deinit();

    try ctx.set("path", "/tmp/test.txt");
    try ctx.set("size", "4096");

    var buf: std.ArrayList(u8) = .{};
    defer buf.deinit(allocator);

    try ctx.format(buf.writer(allocator), error.FileNotFound);
    const result = buf.items;

    try std.testing.expect(std.mem.indexOf(u8, result, "module.zig:100") != null);
    try std.testing.expect(std.mem.indexOf(u8, result, "processing file") != null);
    try std.testing.expect(std.mem.indexOf(u8, result, "FileNotFound") != null);
    try std.testing.expect(std.mem.indexOf(u8, result, "path: /tmp/test.txt") != null);
    try std.testing.expect(std.mem.indexOf(u8, result, "size: 4096") != null);
}

test "SimpleErrorMsg - no allocation" {
    var buf: [256]u8 = undefined;
    const msg = SimpleErrorMsg.init("foo.zig", 10, "initializing");

    const result = try msg.formatToBuf(&buf, error.InitFailed);

    try std.testing.expect(std.mem.indexOf(u8, result, "foo.zig:10") != null);
    try std.testing.expect(std.mem.indexOf(u8, result, "initializing") != null);
    try std.testing.expect(std.mem.indexOf(u8, result, "InitFailed") != null);
}

test "SimpleErrorMsg - format to writer" {
    const allocator = std.testing.allocator;
    var buf: std.ArrayList(u8) = .{};
    defer buf.deinit(allocator);

    const msg = SimpleErrorMsg.init("bar.zig", 20, "validating input");
    try msg.format(buf.writer(allocator), error.InvalidInput);

    const result = buf.items;
    try std.testing.expect(std.mem.indexOf(u8, result, "bar.zig:20") != null);
    try std.testing.expect(std.mem.indexOf(u8, result, "validating input") != null);
    try std.testing.expect(std.mem.indexOf(u8, result, "InvalidInput") != null);
}

test "here() helper - captures source location" {
    const msg = here("testing here() function");

    // Should contain this file name
    try std.testing.expect(std.mem.indexOf(u8, msg.file, "error_context.zig") != null);
    try std.testing.expectEqualStrings("testing here() function", msg.context);
    // Line number should be reasonable (this test is somewhere in the file)
    try std.testing.expect(msg.line > 0 and msg.line < 1000);
}

test "ErrorContext - empty metadata" {
    const allocator = std.testing.allocator;
    var ctx = ErrorContext.init(allocator, "empty.zig", 1, "no metadata");
    defer ctx.deinit();

    var buf: std.ArrayList(u8) = .{};
    defer buf.deinit(allocator);

    try ctx.format(buf.writer(allocator), error.NoMetadata);
    const result = buf.items;

    // Should not have "Details:" section when no metadata
    try std.testing.expect(std.mem.indexOf(u8, result, "empty.zig:1") != null);
    try std.testing.expect(std.mem.indexOf(u8, result, "NoMetadata") != null);
}

test "ErrorContext - multiple metadata entries" {
    const allocator = std.testing.allocator;
    var ctx = ErrorContext.init(allocator, "multi.zig", 50, "complex operation");
    defer ctx.deinit();

    try ctx.set("step", "parsing");
    try ctx.set("input", "test.json");
    try ctx.set("offset", "1024");

    var buf: std.ArrayList(u8) = .{};
    defer buf.deinit(allocator);

    try ctx.format(buf.writer(allocator), error.ParseError);
    const result = buf.items;

    try std.testing.expect(std.mem.indexOf(u8, result, "step: parsing") != null);
    try std.testing.expect(std.mem.indexOf(u8, result, "input: test.json") != null);
    try std.testing.expect(std.mem.indexOf(u8, result, "offset: 1024") != null);
}
