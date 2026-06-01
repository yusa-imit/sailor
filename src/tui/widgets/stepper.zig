//! Stepper Widget — v2.18.0
//!
//! Multi-step wizard/progress indicator with:
//! - Step navigation (moveNext, movePrev)
//! - Status tracking (pending, active, completed, failed)
//! - Horizontal/vertical rendering
//! - Customizable styles and block wrapping

const std = @import("std");
const buffer_mod = @import("../buffer.zig");
const Buffer = buffer_mod.Buffer;
const Cell = buffer_mod.Cell;
const layout_mod = @import("../layout.zig");
const Rect = layout_mod.Rect;
const Direction = layout_mod.Direction;
const style_mod = @import("../style.zig");
const Style = style_mod.Style;
const Color = style_mod.Color;
const Block = @import("block.zig").Block;

/// Step status enum
pub const StepStatus = enum {
    pending,
    active,
    completed,
    failed,
};

/// Single step in the stepper
pub const Step = struct {
    label: []const u8,
    status: StepStatus = .pending,
};

/// Multi-step widget for wizards and progress indication
pub const Stepper = struct {
    steps: []Step = &.{},
    current: usize = 0,
    direction: Direction = .horizontal,

    pending_style: Style = .{ .fg = .bright_black },
    active_style: Style = .{ .bold = true },
    completed_style: Style = .{ .fg = .green },
    failed_style: Style = .{ .fg = .red },
    connector_style: Style = .{ .fg = .bright_black },

    block: ?Block = null,

    /// Move to next step (clamped to last)
    pub fn moveNext(self: *Stepper) void {
        if (self.steps.len == 0) return;
        if (self.current < self.steps.len - 1) {
            self.current += 1;
        }
    }

    /// Move to previous step (clamped to 0)
    pub fn movePrev(self: *Stepper) void {
        if (self.current > 0) {
            self.current -= 1;
        }
    }

    /// Set status of a step by index
    pub fn setStatus(self: *Stepper, step_idx: usize, status: StepStatus) void {
        if (step_idx >= self.steps.len) return;
        self.steps[step_idx].status = status;
    }

    /// Check if all steps are completed
    pub fn isComplete(self: Stepper) bool {
        if (self.steps.len == 0) return true; // Empty is complete (vacuous truth)
        for (self.steps) |step| {
            if (step.status != .completed) return false;
        }
        return true;
    }

    /// Check if any step has failed
    pub fn hasFailed(self: Stepper) bool {
        for (self.steps) |step| {
            if (step.status == .failed) return true;
        }
        return false;
    }

    /// Get current step, or null if no steps or current out of bounds
    pub fn currentStep(self: Stepper) ?Step {
        if (self.steps.len == 0) return null;
        const idx = @min(self.current, self.steps.len - 1);
        return self.steps[idx];
    }

    /// Render the stepper into the buffer
    pub fn render(self: Stepper, buf: *Buffer, area: Rect) void {
        if (area.width == 0 or area.height == 0) return;
        if (self.steps.len == 0) return;

        // Render block border if present
        if (self.block) |blk| {
            blk.render(buf, area);
        }

        switch (self.direction) {
            .horizontal => self.renderHorizontal(buf, area),
            .vertical => self.renderVertical(buf, area),
        }
    }

    /// Add block to stepper (builder pattern)
    pub fn withBlock(self: Stepper, block: Block) Stepper {
        var result = self;
        result.block = block;
        return result;
    }

    /// Set direction (builder pattern)
    pub fn withDirection(self: Stepper, dir: Direction) Stepper {
        var result = self;
        result.direction = dir;
        return result;
    }

    // =========================================================================
    // Private rendering methods
    // =========================================================================

    fn renderHorizontal(self: Stepper, buf: *Buffer, area: Rect) void {
        var cursor_x: u16 = area.x;
        const y: u16 = area.y + area.height / 2;

        for (self.steps, 0..) |step, idx| {
            if (cursor_x >= area.x + area.width) break;

            // Render step icon
            const icon = self.stepIcon(step);
            const style = self.statusStyle(step.status);
            buf.set(cursor_x, y, Cell{ .char = icon, .style = style });
            cursor_x += 1;

            // Render label (truncated if needed)
            const label_space = area.x + area.width -| cursor_x;
            const label_len = @min(step.label.len, label_space);
            if (label_len > 0) {
                buf.setString(cursor_x, y, step.label[0..label_len], style);
                cursor_x += @intCast(label_len);
            }

            // Render connector
            if (idx + 1 < self.steps.len and cursor_x < area.x + area.width) {
                buf.set(cursor_x, y, Cell{
                    .char = ' ',
                    .style = self.connector_style,
                });
                cursor_x += 1;
            }
        }
    }

    fn renderVertical(self: Stepper, buf: *Buffer, area: Rect) void {
        var cursor_y: u16 = area.y;

        for (self.steps, 0..) |step, idx| {
            if (cursor_y >= area.y + area.height) break;

            // Render step icon + label
            const icon = self.stepIcon(step);
            const style = self.statusStyle(step.status);
            buf.set(area.x, cursor_y, Cell{ .char = icon, .style = style });

            // Render label
            const label_space = area.x + area.width -| (area.x + 1);
            const label_len = @min(step.label.len, label_space);
            if (label_len > 0 and area.x + 1 < area.x + area.width) {
                buf.setString(area.x + 1, cursor_y, step.label[0..label_len], style);
            }

            cursor_y += 1;

            // Render connector line between steps
            if (idx + 1 < self.steps.len and cursor_y < area.y + area.height) {
                buf.set(area.x, cursor_y, Cell{
                    .char = '│',
                    .style = self.connector_style,
                });
                cursor_y += 1;
            }
        }
    }

    fn stepIcon(self: Stepper, step: Step) u21 {
        _ = self;
        return switch (step.status) {
            .pending => '○',
            .active => '●',
            .completed => '✓',
            .failed => '✗',
        };
    }

    fn statusStyle(self: Stepper, status: StepStatus) Style {
        return switch (status) {
            .pending => self.pending_style,
            .active => self.active_style,
            .completed => self.completed_style,
            .failed => self.failed_style,
        };
    }
};
