//! BracketViewer Widget — Tournament bracket visualization
//!
//! The BracketViewer widget displays tournament/competition matches organized in rounds,
//! with team names, scores, winner highlighting, and focused match support.
//!
//! ## Features
//! - Multi-round tournament bracket layout
//! - Team name and score display
//! - Winner highlighting with customizable styles
//! - Focused match highlighting for navigation
//! - Configurable score visibility
//! - Block border support
//! - Builder API for fluent configuration
//!
//! ## Usage
//! ```zig
//! var matches = [_]Match{.{ .team_a = "Alpha", .team_b = "Beta", .winner = .a }};
//! var rounds = [_]Round{.{ .matches = &matches }};
//! var bv = BracketViewer.init()
//!     .withRounds(&rounds)
//!     .withFocusedMatch(0)
//!     .withBlock(Block{});
//! bv.render(&buf, area);
//! ```

const std = @import("std");
const buffer_mod = @import("../buffer.zig");
const Buffer = buffer_mod.Buffer;
const layout_mod = @import("../layout.zig");
const Rect = layout_mod.Rect;
const style_mod = @import("../style.zig");
const Style = style_mod.Style;
const block_mod = @import("block.zig");
const Block = block_mod.Block;

/// Winner indicator for a match
pub const Winner = enum {
    none,
    a,
    b,
};

/// A single match between two teams
pub const Match = struct {
    team_a: []const u8 = "",
    team_b: []const u8 = "",
    score_a: i32 = 0,
    score_b: i32 = 0,
    winner: Winner = .none,
};

/// A single round containing matches
pub const Round = struct {
    matches: []const Match = &.{},
};

/// BracketViewer widget for displaying tournament brackets
pub const BracketViewer = struct {
    /// Maximum number of rounds to display
    pub const MAX_ROUNDS: usize = 8;

    /// Maximum number of matches per round
    pub const MAX_MATCHES_PER_ROUND: usize = 16;

    /// Array of rounds to render
    rounds: []const Round = &.{},

    /// Index of the focused match
    focused_match: usize = 0,

    /// Index of the focused round
    focused_round: usize = 0,

    /// Base style for all content
    style: Style = .{},

    /// Style for winning team names
    win_style: Style = .{},

    /// Style for focused match
    focused_style: Style = .{},

    /// Whether to display scores
    show_scores: bool = true,

    /// Optional border block
    block: ?Block = null,

    /// Initialize a new BracketViewer with defaults
    pub fn init() BracketViewer {
        return .{};
    }

    /// Get the total number of rounds
    pub fn totalRounds(self: BracketViewer) usize {
        return self.rounds.len;
    }

    /// Count all matches across all rounds
    pub fn matchCount(self: BracketViewer) usize {
        var total: usize = 0;
        for (self.rounds) |round| {
            total += round.matches.len;
        }
        return total;
    }

    /// Create a copy with different rounds
    pub fn withRounds(self: BracketViewer, rounds: []const Round) BracketViewer {
        var result = self;
        result.rounds = rounds;
        return result;
    }

    /// Create a copy with different focused match
    pub fn withFocusedMatch(self: BracketViewer, idx: usize) BracketViewer {
        var result = self;
        result.focused_match = idx;
        return result;
    }

    /// Create a copy with different focused round
    pub fn withFocusedRound(self: BracketViewer, idx: usize) BracketViewer {
        var result = self;
        result.focused_round = idx;
        return result;
    }

    /// Create a copy with different base style
    pub fn withStyle(self: BracketViewer, s: Style) BracketViewer {
        var result = self;
        result.style = s;
        return result;
    }

    /// Create a copy with different win style
    pub fn withWinStyle(self: BracketViewer, s: Style) BracketViewer {
        var result = self;
        result.win_style = s;
        return result;
    }

    /// Create a copy with different focused style
    pub fn withFocusedStyle(self: BracketViewer, s: Style) BracketViewer {
        var result = self;
        result.focused_style = s;
        return result;
    }

    /// Create a copy with different score visibility
    pub fn withShowScores(self: BracketViewer, show: bool) BracketViewer {
        var result = self;
        result.show_scores = show;
        return result;
    }

    /// Create a copy with a block border
    pub fn withBlock(self: BracketViewer, b: Block) BracketViewer {
        var result = self;
        result.block = b;
        return result;
    }

    /// Render the bracket to the buffer
    pub fn render(self: BracketViewer, buf: *Buffer, area: Rect) void {
        // Early exit for zero-area
        if (area.width == 0 or area.height == 0) {
            return;
        }

        // Render block border if present
        if (self.block) |b| {
            b.render(buf, area);
        }

        // Use inner area if block exists, otherwise use full area
        const inner = if (self.block != null) area else area;

        // Early exit if inner area is zero
        if (inner.width == 0 or inner.height == 0) {
            return;
        }

        // Early exit if no rounds
        if (self.rounds.len == 0) {
            return;
        }

        // Clamp number of rounds
        const num_rounds = @min(self.rounds.len, MAX_ROUNDS);

        // Calculate column width
        const total_sep_width: u16 = if (num_rounds > 1) @as(u16, @intCast(num_rounds - 1)) else 0;
        const available_width = if (inner.width > total_sep_width) inner.width - total_sep_width else 0;
        const col_width = if (num_rounds > 0) available_width / @as(u16, @intCast(num_rounds)) else 0;

        // Early exit if columns are too narrow
        if (col_width == 0) {
            return;
        }

        // Render each round column
        var round_idx: usize = 0;
        while (round_idx < num_rounds) : (round_idx += 1) {
            const col_x = inner.x + @as(u16, @intCast(round_idx)) * (col_width + 1);

            // Draw separator between rounds (not for first round)
            if (round_idx > 0) {
                const sep_x = col_x -% 1;
                var sep_y = inner.y;
                while (sep_y < inner.y + inner.height) : (sep_y += 1) {
                    buf.set(sep_x, sep_y, .{ .char = '│', .style = self.style });
                }
            }

            self.renderRound(buf, inner, col_x, col_width, round_idx);
        }
    }

    /// Render a single round column
    fn renderRound(self: BracketViewer, buf: *Buffer, inner: Rect, col_x: u16, col_width: u16, round_idx: usize) void {
        const round = self.rounds[round_idx];

        // Clamp number of matches in this round
        const num_matches = @min(round.matches.len, MAX_MATCHES_PER_ROUND);

        // Early exit if no matches in round
        if (num_matches == 0) {
            return;
        }

        // Calculate vertical slot height for each match
        const slot_height = if (inner.height > 0) inner.height / @as(u16, @intCast(num_matches)) else 0;

        // Render each match in the round
        var match_idx: usize = 0;
        while (match_idx < num_matches) : (match_idx += 1) {
            const match_data = round.matches[match_idx];

            // Calculate center y position for this match
            const center_y = inner.y + @as(u16, @intCast(match_idx)) * slot_height + slot_height / 2;

            // Determine if this match is focused
            const is_focused = (round_idx == self.focused_round and match_idx == self.focused_match);

            // Render team_a (above divider)
            if (center_y > inner.y) {
                const team_a_y = center_y - 1;
                const team_a_style = self.selectStyle(match_data.winner, .a, is_focused);
                self.renderTeamName(buf, col_x, team_a_y, col_width, match_data.team_a, team_a_style);
            }

            // Render divider with optional scores
            self.renderDivider(buf, col_x, center_y, col_width, match_data);

            // Render team_b (below divider)
            if (center_y < inner.y + inner.height - 1) {
                const team_b_y = center_y + 1;
                const team_b_style = self.selectStyle(match_data.winner, .b, is_focused);
                self.renderTeamName(buf, col_x, team_b_y, col_width, match_data.team_b, team_b_style);
            }
        }
    }

    /// Select the appropriate style based on focus and winner
    fn selectStyle(self: BracketViewer, winner: Winner, team: Winner, is_focused: bool) Style {
        if (is_focused) {
            return self.focused_style;
        }
        if (winner == team) {
            return self.win_style;
        }
        return self.style;
    }

    /// Render a team name with truncation
    fn renderTeamName(_: BracketViewer, buf: *Buffer, x: u16, y: u16, width: u16, name: []const u8, style: Style) void {
        if (width == 0) {
            return;
        }

        const display_len = @min(@as(u16, @intCast(name.len)), width);
        const display_name = name[0..display_len];

        buf.setString(x, y, display_name, style);
    }

    /// Render the divider row with optional scores
    fn renderDivider(self: BracketViewer, buf: *Buffer, x: u16, y: u16, width: u16, match_data: Match) void {
        if (width == 0) {
            return;
        }

        // Build divider string
        var divider_buf: [128]u8 = undefined;
        var divider_len: usize = 0;

        // Fill with dashes (use UTF-8 encoding of '─' which is 3 bytes: E2 94 80)
        var dash_count = width;
        if (self.show_scores) {
            // Reserve space for score suffix like " [5:3]"
            dash_count = if (width > 8) width - 8 else 1;
        }

        // UTF-8 encoding of '─' (U+2500 BOX DRAWINGS LIGHT HORIZONTAL)
        const dash_utf8 = "\u{2500}";
        for (0..dash_count) |_| {
            if (divider_len + dash_utf8.len <= divider_buf.len) {
                @memcpy(divider_buf[divider_len .. divider_len + dash_utf8.len], dash_utf8);
                divider_len += dash_utf8.len;
            }
        }

        // Append scores if enabled
        if (self.show_scores) {
            const score_str = std.fmt.bufPrint(
                divider_buf[divider_len..],
                " [{d}:{d}]",
                .{ match_data.score_a, match_data.score_b },
            ) catch divider_buf[divider_len..];

            divider_len += @min(score_str.len, divider_buf.len - divider_len);
        }

        // Use only the computed length, bounded by array size
        const display_len = @min(divider_len, divider_buf.len);
        buf.setString(x, y, divider_buf[0..display_len], self.style);
    }
};
