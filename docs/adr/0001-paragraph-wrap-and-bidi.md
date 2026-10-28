# ADR 0001: Paragraph wrap and bidi

- Status: Proposed
- Date: 2026-10-28
- Plan: `docs/plans/003-bounds-and-test-honesty.md`, item 6 (unblocks items 7 and 8)

## Context

The `//!` header of `src/tui/widgets/paragraph.zig` promises word/char wrapping and RTL support.
`render()` delivers neither:
- it writes one cell per byte, so `é` becomes the two cells U+00C3 U+00A9;
- it never wraps, and `wrap` is only checked against a bound that has already broken the loop;
- it never reads `direction`;
- `calculateLineWidth` counts bytes;
- `scroll` counts `Line`s.

`Bidi.reorder` allocates and reverses every code point, digits and Latin included.
`Bidi.charType` calls anything outside ASCII letters, Greek, Cyrillic, Hebrew and Arabic "ON"
(`é`, CJK), and classifies Arabic-Indic digits as R. `unicode.charWidth` gives the bidi control
characters (U+200E/F, U+202A-E, U+2066-9) width 1. `grapheme.wrapText` allocates and works on one
string, not on spans.

Constraints:
- `render(self, buf: *Buffer, area: Rect) void` must not change, since changing it would be MAJOR.
- `render` cannot allocate (Tiger Style 1.9).
- Every loop is bounded and named `*_max` (1.7), with no recursion (1.8).
- No dependencies, functions of 70 lines or fewer, lines of 100 columns or fewer, and
  `paragraph.zig` kept under 800 lines.

Callers outside `paragraph.zig`:
- `src/`: `tui/widgets/theme_editor.zig:345`, whose ~130-column sample text will now wrap, and
  `tui/widgets/dialog.zig:175`. That one builds `Paragraph{ .text, .style }`, fields that do not
  exist, so `Dialog.render` fails to compile once referenced (checked on Zig 0.16.0). That is a
  separate bug fix, landed before item 7.
- `tests/`: 9 files, 27 tests in `paragraph_test.zig`. All fixtures fit their areas.
- `examples/`: 14 files.

`Pager` (plan 002) soft-wraps and scrolls by logical line.

## Decision

1. **Allocation: one bounded row scratch on the stack, one code path for every row.** All logic
   lives in the new internal `src/tui/widgets/paragraph_wrap.zig`, which `tui.zig` does not
   re-export. `Alignment` and `Wrap` move there, and `paragraph.zig` re-exports them as the same
   types, so `paragraph.Wrap` keeps working.
   ```zig
   pub const row_columns_max: u16 = 512; // widest visual row; every kept glyph is >= 1 column
   pub const replacement_cp: u21 = 0xFFFD;
   pub const Cursor = struct { span: u32, byte: u32 }; // position inside a Line
   pub const Glyph = struct { cp: u21, width: u2, len: u3 }; // width 0: consume, draw nothing
   pub const RowScratch = struct { // 5.5 KiB; comptime assert(@sizeOf(RowScratch) <= 6144)
       cps: [row_columns_max]u21,
       spans: [row_columns_max]u32, // index into line.spans: style travels with each glyph
       levels: [row_columns_max]Bidi.Level,
       visual: [row_columns_max]u16, // visual position -> logical glyph index
   };
   pub const Row = struct {
       len: u16, // glyphs in scratch[0..len], logical order
       width: u16, // columns, <= RowOptions.capacity
       spaces: u16, // U+0020 glyphs inside the row (justify gaps)
       next: Cursor, // start of the next row, break spaces already skipped
       last: bool, // next == end of line
   };
   pub const RowOptions = struct { capacity: u16, wrap: Wrap };
   pub fn decode(bytes: []const u8, index: u32) Glyph;
   pub fn fillRow(line: Line, start: Cursor, options: RowOptions, scratch: *RowScratch) Row;
   pub fn lineDirection(line: Line, direction: Bidi.Direction) Bidi.Direction; // never .auto
   pub fn orderRow(scratch: *RowScratch, row: Row, options: Bidi.ResolveOptions) void;
   pub fn rowCount(lines: []const Line, options: CountOptions) u32; // saturating
   ```
   - `renderLines` keeps one `RowScratch` local. A row holds at most
     `min(area.width - indent, row_columns_max)` columns.
   - **Overflow behavior.** In an area wider than 512 columns, `.word`/`.char` wrap at 512 and
     `.none` cuts at 512. This is the only effect of the bound, and it is the same for LTR and
     RTL. No row is ever drawn unreordered, half-reordered or char-split because of the scratch
     size.
   - Rows per `Line` are bounded by `bytes_in_line + 1`, and each row asserts the cursor moved
     forward. Rows skipped by `scroll` are bounded by `scroll` (u16). Every pass in `bidi.zig` is
     a `for` over the row.
2. **Measuring: code points and display width via `unicode.zig`, never bytes.**
   - `decode` handles errors with an exhaustive `switch`. A byte that does not start a valid,
     complete UTF-8 sequence becomes one U+FFFD (width 1), and decoding resumes at the next byte.
     Spans are decoded separately; a sequence split across two spans is two bad sequences.
   - Width is `UnicodeWidth.charWidth`. Width-0 code points (combining marks, ZWJ, controls
     including `\t` and `\n`, bidi controls) are consumed and never drawn, matching
     `Buffer.setString`. A `Cell` holds one `u21`, so there is no grapheme composition.
   - A width-2 glyph that does not fit the remaining columns starts the next row. The leftover
     column is not written. Under `.none` the row ends there.
   - A width-2 glyph that cannot fit even an empty row (capacity 1) is drawn as U+FFFD.
   - A width-2 glyph writes its cell at `x` only; `x + 1` is not written, matching
     `Buffer.setString`. `Buffer` has no continuation-cell model, and that is out of scope here.
   - Item 8 adds to `unicode.zig` `isZeroWidth`: U+061C, U+200E, U+200F, U+202A-U+202E,
     U+2066-U+2069, U+05BF-U+05C7 (points), U+064B-U+065F and U+0670.
3. **Span styles: each glyph carries its span index** (`scratch.spans`), and the style is read
   from `line.spans[i].style` at write time. That way a style survives wrapping, because rows
   are built from cursors across spans and a word may straddle spans. It also survives
   reordering, because `visual` permutes indices and never the style data. Justify padding takes
   the style of the space it follows, as today. Cells the text does not reach are not written.
4. **`scroll` counts visual rows** after wrapping, with the same capacities as rendering.
   - It means: skip the first `scroll` rows of the wrapped content. Past the end, nothing is
     drawn.
   - Under `.none` a row is a `Line`, so every current fixture keeps its output.
   - Pager's choice (logical lines) is rejected for Paragraph: a `Line` taller than the area
     would never show its tail. That is the common case for wrapped prose in shells and dialogs.
     Pager is a line-numbered viewer, where line identity matters.
   - Cost: the skipped rows are filled but not ordered or written, so a frame costs O(bytes up to
     the last visible row) and allocates nothing.
   - New `pub fn rowCount(self: Paragraph, area: Rect) u32` uses the same `area` as `render`
     (block inner applied) and ignores `scroll` and height. Callers clamp
     `scroll <= rowCount(area) -| inner.height`.
5. **Alignment, justify, indent and direction.** Alignment is physical: `.left` is the left
   edge, under RTL as well.
   - Each row is aligned on its own within `area.width - indent`. Center uses `@divFloor`, the
     same result as today's `@divTrunc` because operands are unsigned.
   - Under `.word`, the run of U+0020 at a break is dropped. It is not counted in `width`, not
     drawn, and not leading on the next row. Spaces inside a row and at the end of an unwrapped
     `Line` are kept, as today.
   - `.char` splits at the column and drops nothing.
   - A word wider than the capacity is char-split under `.word`.
   - Break opportunities are U+0020 only; UAX #14 is not implemented, so CJK runs char-split.
   - Justify spreads every row with at least one space to the row capacity. Extra spaces go
     after each space glyph, left to right in visual order, and the remainder goes to the
     leftmost gaps (the current algorithm).
   - **Justify exception:** the last row of a `Line` that wrapped is left-aligned, like CSS
     `text-align-last: auto`. A `Line` that fits on one row is still justified, as today.
   - `first_line_indent` narrows row 0 of `lines[0]` only, as today, and stays physical (left)
     under RTL. It is clamped to `area.width - 1` so every row has at least one column.
6. **`.word` stays the default.** It is the documented contract, the `Wrap.word` default is
   asserted in `tests/paragraph_test.zig`, and a default of `.none` would keep the doc lie as
   the default behavior. Release note and migration-issue text:
   > Paragraph now wraps. `wrap` always defaulted to `.word`, but `render()` ignored it and cut
   > each Line at the area edge, one cell per byte. From v3.2.0, a Line wider than the area
   > continues on the next rows, and a word wider than the area is split. Set `.wrap = .none` to
   > keep the cut-off. Text is measured in display columns: one cell per code point, two for
   > CJK/emoji, none for combining marks and control characters (tab included), U+FFFD per
   > invalid byte. `scroll` counts visual rows (unchanged with `.none`). `direction = .auto`
   > (the default) is now honored: a Line whose first strong character is Hebrew/Arabic is laid
   > out right-to-left by runs; set `.direction = .ltr` to opt out. Alignment stays physical.
   > New: `Paragraph.rowCount(area)` to clamp `scroll`.
7. **Bidi: ship item 8 with run-based reordering, as a documented UAX #9 subset.**
   - Each `Line` is one paragraph. With `.auto`, its base is the first L or R across all spans
     (P2: digits are not strong), defaulting to `.ltr`.
   - Rules implemented: X9 (bidi controls are width 0 and dropped), W4 (a single `, . : /`
     between two EN, or `+ -` between two EN, becomes EN), W7, N1, N2, I1, I2, L1 (trailing
     spaces of a row get the base level), L2.
   - Levels are 0..2 (no explicit embeddings). `orderRow` may take an identity fast path when the
     base is `.ltr` and the row has no R or AN; it must give the same result.
   - Additions to `bidi.zig` (additive; `reorder` keeps its documented full reversal for
     compatibility, and its doc points to the new pair):
   ```zig
   pub const Level = u2;
   pub const level_max: Level = 2;
   pub const ResolveOptions = struct {
       base: Direction, // .ltr or .rtl; .auto asserted against (resolve with firstStrong)
       strong_before: ?Direction, // last L/R before cps[0] in the same Line (W7); null = sos
   };
   pub fn firstStrong(str: []const u8) ?Direction; // detectDirection = firstStrong orelse .ltr
   pub fn resolveLevels(cps: []const u21, levels: []Level, options: ResolveOptions) void;
   pub fn reorderVisual(levels: []const Level, visual: []u16) void; // L2, in place, no alloc
   ```
   - `resolveLevels` uses `levels` as its only working storage; value 3 marks an unresolved
     neutral before N1. Both functions assert `cps.len == levels.len == visual.len` and that the
     length is at most `maxInt(u16) + 1`.
   - `charType` corrections (no signature change):
     - unlisted code points default to `.L` (UCD default), with an explicit ON table: ASCII
       punctuation/symbols, U+00A1-U+00BF, U+00D7, U+00F7, U+2010-U+205E, U+2190-U+2BFF, CJK
       punctuation U+3001-U+303F, U+1F000-U+1FAFF;
     - `.WS` gains U+2000-U+200A and U+3000;
     - U+0660-U+0669 become `.AN` and U+06F0-U+06F9 `.EN`;
     - R widens to U+0590-U+08FF (Hebrew through Arabic Extended-A) plus the presentation
       forms already listed.
   - Not supported, and stated in the `//!` header: explicit embeddings, overrides and isolates
     (X1-X8; controls are dropped without effect), W5/W6 (`%`, `$`, `#` resolve as neutrals), N0
     bracket pairs, L3, L4 mirroring (`(` is not mirrored), Arabic shaping and joining forms, and
     N1 context across a row edge. Neutrals at a row's start or end resolve against the base,
     which is exact under `.none`.
8. **Order: wrap first (logical order), then resolve and reorder each visual row, then write
   left to right.** This is UAX #9 §3.4: L1/L2 run per line after breaking. `strong_before` is
   carried from row to row of one `Line`, so W7 is exact across wraps.

## Consequences

- **Behavior changes, all `render()` output:**
  - wrapping under the default `.word`;
  - multi-byte text drawn correctly;
  - tabs and control characters no longer emitted as cells;
  - U+FFFD for invalid bytes;
  - RTL `Line`s reordered under the default `.auto`;
  - rows capped at 512 columns;
  - last wrapped row of a justified `Line` left-aligned.

  No current fixture wraps, so all 20 in-file and 27 `tests/paragraph_test.zig` tests stay
  green unchanged. Item 7's PR lists any other test whose expectation moves.
  `detectDirection("123 א")` becomes `.rtl`, and strings that start with `é` or CJK now detect
  as `.ltr`.
- **API:**
  - additions: `Paragraph.rowCount`, `Bidi.Level`, `Bidi.level_max`, `Bidi.ResolveOptions`,
    `Bidi.firstStrong`, `Bidi.resolveLevels`, `Bidi.reorderVisual`;
  - `Alignment`/`Wrap` re-exported as the same types;
  - no public signature changes, so MINOR (v3.2.0) holds.
- **Files:** `paragraph.zig` drops `calculateLineWidth` and `renderJustifiedLine` (about 110
  lines) and gains about 60. New render tests go to `tests/paragraph_wrap_test.zig` (item 7)
  and `tests/paragraph_bidi_test.zig` (item 8), registered in `build.zig`. Kernel tests stay in
  `paragraph_wrap.zig` and `bidi.zig`.
- **Risks:**
  - about 5.5 KiB of stack per `render`/`rowCount` call;
  - a word-wrapped glyph may be decoded twice, and rows above `scroll` are decoded every frame
    (`benchmark_stability_test` watches this);
  - the `charType` table is approximate;
  - Arabic is drawn unshaped;
  - a stale `x + 1` cell after a wide glyph can show (a shared `Buffer` limitation);
  - `Line.width()` in `style.zig` still counts bytes, so callers that size areas with it
    disagree with Paragraph (out of scope; note it in the release);
  - `Pager` scrolls by logical line and Paragraph by visual row, a deliberate difference that
    goes in both doc comments.

## Alternatives considered

| Option | Verdict |
|---|---|
| `Bidi.reorder` over a `FixedBufferAllocator` | Rejected: full-reverse semantics, byte output loses the span/style map |
| `Bidi.reorderInto(out: []u8, ...)` | Rejected: same style loss; reordering before wrap breaks L1/L2 order |
| Caller scratch field `scratch: ?*RowScratch` | Rejected: leaks an internal type into public API, still needs a fallback when null |
| Zero-scratch streaming placement | Rejected for now: three cursor re-scans per run, harder to prove than textbook L2; revisit if the 512 cap bites |
| Separate no-scratch LTR path | Rejected: two construction paths |
| Keep full reversal | Rejected: digits and Latin come out backwards, so "mixed RTL with LTR digits" cannot pass honestly |
| Drop RTL (`withDirection` a no-op) | Rejected: the bounded subset is small and fixes the doc lie |
| Full UAX #9 (embeddings, brackets) | Rejected: needs storage per paragraph, not per row; unbounded per Line |
| `scroll` = logical lines | Rejected: the tail of a tall `Line` is unreachable |
| Default `.none` | Rejected: the default would keep breaking the documented contract |
| Pure CSS justify (last row of every Line left) | Rejected: breaks justify on one-row Lines, which current users rely on |
| `grapheme.wrapText` | Rejected: allocates, works on one string, no spans |

## Test list

Notation: buffers are prefilled with `.` via `buf.fill`, so `.` means "not written".
`(x,y)=c` gives an exact cell; `_` is a written U+0020. Hebrew is written by name: alef U+05D0,
bet U+05D1, gimel U+05D2, dalet U+05D3. Inputs are in logical (memory) order. Area origin is
(0,0), height 1, `.left`, `.word` and `.ltr` unless stated.

### Item 7: wrap (RED first; `tests/paragraph_wrap_test.zig`)

1. `width 0 leaves the buffer untouched`: "ab", w0 h3. All cells `.`; `rowCount` = 0.
2. `width 1 puts one glyph per row`: "ab", w1 h3. (0,0)=a (0,1)=b (0,2)=`.`.
3. `exact fit is one row`: "Hello", w5 h2. (0..4,0)=Hello, (0,1)=`.`; `rowCount` = 1.
4. `fit plus one breaks at the space and drops it`: "Hello world", w6 h2. (0..4,0)=Hello
   (5,0)=`.`; (0..4,1)=world (5,1)=`.`.
5. `word longer than the width falls back to char split`: "abcdefg hi", w3 h4. Rows "abc",
   "def", "g" with (1,2)=`.`, then "hi" with (2,3)=`.`.
6. `a word straddling spans wraps whole and keeps styles`: [raw "ab ", bold "cd", raw "ef"],
   w5 h2. (0,0)=a (1,0)=b (2,0)=`.`; (0,1)=c bold, (1,1)=d bold, (2,1)=e not bold, (3,1)=f.
7. `multi-byte UTF-8 is one column per code point`: "héllo wörld", w5 h2. (1,0)=U+00E9,
   (4,0)=o; (1,1)=U+00F6, (4,1)=d.
8. `a CJK glyph that does not fit moves to the next row`: "你好世", w5 h2. (0,0)=你 (1,0)=`.`
   (2,0)=好 (3,0)=`.` (4,0)=`.`; (0,1)=世.
9. `a width-2 glyph in a 1-column row becomes U+FFFD`: "你a", w1 h2. (0,0)=U+FFFD (0,1)=a.
10. `invalid UTF-8 is one U+FFFD per bad byte`: "a\xFFb\xC3", w8. a, FFFD, b, FFFD at 0..3,
    (4,0)=`.`. Also "x\xE2\x82y": x FFFD FFFD y.
11. `zero-width and control code points take no cell`: "e\u{301}x\ty", w8. e x y at 0..2,
    (3,0)=`.`.
12. `scroll counts visual rows`: "aaa bbb ccc", w3 h2 scroll 1. (0..2,0)=bbb (0..2,1)=ccc.
13. `scroll reaches the tail of a Line taller than the area`: "a b c d", w1 h2 scroll 2.
    (0,0)=c (0,1)=d.
14. `scroll past the last row draws nothing`: same, scroll 9. All `.`.
15. `.none truncates, one row per Line`: ["Hello world", "ab"], w5 h2. (0..4,0)=Hello;
    (0,1)=a (1,1)=b (2,1)=`.`; `rowCount` = 2.
16. `.char splits at the column and keeps spaces`: "ab cd", w3 h2. (2,0)=`_`; (0,1)=c (1,1)=d.
17. `justify spreads wrapped rows, last row left`: "aa bb cc", w6 h2. Row 0 = a a _ _ b b; row
    1: (0,1)=c (1,1)=c (2,1)=`.`.
18. `first_line_indent narrows only row 0 of Line 0`: ["aaa bbb", "cc"], indent 2, w5 h3.
    (0,0)=`.` (2..4,0)=aaa; (0..2,1)=bbb; (0..1,2)=cc.
19. `an indent at or above the width is clamped to leave one column`: "ab", indent 9, w4 h2.
    (3,0)=a (0,1)=b.
20. `center and right align each row`: "ab cdef", w6 h2 `.center`: (2,0)=a (3,0)=b, (1..4,1)=cdef.
    "ab cd", w4 `.right`: (2,0)=a (3,0)=b (2,1)=c (3,1)=d.
21. `trailing spaces of an unwrapped Line still align`: "ab  ", w6 `.right`. (2,0)=a (3,0)=b
    (4,0)=`_` (5,0)=`_`.
22. `rowCount matches rendering`: "Hello world" gives 2 at w5, 2 with `Block` borders `.all` at
    w7 h4, 1 with `.none`, 0 at w0.
23. `seeded model test`: 1000 Lines from {a, b, _, é, 你} at widths 1..12, seed printed. The
    rendered rows equal a test-local allocating greedy reference wrapper, and no cell outside
    the area changes.
24. Parity: all existing Paragraph tests stay green unchanged, including the four justify tests.

### Item 8: RTL (RED first; `tests/paragraph_bidi_test.zig` plus `bidi.zig`/`unicode.zig`)

1. `rtl reverses a Hebrew run`: alef bet gimel, `.rtl`, w6. gimel bet alef at 0..2, (3,0)=`.`.
2. `.auto detects rtl`: same input, `.auto`. Same cells.
3. `.auto skips leading digits (P2)`: "12 " alef bet, `.auto`, w6. bet alef _ 1 2, (5,0)=`.`.
4. `.auto keeps an LTR Line in order`: "ab " alef bet, `.auto`, w6. a b _ bet alef.
5. `mixed RTL with LTR digits`: alef bet " 123 " gimel dalet, `.rtl`, w10.
   dalet gimel _ 1 2 3 _ bet alef, (9,0)=`.`.
6. `Latin and following digits form one LTR run (W7)`: alef bet " abc 12", `.rtl`, w10.
   a b c _ 1 2 _ bet alef.
7. `ltr base reverses an embedded Hebrew run`: "ab " alef bet gimel " cd", `.ltr`, w10.
   a b _ gimel bet alef _ c d.
8. `ltr base: digits after Hebrew join the RTL run`: "a " alef bet " 12", `.ltr`, w8.
   a _ 1 2 _ bet alef, (7,0)=`.`.
9. `a single separator stays inside the number (W4)`: alef bet " 1,000", `.rtl`, w8.
   1 , 0 0 0 _ bet alef.
10. `Arabic-Indic digits are AN`: alef " \u{661}\u{662}", `.rtl`, w4. U+0661 U+0662 _ alef.
11. `forced rtl leaves Latin in order`: "abc", `.rtl`. a b c (whereas `Bidi.reorder` gives
    "cba").
12. `span styles travel with their code points`: [bold alef bet, raw gimel], `.rtl`, w4.
    (0,0)=gimel not bold, (1,0)=bet bold, (2,0)=alef bold.
13. `wrap happens before reorder (L1/L2 per row)`: alef bet " " gimel dalet, `.rtl`, w3 h2.
    (0,0)=bet (1,0)=alef (2,0)=`.`; (0,1)=dalet (1,1)=gimel.
14. `alignment stays physical under rtl`: alef bet, `.rtl`, w5. `.right`: (3,0)=bet (4,0)=alef
    and 0..2 = `.`; `.left`: (0,0)=bet (1,0)=alef.
15. `bidi controls take no cell`: alef U+200F bet, `.rtl`, w4. bet alef, (2,0)=`.`.
16. `a Line over the scratch bound wraps at 512 and is still reordered`: bet ++ 511 x alef ++
    gimel dalet, `.rtl`, w600 h2. (511,0)=bet (0,0)=alef (512,0)=`.`; (0,1)=dalet (1,1)=gimel;
    `rowCount` = 2.
17. `.none over the bound cuts at 512`: same input, `.none`. Row 0 as in 16; (0,1)=`.`;
    `rowCount` = 1.
18. `an LTR Line over the bound wraps at 512 too`: 520 x a, w600 h2. (511,0)=a (512,0)=`.`;
    (0..7,1)=a.
19. `bidi.zig`: `firstStrong("12 " alef)` = `.rtl`, `firstStrong("...")` = null,
    `firstStrong("é")` = `.ltr`; `detectDirection("123 " alef)` = `.rtl`. `charType`: 0x661
    `.AN`, 0x6F1 `.EN`, 0xE9 `.L`, 0x4F60 `.L`, '!' `.ON`, 0x2192 `.ON`, 0x3000 `.WS`.
20. `resolveLevels`: "a " alef bet " 12", base `.ltr`, before null gives [0,0,1,1,1,2,2]. "12"
    with base `.ltr`: before `.rtl` gives [2,2], before `.ltr` gives [0,0], before null gives
    [0,0].
21. `reorderVisual`: levels [0,1,1,2,2,0] give visual [0,3,4,2,1,5]; all-zero levels give the
    identity.
22. `unicode.zig`: `charWidth` is 0 for 0x200F, 0x202B, 0x2067, 0x064B. Existing
    `Bidi.reorder` tests stay green unchanged.
