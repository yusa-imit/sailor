const std = @import("std");
const tui_mod = @import("tui.zig");
const Event = tui_mod.Event;
const KeyEvent = tui_mod.KeyEvent;
const KeyCode = tui_mod.KeyCode;
const Modifiers = tui_mod.Modifiers;
const mouse = @import("mouse.zig");
const gamepad = @import("gamepad.zig");
const touch = @import("touch.zig");

/// Input mapping configuration for remapping mouse/gamepad/touch to keyboard
pub const InputMap = struct {
    const Self = @This();

    allocator: std.mem.Allocator,

    // Mouse button mappings
    mouse_left_click: ?KeyEvent = null,
    mouse_right_click: ?KeyEvent = null,
    mouse_middle_click: ?KeyEvent = null,
    mouse_scroll_up: ?KeyEvent = null,
    mouse_scroll_down: ?KeyEvent = null,

    // Gamepad button mappings (common buttons)
    gamepad_a: ?KeyEvent = null, // South button
    gamepad_b: ?KeyEvent = null, // East button
    gamepad_x: ?KeyEvent = null, // West button
    gamepad_y: ?KeyEvent = null, // North button
    gamepad_dpad_up: ?KeyEvent = null,
    gamepad_dpad_down: ?KeyEvent = null,
    gamepad_dpad_left: ?KeyEvent = null,
    gamepad_dpad_right: ?KeyEvent = null,
    gamepad_start: ?KeyEvent = null,
    gamepad_select: ?KeyEvent = null,

    // Touch gesture mappings
    touch_tap: ?KeyEvent = null,
    touch_double_tap: ?KeyEvent = null,
    touch_long_press: ?KeyEvent = null,
    touch_swipe_left: ?KeyEvent = null,
    touch_swipe_right: ?KeyEvent = null,
    touch_swipe_up: ?KeyEvent = null,
    touch_swipe_down: ?KeyEvent = null,

    pub fn init(allocator: std.mem.Allocator) Self {
        return .{
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Self) void {
        _ = self; // No dynamic allocations to free currently
    }

    /// Map a mouse event to a key event
    pub fn mapMouse(self: Self, event: mouse.MouseEvent) ?KeyEvent {
        switch (event.event_type) {
            .press => {
                return switch (event.button) {
                    .left => self.mouse_left_click,
                    .right => self.mouse_right_click,
                    .middle => self.mouse_middle_click,
                    else => null,
                };
            },
            .scroll_up => return self.mouse_scroll_up,
            .scroll_down => return self.mouse_scroll_down,
            else => return null, // drag, move, release, double_click not mapped yet
        }
    }

    /// Map a gamepad event to a key event
    pub fn mapGamepad(self: Self, event: gamepad.GamepadEvent) ?KeyEvent {
        // Only map button press events
        if (event.event_type != .button_press) return null;
        if (event.button == null) return null;

        return switch (event.button.?) {
            .a => self.gamepad_a,
            .b => self.gamepad_b,
            .x => self.gamepad_x,
            .y => self.gamepad_y,
            .dpad_up => self.gamepad_dpad_up,
            .dpad_down => self.gamepad_dpad_down,
            .dpad_left => self.gamepad_dpad_left,
            .dpad_right => self.gamepad_dpad_right,
            .start => self.gamepad_start,
            .select => self.gamepad_select,
            else => null, // Other buttons not mapped
        };
    }

    /// Map a touch gesture to a key event
    pub fn mapTouch(self: Self, gesture: touch.TouchGesture) ?KeyEvent {
        return switch (gesture) {
            .tap => self.touch_tap,
            .double_tap => self.touch_double_tap,
            .long_press => self.touch_long_press,
            .swipe_left => self.touch_swipe_left,
            .swipe_right => self.touch_swipe_right,
            .swipe_up => self.touch_swipe_up,
            .swipe_down => self.touch_swipe_down,
            else => null, // pinch gestures not mapped to discrete keys
        };
    }

    /// Apply input mapping to an event. Returns mapped key event if applicable, null otherwise.
    pub fn apply(self: Self, event: Event) ?KeyEvent {
        return switch (event) {
            .mouse => |m| self.mapMouse(m),
            .gamepad => |g| self.mapGamepad(g),
            .touch => |t| self.mapTouch(t),
            else => null, // key/resize events pass through unchanged
        };
    }

    /// Set mouse left click mapping
    pub fn setMouseLeftClick(self: *Self, key: KeyCode, modifiers: Modifiers) void {
        self.mouse_left_click = .{ .code = key, .modifiers = modifiers };
    }

    /// Set mouse right click mapping
    pub fn setMouseRightClick(self: *Self, key: KeyCode, modifiers: Modifiers) void {
        self.mouse_right_click = .{ .code = key, .modifiers = modifiers };
    }

    /// Set mouse scroll mappings
    pub fn setMouseScroll(self: *Self, up_key: KeyCode, down_key: KeyCode) void {
        self.mouse_scroll_up = .{ .code = up_key, .modifiers = .{} };
        self.mouse_scroll_down = .{ .code = down_key, .modifiers = .{} };
    }

    /// Set gamepad D-pad arrow key mappings
    pub fn setGamepadDPadArrows(self: *Self) void {
        self.gamepad_dpad_up = .{ .code = .up, .modifiers = .{} };
        self.gamepad_dpad_down = .{ .code = .down, .modifiers = .{} };
        self.gamepad_dpad_left = .{ .code = .left, .modifiers = .{} };
        self.gamepad_dpad_right = .{ .code = .right, .modifiers = .{} };
    }

    /// Set gamepad face buttons to common vim-style keys
    pub fn setGamepadFaceButtonsVim(self: *Self) void {
        self.gamepad_a = .{ .code = .char, .modifiers = .{} }; // 'j' for down/select
        self.gamepad_b = .{ .code = .esc, .modifiers = .{} }; // Escape/back
        self.gamepad_x = .{ .code = .char, .modifiers = .{} }; // 'x' for action
        self.gamepad_y = .{ .code = .char, .modifiers = .{} }; // 'y' for yank/copy
    }

    /// Set touch swipe gestures to arrow keys
    pub fn setTouchSwipesArrows(self: *Self) void {
        self.touch_swipe_up = .{ .code = .up, .modifiers = .{} };
        self.touch_swipe_down = .{ .code = .down, .modifiers = .{} };
        self.touch_swipe_left = .{ .code = .left, .modifiers = .{} };
        self.touch_swipe_right = .{ .code = .right, .modifiers = .{} };
    }

    /// Set touch tap to Enter key
    pub fn setTouchTapEnter(self: *Self) void {
        self.touch_tap = .{ .code = .enter, .modifiers = .{} };
    }

    /// Clear all mappings
    pub fn clear(self: *Self) void {
        self.mouse_left_click = null;
        self.mouse_right_click = null;
        self.mouse_middle_click = null;
        self.mouse_scroll_up = null;
        self.mouse_scroll_down = null;

        self.gamepad_a = null;
        self.gamepad_b = null;
        self.gamepad_x = null;
        self.gamepad_y = null;
        self.gamepad_dpad_up = null;
        self.gamepad_dpad_down = null;
        self.gamepad_dpad_left = null;
        self.gamepad_dpad_right = null;
        self.gamepad_start = null;
        self.gamepad_select = null;

        self.touch_tap = null;
        self.touch_double_tap = null;
        self.touch_long_press = null;
        self.touch_swipe_left = null;
        self.touch_swipe_right = null;
        self.touch_swipe_up = null;
        self.touch_swipe_down = null;
    }
};

// ============================================================
// TESTS
// ============================================================

const testing = std.testing;

test "InputMap init and deinit" {
    var map = InputMap.init(testing.allocator);
    defer map.deinit();

    try testing.expectEqual(@as(?KeyEvent, null), map.mouse_left_click);
    try testing.expectEqual(@as(?KeyEvent, null), map.gamepad_a);
    try testing.expectEqual(@as(?KeyEvent, null), map.touch_tap);
}

test "InputMap - mouse left click mapping" {
    var map = InputMap.init(testing.allocator);
    defer map.deinit();

    map.setMouseLeftClick(.enter, .{});

    const mouse_event = mouse.MouseEvent{
        .x = 10,
        .y = 10,
        .button = .left,
        .event_type = .press,
        .modifiers = .{},
    };

    const mapped = map.mapMouse(mouse_event);
    try testing.expect(mapped != null);
    try testing.expectEqual(KeyCode.enter, mapped.?.code);
}

test "InputMap - mouse scroll mapping" {
    var map = InputMap.init(testing.allocator);
    defer map.deinit();

    map.setMouseScroll(.up, .down);

    const scroll_up = mouse.MouseEvent{
        .x = 10,
        .y = 10,
        .button = .none,
        .event_type = .scroll_up,
        .modifiers = .{},
    };

    const mapped_up = map.mapMouse(scroll_up);
    try testing.expect(mapped_up != null);
    try testing.expectEqual(KeyCode.up, mapped_up.?.code);

    const scroll_down = mouse.MouseEvent{
        .x = 10,
        .y = 10,
        .button = .none,
        .event_type = .scroll_down,
        .modifiers = .{},
    };

    const mapped_down = map.mapMouse(scroll_down);
    try testing.expect(mapped_down != null);
    try testing.expectEqual(KeyCode.down, mapped_down.?.code);
}

test "InputMap - gamepad D-pad arrows" {
    var map = InputMap.init(testing.allocator);
    defer map.deinit();

    map.setGamepadDPadArrows();

    const up_event = gamepad.GamepadEvent.buttonPress(0, .dpad_up);
    const mapped = map.mapGamepad(up_event);
    try testing.expect(mapped != null);
    try testing.expectEqual(KeyCode.up, mapped.?.code);

    const down_event = gamepad.GamepadEvent.buttonPress(0, .dpad_down);
    const mapped_down = map.mapGamepad(down_event);
    try testing.expectEqual(KeyCode.down, mapped_down.?.code);
}

test "InputMap - gamepad face buttons" {
    var map = InputMap.init(testing.allocator);
    defer map.deinit();

    map.gamepad_a = .{ .code = .enter, .modifiers = .{} };
    map.gamepad_b = .{ .code = .esc, .modifiers = .{} };

    const a_press = gamepad.GamepadEvent.buttonPress(0, .a);
    const mapped_a = map.mapGamepad(a_press);
    try testing.expectEqual(KeyCode.enter, mapped_a.?.code);

    const b_press = gamepad.GamepadEvent.buttonPress(0, .b);
    const mapped_b = map.mapGamepad(b_press);
    try testing.expectEqual(KeyCode.esc, mapped_b.?.code);
}

test "InputMap - touch swipes to arrows" {
    var map = InputMap.init(testing.allocator);
    defer map.deinit();

    map.setTouchSwipesArrows();

    const swipe_up = touch.TouchGesture{
        .swipe_up = .{
            .start = touch.TouchPoint.init(1, 10, 20),
            .end = touch.TouchPoint.init(1, 10, 10),
        },
    };

    const mapped = map.mapTouch(swipe_up);
    try testing.expect(mapped != null);
    try testing.expectEqual(KeyCode.up, mapped.?.code);

    const swipe_left = touch.TouchGesture{
        .swipe_left = .{
            .start = touch.TouchPoint.init(1, 20, 10),
            .end = touch.TouchPoint.init(1, 10, 10),
        },
    };

    const mapped_left = map.mapTouch(swipe_left);
    try testing.expectEqual(KeyCode.left, mapped_left.?.code);
}

test "InputMap - touch tap to enter" {
    var map = InputMap.init(testing.allocator);
    defer map.deinit();

    map.setTouchTapEnter();

    const tap = touch.TouchGesture{ .tap = touch.TouchPoint.init(1, 10, 10) };
    const mapped = map.mapTouch(tap);
    try testing.expect(mapped != null);
    try testing.expectEqual(KeyCode.enter, mapped.?.code);
}

test "InputMap.apply - mouse event" {
    var map = InputMap.init(testing.allocator);
    defer map.deinit();

    map.setMouseLeftClick(.enter, .{});

    const event = Event{
        .mouse = mouse.MouseEvent{
            .x = 10,
            .y = 10,
            .button = .left,
            .event_type = .press,
            .modifiers = .{},
        },
    };

    const mapped = map.apply(event);
    try testing.expect(mapped != null);
    try testing.expectEqual(KeyCode.enter, mapped.?.code);
}

test "InputMap.apply - gamepad event" {
    var map = InputMap.init(testing.allocator);
    defer map.deinit();

    map.setGamepadDPadArrows();

    const event = Event{ .gamepad = gamepad.GamepadEvent.buttonPress(0, .dpad_up) };
    const mapped = map.apply(event);
    try testing.expect(mapped != null);
    try testing.expectEqual(KeyCode.up, mapped.?.code);
}

test "InputMap.apply - touch event" {
    var map = InputMap.init(testing.allocator);
    defer map.deinit();

    map.setTouchTapEnter();

    const event = Event{
        .touch = .{ .tap = touch.TouchPoint.init(1, 10, 10) },
    };

    const mapped = map.apply(event);
    try testing.expect(mapped != null);
    try testing.expectEqual(KeyCode.enter, mapped.?.code);
}

test "InputMap.apply - key event passthrough" {
    var map = InputMap.init(testing.allocator);
    defer map.deinit();

    const event = Event{
        .key = .{ .code = .enter, .modifiers = .{} },
    };

    const mapped = map.apply(event);
    try testing.expectEqual(@as(?KeyEvent, null), mapped); // Keys pass through unchanged
}

test "InputMap - unmapped input returns null" {
    var map = InputMap.init(testing.allocator);
    defer map.deinit();

    const mouse_event = mouse.MouseEvent{
        .x = 10,
        .y = 10,
        .button = .left,
        .event_type = .press,
        .modifiers = .{},
    };

    const mapped = map.mapMouse(mouse_event);
    try testing.expectEqual(@as(?KeyEvent, null), mapped);
}

test "InputMap.clear - removes all mappings" {
    var map = InputMap.init(testing.allocator);
    defer map.deinit();

    map.setMouseLeftClick(.enter, .{});
    map.setGamepadDPadArrows();
    map.setTouchTapEnter();

    map.clear();

    try testing.expectEqual(@as(?KeyEvent, null), map.mouse_left_click);
    try testing.expectEqual(@as(?KeyEvent, null), map.gamepad_dpad_up);
    try testing.expectEqual(@as(?KeyEvent, null), map.touch_tap);
}

test "InputMap - mouse drag not mapped" {
    var map = InputMap.init(testing.allocator);
    defer map.deinit();

    map.setMouseLeftClick(.enter, .{});

    const drag_event = mouse.MouseEvent{
        .x = 10,
        .y = 10,
        .button = .left,
        .event_type = .drag, // Drag events not mapped
        .modifiers = .{},
    };

    const mapped = map.mapMouse(drag_event);
    try testing.expectEqual(@as(?KeyEvent, null), mapped);
}

test "InputMap - gamepad analog not mapped" {
    var map = InputMap.init(testing.allocator);
    defer map.deinit();

    map.setGamepadDPadArrows();

    const analog_event = gamepad.GamepadEvent{
        .event_type = .analog_move,
        .gamepad_id = 0,
        .left_stick = .{ .x = 0.5, .y = 0.0 },
    };

    const mapped = map.mapGamepad(analog_event);
    try testing.expectEqual(@as(?KeyEvent, null), mapped);
}

test "InputMap - touch pinch not mapped" {
    var map = InputMap.init(testing.allocator);
    defer map.deinit();

    map.setTouchSwipesArrows();

    const pinch_event = touch.TouchGesture{
        .pinch_in = .{
            .scale = 0.5,
            .center_x = 10,
            .center_y = 10,
        },
    };

    const mapped = map.mapTouch(pinch_event);
    try testing.expectEqual(@as(?KeyEvent, null), mapped);
}
