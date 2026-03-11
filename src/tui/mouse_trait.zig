//! Widget-level mouse interaction protocol
//!
//! Provides traits and helpers for widgets that support mouse interaction.
//! Widgets can implement clickable, draggable, scrollable, or hoverable behaviors.

const std = @import("std");
const mouse = @import("mouse.zig");
const layout = @import("layout.zig");

const Rect = layout.Rect;
const MouseEvent = mouse.MouseEvent;
const MouseButton = mouse.MouseButton;
const MouseEventType = mouse.MouseEventType;

/// Result of mouse interaction
pub const InteractionResult = enum {
    handled, // Event was handled by this widget
    ignored, // Event was not relevant to this widget
    propagate, // Event should be propagated to parent/siblings
};

/// Clickable widget trait
/// Widgets that implement this can respond to mouse clicks
pub const Clickable = struct {
    /// Called when widget is clicked
    /// Returns true if click was handled
    on_click: *const fn (ctx: *anyopaque, event: MouseEvent) InteractionResult,

    /// Check if point is inside clickable area
    pub fn contains(area: Rect, x: u16, y: u16) bool {
        return x >= area.x and
            x < area.x + area.width and
            y >= area.y and
            y < area.y + area.height;
    }

    /// Handle mouse event for clickable widget
    pub fn handleEvent(self: Clickable, ctx: *anyopaque, event: MouseEvent, area: Rect) InteractionResult {
        if (event.event_type != .press and event.event_type != .double_click) {
            return .ignored;
        }

        if (!contains(area, event.x, event.y)) {
            return .ignored;
        }

        return self.on_click(ctx, event);
    }
};

/// Draggable widget trait
/// Widgets that implement this can be dragged with the mouse
pub const Draggable = struct {
    /// Called when drag starts
    on_drag_start: ?*const fn (ctx: *anyopaque, event: MouseEvent) void = null,

    /// Called during drag motion
    on_drag: *const fn (ctx: *anyopaque, event: MouseEvent) InteractionResult,

    /// Called when drag ends
    on_drag_end: ?*const fn (ctx: *anyopaque, event: MouseEvent) void = null,

    /// Track drag state
    pub const DragState = struct {
        active: bool = false,
        start_x: u16 = 0,
        start_y: u16 = 0,
        last_x: u16 = 0,
        last_y: u16 = 0,
        button: MouseButton = .none,

        pub fn start(self: *DragState, event: MouseEvent) void {
            self.active = true;
            self.start_x = event.x;
            self.start_y = event.y;
            self.last_x = event.x;
            self.last_y = event.y;
            self.button = event.button;
        }

        pub fn update(self: *DragState, event: MouseEvent) void {
            self.last_x = event.x;
            self.last_y = event.y;
        }

        pub fn end(self: *DragState) void {
            self.active = false;
            self.button = .none;
        }

        pub fn getDelta(self: DragState) struct { dx: i32, dy: i32 } {
            return .{
                .dx = @as(i32, self.last_x) - @as(i32, self.start_x),
                .dy = @as(i32, self.last_y) - @as(i32, self.start_y),
            };
        }
    };

    /// Handle mouse event for draggable widget
    pub fn handleEvent(
        self: Draggable,
        ctx: *anyopaque,
        event: MouseEvent,
        state: *DragState,
        area: Rect,
    ) InteractionResult {
        switch (event.event_type) {
            .press => {
                if (Clickable.contains(area, event.x, event.y)) {
                    state.start(event);
                    if (self.on_drag_start) |start_fn| {
                        start_fn(ctx, event);
                    }
                    return .handled;
                }
            },
            .drag => {
                if (state.active and event.button == state.button) {
                    state.update(event);
                    return self.on_drag(ctx, event);
                }
            },
            .release => {
                if (state.active) {
                    if (self.on_drag_end) |end_fn| {
                        end_fn(ctx, event);
                    }
                    state.end();
                    return .handled;
                }
            },
            else => {},
        }
        return .ignored;
    }
};

/// Scrollable widget trait
/// Widgets that implement this can respond to scroll wheel events
pub const Scrollable = struct {
    /// Called when scroll occurs
    on_scroll: *const fn (ctx: *anyopaque, delta: i32, event: MouseEvent) InteractionResult,

    /// Handle mouse event for scrollable widget
    pub fn handleEvent(self: Scrollable, ctx: *anyopaque, event: MouseEvent, area: Rect) InteractionResult {
        if (!Clickable.contains(area, event.x, event.y)) {
            return .ignored;
        }

        const delta: i32 = switch (event.event_type) {
            .scroll_up => -1,
            .scroll_down => 1,
            else => return .ignored,
        };

        return self.on_scroll(ctx, delta, event);
    }
};

/// Hoverable widget trait
/// Widgets that implement this can respond to mouse hover
pub const Hoverable = struct {
    /// Called when mouse enters widget area
    on_enter: ?*const fn (ctx: *anyopaque, event: MouseEvent) void = null,

    /// Called when mouse moves within widget area
    on_hover: ?*const fn (ctx: *anyopaque, event: MouseEvent) void = null,

    /// Called when mouse leaves widget area
    on_leave: ?*const fn (ctx: *anyopaque) void = null,

    /// Track hover state
    pub const HoverState = struct {
        hovering: bool = false,
        last_x: u16 = 0,
        last_y: u16 = 0,

        pub fn isInside(area: Rect, x: u16, y: u16) bool {
            return Clickable.contains(area, x, y);
        }
    };

    /// Handle mouse event for hoverable widget
    pub fn handleEvent(
        self: Hoverable,
        ctx: *anyopaque,
        event: MouseEvent,
        state: *HoverState,
        area: Rect,
    ) InteractionResult {
        const inside = HoverState.isInside(area, event.x, event.y);

        if (event.event_type == .move or event.event_type == .drag) {
            if (inside and !state.hovering) {
                // Mouse entered
                state.hovering = true;
                state.last_x = event.x;
                state.last_y = event.y;
                if (self.on_enter) |enter_fn| {
                    enter_fn(ctx, event);
                }
                return .handled;
            } else if (inside and state.hovering) {
                // Mouse moved within
                state.last_x = event.x;
                state.last_y = event.y;
                if (self.on_hover) |hover_fn| {
                    hover_fn(ctx, event);
                }
                return .handled;
            } else if (!inside and state.hovering) {
                // Mouse left
                state.hovering = false;
                if (self.on_leave) |leave_fn| {
                    leave_fn(ctx);
                }
                return .handled;
            }
        }

        return .ignored;
    }
};

/// Helper to combine multiple interaction traits
pub const CompositeInteraction = struct {
    clickable: ?Clickable = null,
    draggable: ?Draggable = null,
    scrollable: ?Scrollable = null,
    hoverable: ?Hoverable = null,

    drag_state: Draggable.DragState = .{},
    hover_state: Hoverable.HoverState = .{},

    /// Handle event with all enabled traits
    pub fn handleEvent(
        self: *CompositeInteraction,
        ctx: *anyopaque,
        event: MouseEvent,
        area: Rect,
    ) InteractionResult {
        var result = InteractionResult.ignored;

        // Try hoverable first (for enter/leave tracking)
        if (self.hoverable) |hoverable| {
            const hover_result = hoverable.handleEvent(ctx, event, &self.hover_state, area);
            if (hover_result == .handled) result = .handled;
        }

        // Try draggable
        if (self.draggable) |draggable| {
            const drag_result = draggable.handleEvent(ctx, event, &self.drag_state, area);
            if (drag_result == .handled) return .handled;
        }

        // Try clickable
        if (self.clickable) |clickable| {
            const click_result = clickable.handleEvent(ctx, event, area);
            if (click_result == .handled) return .handled;
        }

        // Try scrollable
        if (self.scrollable) |scrollable| {
            const scroll_result = scrollable.handleEvent(ctx, event, area);
            if (scroll_result == .handled) return .handled;
        }

        return result;
    }
};

// ============================================================================
// Tests
// ============================================================================

test "Clickable.contains" {
    const area = Rect.new(10, 5, 20, 10);
    try std.testing.expect(Clickable.contains(area, 10, 5)); // top-left
    try std.testing.expect(Clickable.contains(area, 15, 8)); // center
    try std.testing.expect(Clickable.contains(area, 29, 14)); // bottom-right
    try std.testing.expect(!Clickable.contains(area, 9, 5)); // left of area
    try std.testing.expect(!Clickable.contains(area, 10, 4)); // above area
    try std.testing.expect(!Clickable.contains(area, 30, 10)); // right of area
    try std.testing.expect(!Clickable.contains(area, 15, 15)); // below area
}

test "Clickable.handleEvent press inside" {
    var clicked = false;
    const TestCtx = struct {
        clicked: *bool,
    };

    const onClick = struct {
        fn f(ctx: *anyopaque, event: MouseEvent) InteractionResult {
            const self: *TestCtx = @ptrCast(@alignCast(ctx));
            self.clicked.* = true;
            // Verify event type and button (no try needed in callback)
            std.debug.assert(event.event_type == .press);
            std.debug.assert(event.button == .left);
            return .handled;
        }
    }.f;

    const clickable = Clickable{ .on_click = onClick };
    var ctx = TestCtx{ .clicked = &clicked };
    const area = Rect.new(10, 5, 20, 10);
    const event = MouseEvent{
        .event_type = .press,
        .button = .left,
        .x = 15,
        .y = 8,
    };

    const result = clickable.handleEvent(&ctx, event, area);
    try std.testing.expectEqual(InteractionResult.handled, result);
    try std.testing.expect(clicked);
}

test "Clickable.handleEvent press outside" {
    var clicked = false;
    const TestCtx = struct {
        clicked: *bool,
    };

    const onClick = struct {
        fn f(ctx: *anyopaque, _: MouseEvent) InteractionResult {
            const self: *TestCtx = @ptrCast(@alignCast(ctx));
            self.clicked.* = true;
            return .handled;
        }
    }.f;

    const clickable = Clickable{ .on_click = onClick };
    var ctx = TestCtx{ .clicked = &clicked };
    const area = Rect.new(10, 5, 20, 10);
    const event = MouseEvent{
        .event_type = .press,
        .button = .left,
        .x = 5, // Outside area
        .y = 8,
    };

    const result = clickable.handleEvent(&ctx, event, area);
    try std.testing.expectEqual(InteractionResult.ignored, result);
    try std.testing.expect(!clicked);
}

test "DragState lifecycle" {
    var state = Draggable.DragState{};
    try std.testing.expect(!state.active);

    const start_event = MouseEvent{
        .event_type = .press,
        .button = .left,
        .x = 10,
        .y = 5,
    };
    state.start(start_event);
    try std.testing.expect(state.active);
    try std.testing.expectEqual(@as(u16, 10), state.start_x);
    try std.testing.expectEqual(@as(u16, 5), state.start_y);
    try std.testing.expectEqual(MouseButton.left, state.button);

    const drag_event = MouseEvent{
        .event_type = .drag,
        .button = .left,
        .x = 15,
        .y = 10,
    };
    state.update(drag_event);
    try std.testing.expectEqual(@as(u16, 15), state.last_x);
    try std.testing.expectEqual(@as(u16, 10), state.last_y);

    const delta = state.getDelta();
    try std.testing.expectEqual(@as(i32, 5), delta.dx);
    try std.testing.expectEqual(@as(i32, 5), delta.dy);

    state.end();
    try std.testing.expect(!state.active);
}

test "Draggable.handleEvent full cycle" {
    var drag_started = false;
    var drag_count: u32 = 0;
    var drag_ended = false;

    const TestCtx = struct {
        started: *bool,
        count: *u32,
        ended: *bool,
    };

    const onDragStart = struct {
        fn f(ctx: *anyopaque, _: MouseEvent) void {
            const self: *TestCtx = @ptrCast(@alignCast(ctx));
            self.started.* = true;
        }
    }.f;

    const onDrag = struct {
        fn f(ctx: *anyopaque, _: MouseEvent) InteractionResult {
            const self: *TestCtx = @ptrCast(@alignCast(ctx));
            self.count.* += 1;
            return .handled;
        }
    }.f;

    const onDragEnd = struct {
        fn f(ctx: *anyopaque, _: MouseEvent) void {
            const self: *TestCtx = @ptrCast(@alignCast(ctx));
            self.ended.* = true;
        }
    }.f;

    const draggable = Draggable{
        .on_drag_start = onDragStart,
        .on_drag = onDrag,
        .on_drag_end = onDragEnd,
    };

    var ctx = TestCtx{ .started = &drag_started, .count = &drag_count, .ended = &drag_ended };
    var state = Draggable.DragState{};
    const area = Rect.new(10, 5, 20, 10);

    // Press to start drag
    const press_event = MouseEvent{ .event_type = .press, .button = .left, .x = 15, .y = 8 };
    _ = draggable.handleEvent(&ctx, press_event, &state, area);
    try std.testing.expect(drag_started);
    try std.testing.expect(state.active);

    // Drag motion
    const drag_event = MouseEvent{ .event_type = .drag, .button = .left, .x = 20, .y = 10 };
    _ = draggable.handleEvent(&ctx, drag_event, &state, area);
    try std.testing.expectEqual(@as(u32, 1), drag_count);

    // Release to end drag
    const release_event = MouseEvent{ .event_type = .release, .button = .left, .x = 20, .y = 10 };
    _ = draggable.handleEvent(&ctx, release_event, &state, area);
    try std.testing.expect(drag_ended);
    try std.testing.expect(!state.active);
}

test "Scrollable.handleEvent scroll up" {
    var scroll_delta: i32 = 0;

    const TestCtx = struct {
        delta: *i32,
    };

    const onScroll = struct {
        fn f(ctx: *anyopaque, delta: i32, _: MouseEvent) InteractionResult {
            const self: *TestCtx = @ptrCast(@alignCast(ctx));
            self.delta.* = delta;
            return .handled;
        }
    }.f;

    const scrollable = Scrollable{ .on_scroll = onScroll };
    var ctx = TestCtx{ .delta = &scroll_delta };
    const area = Rect.new(10, 5, 20, 10);
    const event = MouseEvent{
        .event_type = .scroll_up,
        .button = .none,
        .x = 15,
        .y = 8,
    };

    const result = scrollable.handleEvent(&ctx, event, area);
    try std.testing.expectEqual(InteractionResult.handled, result);
    try std.testing.expectEqual(@as(i32, -1), scroll_delta);
}

test "Scrollable.handleEvent scroll down" {
    var scroll_delta: i32 = 0;

    const TestCtx = struct {
        delta: *i32,
    };

    const onScroll = struct {
        fn f(ctx: *anyopaque, delta: i32, _: MouseEvent) InteractionResult {
            const self: *TestCtx = @ptrCast(@alignCast(ctx));
            self.delta.* = delta;
            return .handled;
        }
    }.f;

    const scrollable = Scrollable{ .on_scroll = onScroll };
    var ctx = TestCtx{ .delta = &scroll_delta };
    const area = Rect.new(10, 5, 20, 10);
    const event = MouseEvent{
        .event_type = .scroll_down,
        .button = .none,
        .x = 15,
        .y = 8,
    };

    const result = scrollable.handleEvent(&ctx, event, area);
    try std.testing.expectEqual(InteractionResult.handled, result);
    try std.testing.expectEqual(@as(i32, 1), scroll_delta);
}

test "HoverState tracking" {
    const state = Hoverable.HoverState{};
    const area = Rect.new(10, 5, 20, 10);

    try std.testing.expect(!state.hovering);
    try std.testing.expect(Hoverable.HoverState.isInside(area, 15, 8));
    try std.testing.expect(!Hoverable.HoverState.isInside(area, 5, 5));
}

test "Hoverable.handleEvent enter and leave" {
    var entered = false;
    var left = false;

    const TestCtx = struct {
        entered: *bool,
        left: *bool,
    };

    const onEnter = struct {
        fn f(ctx: *anyopaque, _: MouseEvent) void {
            const self: *TestCtx = @ptrCast(@alignCast(ctx));
            self.entered.* = true;
        }
    }.f;

    const onLeave = struct {
        fn f(ctx: *anyopaque) void {
            const self: *TestCtx = @ptrCast(@alignCast(ctx));
            self.left.* = true;
        }
    }.f;

    const hoverable = Hoverable{
        .on_enter = onEnter,
        .on_leave = onLeave,
    };

    var ctx = TestCtx{ .entered = &entered, .left = &left };
    var state = Hoverable.HoverState{};
    const area = Rect.new(10, 5, 20, 10);

    // Move into area
    const enter_event = MouseEvent{ .event_type = .move, .button = .none, .x = 15, .y = 8 };
    _ = hoverable.handleEvent(&ctx, enter_event, &state, area);
    try std.testing.expect(entered);
    try std.testing.expect(state.hovering);

    // Move outside area
    const leave_event = MouseEvent{ .event_type = .move, .button = .none, .x = 5, .y = 5 };
    _ = hoverable.handleEvent(&ctx, leave_event, &state, area);
    try std.testing.expect(left);
    try std.testing.expect(!state.hovering);
}

test "CompositeInteraction clickable only" {
    var clicked = false;

    const TestCtx = struct {
        clicked: *bool,
    };

    const onClick = struct {
        fn f(ctx: *anyopaque, _: MouseEvent) InteractionResult {
            const self: *TestCtx = @ptrCast(@alignCast(ctx));
            self.clicked.* = true;
            return .handled;
        }
    }.f;

    var composite = CompositeInteraction{
        .clickable = Clickable{ .on_click = onClick },
    };

    var ctx = TestCtx{ .clicked = &clicked };
    const area = Rect.new(10, 5, 20, 10);
    const event = MouseEvent{ .event_type = .press, .button = .left, .x = 15, .y = 8 };

    const result = composite.handleEvent(&ctx, event, area);
    try std.testing.expectEqual(InteractionResult.handled, result);
    try std.testing.expect(clicked);
}

test "CompositeInteraction scrollable only" {
    var scroll_delta: i32 = 0;

    const TestCtx = struct {
        delta: *i32,
    };

    const onScroll = struct {
        fn f(ctx: *anyopaque, delta: i32, _: MouseEvent) InteractionResult {
            const self: *TestCtx = @ptrCast(@alignCast(ctx));
            self.delta.* = delta;
            return .handled;
        }
    }.f;

    var composite = CompositeInteraction{
        .scrollable = Scrollable{ .on_scroll = onScroll },
    };

    var ctx = TestCtx{ .delta = &scroll_delta };
    const area = Rect.new(10, 5, 20, 10);
    const event = MouseEvent{ .event_type = .scroll_up, .button = .none, .x = 15, .y = 8 };

    const result = composite.handleEvent(&ctx, event, area);
    try std.testing.expectEqual(InteractionResult.handled, result);
    try std.testing.expectEqual(@as(i32, -1), scroll_delta);
}

test "Clickable.handleEvent double click" {
    var clicked = false;
    const TestCtx = struct {
        clicked: *bool,
    };

    const onClick = struct {
        fn f(ctx: *anyopaque, event: MouseEvent) InteractionResult {
            const self: *TestCtx = @ptrCast(@alignCast(ctx));
            self.clicked.* = true;
            std.debug.assert(event.event_type == .double_click);
            std.debug.assert(event.button == .left);
            return .handled;
        }
    }.f;

    const clickable = Clickable{ .on_click = onClick };
    var ctx = TestCtx{ .clicked = &clicked };
    const area = Rect.new(10, 5, 20, 10);
    const event = MouseEvent{
        .event_type = .double_click,
        .button = .left,
        .x = 15,
        .y = 8,
    };

    const result = clickable.handleEvent(&ctx, event, area);
    try std.testing.expectEqual(InteractionResult.handled, result);
    try std.testing.expect(clicked);
}

test "CompositeInteraction draggable only" {
    var drag_started = false;

    const TestCtx = struct {
        started: *bool,
    };

    const onDragStart = struct {
        fn f(ctx: *anyopaque, _: MouseEvent) void {
            const self: *TestCtx = @ptrCast(@alignCast(ctx));
            self.started.* = true;
        }
    }.f;

    const onDrag = struct {
        fn f(_: *anyopaque, _: MouseEvent) InteractionResult {
            return .handled;
        }
    }.f;

    var composite = CompositeInteraction{
        .draggable = Draggable{
            .on_drag_start = onDragStart,
            .on_drag = onDrag,
        },
    };

    var ctx = TestCtx{ .started = &drag_started };
    const area = Rect.new(10, 5, 20, 10);
    const event = MouseEvent{ .event_type = .press, .button = .left, .x = 15, .y = 8 };

    const result = composite.handleEvent(&ctx, event, area);
    try std.testing.expectEqual(InteractionResult.handled, result);
    try std.testing.expect(drag_started);
    try std.testing.expect(composite.drag_state.active);
}

test "CompositeInteraction hoverable only" {
    var hover_entered = false;

    const TestCtx = struct {
        entered: *bool,
    };

    const onHoverEnter = struct {
        fn f(ctx: *anyopaque, _: MouseEvent) void {
            const self: *TestCtx = @ptrCast(@alignCast(ctx));
            self.entered.* = true;
        }
    }.f;

    var composite = CompositeInteraction{
        .hoverable = Hoverable{
            .on_enter = onHoverEnter,
        },
    };

    var ctx = TestCtx{ .entered = &hover_entered };
    const area = Rect.new(10, 5, 20, 10);
    const event = MouseEvent{ .event_type = .move, .button = .none, .x = 15, .y = 8 };

    const result = composite.handleEvent(&ctx, event, area);
    try std.testing.expectEqual(InteractionResult.handled, result);
    try std.testing.expect(hover_entered);
    try std.testing.expect(composite.hover_state.hovering);
}

test "CompositeInteraction clickable and scrollable" {
    var clicked = false;
    var scroll_delta: i32 = 0;

    const TestCtx = struct {
        clicked: *bool,
        scroll_delta: *i32,
    };

    const onClick = struct {
        fn f(ctx: *anyopaque, _: MouseEvent) InteractionResult {
            const self: *TestCtx = @ptrCast(@alignCast(ctx));
            self.clicked.* = true;
            return .handled;
        }
    }.f;

    const onScroll = struct {
        fn f(ctx: *anyopaque, delta: i32, _: MouseEvent) InteractionResult {
            const self: *TestCtx = @ptrCast(@alignCast(ctx));
            self.scroll_delta.* = delta;
            return .handled;
        }
    }.f;

    var composite = CompositeInteraction{
        .clickable = Clickable{ .on_click = onClick },
        .scrollable = Scrollable{ .on_scroll = onScroll },
    };

    var ctx = TestCtx{ .clicked = &clicked, .scroll_delta = &scroll_delta };
    const area = Rect.new(10, 5, 20, 10);

    // Click event
    const click_event = MouseEvent{ .event_type = .press, .button = .left, .x = 15, .y = 8 };
    const result1 = composite.handleEvent(&ctx, click_event, area);
    try std.testing.expectEqual(InteractionResult.handled, result1);
    try std.testing.expect(clicked);

    // Scroll event
    const scroll_event = MouseEvent{ .event_type = .scroll_up, .button = .none, .x = 15, .y = 8 };
    const result2 = composite.handleEvent(&ctx, scroll_event, area);
    try std.testing.expectEqual(InteractionResult.handled, result2);
    try std.testing.expectEqual(@as(i32, -1), scroll_delta);
}

test "Hoverable.handleEvent move outside" {
    var left_called = false;

    const TestCtx = struct {
        left: *bool,
    };

    const onHoverLeave = struct {
        fn f(ctx: *anyopaque) void {
            const self: *TestCtx = @ptrCast(@alignCast(ctx));
            self.left.* = true;
        }
    }.f;

    var state = Hoverable.HoverState{};
    state.hovering = true; // Start in hovering state

    const hoverable = Hoverable{
        .on_leave = onHoverLeave,
    };

    var ctx = TestCtx{ .left = &left_called };
    const area = Rect.new(10, 5, 20, 10);
    const event = MouseEvent{ .event_type = .move, .button = .none, .x = 5, .y = 5 }; // Outside area

    const result = hoverable.handleEvent(&ctx, event, &state, area);
    try std.testing.expectEqual(InteractionResult.handled, result);
    try std.testing.expect(left_called);
    try std.testing.expect(!state.hovering);
}

test "Draggable.handleEvent release outside area" {
    var drag_ended = false;

    const TestCtx = struct {
        ended: *bool,
    };

    const onDragEnd = struct {
        fn f(ctx: *anyopaque, _: MouseEvent) void {
            const self: *TestCtx = @ptrCast(@alignCast(ctx));
            self.ended.* = true;
        }
    }.f;

    const onDrag = struct {
        fn f(_: *anyopaque, _: MouseEvent) InteractionResult {
            return .handled;
        }
    }.f;

    var state = Draggable.DragState{};
    state.active = true; // Start in dragging state
    state.start_x = 15;
    state.start_y = 8;
    state.button = .left;

    const draggable = Draggable{
        .on_drag = onDrag,
        .on_drag_end = onDragEnd,
    };

    var ctx = TestCtx{ .ended = &drag_ended };
    const area = Rect.new(10, 5, 20, 10);
    const event = MouseEvent{ .event_type = .release, .button = .left, .x = 50, .y = 50 }; // Far outside

    const result = draggable.handleEvent(&ctx, event, &state, area);
    try std.testing.expectEqual(InteractionResult.handled, result);
    try std.testing.expect(drag_ended);
    try std.testing.expect(!state.active);
}
