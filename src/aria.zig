const std = @import("std");

/// ARIA-like accessibility attributes for widgets
/// Provides semantic information for screen readers and assistive technologies
pub const AriaAttributes = struct {
    /// Widget role (button, textbox, list, etc.)
    role: ?Role = null,
    /// Accessible label
    label: ?[]const u8 = null,
    /// Extended description
    description: ?[]const u8 = null,
    /// Current value (for inputs, sliders, etc.)
    value: ?[]const u8 = null,
    /// Minimum value (for range widgets)
    value_min: ?f64 = null,
    /// Maximum value (for range widgets)
    value_max: ?f64 = null,
    /// Current value as number (for range widgets)
    value_now: ?f64 = null,
    /// Widget state
    state: State = .{},
    /// Live region announcement level
    live: ?LiveLevel = null,
    /// Indicates if widget can receive focus
    focusable: bool = true,

    /// ARIA role types
    pub const Role = enum {
        // Widget roles
        button,
        checkbox,
        radio,
        textbox,
        searchbox,
        slider,
        spinbutton,
        progressbar,
        tab,
        tabpanel,
        tablist,
        menuitem,
        menubar,
        menu,
        listbox,
        option,
        combobox,
        tree,
        treeitem,

        // Document structure roles
        article,
        banner,
        complementary,
        contentinfo,
        form,
        main,
        navigation,
        region,
        search,

        // Landmark roles
        application,
        dialog,
        alertdialog,
        alert,
        log,
        status,
        timer,

        // List roles
        list,
        listitem,
        table,
        row,
        cell,
        columnheader,
        rowheader,

        /// Convert role to string representation
        pub fn toString(self: Role) []const u8 {
            return @tagName(self);
        }
    };

    /// Widget state attributes
    pub const State = struct {
        /// Widget is disabled
        disabled: bool = false,
        /// Widget is checked (checkbox, radio)
        checked: ?bool = null,
        /// Widget is selected (option, tab)
        selected: bool = false,
        /// Widget is expanded (tree, menu)
        expanded: ?bool = null,
        /// Widget is pressed (button, toggle)
        pressed: ?bool = null,
        /// Widget is read-only
        readonly: bool = false,
        /// Widget is required (form input)
        required: bool = false,
        /// Widget has error
        invalid: bool = false,
    };

    /// Live region announcement level
    pub const LiveLevel = enum {
        /// Announce immediately
        assertive,
        /// Announce when convenient
        polite,
        /// Don't announce
        off,
    };

    /// Create default attributes
    pub fn init() AriaAttributes {
        return .{};
    }

    /// Set role
    pub fn withRole(self: AriaAttributes, role: Role) AriaAttributes {
        var attrs = self;
        attrs.role = role;
        return attrs;
    }

    /// Set label
    pub fn withLabel(self: AriaAttributes, label: []const u8) AriaAttributes {
        var attrs = self;
        attrs.label = label;
        return attrs;
    }

    /// Set description
    pub fn withDescription(self: AriaAttributes, description: []const u8) AriaAttributes {
        var attrs = self;
        attrs.description = description;
        return attrs;
    }

    /// Set value
    pub fn withValue(self: AriaAttributes, value: []const u8) AriaAttributes {
        var attrs = self;
        attrs.value = value;
        return attrs;
    }

    /// Set range (for sliders, spinbuttons, progressbars)
    pub fn withRange(self: AriaAttributes, min: f64, max: f64, now: f64) AriaAttributes {
        var attrs = self;
        attrs.value_min = min;
        attrs.value_max = max;
        attrs.value_now = now;
        return attrs;
    }

    /// Set disabled state
    pub fn withDisabled(self: AriaAttributes, disabled: bool) AriaAttributes {
        var attrs = self;
        attrs.state.disabled = disabled;
        return attrs;
    }

    /// Set checked state
    pub fn withChecked(self: AriaAttributes, checked: ?bool) AriaAttributes {
        var attrs = self;
        attrs.state.checked = checked;
        return attrs;
    }

    /// Set selected state
    pub fn withSelected(self: AriaAttributes, selected: bool) AriaAttributes {
        var attrs = self;
        attrs.state.selected = selected;
        return attrs;
    }

    /// Set expanded state
    pub fn withExpanded(self: AriaAttributes, expanded: ?bool) AriaAttributes {
        var attrs = self;
        attrs.state.expanded = expanded;
        return attrs;
    }

    /// Set pressed state
    pub fn withPressed(self: AriaAttributes, pressed: ?bool) AriaAttributes {
        var attrs = self;
        attrs.state.pressed = pressed;
        return attrs;
    }

    /// Set readonly state
    pub fn withReadonly(self: AriaAttributes, readonly: bool) AriaAttributes {
        var attrs = self;
        attrs.state.readonly = readonly;
        return attrs;
    }

    /// Set required state
    pub fn withRequired(self: AriaAttributes, required: bool) AriaAttributes {
        var attrs = self;
        attrs.state.required = required;
        return attrs;
    }

    /// Set invalid state
    pub fn withInvalid(self: AriaAttributes, invalid: bool) AriaAttributes {
        var attrs = self;
        attrs.state.invalid = invalid;
        return attrs;
    }

    /// Set live region level
    pub fn withLive(self: AriaAttributes, live: LiveLevel) AriaAttributes {
        var attrs = self;
        attrs.live = live;
        return attrs;
    }

    /// Set focusable
    pub fn withFocusable(self: AriaAttributes, focusable: bool) AriaAttributes {
        var attrs = self;
        attrs.focusable = focusable;
        return attrs;
    }

    /// Generate accessibility announcement text for screen readers
    pub fn generateAnnouncement(self: AriaAttributes, allocator: std.mem.Allocator) ![]const u8 {
        var parts = std.ArrayList([]const u8){};
        defer parts.deinit(allocator);

        var allocated_indices = std.ArrayList(usize){};
        defer allocated_indices.deinit(allocator);

        // Role
        if (self.role) |role| {
            try parts.append(allocator, role.toString());
        }

        // Label
        if (self.label) |label| {
            try parts.append(allocator, label);
        }

        // State
        if (self.state.disabled) {
            try parts.append(allocator, "disabled");
        }
        if (self.state.checked) |checked| {
            try parts.append(allocator, if (checked) "checked" else "unchecked");
        }
        if (self.state.selected) {
            try parts.append(allocator, "selected");
        }
        if (self.state.expanded) |expanded| {
            try parts.append(allocator, if (expanded) "expanded" else "collapsed");
        }
        if (self.state.pressed) |pressed| {
            try parts.append(allocator, if (pressed) "pressed" else "not pressed");
        }
        if (self.state.readonly) {
            try parts.append(allocator, "read-only");
        }
        if (self.state.required) {
            try parts.append(allocator, "required");
        }
        if (self.state.invalid) {
            try parts.append(allocator, "invalid");
        }

        // Value (allocated)
        if (self.value) |value| {
            const value_text = try std.fmt.allocPrint(allocator, "value: {s}", .{value});
            try allocated_indices.append(allocator, parts.items.len);
            try parts.append(allocator, value_text);
        }

        // Range (allocated)
        if (self.value_now) |now| {
            if (self.value_min) |min| {
                if (self.value_max) |max| {
                    const range_text = try std.fmt.allocPrint(
                        allocator,
                        "{d} of {d} to {d}",
                        .{ now, min, max },
                    );
                    try allocated_indices.append(allocator, parts.items.len);
                    try parts.append(allocator, range_text);
                }
            }
        }

        // Description
        if (self.description) |desc| {
            try parts.append(allocator, desc);
        }

        // Join parts with spaces
        const result = try std.mem.join(allocator, " ", parts.items);

        // Free allocated strings
        for (allocated_indices.items) |idx| {
            allocator.free(parts.items[idx]);
        }

        return result;
    }
};

/// Mixin for widgets to add ARIA attributes
pub fn AriaWidget(comptime T: type) type {
    return struct {
        base: T,
        aria: AriaAttributes = AriaAttributes.init(),

        pub fn init(base: T) @This() {
            return .{ .base = base };
        }

        pub fn withAria(self: @This(), aria: AriaAttributes) @This() {
            var widget = self;
            widget.aria = aria;
            return widget;
        }

        pub fn setRole(self: *@This(), role: AriaAttributes.Role) void {
            self.aria.role = role;
        }

        pub fn setLabel(self: *@This(), label: []const u8) void {
            self.aria.label = label;
        }

        pub fn setDescription(self: *@This(), description: []const u8) void {
            self.aria.description = description;
        }

        pub fn announce(self: @This(), allocator: std.mem.Allocator) ![]const u8 {
            return self.aria.generateAnnouncement(allocator);
        }
    };
}

test "aria: init default" {
    const attrs = AriaAttributes.init();
    try std.testing.expect(attrs.role == null);
    try std.testing.expect(attrs.label == null);
    try std.testing.expectEqual(false, attrs.state.disabled);
}

test "aria: with role" {
    const attrs = AriaAttributes.init().withRole(.button);
    try std.testing.expectEqual(AriaAttributes.Role.button, attrs.role.?);
}

test "aria: with label" {
    const attrs = AriaAttributes.init().withLabel("Submit");
    try std.testing.expectEqualStrings("Submit", attrs.label.?);
}

test "aria: with description" {
    const attrs = AriaAttributes.init().withDescription("Click to submit form");
    try std.testing.expectEqualStrings("Click to submit form", attrs.description.?);
}

test "aria: with value" {
    const attrs = AriaAttributes.init().withValue("Hello");
    try std.testing.expectEqualStrings("Hello", attrs.value.?);
}

test "aria: with range" {
    const attrs = AriaAttributes.init().withRange(0, 100, 50);
    try std.testing.expectEqual(@as(f64, 0), attrs.value_min.?);
    try std.testing.expectEqual(@as(f64, 100), attrs.value_max.?);
    try std.testing.expectEqual(@as(f64, 50), attrs.value_now.?);
}

test "aria: with disabled" {
    const attrs = AriaAttributes.init().withDisabled(true);
    try std.testing.expectEqual(true, attrs.state.disabled);
}

test "aria: with checked" {
    const attrs = AriaAttributes.init().withChecked(true);
    try std.testing.expectEqual(@as(?bool, true), attrs.state.checked);
}

test "aria: with selected" {
    const attrs = AriaAttributes.init().withSelected(true);
    try std.testing.expectEqual(true, attrs.state.selected);
}

test "aria: with expanded" {
    const attrs = AriaAttributes.init().withExpanded(true);
    try std.testing.expectEqual(@as(?bool, true), attrs.state.expanded);
}

test "aria: with pressed" {
    const attrs = AriaAttributes.init().withPressed(true);
    try std.testing.expectEqual(@as(?bool, true), attrs.state.pressed);
}

test "aria: with readonly" {
    const attrs = AriaAttributes.init().withReadonly(true);
    try std.testing.expectEqual(true, attrs.state.readonly);
}

test "aria: with required" {
    const attrs = AriaAttributes.init().withRequired(true);
    try std.testing.expectEqual(true, attrs.state.required);
}

test "aria: with invalid" {
    const attrs = AriaAttributes.init().withInvalid(true);
    try std.testing.expectEqual(true, attrs.state.invalid);
}

test "aria: with live" {
    const attrs = AriaAttributes.init().withLive(.assertive);
    try std.testing.expectEqual(AriaAttributes.LiveLevel.assertive, attrs.live.?);
}

test "aria: with focusable" {
    const attrs = AriaAttributes.init().withFocusable(false);
    try std.testing.expectEqual(false, attrs.focusable);
}

test "aria: role to string" {
    try std.testing.expectEqualStrings("button", AriaAttributes.Role.button.toString());
    try std.testing.expectEqualStrings("checkbox", AriaAttributes.Role.checkbox.toString());
    try std.testing.expectEqualStrings("textbox", AriaAttributes.Role.textbox.toString());
}

test "aria: generate announcement simple" {
    const attrs = AriaAttributes.init()
        .withRole(.button)
        .withLabel("Submit");

    const announcement = try attrs.generateAnnouncement(std.testing.allocator);
    defer std.testing.allocator.free(announcement);

    try std.testing.expect(std.mem.indexOf(u8, announcement, "button") != null);
    try std.testing.expect(std.mem.indexOf(u8, announcement, "Submit") != null);
}

test "aria: generate announcement with state" {
    const attrs = AriaAttributes.init()
        .withRole(.checkbox)
        .withLabel("Accept terms")
        .withChecked(true)
        .withRequired(true);

    const announcement = try attrs.generateAnnouncement(std.testing.allocator);
    defer std.testing.allocator.free(announcement);

    try std.testing.expect(std.mem.indexOf(u8, announcement, "checkbox") != null);
    try std.testing.expect(std.mem.indexOf(u8, announcement, "Accept terms") != null);
    try std.testing.expect(std.mem.indexOf(u8, announcement, "checked") != null);
    try std.testing.expect(std.mem.indexOf(u8, announcement, "required") != null);
}

test "aria: generate announcement with range" {
    const attrs = AriaAttributes.init()
        .withRole(.slider)
        .withLabel("Volume")
        .withRange(0, 100, 75);

    const announcement = try attrs.generateAnnouncement(std.testing.allocator);
    defer std.testing.allocator.free(announcement);

    try std.testing.expect(std.mem.indexOf(u8, announcement, "slider") != null);
    try std.testing.expect(std.mem.indexOf(u8, announcement, "Volume") != null);
    try std.testing.expect(std.mem.indexOf(u8, announcement, "75") != null);
}

test "aria: generate announcement disabled" {
    const attrs = AriaAttributes.init()
        .withRole(.button)
        .withLabel("Submit")
        .withDisabled(true);

    const announcement = try attrs.generateAnnouncement(std.testing.allocator);
    defer std.testing.allocator.free(announcement);

    try std.testing.expect(std.mem.indexOf(u8, announcement, "disabled") != null);
}

test "aria: generate announcement expanded/collapsed" {
    var attrs = AriaAttributes.init()
        .withRole(.tree)
        .withLabel("File tree")
        .withExpanded(true);

    {
        const announcement = try attrs.generateAnnouncement(std.testing.allocator);
        defer std.testing.allocator.free(announcement);
        try std.testing.expect(std.mem.indexOf(u8, announcement, "expanded") != null);
    }

    attrs = attrs.withExpanded(false);
    {
        const announcement = try attrs.generateAnnouncement(std.testing.allocator);
        defer std.testing.allocator.free(announcement);
        try std.testing.expect(std.mem.indexOf(u8, announcement, "collapsed") != null);
    }
}

test "aria: builder pattern" {
    const attrs = AriaAttributes.init()
        .withRole(.textbox)
        .withLabel("Username")
        .withDescription("Enter your username")
        .withRequired(true)
        .withInvalid(false);

    try std.testing.expectEqual(AriaAttributes.Role.textbox, attrs.role.?);
    try std.testing.expectEqualStrings("Username", attrs.label.?);
    try std.testing.expectEqualStrings("Enter your username", attrs.description.?);
    try std.testing.expectEqual(true, attrs.state.required);
    try std.testing.expectEqual(false, attrs.state.invalid);
}

test "aria: widget mixin" {
    const DummyWidget = struct {
        value: i32,
    };

    const AccessibleWidget = AriaWidget(DummyWidget);
    var widget = AccessibleWidget.init(.{ .value = 42 });

    widget.setRole(.button);
    widget.setLabel("Click me");
    widget.setDescription("A clickable button");

    try std.testing.expectEqual(AriaAttributes.Role.button, widget.aria.role.?);
    try std.testing.expectEqualStrings("Click me", widget.aria.label.?);
    try std.testing.expectEqualStrings("A clickable button", widget.aria.description.?);
    try std.testing.expectEqual(@as(i32, 42), widget.base.value);
}

test "aria: widget announcement" {
    const DummyWidget = struct {
        name: []const u8,
    };

    const AccessibleWidget = AriaWidget(DummyWidget);
    const widget = AccessibleWidget.init(.{ .name = "test" })
        .withAria(AriaAttributes.init()
        .withRole(.button)
        .withLabel("Submit form"));

    const announcement = try widget.announce(std.testing.allocator);
    defer std.testing.allocator.free(announcement);

    try std.testing.expect(std.mem.indexOf(u8, announcement, "button") != null);
    try std.testing.expect(std.mem.indexOf(u8, announcement, "Submit form") != null);
}

test "aria: all widget roles" {
    const roles = [_]AriaAttributes.Role{
        .button,
        .checkbox,
        .radio,
        .textbox,
        .searchbox,
        .slider,
        .spinbutton,
        .progressbar,
        .tab,
        .tabpanel,
        .tablist,
    };

    for (roles) |role| {
        const attrs = AriaAttributes.init().withRole(role);
        try std.testing.expectEqual(role, attrs.role.?);
    }
}

test "aria: all state flags" {
    const attrs = AriaAttributes.init()
        .withDisabled(true)
        .withChecked(true)
        .withSelected(true)
        .withExpanded(true)
        .withPressed(true)
        .withReadonly(true)
        .withRequired(true)
        .withInvalid(true);

    try std.testing.expectEqual(true, attrs.state.disabled);
    try std.testing.expectEqual(@as(?bool, true), attrs.state.checked);
    try std.testing.expectEqual(true, attrs.state.selected);
    try std.testing.expectEqual(@as(?bool, true), attrs.state.expanded);
    try std.testing.expectEqual(@as(?bool, true), attrs.state.pressed);
    try std.testing.expectEqual(true, attrs.state.readonly);
    try std.testing.expectEqual(true, attrs.state.required);
    try std.testing.expectEqual(true, attrs.state.invalid);
}
