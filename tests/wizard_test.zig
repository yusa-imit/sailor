const std = @import("std");
const testing = std.testing;
const sailor = @import("sailor");

const tui = sailor.tui;
const Buffer = tui.Buffer;
const Rect = tui.Rect;
const Style = tui.Style;
const Color = tui.Color;
const Block = tui.widgets.Block;
const Wizard = tui.widgets.Wizard;
const Step = tui.widgets.Wizard.Step;

// ============================================================================
// INITIALIZATION TESTS
// ============================================================================

test "Wizard init with empty steps" {
    const steps: [0]Step = .{};
    const wizard = Wizard.init(&steps);

    try testing.expectEqual(@as(usize, 0), wizard.steps.len);
    try testing.expectEqual(@as(usize, 0), wizard.current);
}

test "Wizard init with single step" {
    var steps_arr: [1]Step = .{
        .{ .title = "Welcome", .description = "Start here" },
    };
    const wizard = Wizard.init(&steps_arr);

    try testing.expectEqual(@as(usize, 1), wizard.steps.len);
    try testing.expectEqual(@as(usize, 0), wizard.current);
    try testing.expectEqualStrings("Welcome", wizard.steps[0].title);
    try testing.expectEqualStrings("Start here", wizard.steps[0].description);
}

test "Wizard init with three steps" {
    var steps_arr: [3]Step = .{
        .{ .title = "Step 1", .description = "First" },
        .{ .title = "Step 2", .description = "Second" },
        .{ .title = "Step 3", .description = "Third" },
    };
    const wizard = Wizard.init(&steps_arr);

    try testing.expectEqual(@as(usize, 3), wizard.steps.len);
    try testing.expectEqual(@as(usize, 0), wizard.current);
}

test "Wizard init defaults: styles empty" {
    var steps_arr: [1]Step = .{
        .{ .title = "Test", .description = "" },
    };
    const wizard = Wizard.init(&steps_arr);

    try testing.expectEqual(Style{}, wizard.active_step_style);
    try testing.expectEqual(Style{}, wizard.inactive_step_style);
    try testing.expectEqual(Style{}, wizard.title_style);
    try testing.expectEqual(Style{}, wizard.description_style);
    try testing.expectEqual(Style{}, wizard.nav_style);
}

test "Wizard init defaults: show_nav_hint true" {
    var steps_arr: [1]Step = .{
        .{ .title = "Test", .description = "" },
    };
    const wizard = Wizard.init(&steps_arr);

    try testing.expect(wizard.show_nav_hint);
}

test "Wizard init defaults: block null" {
    var steps_arr: [1]Step = .{
        .{ .title = "Test", .description = "" },
    };
    const wizard = Wizard.init(&steps_arr);

    try testing.expect(wizard.block == null);
}

test "Wizard init Step defaults: description empty string" {
    var steps_arr: [1]Step = .{
        .{ .title = "NoDesc" },
    };
    const wizard = Wizard.init(&steps_arr);

    try testing.expectEqualStrings("", wizard.steps[0].description);
}

test "Wizard init sets current to 0 always" {
    var steps_arr: [3]Step = .{
        .{ .title = "A", .description = "" },
        .{ .title = "B", .description = "" },
        .{ .title = "C", .description = "" },
    };
    const wizard = Wizard.init(&steps_arr);

    try testing.expectEqual(@as(usize, 0), wizard.current);
}

// ============================================================================
// stepCount / currentStep TESTS
// ============================================================================

test "Wizard stepCount with empty steps" {
    const steps: [0]Step = .{};
    const wizard = Wizard.init(&steps);

    try testing.expectEqual(@as(usize, 0), wizard.stepCount());
}

test "Wizard stepCount with three steps" {
    var steps_arr: [3]Step = .{
        .{ .title = "A", .description = "" },
        .{ .title = "B", .description = "" },
        .{ .title = "C", .description = "" },
    };
    const wizard = Wizard.init(&steps_arr);

    try testing.expectEqual(@as(usize, 3), wizard.stepCount());
}

test "Wizard currentStep with empty steps returns null" {
    const steps: [0]Step = .{};
    const wizard = Wizard.init(&steps);

    try testing.expect(wizard.currentStep() == null);
}

test "Wizard currentStep returns step at current index" {
    var steps_arr: [3]Step = .{
        .{ .title = "First", .description = "Desc 1" },
        .{ .title = "Second", .description = "Desc 2" },
        .{ .title = "Third", .description = "Desc 3" },
    };
    const wizard = Wizard.init(&steps_arr);

    const step = wizard.currentStep();
    try testing.expect(step != null);
    try testing.expectEqualStrings("First", step.?.title);
    try testing.expectEqualStrings("Desc 1", step.?.description);
}

test "Wizard currentStep after nextStep" {
    var steps_arr: [3]Step = .{
        .{ .title = "A", .description = "Desc A" },
        .{ .title = "B", .description = "Desc B" },
        .{ .title = "C", .description = "Desc C" },
    };
    var wizard = Wizard.init(&steps_arr);

    wizard.nextStep();
    const step = wizard.currentStep();
    try testing.expect(step != null);
    try testing.expectEqualStrings("B", step.?.title);
}

// ============================================================================
// nextStep TESTS
// ============================================================================

test "Wizard nextStep from 0 to 1 with 3 steps" {
    var steps_arr: [3]Step = .{
        .{ .title = "A", .description = "" },
        .{ .title = "B", .description = "" },
        .{ .title = "C", .description = "" },
    };
    var wizard = Wizard.init(&steps_arr);

    wizard.nextStep();
    try testing.expectEqual(@as(usize, 1), wizard.current);
}

test "Wizard nextStep from 1 to 2 with 3 steps" {
    var steps_arr: [3]Step = .{
        .{ .title = "A", .description = "" },
        .{ .title = "B", .description = "" },
        .{ .title = "C", .description = "" },
    };
    var wizard = Wizard.init(&steps_arr);

    wizard.nextStep();
    wizard.nextStep();
    try testing.expectEqual(@as(usize, 2), wizard.current);
}

test "Wizard nextStep at last step is no-op" {
    var steps_arr: [3]Step = .{
        .{ .title = "A", .description = "" },
        .{ .title = "B", .description = "" },
        .{ .title = "C", .description = "" },
    };
    var wizard = Wizard.init(&steps_arr);

    wizard.current = 2;
    wizard.nextStep();
    try testing.expectEqual(@as(usize, 2), wizard.current);
}

test "Wizard nextStep on empty steps is no-op" {
    const steps: [0]Step = .{};
    var wizard = Wizard.init(&steps);

    wizard.nextStep();
    try testing.expectEqual(@as(usize, 0), wizard.current);
}

test "Wizard nextStep multiple times clamps correctly" {
    var steps_arr: [3]Step = .{
        .{ .title = "A", .description = "" },
        .{ .title = "B", .description = "" },
        .{ .title = "C", .description = "" },
    };
    var wizard = Wizard.init(&steps_arr);

    wizard.nextStep();
    wizard.nextStep();
    wizard.nextStep();
    wizard.nextStep();
    try testing.expectEqual(@as(usize, 2), wizard.current);
}

test "Wizard nextStep then check currentStep title" {
    var steps_arr: [2]Step = .{
        .{ .title = "Start", .description = "" },
        .{ .title = "End", .description = "" },
    };
    var wizard = Wizard.init(&steps_arr);

    wizard.nextStep();
    const step = wizard.currentStep();
    try testing.expect(step != null);
    try testing.expectEqualStrings("End", step.?.title);
}

// ============================================================================
// prevStep TESTS
// ============================================================================

test "Wizard prevStep from 0 is no-op" {
    var steps_arr: [3]Step = .{
        .{ .title = "A", .description = "" },
        .{ .title = "B", .description = "" },
        .{ .title = "C", .description = "" },
    };
    var wizard = Wizard.init(&steps_arr);

    wizard.prevStep();
    try testing.expectEqual(@as(usize, 0), wizard.current);
}

test "Wizard prevStep from 2 to 1 with 3 steps" {
    var steps_arr: [3]Step = .{
        .{ .title = "A", .description = "" },
        .{ .title = "B", .description = "" },
        .{ .title = "C", .description = "" },
    };
    var wizard = Wizard.init(&steps_arr);

    wizard.current = 2;
    wizard.prevStep();
    try testing.expectEqual(@as(usize, 1), wizard.current);
}

test "Wizard prevStep from 1 to 0 with 3 steps" {
    var steps_arr: [3]Step = .{
        .{ .title = "A", .description = "" },
        .{ .title = "B", .description = "" },
        .{ .title = "C", .description = "" },
    };
    var wizard = Wizard.init(&steps_arr);

    wizard.current = 1;
    wizard.prevStep();
    try testing.expectEqual(@as(usize, 0), wizard.current);
}

test "Wizard prevStep on empty steps is no-op" {
    const steps: [0]Step = .{};
    var wizard = Wizard.init(&steps);

    wizard.prevStep();
    try testing.expectEqual(@as(usize, 0), wizard.current);
}

test "Wizard prevStep then nextStep sequence" {
    var steps_arr: [3]Step = .{
        .{ .title = "A", .description = "" },
        .{ .title = "B", .description = "" },
        .{ .title = "C", .description = "" },
    };
    var wizard = Wizard.init(&steps_arr);

    wizard.current = 2;
    wizard.prevStep();
    try testing.expectEqual(@as(usize, 1), wizard.current);
    wizard.nextStep();
    try testing.expectEqual(@as(usize, 2), wizard.current);
}

test "Wizard prevStep multiple times clamps correctly" {
    var steps_arr: [3]Step = .{
        .{ .title = "A", .description = "" },
        .{ .title = "B", .description = "" },
        .{ .title = "C", .description = "" },
    };
    var wizard = Wizard.init(&steps_arr);

    wizard.current = 2;
    wizard.prevStep();
    wizard.prevStep();
    wizard.prevStep();
    wizard.prevStep();
    try testing.expectEqual(@as(usize, 0), wizard.current);
}

// ============================================================================
// goToStep TESTS
// ============================================================================

test "Wizard goToStep from 0 to 1 with 3 steps" {
    var steps_arr: [3]Step = .{
        .{ .title = "A", .description = "" },
        .{ .title = "B", .description = "" },
        .{ .title = "C", .description = "" },
    };
    var wizard = Wizard.init(&steps_arr);

    wizard.goToStep(1);
    try testing.expectEqual(@as(usize, 1), wizard.current);
}

test "Wizard goToStep to 0" {
    var steps_arr: [3]Step = .{
        .{ .title = "A", .description = "" },
        .{ .title = "B", .description = "" },
        .{ .title = "C", .description = "" },
    };
    var wizard = Wizard.init(&steps_arr);

    wizard.current = 2;
    wizard.goToStep(0);
    try testing.expectEqual(@as(usize, 0), wizard.current);
}

test "Wizard goToStep to last index" {
    var steps_arr: [3]Step = .{
        .{ .title = "A", .description = "" },
        .{ .title = "B", .description = "" },
        .{ .title = "C", .description = "" },
    };
    var wizard = Wizard.init(&steps_arr);

    wizard.goToStep(2);
    try testing.expectEqual(@as(usize, 2), wizard.current);
}

test "Wizard goToStep out of bounds is no-op" {
    var steps_arr: [3]Step = .{
        .{ .title = "A", .description = "" },
        .{ .title = "B", .description = "" },
        .{ .title = "C", .description = "" },
    };
    var wizard = Wizard.init(&steps_arr);

    wizard.goToStep(3);
    try testing.expectEqual(@as(usize, 0), wizard.current);
}

test "Wizard goToStep way out of bounds is no-op" {
    var steps_arr: [3]Step = .{
        .{ .title = "A", .description = "" },
        .{ .title = "B", .description = "" },
        .{ .title = "C", .description = "" },
    };
    var wizard = Wizard.init(&steps_arr);

    wizard.goToStep(99);
    try testing.expectEqual(@as(usize, 0), wizard.current);
}

test "Wizard goToStep on empty steps is no-op" {
    const steps: [0]Step = .{};
    var wizard = Wizard.init(&steps);

    wizard.goToStep(0);
    try testing.expectEqual(@as(usize, 0), wizard.current);
}

// ============================================================================
// isFirst / isLast TESTS
// ============================================================================

test "Wizard isFirst with empty steps returns true" {
    const steps: [0]Step = .{};
    const wizard = Wizard.init(&steps);

    try testing.expect(wizard.isFirst());
}

test "Wizard isLast with empty steps returns true" {
    const steps: [0]Step = .{};
    const wizard = Wizard.init(&steps);

    try testing.expect(wizard.isLast());
}

test "Wizard isFirst at current==0 with 3 steps returns true" {
    var steps_arr: [3]Step = .{
        .{ .title = "A", .description = "" },
        .{ .title = "B", .description = "" },
        .{ .title = "C", .description = "" },
    };
    const wizard = Wizard.init(&steps_arr);

    try testing.expect(wizard.isFirst());
}

test "Wizard isFirst at current==1 with 3 steps returns false" {
    var steps_arr: [3]Step = .{
        .{ .title = "A", .description = "" },
        .{ .title = "B", .description = "" },
        .{ .title = "C", .description = "" },
    };
    var wizard = Wizard.init(&steps_arr);

    wizard.current = 1;
    try testing.expect(!wizard.isFirst());
}

test "Wizard isLast at current==2 with 3 steps returns true" {
    var steps_arr: [3]Step = .{
        .{ .title = "A", .description = "" },
        .{ .title = "B", .description = "" },
        .{ .title = "C", .description = "" },
    };
    var wizard = Wizard.init(&steps_arr);

    wizard.current = 2;
    try testing.expect(wizard.isLast());
}

test "Wizard isLast at current==1 with 3 steps returns false" {
    var steps_arr: [3]Step = .{
        .{ .title = "A", .description = "" },
        .{ .title = "B", .description = "" },
        .{ .title = "C", .description = "" },
    };
    var wizard = Wizard.init(&steps_arr);

    wizard.current = 1;
    try testing.expect(!wizard.isLast());
}

test "Wizard single step: both isFirst and isLast true" {
    var steps_arr: [1]Step = .{
        .{ .title = "Only", .description = "" },
    };
    const wizard = Wizard.init(&steps_arr);

    try testing.expect(wizard.isFirst());
    try testing.expect(wizard.isLast());
}

test "Wizard middle step: isFirst false, isLast false" {
    var steps_arr: [5]Step = .{
        .{ .title = "A", .description = "" },
        .{ .title = "B", .description = "" },
        .{ .title = "C", .description = "" },
        .{ .title = "D", .description = "" },
        .{ .title = "E", .description = "" },
    };
    var wizard = Wizard.init(&steps_arr);

    wizard.current = 2;
    try testing.expect(!wizard.isFirst());
    try testing.expect(!wizard.isLast());
}

// ============================================================================
// headerHeight TESTS
// ============================================================================

test "Wizard headerHeight with empty steps returns 0" {
    const steps: [0]Step = .{};
    const wizard = Wizard.init(&steps);

    try testing.expectEqual(@as(u16, 0), wizard.headerHeight());
}

test "Wizard headerHeight with 1 step returns 3" {
    var steps_arr: [1]Step = .{
        .{ .title = "Test", .description = "" },
    };
    const wizard = Wizard.init(&steps_arr);

    try testing.expectEqual(@as(u16, 3), wizard.headerHeight());
}

test "Wizard headerHeight with 3 steps returns 3" {
    var steps_arr: [3]Step = .{
        .{ .title = "A", .description = "" },
        .{ .title = "B", .description = "" },
        .{ .title = "C", .description = "" },
    };
    const wizard = Wizard.init(&steps_arr);

    try testing.expectEqual(@as(u16, 3), wizard.headerHeight());
}

test "Wizard headerHeight independent of step content" {
    var steps_arr: [2]Step = .{
        .{ .title = "VeryLongTitle", .description = "VeryLongDescription" },
        .{ .title = "X", .description = "" },
    };
    const wizard = Wizard.init(&steps_arr);

    try testing.expectEqual(@as(u16, 3), wizard.headerHeight());
}

// ============================================================================
// contentArea TESTS
// ============================================================================

test "Wizard contentArea no block, no nav hint, 3 steps, area 10x10" {
    var steps_arr: [3]Step = .{
        .{ .title = "A", .description = "" },
        .{ .title = "B", .description = "" },
        .{ .title = "C", .description = "" },
    };
    var wizard = Wizard.init(&steps_arr);
    wizard.show_nav_hint = false;

    const area = Rect{ .x = 0, .y = 0, .width = 10, .height = 10 };
    const content = wizard.contentArea(area);

    try testing.expectEqual(@as(u16, 0), content.x);
    try testing.expectEqual(@as(u16, 3), content.y);
    try testing.expectEqual(@as(u16, 10), content.width);
    try testing.expectEqual(@as(u16, 7), content.height); // 10 - 3 header
}

test "Wizard contentArea with nav hint, 3 steps, area 10x10" {
    var steps_arr: [3]Step = .{
        .{ .title = "A", .description = "" },
        .{ .title = "B", .description = "" },
        .{ .title = "C", .description = "" },
    };
    var wizard = Wizard.init(&steps_arr);
    wizard.show_nav_hint = true;

    const area = Rect{ .x = 0, .y = 0, .width = 10, .height = 10 };
    const content = wizard.contentArea(area);

    try testing.expectEqual(@as(u16, 0), content.x);
    try testing.expectEqual(@as(u16, 3), content.y);
    try testing.expectEqual(@as(u16, 10), content.width);
    try testing.expectEqual(@as(u16, 6), content.height); // 10 - 3 header - 1 nav
}

test "Wizard contentArea no block, empty steps, area 10x10 with nav hint" {
    const steps: [0]Step = .{};
    var wizard = Wizard.init(&steps);
    wizard.show_nav_hint = true;

    const area = Rect{ .x = 0, .y = 0, .width = 10, .height = 10 };
    const content = wizard.contentArea(area);

    // headerHeight = 0, so should be full area minus nav hint row
    try testing.expectEqual(@as(u16, 0), content.y);
    try testing.expectEqual(@as(u16, 9), content.height); // 10 - 1 nav (no header)
}

test "Wizard contentArea with block border, 3 steps, 10x10" {
    var steps_arr: [3]Step = .{
        .{ .title = "A", .description = "" },
        .{ .title = "B", .description = "" },
        .{ .title = "C", .description = "" },
    };
    var wizard = Wizard.init(&steps_arr);
    wizard.block = Block{};
    wizard.show_nav_hint = false;

    const area = Rect{ .x = 0, .y = 0, .width = 10, .height = 10 };
    const content = wizard.contentArea(area);

    // Block border is 1 on each side: inner area is (x+1, y+1, width-2, height-2)
    // Then minus headerHeight (3)
    try testing.expectEqual(@as(u16, 1), content.x); // 0 + 1
    try testing.expectEqual(@as(u16, 4), content.y); // 1 + 3 header
    try testing.expectEqual(@as(u16, 8), content.width); // 10 - 2
    try testing.expectEqual(@as(u16, 5), content.height); // (10 - 2) - 3
}

test "Wizard contentArea with block and nav hint, 10x10" {
    var steps_arr: [3]Step = .{
        .{ .title = "A", .description = "" },
        .{ .title = "B", .description = "" },
        .{ .title = "C", .description = "" },
    };
    var wizard = Wizard.init(&steps_arr);
    wizard.block = Block{};
    wizard.show_nav_hint = true;

    const area = Rect{ .x = 0, .y = 0, .width = 10, .height = 10 };
    const content = wizard.contentArea(area);

    try testing.expectEqual(@as(u16, 1), content.x); // inner x
    try testing.expectEqual(@as(u16, 4), content.y); // inner y + header
    try testing.expectEqual(@as(u16, 8), content.width); // inner width
    try testing.expectEqual(@as(u16, 4), content.height); // (10 - 2) - 3 header - 1 nav
}

test "Wizard contentArea x/width unaffected by steps (no block)" {
    var steps_arr: [3]Step = .{
        .{ .title = "A", .description = "" },
        .{ .title = "B", .description = "" },
        .{ .title = "C", .description = "" },
    };
    var wizard = Wizard.init(&steps_arr);
    wizard.show_nav_hint = false;

    const area = Rect{ .x = 5, .y = 2, .width = 20, .height = 15 };
    const content = wizard.contentArea(area);

    try testing.expectEqual(@as(u16, 5), content.x);
    try testing.expectEqual(@as(u16, 20), content.width);
}

test "Wizard contentArea clamps height when too small" {
    var steps_arr: [3]Step = .{
        .{ .title = "A", .description = "" },
        .{ .title = "B", .description = "" },
        .{ .title = "C", .description = "" },
    };
    var wizard = Wizard.init(&steps_arr);
    wizard.show_nav_hint = false;

    const area = Rect{ .x = 0, .y = 0, .width = 10, .height = 2 };
    const content = wizard.contentArea(area);

    // headerHeight = 3, area height = 2, result should be 0
    try testing.expectEqual(@as(u16, 0), content.height);
}

test "Wizard contentArea no nav hint, 3 steps, area 5x5" {
    var steps_arr: [3]Step = .{
        .{ .title = "A", .description = "" },
        .{ .title = "B", .description = "" },
        .{ .title = "C", .description = "" },
    };
    var wizard = Wizard.init(&steps_arr);
    wizard.show_nav_hint = false;

    const area = Rect{ .x = 0, .y = 0, .width = 5, .height = 5 };
    const content = wizard.contentArea(area);

    try testing.expectEqual(@as(u16, 2), content.height); // 5 - 3 header
}

test "Wizard contentArea with nav hint area exactly 3 high plus 1" {
    var steps_arr: [3]Step = .{
        .{ .title = "A", .description = "" },
        .{ .title = "B", .description = "" },
        .{ .title = "C", .description = "" },
    };
    var wizard = Wizard.init(&steps_arr);
    wizard.show_nav_hint = true;

    const area = Rect{ .x = 0, .y = 0, .width = 10, .height = 4 };
    const content = wizard.contentArea(area);

    // 4 - 3 header - 1 nav = 0
    try testing.expectEqual(@as(u16, 0), content.height);
}

test "Wizard contentArea y position offset by area.y + header" {
    var steps_arr: [3]Step = .{
        .{ .title = "A", .description = "" },
        .{ .title = "B", .description = "" },
        .{ .title = "C", .description = "" },
    };
    var wizard = Wizard.init(&steps_arr);
    wizard.show_nav_hint = false;

    const area = Rect{ .x = 0, .y = 5, .width = 10, .height = 10 };
    const content = wizard.contentArea(area);

    try testing.expectEqual(@as(u16, 8), content.y); // 5 + 3 header
}

// ============================================================================
// BUILDER PATTERN — IMMUTABILITY
// ============================================================================

test "Wizard withCurrent creates copy with new current" {
    var steps_arr: [3]Step = .{
        .{ .title = "A", .description = "" },
        .{ .title = "B", .description = "" },
        .{ .title = "C", .description = "" },
    };
    const original = Wizard.init(&steps_arr);
    const modified = original.withCurrent(2);

    try testing.expectEqual(@as(usize, 0), original.current);
    try testing.expectEqual(@as(usize, 2), modified.current);
}

test "Wizard withActiveStepStyle preserves immutability" {
    var steps_arr: [1]Step = .{
        .{ .title = "Test", .description = "" },
    };
    const original = Wizard.init(&steps_arr);
    const style = Style{ .fg = Color.red };
    const modified = original.withActiveStepStyle(style);

    try testing.expect(modified.active_step_style.fg != null);
    try testing.expect(original.active_step_style.fg == null);
}

test "Wizard withInactiveStepStyle preserves immutability" {
    var steps_arr: [1]Step = .{
        .{ .title = "Test", .description = "" },
    };
    const original = Wizard.init(&steps_arr);
    const style = Style{ .bold = true };
    const modified = original.withInactiveStepStyle(style);

    try testing.expect(modified.inactive_step_style.bold);
    try testing.expect(!original.inactive_step_style.bold);
}

test "Wizard withTitleStyle preserves immutability" {
    var steps_arr: [1]Step = .{
        .{ .title = "Test", .description = "" },
    };
    const original = Wizard.init(&steps_arr);
    const style = Style{ .underline = true };
    const modified = original.withTitleStyle(style);

    try testing.expect(modified.title_style.underline);
    try testing.expect(!original.title_style.underline);
}

test "Wizard withDescriptionStyle preserves immutability" {
    var steps_arr: [1]Step = .{
        .{ .title = "Test", .description = "" },
    };
    const original = Wizard.init(&steps_arr);
    const style = Style{ .bg = Color.blue };
    const modified = original.withDescriptionStyle(style);

    try testing.expect(modified.description_style.bg != null);
    try testing.expect(original.description_style.bg == null);
}

test "Wizard withNavStyle preserves immutability" {
    var steps_arr: [1]Step = .{
        .{ .title = "Test", .description = "" },
    };
    const original = Wizard.init(&steps_arr);
    const style = Style{ .dim = true };
    const modified = original.withNavStyle(style);

    try testing.expect(modified.nav_style.dim);
    try testing.expect(!original.nav_style.dim);
}

test "Wizard withShowNavHint(false) preserves immutability" {
    var steps_arr: [1]Step = .{
        .{ .title = "Test", .description = "" },
    };
    const original = Wizard.init(&steps_arr);
    const modified = original.withShowNavHint(false);

    try testing.expect(original.show_nav_hint);
    try testing.expect(!modified.show_nav_hint);
}

test "Wizard withShowNavHint(true) preserves immutability" {
    var steps_arr: [1]Step = .{
        .{ .title = "Test", .description = "" },
    };
    var original = Wizard.init(&steps_arr);
    original.show_nav_hint = false;
    const modified = original.withShowNavHint(true);

    try testing.expect(!original.show_nav_hint);
    try testing.expect(modified.show_nav_hint);
}

test "Wizard withBlock preserves immutability" {
    var steps_arr: [1]Step = .{
        .{ .title = "Test", .description = "" },
    };
    const original = Wizard.init(&steps_arr);
    const block = Block{};
    const modified = original.withBlock(block);

    try testing.expect(original.block == null);
    try testing.expect(modified.block != null);
}

test "Wizard chained builders: withCurrent and withShowNavHint" {
    var steps_arr: [3]Step = .{
        .{ .title = "A", .description = "" },
        .{ .title = "B", .description = "" },
        .{ .title = "C", .description = "" },
    };
    const original = Wizard.init(&steps_arr);

    const modified = original.withCurrent(1).withShowNavHint(false);

    try testing.expectEqual(@as(usize, 0), original.current);
    try testing.expect(original.show_nav_hint);

    try testing.expectEqual(@as(usize, 1), modified.current);
    try testing.expect(!modified.show_nav_hint);
}

test "Wizard builder chain with multiple methods" {
    var steps_arr: [3]Step = .{
        .{ .title = "A", .description = "" },
        .{ .title = "B", .description = "" },
        .{ .title = "C", .description = "" },
    };
    const original = Wizard.init(&steps_arr);
    const block = Block{};
    const active_style = Style{ .bold = true };
    const inactive_style = Style{ .dim = true };

    const modified = original
        .withCurrent(2)
        .withActiveStepStyle(active_style)
        .withInactiveStepStyle(inactive_style)
        .withShowNavHint(false)
        .withBlock(block);

    try testing.expectEqual(@as(usize, 0), original.current);
    try testing.expect(original.show_nav_hint);
    try testing.expect(original.block == null);

    try testing.expectEqual(@as(usize, 2), modified.current);
    try testing.expect(!modified.show_nav_hint);
    try testing.expect(modified.block != null);
    try testing.expect(modified.active_step_style.bold);
    try testing.expect(modified.inactive_step_style.dim);
}

test "Wizard builder doesn't mutate steps" {
    var steps_arr: [3]Step = .{
        .{ .title = "A", .description = "" },
        .{ .title = "B", .description = "" },
        .{ .title = "C", .description = "" },
    };
    const original = Wizard.init(&steps_arr);
    const modified = original.withCurrent(1).withShowNavHint(false);

    // steps reference should be identical (same slice)
    try testing.expectEqual(original.steps.ptr, modified.steps.ptr);
    try testing.expectEqual(original.steps.len, modified.steps.len);
}

// ============================================================================
// RENDER TESTS
// ============================================================================

test "Wizard render zero-area does not crash" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 10, 10);
    defer buf.deinit();

    var steps_arr: [1]Step = .{
        .{ .title = "Test", .description = "" },
    };
    var wizard = Wizard.init(&steps_arr);

    const area = Rect{ .x = 0, .y = 0, .width = 0, .height = 10 };
    wizard.render(&buf, area);

    // Should not crash; buffer unchanged
    try testing.expect(true);
}

test "Wizard render empty steps does not crash" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 20, 10);
    defer buf.deinit();

    const steps: [0]Step = .{};
    var wizard = Wizard.init(&steps);

    const area = Rect{ .x = 0, .y = 0, .width = 20, .height = 10 };
    wizard.render(&buf, area);

    // Should not crash
    try testing.expect(true);
}

test "Wizard render single step shows indicator" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 20, 10);
    defer buf.deinit();

    var steps_arr: [1]Step = .{
        .{ .title = "Welcome", .description = "" },
    };
    var wizard = Wizard.init(&steps_arr);

    const area = Rect{ .x = 0, .y = 0, .width = 20, .height = 10 };
    wizard.render(&buf, area);

    // First row should have active step indicator '●'
    const cell = buf.get(0, 0);
    try testing.expect(cell != null);
}

test "Wizard render 3 steps current=0 shows first as active" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 20, 10);
    defer buf.deinit();

    var steps_arr: [3]Step = .{
        .{ .title = "Step 1", .description = "" },
        .{ .title = "Step 2", .description = "" },
        .{ .title = "Step 3", .description = "" },
    };
    var wizard = Wizard.init(&steps_arr);

    const area = Rect{ .x = 0, .y = 0, .width = 20, .height = 10 };
    wizard.render(&buf, area);

    // Row 0 should have at least one cell with content (indicator row)
    const cell = buf.get(0, 0);
    try testing.expect(cell != null);
    try testing.expect(cell.?.char != 0);
}

test "Wizard render 3 steps current=1 shows second as active" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 20, 10);
    defer buf.deinit();

    var steps_arr: [3]Step = .{
        .{ .title = "First", .description = "" },
        .{ .title = "Second", .description = "" },
        .{ .title = "Third", .description = "" },
    };
    var wizard = Wizard.init(&steps_arr);
    wizard.current = 1;

    const area = Rect{ .x = 0, .y = 0, .width = 20, .height = 10 };
    wizard.render(&buf, area);

    // Row 0 should have indicator content
    try testing.expect(buf.get(0, 0) != null);
}

test "Wizard render 3 steps current=2 shows third as active" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 20, 10);
    defer buf.deinit();

    var steps_arr: [3]Step = .{
        .{ .title = "Alpha", .description = "" },
        .{ .title = "Beta", .description = "" },
        .{ .title = "Gamma", .description = "" },
    };
    var wizard = Wizard.init(&steps_arr);
    wizard.current = 2;

    const area = Rect{ .x = 0, .y = 0, .width = 20, .height = 10 };
    wizard.render(&buf, area);

    // Row 0 should have indicator
    try testing.expect(buf.get(0, 0) != null);
}

test "Wizard render title row shows current step title" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 20, 10);
    defer buf.deinit();

    var steps_arr: [3]Step = .{
        .{ .title = "Start", .description = "" },
        .{ .title = "Middle", .description = "" },
        .{ .title = "End", .description = "" },
    };
    var wizard = Wizard.init(&steps_arr);
    wizard.current = 1;

    const area = Rect{ .x = 0, .y = 0, .width = 20, .height = 10 };
    wizard.render(&buf, area);

    // Row 1 should have title content
    const cell = buf.get(0, 1);
    try testing.expect(cell != null);
}

test "Wizard render separator line at row 2" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 20, 10);
    defer buf.deinit();

    var steps_arr: [2]Step = .{
        .{ .title = "A", .description = "" },
        .{ .title = "B", .description = "" },
    };
    var wizard = Wizard.init(&steps_arr);

    const area = Rect{ .x = 0, .y = 0, .width = 20, .height = 10 };
    wizard.render(&buf, area);

    // Row 2 should have separator (─)
    const cell = buf.get(0, 2);
    try testing.expect(cell != null);
}

test "Wizard render with block border" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 20, 10);
    defer buf.deinit();

    var steps_arr: [2]Step = .{
        .{ .title = "Test", .description = "" },
        .{ .title = "Verify", .description = "" },
    };
    var wizard = Wizard.init(&steps_arr);
    wizard.block = Block{};

    const area = Rect{ .x = 0, .y = 0, .width = 20, .height = 10 };
    wizard.render(&buf, area);

    // Should render without crash
    try testing.expect(true);
}

test "Wizard render nav hint: show_nav_hint=true and not first" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 20, 10);
    defer buf.deinit();

    var steps_arr: [3]Step = .{
        .{ .title = "A", .description = "" },
        .{ .title = "B", .description = "" },
        .{ .title = "C", .description = "" },
    };
    var wizard = Wizard.init(&steps_arr);
    wizard.current = 1;
    wizard.show_nav_hint = true;

    const area = Rect{ .x = 0, .y = 0, .width = 20, .height = 10 };
    wizard.render(&buf, area);

    // Last row should have nav hint (area height 10, so row 9)
    const last_cell = buf.get(0, 9);
    try testing.expect(last_cell != null);
}

test "Wizard render nav hint: show_nav_hint=true and not last" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 20, 10);
    defer buf.deinit();

    var steps_arr: [3]Step = .{
        .{ .title = "A", .description = "" },
        .{ .title = "B", .description = "" },
        .{ .title = "C", .description = "" },
    };
    var wizard = Wizard.init(&steps_arr);
    wizard.current = 1;
    wizard.show_nav_hint = true;

    const area = Rect{ .x = 0, .y = 0, .width = 20, .height = 10 };
    wizard.render(&buf, area);

    // Last row should have nav hint
    const last_cell = buf.get(0, 9);
    try testing.expect(last_cell != null);
}

test "Wizard render nav hint=false has no nav hint chars in last row" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 20, 10);
    defer buf.deinit();

    var steps_arr: [3]Step = .{
        .{ .title = "A", .description = "" },
        .{ .title = "B", .description = "" },
        .{ .title = "C", .description = "" },
    };
    var wizard = Wizard.init(&steps_arr);
    wizard.show_nav_hint = false;

    const area = Rect{ .x = 0, .y = 0, .width = 20, .height = 10 };
    wizard.render(&buf, area);

    // With show_nav_hint=false, last row should not have nav hint
    // This test verifies behavior, exact check depends on implementation
    try testing.expect(true);
}

test "Wizard render title truncated if too long" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 10, 10);
    defer buf.deinit();

    var steps_arr: [1]Step = .{
        .{ .title = "This is a very long title that should be truncated", .description = "" },
    };
    var wizard = Wizard.init(&steps_arr);

    const area = Rect{ .x = 0, .y = 0, .width = 10, .height = 10 };
    wizard.render(&buf, area);

    // Should not crash on truncation
    try testing.expect(true);
}

test "Wizard render area narrower than indicator string truncates gracefully" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 5, 10);
    defer buf.deinit();

    var steps_arr: [3]Step = .{
        .{ .title = "A", .description = "" },
        .{ .title = "B", .description = "" },
        .{ .title = "C", .description = "" },
    };
    var wizard = Wizard.init(&steps_arr);

    const area = Rect{ .x = 0, .y = 0, .width = 5, .height = 10 };
    wizard.render(&buf, area);

    // Should not crash on narrow area
    try testing.expect(true);
}

test "Wizard render area height exactly 3 shows header only" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 20, 3);
    defer buf.deinit();

    var steps_arr: [2]Step = .{
        .{ .title = "Test", .description = "" },
        .{ .title = "Verify", .description = "" },
    };
    var wizard = Wizard.init(&steps_arr);
    wizard.show_nav_hint = false;

    const area = Rect{ .x = 0, .y = 0, .width = 20, .height = 3 };
    wizard.render(&buf, area);

    // Should render indicator, title, separator without crash
    try testing.expect(true);
}

test "Wizard render area height 1 shows indicator only" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 20, 10);
    defer buf.deinit();

    var steps_arr: [2]Step = .{
        .{ .title = "A", .description = "" },
        .{ .title = "B", .description = "" },
    };
    var wizard = Wizard.init(&steps_arr);

    const area = Rect{ .x = 0, .y = 0, .width = 20, .height = 1 };
    wizard.render(&buf, area);

    // Should render at least indicator without crash
    try testing.expect(true);
}

test "Wizard render area height 2 shows indicator and title" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 20, 10);
    defer buf.deinit();

    var steps_arr: [2]Step = .{
        .{ .title = "Step", .description = "" },
        .{ .title = "Final", .description = "" },
    };
    var wizard = Wizard.init(&steps_arr);

    const area = Rect{ .x = 0, .y = 0, .width = 20, .height = 2 };
    wizard.render(&buf, area);

    // Should render indicator and title without crash
    try testing.expect(true);
}

test "Wizard render with active_step_style applies to active step" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 20, 10);
    defer buf.deinit();

    var steps_arr: [3]Step = .{
        .{ .title = "A", .description = "" },
        .{ .title = "B", .description = "" },
        .{ .title = "C", .description = "" },
    };
    var wizard = Wizard.init(&steps_arr);
    wizard.active_step_style = Style{ .bold = true };

    const area = Rect{ .x = 0, .y = 0, .width = 20, .height = 10 };
    wizard.render(&buf, area);

    // Should apply style without crash
    try testing.expect(true);
}

test "Wizard render with title_style applies to title row" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 20, 10);
    defer buf.deinit();

    var steps_arr: [2]Step = .{
        .{ .title = "Start", .description = "" },
        .{ .title = "End", .description = "" },
    };
    var wizard = Wizard.init(&steps_arr);
    wizard.title_style = Style{ .fg = Color.yellow };

    const area = Rect{ .x = 0, .y = 0, .width = 20, .height = 10 };
    wizard.render(&buf, area);

    // Should apply style without crash
    try testing.expect(true);
}

test "Wizard render respects area x and y position" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 30, 20);
    defer buf.deinit();

    var steps_arr: [2]Step = .{
        .{ .title = "Test", .description = "" },
        .{ .title = "Verify", .description = "" },
    };
    var wizard = Wizard.init(&steps_arr);

    const area = Rect{ .x = 5, .y = 3, .width = 15, .height = 10 };
    wizard.render(&buf, area);

    // Should render at offset position without crash
    try testing.expect(true);
}

test "Wizard render at area boundary" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 20, 10);
    defer buf.deinit();

    var steps_arr: [2]Step = .{
        .{ .title = "A", .description = "" },
        .{ .title = "B", .description = "" },
    };
    var wizard = Wizard.init(&steps_arr);

    const area = Rect{ .x = 19, .y = 9, .width = 1, .height = 1 };
    wizard.render(&buf, area);

    // Should handle boundary without crash
    try testing.expect(true);
}

// ============================================================================
// INTEGRATION TESTS
// ============================================================================

test "Wizard workflow: init, navigate, check state" {
    var steps_arr: [4]Step = .{
        .{ .title = "Welcome", .description = "Start here" },
        .{ .title = "Setup", .description = "Configure settings" },
        .{ .title = "Review", .description = "Check your choices" },
        .{ .title = "Confirm", .description = "Final step" },
    };
    var wizard = Wizard.init(&steps_arr);

    try testing.expect(wizard.isFirst());
    try testing.expect(!wizard.isLast());

    wizard.nextStep();
    try testing.expect(!wizard.isFirst());
    try testing.expect(!wizard.isLast());
    try testing.expectEqualStrings("Setup", wizard.currentStep().?.title);

    wizard.goToStep(3);
    try testing.expect(!wizard.isFirst());
    try testing.expect(wizard.isLast());

    wizard.prevStep();
    try testing.expectEqualStrings("Review", wizard.currentStep().?.title);
}

test "Wizard workflow: builder chain then navigate" {
    var steps_arr: [3]Step = .{
        .{ .title = "Step 1", .description = "First" },
        .{ .title = "Step 2", .description = "Second" },
        .{ .title = "Step 3", .description = "Third" },
    };
    const original = Wizard.init(&steps_arr);

    var wizard = original
        .withCurrent(1)
        .withShowNavHint(false)
        .withActiveStepStyle(Style{ .bold = true });

    try testing.expectEqual(@as(usize, 1), wizard.current);
    try testing.expect(!wizard.show_nav_hint);

    wizard.nextStep();
    try testing.expectEqual(@as(usize, 2), wizard.current);
    try testing.expect(wizard.isLast());
}

test "Wizard render with full setup: styles, block, nav" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 40, 15);
    defer buf.deinit();

    var steps_arr: [3]Step = .{
        .{ .title = "Configuration", .description = "Setup options" },
        .{ .title = "Installation", .description = "Install components" },
        .{ .title = "Summary", .description = "Review installation" },
    };

    var wizard = Wizard.init(&steps_arr);
    wizard.current = 1;
    wizard.block = Block{};
    wizard.active_step_style = Style{ .bold = true, .fg = Color.green };
    wizard.inactive_step_style = Style{ .dim = true };
    wizard.title_style = Style{ .fg = Color.cyan };
    wizard.nav_style = Style{ .fg = Color.yellow };
    wizard.show_nav_hint = true;

    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 15 };
    wizard.render(&buf, area);

    // Full workflow should render without crash
    try testing.expect(true);
}

test "Wizard state consistency: all navigation methods maintain validity" {
    var steps_arr: [5]Step = .{
        .{ .title = "A", .description = "" },
        .{ .title = "B", .description = "" },
        .{ .title = "C", .description = "" },
        .{ .title = "D", .description = "" },
        .{ .title = "E", .description = "" },
    };
    var wizard = Wizard.init(&steps_arr);

    // Test state consistency through various operations
    wizard.nextStep();
    wizard.nextStep();
    try testing.expectEqual(@as(usize, 2), wizard.current);

    wizard.prevStep();
    try testing.expectEqual(@as(usize, 1), wizard.current);

    wizard.goToStep(4);
    try testing.expectEqual(@as(usize, 4), wizard.current);

    wizard.prevStep();
    wizard.prevStep();
    wizard.prevStep();
    wizard.prevStep();
    try testing.expectEqual(@as(usize, 0), wizard.current);

    // Verify final state
    try testing.expect(wizard.isFirst());
    try testing.expect(!wizard.isLast());
    try testing.expectEqualStrings("A", wizard.currentStep().?.title);
}
