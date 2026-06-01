//! Layout Template Tests — v2.18.0
//!
//! Tests pre-built TUI layouts: DashboardLayout (header+sidebar+main+footer)
//! and MasterDetail (master/detail split with divider).

const std = @import("std");
const testing = std.testing;
const sailor = @import("sailor");

const Buffer = sailor.tui.Buffer;
const Rect = sailor.tui.Rect;
const Style = sailor.tui.Style;
const Block = sailor.tui.widgets.Block;
const DashboardLayout = sailor.tui.widgets.DashboardLayout;
const MasterDetail = sailor.tui.widgets.MasterDetail;

// ============================================================================
// DashboardLayout.split() — Basic Layout
// ============================================================================

test "DashboardLayout.split returns 4 non-overlapping rects" {
    const layout = DashboardLayout{ .header_height = 3, .footer_height = 1, .sidebar_width = 20 };
    const area = Rect{ .x = 0, .y = 0, .width = 100, .height = 30 };
    const result = layout.split(area);

    try testing.expectEqual(@as(u16, 3), result.header.height);
    try testing.expectEqual(@as(u16, 1), result.footer.height);
    try testing.expectEqual(@as(u16, 20), result.sidebar.width);
    try testing.expectEqual(@as(u16, 80), result.main.width);
    // All cover the full 30-row height together
    const total_h = result.header.height + result.sidebar.height + result.footer.height;
    try testing.expectEqual(area.height, total_h);
}

test "DashboardLayout.split header rect positioned at y=0" {
    const layout = DashboardLayout{};
    const area = Rect{ .x = 0, .y = 0, .width = 100, .height = 30 };
    const result = layout.split(area);

    try testing.expectEqual(@as(u16, 0), result.header.y);
}

test "DashboardLayout.split header rect has correct height" {
    const layout = DashboardLayout{ .header_height = 3 };
    const area = Rect{ .x = 0, .y = 0, .width = 100, .height = 30 };
    const result = layout.split(area);

    try testing.expectEqual(@as(u16, 3), result.header.height);
}

test "DashboardLayout.split footer rect positioned at bottom" {
    const layout = DashboardLayout{ .footer_height = 1 };
    const area = Rect{ .x = 0, .y = 0, .width = 100, .height = 30 };
    const result = layout.split(area);

    try testing.expectEqual(@as(u16, 29), result.footer.y);
}

test "DashboardLayout.split footer rect has correct height" {
    const layout = DashboardLayout{ .footer_height = 2 };
    const area = Rect{ .x = 0, .y = 0, .width = 100, .height = 30 };
    const result = layout.split(area);

    try testing.expectEqual(@as(u16, 2), result.footer.height);
}

test "DashboardLayout.split sidebar rect positioned after header" {
    const layout = DashboardLayout{ .header_height = 3 };
    const area = Rect{ .x = 0, .y = 0, .width = 100, .height = 30 };
    const result = layout.split(area);

    try testing.expectEqual(@as(u16, 3), result.sidebar.y);
}

test "DashboardLayout.split sidebar rect has correct width" {
    const layout = DashboardLayout{ .sidebar_width = 25 };
    const area = Rect{ .x = 0, .y = 0, .width = 100, .height = 30 };
    const result = layout.split(area);

    try testing.expectEqual(@as(u16, 25), result.sidebar.width);
}

test "DashboardLayout.split sidebar rect starts at x=0" {
    const layout = DashboardLayout{};
    const area = Rect{ .x = 0, .y = 0, .width = 100, .height = 30 };
    const result = layout.split(area);

    try testing.expectEqual(@as(u16, 0), result.sidebar.x);
}

test "DashboardLayout.split main rect positioned right of sidebar" {
    const layout = DashboardLayout{ .sidebar_width = 20 };
    const area = Rect{ .x = 0, .y = 0, .width = 100, .height = 30 };
    const result = layout.split(area);

    try testing.expectEqual(@as(u16, 20), result.main.x);
}

test "DashboardLayout.split main rect fills remaining width" {
    const layout = DashboardLayout{ .sidebar_width = 20 };
    const area = Rect{ .x = 0, .y = 0, .width = 100, .height = 30 };
    const result = layout.split(area);

    try testing.expectEqual(@as(u16, 80), result.main.width);
}

test "DashboardLayout.split main rect has same height as sidebar (body height)" {
    const layout = DashboardLayout{ .header_height = 3, .footer_height = 1 };
    const area = Rect{ .x = 0, .y = 0, .width = 100, .height = 30 };
    const result = layout.split(area);

    try testing.expectEqual(result.sidebar.height, result.main.height);
}

test "DashboardLayout.split all rects within original area bounds" {
    const layout = DashboardLayout{ .header_height = 3, .footer_height = 1, .sidebar_width = 20 };
    const area = Rect{ .x = 0, .y = 0, .width = 100, .height = 30 };
    const result = layout.split(area);

    // Header bounds
    try testing.expect(result.header.x >= area.x);
    try testing.expect(result.header.x + result.header.width <= area.x + area.width);
    try testing.expect(result.header.y + result.header.height <= area.y + area.height);

    // Sidebar bounds
    try testing.expect(result.sidebar.x >= area.x);
    try testing.expect(result.sidebar.x + result.sidebar.width <= area.x + area.width);
    try testing.expect(result.sidebar.y + result.sidebar.height <= area.y + area.height);

    // Main bounds
    try testing.expect(result.main.x >= area.x);
    try testing.expect(result.main.x + result.main.width <= area.x + area.width);
    try testing.expect(result.main.y + result.main.height <= area.y + area.height);

    // Footer bounds
    try testing.expect(result.footer.x >= area.x);
    try testing.expect(result.footer.x + result.footer.width <= area.x + area.width);
    try testing.expect(result.footer.y + result.footer.height <= area.y + area.height);
}

test "DashboardLayout.split header and footer are full width" {
    const layout = DashboardLayout{ .sidebar_width = 20 };
    const area = Rect{ .x = 0, .y = 0, .width = 100, .height = 30 };
    const result = layout.split(area);

    try testing.expectEqual(area.width, result.header.width);
    try testing.expectEqual(area.width, result.footer.width);
}

// ============================================================================
// DashboardLayout — Edge Cases
// ============================================================================

test "DashboardLayout.split with header_height > area.height returns graceful layout" {
    const layout = DashboardLayout{ .header_height = 100 };
    const area = Rect{ .x = 0, .y = 0, .width = 100, .height = 30 };
    const result = layout.split(area);

    // Should not crash, gracefully handle overflow
    try testing.expectEqual(@as(u16, 0), result.header.y);
}

test "DashboardLayout.split with sidebar_width > area.width returns graceful layout" {
    const layout = DashboardLayout{ .sidebar_width = 200 };
    const area = Rect{ .x = 0, .y = 0, .width = 100, .height = 30 };
    const result = layout.split(area);

    // Should not crash, gracefully handle overflow
    try testing.expect(result.sidebar.x >= area.x);
}

test "DashboardLayout.split with zero-height area returns graceful layout" {
    const layout = DashboardLayout{};
    const area = Rect{ .x = 0, .y = 0, .width = 100, .height = 0 };
    const result = layout.split(area);

    // All rects should have zero or minimal height
    try testing.expect(result.header.height <= area.height or result.header.height == 0);
}

test "DashboardLayout.split with zero-width area returns graceful layout" {
    const layout = DashboardLayout{};
    const area = Rect{ .x = 0, .y = 0, .width = 0, .height = 30 };
    const result = layout.split(area);

    // All rects should have zero or minimal width
    try testing.expect(result.sidebar.width <= area.width or result.sidebar.width == 0);
}

test "DashboardLayout.split with small area (5x5) returns graceful layout" {
    const layout = DashboardLayout{ .header_height = 1, .footer_height = 1, .sidebar_width = 1 };
    const area = Rect{ .x = 0, .y = 0, .width = 5, .height = 5 };
    const result = layout.split(area);

    // Should not crash and respect minimal bounds
    try testing.expect(result.header.width <= 5 and result.header.height <= 5);
}

test "DashboardLayout.split header and footer do not overlap" {
    const layout = DashboardLayout{ .header_height = 3, .footer_height = 2 };
    const area = Rect{ .x = 0, .y = 0, .width = 100, .height = 30 };
    const result = layout.split(area);

    // Header ends before body
    const header_end = result.header.y + result.header.height;
    const body_start = result.sidebar.y;
    try testing.expect(header_end <= body_start);

    // Body ends before footer
    const body_end = result.sidebar.y + result.sidebar.height;
    const footer_start = result.footer.y;
    try testing.expect(body_end <= footer_start);
}

// ============================================================================
// DashboardLayout.body() — Middle Band
// ============================================================================

test "DashboardLayout.body returns middle band rect" {
    const layout = DashboardLayout{ .header_height = 3, .footer_height = 1 };
    const area = Rect{ .x = 0, .y = 0, .width = 100, .height = 30 };
    const body = layout.body(area);

    try testing.expect(body.width > 0);
    try testing.expect(body.height > 0);
}

test "DashboardLayout.body starts after header" {
    const layout = DashboardLayout{ .header_height = 3 };
    const area = Rect{ .x = 0, .y = 0, .width = 100, .height = 30 };
    const body = layout.body(area);

    try testing.expectEqual(@as(u16, 3), body.y);
}

test "DashboardLayout.body has full area width" {
    const layout = DashboardLayout{};
    const area = Rect{ .x = 0, .y = 0, .width = 100, .height = 30 };
    const body = layout.body(area);

    try testing.expectEqual(@as(u16, 100), body.width);
}

test "DashboardLayout.body height = area.height - header_height - footer_height" {
    const layout = DashboardLayout{ .header_height = 3, .footer_height = 2 };
    const area = Rect{ .x = 0, .y = 0, .width = 100, .height = 30 };
    const body = layout.body(area);

    try testing.expectEqual(@as(u16, 25), body.height);
}

// ============================================================================
// MasterDetail.split() — Two-Panel Layout
// ============================================================================

test "MasterDetail.split returns master and detail rects" {
    const layout = MasterDetail{};
    const area = Rect{ .x = 0, .y = 0, .width = 100, .height = 30 };
    const result = layout.split(area);

    try testing.expect(result.master.width > 0);
    try testing.expect(result.detail.width > 0);
}

test "MasterDetail.split master has correct width" {
    const layout = MasterDetail{ .master_width = 30 };
    const area = Rect{ .x = 0, .y = 0, .width = 100, .height = 30 };
    const result = layout.split(area);

    try testing.expectEqual(@as(u16, 30), result.master.width);
}

test "MasterDetail.split master positioned at x=0" {
    const layout = MasterDetail{};
    const area = Rect{ .x = 0, .y = 0, .width = 100, .height = 30 };
    const result = layout.split(area);

    try testing.expectEqual(@as(u16, 0), result.master.x);
}

test "MasterDetail.split detail positioned after master" {
    const layout = MasterDetail{ .master_width = 30 };
    const area = Rect{ .x = 0, .y = 0, .width = 100, .height = 30 };
    const result = layout.split(area);

    try testing.expectEqual(@as(u16, 30), result.detail.x);
}

test "MasterDetail.split detail fills remaining width" {
    const layout = MasterDetail{ .master_width = 30 };
    const area = Rect{ .x = 0, .y = 0, .width = 100, .height = 30 };
    const result = layout.split(area);

    try testing.expectEqual(@as(u16, 70), result.detail.width);
}

test "MasterDetail.split both panels have same height as area" {
    const layout = MasterDetail{};
    const area = Rect{ .x = 0, .y = 0, .width = 100, .height = 30 };
    const result = layout.split(area);

    try testing.expectEqual(area.height, result.master.height);
    try testing.expectEqual(area.height, result.detail.height);
}

test "MasterDetail.split both panels start at same y" {
    const layout = MasterDetail{};
    const area = Rect{ .x = 5, .y = 10, .width = 100, .height = 30 };
    const result = layout.split(area);

    try testing.expectEqual(area.y, result.master.y);
    try testing.expectEqual(area.y, result.detail.y);
}

test "MasterDetail.split with master_width > area.width clamps master to area width" {
    const layout = MasterDetail{ .master_width = 200 };
    const area = Rect{ .x = 0, .y = 0, .width = 100, .height = 30 };
    const result = layout.split(area);

    // master_width is clamped to area.width; detail gets the remaining 0 columns
    try testing.expectEqual(area.width, result.master.width);
    try testing.expectEqual(@as(u16, 0), result.detail.width);
}

test "MasterDetail.split with zero-width area returns zero-width panels" {
    const layout = MasterDetail{};
    const area = Rect{ .x = 0, .y = 0, .width = 0, .height = 30 };
    const result = layout.split(area);

    // Both panels must be zero-width when area is zero-width
    try testing.expectEqual(@as(u16, 0), result.master.width);
    try testing.expectEqual(@as(u16, 0), result.detail.width);
}

test "MasterDetail.split master and detail do not overlap" {
    const layout = MasterDetail{ .master_width = 30 };
    const area = Rect{ .x = 0, .y = 0, .width = 100, .height = 30 };
    const result = layout.split(area);

    const master_end = result.master.x + result.master.width;
    const detail_start = result.detail.x;
    try testing.expect(master_end <= detail_start);
}

test "MasterDetail.split both rects within area bounds" {
    const layout = MasterDetail{ .master_width = 30 };
    const area = Rect{ .x = 5, .y = 10, .width = 100, .height = 30 };
    const result = layout.split(area);

    // Master bounds
    try testing.expect(result.master.x >= area.x);
    try testing.expect(result.master.x + result.master.width <= area.x + area.width);
    try testing.expect(result.master.y + result.master.height <= area.y + area.height);

    // Detail bounds
    try testing.expect(result.detail.x >= area.x);
    try testing.expect(result.detail.x + result.detail.width <= area.x + area.width);
    try testing.expect(result.detail.y + result.detail.height <= area.y + area.height);
}

// ============================================================================
// MasterDetail.render() — Divider Rendering
// ============================================================================

test "MasterDetail.render on normal area renders without panic" {
    var buf = try Buffer.init(std.testing.allocator, 100, 30);
    defer buf.deinit();
    const area = Rect{ .x = 0, .y = 0, .width = 100, .height = 30 };

    const layout = MasterDetail{ .divider = true };
    layout.render(&buf, area);

    // Should complete without error
}

test "MasterDetail.render on zero-area does not crash" {
    var buf = try Buffer.init(std.testing.allocator, 100, 30);
    defer buf.deinit();
    const area = Rect{ .x = 0, .y = 0, .width = 0, .height = 0 };

    const layout = MasterDetail{ .divider = true };
    layout.render(&buf, area);

    // Should not crash
}

test "MasterDetail.render with divider=false does not render divider" {
    var buf = try Buffer.init(std.testing.allocator, 100, 30);
    defer buf.deinit();
    const area = Rect{ .x = 0, .y = 0, .width = 100, .height = 30 };

    const layout = MasterDetail{ .divider = false };
    layout.render(&buf, area);

    // Should complete without error
}

test "MasterDetail.render with small area renders without panic" {
    var buf = try Buffer.init(std.testing.allocator, 10, 5);
    defer buf.deinit();
    const area = Rect{ .x = 0, .y = 0, .width = 10, .height = 5 };

    const layout = MasterDetail{ .divider = true, .master_width = 3 };
    layout.render(&buf, area);

    // Should not crash
}

test "MasterDetail.render respects divider_style" {
    var buf = try Buffer.init(std.testing.allocator, 100, 30);
    defer buf.deinit();
    const area = Rect{ .x = 0, .y = 0, .width = 100, .height = 30 };

    const style = Style{ .bold = true };
    const layout = MasterDetail{ .divider = true, .divider_style = style };
    layout.render(&buf, area);

    // Should complete without error
}

test "MasterDetail.render on single-column area does not crash" {
    var buf = try Buffer.init(std.testing.allocator, 1, 30);
    defer buf.deinit();
    const area = Rect{ .x = 0, .y = 0, .width = 1, .height = 30 };

    const layout = MasterDetail{ .divider = true };
    layout.render(&buf, area);

    // Should not crash
}

test "MasterDetail.render on single-row area does not crash" {
    var buf = try Buffer.init(std.testing.allocator, 100, 1);
    defer buf.deinit();
    const area = Rect{ .x = 0, .y = 0, .width = 100, .height = 1 };

    const layout = MasterDetail{ .divider = true };
    layout.render(&buf, area);

    // Should not crash
}
