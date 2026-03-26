const std = @import("std");
const Buffer = @import("buffer.zig").Buffer;
const Rect = @import("layout.zig").Rect;

/// Widget trait provides an extensible protocol for custom widgets.
/// Any struct implementing `measure` and `render` methods can be treated as a widget.
///
/// Example:
/// ```zig
/// const MyWidget = struct {
///     text: []const u8,
///
///     pub fn measure(self: @This(), _: std.mem.Allocator, max_width: u16, max_height: u16) !Size {
///         return Size{
///             .width = @min(self.text.len, max_width),
///             .height = 1,
///         };
///     }
///
///     pub fn render(self: @This(), buf: *Buffer, area: Rect) !void {
///         buf.setString(area.x, area.y, self.text, .{});
///     }
/// };
/// ```

/// Size represents the measured dimensions of a widget.
pub const Size = struct {
    width: u16,
    height: u16,

    /// Returns a size with both dimensions set to zero.
    pub fn zero() Size {
        return .{ .width = 0, .height = 0 };
    }

    /// Returns a size constrained to the given maximum dimensions.
    pub fn constrain(self: Size, max_width: u16, max_height: u16) Size {
        return .{
            .width = @min(self.width, max_width),
            .height = @min(self.height, max_height),
        };
    }

    /// Returns true if both dimensions are zero.
    pub fn isEmpty(self: Size) bool {
        return self.width == 0 or self.height == 0;
    }

    /// Returns true if this size fits within the given dimensions.
    pub fn fitsWithin(self: Size, width: u16, height: u16) bool {
        return self.width <= width and self.height <= height;
    }
};

/// Widget trait interface using comptime dispatch.
/// This provides type-safe wrapper around any struct implementing the widget protocol.
pub fn Widget(comptime T: type) type {
    // Compile-time check that T implements the required methods
    comptime {
        if (!@hasDecl(T, "render")) {
            @compileError("Widget type must implement 'render' method");
        }
    }

    return struct {
        widget: T,

        const Self = @This();

        /// Create a new widget wrapper.
        pub fn init(widget: T) Self {
            return .{ .widget = widget };
        }

        /// Measure the widget's preferred size given maximum constraints.
        /// If the widget doesn't implement `measure`, returns the max dimensions.
        pub fn measure(self: Self, allocator: std.mem.Allocator, max_width: u16, max_height: u16) !Size {
            if (@hasDecl(T, "measure")) {
                return try self.widget.measure(allocator, max_width, max_height);
            } else {
                // Default: use all available space
                return Size{ .width = max_width, .height = max_height };
            }
        }

        /// Render the widget into the buffer at the given area.
        pub fn render(self: Self, buf: *Buffer, area: Rect) !void {
            return try self.widget.render(buf, area);
        }
    };
}

/// WidgetList manages a dynamic collection of widgets with type erasure.
/// Uses arena allocator for efficient memory management.
pub const WidgetList = struct {
    items: std.ArrayListUnmanaged(WidgetBox),
    arena: std.heap.ArenaAllocator,
    gpa: std.mem.Allocator,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator) Self {
        return .{
            .items = .{},
            .arena = std.heap.ArenaAllocator.init(allocator),
            .gpa = allocator,
        };
    }

    pub fn deinit(self: *Self) void {
        self.arena.deinit();
        self.items.deinit(self.gpa);
    }

    /// Add a widget to the list.
    /// The widget is cloned into the arena allocator.
    pub fn add(self: *Self, comptime T: type, widget: T) !void {
        const box = try WidgetBox.init(self.arena.allocator(), widget);
        try self.items.append(self.gpa, box);
    }

    /// Get the number of widgets in the list.
    pub fn count(self: Self) usize {
        return self.items.items.len;
    }

    /// Measure the widget at the given index.
    pub fn measureAt(self: Self, index: usize, allocator: std.mem.Allocator, max_width: u16, max_height: u16) !Size {
        if (index >= self.items.items.len) return error.IndexOutOfBounds;
        return try self.items.items[index].measure(allocator, max_width, max_height);
    }

    /// Render the widget at the given index.
    pub fn renderAt(self: Self, index: usize, buf: *Buffer, area: Rect) !void {
        if (index >= self.items.items.len) return error.IndexOutOfBounds;
        try self.items.items[index].render(buf, area);
    }

    /// Render all widgets in sequence.
    /// Each widget receives its measured size within the available area.
    pub fn renderAll(self: Self, buf: *Buffer, area: Rect, allocator: std.mem.Allocator) !void {
        var y: u16 = area.y;
        for (self.items.items) |*item| {
            if (y >= area.y + area.height) break;

            const remaining_height = area.y + area.height - y;
            const size = try item.measure(allocator, area.width, remaining_height);

            if (size.height == 0) continue;

            const widget_area = Rect{
                .x = area.x,
                .y = y,
                .width = area.width,
                .height = @min(size.height, remaining_height),
            };

            try item.render(buf, widget_area);
            y += widget_area.height;
        }
    }
};

/// WidgetBox provides type-erased storage for widgets.
/// Internally stores widget data and function pointers for dynamic dispatch.
const WidgetBox = struct {
    data: *anyopaque,
    measure_fn: *const fn (*anyopaque, std.mem.Allocator, u16, u16) anyerror!Size,
    render_fn: *const fn (*anyopaque, *Buffer, Rect) anyerror!void,

    fn init(allocator: std.mem.Allocator, widget: anytype) !WidgetBox {
        const T = @TypeOf(widget);
        const ptr = try allocator.create(T);
        ptr.* = widget;

        return .{
            .data = ptr,
            .measure_fn = struct {
                fn measure(data: *anyopaque, alloc: std.mem.Allocator, max_w: u16, max_h: u16) !Size {
                    const self: *T = @ptrCast(@alignCast(data));
                    if (@hasDecl(T, "measure")) {
                        return try self.measure(alloc, max_w, max_h);
                    } else {
                        return Size{ .width = max_w, .height = max_h };
                    }
                }
            }.measure,
            .render_fn = struct {
                fn render(data: *anyopaque, buf: *Buffer, area: Rect) !void {
                    const self: *T = @ptrCast(@alignCast(data));
                    const ReturnType = @typeInfo(@TypeOf(T.render)).@"fn".return_type.?;
                    if (ReturnType == void) {
                        self.render(buf, area);
                    } else {
                        return try self.render(buf, area);
                    }
                }
            }.render,
        };
    }

    fn measure(self: WidgetBox, allocator: std.mem.Allocator, max_width: u16, max_height: u16) !Size {
        return try self.measure_fn(self.data, allocator, max_width, max_height);
    }

    fn render(self: WidgetBox, buf: *Buffer, area: Rect) !void {
        try self.render_fn(self.data, buf, area);
    }
};

// ============================================================================
// Tests
// ============================================================================

test "Size: zero" {
    const size = Size.zero();
    try std.testing.expectEqual(@as(u16, 0), size.width);
    try std.testing.expectEqual(@as(u16, 0), size.height);
}

test "Size: constrain" {
    const size = Size{ .width = 100, .height = 50 };
    const constrained = size.constrain(80, 40);
    try std.testing.expectEqual(@as(u16, 80), constrained.width);
    try std.testing.expectEqual(@as(u16, 40), constrained.height);
}

test "Size: isEmpty" {
    try std.testing.expect(Size.zero().isEmpty());
    try std.testing.expect((Size{ .width = 0, .height = 10 }).isEmpty());
    try std.testing.expect((Size{ .width = 10, .height = 0 }).isEmpty());
    try std.testing.expect(!(Size{ .width = 10, .height = 10 }).isEmpty());
}

test "Size: fitsWithin" {
    const size = Size{ .width = 50, .height = 30 };
    try std.testing.expect(size.fitsWithin(100, 100));
    try std.testing.expect(size.fitsWithin(50, 30));
    try std.testing.expect(!size.fitsWithin(40, 30));
    try std.testing.expect(!size.fitsWithin(50, 20));
}

test "Widget trait: simple widget with measure" {
    const TestWidget = struct {
        text: []const u8,

        pub fn measure(_: @This(), _: std.mem.Allocator, max_width: u16, _: u16) !Size {
            return Size{ .width = @min(5, max_width), .height = 1 };
        }

        pub fn render(self: @This(), buf: *Buffer, area: Rect) !void {
            buf.setString(area.x, area.y, self.text, .{});
        }
    };

    const widget = Widget(TestWidget).init(.{ .text = "hello" });
    const size = try widget.measure(std.testing.allocator, 10, 10);

    try std.testing.expectEqual(@as(u16, 5), size.width);
    try std.testing.expectEqual(@as(u16, 1), size.height);
}

test "Widget trait: widget without measure" {
    const TestWidget = struct {
        pub fn render(_: @This(), buf: *Buffer, area: Rect) !void {
            buf.setString(area.x, area.y, "test", .{});
        }
    };

    const widget = Widget(TestWidget).init(.{});
    const size = try widget.measure(std.testing.allocator, 20, 15);

    // Should default to max dimensions
    try std.testing.expectEqual(@as(u16, 20), size.width);
    try std.testing.expectEqual(@as(u16, 15), size.height);
}

test "Widget trait: render integration" {
    const TestWidget = struct {
        value: u32,

        pub fn render(self: @This(), buf: *Buffer, area: Rect) !void {
            var text_buf: [32]u8 = undefined;
            const text = try std.fmt.bufPrint(&text_buf, "Value: {d}", .{self.value});
            buf.setString(area.x, area.y, text, .{});
        }
    };

    const widget = Widget(TestWidget).init(.{ .value = 42 });

    var buf = try Buffer.init(std.testing.allocator, 20, 5);
    defer buf.deinit();

    const area = Rect{ .x = 0, .y = 0, .width = 20, .height = 5 };
    try widget.render(&buf, area);

    // Check first few characters: "Value: 42"
    try std.testing.expectEqual('V', buf.getConst(0, 0).?.char);
    try std.testing.expectEqual('a', buf.getConst(1, 0).?.char);
    try std.testing.expectEqual('l', buf.getConst(2, 0).?.char);
    try std.testing.expectEqual('4', buf.getConst(7, 0).?.char);
    try std.testing.expectEqual('2', buf.getConst(8, 0).?.char);
}

test "WidgetList: init and deinit" {
    var list = WidgetList.init(std.testing.allocator);
    defer list.deinit();

    try std.testing.expectEqual(@as(usize, 0), list.count());
}

test "WidgetList: add and count" {
    const TestWidget = struct {
        pub fn render(_: @This(), _: *Buffer, _: Rect) !void {}
    };

    var list = WidgetList.init(std.testing.allocator);
    defer list.deinit();

    try list.add(TestWidget, .{});
    try list.add(TestWidget, .{});
    try list.add(TestWidget, .{});

    try std.testing.expectEqual(@as(usize, 3), list.count());
}

test "WidgetList: measureAt" {
    const TestWidget = struct {
        height: u16,

        pub fn measure(self: @This(), _: std.mem.Allocator, max_w: u16, _: u16) !Size {
            return Size{ .width = max_w, .height = self.height };
        }

        pub fn render(_: @This(), _: *Buffer, _: Rect) !void {}
    };

    var list = WidgetList.init(std.testing.allocator);
    defer list.deinit();

    try list.add(TestWidget, .{ .height = 5 });
    try list.add(TestWidget, .{ .height = 10 });

    const size1 = try list.measureAt(0, std.testing.allocator, 20, 20);
    const size2 = try list.measureAt(1, std.testing.allocator, 20, 20);

    try std.testing.expectEqual(@as(u16, 5), size1.height);
    try std.testing.expectEqual(@as(u16, 10), size2.height);
}

test "WidgetList: measureAt out of bounds" {
    var list = WidgetList.init(std.testing.allocator);
    defer list.deinit();

    const result = list.measureAt(0, std.testing.allocator, 10, 10);
    try std.testing.expectError(error.IndexOutOfBounds, result);
}

test "WidgetList: renderAt" {
    const TestWidget = struct {
        text: []const u8,

        pub fn render(self: @This(), buf: *Buffer, area: Rect) !void {
            buf.setString(area.x, area.y, self.text, .{});
        }
    };

    var list = WidgetList.init(std.testing.allocator);
    defer list.deinit();

    try list.add(TestWidget, .{ .text = "first" });
    try list.add(TestWidget, .{ .text = "second" });

    var buf = try Buffer.init(std.testing.allocator, 20, 5);
    defer buf.deinit();

    const area = Rect{ .x = 0, .y = 0, .width = 20, .height = 1 };
    try list.renderAt(0, &buf, area);

    // Check for "first"
    try std.testing.expectEqual('f', buf.getConst(0, 0).?.char);
    try std.testing.expectEqual('i', buf.getConst(1, 0).?.char);
    try std.testing.expectEqual('r', buf.getConst(2, 0).?.char);
    try std.testing.expectEqual('s', buf.getConst(3, 0).?.char);
    try std.testing.expectEqual('t', buf.getConst(4, 0).?.char);
}

test "WidgetList: renderAt out of bounds" {
    var list = WidgetList.init(std.testing.allocator);
    defer list.deinit();

    var buf = try Buffer.init(std.testing.allocator, 10, 5);
    defer buf.deinit();

    const area = Rect{ .x = 0, .y = 0, .width = 10, .height = 5 };
    const result = list.renderAt(0, &buf, area);
    try std.testing.expectError(error.IndexOutOfBounds, result);
}

test "WidgetList: renderAll vertical stacking" {
    const TestWidget = struct {
        text: []const u8,
        height: u16,

        pub fn measure(self: @This(), _: std.mem.Allocator, max_w: u16, _: u16) !Size {
            return Size{ .width = max_w, .height = self.height };
        }

        pub fn render(self: @This(), buf: *Buffer, area: Rect) !void {
            buf.setString(area.x, area.y, self.text, .{});
        }
    };

    var list = WidgetList.init(std.testing.allocator);
    defer list.deinit();

    try list.add(TestWidget, .{ .text = "row1", .height = 2 });
    try list.add(TestWidget, .{ .text = "row2", .height = 2 });
    try list.add(TestWidget, .{ .text = "row3", .height = 2 });

    var buf = try Buffer.init(std.testing.allocator, 20, 10);
    defer buf.deinit();

    const area = Rect{ .x = 0, .y = 0, .width = 20, .height = 10 };
    try list.renderAll(&buf, area, std.testing.allocator);

    // Check widgets at y=0, y=2, y=4
    try std.testing.expectEqual('r', buf.getConst(0, 0).?.char);
    try std.testing.expectEqual('o', buf.getConst(1, 0).?.char);
    try std.testing.expectEqual('w', buf.getConst(2, 0).?.char);
    try std.testing.expectEqual('1', buf.getConst(3, 0).?.char);

    try std.testing.expectEqual('r', buf.getConst(0, 2).?.char);
    try std.testing.expectEqual('o', buf.getConst(1, 2).?.char);
    try std.testing.expectEqual('w', buf.getConst(2, 2).?.char);
    try std.testing.expectEqual('2', buf.getConst(3, 2).?.char);

    try std.testing.expectEqual('r', buf.getConst(0, 4).?.char);
    try std.testing.expectEqual('o', buf.getConst(1, 4).?.char);
    try std.testing.expectEqual('w', buf.getConst(2, 4).?.char);
    try std.testing.expectEqual('3', buf.getConst(3, 4).?.char);
}

test "WidgetList: renderAll with limited height" {
    const TestWidget = struct {
        text: []const u8,
        height: u16,

        pub fn measure(self: @This(), _: std.mem.Allocator, max_w: u16, _: u16) !Size {
            return Size{ .width = max_w, .height = self.height };
        }

        pub fn render(self: @This(), buf: *Buffer, area: Rect) !void {
            buf.setString(area.x, area.y, self.text, .{});
        }
    };

    var list = WidgetList.init(std.testing.allocator);
    defer list.deinit();

    try list.add(TestWidget, .{ .text = "A", .height = 3 });
    try list.add(TestWidget, .{ .text = "B", .height = 3 });
    try list.add(TestWidget, .{ .text = "C", .height = 3 });

    var buf = try Buffer.init(std.testing.allocator, 20, 5);
    defer buf.deinit();

    // Only 5 lines available - should render A (3) and B (2, clipped)
    const area = Rect{ .x = 0, .y = 0, .width = 20, .height = 5 };
    try list.renderAll(&buf, area, std.testing.allocator);

    // Check A at y=0 and B at y=3
    try std.testing.expectEqual('A', buf.getConst(0, 0).?.char);
    try std.testing.expectEqual('B', buf.getConst(0, 3).?.char);
}

test "WidgetList: mixed widgets with different types" {
    const TextWidget = struct {
        text: []const u8,

        pub fn measure(_: @This(), _: std.mem.Allocator, max_w: u16, _: u16) !Size {
            return Size{ .width = max_w, .height = 1 };
        }

        pub fn render(self: @This(), buf: *Buffer, area: Rect) !void {
            buf.setString(area.x, area.y, self.text, .{});
        }
    };

    const NumberWidget = struct {
        value: u32,

        pub fn measure(_: @This(), _: std.mem.Allocator, max_w: u16, _: u16) !Size {
            return Size{ .width = max_w, .height = 1 };
        }

        pub fn render(self: @This(), buf: *Buffer, area: Rect) !void {
            var text_buf: [32]u8 = undefined;
            const text = try std.fmt.bufPrint(&text_buf, "{d}", .{self.value});
            buf.setString(area.x, area.y, text, .{});
        }
    };

    var list = WidgetList.init(std.testing.allocator);
    defer list.deinit();

    try list.add(TextWidget, .{ .text = "Count:" });
    try list.add(NumberWidget, .{ .value = 42 });

    var buf = try Buffer.init(std.testing.allocator, 20, 5);
    defer buf.deinit();

    const area = Rect{ .x = 0, .y = 0, .width = 20, .height = 5 };
    try list.renderAll(&buf, area, std.testing.allocator);

    // Check "Count:" at y=0
    try std.testing.expectEqual('C', buf.getConst(0, 0).?.char);
    try std.testing.expectEqual('o', buf.getConst(1, 0).?.char);
    try std.testing.expectEqual('u', buf.getConst(2, 0).?.char);

    // Check "42" at y=1
    try std.testing.expectEqual('4', buf.getConst(0, 1).?.char);
    try std.testing.expectEqual('2', buf.getConst(1, 1).?.char);
}

test "WidgetList: widgets with zero height" {
    const TestWidget = struct {
        text: []const u8,
        height: u16,

        pub fn measure(self: @This(), _: std.mem.Allocator, max_w: u16, _: u16) !Size {
            return Size{ .width = max_w, .height = self.height };
        }

        pub fn render(self: @This(), buf: *Buffer, area: Rect) !void {
            if (area.height > 0) {
                buf.setString(area.x, area.y, self.text, .{});
            }
        }
    };

    var list = WidgetList.init(std.testing.allocator);
    defer list.deinit();

    try list.add(TestWidget, .{ .text = "A", .height = 2 });
    try list.add(TestWidget, .{ .text = "B", .height = 0 }); // Should be skipped
    try list.add(TestWidget, .{ .text = "C", .height = 2 });

    var buf = try Buffer.init(std.testing.allocator, 20, 10);
    defer buf.deinit();

    const area = Rect{ .x = 0, .y = 0, .width = 20, .height = 10 };
    try list.renderAll(&buf, area, std.testing.allocator);

    // Check A at y=0, C at y=2 (B skipped because height=0)
    try std.testing.expectEqual('A', buf.getConst(0, 0).?.char);
    try std.testing.expectEqual('C', buf.getConst(0, 2).?.char);
}
