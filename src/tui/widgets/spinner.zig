//! Spinner Widget — animated loading/progress indicator.
//!
//! Spinner displays an animated character sequence (frames) that cycles
//! through different states. It's ideal for showing loading/processing states
//! with optional text labels.
//!
//! ## Features
//! - Configurable animation frames (braille, line, dots, arrow, etc.)
//! - Optional text label alongside spinner
//! - Independent styling for spinner char and label text
//! - Optional Block wrapper for borders
//! - Frame advancement via tick()
//!
//! ## Usage
//! ```zig
//! var spinner = (Spinner{})
//!     .withLabel("Loading...")
//!     .withStyle(Style{ .fg = Color.green });
//!
//! spinner.render(&buf, area);
//! spinner = spinner.tick();  // advance to next frame
//! ```

const std = @import("std");
const buffer_mod = @import("../buffer.zig");
const Buffer = buffer_mod.Buffer;
const layout_mod = @import("../layout.zig");
const Rect = layout_mod.Rect;
const style_mod = @import("../style.zig");
const Style = style_mod.Style;
const block_mod = @import("block.zig");
const Block = block_mod.Block;
const symbols = @import("../symbols.zig");

/// Spinner widget — animated loading indicator
pub const Spinner = struct {
    /// Animation frames to cycle through
    frames: []const []const u8 = &symbols.Spinner.braille,

    /// Current frame index
    frame: usize = 0,

    /// Optional label text to display after spinner
    label: ?[]const u8 = null,

    /// Style for the spinner character
    style: Style = .{},

    /// Style for the label text
    label_style: Style = .{},

    /// Optional block for borders/title
    block: ?Block = null,

    /// Set custom animation frames
    pub fn withFrames(self: Spinner, frames: []const []const u8) Spinner {
        var result = self;
        result.frames = frames;
        return result;
    }

    /// Set current frame index
    pub fn withFrame(self: Spinner, frame: usize) Spinner {
        var result = self;
        result.frame = frame;
        return result;
    }

    /// Set label text
    pub fn withLabel(self: Spinner, label: []const u8) Spinner {
        var result = self;
        result.label = label;
        return result;
    }

    /// Set spinner character style
    pub fn withStyle(self: Spinner, new_style: Style) Spinner {
        var result = self;
        result.style = new_style;
        return result;
    }

    /// Set label text style
    pub fn withLabelStyle(self: Spinner, new_style: Style) Spinner {
        var result = self;
        result.label_style = new_style;
        return result;
    }

    /// Set block for borders/title
    pub fn withBlock(self: Spinner, new_block: Block) Spinner {
        var result = self;
        result.block = new_block;
        return result;
    }

    /// Advance to next frame (returns new Spinner with frame+1)
    pub fn tick(self: Spinner) Spinner {
        var result = self;
        result.frame += 1;
        return result;
    }

    /// Get current frame string
    pub fn currentFrame(self: Spinner) []const u8 {
        if (self.frames.len == 0) return "";
        return self.frames[self.frame % self.frames.len];
    }

    /// Render the spinner widget
    pub fn render(self: Spinner, buf: *Buffer, area: Rect) void {
        // Render block if present
        var inner_area = area;
        if (self.block) |blk| {
            blk.render(buf, area);
            inner_area = blk.inner(area);
        }

        // Nothing to render if area too small
        if (inner_area.width == 0 or inner_area.height == 0) return;

        // Get current frame string
        const frame_str = self.currentFrame();

        // Render spinner character at the start of the area
        buf.setString(inner_area.x, inner_area.y, frame_str, self.style);

        // Render label if present
        if (self.label) |label_text| {
            if (label_text.len > 0) {
                // Calculate position: spinner (1 cell) + space (1 cell) + label
                // For simplicity, assume spinner frames are 1 display-width wide
                const label_start_x = inner_area.x + 1 + 1; // spinner + space

                // Only render label if there's enough space
                if (label_start_x < inner_area.x + inner_area.width) {
                    // Calculate available space for label
                    const available_width = @as(isize, @intCast(inner_area.x + @as(u16, @intCast(inner_area.width)))) - @as(isize, @intCast(label_start_x));
                    if (available_width > 0) {
                        // Render space separator
                        buf.setString(inner_area.x + 1, inner_area.y, " ", self.style);
                        // Render label text
                        buf.setString(@intCast(label_start_x), inner_area.y, label_text, self.label_style);
                    }
                }
            }
        }
    }
};
