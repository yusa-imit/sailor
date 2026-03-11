const std = @import("std");
const builtin = @import("builtin");

/// Gamepad button identifiers
pub const Button = enum {
    a, // South button (PlayStation X, Xbox A)
    b, // East button (PlayStation Circle, Xbox B)
    x, // West button (PlayStation Square, Xbox X)
    y, // North button (PlayStation Triangle, Xbox Y)
    left_shoulder,
    right_shoulder,
    left_trigger,
    right_trigger,
    select, // Back/Share button
    start, // Start/Options button
    left_stick, // L3
    right_stick, // R3
    dpad_up,
    dpad_down,
    dpad_left,
    dpad_right,
    guide, // Xbox/PlayStation home button

    pub fn isDirectional(self: Button) bool {
        return switch (self) {
            .dpad_up, .dpad_down, .dpad_left, .dpad_right => true,
            else => false,
        };
    }

    pub fn isTrigger(self: Button) bool {
        return switch (self) {
            .left_trigger, .right_trigger => true,
            else => false,
        };
    }
};

/// Analog stick axis values (-1.0 to 1.0)
pub const AnalogStick = struct {
    x: f32, // -1.0 = left, 1.0 = right
    y: f32, // -1.0 = up, 1.0 = down

    pub fn zero() AnalogStick {
        return .{ .x = 0.0, .y = 0.0 };
    }

    pub fn magnitude(self: AnalogStick) f32 {
        return @sqrt(self.x * self.x + self.y * self.y);
    }

    pub fn normalized(self: AnalogStick) AnalogStick {
        const mag = self.magnitude();
        if (mag < 0.001) return AnalogStick.zero();
        return .{ .x = self.x / mag, .y = self.y / mag };
    }

    pub fn withinDeadzone(self: AnalogStick, deadzone: f32) bool {
        return self.magnitude() < deadzone;
    }
};

/// Gamepad event types
pub const EventType = enum {
    button_press,
    button_release,
    analog_move,
    trigger_move,
    connected,
    disconnected,
};

/// Gamepad event containing button/analog state
pub const GamepadEvent = struct {
    event_type: EventType,
    gamepad_id: u32, // Gamepad device ID (0-3 typically)
    button: ?Button = null,
    left_stick: AnalogStick = AnalogStick.zero(),
    right_stick: AnalogStick = AnalogStick.zero(),
    left_trigger: f32 = 0.0, // 0.0 to 1.0
    right_trigger: f32 = 0.0, // 0.0 to 1.0
    timestamp: u64 = 0, // Milliseconds since epoch

    pub fn buttonPress(gamepad_id: u32, button: Button) GamepadEvent {
        return .{
            .event_type = .button_press,
            .gamepad_id = gamepad_id,
            .button = button,
            .timestamp = @intCast(std.time.milliTimestamp()),
        };
    }

    pub fn buttonRelease(gamepad_id: u32, button: Button) GamepadEvent {
        return .{
            .event_type = .button_release,
            .gamepad_id = gamepad_id,
            .button = button,
            .timestamp = @intCast(std.time.milliTimestamp()),
        };
    }

    pub fn analogMove(gamepad_id: u32, left: AnalogStick, right: AnalogStick) GamepadEvent {
        return .{
            .event_type = .analog_move,
            .gamepad_id = gamepad_id,
            .left_stick = left,
            .right_stick = right,
            .timestamp = @intCast(std.time.milliTimestamp()),
        };
    }

    pub fn triggerMove(gamepad_id: u32, left_trig: f32, right_trig: f32) GamepadEvent {
        return .{
            .event_type = .trigger_move,
            .gamepad_id = gamepad_id,
            .left_trigger = left_trig,
            .right_trigger = right_trig,
            .timestamp = @intCast(std.time.milliTimestamp()),
        };
    }

    pub fn connected(gamepad_id: u32) GamepadEvent {
        return .{
            .event_type = .connected,
            .gamepad_id = gamepad_id,
            .timestamp = @intCast(std.time.milliTimestamp()),
        };
    }

    pub fn disconnected(gamepad_id: u32) GamepadEvent {
        return .{
            .event_type = .disconnected,
            .gamepad_id = gamepad_id,
            .timestamp = @intCast(std.time.milliTimestamp()),
        };
    }
};

/// Gamepad state tracker for a single controller
pub const GamepadState = struct {
    gamepad_id: u32,
    connected: bool = false,
    buttons: std.EnumArray(Button, bool),
    left_stick: AnalogStick = AnalogStick.zero(),
    right_stick: AnalogStick = AnalogStick.zero(),
    left_trigger: f32 = 0.0,
    right_trigger: f32 = 0.0,
    deadzone: f32 = 0.15, // Default 15% deadzone

    pub fn init(gamepad_id: u32) GamepadState {
        const buttons = std.EnumArray(Button, bool).initFill(false);
        return .{
            .gamepad_id = gamepad_id,
            .buttons = buttons,
        };
    }

    pub fn isButtonPressed(self: GamepadState, button: Button) bool {
        return self.buttons.get(button);
    }

    pub fn handleEvent(self: *GamepadState, event: GamepadEvent) void {
        switch (event.event_type) {
            .button_press => {
                if (event.button) |btn| {
                    self.buttons.set(btn, true);
                }
            },
            .button_release => {
                if (event.button) |btn| {
                    self.buttons.set(btn, false);
                }
            },
            .analog_move => {
                self.left_stick = event.left_stick;
                self.right_stick = event.right_stick;
            },
            .trigger_move => {
                self.left_trigger = event.left_trigger;
                self.right_trigger = event.right_trigger;
            },
            .connected => {
                self.connected = true;
            },
            .disconnected => {
                self.connected = false;
                // Reset all state on disconnect
                self.buttons = std.EnumArray(Button, bool).initFill(false);
                self.left_stick = AnalogStick.zero();
                self.right_stick = AnalogStick.zero();
                self.left_trigger = 0.0;
                self.right_trigger = 0.0;
            },
        }
    }

    pub fn getLeftStick(self: GamepadState) AnalogStick {
        if (self.left_stick.withinDeadzone(self.deadzone)) {
            return AnalogStick.zero();
        }
        return self.left_stick;
    }

    pub fn getRightStick(self: GamepadState) AnalogStick {
        if (self.right_stick.withinDeadzone(self.deadzone)) {
            return AnalogStick.zero();
        }
        return self.right_stick;
    }

    pub fn getLeftTrigger(self: GamepadState) f32 {
        return if (self.left_trigger < self.deadzone) 0.0 else self.left_trigger;
    }

    pub fn getRightTrigger(self: GamepadState) f32 {
        return if (self.right_trigger < self.deadzone) 0.0 else self.right_trigger;
    }
};

/// Gamepad manager for multiple controllers
pub const GamepadManager = struct {
    allocator: std.mem.Allocator,
    gamepads: std.AutoHashMap(u32, GamepadState),
    max_gamepads: u32 = 4,

    pub fn init(allocator: std.mem.Allocator) GamepadManager {
        return .{
            .allocator = allocator,
            .gamepads = std.AutoHashMap(u32, GamepadState).init(allocator),
        };
    }

    pub fn deinit(self: *GamepadManager) void {
        self.gamepads.deinit();
    }

    pub fn handleEvent(self: *GamepadManager, event: GamepadEvent) !void {
        if (event.event_type == .connected) {
            if (self.gamepads.count() >= self.max_gamepads) return error.MaxGamepadsReached;
            var state = GamepadState.init(event.gamepad_id);
            state.connected = true;
            try self.gamepads.put(event.gamepad_id, state);
        } else if (event.event_type == .disconnected) {
            _ = self.gamepads.remove(event.gamepad_id);
        } else {
            if (self.gamepads.getPtr(event.gamepad_id)) |state| {
                state.handleEvent(event);
            }
        }
    }

    pub fn getGamepad(self: GamepadManager, gamepad_id: u32) ?*GamepadState {
        return self.gamepads.getPtr(gamepad_id);
    }

    pub fn isConnected(self: GamepadManager, gamepad_id: u32) bool {
        if (self.gamepads.get(gamepad_id)) |state| {
            return state.connected;
        }
        return false;
    }

    pub fn getConnectedCount(self: GamepadManager) usize {
        return self.gamepads.count();
    }

    pub fn getFirstConnected(self: GamepadManager) ?u32 {
        var iter = self.gamepads.keyIterator();
        if (iter.next()) |key| {
            return key.*;
        }
        return null;
    }
};

// Platform-specific gamepad input parsing

/// Parse Linux evdev gamepad input (placeholder - requires evdev integration)
pub fn parseLinuxEvdevEvent(data: []const u8) ?GamepadEvent {
    // This is a placeholder for actual evdev parsing
    // Real implementation would use /dev/input/eventX devices
    _ = data;
    return null;
}

/// Parse Windows XInput gamepad state (placeholder - requires WinAPI integration)
pub fn parseWindowsXInputState(gamepad_id: u32, state_data: []const u8) ?GamepadEvent {
    // This is a placeholder for actual XInput parsing
    // Real implementation would use XInputGetState API
    _ = gamepad_id;
    _ = state_data;
    return null;
}

/// Parse macOS HID gamepad input (placeholder - requires IOKit integration)
pub fn parseMacOSHIDEvent(data: []const u8) ?GamepadEvent {
    // This is a placeholder for actual IOKit HID parsing
    // Real implementation would use IOHIDManager
    _ = data;
    return null;
}

// Tests

test "Button classification" {
    try std.testing.expect(Button.dpad_up.isDirectional());
    try std.testing.expect(Button.dpad_left.isDirectional());
    try std.testing.expect(!Button.a.isDirectional());
    try std.testing.expect(Button.left_trigger.isTrigger());
    try std.testing.expect(!Button.x.isTrigger());
}

test "AnalogStick operations" {
    const stick = AnalogStick{ .x = 0.6, .y = 0.8 };
    try std.testing.expectApproxEqAbs(@as(f32, 1.0), stick.magnitude(), 0.01);

    const normalized = stick.normalized();
    try std.testing.expectApproxEqAbs(@as(f32, 0.6), normalized.x, 0.01);
    try std.testing.expectApproxEqAbs(@as(f32, 0.8), normalized.y, 0.01);

    const zero = AnalogStick.zero();
    try std.testing.expect(zero.withinDeadzone(0.1));
    try std.testing.expect(!stick.withinDeadzone(0.1));
}

test "GamepadEvent constructors" {
    const press = GamepadEvent.buttonPress(0, .a);
    try std.testing.expectEqual(EventType.button_press, press.event_type);
    try std.testing.expectEqual(@as(u32, 0), press.gamepad_id);
    try std.testing.expectEqual(Button.a, press.button.?);

    const release = GamepadEvent.buttonRelease(1, .b);
    try std.testing.expectEqual(EventType.button_release, release.event_type);
    try std.testing.expectEqual(@as(u32, 1), release.gamepad_id);

    const analog = GamepadEvent.analogMove(0, .{ .x = 0.5, .y = 0.5 }, AnalogStick.zero());
    try std.testing.expectEqual(EventType.analog_move, analog.event_type);
    try std.testing.expectApproxEqAbs(@as(f32, 0.5), analog.left_stick.x, 0.01);

    const trigger = GamepadEvent.triggerMove(0, 0.7, 0.3);
    try std.testing.expectEqual(EventType.trigger_move, trigger.event_type);
    try std.testing.expectApproxEqAbs(@as(f32, 0.7), trigger.left_trigger, 0.01);

    const conn = GamepadEvent.connected(2);
    try std.testing.expectEqual(EventType.connected, conn.event_type);
    try std.testing.expectEqual(@as(u32, 2), conn.gamepad_id);

    const disconn = GamepadEvent.disconnected(3);
    try std.testing.expectEqual(EventType.disconnected, disconn.event_type);
}

test "GamepadState button tracking" {
    var state = GamepadState.init(0);
    try std.testing.expect(!state.isButtonPressed(.a));

    const press = GamepadEvent.buttonPress(0, .a);
    state.handleEvent(press);
    try std.testing.expect(state.isButtonPressed(.a));

    const release = GamepadEvent.buttonRelease(0, .a);
    state.handleEvent(release);
    try std.testing.expect(!state.isButtonPressed(.a));
}

test "GamepadState analog stick tracking" {
    var state = GamepadState.init(0);
    state.deadzone = 0.1;

    const stick = AnalogStick{ .x = 0.8, .y = 0.6 };
    const event = GamepadEvent.analogMove(0, stick, AnalogStick.zero());
    state.handleEvent(event);

    const left = state.getLeftStick();
    try std.testing.expectApproxEqAbs(@as(f32, 0.8), left.x, 0.01);
    try std.testing.expectApproxEqAbs(@as(f32, 0.6), left.y, 0.01);
}

test "GamepadState deadzone handling" {
    var state = GamepadState.init(0);
    state.deadzone = 0.2;

    // Small movement within deadzone
    const small = AnalogStick{ .x = 0.1, .y = 0.1 };
    const event = GamepadEvent.analogMove(0, small, AnalogStick.zero());
    state.handleEvent(event);

    const stick = state.getLeftStick();
    try std.testing.expectApproxEqAbs(@as(f32, 0.0), stick.x, 0.01);
    try std.testing.expectApproxEqAbs(@as(f32, 0.0), stick.y, 0.01);
}

test "GamepadState trigger tracking" {
    var state = GamepadState.init(0);
    state.deadzone = 0.1;

    const event = GamepadEvent.triggerMove(0, 0.8, 0.3);
    state.handleEvent(event);

    try std.testing.expectApproxEqAbs(@as(f32, 0.8), state.getLeftTrigger(), 0.01);
    try std.testing.expectApproxEqAbs(@as(f32, 0.3), state.getRightTrigger(), 0.01);
}

test "GamepadState disconnect resets state" {
    var state = GamepadState.init(0);
    state.connected = true;
    const press = GamepadEvent.buttonPress(0, .a);
    state.handleEvent(press);
    try std.testing.expect(state.isButtonPressed(.a));

    const disconn = GamepadEvent.disconnected(0);
    state.handleEvent(disconn);
    try std.testing.expect(!state.connected);
    try std.testing.expect(!state.isButtonPressed(.a));
}

test "GamepadManager connect and disconnect" {
    const allocator = std.testing.allocator;
    var manager = GamepadManager.init(allocator);
    defer manager.deinit();

    try std.testing.expectEqual(@as(usize, 0), manager.getConnectedCount());

    const conn = GamepadEvent.connected(0);
    try manager.handleEvent(conn);
    try std.testing.expect(manager.isConnected(0));
    try std.testing.expectEqual(@as(usize, 1), manager.getConnectedCount());

    const disconn = GamepadEvent.disconnected(0);
    try manager.handleEvent(disconn);
    try std.testing.expect(!manager.isConnected(0));
    try std.testing.expectEqual(@as(usize, 0), manager.getConnectedCount());
}

test "GamepadManager multiple gamepads" {
    const allocator = std.testing.allocator;
    var manager = GamepadManager.init(allocator);
    defer manager.deinit();

    try manager.handleEvent(GamepadEvent.connected(0));
    try manager.handleEvent(GamepadEvent.connected(1));
    try manager.handleEvent(GamepadEvent.connected(2));

    try std.testing.expectEqual(@as(usize, 3), manager.getConnectedCount());
    try std.testing.expect(manager.isConnected(0));
    try std.testing.expect(manager.isConnected(1));
    try std.testing.expect(manager.isConnected(2));
}

test "GamepadManager max gamepads limit" {
    const allocator = std.testing.allocator;
    var manager = GamepadManager.init(allocator);
    defer manager.deinit();
    manager.max_gamepads = 2;

    try manager.handleEvent(GamepadEvent.connected(0));
    try manager.handleEvent(GamepadEvent.connected(1));

    // Third gamepad should fail
    const result = manager.handleEvent(GamepadEvent.connected(2));
    try std.testing.expectError(error.MaxGamepadsReached, result);
    try std.testing.expectEqual(@as(usize, 2), manager.getConnectedCount());
}

test "GamepadManager state updates" {
    const allocator = std.testing.allocator;
    var manager = GamepadManager.init(allocator);
    defer manager.deinit();

    try manager.handleEvent(GamepadEvent.connected(0));
    try manager.handleEvent(GamepadEvent.buttonPress(0, .a));

    const state = manager.getGamepad(0).?;
    try std.testing.expect(state.isButtonPressed(.a));

    try manager.handleEvent(GamepadEvent.buttonRelease(0, .a));
    try std.testing.expect(!state.isButtonPressed(.a));
}

test "GamepadManager get first connected" {
    const allocator = std.testing.allocator;
    var manager = GamepadManager.init(allocator);
    defer manager.deinit();

    try std.testing.expectEqual(@as(?u32, null), manager.getFirstConnected());

    try manager.handleEvent(GamepadEvent.connected(2));
    const first = manager.getFirstConnected();
    try std.testing.expect(first != null);
    try std.testing.expectEqual(@as(u32, 2), first.?);
}
