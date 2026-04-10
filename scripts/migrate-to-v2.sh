#!/usr/bin/env bash
# sailor v1.x to v2.0.0 Migration Script
#
# Usage:
#   ./scripts/migrate-to-v2.sh [--dry-run] <path>
#
# Examples:
#   ./scripts/migrate-to-v2.sh --dry-run src/      # Preview changes
#   ./scripts/migrate-to-v2.sh src/main.zig        # Migrate single file
#   ./scripts/migrate-to-v2.sh src/                # Migrate entire directory

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Parse arguments
DRY_RUN=false
TARGET_PATH=""

while [[ $# -gt 0 ]]; do
    case $1 in
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        *)
            TARGET_PATH="$1"
            shift
            ;;
    esac
done

if [[ -z "$TARGET_PATH" ]]; then
    echo -e "${RED}Error: No target path specified${NC}"
    echo "Usage: $0 [--dry-run] <path>"
    exit 1
fi

if [[ ! -e "$TARGET_PATH" ]]; then
    echo -e "${RED}Error: Path does not exist: $TARGET_PATH${NC}"
    exit 1
fi

# Find all .zig files
if [[ -d "$TARGET_PATH" ]]; then
    ZIG_FILES=$(find "$TARGET_PATH" -name "*.zig" -type f)
else
    ZIG_FILES="$TARGET_PATH"
fi

FILE_COUNT=$(echo "$ZIG_FILES" | wc -l | tr -d ' ')

echo -e "${BLUE}=== sailor v1.x → v2.0.0 Migration Script ===${NC}"
echo -e "${BLUE}Target: $TARGET_PATH${NC}"
echo -e "${BLUE}Files: $FILE_COUNT${NC}"
echo -e "${BLUE}Dry-run: $DRY_RUN${NC}"
echo ""

TOTAL_CHANGES=0

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Complex transformation function for Buffer.setChar → set
transform_setchar() {
    local file="$1"
    python3 "$SCRIPT_DIR/migrate_helper.py" setchar "$file"
}

# Complex transformation for Rect.new → Rect{}
transform_rect_new() {
    local file="$1"
    python3 "$SCRIPT_DIR/migrate_helper.py" rect "$file"
}

# Complex transformation for Block.withTitle → Block{}
transform_block_withtitle() {
    local file="$1"
    python3 "$SCRIPT_DIR/migrate_helper.py" block "$file"
}

# Migration patterns (simple sed patterns only)
declare -a PATTERNS=(
    # Style API: Basic color simplification
    # Color{ .basic = .red } → .red
    "s/Color{ \.basic = \.\([a-z_]*\) }/.\1/g"
    "s/Color{ \.basic = BasicColor\.\([a-z_]*\) }/.\1/g"

    # Style API: Indexed color simplification
    # Color{ .indexed = 235 } → .@"235"
    "s/Color{ \.indexed = \([0-9]*\) }/.@\"\1\"/g"

    # Old constraint syntax
    "s/Constraint\.Length(\([0-9]*\))/.{ .length = \1 }/g"
    "s/Constraint\.Percentage(\([0-9]*\))/.{ .percentage = \1 }/g"
    "s/Constraint\.Min(\([0-9]*\))/.{ .min = \1 }/g"
    "s/Constraint\.Max(\([0-9]*\))/.{ .max = \1 }/g"
)

declare -a PATTERN_NAMES=(
    "Color{ .basic = .X } → .X"
    "Color{ .basic = BasicColor.X } → .X"
    "Color{ .indexed = N } → .@\"N\""
    "Constraint.Length(N) → { .length = N }"
    "Constraint.Percentage(N) → { .percentage = N }"
    "Constraint.Min(N) → { .min = N }"
    "Constraint.Max(N) → { .max = N }"
)

# Apply migrations
for file in $ZIG_FILES; do
    echo -e "${YELLOW}Processing: $file${NC}"

    if [[ ! -f "$file" ]]; then
        echo -e "${RED}  Skipping: not a file${NC}"
        continue
    fi

    # Create backup
    cp "$file" "$file.bak"

    file_changes=0

    # Apply complex transformations first (these use perl)

    # 1. Buffer.setChar → Buffer.set (signature change)
    if grep -q "\.setChar(" "$file.bak" 2>/dev/null; then
        before=$(cat "$file.bak")
        transform_setchar "$file.bak"
        after=$(cat "$file.bak")
        if [[ "$before" != "$after" ]]; then
            echo -e "  ${GREEN}✓ Buffer.setChar() → set() (signature): changes applied${NC}"
            ((file_changes++))
        fi
    fi

    # 2. Rect.new → Rect{}
    if grep -q "Rect\.new(" "$file.bak" 2>/dev/null; then
        before=$(cat "$file.bak")
        transform_rect_new "$file.bak"
        after=$(cat "$file.bak")
        if [[ "$before" != "$after" ]]; then
            echo -e "  ${GREEN}✓ Rect.new() → Rect{}: changes applied${NC}"
            ((file_changes++))
        fi
    fi

    # 3. Block.withTitle → Block{}
    if grep -q "Block{}\\.withTitle(" "$file.bak" 2>/dev/null; then
        before=$(cat "$file.bak")
        transform_block_withtitle "$file.bak"
        after=$(cat "$file.bak")
        if [[ "$before" != "$after" ]]; then
            echo -e "  ${GREEN}✓ Block.withTitle() → Block{}: changes applied${NC}"
            ((file_changes++))
        fi
    fi

    # Apply simple sed patterns
    for i in "${!PATTERNS[@]}"; do
        pattern="${PATTERNS[$i]}"
        name="${PATTERN_NAMES[$i]}"

        # Count changes by comparing before/after
        before=$(cat "$file.bak")
        sed -i '' "$pattern" "$file.bak"
        after=$(cat "$file.bak")

        if [[ "$before" != "$after" ]]; then
            change_count=$( (diff -y --suppress-common-lines <(echo "$before") <(echo "$after") 2>/dev/null || true) | wc -l | tr -d ' ')
            if [[ $change_count -gt 0 ]]; then
                echo -e "  ${GREEN}✓ $name: $change_count changes${NC}"
                ((file_changes += change_count))
            fi
        fi
    done

    # Special case: Widget lifecycle (complex pattern)
    # Remove unnecessary .init() for stateless widgets
    # Pattern: var widget = Widget{}.init() → var widget = Widget{}
    if grep -q "Block{}\\.init()" "$file.bak" 2>/dev/null; then
        sed -i '' 's/Block{}\\.init()/Block{}/g' "$file.bak"
        echo -e "  ${GREEN}✓ Remove Block{}.init(): 1 change${NC}"
        ((file_changes++))
    fi

    if grep -q "Paragraph{}\\.init()" "$file.bak" 2>/dev/null; then
        sed -i '' 's/Paragraph{}\\.init()/Paragraph{}/g' "$file.bak"
        echo -e "  ${GREEN}✓ Remove Paragraph{}.init(): 1 change${NC}"
        ((file_changes++))
    fi

    if grep -q "Gauge{}\\.init()" "$file.bak" 2>/dev/null; then
        sed -i '' 's/Gauge{}\\.init()/Gauge{}/g' "$file.bak"
        echo -e "  ${GREEN}✓ Remove Gauge{}.init(): 1 change${NC}"
        ((file_changes++))
    fi

    # If dry-run, restore original and show diff
    if [[ "$DRY_RUN" == true ]]; then
        if [[ $file_changes -gt 0 ]]; then
            echo -e "  ${BLUE}Diff preview:${NC}"
            diff -u "$file" "$file.bak" | head -20 || true
            echo ""
        fi
        mv "$file.bak" "$file"  # Restore original
    else
        # Apply changes
        if [[ $file_changes -gt 0 ]]; then
            mv "$file.bak" "$file"
            echo -e "  ${GREEN}✓ Applied $file_changes changes${NC}"
        else
            rm "$file.bak"
            echo -e "  ${BLUE}No changes needed${NC}"
        fi
    fi

    ((TOTAL_CHANGES += file_changes))
    echo ""
done

# Summary
echo -e "${BLUE}=== Migration Summary ===${NC}"
echo -e "${GREEN}Total files processed: $FILE_COUNT${NC}"
echo -e "${GREEN}Total changes: $TOTAL_CHANGES${NC}"

if [[ "$DRY_RUN" == true ]]; then
    echo -e "${YELLOW}Dry-run mode: No files were modified${NC}"
    echo -e "${YELLOW}Re-run without --dry-run to apply changes${NC}"
else
    echo -e "${GREEN}Migration complete!${NC}"
    echo -e "${BLUE}Next steps:${NC}"
    echo "  1. Run: zig build test"
    echo "  2. Review changes: git diff"
    echo "  3. Commit: git commit -am 'chore: migrate to sailor v2.0.0 APIs'"
fi
