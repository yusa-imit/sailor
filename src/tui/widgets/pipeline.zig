//! Pipeline widget — linear CI/build stage visualization (v2.15.0)
//!
//! Renders a sequence of stages with status indicators and connectors.
//! Horizontal: [✓ Build] → [⊙ Test] → [· Deploy]
//! Vertical: stages stacked with connector lines between them.

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

/// Status indicator characters
const ICON_SUCCESS: u21 = '✓';
const ICON_FAILED: u21 = '✗';
const ICON_RUNNING: u21 = '⊙';
const ICON_PENDING: u21 = '·';
const ICON_SKIPPED: u21 = '⊘';

pub const Pipeline = struct {
    pub const StageStatus = enum {
        pending,
        running,
        success,
        failed,
        skipped,
    };

    pub const PipelineStage = struct {
        label: []const u8,
        status: StageStatus,
        /// Progress percentage (0-100), used when status == .running
        progress: u8 = 0,
    };

    stages: []const PipelineStage,
    direction: Direction = .horizontal,
    show_connectors: bool = true,
    style: Style = .{},

    /// Returns the count of stages with the given status.
    pub fn countByStatus(self: Pipeline, status: StageStatus) usize {
        var count: usize = 0;
        for (self.stages) |s| {
            if (s.status == status) count += 1;
        }
        return count;
    }

    /// Returns true if all stages are success or skipped.
    pub fn isComplete(self: Pipeline) bool {
        for (self.stages) |s| {
            switch (s.status) {
                .success, .skipped => {},
                else => return false,
            }
        }
        return true;
    }

    /// Returns true if any stage has failed status.
    pub fn hasFailed(self: Pipeline) bool {
        for (self.stages) |s| {
            if (s.status == .failed) return true;
        }
        return false;
    }

    /// Renders the pipeline into the buffer, clipped to area.
    pub fn render(self: Pipeline, buf: *Buffer, area: Rect) void {
        if (area.width == 0 or area.height == 0) return;
        if (self.stages.len == 0) return;

        switch (self.direction) {
            .horizontal => self.renderHorizontal(buf, area),
            .vertical => self.renderVertical(buf, area),
        }
    }

    fn renderHorizontal(self: Pipeline, buf: *Buffer, area: Rect) void {
        var cursor_x: u16 = area.x;
        const mid_y: u16 = area.y + area.height / 2;

        for (self.stages, 0..) |stage, idx| {
            if (cursor_x >= area.x + area.width) break;

            const stage_width = stageWidth(stage);
            const stage_end = cursor_x + stage_width;

            renderStageBox(buf, area, stage, cursor_x, mid_y, stage_width);

            cursor_x = stage_end;

            if (self.show_connectors and idx + 1 < self.stages.len) {
                if (cursor_x < area.x + area.width) {
                    setCell(buf, area, cursor_x, mid_y, '\u{2192}', self.style); // →
                    cursor_x += 1;
                }
            }
        }
    }

    fn renderVertical(self: Pipeline, buf: *Buffer, area: Rect) void {
        var cursor_y: u16 = area.y;

        for (self.stages, 0..) |stage, idx| {
            if (cursor_y >= area.y + area.height) break;

            const stage_width = stageWidth(stage);
            renderStageBox(buf, area, stage, area.x, cursor_y, stage_width);

            cursor_y += 1;

            if (self.show_connectors and idx + 1 < self.stages.len) {
                if (cursor_y < area.y + area.height) {
                    setCell(buf, area, area.x, cursor_y, '\u{2193}', self.style); // ↓
                    cursor_y += 1;
                }
            }
        }
    }

    fn stageWidth(stage: PipelineStage) u16 {
        // "[icon label]" = 1([) + 1(icon) + 1(space) + label.len + 1(]) = label.len + 4
        return @intCast(@min(65535, stage.label.len + 4));
    }

    fn stageStyle(stage: PipelineStage) Style {
        return switch (stage.status) {
            .success => Style{},
            .failed => Style{ .bold = true },
            .running => Style{},
            .pending => Style{ .dim = true },
            .skipped => Style{ .dim = true },
        };
    }

    fn stageIcon(stage: PipelineStage) u21 {
        return switch (stage.status) {
            .success => ICON_SUCCESS,
            .failed => ICON_FAILED,
            .running => ICON_RUNNING,
            .pending => ICON_PENDING,
            .skipped => ICON_SKIPPED,
        };
    }

    fn renderStageBox(buf: *Buffer, area: Rect, stage: PipelineStage, x: u16, y: u16, width: u16) void {
        if (y < area.y or y >= area.y + area.height) return;
        if (x >= area.x + area.width) return;

        const s = stageStyle(stage);
        const icon = stageIcon(stage);

        var cx = x;
        const max_x = area.x + area.width;

        if (cx < max_x) { setCell(buf, area, cx, y, '[', s); cx += 1; }
        if (cx < max_x) { setCell(buf, area, cx, y, icon, s); cx += 1; }
        if (cx < max_x) { setCell(buf, area, cx, y, ' ', s); cx += 1; }

        for (stage.label) |ch| {
            if (cx + 1 >= max_x) break;
            setCell(buf, area, cx, y, ch, s);
            cx += 1;
        }

        if (cx < max_x) { setCell(buf, area, cx, y, ']', s); }

        _ = width;
    }

    fn setCell(buf: *Buffer, area: Rect, abs_x: u16, abs_y: u16, char: u21, s: Style) void {
        if (abs_x < area.x or abs_x >= area.x + area.width) return;
        if (abs_y < area.y or abs_y >= area.y + area.height) return;
        buf.set(abs_x, abs_y, .{ .char = char, .style = s });
    }
};

