//! Pagination Widget — Page navigation control
//!
//! A horizontal page navigator displaying: < 1 2 [3] 4 5 ... 10 >
//! - Navigation: nextPage, prevPage, goToPage, goToFirst, goToLast
//! - Truncation: shows max_visible_pages slots with ... ellipsis for large counts
//! - Builder API: withBlock, withStyle, withSelectedStyle, withArrowStyle, withMaxVisiblePages
//! - No allocator needed — pure value type

const std = @import("std");
const Buffer = @import("../buffer.zig").Buffer;
const Rect = @import("../layout.zig").Rect;
const Style = @import("../style.zig").Style;
const Block = @import("block.zig").Block;

/// Pagination widget for page navigation
pub const Pagination = struct {
    total_pages: usize,
    current_page: usize,
    max_visible_pages: usize,
    block: ?Block = null,
    style: Style = .{},
    selected_style: Style = .{},
    arrow_style: Style = .{},

    /// Initialize pagination with total page count
    pub fn init(total_pages: usize) Pagination {
        return Pagination{
            .total_pages = total_pages,
            .current_page = 0,
            .max_visible_pages = 7,
            .block = null,
            .style = .{},
            .selected_style = .{},
            .arrow_style = .{},
        };
    }

    /// Advance to next page (clamps at total_pages - 1)
    pub fn nextPage(self: *Pagination) void {
        if (self.total_pages == 0) return;
        if (self.current_page < self.total_pages - 1) {
            self.current_page += 1;
        }
    }

    /// Go back to previous page (clamps at 0)
    pub fn prevPage(self: *Pagination) void {
        if (self.current_page > 0) {
            self.current_page -= 1;
        }
    }

    /// Go to specific page (clamped to valid range)
    pub fn goToPage(self: *Pagination, page: usize) void {
        if (self.total_pages == 0) {
            self.current_page = 0;
        } else {
            self.current_page = @min(page, self.total_pages - 1);
        }
    }

    /// Go to first page (page 0)
    pub fn goToFirst(self: *Pagination) void {
        self.current_page = 0;
    }

    /// Go to last page
    pub fn goToLast(self: *Pagination) void {
        if (self.total_pages == 0) {
            self.current_page = 0;
        } else {
            self.current_page = self.total_pages - 1;
        }
    }

    /// Builder: set block
    pub fn withBlock(self: Pagination, block: Block) Pagination {
        var result = self;
        result.block = block;
        return result;
    }

    /// Builder: set style
    pub fn withStyle(self: Pagination, style: Style) Pagination {
        var result = self;
        result.style = style;
        return result;
    }

    /// Builder: set selected_style
    pub fn withSelectedStyle(self: Pagination, style: Style) Pagination {
        var result = self;
        result.selected_style = style;
        return result;
    }

    /// Builder: set arrow_style
    pub fn withArrowStyle(self: Pagination, style: Style) Pagination {
        var result = self;
        result.arrow_style = style;
        return result;
    }

    /// Builder: set max_visible_pages
    pub fn withMaxVisiblePages(self: Pagination, n: usize) Pagination {
        var result = self;
        result.max_visible_pages = n;
        return result;
    }

    /// Render pagination to buffer
    pub fn render(self: Pagination, buf: *Buffer, area: Rect) void {
        // Early returns for invalid areas
        if (area.width == 0 or area.height == 0) return;

        // Determine render area (apply block border if set)
        var inner_area = area;
        if (self.block) |block| {
            block.render(buf, area);
            // Get inner area by applying border width
            if (area.x + 1 < area.x + area.width and area.y + 1 < area.y + area.height) {
                inner_area = Rect{
                    .x = area.x + 1,
                    .y = area.y + 1,
                    .width = if (area.width > 2) area.width - 2 else 0,
                    .height = if (area.height > 2) area.height - 2 else 0,
                };
            } else {
                return; // No space for content
            }
        }

        if (inner_area.width == 0 or inner_area.height == 0) return;

        // Render on middle row of area
        const render_y = inner_area.y + inner_area.height / 2;
        var render_x: u16 = inner_area.x;
        const max_render_x = inner_area.x + inner_area.width;

        // Render left arrow
        if (render_x < max_render_x) {
            const arrow_str = if (self.current_page == 0) "  " else "< ";
            const arrow_style_to_use = if (self.current_page == 0)
                Style{ .dim = true }
            else
                self.arrow_style;
            buf.setString(render_x, render_y, arrow_str, arrow_style_to_use);
            render_x += 2;
        }

        // Determine visible page range
        var pages_buffer: [100]usize = undefined; // Stack buffer to avoid allocator
        var page_count: usize = 0;

        if (self.total_pages == 0) {
            // No pages to show
        } else if (self.total_pages <= self.max_visible_pages) {
            // Show all pages
            for (0..self.total_pages) |i| {
                if (page_count < pages_buffer.len) {
                    pages_buffer[page_count] = i;
                    page_count += 1;
                }
            }
        } else {
            // Show subset with truncation
            const half_visible = self.max_visible_pages / 2;
            var window_start: usize = 0;
            var window_end: usize = self.max_visible_pages;

            // Center window around current_page
            if (self.current_page >= half_visible) {
                window_start = self.current_page - half_visible;
            }
            if (window_start + self.max_visible_pages > self.total_pages) {
                window_start = self.total_pages - self.max_visible_pages;
            }
            window_end = window_start + self.max_visible_pages;

            // Add start ellipsis if needed
            if (window_start > 0) {
                if (page_count < pages_buffer.len) {
                    pages_buffer[page_count] = 0; // Always show first page
                    page_count += 1;
                }
            }

            // Add middle pages
            for (window_start..window_end) |i| {
                if (i < self.total_pages and page_count < pages_buffer.len) {
                    pages_buffer[page_count] = i;
                    page_count += 1;
                }
            }

            // Add end ellipsis if needed
            if (window_end < self.total_pages) {
                if (page_count < pages_buffer.len) {
                    pages_buffer[page_count] = self.total_pages - 1;
                    page_count += 1;
                }
            }
        }

        // Render page numbers with spaces
        var i: usize = 0;
        while (i < page_count and render_x < max_render_x) : (i += 1) {
            const page_num = pages_buffer[i];
            const page_display = page_num + 1; // Convert to 1-indexed for display

            // Build page text with brackets for selected
            var page_text: [16]u8 = undefined;
            var page_text_len: usize = 0;

            if (page_num == self.current_page) {
                // Selected page: [N]
                if (std.fmt.bufPrint(page_text[0..], "[{d}]", .{page_display})) |s| {
                    page_text_len = s.len;
                } else |_| {
                    page_text_len = 0;
                }
            } else {
                // Unselected page: N
                if (std.fmt.bufPrint(page_text[0..], "{d}", .{page_display})) |s| {
                    page_text_len = s.len;
                } else |_| {
                    page_text_len = 0;
                }
            }

            if (page_text_len > 0 and render_x < max_render_x) {
                const style_to_use = if (page_num == self.current_page)
                    self.selected_style
                else
                    self.style;

                buf.setString(render_x, render_y, page_text[0..page_text_len], style_to_use);
                render_x += @as(u16, @intCast(page_text_len));
            }

            // Add space after page number (except last)
            if (i < page_count - 1 and render_x < max_render_x) {
                buf.setString(render_x, render_y, " ", self.style);
                render_x += 1;
            }

            // Check for ellipsis (when page numbers aren't consecutive)
            if (i < page_count - 1) {
                const next_page = pages_buffer[i + 1];
                if (next_page > page_num + 1 and render_x < max_render_x) {
                    buf.setString(render_x, render_y, "... ", self.style);
                    render_x += 4;
                }
            }
        }

        // Render right arrow
        if (render_x + 2 <= max_render_x) {
            const is_last = self.total_pages == 0 or self.current_page == self.total_pages - 1;
            const arrow_str = if (is_last) "  " else " >";
            const arrow_style_to_use = if (is_last)
                Style{ .dim = true }
            else
                self.arrow_style;
            buf.setString(render_x, render_y, arrow_str, arrow_style_to_use);
        }
    }
};
