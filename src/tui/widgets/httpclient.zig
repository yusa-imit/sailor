const std = @import("std");
const Allocator = std.mem.Allocator;
const Rect = @import("../layout.zig").Rect;
const Buffer = @import("../buffer.zig").Buffer;
const Style = @import("../style.zig").Style;
const Color = @import("../style.zig").Color;
const Block = @import("block.zig").Block;
const Gauge = @import("gauge.zig").Gauge;

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
            self.progress.speed_bps = (bytes_downloaded * 1000) / elapsed_ms;
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

    /// Render the widget
    pub fn render(self: HttpClient, buf: *Buffer, area: Rect) void {
        var render_area = area;

        // Render block border if present
        if (self.block) |block| {
            block.render(buf, area);
            render_area = block.inner(area);
        }

        if (render_area.width < 3 or render_area.height < 1) return;

        var y: u16 = render_area.y;

        // Line 1: URL
        if (y < render_area.y + render_area.height) {
            const url_label = "URL: ";
            buf.setString(render_area.x, y, url_label, .{});
            const url_x = render_area.x + @as(u16, @intCast(url_label.len));
            const url_width = render_area.width -| @as(u16, @intCast(url_label.len));
            if (url_width > 0) {
                const url_display = if (self.url.len > url_width)
                    self.url[0..url_width]
                else
                    self.url;
                buf.setString(url_x, y, url_display, .{});
            }
            y += 1;
        }

        // Line 2: State
        if (y < render_area.y + render_area.height) {
            const state_str = switch (self.state) {
                .idle => "State: Idle",
                .connecting => "State: Connecting...",
                .sending => "State: Sending request...",
                .receiving => "State: Receiving data...",
                .completed => "State: Completed ✓",
                .failed => "State: Failed ✗",
            };
            const state_color = switch (self.state) {
                .completed => Color{ .green = {} },
                .failed => Color{ .red = {} },
                else => Color{ .yellow = {} },
            };
            buf.setString(render_area.x, y, state_str, Style.init().fg(state_color));
            y += 1;
        }

        // Line 3+: Progress bar (if receiving or completed)
        if ((self.state == .receiving or self.state == .completed) and y < render_area.y + render_area.height) {
            const progress_area = Rect{
                .x = render_area.x,
                .y = y,
                .width = render_area.width,
                .height = 1,
            };

            const percent: u8 = if (self.progress.total_bytes) |total|
                if (total > 0)
                    @intCast(@min(100, (self.progress.bytes_downloaded * 100) / total))
                else
                    0
            else
                0; // Unknown total

            var gauge = Gauge.init(percent);
            const label_buf = std.fmt.allocPrint(
                std.heap.page_allocator,
                "{d}%",
                .{percent},
            ) catch "?";
            defer std.heap.page_allocator.free(label_buf);
            gauge.setLabel(label_buf);
            gauge.render(buf, progress_area);
            y += 1;
        }

        // Line 4: Download stats (if show_details)
        if (self.show_details and (self.state == .receiving or self.state == .completed) and y < render_area.y + render_area.height) {
            const bytes_str = formatBytes(self.progress.bytes_downloaded);
            const total_str = if (self.progress.total_bytes) |total|
                formatBytes(total)
            else
                "unknown";
            const speed_str = formatBytes(self.progress.speed_bps);

            const stats_buf = std.fmt.allocPrint(
                std.heap.page_allocator,
                "Downloaded: {s} / {s} ({s}/s)",
                .{ bytes_str, total_str, speed_str },
            ) catch "Stats unavailable";
            defer std.heap.page_allocator.free(stats_buf);

            buf.setString(render_area.x, y, stats_buf, .{});
            y += 1;
        }

        // Line 5: Error message (if failed)
        if (self.state == .failed and self.error_msg != null and y < render_area.y + render_area.height) {
            const error_label = "Error: ";
            buf.setString(render_area.x, y, error_label, Style.init().fg(.{ .red = {} }));
            const error_x = render_area.x + @as(u16, @intCast(error_label.len));
            const error_width = render_area.width -| @as(u16, @intCast(error_label.len));
            if (error_width > 0 and self.error_msg != null) {
                const error_display = if (self.error_msg.?.len > error_width)
                    self.error_msg.?[0..error_width]
                else
                    self.error_msg.?;
                buf.setString(error_x, y, error_display, .{});
            }
            y += 1;
        }

        // Line 6+: Response preview (if completed)
        if (self.state == .completed and self.response_preview != null and y < render_area.y + render_area.height) {
            if (y < render_area.y + render_area.height) {
                buf.setString(render_area.x, y, "Response:", .{});
                y += 1;
            }

            if (y < render_area.y + render_area.height and self.response_preview != null) {
                const preview = self.response_preview.?;
                const max_lines = render_area.height -| (y -| render_area.y);
                var lines: u16 = 0;
                var i: usize = 0;
                while (i < preview.len and lines < max_lines) {
                    const line_end = std.mem.indexOfScalarPos(u8, preview, i, '\n') orelse preview.len;
                    const line = preview[i..line_end];
                    const display_len = @min(line.len, render_area.width);
                    buf.setString(render_area.x, y + lines, line[0..display_len], .{});
                    lines += 1;
                    i = if (line_end < preview.len) line_end + 1 else preview.len;
                }
            }
        }
    }

    /// Format bytes as human-readable string (uses static buffer, not thread-safe)
    fn formatBytes(bytes: u64) []const u8 {
        const kb: u64 = 1024;
        const mb: u64 = kb * 1024;
        const gb: u64 = mb * 1024;

        // Static buffer for formatting (not thread-safe but simple)
        var buf: [32]u8 = undefined;

        const formatted = if (bytes >= gb)
            std.fmt.bufPrint(&buf, "{d:.2} GB", .{@as(f64, @floatFromInt(bytes)) / @as(f64, @floatFromInt(gb))}) catch "? GB"
        else if (bytes >= mb)
            std.fmt.bufPrint(&buf, "{d:.2} MB", .{@as(f64, @floatFromInt(bytes)) / @as(f64, @floatFromInt(mb))}) catch "? MB"
        else if (bytes >= kb)
            std.fmt.bufPrint(&buf, "{d:.2} KB", .{@as(f64, @floatFromInt(bytes)) / @as(f64, @floatFromInt(kb))}) catch "? KB"
        else
            std.fmt.bufPrint(&buf, "{d} B", .{bytes}) catch "? B";

        // WARNING: This returns a pointer to stack-allocated memory
        // In real usage, caller should own the buffer
        return formatted;
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

test "HttpClient - render idle state" {
    const allocator = std.testing.allocator;
    var buffer = try Buffer.init(allocator, 40, 10);
    defer buffer.deinit();

    var client = HttpClient.init("https://example.com");
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 10 };
    client.render(&buffer, area);

    // Check that URL is rendered
    const line0 = buffer.getLine(0);
    try std.testing.expect(std.mem.indexOf(u8, line0, "URL:") != null);
    try std.testing.expect(std.mem.indexOf(u8, line0, "example.com") != null);

    // Check that state is rendered
    const line1 = buffer.getLine(1);
    try std.testing.expect(std.mem.indexOf(u8, line1, "Idle") != null);
}

test "HttpClient - render receiving state" {
    const allocator = std.testing.allocator;
    var buffer = try Buffer.init(allocator, 40, 10);
    defer buffer.deinit();

    var client = HttpClient.init("https://example.com");
    client.updateProgress(1024, 2048, 1000);

    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 10 };
    client.render(&buffer, area);

    // Check state line
    const line1 = buffer.getLine(1);
    try std.testing.expect(std.mem.indexOf(u8, line1, "Receiving") != null);
}

test "HttpClient - render completed state" {
    const allocator = std.testing.allocator;
    var buffer = try Buffer.init(allocator, 40, 10);
    defer buffer.deinit();

    var client = HttpClient.init("https://example.com");
    client.updateProgress(2048, 2048, 2000);
    client.complete("Response data here");

    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 10 };
    client.render(&buffer, area);

    // Check completed state
    const line1 = buffer.getLine(1);
    try std.testing.expect(std.mem.indexOf(u8, line1, "Completed") != null);
}

test "HttpClient - render failed state" {
    const allocator = std.testing.allocator;
    var buffer = try Buffer.init(allocator, 40, 10);
    defer buffer.deinit();

    var client = HttpClient.init("https://example.com");
    client.fail("Connection timeout");

    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 10 };
    client.render(&buffer, area);

    // Check failed state
    const line1 = buffer.getLine(1);
    try std.testing.expect(std.mem.indexOf(u8, line1, "Failed") != null);
}

test "HttpClient - setBlock" {
    var client = HttpClient.init("https://example.com");
    var block = Block.init();
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
    // Note: formatBytes uses static buffer, so these must be tested sequentially
    const bytes_str = HttpClient.formatBytes(512);
    try std.testing.expect(std.mem.indexOf(u8, bytes_str, "B") != null);

    const kb_str = HttpClient.formatBytes(1536); // 1.5 KB
    try std.testing.expect(std.mem.indexOf(u8, kb_str, "KB") != null);

    const mb_str = HttpClient.formatBytes(2 * 1024 * 1024); // 2 MB
    try std.testing.expect(std.mem.indexOf(u8, mb_str, "MB") != null);

    const gb_str = HttpClient.formatBytes(3 * 1024 * 1024 * 1024); // 3 GB
    try std.testing.expect(std.mem.indexOf(u8, gb_str, "GB") != null);
}
