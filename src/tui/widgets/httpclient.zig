//! HTTP client widget visualizing request state and download progress.
const std = @import("std");
const Allocator = std.mem.Allocator;
const Rect = @import("../layout.zig").Rect;
const Buffer = @import("../buffer.zig").Buffer;
const Style = @import("../style.zig").Style;
const Color = @import("../style.zig").Color;
const Block = @import("block.zig").Block;
const Gauge = @import("gauge.zig").Gauge;
const UnicodeWidth = @import("../../unicode.zig").UnicodeWidth;

/// HTTP request state
pub const RequestState = enum {
    idle,
    connecting,
    sending,
    receiving,
    completed,
    failed,
};

/// Download progress information
pub const DownloadProgress = struct {
    bytes_downloaded: u64,
    total_bytes: ?u64, // null if Content-Length not available
    speed_bps: u64, // bytes per second
    elapsed_ms: u64,
};

/// HTTP client widget with download progress visualization
pub const HttpClient = struct {
    /// URL being fetched
    url: []const u8,
    /// Current request state
    state: RequestState,
    /// Download progress (only valid when state is receiving/completed)
    progress: DownloadProgress,
    /// Error message (only valid when state is failed)
    error_msg: ?[]const u8,
    /// Block widget for border and title
    block: ?Block,
    /// Show detailed stats
    show_details: bool,
    /// Response preview (first N bytes)
    response_preview: ?[]const u8,
    /// Maximum preview length
    max_preview_len: usize,

    /// Create a new HTTP client widget
    pub fn init(url: []const u8) HttpClient {
        return .{
            .url = url,
            .state = .idle,
            .progress = .{
                .bytes_downloaded = 0,
                .total_bytes = null,
                .speed_bps = 0,
                .elapsed_ms = 0,
            },
            .error_msg = null,
            .block = null,
            .show_details = true,
            .response_preview = null,
            .max_preview_len = 256,
        };
    }

    /// Set block border/title
    pub fn setBlock(self: *HttpClient, block: Block) void {
        self.block = block;
    }

    /// Update progress (called by external HTTP client code)
    pub fn updateProgress(
        self: *HttpClient,
        bytes_downloaded: u64,
        total_bytes: ?u64,
        elapsed_ms: u64,
    ) void {
        self.state = .receiving;
        self.progress.bytes_downloaded = bytes_downloaded;
        self.progress.total_bytes = total_bytes;
        self.progress.elapsed_ms = elapsed_ms;

        // Calculate speed (bytes per second)
        if (elapsed_ms > 0) {
            const scaled = @as(u128, bytes_downloaded) * 1000;
            const speed = @divFloor(scaled, elapsed_ms);
            self.progress.speed_bps = @intCast(@min(speed, std.math.maxInt(u64)));
        }
    }

    /// Mark request as completed
    pub fn complete(self: *HttpClient, response_data: ?[]const u8) void {
        self.state = .completed;
        if (response_data) |data| {
            const len = @min(data.len, self.max_preview_len);
            self.response_preview = data[0..len];
        }
    }

    /// Mark request as failed with error message
    pub fn fail(self: *HttpClient, error_msg: []const u8) void {
        self.state = .failed;
        self.error_msg = error_msg;
    }

    /// Render the widget. Content is clipped to `area` (and to the buffer).
    pub fn render(self: HttpClient, buf: *Buffer, area: Rect) void {
        var inner = area;
        if (self.block) |block| {
            block.render(buf, area);
            inner = block.inner(area);
        }
        if (inner.width < 3 or inner.height < 1) return;

        var row: u16 = 0;
        self.renderUrl(buf, inner, &row);
        self.renderState(buf, inner, &row);
        const active = self.state == .receiving or self.state == .completed;
        if (active) self.renderProgress(buf, inner, &row);
        if (active and self.show_details) self.renderStats(buf, inner, &row);
        if (self.state == .failed) self.renderError(buf, inner, &row);
        if (self.state == .completed) self.renderPreview(buf, inner, &row);
    }

    fn renderUrl(self: HttpClient, buf: *Buffer, inner: Rect, row: *u16) void {
        std.debug.assert(row.* < inner.height);
        std.debug.assert(inner.width >= 3);
        const label = "URL: ";
        const y = inner.y +| row.*;
        buf.setString(inner.x, y, label, .{});
        const label_width: u16 = label.len;
        const x = inner.x +| label_width;
        buf.setString(x, y, fitPrefix(self.url, inner.width -| label_width), .{});
        row.* += 1;
    }

    fn renderState(self: HttpClient, buf: *Buffer, inner: Rect, row: *u16) void {
        std.debug.assert(row.* >= 1);
        std.debug.assert(inner.width >= 3);
        if (row.* >= inner.height) return;
        const state_str = switch (self.state) {
            .idle => "State: Idle",
            .connecting => "State: Connecting...",
            .sending => "State: Sending request...",
            .receiving => "State: Receiving data...",
            .completed => "State: Completed ✓",
            .failed => "State: Failed ✗",
        };
        const state_color: Color = switch (self.state) {
            .completed => .green,
            .failed => .red,
            else => .yellow,
        };
        const text = fitPrefix(state_str, inner.width);
        buf.setString(inner.x, inner.y +| row.*, text, .{ .fg = state_color });
        row.* += 1;
    }

    fn renderProgress(self: HttpClient, buf: *Buffer, inner: Rect, row: *u16) void {
        std.debug.assert(row.* >= 2);
        std.debug.assert(inner.width >= 3);
        if (row.* >= inner.height) return;
        defer row.* += 1;

        // Gauge does not clip its extent to the buffer, so hand it only visible columns.
        const visible = @min(inner.width, buf.width -| inner.x);
        if (visible == 0) return;
        const bar = Rect{ .x = inner.x, .y = inner.y +| row.*, .width = visible, .height = 1 };
        const done = self.percentDone();
        var label_buf: [8]u8 = undefined;
        const label = std.fmt.bufPrint(&label_buf, "{d}%", .{done}) catch unreachable; // <= 4 bytes
        const gauge = (Gauge{}).withPercent(done).withLabel(label);
        gauge.render(buf, bar);
    }

    /// Whole-number completion percentage; 0 when the total is unknown or zero.
    fn percentDone(self: HttpClient) u8 {
        const total = self.progress.total_bytes orelse return 0;
        if (total == 0) return 0;
        const done: u128 = self.progress.bytes_downloaded;
        const scaled = @divFloor(done * 100, total);
        return @intCast(@min(scaled, 100));
    }

    fn renderStats(self: HttpClient, buf: *Buffer, inner: Rect, row: *u16) void {
        std.debug.assert(row.* >= 3);
        std.debug.assert(inner.width >= 3);
        if (row.* >= inner.height) return;
        var done_buf: [byte_str_max]u8 = undefined;
        var total_buf: [byte_str_max]u8 = undefined;
        var speed_buf: [byte_str_max]u8 = undefined;
        const done_str = formatBytes(&done_buf, self.progress.bytes_downloaded);
        const total_str = if (self.progress.total_bytes) |total|
            formatBytes(&total_buf, total)
        else
            "unknown";
        const speed_str = formatBytes(&speed_buf, self.progress.speed_bps);
        var line_buf: [3 * byte_str_max + 32]u8 = undefined;
        const line = std.fmt.bufPrint(
            &line_buf,
            "Downloaded: {s} / {s} ({s}/s)",
            .{ done_str, total_str, speed_str },
        ) catch unreachable; // line_buf fits three byte strings plus fixed text
        buf.setString(inner.x, inner.y +| row.*, fitPrefix(line, inner.width), .{});
        row.* += 1;
    }

    fn renderError(self: HttpClient, buf: *Buffer, inner: Rect, row: *u16) void {
        std.debug.assert(row.* >= 2);
        std.debug.assert(inner.width >= 3);
        const message = self.error_msg orelse return;
        if (row.* >= inner.height) return;
        const label = "Error: ";
        const y = inner.y +| row.*;
        buf.setString(inner.x, y, fitPrefix(label, inner.width), .{ .fg = .red });
        const label_width: u16 = label.len;
        const x = inner.x +| label_width;
        buf.setString(x, y, fitPrefix(message, inner.width -| label_width), .{});
        row.* += 1;
    }

    fn renderPreview(self: HttpClient, buf: *Buffer, inner: Rect, row: *u16) void {
        std.debug.assert(row.* >= 2);
        std.debug.assert(inner.width >= 3);
        const preview = self.response_preview orelse return;
        if (row.* >= inner.height) return;
        buf.setString(inner.x, inner.y +| row.*, "Response:", .{});
        row.* += 1;

        var rest = preview;
        while (rest.len > 0 and row.* < inner.height) {
            const line_end = std.mem.findScalar(u8, rest, '\n') orelse rest.len;
            buf.setString(inner.x, inner.y +| row.*, fitPrefix(rest[0..line_end], inner.width), .{});
            row.* += 1;
            rest = rest[@min(line_end + 1, rest.len)..];
        }
    }

    /// Longest prefix of `text` (cut on a codepoint boundary) fitting in `width_max` cells.
    fn fitPrefix(text: []const u8, width_max: u16) []const u8 {
        std.debug.assert(text.len <= std.math.maxInt(u32));
        std.debug.assert(width_max <= std.math.maxInt(u16));
        var cells: u32 = 0;
        var i: usize = 0;
        while (i < text.len) {
            const len = std.unicode.utf8ByteSequenceLength(text[i]) catch 1;
            if (i + len > text.len) break;
            const cp = std.unicode.utf8Decode(text[i .. i + len]) catch @as(u21, text[i]);
            const w = UnicodeWidth.charWidth(cp);
            if (cells + w > width_max) break;
            cells += w;
            i += len;
        }
        return text[0..i];
    }

    /// Longest `formatBytes` output, e.g. "17179869184.00 GB" is 17 bytes.
    const byte_str_max = 24;

    /// Format bytes as a human-readable string into `out` (>= `byte_str_max` bytes).
    fn formatBytes(out: []u8, bytes: u64) []const u8 {
        std.debug.assert(out.len >= byte_str_max);
        const units = [_]struct { size: u64, name: []const u8 }{
            .{ .size = 1 << 30, .name = "GB" },
            .{ .size = 1 << 20, .name = "MB" },
            .{ .size = 1 << 10, .name = "KB" },
        };
        for (units) |unit| {
            if (bytes < unit.size) continue;
            const value = @as(f64, @floatFromInt(bytes)) / @as(f64, @floatFromInt(unit.size));
            return std.fmt.bufPrint(out, "{d:.2} {s}", .{ value, unit.name }) catch unreachable; // <= 24 bytes
        }
        return std.fmt.bufPrint(out, "{d} B", .{bytes}) catch unreachable; // u64 fits in 24 bytes
    }
};

// ============================================================================
// Tests
// ============================================================================

test "HttpClient - init" {
    const client = HttpClient.init("https://example.com");
    try std.testing.expectEqualStrings("https://example.com", client.url);
    try std.testing.expectEqual(RequestState.idle, client.state);
    try std.testing.expectEqual(@as(u64, 0), client.progress.bytes_downloaded);
}

test "HttpClient - updateProgress" {
    var client = HttpClient.init("https://example.com");

    client.updateProgress(1024, 2048, 1000);
    try std.testing.expectEqual(RequestState.receiving, client.state);
    try std.testing.expectEqual(@as(u64, 1024), client.progress.bytes_downloaded);
    try std.testing.expectEqual(@as(?u64, 2048), client.progress.total_bytes);
    try std.testing.expectEqual(@as(u64, 1024), client.progress.speed_bps); // 1024 bytes/sec
}

test "HttpClient - complete" {
    var client = HttpClient.init("https://example.com");
    const response = "Hello, World!";

    client.complete(response);
    try std.testing.expectEqual(RequestState.completed, client.state);
    try std.testing.expect(client.response_preview != null);
    try std.testing.expectEqualStrings(response, client.response_preview.?);
}

test "HttpClient - fail" {
    var client = HttpClient.init("https://example.com");
    const error_msg = "Connection refused";

    client.fail(error_msg);
    try std.testing.expectEqual(RequestState.failed, client.state);
    try std.testing.expect(client.error_msg != null);
    try std.testing.expectEqualStrings(error_msg, client.error_msg.?);
}

test "HttpClient - progress calculation" {
    var client = HttpClient.init("https://example.com");

    // Download 5 KB in 2 seconds = 2.5 KB/s
    client.updateProgress(5120, 10240, 2000);
    try std.testing.expectEqual(@as(u64, 2560), client.progress.speed_bps);
}

fn expectRow(buf: Buffer, y: u16, expected: []const u8) !void {
    const line = buf.getLine(y, 0, buf.width);
    defer buf.allocator.free(line);

    try std.testing.expectEqualStrings(expected, std.mem.trimEnd(u8, line, " "));
}

test "HttpClient - render idle state" {
    var buffer = try Buffer.init(std.testing.allocator, 40, 10);
    defer buffer.deinit();

    const client = HttpClient.init("https://example.com");
    client.render(&buffer, .{ .x = 0, .y = 0, .width = 40, .height = 10 });

    try expectRow(buffer, 0, "URL: https://example.com");
    try expectRow(buffer, 1, "State: Idle");
    try expectRow(buffer, 2, "");
    try std.testing.expectEqual(@as(?Color, .yellow), buffer.getStyle(0, 1).fg);
    try std.testing.expectEqual(@as(?Color, null), buffer.getStyle(0, 0).fg);
}

test "HttpClient - render receiving state" {
    var buffer = try Buffer.init(std.testing.allocator, 40, 10);
    defer buffer.deinit();

    var client = HttpClient.init("https://example.com");
    client.updateProgress(1024, 2048, 1000);
    client.render(&buffer, .{ .x = 0, .y = 0, .width = 40, .height = 10 });

    try expectRow(buffer, 1, "State: Receiving data...");
    // 50% of 40 cells filled, label centred over the bar.
    try std.testing.expectEqual(@as(u21, '█'), buffer.getChar(0, 2));
    try std.testing.expectEqual(@as(u21, '█'), buffer.getChar(17, 2));
    try std.testing.expectEqual(@as(u21, '5'), buffer.getChar(18, 2));
    try std.testing.expectEqual(@as(u21, '0'), buffer.getChar(19, 2));
    try std.testing.expectEqual(@as(u21, '%'), buffer.getChar(20, 2));
    try std.testing.expectEqual(@as(u21, ' '), buffer.getChar(21, 2));
    try std.testing.expectEqual(@as(u21, ' '), buffer.getChar(39, 2));
    try expectRow(buffer, 3, "Downloaded: 1.00 KB / 2.00 KB (1.00 KB/s");
}

test "HttpClient - render completed state" {
    var buffer = try Buffer.init(std.testing.allocator, 40, 10);
    defer buffer.deinit();

    var client = HttpClient.init("https://example.com");
    client.updateProgress(2048, 2048, 2000);
    client.complete("Response data here\nsecond line");
    client.render(&buffer, .{ .x = 0, .y = 0, .width = 40, .height = 10 });

    try expectRow(buffer, 1, "State: Completed ✓");
    try std.testing.expectEqual(@as(?Color, .green), buffer.getStyle(0, 1).fg);
    try std.testing.expectEqual(@as(u21, '█'), buffer.getChar(39, 2));
    try expectRow(buffer, 4, "Response:");
    try expectRow(buffer, 5, "Response data here");
    try expectRow(buffer, 6, "second line");
    try expectRow(buffer, 7, "");
}

test "HttpClient - render failed state" {
    var buffer = try Buffer.init(std.testing.allocator, 40, 10);
    defer buffer.deinit();

    var client = HttpClient.init("https://example.com");
    client.fail("Connection timeout");
    client.render(&buffer, .{ .x = 0, .y = 0, .width = 40, .height = 10 });

    try expectRow(buffer, 1, "State: Failed ✗");
    try std.testing.expectEqual(@as(?Color, .red), buffer.getStyle(0, 1).fg);
    try expectRow(buffer, 2, "Error: Connection timeout");
    try std.testing.expectEqual(@as(?Color, .red), buffer.getStyle(0, 2).fg);
    try std.testing.expectEqual(@as(?Color, null), buffer.getStyle(7, 2).fg);
}

test "HttpClient - render with block insets content" {
    var buffer = try Buffer.init(std.testing.allocator, 30, 6);
    defer buffer.deinit();

    var client = HttpClient.init("a.io");
    client.setBlock(Block{});
    client.render(&buffer, .{ .x = 0, .y = 0, .width = 30, .height = 6 });

    try std.testing.expectEqual(@as(u21, '┌'), buffer.getChar(0, 0));
    try expectRow(buffer, 1, "│URL: a.io" ++ " " ** 19 ++ "│");
    try expectRow(buffer, 2, "│State: Idle" ++ " " ** 17 ++ "│");
}

test "HttpClient - render clips to a narrow area, not the buffer" {
    var buffer = try Buffer.init(std.testing.allocator, 40, 4);
    defer buffer.deinit();

    const client = HttpClient.init("https://example.com");
    client.render(&buffer, .{ .x = 2, .y = 1, .width = 12, .height = 2 });

    try expectRow(buffer, 0, "");
    try expectRow(buffer, 1, "  URL: https:/");
    try expectRow(buffer, 2, "  State: Idle");
    try std.testing.expectEqual(@as(u21, ' '), buffer.getChar(14, 1));
}

test "HttpClient - render multibyte url is clipped by cells" {
    var buffer = try Buffer.init(std.testing.allocator, 20, 2);
    defer buffer.deinit();

    // Four 2-byte narrow codepoints, then two 3-byte wide codepoints (2 cells each).
    const client = HttpClient.init("éééé漢字");
    client.render(&buffer, .{ .x = 0, .y = 0, .width = 11, .height = 2 });
    // 6 cells for the url: four narrow + one wide; the second wide would need 8.
    try expectRow(buffer, 0, "URL: éééé漢");

    buffer.clear();
    client.render(&buffer, .{ .x = 0, .y = 0, .width = 10, .height = 2 });
    // 5 cells: the wide codepoint no longer fits and is dropped whole, never split.
    try expectRow(buffer, 0, "URL: éééé");
}

test "HttpClient - render tiny and degenerate areas draw nothing" {
    var buffer = try Buffer.init(std.testing.allocator, 10, 3);
    defer buffer.deinit();

    var client = HttpClient.init("x");
    client.updateProgress(1, 2, 1);
    client.render(&buffer, .{ .x = 0, .y = 0, .width = 2, .height = 3 });
    client.render(&buffer, .{ .x = 0, .y = 0, .width = 10, .height = 0 });
    client.render(&buffer, .{ .x = 20, .y = 20, .width = 10, .height = 3 });

    for (0..3) |y| try expectRow(buffer, @intCast(y), "");
}

test "HttpClient - render at the u16 edge does not overflow" {
    var buffer = try Buffer.init(std.testing.allocator, 8, 4);
    defer buffer.deinit();

    var client = HttpClient.init("https://example.com");
    client.updateProgress(5, 10, 1);
    client.complete("a\nb\nc");
    const edge: u16 = std.math.maxInt(u16);
    client.render(&buffer, .{ .x = edge - 4, .y = edge - 4, .width = edge, .height = edge });
    client.render(&buffer, .{ .x = 0, .y = 0, .width = edge, .height = edge });

    try expectRow(buffer, 0, "URL: htt");
}

test "HttpClient - render height limits rows" {
    var buffer = try Buffer.init(std.testing.allocator, 30, 8);
    defer buffer.deinit();

    var client = HttpClient.init("u");
    client.updateProgress(1, 2, 1);
    client.complete("one\ntwo\nthree\nfour");
    client.render(&buffer, .{ .x = 0, .y = 0, .width = 30, .height = 6 });

    try expectRow(buffer, 4, "Response:");
    try expectRow(buffer, 5, "one");
    try expectRow(buffer, 6, "");
}

test "HttpClient - unknown total renders 0 percent and 'unknown'" {
    var buffer = try Buffer.init(std.testing.allocator, 50, 5);
    defer buffer.deinit();

    var client = HttpClient.init("u");
    client.updateProgress(1024, null, 1000);
    client.render(&buffer, .{ .x = 0, .y = 0, .width = 50, .height = 5 });

    try std.testing.expectEqual(@as(u21, ' '), buffer.getChar(0, 2));
    try std.testing.expectEqual(@as(u21, '0'), buffer.getChar(24, 2));
    try expectRow(buffer, 3, "Downloaded: 1.00 KB / unknown (1.00 KB/s)");
}

test "HttpClient - show_details false hides stats" {
    var buffer = try Buffer.init(std.testing.allocator, 50, 5);
    defer buffer.deinit();

    var client = HttpClient.init("u");
    client.show_details = false;
    client.updateProgress(1024, 2048, 1000);
    client.render(&buffer, .{ .x = 0, .y = 0, .width = 50, .height = 5 });

    try expectRow(buffer, 3, "");
}

test "HttpClient - percent saturates and survives u64 extremes" {
    var client = HttpClient.init("u");
    const big = std.math.maxInt(u64);

    client.updateProgress(big, big, 1);
    try std.testing.expectEqual(@as(u8, 100), client.percentDone());
    try std.testing.expectEqual(@as(u64, big), client.progress.speed_bps);
    client.updateProgress(2048, 1024, 1);
    try std.testing.expectEqual(@as(u8, 100), client.percentDone());
    client.updateProgress(5, 0, 1);
    try std.testing.expectEqual(@as(u8, 0), client.percentDone());
    client.updateProgress(1, 3, 1);
    try std.testing.expectEqual(@as(u8, 33), client.percentDone());
}

test "HttpClient - control bytes in preview never reach cells" {
    var buffer = try Buffer.init(std.testing.allocator, 20, 6);
    defer buffer.deinit();

    var client = HttpClient.init("u");
    client.updateProgress(1, 1, 1);
    client.complete("a\x1b[31mb\xff\xc3");
    client.render(&buffer, .{ .x = 0, .y = 0, .width = 20, .height = 6 });

    var x: u16 = 0;
    while (x < 20) : (x += 1) {
        const ch = buffer.getChar(x, 5);
        try std.testing.expect(ch >= 0x20 and ch != 0x7f);
    }
    try std.testing.expectEqual(@as(u21, 'a'), buffer.getChar(0, 5));
    try std.testing.expectEqual(@as(u21, '['), buffer.getChar(1, 5));
}

test "HttpClient - setBlock" {
    var client = HttpClient.init("https://example.com");
    var block = (Block{});
    block.title = "Download";

    client.setBlock(block);
    try std.testing.expect(client.block != null);
    try std.testing.expectEqualStrings("Download", client.block.?.title.?);
}

test "HttpClient - preview truncation" {
    var client = HttpClient.init("https://example.com");
    client.max_preview_len = 10;

    const long_response = "This is a very long response that should be truncated";
    client.complete(long_response);

    try std.testing.expect(client.response_preview != null);
    try std.testing.expectEqual(@as(usize, 10), client.response_preview.?.len);
}

test "HttpClient - unknown total bytes" {
    var client = HttpClient.init("https://example.com");

    // Streaming response with unknown total
    client.updateProgress(1024, null, 1000);
    try std.testing.expectEqual(@as(?u64, null), client.progress.total_bytes);
    try std.testing.expectEqual(@as(u64, 1024), client.progress.speed_bps);
}

test "HttpClient - speed calculation zero elapsed" {
    var client = HttpClient.init("https://example.com");

    // Edge case: zero elapsed time
    client.updateProgress(1024, 2048, 0);
    try std.testing.expectEqual(@as(u64, 0), client.progress.speed_bps);
}

test "HttpClient - formatBytes" {
    var out: [HttpClient.byte_str_max]u8 = undefined;

    try std.testing.expectEqualStrings("0 B", HttpClient.formatBytes(&out, 0));
    try std.testing.expectEqualStrings("512 B", HttpClient.formatBytes(&out, 512));
    try std.testing.expectEqualStrings("1023 B", HttpClient.formatBytes(&out, 1023));
    try std.testing.expectEqualStrings("1.00 KB", HttpClient.formatBytes(&out, 1024));
    try std.testing.expectEqualStrings("1.50 KB", HttpClient.formatBytes(&out, 1536));
    try std.testing.expectEqualStrings("2.00 MB", HttpClient.formatBytes(&out, 2 << 20));
    try std.testing.expectEqualStrings("3.00 GB", HttpClient.formatBytes(&out, 3 << 30));
    const max = HttpClient.formatBytes(&out, std.math.maxInt(u64));
    try std.testing.expectEqualStrings("17179869184.00 GB", max);
}
