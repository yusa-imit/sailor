//! Layout Template Widgets — v2.18.0
//!
//! Pre-built TUI layouts:
//! - DashboardLayout: header + sidebar + main + footer
//! - MasterDetail: two-panel master/detail split with optional divider

const std = @import("std");
const buffer_mod = @import("../buffer.zig");
const Buffer = buffer_mod.Buffer;
const Cell = buffer_mod.Cell;
const layout_mod = @import("../layout.zig");
const Rect = layout_mod.Rect;
const style_mod = @import("../style.zig");
const Style = style_mod.Style;

/// Pre-built dashboard layout: header + sidebar + main content + footer
pub const DashboardLayout = struct {
    header_height: u16 = 3,
    footer_height: u16 = 1,
    sidebar_width: u16 = 20,

    /// Split area into four sections: header, sidebar, main, footer
    pub fn split(self: DashboardLayout, area: Rect) struct { header: Rect, sidebar: Rect, main: Rect, footer: Rect } {
        // Calculate available height and widths with clamping
        const available_height = area.height;
        const header_h = @min(self.header_height, available_height);
        const footer_h = @min(self.footer_height, available_height -| header_h);
        const body_h = available_height -| header_h -| footer_h;

        const sidebar_w = @min(self.sidebar_width, area.width);
        const main_w = area.width -| sidebar_w;

        return .{
            .header = Rect{
                .x = area.x,
                .y = area.y,
                .width = area.width,
                .height = header_h,
            },
            .sidebar = Rect{
                .x = area.x,
                .y = area.y + header_h,
                .width = sidebar_w,
                .height = body_h,
            },
            .main = Rect{
                .x = area.x + sidebar_w,
                .y = area.y + header_h,
                .width = main_w,
                .height = body_h,
            },
            .footer = Rect{
                .x = area.x,
                .y = area.y + header_h + body_h,
                .width = area.width,
                .height = footer_h,
            },
        };
    }

    /// Get the body area (excluding header and footer)
    pub fn body(self: DashboardLayout, area: Rect) Rect {
        const available_height = area.height;
        const header_h = @min(self.header_height, available_height);
        const footer_h = @min(self.footer_height, available_height -| header_h);
        const body_h = available_height -| header_h -| footer_h;

        return Rect{
            .x = area.x,
            .y = area.y + header_h,
            .width = area.width,
            .height = body_h,
        };
    }
};

/// Two-panel master/detail layout with optional divider
pub const MasterDetail = struct {
    master_width: u16 = 30,
    divider: bool = true,
    divider_style: Style = .{},

    /// Split area into master and detail panes
    pub fn split(self: MasterDetail, area: Rect) struct { master: Rect, detail: Rect } {
        const master_w = @min(self.master_width, area.width);
        const detail_w = area.width -| master_w;

        return .{
            .master = Rect{
                .x = area.x,
                .y = area.y,
                .width = master_w,
                .height = area.height,
            },
            .detail = Rect{
                .x = area.x + master_w,
                .y = area.y,
                .width = detail_w,
                .height = area.height,
            },
        };
    }

    /// Render divider between master and detail panels
    pub fn render(self: MasterDetail, buf: *Buffer, area: Rect) void {
        if (area.width == 0 or area.height == 0) return;
        if (!self.divider) return;

        const master_w = @min(self.master_width, area.width);

        // Draw vertical divider at (area.x + master_w - 1)
        if (master_w > 0 and master_w < area.width) {
            const divider_x = area.x + master_w - 1;
            var y = area.y;
            while (y < area.y + area.height) : (y += 1) {
                buf.set(divider_x, y, Cell{
                    .char = '│',
                    .style = self.divider_style,
                });
            }
        }
    }
};
