//! Accessibility Demo — Tab Navigation & Focus Management
//!
//! Demonstrates:
//! - Focus management across multiple widgets
//! - Tab navigation (Tab/Shift+Tab)
//! - Disabled widget skipping
//! - Multiple focus styles (default, subtle, highlighted, indicator)
//!
//! Run with: zig build example-accessibility_demo

const std = @import("std");
const sailor = @import("sailor");

const FocusManager = sailor.focus.FocusManager;
const FocusIndicator = sailor.focus.FocusIndicator;
const FocusStyle = sailor.focus.FocusStyle;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    std.debug.print("\n", .{});
    std.debug.print("╔════════════════════════════════════════════════════════════╗\n", .{});
    std.debug.print("║  Sailor Accessibility Demo — Tab Navigation & Focus       ║\n", .{});
    std.debug.print("╚════════════════════════════════════════════════════════════╝\n", .{});
    std.debug.print("\n", .{});

    // Create focus manager
    var focus_manager = FocusManager.init(allocator);
    defer focus_manager.deinit();

    // Register 5 widgets in tab order
    try focus_manager.register(1); // Widget 1
    try focus_manager.register(2); // Widget 2
    try focus_manager.register(3); // Widget 3 (starts disabled)
    try focus_manager.register(4); // Widget 4
    try focus_manager.register(5); // Widget 5

    // Widget 3 starts disabled
    try focus_manager.setDisabled(3, true);

    // Create focus indicators for each widget
    const indicators = [_]struct { name: []const u8, style: FocusStyle }{
        .{ .name = "Default", .style = FocusStyle.default() },
        .{ .name = "Subtle", .style = FocusStyle.subtle() },
        .{ .name = "Highlighted", .style = FocusStyle.highlighted() },
        .{ .name = "Indicator", .style = FocusStyle.withIndicator('>') },
        .{ .name = "Default", .style = FocusStyle.default() },
    };

    std.debug.print("Initial setup:\n", .{});
    std.debug.print("  - 5 widgets registered in tab order\n", .{});
    std.debug.print("  - Widget 3 is DISABLED (will be skipped)\n", .{});
    std.debug.print("  - Focus wrapping enabled (last → first)\n", .{});
    std.debug.print("\n", .{});

    for (indicators, 1..) |indicator, i| {
        const disabled = if (i == 3) " [DISABLED]" else "";
        std.debug.print("  Widget {d}: {s} focus style{s}\n", .{ i, indicator.name, disabled });
    }

    std.debug.print("\n", .{});
    std.debug.print("══════════════════════════════════════════════════════════════\n", .{});
    std.debug.print("\n", .{});

    std.debug.print("Initial state:\n", .{});
    printFocusState(&focus_manager, "  ");

    std.debug.print("\nTab navigation sequence:\n", .{});

    // Tab 1: 1 -> 2
    focus_manager.focusNext();
    std.debug.print("  [Tab] ", .{});
    printFocusState(&focus_manager, "");

    // Tab 2: 2 -> 4 (skips disabled widget 3)
    focus_manager.focusNext();
    std.debug.print("  [Tab] ", .{});
    printFocusState(&focus_manager, "");
    std.debug.print("         ^ Skipped Widget 3 (disabled)\n", .{});

    // Tab 3: 4 -> 5
    focus_manager.focusNext();
    std.debug.print("  [Tab] ", .{});
    printFocusState(&focus_manager, "");

    // Tab 4: 5 -> 1 (wraps around)
    focus_manager.focusNext();
    std.debug.print("  [Tab] ", .{});
    printFocusState(&focus_manager, "");
    std.debug.print("         ^ Wrapped around to first widget\n", .{});

    std.debug.print("\nShift+Tab (reverse) sequence:\n", .{});

    // Shift+Tab 1: 1 -> 5
    focus_manager.focusPrev();
    std.debug.print("  [Shift+Tab] ", .{});
    printFocusState(&focus_manager, "");

    // Shift+Tab 2: 5 -> 4
    focus_manager.focusPrev();
    std.debug.print("  [Shift+Tab] ", .{});
    printFocusState(&focus_manager, "");

    // Shift+Tab 3: 4 -> 2 (skips disabled widget 3)
    focus_manager.focusPrev();
    std.debug.print("  [Shift+Tab] ", .{});
    printFocusState(&focus_manager, "");
    std.debug.print("               ^ Skipped Widget 3 (disabled)\n", .{});

    std.debug.print("\nEnabling Widget 3:\n", .{});
    try focus_manager.setDisabled(3, false);
    std.debug.print("  Widget 3 is now enabled\n\n", .{});

    // Tab from 2 -> 3 (now enabled)
    focus_manager.focusNext();
    std.debug.print("  [Tab] ", .{});
    printFocusState(&focus_manager, "");
    std.debug.print("         ^ Widget 3 is now accessible\n", .{});

    std.debug.print("\n", .{});
    std.debug.print("══════════════════════════════════════════════════════════════\n", .{});
    std.debug.print("\n", .{});

    std.debug.print("Focus Styles:\n", .{});
    std.debug.print("  • Default:      Cyan border, bold\n", .{});
    std.debug.print("  • Subtle:       Blue border, no bold\n", .{});
    std.debug.print("  • Highlighted:  Yellow border + dark gray background\n", .{});
    std.debug.print("  • Indicator:    Cyan border + '>' arrow on left\n", .{});

    std.debug.print("\n", .{});
    std.debug.print("✓ Accessibility demo complete!\n", .{});
    std.debug.print("  Tab navigation: {d} widgets\n", .{focus_manager.count()});
    std.debug.print("  Disabled widgets are automatically skipped during navigation\n", .{});
    std.debug.print("  Focus wraps around (last → first, first → last)\n", .{});
    std.debug.print("\n", .{});
}

fn printFocusState(manager: *const FocusManager, prefix: []const u8) void {
    if (manager.focused_id) |id| {
        std.debug.print("{s}Focused: Widget {d}", .{ prefix, id });
        if (manager.isDisabled(id)) {
            std.debug.print(" [DISABLED]", .{});
        }
        std.debug.print("\n", .{});
    } else {
        std.debug.print("{s}No widget focused\n", .{prefix});
    }
}
