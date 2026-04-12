//! Plugin Demo — Custom widget integration example (v1.23.0)
//!
//! Demonstrates sailor's plugin architecture:
//! 1. Implementing widget protocol (render + measure)
//! 2. Composition helpers (Padding + Aligned)

const std = @import("std");
const sailor = @import("sailor");

const Buffer = sailor.tui.Buffer;
const Rect = sailor.tui.Rect;
const Style = sailor.tui.Style;
const Color = sailor.tui.Color;
const Size = sailor.tui.widget_trait.Size;

// Import composition helpers
const Padding = sailor.tui.widget_helpers.Padding;
const Aligned = sailor.tui.widget_helpers.Aligned;

// ============================================================================
// Custom Plugin Widget: ProgressRing
// ============================================================================

/// Custom progress indicator widget implementing the widget protocol.
const ProgressRing = struct {
    progress: f32, // 0.0 to 1.0
    label: []const u8,
    style: Style,

    pub fn init(progress: f32, label: []const u8, style: Style) ProgressRing {
        return .{
            .progress = @max(0.0, @min(1.0, progress)),
            .label = label,
            .style = style,
        };
    }

    pub fn measure(_: ProgressRing, _: std.mem.Allocator, max_width: u16, max_height: u16) !Size {
        return Size{
            .width = @min(max_width, 20),
            .height = @min(max_height, 7),
        };
    }

    pub fn render(self: ProgressRing, buf: *Buffer, area: Rect) void {
        if (area.width < 10 or area.height < 5) return;

        // Calculate center
        const center_x = area.x + area.width / 2;
        const center_y = area.y + area.height / 2;

        // Render box using Unicode characters
        buf.set(center_x - 1, center_y - 1, .{ .char = '╔', .style = self.style });
        buf.set(center_x, center_y - 1, .{ .char = '═', .style = self.style });
        buf.set(center_x + 1, center_y - 1, .{ .char = '╗', .style = self.style });

        // Show percentage in center
        const percent = @as(u8, @intFromFloat(self.progress * 100.0));
        var buf_arr: [8]u8 = undefined;
        const percent_str = std.fmt.bufPrint(&buf_arr, "{d}%", .{percent}) catch "??%";
        buf.setString(center_x - @as(u16, @intCast(percent_str.len / 2)), center_y, percent_str, self.style);

        // Bottom border
        buf.set(center_x - 1, center_y + 1, .{ .char = '╚', .style = self.style });
        buf.set(center_x, center_y + 1, .{ .char = '═', .style = self.style });
        buf.set(center_x + 1, center_y + 1, .{ .char = '╝', .style = self.style });

        // Render label
        if (self.label.len > 0) {
            const label_x = center_x - @as(u16, @intCast(@min(self.label.len, area.width) / 2));
            buf.setString(label_x, center_y + 2, self.label, self.style);
        }
    }
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Get terminal size
    const term_size = try sailor.term.getSize();
    const width = @min(term_size.cols, 80);
    const height = @min(term_size.rows, 24);

    // Create buffer
    var buffer = try Buffer.init(allocator, width, height);
    defer buffer.deinit();

    // Create custom widget with style
    const ring_style = Style{ .fg = Color{ .indexed = 14 } }; // Bright cyan
    const ring = ProgressRing.init(0.75, "Loading...", ring_style);

    // Demonstrate composition: Padding + Centered alignment
    const padded = Padding(ProgressRing).init(ring, 2);
    const aligned = Aligned(Padding(ProgressRing)).init(padded, .{
        .horizontal = .center,
        .vertical = .middle,
    });

    // Render widget
    const area = Rect{ .x = 0, .y = 0, .width = width, .height = height };
    aligned.render(&buffer, area);

    // Create empty previous buffer for diff
    var previous = try Buffer.init(allocator, width, height);
    defer previous.deinit();

    // Compute diff and render to stdout
    var output_buf: std.ArrayList(u8) = .{};
    defer output_buf.deinit(allocator);
    const writer = output_buf.writer(allocator);

    const diff_ops = try sailor.tui.buffer.diff(allocator, previous, buffer);
    defer allocator.free(diff_ops);
    try sailor.tui.buffer.renderDiff(diff_ops, writer);

    // Write to stdout
    _ = try std.posix.write(std.posix.STDOUT_FILENO, output_buf.items);

    std.debug.print("\n\n✅ Plugin Demo (v1.23.0)\n", .{});
    std.debug.print("Custom widget: ProgressRing (75% progress)\n", .{});
    std.debug.print("Composition: Padding(2) + Aligned(center, middle)\n\n", .{});
}
