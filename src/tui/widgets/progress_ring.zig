//! ProgressRing widget — circular ring-shaped progress indicator.
//!
//! The ProgressRing widget displays progress as a filled ring that grows clockwise
//! from the top (12 o'clock position). It uses geometry-based rendering with
//! terminal aspect ratio compensation for a circular appearance.
//!
//! ## Features
//! - Circular ring progress from 0.0 to 1.0
//! - Configurable ring thickness
//! - Custom filled/empty characters and styles
//! - Percentage or custom label display
//! - Block integration for bordered display
//! - Builder API for fluent configuration
//!
//! ## Usage
//! ```zig
//! const ring = ProgressRing.init(0.5)
//!     .withThickness(2)
//!     .withLabel("50%");
//! ring.render(&buf, area);
//! ```

const std = @import("std");
const buffer_mod = @import("../buffer.zig");
const Buffer = buffer_mod.Buffer;
const Cell = buffer_mod.Cell;
const layout_mod = @import("../layout.zig");
const Rect = layout_mod.Rect;
const style_mod = @import("../style.zig");
const Style = style_mod.Style;
const block_mod = @import("block.zig");
const Block = block_mod.Block;

/// ProgressRing widget - circular progress indicator
pub const ProgressRing = struct {
    value: f32 = 0.0,
    filled_char: u21 = '█',
    empty_char: u21 = '░',
    filled_style: Style = .{},
    empty_style: Style = .{},
    label: []const u8 = "",
    label_style: Style = .{},
    show_percentage: bool = true,
    thickness: u8 = 2,
    block: ?Block = null,

    /// Initialize ProgressRing with given value
    pub fn init(value: f32) ProgressRing {
        return .{ .value = value };
    }

    /// Set value directly (no clamping)
    pub fn setValue(self: *ProgressRing, v: f32) void {
        self.value = v;
    }

    /// Set value with clamping to [0.0, 1.0]
    pub fn setValueClamped(self: *ProgressRing, v: f32) void {
        self.value = std.math.clamp(v, 0.0, 1.0);
    }

    /// Get percentage (0-100) of current value
    pub fn percentage(self: ProgressRing) u8 {
        const clamped = std.math.clamp(self.value, 0.0, 1.0);
        return @as(u8, @intFromFloat(clamped * 100.0));
    }

    /// Render the progress ring to buffer
    pub fn render(self: ProgressRing, buf: *Buffer, area: Rect) void {
        if (area.width == 0 or area.height == 0) return;

        // Calculate inner area (with block border if present)
        const inner = if (self.block) |b| blk: {
            b.render(buf, area);
            break :blk b.inner(area);
        } else area;

        if (inner.width == 0 or inner.height == 0) return;

        // Calculate ring geometry
        const cx: f32 = @as(f32, @floatFromInt(inner.x)) + @as(f32, @floatFromInt(inner.width)) / 2.0 - 0.5;
        const cy: f32 = @as(f32, @floatFromInt(inner.y)) + @as(f32, @floatFromInt(inner.height)) / 2.0 - 0.5;
        const outer_r: f32 = @min(@as(f32, @floatFromInt(inner.width)) / 2.0, @as(f32, @floatFromInt(inner.height))) - 0.5;
        const inner_r: f32 = @max(0.0, outer_r - @as(f32, @floatFromInt(self.thickness)) * 2.0);
        const progress: f32 = std.math.clamp(self.value, 0.0, 1.0);

        // Render ring cells
        for (0..inner.height) |row_offset| {
            const row: u16 = inner.y + @as(u16, @intCast(row_offset));
            for (0..inner.width) |col_offset| {
                const col: u16 = inner.x + @as(u16, @intCast(col_offset));

                // Calculate distance from center (with aspect ratio compensation on y)
                const dx: f32 = @as(f32, @floatFromInt(col)) - cx;
                const dy: f32 = (@as(f32, @floatFromInt(row)) - cy) * 2.0;
                const dist: f32 = @sqrt(dx * dx + dy * dy);

                // Check if cell is in ring area (strict inequalities to avoid degenerate case)
                if (dist > inner_r and dist < outer_r) {
                    // Calculate angle: clockwise from top (12 o'clock)
                    const raw_angle: f32 = std.math.atan2(dx, -dy);
                    const angle: f32 = if (raw_angle < 0.0) raw_angle + 2.0 * std.math.pi else raw_angle;
                    const normalized: f32 = angle / (2.0 * std.math.pi);

                    // Choose character based on progress
                    if (normalized <= progress) {
                        buf.set(col, row, Cell{ .char = self.filled_char, .style = self.filled_style });
                    } else {
                        buf.set(col, row, Cell{ .char = self.empty_char, .style = self.empty_style });
                    }
                }
            }
        }

        // Render center label
        const label_str: []const u8 = if (self.label.len > 0)
            self.label
        else if (self.show_percentage) blk: {
            // Format percentage into stack buffer
            const Stack = struct {
                var pct_buf: [4]u8 = undefined;
            };
            const pct = self.percentage();
            break :blk std.fmt.bufPrint(&Stack.pct_buf, "{}%", .{pct}) catch "";
        } else
            "";

        if (label_str.len > 0 and label_str.len <= inner.width) {
            const label_x: u16 = inner.x + @as(u16, @intCast((inner.width - label_str.len) / 2));
            const label_y: u16 = inner.y + inner.height / 2;
            for (label_str, 0..) |byte, i| {
                buf.set(label_x + @as(u16, @intCast(i)), label_y, Cell{
                    .char = @as(u21, byte),
                    .style = self.label_style,
                });
            }
        }
    }

    // ===== Builder methods =====

    /// Create copy with new value
    pub fn withValue(self: ProgressRing, v: f32) ProgressRing {
        var result = self;
        result.value = v;
        return result;
    }

    /// Create copy with new filled character
    pub fn withFilledChar(self: ProgressRing, char: u21) ProgressRing {
        var result = self;
        result.filled_char = char;
        return result;
    }

    /// Create copy with new empty character
    pub fn withEmptyChar(self: ProgressRing, char: u21) ProgressRing {
        var result = self;
        result.empty_char = char;
        return result;
    }

    /// Create copy with new filled style
    pub fn withFilledStyle(self: ProgressRing, style: Style) ProgressRing {
        var result = self;
        result.filled_style = style;
        return result;
    }

    /// Create copy with new empty style
    pub fn withEmptyStyle(self: ProgressRing, style: Style) ProgressRing {
        var result = self;
        result.empty_style = style;
        return result;
    }

    /// Create copy with new label
    pub fn withLabel(self: ProgressRing, label: []const u8) ProgressRing {
        var result = self;
        result.label = label;
        return result;
    }

    /// Create copy with new label style
    pub fn withLabelStyle(self: ProgressRing, style: Style) ProgressRing {
        var result = self;
        result.label_style = style;
        return result;
    }

    /// Create copy with new show_percentage setting
    pub fn withShowPercentage(self: ProgressRing, show: bool) ProgressRing {
        var result = self;
        result.show_percentage = show;
        return result;
    }

    /// Create copy with new thickness
    pub fn withThickness(self: ProgressRing, t: u8) ProgressRing {
        var result = self;
        result.thickness = t;
        return result;
    }

    /// Create copy with block
    pub fn withBlock(self: ProgressRing, b: Block) ProgressRing {
        var result = self;
        result.block = b;
        return result;
    }
};
