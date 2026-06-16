//! Wizard Widget — multi-step flow navigation with step indicators.
//!
//! Wizard displays a series of steps with a visual indicator showing progress,
//! a title for the current step, and optional navigation hints.
//!
//! ## Features
//! - Step indicator row with active/inactive step circles
//! - Current step title display
//! - Optional navigation hints (← Back, Next →)
//! - Builder pattern for styling
//! - Block support for borders
//! - Geometry calculations (contentArea, headerHeight)
//!
//! ## Usage
//! ```zig
//! var steps: [3]Wizard.Step = .{
//!     .{ .title = "Welcome" },
//!     .{ .title = "Setup" },
//!     .{ .title = "Confirm" },
//! };
//!
//! var wizard = Wizard.init(&steps)
//!     .withActiveStepStyle(Style{ .bold = true })
//!     .withShowNavHint(true);
//!
//! wizard.render(&buf, area);
//! wizard.nextStep();
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

/// Wizard widget — multi-step flow navigation
pub const Wizard = struct {
    /// Step definition
    pub const Step = struct {
        /// Step title
        title: []const u8,
        /// Optional step description
        description: []const u8 = "",
    };

    /// Array of steps in the wizard
    steps: []const Step,

    /// Index of the current step
    current: usize = 0,

    /// Style for the active (current) step indicator
    active_step_style: Style = .{},

    /// Style for inactive step indicators
    inactive_step_style: Style = .{},

    /// Style for the current step title
    title_style: Style = .{},

    /// Style for step descriptions
    description_style: Style = .{},

    /// Style for navigation hints
    nav_style: Style = .{},

    /// Whether to show navigation hints at the bottom
    show_nav_hint: bool = true,

    /// Optional block for borders
    block: ?Block = null,

    /// Initialize Wizard with steps
    pub fn init(steps: []const Step) Wizard {
        return .{
            .steps = steps,
        };
    }

    /// Get the total number of steps
    pub fn stepCount(self: Wizard) usize {
        return self.steps.len;
    }

    /// Get the current step, or null if no steps
    pub fn currentStep(self: Wizard) ?Step {
        if (self.steps.len == 0) return null;
        if (self.current >= self.steps.len) return null;
        return self.steps[self.current];
    }

    /// Advance to the next step (clamped at steps.len-1)
    pub fn nextStep(self: *Wizard) void {
        if (self.steps.len == 0) return;
        if (self.current < self.steps.len - 1) {
            self.current += 1;
        }
    }

    /// Go back to the previous step (clamped at 0)
    pub fn prevStep(self: *Wizard) void {
        if (self.current > 0) {
            self.current -= 1;
        }
    }

    /// Jump to a specific step (no-op if out of bounds or no steps)
    pub fn goToStep(self: *Wizard, step: usize) void {
        if (self.steps.len == 0) return;
        if (step < self.steps.len) {
            self.current = step;
        }
    }

    /// Check if at the first step
    pub fn isFirst(self: Wizard) bool {
        if (self.steps.len == 0) return true;
        return self.current == 0;
    }

    /// Check if at the last step
    pub fn isLast(self: Wizard) bool {
        if (self.steps.len == 0) return true;
        return self.current == self.steps.len - 1;
    }

    /// Get the height of the header (step indicator + title + separator)
    pub fn headerHeight(self: Wizard) u16 {
        if (self.steps.len == 0) return 0;
        return 3; // indicator row + title row + separator row
    }

    /// Calculate the content area after header and optional nav hint
    pub fn contentArea(self: Wizard, area: Rect) Rect {
        var inner = area;

        // Apply block borders/padding if present
        if (self.block) |block| {
            inner = block.inner(area);
        }

        if (inner.width == 0 or inner.height == 0) {
            return Rect{ .x = inner.x, .y = inner.y, .width = 0, .height = 0 };
        }

        // Subtract header height from inner area
        const hdr = self.headerHeight();
        inner.y += hdr;
        inner.height -|= hdr;

        // Subtract nav hint row if shown and space available
        if (self.show_nav_hint and inner.height > 0) {
            inner.height -= 1;
        }

        return inner;
    }

    // ========================================================================
    // Builder Pattern — all return value copies for immutability
    // ========================================================================

    /// Set current step
    pub fn withCurrent(self: Wizard, current: usize) Wizard {
        var result = self;
        result.current = current;
        return result;
    }

    /// Set active step style
    pub fn withActiveStepStyle(self: Wizard, style: Style) Wizard {
        var result = self;
        result.active_step_style = style;
        return result;
    }

    /// Set inactive step style
    pub fn withInactiveStepStyle(self: Wizard, style: Style) Wizard {
        var result = self;
        result.inactive_step_style = style;
        return result;
    }

    /// Set title style
    pub fn withTitleStyle(self: Wizard, style: Style) Wizard {
        var result = self;
        result.title_style = style;
        return result;
    }

    /// Set description style
    pub fn withDescriptionStyle(self: Wizard, style: Style) Wizard {
        var result = self;
        result.description_style = style;
        return result;
    }

    /// Set navigation hint style
    pub fn withNavStyle(self: Wizard, style: Style) Wizard {
        var result = self;
        result.nav_style = style;
        return result;
    }

    /// Set whether to show navigation hints
    pub fn withShowNavHint(self: Wizard, show: bool) Wizard {
        var result = self;
        result.show_nav_hint = show;
        return result;
    }

    /// Set block (border/padding)
    pub fn withBlock(self: Wizard, block: Block) Wizard {
        var result = self;
        result.block = block;
        return result;
    }

    // ========================================================================
    // Rendering
    // ========================================================================

    /// Render the wizard widget
    pub fn render(self: Wizard, buf: *Buffer, area: Rect) void {
        if (area.width == 0 or area.height == 0) return;

        var inner = area;

        // Render block if present
        if (self.block) |block| {
            block.render(buf, area);
            inner = block.inner(area);
        }

        if (inner.width == 0 or inner.height == 0) return;
        if (self.steps.len == 0) return;

        // Row 0: Step indicator line
        if (inner.height > 0) {
            self.renderIndicatorRow(buf, inner, 0);
        }

        // Row 1: Title of current step
        if (inner.height > 1) {
            self.renderTitleRow(buf, inner, 1);
        }

        // Row 2: Separator line
        if (inner.height > 2) {
            self.renderSeparatorRow(buf, inner, 2);
        }

        // Nav hint row: last row of inner area
        if (self.show_nav_hint and inner.height > 3) {
            const nav_row = inner.y + inner.height - 1;
            self.renderNavHint(buf, inner, nav_row);
        }
    }

    /// Render the step indicator row
    fn renderIndicatorRow(self: Wizard, buf: *Buffer, inner: Rect, row_offset: u16) void {
        var col: u16 = inner.x;
        const end_col = inner.x + inner.width;

        for (0..self.steps.len) |i| {
            if (col >= end_col) break;

            // Active step uses filled circle, inactive uses empty
            const char: u21 = if (i == self.current) '●' else '○';
            const style = if (i == self.current) self.active_step_style else self.inactive_step_style;

            buf.set(col, inner.y + row_offset, .{ .char = char, .style = style });
            col += 1;

            if (col >= end_col) break;

            // Add step name/number
            var step_label: [32]u8 = undefined;
            const label_slice = std.fmt.bufPrint(&step_label, "Step{d}", .{i + 1}) catch "";
            for (label_slice) |ch| {
                if (col >= end_col) break;
                buf.set(col, inner.y + row_offset, .{ .char = ch, .style = style });
                col += 1;
            }

            // Separator between steps (but not after the last one)
            if (i < self.steps.len - 1) {
                if (col < end_col) {
                    buf.set(col, inner.y + row_offset, .{ .char = ' ', .style = .{} });
                    col += 1;
                }
                for (0..3) |_| {
                    if (col >= end_col) break;
                    buf.set(col, inner.y + row_offset, .{ .char = '─', .style = .{} });
                    col += 1;
                }
                if (col < end_col) {
                    buf.set(col, inner.y + row_offset, .{ .char = ' ', .style = .{} });
                    col += 1;
                }
            }
        }
    }

    /// Render the title row
    fn renderTitleRow(self: Wizard, buf: *Buffer, inner: Rect, row_offset: u16) void {
        if (self.current >= self.steps.len) return;

        const title = self.steps[self.current].title;
        const row = inner.y + row_offset;

        var col = inner.x;
        const end_col = inner.x + inner.width;

        for (title) |ch| {
            if (col >= end_col) break;
            buf.set(col, row, .{ .char = ch, .style = self.title_style });
            col += 1;
        }
    }

    /// Render the separator line
    fn renderSeparatorRow(_: Wizard, buf: *Buffer, inner: Rect, row_offset: u16) void {
        const row = inner.y + row_offset;

        for (inner.x..inner.x + inner.width) |col| {
            buf.set(@intCast(col), row, .{ .char = '─', .style = .{} });
        }
    }

    /// Render navigation hints at the bottom
    fn renderNavHint(self: Wizard, buf: *Buffer, inner: Rect, nav_row: u16) void {
        // "← Back" on the left if not first
        if (!self.isFirst()) {
            const back_text = "← Back";
            var col: u16 = inner.x;
            for (back_text) |ch| {
                if (col >= inner.x + inner.width) break;
                buf.set(col, nav_row, .{ .char = ch, .style = self.nav_style });
                col += 1;
            }
        }

        // "Next →" on the right if not last
        if (!self.isLast()) {
            const next_text = "Next →";
            const text_start: u16 = if (inner.width >= next_text.len)
                inner.x + inner.width - @as(u16, @intCast(next_text.len))
            else
                inner.x;

            var col: u16 = text_start;
            for (next_text) |ch| {
                if (col >= inner.x + inner.width) break;
                buf.set(col, nav_row, .{ .char = ch, .style = self.nav_style });
                col += 1;
            }
        }
    }
};

// ============================================================================
// TESTS
// ============================================================================

const testing = std.testing;
const tui = @import("../tui.zig");
const Cell = tui.Cell;

test "Wizard sanity check" {
    var steps_arr: [1]Wizard.Step = .{
        .{ .title = "Test", .description = "" },
    };
    const wizard = Wizard.init(&steps_arr);

    try testing.expectEqual(@as(usize, 1), wizard.steps.len);
    try testing.expectEqual(@as(usize, 0), wizard.current);
}
