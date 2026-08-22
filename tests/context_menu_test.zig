//! ContextMenu Widget Tests
//!
//! Comprehensive test coverage for the ContextMenu widget supporting:
//! - Initialization and builder pattern
//! - Navigation (moveDown/moveUp with wrap-around)
//! - Separator and disabled item handling
//! - Item counting and selection
//! - Rendering and area fitting

const std = @import("std");
const testing = std.testing;
const sailor = @import("sailor");

const Buffer = sailor.tui.buffer.Buffer;
const Rect = sailor.tui.layout.Rect;
const Style = sailor.tui.style.Style;
const Color = sailor.tui.style.Color;
const ContextMenu = sailor.tui.widgets.ContextMenu;
const Block = sailor.tui.widgets.Block;

// ============================================================================
// INITIALIZATION TESTS
// ============================================================================

test "ContextMenu init creates menu with default cursor at zero" {
    const items = [_]ContextMenu.Item{
        .{ .action = .{ .label = "Save", .enabled = true } },
        .{ .action = .{ .label = "Exit", .enabled = true } },
    };
    const menu = ContextMenu.init(&items);
    try testing.expectEqual(@as(usize, 0), menu.cursor);
}

test "ContextMenu init default origin at zero" {
    const items = [_]ContextMenu.Item{
        .{ .action = .{ .label = "A", .enabled = true } },
    };
    const menu = ContextMenu.init(&items);
    try testing.expectEqual(@as(u16, 0), menu.origin_x);
    try testing.expectEqual(@as(u16, 0), menu.origin_y);
}

test "ContextMenu init block is null" {
    const items = [_]ContextMenu.Item{
        .{ .action = .{ .label = "A", .enabled = true } },
    };
    const menu = ContextMenu.init(&items);
    try testing.expectEqual(null, menu.block);
}

test "ContextMenu init item_style defaults to false" {
    const items = [_]ContextMenu.Item{
        .{ .action = .{ .label = "A", .enabled = true } },
    };
    const menu = ContextMenu.init(&items);
    try testing.expectEqual(false, menu.item_style.bold);
}

test "ContextMenu init selected_style defaults to bold and reversed" {
    const items = [_]ContextMenu.Item{
        .{ .action = .{ .label = "A", .enabled = true } },
    };
    const menu = ContextMenu.init(&items);
    try testing.expectEqual(true, menu.selected_style.bold);
    try testing.expectEqual(true, menu.selected_style.reverse);
}

test "ContextMenu init disabled_style defaults to dim" {
    const items = [_]ContextMenu.Item{
        .{ .action = .{ .label = "A", .enabled = true } },
    };
    const menu = ContextMenu.init(&items);
    try testing.expectEqual(true, menu.disabled_style.dim);
}

test "ContextMenu init with empty items list" {
    const items: [0]ContextMenu.Item = .{};
    const menu = ContextMenu.init(&items);
    try testing.expectEqual(@as(usize, 0), menu.cursor);
    try testing.expectEqual(@as(usize, 0), menu.items.len);
}

test "ContextMenu init with single item" {
    const items = [_]ContextMenu.Item{
        .{ .action = .{ .label = "Only", .enabled = true } },
    };
    const menu = ContextMenu.init(&items);
    try testing.expectEqual(@as(usize, 1), menu.items.len);
}

test "ContextMenu init stores items reference" {
    const items = [_]ContextMenu.Item{
        .{ .action = .{ .label = "First", .enabled = true } },
        .{ .action = .{ .label = "Second", .enabled = true } },
    };
    const menu = ContextMenu.init(&items);
    try testing.expectEqual(@as(usize, 2), menu.items.len);
}

// ============================================================================
// BUILDER PATTERN TESTS
// ============================================================================

test "ContextMenu withOrigin sets x coordinate" {
    const items = [_]ContextMenu.Item{
        .{ .action = .{ .label = "A", .enabled = true } },
    };
    var menu = ContextMenu.init(&items);
    menu = menu.withOrigin(15, 0);
    try testing.expectEqual(@as(u16, 15), menu.origin_x);
}

test "ContextMenu withOrigin sets y coordinate" {
    const items = [_]ContextMenu.Item{
        .{ .action = .{ .label = "A", .enabled = true } },
    };
    var menu = ContextMenu.init(&items);
    menu = menu.withOrigin(0, 8);
    try testing.expectEqual(@as(u16, 8), menu.origin_y);
}

test "ContextMenu withOrigin sets both coordinates" {
    const items = [_]ContextMenu.Item{
        .{ .action = .{ .label = "A", .enabled = true } },
    };
    var menu = ContextMenu.init(&items);
    menu = menu.withOrigin(10, 5);
    try testing.expectEqual(@as(u16, 10), menu.origin_x);
    try testing.expectEqual(@as(u16, 5), menu.origin_y);
}

test "ContextMenu withBlock attaches block" {
    const items = [_]ContextMenu.Item{
        .{ .action = .{ .label = "A", .enabled = true } },
    };
    var menu = ContextMenu.init(&items);
    const block = Block{};
    menu = menu.withBlock(block);
    try testing.expect(menu.block != null);
}

test "ContextMenu withItemStyle sets item style" {
    const items = [_]ContextMenu.Item{
        .{ .action = .{ .label = "A", .enabled = true } },
    };
    var menu = ContextMenu.init(&items);
    const style = Style{ .bold = true, .fg = Color.red };
    menu = menu.withItemStyle(style);
    try testing.expectEqual(true, menu.item_style.bold);
}

test "ContextMenu withSelectedStyle sets selected style" {
    const items = [_]ContextMenu.Item{
        .{ .action = .{ .label = "A", .enabled = true } },
    };
    var menu = ContextMenu.init(&items);
    const style = Style{ .reverse = false };
    menu = menu.withSelectedStyle(style);
    try testing.expectEqual(false, menu.selected_style.reverse);
}

test "ContextMenu withDisabledStyle sets disabled style" {
    const items = [_]ContextMenu.Item{
        .{ .action = .{ .label = "A", .enabled = true } },
    };
    var menu = ContextMenu.init(&items);
    const style = Style{ .dim = false };
    menu = menu.withDisabledStyle(style);
    try testing.expectEqual(false, menu.disabled_style.dim);
}

test "ContextMenu withShortcutStyle sets shortcut style" {
    const items = [_]ContextMenu.Item{
        .{ .action = .{ .label = "A", .enabled = true } },
    };
    var menu = ContextMenu.init(&items);
    const style = Style{ .bold = true };
    menu = menu.withShortcutStyle(style);
    try testing.expectEqual(true, menu.shortcut_style.bold);
}

test "ContextMenu withCursor sets cursor position" {
    const items = [_]ContextMenu.Item{
        .{ .action = .{ .label = "A", .enabled = true } },
        .{ .action = .{ .label = "B", .enabled = true } },
        .{ .action = .{ .label = "C", .enabled = true } },
    };
    var menu = ContextMenu.init(&items);
    menu = menu.withCursor(2);
    try testing.expectEqual(@as(usize, 2), menu.cursor);
}

test "ContextMenu builder pattern chaining" {
    const items = [_]ContextMenu.Item{
        .{ .action = .{ .label = "A", .enabled = true } },
    };
    const menu = ContextMenu.init(&items)
        .withOrigin(5, 10)
        .withCursor(0)
        .withItemStyle(.{ .bold = false });

    try testing.expectEqual(@as(u16, 5), menu.origin_x);
    try testing.expectEqual(@as(u16, 10), menu.origin_y);
    try testing.expectEqual(@as(usize, 0), menu.cursor);
}

// ============================================================================
// ACTION COUNT TESTS
// ============================================================================

test "ContextMenu actionCount with only actions" {
    const items = [_]ContextMenu.Item{
        .{ .action = .{ .label = "A", .enabled = true } },
        .{ .action = .{ .label = "B", .enabled = true } },
        .{ .action = .{ .label = "C", .enabled = true } },
    };
    const menu = ContextMenu.init(&items);
    try testing.expectEqual(@as(usize, 3), menu.actionCount());
}

test "ContextMenu actionCount excludes separators" {
    const items = [_]ContextMenu.Item{
        .{ .action = .{ .label = "A", .enabled = true } },
        .{ .separator = {} },
        .{ .action = .{ .label = "B", .enabled = true } },
    };
    const menu = ContextMenu.init(&items);
    try testing.expectEqual(@as(usize, 2), menu.actionCount());
}

test "ContextMenu actionCount includes submenus" {
    const items = [_]ContextMenu.Item{
        .{ .action = .{ .label = "A", .enabled = true } },
        .{ .submenu = .{ .label = "Sub", .items = &.{} } },
    };
    const menu = ContextMenu.init(&items);
    try testing.expectEqual(@as(usize, 2), menu.actionCount());
}

test "ContextMenu actionCount with multiple separators" {
    const items = [_]ContextMenu.Item{
        .{ .action = .{ .label = "A", .enabled = true } },
        .{ .separator = {} },
        .{ .action = .{ .label = "B", .enabled = true } },
        .{ .separator = {} },
        .{ .action = .{ .label = "C", .enabled = true } },
    };
    const menu = ContextMenu.init(&items);
    try testing.expectEqual(@as(usize, 3), menu.actionCount());
}

test "ContextMenu actionCount empty items" {
    const items: [0]ContextMenu.Item = .{};
    const menu = ContextMenu.init(&items);
    try testing.expectEqual(@as(usize, 0), menu.actionCount());
}

test "ContextMenu actionCount all separators" {
    const items = [_]ContextMenu.Item{
        .{ .separator = {} },
        .{ .separator = {} },
        .{ .separator = {} },
    };
    const menu = ContextMenu.init(&items);
    try testing.expectEqual(@as(usize, 0), menu.actionCount());
}

test "ContextMenu actionCount disabled items still count" {
    const items = [_]ContextMenu.Item{
        .{ .action = .{ .label = "A", .enabled = true } },
        .{ .action = .{ .label = "B", .enabled = false } },
    };
    const menu = ContextMenu.init(&items);
    try testing.expectEqual(@as(usize, 2), menu.actionCount());
}

// ============================================================================
// MOVE DOWN TESTS
// ============================================================================

test "ContextMenu moveDown advances cursor by one" {
    const items = [_]ContextMenu.Item{
        .{ .action = .{ .label = "A", .enabled = true } },
        .{ .action = .{ .label = "B", .enabled = true } },
        .{ .action = .{ .label = "C", .enabled = true } },
    };
    var menu = ContextMenu.init(&items);
    menu = menu.moveDown();
    try testing.expectEqual(@as(usize, 1), menu.cursor);
}

test "ContextMenu moveDown multiple times" {
    const items = [_]ContextMenu.Item{
        .{ .action = .{ .label = "A", .enabled = true } },
        .{ .action = .{ .label = "B", .enabled = true } },
        .{ .action = .{ .label = "C", .enabled = true } },
    };
    var menu = ContextMenu.init(&items);
    menu = menu.moveDown().moveDown();
    try testing.expectEqual(@as(usize, 2), menu.cursor);
}

test "ContextMenu moveDown wraps from last to first" {
    const items = [_]ContextMenu.Item{
        .{ .action = .{ .label = "A", .enabled = true } },
        .{ .action = .{ .label = "B", .enabled = true } },
    };
    var menu = ContextMenu.init(&items).withCursor(1);
    menu = menu.moveDown();
    try testing.expectEqual(@as(usize, 0), menu.cursor);
}

test "ContextMenu moveDown skips separator" {
    const items = [_]ContextMenu.Item{
        .{ .action = .{ .label = "A", .enabled = true } },
        .{ .separator = {} },
        .{ .action = .{ .label = "B", .enabled = true } },
    };
    var menu = ContextMenu.init(&items);
    menu = menu.moveDown();
    try testing.expectEqual(@as(usize, 2), menu.cursor);
}

test "ContextMenu moveDown skips disabled action" {
    const items = [_]ContextMenu.Item{
        .{ .action = .{ .label = "A", .enabled = true } },
        .{ .action = .{ .label = "B", .enabled = false } },
        .{ .action = .{ .label = "C", .enabled = true } },
    };
    var menu = ContextMenu.init(&items);
    menu = menu.moveDown();
    try testing.expectEqual(@as(usize, 2), menu.cursor);
}

test "ContextMenu moveDown skips multiple separators" {
    const items = [_]ContextMenu.Item{
        .{ .action = .{ .label = "A", .enabled = true } },
        .{ .separator = {} },
        .{ .separator = {} },
        .{ .action = .{ .label = "B", .enabled = true } },
    };
    var menu = ContextMenu.init(&items);
    menu = menu.moveDown();
    try testing.expectEqual(@as(usize, 3), menu.cursor);
}

test "ContextMenu moveDown with empty items stays at zero" {
    const items: [0]ContextMenu.Item = .{};
    var menu = ContextMenu.init(&items);
    menu = menu.moveDown();
    try testing.expectEqual(@as(usize, 0), menu.cursor);
}

test "ContextMenu moveDown single action item stays at zero" {
    const items = [_]ContextMenu.Item{
        .{ .action = .{ .label = "Only", .enabled = true } },
    };
    var menu = ContextMenu.init(&items);
    menu = menu.moveDown();
    try testing.expectEqual(@as(usize, 0), menu.cursor);
}

test "ContextMenu moveDown all separators stays at zero" {
    const items = [_]ContextMenu.Item{
        .{ .separator = {} },
        .{ .separator = {} },
    };
    var menu = ContextMenu.init(&items);
    menu = menu.moveDown();
    try testing.expectEqual(@as(usize, 0), menu.cursor);
}

test "ContextMenu moveDown finds submenu after disabled action" {
    const items = [_]ContextMenu.Item{
        .{ .action = .{ .label = "A", .enabled = true } },
        .{ .action = .{ .label = "B", .enabled = false } },
        .{ .submenu = .{ .label = "Sub", .items = &.{} } },
    };
    var menu = ContextMenu.init(&items);
    menu = menu.moveDown();
    try testing.expectEqual(@as(usize, 2), menu.cursor);
}

// ============================================================================
// MOVE UP TESTS
// ============================================================================

test "ContextMenu moveUp moves cursor back by one" {
    const items = [_]ContextMenu.Item{
        .{ .action = .{ .label = "A", .enabled = true } },
        .{ .action = .{ .label = "B", .enabled = true } },
        .{ .action = .{ .label = "C", .enabled = true } },
    };
    var menu = ContextMenu.init(&items).withCursor(2);
    menu = menu.moveUp();
    try testing.expectEqual(@as(usize, 1), menu.cursor);
}

test "ContextMenu moveUp multiple times" {
    const items = [_]ContextMenu.Item{
        .{ .action = .{ .label = "A", .enabled = true } },
        .{ .action = .{ .label = "B", .enabled = true } },
        .{ .action = .{ .label = "C", .enabled = true } },
    };
    var menu = ContextMenu.init(&items).withCursor(2);
    menu = menu.moveUp().moveUp();
    try testing.expectEqual(@as(usize, 0), menu.cursor);
}

test "ContextMenu moveUp wraps from first to last" {
    const items = [_]ContextMenu.Item{
        .{ .action = .{ .label = "A", .enabled = true } },
        .{ .action = .{ .label = "B", .enabled = true } },
    };
    var menu = ContextMenu.init(&items).withCursor(0);
    menu = menu.moveUp();
    try testing.expectEqual(@as(usize, 1), menu.cursor);
}

test "ContextMenu moveUp skips separator" {
    const items = [_]ContextMenu.Item{
        .{ .action = .{ .label = "A", .enabled = true } },
        .{ .separator = {} },
        .{ .action = .{ .label = "B", .enabled = true } },
    };
    var menu = ContextMenu.init(&items).withCursor(2);
    menu = menu.moveUp();
    try testing.expectEqual(@as(usize, 0), menu.cursor);
}

test "ContextMenu moveUp skips disabled action" {
    const items = [_]ContextMenu.Item{
        .{ .action = .{ .label = "A", .enabled = true } },
        .{ .action = .{ .label = "B", .enabled = false } },
        .{ .action = .{ .label = "C", .enabled = true } },
    };
    var menu = ContextMenu.init(&items).withCursor(2);
    menu = menu.moveUp();
    try testing.expectEqual(@as(usize, 0), menu.cursor);
}

test "ContextMenu moveUp skips multiple separators" {
    const items = [_]ContextMenu.Item{
        .{ .action = .{ .label = "A", .enabled = true } },
        .{ .separator = {} },
        .{ .separator = {} },
        .{ .action = .{ .label = "B", .enabled = true } },
    };
    var menu = ContextMenu.init(&items).withCursor(3);
    menu = menu.moveUp();
    try testing.expectEqual(@as(usize, 0), menu.cursor);
}

test "ContextMenu moveUp with empty items stays at zero" {
    const items: [0]ContextMenu.Item = .{};
    var menu = ContextMenu.init(&items);
    menu = menu.moveUp();
    try testing.expectEqual(@as(usize, 0), menu.cursor);
}

test "ContextMenu moveUp single action item stays at zero" {
    const items = [_]ContextMenu.Item{
        .{ .action = .{ .label = "Only", .enabled = true } },
    };
    var menu = ContextMenu.init(&items);
    menu = menu.moveUp();
    try testing.expectEqual(@as(usize, 0), menu.cursor);
}

test "ContextMenu moveUp all separators stays at zero" {
    const items = [_]ContextMenu.Item{
        .{ .separator = {} },
        .{ .separator = {} },
    };
    var menu = ContextMenu.init(&items);
    menu = menu.moveUp();
    try testing.expectEqual(@as(usize, 0), menu.cursor);
}

// ============================================================================
// CURRENT ITEM TESTS
// ============================================================================

test "ContextMenu currentItem returns action at cursor" {
    const items = [_]ContextMenu.Item{
        .{ .action = .{ .label = "First", .enabled = true } },
    };
    const menu = ContextMenu.init(&items);
    const item = menu.currentItem();
    try testing.expect(item != null);
}

test "ContextMenu currentItem returns separator at cursor" {
    const items = [_]ContextMenu.Item{
        .{ .separator = {} },
    };
    const menu = ContextMenu.init(&items);
    const item = menu.currentItem();
    try testing.expect(item != null);
}

test "ContextMenu currentItem returns submenu at cursor" {
    const items = [_]ContextMenu.Item{
        .{ .submenu = .{ .label = "Sub", .items = &.{} } },
    };
    const menu = ContextMenu.init(&items);
    const item = menu.currentItem();
    try testing.expect(item != null);
}

test "ContextMenu currentItem null when cursor out of bounds" {
    const items = [_]ContextMenu.Item{
        .{ .action = .{ .label = "A", .enabled = true } },
    };
    var menu = ContextMenu.init(&items);
    menu.cursor = 10;
    const item = menu.currentItem();
    try testing.expectEqual(null, item);
}

test "ContextMenu currentItem at different positions" {
    const items = [_]ContextMenu.Item{
        .{ .action = .{ .label = "A", .enabled = true } },
        .{ .action = .{ .label = "B", .enabled = true } },
        .{ .action = .{ .label = "C", .enabled = true } },
    };
    var menu = ContextMenu.init(&items);
    try testing.expect(menu.currentItem() != null);
    menu = menu.moveDown();
    try testing.expect(menu.currentItem() != null);
    menu = menu.moveDown();
    try testing.expect(menu.currentItem() != null);
}

// ============================================================================
// IS CURRENT SELECTABLE TESTS
// ============================================================================

test "ContextMenu isCurrentSelectable true for enabled action" {
    const items = [_]ContextMenu.Item{
        .{ .action = .{ .label = "A", .enabled = true } },
    };
    const menu = ContextMenu.init(&items);
    try testing.expect(menu.isCurrentSelectable());
}

test "ContextMenu isCurrentSelectable false for disabled action" {
    const items = [_]ContextMenu.Item{
        .{ .action = .{ .label = "A", .enabled = false } },
    };
    const menu = ContextMenu.init(&items);
    try testing.expect(!menu.isCurrentSelectable());
}

test "ContextMenu isCurrentSelectable true for submenu" {
    const items = [_]ContextMenu.Item{
        .{ .submenu = .{ .label = "Sub", .items = &.{} } },
    };
    const menu = ContextMenu.init(&items);
    try testing.expect(menu.isCurrentSelectable());
}

test "ContextMenu isCurrentSelectable false for separator" {
    const items = [_]ContextMenu.Item{
        .{ .separator = {} },
    };
    const menu = ContextMenu.init(&items);
    try testing.expect(!menu.isCurrentSelectable());
}

test "ContextMenu isCurrentSelectable false when cursor out of bounds" {
    const items = [_]ContextMenu.Item{
        .{ .action = .{ .label = "A", .enabled = true } },
    };
    var menu = ContextMenu.init(&items);
    menu.cursor = 100;
    try testing.expect(!menu.isCurrentSelectable());
}

test "ContextMenu isCurrentSelectable at different positions" {
    const items = [_]ContextMenu.Item{
        .{ .action = .{ .label = "A", .enabled = true } },
        .{ .separator = {} },
        .{ .action = .{ .label = "B", .enabled = true } },
    };
    var menu = ContextMenu.init(&items);
    try testing.expect(menu.isCurrentSelectable());
    menu = menu.moveDown();
    try testing.expect(menu.isCurrentSelectable()); // Now at position 2, which is enabled
    menu = menu.moveDown();
    try testing.expect(menu.isCurrentSelectable()); // Wrapped back to position 0
}

// ============================================================================
// FITTING AREA TESTS
// ============================================================================

test "ContextMenu fittingArea at origin within screen" {
    const items = [_]ContextMenu.Item{
        .{ .action = .{ .label = "A", .enabled = true } },
    };
    const menu = ContextMenu.init(&items).withOrigin(5, 5);
    const screen = Rect{ .x = 0, .y = 0, .width = 100, .height = 100 };
    const area = menu.fittingArea(screen);
    try testing.expectEqual(@as(u16, 5), area.x);
    try testing.expectEqual(@as(u16, 5), area.y);
}

test "ContextMenu fittingArea height includes items and border" {
    const items = [_]ContextMenu.Item{
        .{ .action = .{ .label = "A", .enabled = true } },
        .{ .action = .{ .label = "B", .enabled = true } },
        .{ .action = .{ .label = "C", .enabled = true } },
    };
    const menu = ContextMenu.init(&items);
    const screen = Rect{ .x = 0, .y = 0, .width = 100, .height = 100 };
    const area = menu.fittingArea(screen);
    try testing.expectEqual(@as(u16, 5), area.height);
}

test "ContextMenu fittingArea clamps x to screen width" {
    const items = [_]ContextMenu.Item{
        .{ .action = .{ .label = "A", .enabled = true } },
    };
    var menu = ContextMenu.init(&items);
    menu = menu.withOrigin(80, 10);
    const screen = Rect{ .x = 0, .y = 0, .width = 100, .height = 100 };
    const area = menu.fittingArea(screen);
    try testing.expect(area.x + area.width <= screen.x + screen.width);
}

test "ContextMenu fittingArea clamps y to screen height" {
    const items = [_]ContextMenu.Item{
        .{ .action = .{ .label = "A", .enabled = true } },
        .{ .action = .{ .label = "B", .enabled = true } },
        .{ .action = .{ .label = "C", .enabled = true } },
    };
    var menu = ContextMenu.init(&items);
    menu = menu.withOrigin(10, 90);
    const screen = Rect{ .x = 0, .y = 0, .width = 100, .height = 100 };
    const area = menu.fittingArea(screen);
    try testing.expect(area.y + area.height <= screen.y + screen.height);
}

test "ContextMenu fittingArea with zero screen size" {
    const items = [_]ContextMenu.Item{
        .{ .action = .{ .label = "A", .enabled = true } },
    };
    var menu = ContextMenu.init(&items);
    menu = menu.withOrigin(0, 0);
    const screen = Rect{ .x = 0, .y = 0, .width = 0, .height = 0 };
    const area = menu.fittingArea(screen);
    try testing.expectEqual(@as(u16, 0), area.x);
}

test "ContextMenu fittingArea respects origin" {
    const items = [_]ContextMenu.Item{
        .{ .action = .{ .label = "A", .enabled = true } },
    };
    const menu = ContextMenu.init(&items).withOrigin(25, 30);
    const screen = Rect{ .x = 0, .y = 0, .width = 200, .height = 200 };
    const area = menu.fittingArea(screen);
    try testing.expectEqual(@as(u16, 25), area.x);
    try testing.expectEqual(@as(u16, 30), area.y);
}

// ============================================================================
// RENDERING TESTS
// ============================================================================

test "ContextMenu render does not crash with empty items" {
    const items: [0]ContextMenu.Item = .{};
    const menu = ContextMenu.init(&items);
    var buf = try Buffer.init(testing.allocator, 10, 10);
    defer buf.deinit();
    const area = Rect{ .x = 0, .y = 0, .width = 10, .height = 10 };
    menu.render(&buf, area);
}

test "ContextMenu render does not crash with narrow area" {
    const items = [_]ContextMenu.Item{
        .{ .action = .{ .label = "A", .enabled = true } },
    };
    const menu = ContextMenu.init(&items);
    var buf = try Buffer.init(testing.allocator, 3, 10);
    defer buf.deinit();
    const area = Rect{ .x = 0, .y = 0, .width = 3, .height = 5 };
    menu.render(&buf, area);
}

test "ContextMenu render with single action" {
    const items = [_]ContextMenu.Item{
        .{ .action = .{ .label = "Single Action", .shortcut = "Ctrl+S", .enabled = true } },
    };
    const menu = ContextMenu.init(&items);
    var buf = try Buffer.init(testing.allocator, 50, 10);
    defer buf.deinit();
    const area = Rect{ .x = 0, .y = 0, .width = 50, .height = 10 };
    menu.render(&buf, area);
}

test "ContextMenu render with multiple items" {
    const items = [_]ContextMenu.Item{
        .{ .action = .{ .label = "Cut", .shortcut = "Ctrl+X", .enabled = true } },
        .{ .action = .{ .label = "Copy", .shortcut = "Ctrl+C", .enabled = true } },
        .{ .action = .{ .label = "Paste", .shortcut = "Ctrl+V", .enabled = true } },
    };
    const menu = ContextMenu.init(&items);
    var buf = try Buffer.init(testing.allocator, 80, 20);
    defer buf.deinit();
    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 20 };
    menu.render(&buf, area);
}

test "ContextMenu render with separator" {
    const items = [_]ContextMenu.Item{
        .{ .action = .{ .label = "Cut", .enabled = true } },
        .{ .separator = {} },
        .{ .action = .{ .label = "Delete", .enabled = true } },
    };
    const menu = ContextMenu.init(&items);
    var buf = try Buffer.init(testing.allocator, 50, 15);
    defer buf.deinit();
    const area = Rect{ .x = 0, .y = 0, .width = 50, .height = 15 };
    menu.render(&buf, area);
}

test "ContextMenu render with disabled items" {
    const items = [_]ContextMenu.Item{
        .{ .action = .{ .label = "Cut", .enabled = true } },
        .{ .action = .{ .label = "Copy", .enabled = false } },
        .{ .action = .{ .label = "Paste", .enabled = false } },
    };
    const menu = ContextMenu.init(&items);
    var buf = try Buffer.init(testing.allocator, 50, 15);
    defer buf.deinit();
    const area = Rect{ .x = 0, .y = 0, .width = 50, .height = 15 };
    menu.render(&buf, area);
}

test "ContextMenu render with submenu" {
    const sub_items = [_]ContextMenu.Item{
        .{ .action = .{ .label = "Sub1", .enabled = true } },
    };
    const items = [_]ContextMenu.Item{
        .{ .action = .{ .label = "File", .enabled = true } },
        .{ .submenu = .{ .label = "Edit", .items = &sub_items } },
    };
    const menu = ContextMenu.init(&items);
    var buf = try Buffer.init(testing.allocator, 50, 10);
    defer buf.deinit();
    const area = Rect{ .x = 0, .y = 0, .width = 50, .height = 10 };
    menu.render(&buf, area);
}

test "ContextMenu render with shortcuts" {
    const items = [_]ContextMenu.Item{
        .{ .action = .{ .label = "Save", .shortcut = "Ctrl+S", .enabled = true } },
        .{ .action = .{ .label = "Undo", .shortcut = "Ctrl+Z", .enabled = true } },
    };
    const menu = ContextMenu.init(&items);
    var buf = try Buffer.init(testing.allocator, 80, 15);
    defer buf.deinit();
    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 15 };
    menu.render(&buf, area);
}

test "ContextMenu render without shortcuts" {
    const items = [_]ContextMenu.Item{
        .{ .action = .{ .label = "Save", .shortcut = null, .enabled = true } },
        .{ .action = .{ .label = "Undo", .shortcut = null, .enabled = true } },
    };
    const menu = ContextMenu.init(&items);
    var buf = try Buffer.init(testing.allocator, 50, 15);
    defer buf.deinit();
    const area = Rect{ .x = 0, .y = 0, .width = 50, .height = 15 };
    menu.render(&buf, area);
}

test "ContextMenu render at non-zero position" {
    const items = [_]ContextMenu.Item{
        .{ .action = .{ .label = "A", .enabled = true } },
    };
    const menu = ContextMenu.init(&items);
    var buf = try Buffer.init(testing.allocator, 100, 100);
    defer buf.deinit();
    const area = Rect{ .x = 10, .y = 5, .width = 50, .height = 10 };
    menu.render(&buf, area);
}

test "ContextMenu render with complex structure" {
    const items = [_]ContextMenu.Item{
        .{ .action = .{ .label = "File", .enabled = true } },
        .{ .action = .{ .label = "Edit", .enabled = true } },
        .{ .separator = {} },
        .{ .action = .{ .label = "View", .enabled = true } },
        .{ .action = .{ .label = "Options", .enabled = false } },
        .{ .separator = {} },
        .{ .action = .{ .label = "Exit", .shortcut = "Alt+F4", .enabled = true } },
    };
    const menu = ContextMenu.init(&items);
    var buf = try Buffer.init(testing.allocator, 100, 50);
    defer buf.deinit();
    const area = Rect{ .x = 0, .y = 0, .width = 100, .height = 50 };
    menu.render(&buf, area);
}

// ============================================================================
// ACTION ITEM TESTS
// ============================================================================

test "ContextMenu Action with label and shortcut" {
    const action = ContextMenu.Action{
        .label = "Save",
        .shortcut = "Ctrl+S",
        .enabled = true,
    };
    try testing.expectEqualStrings("Save", action.label);
    try testing.expectEqualStrings("Ctrl+S", action.shortcut.?);
    try testing.expect(action.enabled);
}

test "ContextMenu Action with label only" {
    const action = ContextMenu.Action{
        .label = "Delete",
        .enabled = true,
    };
    try testing.expectEqualStrings("Delete", action.label);
    try testing.expectEqual(null, action.shortcut);
    try testing.expect(action.enabled);
}

test "ContextMenu Action disabled" {
    const action = ContextMenu.Action{
        .label = "Grayed Out",
        .enabled = false,
    };
    try testing.expectEqualStrings("Grayed Out", action.label);
    try testing.expect(!action.enabled);
}

// ============================================================================
// SUBMENU TESTS
// ============================================================================

test "ContextMenu Submenu with items" {
    const sub_items = [_]ContextMenu.Item{
        .{ .action = .{ .label = "Sub1", .enabled = true } },
        .{ .action = .{ .label = "Sub2", .enabled = true } },
    };
    const submenu = ContextMenu.Submenu{
        .label = "Edit",
        .items = &sub_items,
    };
    try testing.expectEqualStrings("Edit", submenu.label);
    try testing.expectEqual(@as(usize, 2), submenu.items.len);
}

test "ContextMenu Submenu with empty items" {
    const submenu = ContextMenu.Submenu{
        .label = "Empty",
        .items = &.{},
    };
    try testing.expectEqualStrings("Empty", submenu.label);
    try testing.expectEqual(@as(usize, 0), submenu.items.len);
}

test "ContextMenu Submenu with nested separators" {
    const sub_items = [_]ContextMenu.Item{
        .{ .action = .{ .label = "Sub1", .enabled = true } },
        .{ .separator = {} },
        .{ .action = .{ .label = "Sub2", .enabled = true } },
    };
    const submenu = ContextMenu.Submenu{
        .label = "Nested",
        .items = &sub_items,
    };
    try testing.expectEqual(@as(usize, 3), submenu.items.len);
}

// ============================================================================
// REGRESSION TESTS FOR U16 OVERFLOW BUGS IN FITTING AREA
// ============================================================================
// These tests reproduce the u16 overflow bug in fittingArea() at lines 235 and 238
// when computing area.x + area.width or area.y + area.height with extreme origin values.
// The bug: origin_x/origin_y (public u16 fields with withOrigin builder) are copied directly
// to area.x/area.y with no clamp, then used in unguarded + comparisons that overflow u16 max.
// See toast_manager.zig and block.zig for already-fixed same bug class and regression test patterns.

test "ContextMenu.fittingArea with origin_x near u16::MAX and positive width completes without panic on area.x + area.width" {
    const items = [_]ContextMenu.Item{
        .{ .action = .{ .label = "A", .enabled = true } },
    };
    const menu = ContextMenu.init(&items).withOrigin(65535, 0);
    // area.x = 65535, area.width will be >= 10 (minimum width)
    // Comparison: 65535 + 10 = 65545 (overflows u16 max of 65535)
    // This triggers line 235: if (area.x + area.width > screen.x + screen.width)
    const screen = Rect{ .x = 0, .y = 0, .width = 100, .height = 100 };
    const area = menu.fittingArea(screen); // Should not panic with u16 overflow
    // After fix with saturating arithmetic: area.x is clamped to screen bounds
    // Derivation: area.x +| area.width (65535 +| 10) > screen.x +| screen.width (0 +| 100)?
    // Yes (65535 > 100), so clamp: area.x = max(0, 0 + 100 - 10) = 90
    try testing.expectEqual(@as(u16, 90), area.x);
    try testing.expectEqual(@as(u16, 0), area.y);
}

test "ContextMenu.fittingArea with origin_y near u16::MAX and positive height completes without panic on area.y + area.height" {
    const items = [_]ContextMenu.Item{
        .{ .action = .{ .label = "A", .enabled = true } },
        .{ .action = .{ .label = "B", .enabled = true } },
    };
    const menu = ContextMenu.init(&items).withOrigin(0, 65535);
    // area.y = 65535, area.height will be >= 4 (2 items + 2 borders = 4)
    // Comparison: 65535 + 4 = 65539 (overflows u16 max of 65535)
    // This triggers line 238: if (area.y + area.height > screen.y + screen.height)
    const screen = Rect{ .x = 0, .y = 0, .width = 100, .height = 100 };
    const area = menu.fittingArea(screen); // Should not panic with u16 overflow
    // After fix with saturating arithmetic: area.y is clamped to screen bounds
    // Derivation: area.y +| area.height (65535 +| 4) > screen.y +| screen.height (0 +| 100)?
    // Yes (65535 > 100), so clamp: area.y = max(0, 0 + 100 - 4) = 96
    try testing.expectEqual(@as(u16, 0), area.x);
    try testing.expectEqual(@as(u16, 96), area.y);
}

test "ContextMenu.fittingArea with both origin_x and origin_y near u16::MAX completes without panic on both comparisons" {
    const items = [_]ContextMenu.Item{
        .{ .action = .{ .label = "A", .enabled = true } },
    };
    const menu = ContextMenu.init(&items).withOrigin(65535, 65535);
    // Both area.x and area.y at u16::MAX, both + their dimensions will overflow
    // This triggers both line 235 and line 238
    const screen = Rect{ .x = 0, .y = 0, .width = 100, .height = 100 };
    const area = menu.fittingArea(screen); // Should not panic with u16 overflow on either axis
    // After fix with saturating arithmetic: both axes are clamped to screen bounds
    // Derivation: area.x +| 10 (65535 +| 10) > 0 +| 100? Yes, so area.x = max(0, 100-10) = 90
    //            area.y +| 3 (65535 +| 3) > 0 +| 100? Yes, so area.y = max(0, 100-3) = 97
    try testing.expectEqual(@as(u16, 90), area.x);
    try testing.expectEqual(@as(u16, 97), area.y);
    try testing.expectEqual(@as(u16, 3), area.height); // 1 item, so min height is 3, capped to screen (100)
}

test "ContextMenu.fittingArea with origin_x near MAX and small screen.width completes without panic" {
    const items = [_]ContextMenu.Item{
        .{ .action = .{ .label = "A", .enabled = true } },
    };
    const menu = ContextMenu.init(&items).withOrigin(65530, 10);
    // area.x = 65530, area.width >= 10
    // area.x + area.width = 65540 (overflows u16 max 65535)
    // screen.x + screen.width = 0 + 20 = 20
    const screen = Rect{ .x = 0, .y = 0, .width = 20, .height = 100 };
    const area = menu.fittingArea(screen); // Should not panic with u16 overflow
    // After fix with saturating arithmetic: area.x is clamped to screen bounds
    // Derivation: area.x +| area.width (65530 +| 10) > screen.x +| screen.width (0 +| 20)?
    // Yes (65530 > 20), so clamp: area.x = max(0, 0 + 20 - 10) = 10
    try testing.expectEqual(@as(u16, 10), area.x);
}

test "ContextMenu.fittingArea with origin_y near MAX and small screen.height completes without panic" {
    const items = [_]ContextMenu.Item{
        .{ .action = .{ .label = "A", .enabled = true } },
        .{ .action = .{ .label = "B", .enabled = true } },
    };
    const menu = ContextMenu.init(&items).withOrigin(10, 65530);
    // area.y = 65530, area.height >= 4 (2 items + 2 borders)
    // area.y + area.height = 65534 (near u16 max 65535)
    // screen.y + screen.height = 0 + 10 = 10
    const screen = Rect{ .x = 0, .y = 0, .width = 100, .height = 10 };
    const area = menu.fittingArea(screen); // Should not panic with u16 overflow
    // After fix with saturating arithmetic: area.y is clamped to screen bounds
    // Derivation: area.y +| area.height (65530 +| 4) > screen.y +| screen.height (0 +| 10)?
    // Yes (65530 > 10), so clamp: area.y = max(0, 0 + 10 - 4) = 6
    try testing.expectEqual(@as(u16, 6), area.y);
}

test "ContextMenu.fittingArea with screen.x + screen.width overflow completes without panic" {
    const items = [_]ContextMenu.Item{
        .{ .action = .{ .label = "A", .enabled = true } },
    };
    const menu = ContextMenu.init(&items).withOrigin(10, 10);
    // screen.x + screen.width = 65530 + 100 = 65630 (overflows u16 max 65535)
    // This triggers line 235: if (area.x + area.width > screen.x + screen.width)
    const screen = Rect{ .x = 65530, .y = 0, .width = 100, .height = 100 };
    const area = menu.fittingArea(screen); // Should not panic with u16 overflow in screen bounds check
    // After fix: should complete without panic even if screen coords overflow
    try testing.expectEqual(@as(u16, 10), area.x); // Menu origin unchanged since comparison itself is safe
}

test "ContextMenu.fittingArea with screen.y + screen.height overflow completes without panic" {
    const items = [_]ContextMenu.Item{
        .{ .action = .{ .label = "A", .enabled = true } },
    };
    const menu = ContextMenu.init(&items).withOrigin(10, 10);
    // screen.y + screen.height = 65530 + 100 = 65630 (overflows u16 max 65535)
    // This triggers line 238: if (area.y + area.height > screen.y + screen.height)
    const screen = Rect{ .x = 0, .y = 65530, .width = 100, .height = 100 };
    const area = menu.fittingArea(screen); // Should not panic with u16 overflow in screen bounds check
    // After fix: should complete without panic even if screen coords overflow
    try testing.expectEqual(@as(u16, 10), area.y); // Menu origin unchanged since comparison itself is safe
}

test "ContextMenu.fittingArea post-fix returns sensible result when origin_x saturates" {
    const items = [_]ContextMenu.Item{
        .{ .action = .{ .label = "A", .enabled = true } },
    };
    const menu = ContextMenu.init(&items).withOrigin(65535, 5);
    const screen = Rect{ .x = 0, .y = 0, .width = 80, .height = 100 };
    const area = menu.fittingArea(screen);
    // After fix with saturating arithmetic, result should have:
    // - sensible dimensions (width, height > 0 or = 0)
    // - x + width does not overflow or panics
    try testing.expect(area.width > 0); // Menu width should be sensible
    try testing.expect(area.height > 0); // Menu height should be sensible
}

test "ContextMenu.fittingArea post-fix returns sensible result when origin_y saturates" {
    const items = [_]ContextMenu.Item{
        .{ .action = .{ .label = "A", .enabled = true } },
    };
    const menu = ContextMenu.init(&items).withOrigin(5, 65535);
    const screen = Rect{ .x = 0, .y = 0, .width = 100, .height = 24 };
    const area = menu.fittingArea(screen);
    // After fix with saturating arithmetic, result should have:
    // - sensible dimensions (width, height > 0 or = 0)
    // - y + height does not overflow or panics
    try testing.expect(area.width > 0); // Menu width should be sensible
    try testing.expect(area.height > 0); // Menu height should be sensible
}
