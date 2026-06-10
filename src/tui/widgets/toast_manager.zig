const std = @import("std");
const Buffer = @import("../buffer.zig").Buffer;
const Cell = @import("../buffer.zig").Cell;
const Rect = @import("../layout.zig").Rect;
const Style = @import("../style.zig").Style;
const Color = @import("../style.zig").Color;
const Block = @import("block.zig").Block;
const Borders = @import("block.zig").Borders;

/// Toast notification level
pub const ToastLevel = enum {
    info,
    success,
    warning,
    error_,

    /// Returns the Unicode icon character for this toast level
    pub fn icon(self: ToastLevel) u21 {
        return switch (self) {
            .info => 'ℹ',
            .success => '✓',
            .warning => '⚠',
            .error_ => '✗',
        };
    }

    /// Returns the default style for this toast level
    pub fn style(self: ToastLevel) Style {
        return switch (self) {
            .info => Style{ .fg = .{ .indexed = 12 } }, // Blue
            .success => Style{ .fg = .{ .indexed = 10 } }, // Green
            .warning => Style{ .fg = .{ .indexed = 11 } }, // Yellow
            .error_ => Style{ .fg = .{ .indexed = 9 } }, // Red
        };
    }
};

/// Position where toast stack appears on screen
pub const ToastPosition = enum {
    top_right,
    top_left,
    bottom_right,
    bottom_left,
};

/// Single toast item in the queue
pub const ToastItem = struct {
    message: []const u8,
    level: ToastLevel,
    title: ?[]const u8 = null,
    ticks_remaining: u32 = 0, // 0 = persistent (never auto-dismissed)
};

/// Fixed-capacity toast notification manager
pub const ToastManager = struct {
    const MAX_TOASTS = 8;

    toasts: [MAX_TOASTS]ToastItem = undefined,
    count: usize = 0,
    position: ToastPosition = .top_right,
    max_visible: u8 = 3,
    width: u16 = 40,
    spacing: u16 = 1,
    info_style: Style = Style{ .fg = .{ .indexed = 12 } },
    success_style: Style = Style{ .fg = .{ .indexed = 10 } },
    warning_style: Style = Style{ .fg = .{ .indexed = 11 } },
    error_style: Style = Style{ .fg = .{ .indexed = 9 } },

    /// Initialize a new ToastManager with default values
    pub fn init() ToastManager {
        return ToastManager{};
    }

    /// Add toast to queue. If count == MAX_TOASTS, evict oldest first.
    pub fn push(self: *ToastManager, toast: ToastItem) void {
        if (self.count >= MAX_TOASTS) {
            // Shift all toasts left (evict oldest)
            for (0..MAX_TOASTS - 1) |i| {
                self.toasts[i] = self.toasts[i + 1];
            }
            self.toasts[MAX_TOASTS - 1] = toast;
        } else {
            self.toasts[self.count] = toast;
            self.count += 1;
        }
    }

    /// Remove toast at index, shift remaining left
    pub fn dismiss(self: *ToastManager, index: usize) void {
        if (index >= self.count) return;

        for (index..self.count - 1) |i| {
            self.toasts[i] = self.toasts[i + 1];
        }
        self.count -= 1;
    }

    /// Clear all toasts
    pub fn dismissAll(self: *ToastManager) void {
        self.count = 0;
    }

    /// Decrement ticks_remaining for non-zero entries; remove those that hit 0
    pub fn tick(self: *ToastManager) void {
        var i: usize = 0;
        while (i < self.count) {
            if (self.toasts[i].ticks_remaining > 0) {
                self.toasts[i].ticks_remaining -= 1;
                if (self.toasts[i].ticks_remaining == 0) {
                    self.dismiss(i);
                    continue;
                }
            }
            i += 1;
        }
    }

    /// Return current number of toasts
    pub fn toastCount(self: ToastManager) usize {
        return self.count;
    }

    /// Render up to max_visible toasts stacked from the position corner
    pub fn render(self: ToastManager, buf: *Buffer, screen: Rect) void {
        if (screen.width == 0 or screen.height == 0) return;
        if (self.count == 0) return;

        const n = @min(self.count, self.max_visible);
        const toast_width: u16 = @min(self.width, screen.width);
        if (toast_width < 4) return;

        const base_inner_height: u16 = 1; // message line
        const border_height: u16 = 2; // top + bottom border

        // Pre-compute per-toast heights (2D: border + optional title + message)
        var heights: [MAX_TOASTS]u16 = undefined;
        for (0..n) |i| {
            const title_height: u16 = if (self.toasts[i].title != null) 1 else 0;
            heights[i] = border_height + title_height + base_inner_height;
        }

        // Compute y-positions for each toast based on corner position
        var y_positions: [MAX_TOASTS]u16 = undefined;
        switch (self.position) {
            .top_right, .top_left => {
                var cur_y = screen.y;
                for (0..n) |i| {
                    y_positions[i] = cur_y;
                    cur_y +|= heights[i] + self.spacing;
                }
            },
            .bottom_right, .bottom_left => {
                // Stack upward from bottom: toast[n-1] at very bottom, toast[0] above
                var cur_y: u16 = screen.y + screen.height;
                var j = n;
                while (j > 0) {
                    j -= 1;
                    cur_y -|= heights[j];
                    y_positions[j] = cur_y;
                    if (j > 0) cur_y -|= self.spacing;
                }
            },
        }

        const toast_x: u16 = switch (self.position) {
            .top_right, .bottom_right => screen.x + screen.width -| toast_width,
            .top_left, .bottom_left => screen.x,
        };

        for (0..n) |i| {
            const toast = self.toasts[i];
            const toast_y = y_positions[i];

            // Skip if toast would be outside screen bounds
            if (toast_y >= screen.y + screen.height) continue;
            const avail_height = screen.y + screen.height - toast_y;
            if (avail_height == 0) continue;

            const area = Rect{
                .x = toast_x,
                .y = toast_y,
                .width = toast_width,
                .height = @min(heights[i], @as(u16, @intCast(avail_height))),
            };
            if (area.width == 0 or area.height == 0) continue;

            // Choose level style
            const level_style = switch (toast.level) {
                .info => self.info_style,
                .success => self.success_style,
                .warning => self.warning_style,
                .error_ => self.error_style,
            };

            // Render bordered box with optional title
            const block = Block{
                .borders = Borders.all,
                .border_style = level_style,
                .title = toast.title,
            };
            block.render(buf, area);

            const inner = block.inner(area);
            if (inner.width == 0 or inner.height == 0) continue;

            // Render title line if present
            var content_y = inner.y;
            if (toast.title != null) {
                // Title is already rendered by Block in the top border row — skip to message line
                content_y = inner.y;
            }

            // Render icon + message
            var x = inner.x;
            if (x < inner.x + inner.width) {
                // Encode icon as UTF-8 and render
                var icon_buf: [4]u8 = undefined;
                const icon_len = std.unicode.utf8Encode(toast.level.icon(), &icon_buf) catch 0;
                if (icon_len > 0 and x < inner.x + inner.width) {
                    buf.setString(x, content_y, icon_buf[0..icon_len], level_style);
                    x += 1;
                }
                if (x < inner.x + inner.width) {
                    buf.set(x, content_y, Cell{ .char = ' ', .style = level_style });
                    x += 1;
                }
            }

            // Render message text (clamped to available width)
            if (x < inner.x + inner.width) {
                const avail = inner.x + inner.width - x;
                const msg = if (toast.message.len > avail) toast.message[0..avail] else toast.message;
                buf.setString(x, content_y, msg, level_style);
            }
        }
    }

    /// Builder: set position
    pub fn withPosition(self: ToastManager, pos: ToastPosition) ToastManager {
        var result = self;
        result.position = pos;
        return result;
    }

    /// Builder: set max visible toasts
    pub fn withMaxVisible(self: ToastManager, n: u8) ToastManager {
        var result = self;
        result.max_visible = n;
        return result;
    }

    /// Builder: set width
    pub fn withWidth(self: ToastManager, w: u16) ToastManager {
        var result = self;
        result.width = w;
        return result;
    }

    /// Builder: set spacing
    pub fn withSpacing(self: ToastManager, s: u16) ToastManager {
        var result = self;
        result.spacing = s;
        return result;
    }

    /// Builder: set info style
    pub fn withInfoStyle(self: ToastManager, s: Style) ToastManager {
        var result = self;
        result.info_style = s;
        return result;
    }

    /// Builder: set success style
    pub fn withSuccessStyle(self: ToastManager, s: Style) ToastManager {
        var result = self;
        result.success_style = s;
        return result;
    }

    /// Builder: set warning style
    pub fn withWarningStyle(self: ToastManager, s: Style) ToastManager {
        var result = self;
        result.warning_style = s;
        return result;
    }

    /// Builder: set error style
    pub fn withErrorStyle(self: ToastManager, s: Style) ToastManager {
        var result = self;
        result.error_style = s;
        return result;
    }
};
