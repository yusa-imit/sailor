#!/usr/bin/env python3
"""
Migration helper for sailor v1.x → v2.0.0
Handles complex transformations with nested parentheses
"""
import re
import sys


def parse_balanced_args(text, start_pos, num_args):
    """Parse arguments from text starting at start_pos, respecting nested parens/braces"""
    args = []
    pos = start_pos
    for i in range(num_args):
        # Skip whitespace and newlines
        while pos < len(text) and text[pos] in " \t\n\r":
            pos += 1
        arg_start = pos
        # Find end of this argument
        depth = 0
        while pos < len(text):
            ch = text[pos]
            if ch in "({[":
                depth += 1
            elif ch in ")}]":
                if depth == 0:
                    # End of all args - closing paren of function call
                    args.append(text[arg_start:pos].strip())
                    return args, pos
                depth -= 1
            elif ch == "," and depth == 0:
                # End of this arg
                args.append(text[arg_start:pos].strip())
                pos += 1  # Skip the comma
                break
            pos += 1
        if i == num_args - 1:
            # Last argument - should end at closing paren
            while pos < len(text) and text[pos] in " \t\n\r":
                pos += 1
    return args, pos


def transform_setchar(match):
    """Transform buffer.setChar(x, y, char, style) to buffer.set(x, y, .{ .char = char, .style = style })"""
    buffer_name = match.group(1)
    full_match = match.group(0)
    # Find the opening paren
    try:
        open_paren_idx = full_match.index("(")
    except ValueError:
        return full_match

    args, _ = parse_balanced_args(full_match, open_paren_idx + 1, 4)

    if len(args) != 4:
        # Fallback: return unchanged if we cannot parse
        return full_match

    return f"{buffer_name}.set({args[0]}, {args[1]}, .{{ .char = {args[2]}, .style = {args[3]} }})"


def transform_rect_new(match):
    """Transform Rect.new(x, y, w, h) to Rect{ .x = x, .y = y, .width = w, .height = h }"""
    full_match = match.group(0)
    # Find the opening paren
    try:
        open_paren_idx = full_match.index("(")
    except ValueError:
        return full_match

    args, _ = parse_balanced_args(full_match, open_paren_idx + 1, 4)

    if len(args) != 4:
        # Fallback: return unchanged if we cannot parse
        return full_match

    return f"Rect{{ .x = {args[0]}, .y = {args[1]}, .width = {args[2]}, .height = {args[3]} }}"


def transform_block_withtitle(match):
    """Transform Block{}.withTitle(title, pos) to Block{ .title = title, .title_position = pos }"""
    full_match = match.group(0)
    # Find the opening paren
    try:
        open_paren_idx = full_match.index("(")
    except ValueError:
        return full_match

    args, _ = parse_balanced_args(full_match, open_paren_idx + 1, 2)

    if len(args) != 2:
        # Fallback: return unchanged if we cannot parse
        return full_match

    return f"Block{{ .title = {args[0]}, .title_position = {args[1]} }}"


def find_matching_paren(text, start_pos):
    """Find the matching closing paren for the opening paren at start_pos"""
    depth = 1  # We start after the opening paren
    pos = start_pos
    while pos < len(text) and depth > 0:
        if text[pos] == '(':
            depth += 1
        elif text[pos] == ')':
            depth -= 1
        pos += 1
    return pos if depth == 0 else -1


def transform_all(content, pattern_prefix, transform_func):
    """Find and transform all matches with proper paren matching"""
    result = []
    pos = 0
    while pos < len(content):
        # Find next occurrence of pattern_prefix
        match = re.search(pattern_prefix, content[pos:])
        if not match:
            # No more matches - append rest of content
            result.append(content[pos:])
            break

        # Append everything before the match
        match_start = pos + match.start()
        result.append(content[pos:match_start])

        # Find the opening paren
        open_paren = content.find('(', match_start)
        if open_paren == -1:
            # No paren found - shouldn't happen but handle it
            result.append(match.group(0))
            pos = pos + match.end()
            continue

        # Find matching closing paren
        close_paren = find_matching_paren(content, open_paren + 1)
        if close_paren == -1:
            # No matching paren - leave unchanged
            result.append(match.group(0))
            pos = pos + match.end()
            continue

        # Extract full match including balanced parens
        full_match_text = content[match_start:close_paren]

        # Create a fake match object for transform_func
        class FakeMatch:
            def __init__(self, text, groups=None):
                self._text = text
                self._groups = groups or []

            def group(self, n=0):
                if n == 0:
                    return self._text
                elif n <= len(self._groups):
                    return self._groups[n - 1]
                return None

        # Extract buffer name for setChar
        groups = []
        if "setChar" in pattern_prefix:
            # Extract buffer name
            buffer_match = re.match(r"(\w+)\.setChar", full_match_text)
            if buffer_match:
                groups = [buffer_match.group(1)]

        fake_match = FakeMatch(full_match_text, groups)
        transformed = transform_func(fake_match)
        result.append(transformed)

        # Move position past this match
        pos = close_paren

    return ''.join(result)


def main():
    if len(sys.argv) < 3:
        print("Usage: migrate_helper.py <transformation> <file>", file=sys.stderr)
        print("Transformations: setchar, rect, block", file=sys.stderr)
        sys.exit(1)

    transformation = sys.argv[1]
    filename = sys.argv[2]

    with open(filename, "r") as f:
        content = f.read()

    if transformation == "setchar":
        pattern = r"\w+\.setChar\s*\("
        content = transform_all(content, pattern, transform_setchar)
    elif transformation == "rect":
        pattern = r"Rect\.new\s*\("
        content = transform_all(content, pattern, transform_rect_new)
    elif transformation == "block":
        pattern = r"Block\{\}\.withTitle\s*\("
        content = transform_all(content, pattern, transform_block_withtitle)
    else:
        print(f"Unknown transformation: {transformation}", file=sys.stderr)
        sys.exit(1)

    with open(filename, "w") as f:
        f.write(content)


if __name__ == "__main__":
    main()
