#!/usr/bin/env bash
# Deprecation Audit Script for sailor v2.0.0 migration
# Scans codebase for functions/types that should have deprecation warnings

set -euo pipefail

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}=== sailor v2.0.0 Deprecation Audit ===${NC}\n"

# Track findings
TOTAL_CHECKED=0
HAS_WARNING=0
MISSING_WARNING=0
ISSUES_FOUND=()

# Function to check if a function has deprecation warning
check_function() {
    local file="$1"
    local func_name="$2"
    local replacement="$3"
    local description="$4"

    TOTAL_CHECKED=$((TOTAL_CHECKED + 1))

    # Check if function exists
    if ! grep -q "pub fn ${func_name}" "$file" 2>/dev/null; then
        echo -e "${BLUE}ℹ ${description}: Not found (may have been removed)${NC}"
        return 0
    fi

    # Extract function and check for deprecation warning
    local func_context
    func_context=$(grep -A 15 "pub fn ${func_name}" "$file" 2>/dev/null || echo "")

    if echo "$func_context" | grep -q "deprecation\\.replace\\|@deprecated"; then
        echo -e "${GREEN}✓ ${description}: Has deprecation warning${NC}"
        HAS_WARNING=$((HAS_WARNING + 1))
        return 0
    else
        echo -e "${YELLOW}⚠ ${description}: MISSING deprecation warning${NC}"
        echo -e "  File: ${file}"
        echo -e "  Function: ${func_name}()"
        echo -e "  Should use: deprecation.replace(\"${func_name}\", \"${replacement}\", \"2.0.0\")"
        echo ""
        MISSING_WARNING=$((MISSING_WARNING + 1))
        ISSUES_FOUND+=("${file}:${func_name} → ${replacement}")
        return 1
    fi
}

# Function to check if a type/struct method has deprecation
check_type_method() {
    local file="$1"
    local type_name="$2"
    local method_name="$3"
    local replacement="$4"
    local description="$5"

    TOTAL_CHECKED=$((TOTAL_CHECKED + 1))

    # Check if type exists
    if ! grep -q "pub const ${type_name}" "$file" 2>/dev/null; then
        echo -e "${BLUE}ℹ ${description}: Type not found${NC}"
        return 0
    fi

    # Check if method exists in file (simpler approach)
    if ! grep -q "pub fn ${method_name}" "$file" 2>/dev/null; then
        echo -e "${BLUE}ℹ ${description}: Method not found (may have been removed)${NC}"
        return 0
    fi

    # Check for deprecation warning in the method's vicinity (look 5 lines around it)
    local method_context
    method_context=$(grep -B 2 -A 5 "pub fn ${method_name}" "$file" 2>/dev/null || echo "")

    if echo "$method_context" | grep -q "deprecation\\.replace\\|@deprecated"; then
        echo -e "${GREEN}✓ ${description}: Has deprecation warning${NC}"
        HAS_WARNING=$((HAS_WARNING + 1))
        return 0
    else
        echo -e "${YELLOW}⚠ ${description}: MISSING deprecation warning${NC}"
        echo -e "  File: ${file}"
        echo -e "  Type: ${type_name}.${method_name}()"
        echo -e "  Should use: deprecation.replace(\"${method_name}\", \"${replacement}\", \"2.0.0\")"
        echo ""
        MISSING_WARNING=$((MISSING_WARNING + 1))
        ISSUES_FOUND+=("${file}:${type_name}.${method_name} → ${replacement}")
        return 1
    fi
}

echo -e "${BLUE}Checking Buffer API (v2.0.0 Breaking Change #1)...${NC}"
check_function "src/tui/buffer.zig" "setChar" "set" "Buffer.setChar()"

echo -e "\n${BLUE}Checking Rect API (v2.0.0 Breaking Change #5)...${NC}"
check_type_method "src/tui/layout.zig" "Rect" "new" "struct literal" "Rect.new()"

echo -e "\n${BLUE}Checking Block API (v2.0.0 Breaking Change #5)...${NC}"
check_type_method "src/tui/widgets/block.zig" "Block" "withTitle" "struct literal" "Block.withTitle()"

echo -e "\n${BLUE}Checking for old Constraint syntax...${NC}"
# Check if old Constraint.Length syntax is still present in examples/docs
if grep -r "Constraint\.Length\\|Constraint\.Percentage" examples/ docs/ 2>/dev/null; then
    echo -e "${YELLOW}⚠ Old Constraint syntax found in examples/docs${NC}"
    echo -e "  Should use: .{ .length = N } instead of Constraint.Length(N)"
    echo ""
    MISSING_WARNING=$((MISSING_WARNING + 1))
    ISSUES_FOUND+=("examples/docs: Constraint syntax → .{ .length = N }")
else
    echo -e "${GREEN}✓ No old Constraint syntax found in examples/docs${NC}"
    HAS_WARNING=$((HAS_WARNING + 1))
fi

echo -e "\n${BLUE}Checking for widget lifecycle consistency...${NC}"
# Check if any widgets still use inconsistent init patterns
WIDGET_FILES=$(find src/tui/widgets -name "*.zig" -type f 2>/dev/null || echo "")

INCONSISTENT_WIDGETS=()
for widget_file in $WIDGET_FILES; do
    widget_name=$(basename "$widget_file" .zig)

    # Check for init() without allocator parameter (inconsistent pattern)
    if grep -q "pub fn init()" "$widget_file" 2>/dev/null; then
        INCONSISTENT_WIDGETS+=("${widget_name}: init() without allocator")
    fi

    # Check for init with data but no allocator (should use struct literal instead)
    if grep -E "pub fn init\\([^)]*\\)" "$widget_file" 2>/dev/null | grep -v "allocator" | grep -q "init"; then
        # Further check if it's not a simple init()
        if ! grep -q "pub fn init() " "$widget_file" 2>/dev/null; then
            INCONSISTENT_WIDGETS+=("${widget_name}: init(data) without allocator (should use struct literal)")
        fi
    fi
done

if [ ${#INCONSISTENT_WIDGETS[@]} -eq 0 ]; then
    echo -e "${GREEN}✓ All widgets follow consistent lifecycle patterns${NC}"
    HAS_WARNING=$((HAS_WARNING + 1))
else
    echo -e "${YELLOW}⚠ Found ${#INCONSISTENT_WIDGETS[@]} widgets with inconsistent lifecycle:${NC}"
    for widget in "${INCONSISTENT_WIDGETS[@]}"; do
        echo -e "  - ${widget}"
    done
    echo ""
    MISSING_WARNING=$((MISSING_WARNING + 1))
    ISSUES_FOUND+=("Widget lifecycle inconsistencies")
fi

# Summary
echo -e "\n${BLUE}=== Audit Summary ===${NC}"
echo -e "Total checks: ${TOTAL_CHECKED}"
echo -e "${GREEN}Has deprecation warnings: ${HAS_WARNING}${NC}"
echo -e "${YELLOW}Missing warnings: ${MISSING_WARNING}${NC}"

if [ $MISSING_WARNING -gt 0 ]; then
    echo -e "\n${YELLOW}Issues to fix:${NC}"
    for issue in "${ISSUES_FOUND[@]}"; do
        echo -e "  - ${issue}"
    done

    echo -e "\n${YELLOW}Recommendations:${NC}"
    echo -e "1. Add deprecation.replace() calls to functions missing warnings"
    echo -e "2. Update examples/docs to use v2.0.0 syntax"
    echo -e "3. Standardize widget lifecycle patterns"
    echo -e "4. Verify deprecation warnings appear during compilation"

    exit 1
else
    echo -e "\n${GREEN}✓ All v2.0.0 deprecations are properly documented!${NC}"
    exit 0
fi
