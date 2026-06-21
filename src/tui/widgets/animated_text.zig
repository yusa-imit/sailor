//! AnimatedText widget — text with frame-based character animations.
//!
//! The AnimatedText widget renders text with various animation styles that are
//! controlled by a frame counter. Different animation styles create different effects:
//! - typewriter: reveals characters one by one
//! - wave: moves characters up and down
//! - fade: alternates between visible and invisible
//! - blink: toggles between visible and hidden
//! - glow: cycles colors through a pattern
//!
//! ## Features
//! - Multiple animation styles: typewriter, wave, fade, blink, glow
//! - Frame-based animation with configurable speed
//! - Text alignment (left, center, right, justify)
//! - Optional block wrapper for borders
//! - Fluent builder API for configuration
//!
//! ## Usage
//! ```zig
//! var widget = AnimatedText.init()
//!     .withText("Hello, World!")
//!     .withAnimationStyle(.typewriter)
//!     .withSpeed(2);
//! widget.tick();
//! widget.render(&buf, area);
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
const paragraph_mod = @import("paragraph.zig");
const Alignment = paragraph_mod.Alignment;

/// Animation style determines how text is revealed/transformed
pub const AnimatedText = struct {
    /// Animation style options
    pub const AnimationStyle = enum {
        typewriter, // Reveal characters one by one
        wave,       // Move characters up and down
        fade,       // Alternate between visible and invisible
        blink,      // Toggle between visible and hidden
        glow,       // Cycle colors through a pattern
    };

    /// Text content to display
    text: []const u8 = "",
    /// Current animation frame (incremented by tick())
    frame: u32 = 0,
    /// Speed of animation (affects how many frames per character or cycle)
    speed: u8 = 4,
    /// Base style applied to non-highlighted characters
    base_style: Style = .{},
    /// Highlight style applied to selected characters (used in glow animation)
    highlight_style: Style = .{},
    /// Animation style to use
    animation: AnimationStyle = .typewriter,
    /// Text alignment within the render area
    alignment: Alignment = .left,
    /// Optional block wrapper for borders and padding
    block: ?Block = null,

    /// Initialize with default values
    pub fn init() AnimatedText {
        return .{};
    }

    /// Increment frame by 1 (wrapping at u32 max)
    pub fn tick(self: *AnimatedText) void {
        self.frame +%= 1;
    }

    /// Increment frame by n (wrapping at u32 max)
    pub fn tickBy(self: *AnimatedText, n: u32) void {
        self.frame +%= n;
    }

    /// Reset frame to 0
    pub fn reset(self: *AnimatedText) void {
        self.frame = 0;
    }

    /// Get the number of visible characters for typewriter animation
    /// For other animations, returns full text length
    pub fn visibleLength(self: AnimatedText) usize {
        if (self.animation != .typewriter) {
            return self.text.len;
        }

        const speed = @max(self.speed, 1);
        const step = @as(usize, self.frame) / @as(usize, speed);
        return @min(step, self.text.len);
    }

    /// Builder: set text
    pub fn withText(self: AnimatedText, text: []const u8) AnimatedText {
        var copy = self;
        copy.text = text;
        return copy;
    }

    /// Builder: set animation style
    pub fn withAnimationStyle(self: AnimatedText, animation: AnimationStyle) AnimatedText {
        var copy = self;
        copy.animation = animation;
        return copy;
    }

    /// Builder: set frame
    pub fn withFrame(self: AnimatedText, frame: u32) AnimatedText {
        var copy = self;
        copy.frame = frame;
        return copy;
    }

    /// Builder: set speed
    pub fn withSpeed(self: AnimatedText, speed: u8) AnimatedText {
        var copy = self;
        copy.speed = speed;
        return copy;
    }

    /// Builder: set base style
    pub fn withBaseStyle(self: AnimatedText, style: Style) AnimatedText {
        var copy = self;
        copy.base_style = style;
        return copy;
    }

    /// Builder: set highlight style
    pub fn withHighlightStyle(self: AnimatedText, style: Style) AnimatedText {
        var copy = self;
        copy.highlight_style = style;
        return copy;
    }

    /// Builder: set alignment
    pub fn withAlignment(self: AnimatedText, alignment: Alignment) AnimatedText {
        var copy = self;
        copy.alignment = alignment;
        return copy;
    }

    /// Builder: set block wrapper
    pub fn withBlock(self: AnimatedText, b: ?Block) AnimatedText {
        var copy = self;
        copy.block = b;
        return copy;
    }

    /// Render the widget to a buffer at the given area
    pub fn render(self: AnimatedText, buf: *Buffer, area: Rect) void {
        // Guard: zero area
        if (area.width == 0 or area.height == 0) return;

        // Determine inner area (either inside block or same as area)
        var inner = area;
        if (self.block) |b| {
            b.render(buf, area);
            inner = b.inner(area);
        }

        // Guard: zero inner area
        if (inner.width == 0 or inner.height == 0) return;

        // Early exit for empty text
        if (self.text.len == 0) return;

        // Compute animation parameters
        const speed = @max(self.speed, 1);
        const step = @as(u32, self.frame) / @as(u32, speed);

        // Get visible length based on animation style
        const visible_len = switch (self.animation) {
            .typewriter => self.visibleLength(),
            else => self.text.len,
        };

        // Clamp render length to area width
        const render_len = @min(visible_len, @as(usize, inner.width));

        // Compute start position based on alignment
        const start_x = self.computeStartX(inner, visible_len, render_len);

        // Dispatch to animation-specific rendering
        switch (self.animation) {
            .typewriter => self.renderTypewriter(buf, inner, start_x, render_len),
            .wave => self.renderWave(buf, inner, start_x, step),
            .fade => self.renderFade(buf, inner, start_x, render_len, step),
            .blink => self.renderBlink(buf, inner, start_x, render_len, step),
            .glow => self.renderGlow(buf, inner, start_x, render_len, step),
        }
    }

    /// Compute the starting x position based on alignment
    fn computeStartX(self: AnimatedText, inner: Rect, visible_len: usize, render_len: usize) u16 {
        const inner_x = inner.x;
        const inner_width = inner.width;

        return switch (self.alignment) {
            .left => inner_x,
            .center => {
                if (visible_len <= inner_width) {
                    const offset = (inner_width - render_len) / 2;
                    return inner_x + @as(u16, @intCast(offset));
                } else {
                    return inner_x;
                }
            },
            .right => {
                if (visible_len <= inner_width) {
                    const offset = inner_width - render_len;
                    return inner_x + @as(u16, @intCast(offset));
                } else {
                    return inner_x;
                }
            },
            .justify => inner_x,
        };
    }

    /// Render typewriter animation (reveal characters one by one)
    fn renderTypewriter(self: AnimatedText, buf: *Buffer, inner: Rect, start_x: u16, render_len: usize) void {
        var col = start_x;
        var byte_offset: usize = 0;
        var char_index: usize = 0;

        while (byte_offset < self.text.len and char_index < render_len and col < inner.x + inner.width) {
            const byte = self.text[byte_offset];
            const char_len = std.unicode.utf8ByteSequenceLength(byte) catch 1;

            if (byte_offset + char_len > self.text.len) break;

            // Render single character
            const char_slice = self.text[byte_offset .. byte_offset + char_len];
            buf.setString(col, inner.y, char_slice, self.base_style);

            // Advance
            byte_offset += char_len;
            col += 1;
            char_index += 1;
        }
    }

    /// Render wave animation (move characters up and down)
    fn renderWave(self: AnimatedText, buf: *Buffer, inner: Rect, start_x: u16, step: u32) void {
        var col = start_x;
        var byte_offset: usize = 0;
        var char_index: u32 = 0;

        while (byte_offset < self.text.len and col < inner.x + inner.width) {
            const byte = self.text[byte_offset];
            const char_len = std.unicode.utf8ByteSequenceLength(byte) catch 1;

            if (byte_offset + char_len > self.text.len) break;

            // Compute row for wave effect
            const height = @max(inner.height, 1);
            const row_offset = (step + char_index) % @as(u32, @intCast(height));
            const row = inner.y + @as(u16, @intCast(row_offset));

            // Render single character at wave row
            const char_slice = self.text[byte_offset .. byte_offset + char_len];
            buf.setString(col, row, char_slice, self.base_style);

            // Advance
            byte_offset += char_len;
            col += 1;
            char_index += 1;
        }
    }

    /// Render fade animation (alternate between visible and invisible)
    fn renderFade(self: AnimatedText, buf: *Buffer, inner: Rect, start_x: u16, render_len: usize, step: u32) void {
        const is_visible = (step % 2) == 0;
        const style = if (is_visible) self.base_style else Style{};

        var col = start_x;
        var byte_offset: usize = 0;
        var char_index: usize = 0;

        while (byte_offset < self.text.len and char_index < render_len and col < inner.x + inner.width) {
            const byte = self.text[byte_offset];
            const char_len = std.unicode.utf8ByteSequenceLength(byte) catch 1;

            if (byte_offset + char_len > self.text.len) break;

            // Render single character with fade style
            const char_slice = self.text[byte_offset .. byte_offset + char_len];
            buf.setString(col, inner.y, char_slice, style);

            // Advance
            byte_offset += char_len;
            col += 1;
            char_index += 1;
        }
    }

    /// Render blink animation (toggle between visible and hidden)
    fn renderBlink(self: AnimatedText, buf: *Buffer, inner: Rect, start_x: u16, render_len: usize, step: u32) void {
        // If step is odd, don't render anything (blink off)
        if ((step % 2) == 1) return;

        // Render all characters at start_x, inner.y
        var col = start_x;
        var byte_offset: usize = 0;
        var char_index: usize = 0;

        while (byte_offset < self.text.len and char_index < render_len and col < inner.x + inner.width) {
            const byte = self.text[byte_offset];
            const char_len = std.unicode.utf8ByteSequenceLength(byte) catch 1;

            if (byte_offset + char_len > self.text.len) break;

            // Render single character
            const char_slice = self.text[byte_offset .. byte_offset + char_len];
            buf.setString(col, inner.y, char_slice, self.base_style);

            // Advance
            byte_offset += char_len;
            col += 1;
            char_index += 1;
        }
    }

    /// Render glow animation (cycle colors through a 3-position pattern)
    fn renderGlow(self: AnimatedText, buf: *Buffer, inner: Rect, start_x: u16, render_len: usize, step: u32) void {
        var col = start_x;
        var byte_offset: usize = 0;
        var char_index: u32 = 0;

        while (byte_offset < self.text.len and char_index < @as(u32, @intCast(render_len)) and col < inner.x + inner.width) {
            const byte = self.text[byte_offset];
            const char_len = std.unicode.utf8ByteSequenceLength(byte) catch 1;

            if (byte_offset + char_len > self.text.len) break;

            // Compute style based on position in 3-char cycle
            const style_index = (char_index + step) % 3;
            const style = if (style_index == 0) self.highlight_style else self.base_style;

            // Render single character
            const char_slice = self.text[byte_offset .. byte_offset + char_len];
            buf.setString(col, inner.y, char_slice, style);

            // Advance
            byte_offset += char_len;
            col += 1;
            char_index += 1;
        }
    }
};

// ============================================================================
// TESTS
// ============================================================================

test "AnimatedText init returns zero frame" {
    const widget = AnimatedText.init();
    try std.testing.expectEqual(@as(u32, 0), widget.frame);
}

test "AnimatedText init returns speed 4 by default" {
    const widget = AnimatedText.init();
    try std.testing.expectEqual(@as(u8, 4), widget.speed);
}

test "AnimatedText init returns empty text" {
    const widget = AnimatedText.init();
    try std.testing.expectEqualStrings("", widget.text);
}

test "AnimatedText init returns typewriter animation by default" {
    const widget = AnimatedText.init();
    try std.testing.expectEqual(AnimatedText.AnimationStyle.typewriter, widget.animation);
}

test "AnimatedText init returns left alignment by default" {
    const widget = AnimatedText.init();
    try std.testing.expectEqual(Alignment.left, widget.alignment);
}
