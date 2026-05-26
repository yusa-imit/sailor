//! Tests for custom border patterns in sailor's symbols module
//!
//! Covers the BoxSet variants added in v2.11.0:
//! - dotted: Uniform dot border
//! - wavy:   Tilde/broken-bar border
//! - outer_3d: Block-shading depth illusion

const std = @import("std");
const sailor = @import("sailor");
const testing = std.testing;

const symbols = sailor.tui.symbols;
const BoxSet = symbols.BoxSet;

// ============================================================================
// BoxSet.dotted
// ============================================================================

test "BoxSet.dotted - horizontal and vertical are dot characters" {
    try testing.expectEqualStrings("·", BoxSet.dotted.horizontal);
    try testing.expectEqualStrings("·", BoxSet.dotted.vertical);
}

test "BoxSet.dotted - corners are dot characters" {
    try testing.expectEqualStrings("·", BoxSet.dotted.top_left);
    try testing.expectEqualStrings("·", BoxSet.dotted.top_right);
    try testing.expectEqualStrings("·", BoxSet.dotted.bottom_left);
    try testing.expectEqualStrings("·", BoxSet.dotted.bottom_right);
}

test "BoxSet.dotted - junction characters are dot characters" {
    try testing.expectEqualStrings("·", BoxSet.dotted.vertical_left);
    try testing.expectEqualStrings("·", BoxSet.dotted.vertical_right);
    try testing.expectEqualStrings("·", BoxSet.dotted.horizontal_down);
    try testing.expectEqualStrings("·", BoxSet.dotted.horizontal_up);
    try testing.expectEqualStrings("·", BoxSet.dotted.cross);
}

test "BoxSet.dotted - drawBox produces expected 5x3 output" {
    var buf: [256]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);
    try BoxSet.dotted.drawBox(fbs.writer(), 5, 3);
    const output = fbs.getWritten();

    // All visible characters in the box should be dots
    try testing.expect(output.len > 0);
    // Spot-check: no box-drawing unicode characters like ┌, ─, │
    try testing.expect(!std.mem.containsAtLeast(u8, output, 1, "┌"));
    try testing.expect(!std.mem.containsAtLeast(u8, output, 1, "─"));
}

test "BoxSet.dotted - drawBox too small returns error" {
    var buf: [64]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);
    try testing.expectError(error.BoxTooSmall, BoxSet.dotted.drawBox(fbs.writer(), 1, 1));
}

test "BoxSet.dotted - drawHorizontal fills with dots" {
    var buf: [64]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);
    try BoxSet.dotted.drawHorizontal(fbs.writer(), 3);
    try testing.expectEqualStrings("···", fbs.getWritten());
}

// ============================================================================
// BoxSet.wavy
// ============================================================================

test "BoxSet.wavy - horizontal is tilde, vertical is broken-bar" {
    try testing.expectEqualStrings("~", BoxSet.wavy.horizontal);
    try testing.expectEqualStrings("¦", BoxSet.wavy.vertical);
}

test "BoxSet.wavy - corners use tilde" {
    try testing.expectEqualStrings("~", BoxSet.wavy.top_left);
    try testing.expectEqualStrings("~", BoxSet.wavy.top_right);
    try testing.expectEqualStrings("~", BoxSet.wavy.bottom_left);
    try testing.expectEqualStrings("~", BoxSet.wavy.bottom_right);
}

test "BoxSet.wavy - vertical junctions use broken-bar" {
    try testing.expectEqualStrings("¦", BoxSet.wavy.vertical_left);
    try testing.expectEqualStrings("¦", BoxSet.wavy.vertical_right);
}

test "BoxSet.wavy - horizontal junctions use tilde, cross uses plus" {
    try testing.expectEqualStrings("~", BoxSet.wavy.horizontal_down);
    try testing.expectEqualStrings("~", BoxSet.wavy.horizontal_up);
    try testing.expectEqualStrings("+", BoxSet.wavy.cross);
}

test "BoxSet.wavy - drawBox produces expected 5x3 output" {
    var buf: [256]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);
    try BoxSet.wavy.drawBox(fbs.writer(), 5, 3);
    const expected =
        \\~~~~~
        \\¦   ¦
        \\~~~~~
    ;
    try testing.expectEqualStrings(expected, fbs.getWritten());
}

test "BoxSet.wavy - drawHorizontal produces tildes" {
    var buf: [64]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);
    try BoxSet.wavy.drawHorizontal(fbs.writer(), 4);
    try testing.expectEqualStrings("~~~~", fbs.getWritten());
}

// ============================================================================
// BoxSet.outer_3d
// ============================================================================

test "BoxSet.outer_3d - top uses light shade, bottom uses dark shade" {
    try testing.expectEqualStrings("░", BoxSet.outer_3d.top_left);
    try testing.expectEqualStrings("░", BoxSet.outer_3d.top_right);
    try testing.expectEqualStrings("▓", BoxSet.outer_3d.bottom_left);
    try testing.expectEqualStrings("▓", BoxSet.outer_3d.bottom_right);
}

test "BoxSet.outer_3d - horizontal and vertical use light shade" {
    try testing.expectEqualStrings("░", BoxSet.outer_3d.horizontal);
    try testing.expectEqualStrings("░", BoxSet.outer_3d.vertical);
}

test "BoxSet.outer_3d - vertical junctions: left=light, right=dark" {
    try testing.expectEqualStrings("░", BoxSet.outer_3d.vertical_left);
    try testing.expectEqualStrings("▓", BoxSet.outer_3d.vertical_right);
}

test "BoxSet.outer_3d - horizontal junctions: down=light, up=dark; cross=medium" {
    try testing.expectEqualStrings("░", BoxSet.outer_3d.horizontal_down);
    try testing.expectEqualStrings("▓", BoxSet.outer_3d.horizontal_up);
    try testing.expectEqualStrings("▒", BoxSet.outer_3d.cross);
}

test "BoxSet.outer_3d - drawBox renders block shading characters" {
    var buf: [256]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);
    try BoxSet.outer_3d.drawBox(fbs.writer(), 5, 3);
    const output = fbs.getWritten();
    try testing.expect(output.len > 0);
    // Must contain block shade characters
    try testing.expect(std.mem.containsAtLeast(u8, output, 1, "░"));
    try testing.expect(std.mem.containsAtLeast(u8, output, 1, "▓"));
}

test "BoxSet.outer_3d - drawHorizontal produces light shade" {
    var buf: [64]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);
    try BoxSet.outer_3d.drawHorizontal(fbs.writer(), 3);
    try testing.expectEqualStrings("░░░", fbs.getWritten());
}

// ============================================================================
// Cross-variant distinctness
// ============================================================================

test "Custom borders - dotted and single produce different box output" {
    var buf_dotted: [256]u8 = undefined;
    var buf_single: [256]u8 = undefined;
    var fbs_d = std.io.fixedBufferStream(&buf_dotted);
    var fbs_s = std.io.fixedBufferStream(&buf_single);

    try BoxSet.dotted.drawBox(fbs_d.writer(), 5, 3);
    try BoxSet.single.drawBox(fbs_s.writer(), 5, 3);

    try testing.expect(!std.mem.eql(u8, fbs_d.getWritten(), fbs_s.getWritten()));
}

test "Custom borders - wavy and single produce different box output" {
    var buf_wavy: [256]u8 = undefined;
    var buf_single: [256]u8 = undefined;
    var fbs_w = std.io.fixedBufferStream(&buf_wavy);
    var fbs_s = std.io.fixedBufferStream(&buf_single);

    try BoxSet.wavy.drawBox(fbs_w.writer(), 5, 3);
    try BoxSet.single.drawBox(fbs_s.writer(), 5, 3);

    try testing.expect(!std.mem.eql(u8, fbs_w.getWritten(), fbs_s.getWritten()));
}

test "Custom borders - outer_3d and dotted produce different box output" {
    var buf_3d: [256]u8 = undefined;
    var buf_dotted: [256]u8 = undefined;
    var fbs_3d = std.io.fixedBufferStream(&buf_3d);
    var fbs_d = std.io.fixedBufferStream(&buf_dotted);

    try BoxSet.outer_3d.drawBox(fbs_3d.writer(), 5, 3);
    try BoxSet.dotted.drawBox(fbs_d.writer(), 5, 3);

    try testing.expect(!std.mem.eql(u8, fbs_3d.getWritten(), fbs_d.getWritten()));
}
