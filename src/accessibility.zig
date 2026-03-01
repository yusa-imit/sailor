const std = @import("std");

/// ARIA-like roles for widgets
pub const Role = enum {
    /// Generic application region
    application,
    /// Dialog or modal
    dialog,
    /// Alert or notification
    alert,
    /// Button or clickable element
    button,
    /// Text input field
    textbox,
    /// Multi-line text area
    textarea,
    /// List container
    list,
    /// List item
    listitem,
    /// Table container
    table,
    /// Table row
    row,
    /// Table cell
    cell,
    /// Tree container
    tree,
    /// Tree item
    treeitem,
    /// Tab container
    tablist,
    /// Single tab
    tab,
    /// Tab panel content
    tabpanel,
    /// Progress indicator
    progressbar,
    /// Status message
    status,
    /// Menu container
    menu,
    /// Menu item
    menuitem,
    /// Chart or graph
    chart,
    /// Generic container
    group,
    /// Decorative content (hidden from screen readers)
    presentation,
};

/// Widget state for accessibility
pub const State = struct {
    /// Whether the widget is focused
    focused: bool = false,
    /// Whether the widget is disabled
    disabled: bool = false,
    /// Whether the widget is expanded (for collapsible widgets)
    expanded: ?bool = null,
    /// Whether the widget is selected
    selected: bool = false,
    /// Whether the widget is checked (for checkboxes)
    checked: ?bool = null,
    /// Current value (for inputs, sliders, etc)
    value: ?[]const u8 = null,
    /// Value range min
    value_min: ?f64 = null,
    /// Value range max
    value_max: ?f64 = null,
    /// Current value as number
    value_now: ?f64 = null,
};

/// Accessibility metadata for a widget
pub const Metadata = struct {
    /// Widget role (required)
    role: Role,
    /// Human-readable label (required)
    label: []const u8,
    /// Detailed description (optional)
    description: ?[]const u8 = null,
    /// Current state
    state: State = .{},
    /// Live region politeness (for dynamic content updates)
    live: Live = .off,

    pub const Live = enum {
        /// Not a live region
        off,
        /// Announce updates politely (when user is idle)
        polite,
        /// Announce updates immediately (interrupts user)
        assertive,
    };
};

/// Accessibility hint builder for constructing screen reader announcements
pub const HintBuilder = struct {
    allocator: std.mem.Allocator,
    parts: std.ArrayList([]const u8),
    allocated_parts: std.ArrayList([]const u8),

    pub fn init(allocator: std.mem.Allocator) HintBuilder {
        return .{
            .allocator = allocator,
            .parts = std.ArrayList([]const u8){},
            .allocated_parts = std.ArrayList([]const u8){},
        };
    }

    pub fn deinit(self: *HintBuilder) void {
        for (self.allocated_parts.items) |part| {
            self.allocator.free(part);
        }
        self.allocated_parts.deinit(self.allocator);
        self.parts.deinit(self.allocator);
    }

    /// Add a role announcement
    pub fn role(self: *HintBuilder, r: Role) !void {
        const role_name = switch (r) {
            .application => "application",
            .dialog => "dialog",
            .alert => "alert",
            .button => "button",
            .textbox => "text input",
            .textarea => "text area",
            .list => "list",
            .listitem => "list item",
            .table => "table",
            .row => "row",
            .cell => "cell",
            .tree => "tree",
            .treeitem => "tree item",
            .tablist => "tab list",
            .tab => "tab",
            .tabpanel => "tab panel",
            .progressbar => "progress bar",
            .status => "status",
            .menu => "menu",
            .menuitem => "menu item",
            .chart => "chart",
            .group => "group",
            .presentation => return, // Skip decorative content
        };
        try self.parts.append(self.allocator, role_name);
    }

    /// Add a label
    pub fn label(self: *HintBuilder, text: []const u8) !void {
        try self.parts.append(self.allocator, text);
    }

    /// Add state information
    pub fn state(self: *HintBuilder, s: State) !void {
        if (s.focused) try self.parts.append(self.allocator, "focused");
        if (s.disabled) try self.parts.append(self.allocator, "disabled");
        if (s.selected) try self.parts.append(self.allocator, "selected");

        if (s.expanded) |exp| {
            try self.parts.append(self.allocator, if (exp) "expanded" else "collapsed");
        }

        if (s.checked) |chk| {
            try self.parts.append(self.allocator, if (chk) "checked" else "unchecked");
        }

        if (s.value) |val| {
            try self.parts.append(self.allocator, val);
        }

        if (s.value_now) |now| {
            if (s.value_min) |min| {
                if (s.value_max) |max| {
                    const percent = (now - min) / (max - min) * 100.0;
                    const percent_str = try std.fmt.allocPrint(self.allocator, "{d:.0}%", .{percent});
                    try self.allocated_parts.append(self.allocator, percent_str);
                    try self.parts.append(self.allocator, percent_str);
                }
            }
        }
    }

    /// Build final hint string
    pub fn build(self: *HintBuilder) ![]const u8 {
        return try std.mem.join(self.allocator, ", ", self.parts.items);
    }
};

/// Generate screen reader hint from metadata
pub fn generateHint(allocator: std.mem.Allocator, metadata: Metadata) ![]const u8 {
    var builder = HintBuilder.init(allocator);
    defer builder.deinit();

    try builder.role(metadata.role);
    try builder.label(metadata.label);

    if (metadata.description) |desc| {
        try builder.parts.append(builder.allocator, desc);
    }

    try builder.state(metadata.state);

    return try builder.build();
}

test "accessibility: role names" {
    var builder = HintBuilder.init(std.testing.allocator);
    defer builder.deinit();

    try builder.role(.button);
    const hint = try builder.build();
    defer std.testing.allocator.free(hint);

    try std.testing.expectEqualStrings("button", hint);
}

test "accessibility: label and role" {
    var builder = HintBuilder.init(std.testing.allocator);
    defer builder.deinit();

    try builder.role(.button);
    try builder.label("Submit");
    const hint = try builder.build();
    defer std.testing.allocator.free(hint);

    try std.testing.expectEqualStrings("button, Submit", hint);
}

test "accessibility: state focused" {
    var builder = HintBuilder.init(std.testing.allocator);
    defer builder.deinit();

    try builder.role(.textbox);
    try builder.label("Username");
    try builder.state(.{ .focused = true });
    const hint = try builder.build();
    defer std.testing.allocator.free(hint);

    try std.testing.expectEqualStrings("text input, Username, focused", hint);
}

test "accessibility: state disabled" {
    var builder = HintBuilder.init(std.testing.allocator);
    defer builder.deinit();

    try builder.role(.button);
    try builder.label("Save");
    try builder.state(.{ .disabled = true });
    const hint = try builder.build();
    defer std.testing.allocator.free(hint);

    try std.testing.expectEqualStrings("button, Save, disabled", hint);
}

test "accessibility: state expanded/collapsed" {
    var builder = HintBuilder.init(std.testing.allocator);
    defer builder.deinit();

    try builder.role(.treeitem);
    try builder.label("Folder");
    try builder.state(.{ .expanded = true });
    const hint = try builder.build();
    defer std.testing.allocator.free(hint);

    try std.testing.expectEqualStrings("tree item, Folder, expanded", hint);
}

test "accessibility: state checked" {
    var builder = HintBuilder.init(std.testing.allocator);
    defer builder.deinit();

    try builder.role(.menuitem);
    try builder.label("Dark mode");
    try builder.state(.{ .checked = true });
    const hint = try builder.build();
    defer std.testing.allocator.free(hint);

    try std.testing.expectEqualStrings("menu item, Dark mode, checked", hint);
}

test "accessibility: value with percentage" {
    var builder = HintBuilder.init(std.testing.allocator);
    defer builder.deinit();

    try builder.role(.progressbar);
    try builder.label("Upload progress");
    try builder.state(.{
        .value_min = 0,
        .value_max = 100,
        .value_now = 75,
    });
    const hint = try builder.build();
    defer std.testing.allocator.free(hint);

    try std.testing.expect(std.mem.indexOf(u8, hint, "75%") != null);
}

test "accessibility: generateHint simple" {
    const metadata = Metadata{
        .role = .button,
        .label = "OK",
    };

    const hint = try generateHint(std.testing.allocator, metadata);
    defer std.testing.allocator.free(hint);

    try std.testing.expectEqualStrings("button, OK", hint);
}

test "accessibility: generateHint with description" {
    const metadata = Metadata{
        .role = .textbox,
        .label = "Search",
        .description = "Press Enter to search",
    };

    const hint = try generateHint(std.testing.allocator, metadata);
    defer std.testing.allocator.free(hint);

    try std.testing.expect(std.mem.indexOf(u8, hint, "text input") != null);
    try std.testing.expect(std.mem.indexOf(u8, hint, "Search") != null);
    try std.testing.expect(std.mem.indexOf(u8, hint, "Press Enter") != null);
}

test "accessibility: generateHint with state" {
    const metadata = Metadata{
        .role = .list,
        .label = "Tasks",
        .state = .{
            .focused = true,
            .value = "3 items",
        },
    };

    const hint = try generateHint(std.testing.allocator, metadata);
    defer std.testing.allocator.free(hint);

    try std.testing.expect(std.mem.indexOf(u8, hint, "list") != null);
    try std.testing.expect(std.mem.indexOf(u8, hint, "Tasks") != null);
    try std.testing.expect(std.mem.indexOf(u8, hint, "focused") != null);
    try std.testing.expect(std.mem.indexOf(u8, hint, "3 items") != null);
}

test "accessibility: presentation role is skipped" {
    var builder = HintBuilder.init(std.testing.allocator);
    defer builder.deinit();

    try builder.role(.presentation);
    try builder.label("Decorative border");
    const hint = try builder.build();
    defer std.testing.allocator.free(hint);

    // Only label should be present, role is skipped
    try std.testing.expectEqualStrings("Decorative border", hint);
}
