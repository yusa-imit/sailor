const std = @import("std");
const testing = std.testing;
const sailor = @import("sailor");

const SplitPane = sailor.tui.widgets.SplitPane;
const Direction = sailor.tui.layout.Direction;
const Rect = sailor.tui.Rect;

test "SplitPane init defaults" {
    const pane = SplitPane.init();

    try testing.expectEqual(Direction.horizontal, pane.direction);
    try testing.expectEqual(@as(f64, 0.5), pane.split_ratio);
    try testing.expect(pane.show_divider);
}

test "SplitPane withRatio sets ratio" {
    const pane = SplitPane.init().withRatio(0.75);

    try testing.expectEqual(@as(f64, 0.75), pane.split_ratio);
}

test "SplitPane calculatePanes horizontal 50/50" {
    const pane = SplitPane.init().withRatio(0.5);
    const area = Rect{ .x = 0, .y = 0, .width = 20, .height = 10 };

    const panes = pane.calculatePanes(area);

    // With divider (1 width), 19 usable: 50% = 9.5 → 9
    try testing.expectEqual(@as(u16, 9), panes[0].width);
    try testing.expectEqual(@as(u16, 10), panes[1].width);
}

test "SplitPane calculatePanes with NaN ratio renders identically to ratio 0.0" {
    const area = Rect{ .x = 0, .y = 0, .width = 20, .height = 10 };

    // Calculate panes with NaN ratio
    const pane_nan = SplitPane{
        .direction = .horizontal,
        .split_ratio = std.math.nan(f64),
        .show_divider = false,
    };
    const panes_nan = pane_nan.calculatePanes(area);

    // Calculate panes with 0.0 ratio (floor value)
    const pane_zero = SplitPane{
        .direction = .horizontal,
        .split_ratio = 0.0,
        .show_divider = false,
    };
    const panes_zero = pane_zero.calculatePanes(area);

    // Assert both panes match exactly
    try testing.expectEqual(panes_zero[0].width, panes_nan[0].width);
    try testing.expectEqual(panes_zero[0].height, panes_nan[0].height);
    try testing.expectEqual(panes_zero[0].x, panes_nan[0].x);
    try testing.expectEqual(panes_zero[0].y, panes_nan[0].y);

    try testing.expectEqual(panes_zero[1].width, panes_nan[1].width);
    try testing.expectEqual(panes_zero[1].height, panes_nan[1].height);
    try testing.expectEqual(panes_zero[1].x, panes_nan[1].x);
    try testing.expectEqual(panes_zero[1].y, panes_nan[1].y);
}
