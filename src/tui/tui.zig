//! TUI Framework Core Module
//!
//! Full-screen terminal user interface framework with:
//! - Double-buffered rendering
//! - Constraint-based layout system
//! - Composable widget architecture
//! - Event handling (keyboard, mouse, resize)

const std = @import("std");
const builtin = @import("builtin");
const Allocator = std.mem.Allocator;
const term_mod = @import("../term.zig");

pub const style = @import("style.zig");
pub const buffer = @import("buffer.zig");
pub const layout = @import("layout.zig");
pub const grid = @import("grid.zig");
pub const overlay = @import("overlay.zig");
pub const composition = @import("composition.zig");
pub const responsive = @import("responsive.zig");
pub const symbols = @import("symbols.zig");
pub const theme = @import("theme.zig");
pub const animation = @import("animation.zig");
pub const budget = @import("budget.zig");
pub const lazy = @import("lazy.zig");
pub const batch = @import("batch.zig");
pub const hotreload = @import("hotreload.zig");
pub const validators = @import("validators.zig");

// v1.5.0+ — State Management & Testing
pub const eventbus = @import("../eventbus.zig");
pub const command = @import("../command.zig");
pub const test_utils = @import("test_utils.zig");

// Phase 4+ widgets
pub const widgets = struct {
    pub const Block = @import("widgets/block.zig").Block;
    pub const Borders = @import("widgets/block.zig").Borders;
    pub const TitlePosition = @import("widgets/block.zig").TitlePosition;
    pub const Paragraph = @import("widgets/paragraph.zig").Paragraph;
    pub const Alignment = @import("widgets/paragraph.zig").Alignment;
    pub const Wrap = @import("widgets/paragraph.zig").Wrap;
    pub const List = @import("widgets/list.zig").List;
    pub const Table = @import("widgets/table.zig").Table;
    pub const Column = @import("widgets/table.zig").Column;
    pub const ColumnWidth = @import("widgets/table.zig").ColumnWidth;
    pub const Input = @import("widgets/input.zig").Input;
    pub const Tabs = @import("widgets/tabs.zig").Tabs;
    pub const StatusBar = @import("widgets/statusbar.zig").StatusBar;
    pub const Gauge = @import("widgets/gauge.zig").Gauge;
    pub const Row = @import("widgets/table.zig").Row;

    // Phase 5 widgets
    pub const Tree = @import("widgets/tree.zig").Tree;
    pub const TreeNode = @import("widgets/tree.zig").TreeNode;
    pub const TextArea = @import("widgets/textarea.zig").TextArea;
    pub const Sparkline = @import("widgets/sparkline.zig").Sparkline;
    pub const BarChart = @import("widgets/barchart.zig").BarChart;
    pub const Bar = @import("widgets/barchart.zig").BarChart.Bar;
    pub const LineChart = @import("widgets/linechart.zig").LineChart;
    pub const Series = @import("widgets/linechart.zig").LineChart.Series;
    pub const Canvas = @import("widgets/canvas.zig").Canvas;
    pub const Dialog = @import("widgets/dialog.zig").Dialog;
    pub const Popup = @import("widgets/popup.zig").Popup;
    pub const Notification = @import("widgets/notification.zig").Notification;
    pub const NotificationLevel = @import("widgets/notification.zig").Level;
    pub const NotificationPosition = @import("widgets/notification.zig").Position;

    // Phase 6+ widgets (v1.2.0+)
    pub const ScrollView = @import("widgets/scrollview.zig").ScrollView;

    // v1.3.0+ widgets (Performance & Dev Experience)
    pub const DebugOverlay = @import("widgets/debug.zig").DebugOverlay;
    pub const DebugMode = @import("widgets/debug.zig").DebugMode;

    // v1.4.0+ widgets (Advanced Input & Forms)
    pub const Form = @import("widgets/form.zig").Form;
    pub const Field = @import("widgets/form.zig").Field;
    pub const ValidationResult = @import("widgets/form.zig").ValidationResult;
    pub const Validator = @import("widgets/form.zig").Validator;
    pub const Select = @import("widgets/select.zig").Select;
    pub const Checkbox = @import("widgets/checkbox.zig").Checkbox;
    pub const CheckboxGroup = @import("widgets/checkbox.zig").CheckboxGroup;
    pub const RadioGroup = @import("widgets/radio.zig").RadioGroup;

    // v1.6.0+ widgets (Data Visualization & Advanced Charts)
    pub const Heatmap = @import("widgets/heatmap.zig").Heatmap;
    pub const Gradient = @import("widgets/heatmap.zig").Heatmap.Gradient;
    pub const CellMode = @import("widgets/heatmap.zig").Heatmap.CellMode;
    pub const PieChart = @import("widgets/piechart.zig").PieChart;
    pub const Slice = @import("widgets/piechart.zig").PieChart.Slice;
    pub const LegendPosition = @import("widgets/piechart.zig").PieChart.LegendPosition;
};

// Export commonly used types
pub const Color = style.Color;
pub const Style = style.Style;
pub const Span = style.Span;
pub const Line = style.Line;
pub const Buffer = buffer.Buffer;
pub const Cell = buffer.Cell;
pub const Rect = layout.Rect;
pub const Constraint = layout.Constraint;
pub const Direction = layout.Direction;
pub const BoxSet = symbols.BoxSet;

// Export performance types (v1.3.0)
pub const RenderBudget = budget.RenderBudget;
pub const LazyBuffer = lazy.LazyBuffer;
pub const EventBatcher = batch.EventBatcher;
pub const ThemeWatcher = hotreload.ThemeWatcher;

/// Terminal wrapper for TUI applications (stub for Phase 3)
pub const Terminal = struct {
    width: u16,
    height: u16,
    current: Buffer,
    previous: Buffer,
    allocator: Allocator,

    /// Initialize terminal
    pub fn init(allocator: Allocator) !Terminal {
        const term_size = try term_mod.getSize();
        const width = @min(term_size.cols, std.math.maxInt(u16));
        const height = @min(term_size.rows, std.math.maxInt(u16));

        var current = try Buffer.init(allocator, @intCast(width), @intCast(height));
        errdefer current.deinit();
        var previous = try Buffer.init(allocator, @intCast(width), @intCast(height));
        errdefer previous.deinit();

        return Terminal{
            .width = @intCast(width),
            .height = @intCast(height),
            .current = current,
            .previous = previous,
            .allocator = allocator,
        };
    }

    /// Clean up
    pub fn deinit(self: *Terminal) void {
        self.current.deinit();
        self.previous.deinit();
    }

    /// Get terminal size as Rect
    pub fn size(self: Terminal) Rect {
        return Rect.new(0, 0, self.width, self.height);
    }

    /// Clear terminal
    pub fn clear(self: *Terminal) void {
        self.current.clear();
    }
};

/// Frame represents a drawing context
pub const Frame = struct {
    buffer: *Buffer,
    area: Rect,

    /// Set string at position within frame area
    pub fn setString(self: *Frame, x: u16, y: u16, str: []const u8, style_val: Style) void {
        const abs_x = self.area.x + x;
        const abs_y = self.area.y + y;
        self.buffer.setString(abs_x, abs_y, str, style_val);
    }

    /// Fill area with character and style
    pub fn fill(self: *Frame, area: Rect, char: u21, style_val: Style) void {
        const abs_area = Rect.new(
            self.area.x + area.x,
            self.area.y + area.y,
            area.width,
            area.height,
        );
        self.buffer.fill(abs_area, char, style_val);
    }
};

/// Keyboard event
pub const KeyEvent = struct {
    code: KeyCode,
    modifiers: Modifiers = .{},
};

/// Key codes
pub const KeyCode = union(enum) {
    char: u8,
    enter,
    backspace,
    tab,
    esc,
    up,
    down,
    left,
    right,
    home,
    end,
    page_up,
    page_down,
    delete,
    insert,
    f: u8, // F1-F12
};

/// Keyboard modifiers
pub const Modifiers = struct {
    ctrl: bool = false,
    alt: bool = false,
    shift: bool = false,
};

/// Terminal events
pub const Event = union(enum) {
    key: KeyEvent,
    resize: struct { width: u16, height: u16 },
    mouse: void,
};

// ============================================================================
// Tests
// ============================================================================

test "Terminal init and size" {
    if (!term_mod.isatty(std.posix.STDOUT_FILENO)) return error.SkipZigTest;

    var term = try Terminal.init(std.testing.allocator);
    defer term.deinit();

    const rect = term.size();
    try std.testing.expect(rect.width > 0);
    try std.testing.expect(rect.height > 0);
}

test "Terminal clear" {
    if (!term_mod.isatty(std.posix.STDOUT_FILENO)) return error.SkipZigTest;

    var term = try Terminal.init(std.testing.allocator);
    defer term.deinit();

    term.current.setChar(5, 5, 'X', .{});
    term.clear();

    const cell = term.current.getConst(5, 5).?;
    try std.testing.expectEqual(' ', cell.char);
}

test "Frame setString" {
    var buf = try Buffer.init(std.testing.allocator, 20, 10);
    defer buf.deinit();

    var frame = Frame{
        .buffer = &buf,
        .area = Rect.new(2, 2, 15, 8),
    };

    frame.setString(0, 0, "Test", .{});

    try std.testing.expectEqual('T', buf.get(2, 2).?.char);
    try std.testing.expectEqual('e', buf.get(3, 2).?.char);
}

test "Frame fill" {
    var buf = try Buffer.init(std.testing.allocator, 20, 10);
    defer buf.deinit();

    var frame = Frame{
        .buffer = &buf,
        .area = Rect.new(5, 5, 10, 5),
    };

    frame.fill(Rect.new(0, 0, 3, 2), 'X', .{});

    try std.testing.expectEqual('X', buf.get(5, 5).?.char);
    try std.testing.expectEqual('X', buf.get(7, 6).?.char);
    try std.testing.expectEqual(' ', buf.get(10, 5).?.char);
}

test "KeyCode enum" {
    const key1: KeyCode = .{ .char = 'a' };
    const key2: KeyCode = .enter;
    const key3: KeyCode = .{ .f = 1 };

    try std.testing.expectEqual('a', key1.char);
    try std.testing.expectEqual(KeyCode.enter, key2);
    try std.testing.expectEqual(1, key3.f);
}

test "Event union" {
    const ev1 = Event{ .key = .{ .code = .{ .char = 'x' } } };
    const ev2 = Event{ .resize = .{ .width = 80, .height = 24 } };

    try std.testing.expectEqual('x', ev1.key.code.char);
    try std.testing.expectEqual(80, ev2.resize.width);
}

test {
    std.testing.refAllDecls(@This());
    // Pull in widget tests
    _ = @import("widgets/block.zig");
    _ = @import("widgets/paragraph.zig");
    _ = @import("widgets/list.zig");
    _ = @import("widgets/table.zig");
}
