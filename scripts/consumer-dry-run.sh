#!/usr/bin/env bash
# Consumer Project Migration Dry-Run
# Tests migration script on zr, zoltraak, silica in read-only mode

set -euo pipefail

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
CONSUMER_PROJECTS=("zr" "zoltraak" "silica")
CONSUMER_BASE_DIR="../"
DRY_RUN_DIR="zig-cache/consumer-dry-run"
MIGRATION_SCRIPT="scripts/migrate-to-v2.sh"

# Track results
TOTAL_PROJECTS=0
SUCCESSFUL_PROJECTS=0
FAILED_PROJECTS=0
RESULTS_FILE="${DRY_RUN_DIR}/results.txt"

echo -e "${BLUE}=== sailor v2.0.0 Consumer Migration Dry-Run ===${NC}\n"

# Cleanup previous dry-run
if [ -d "$DRY_RUN_DIR" ]; then
    rm -rf "$DRY_RUN_DIR"
fi
mkdir -p "$DRY_RUN_DIR"

# Initialize results file
echo "# Consumer Migration Dry-Run Results" > "$RESULTS_FILE"
echo "" >> "$RESULTS_FILE"

# Function to run dry-run on a consumer project
run_dry_run() {
    local project_name="$1"
    local source_dir="${CONSUMER_BASE_DIR}${project_name}"
    local dry_run_copy="${DRY_RUN_DIR}/${project_name}"

    echo -e "${BLUE}=== Dry-run: ${project_name} ===${NC}"

    # Check if project exists
    if [ ! -d "$source_dir" ]; then
        echo -e "${YELLOW}⚠ ${project_name}: Project directory not found at ${source_dir}${NC}"
        echo -e "  Skipping this project.\n"
        echo "${project_name}: SKIPPED (not found)" >> "$RESULTS_FILE"
        return 0
    fi

    TOTAL_PROJECTS=$((TOTAL_PROJECTS + 1))

    # Copy project to dry-run directory
    echo -e "  📋 Copying ${project_name} to dry-run directory..."
    cp -r "$source_dir" "$dry_run_copy"

    # Find all Zig source files (exclude build artifacts)
    local zig_files
    zig_files=$(find "$dry_run_copy" -name "*.zig" -type f \
        ! -path "*/.zig-cache/*" \
        ! -path "*/zig-out/*" \
        ! -path "*/zig-cache/*" \
        2>/dev/null || echo "")

    if [ -z "$zig_files" ]; then
        echo -e "${YELLOW}⚠ ${project_name}: No .zig files found${NC}\n"
        echo "${project_name}: NO_ZIG_FILES" >> "$RESULTS_FILE"
        return 0
    fi

    local file_count
    file_count=$(echo "$zig_files" | wc -l | tr -d ' ')
    echo -e "  📄 Found ${file_count} Zig files"

    # Run migration script on each file
    local changes=0
    local issues=0
    local error_log="${DRY_RUN_DIR}/${project_name}_errors.log"
    : > "$error_log"

    for file in $zig_files; do
        # Run migration (suppress output unless error)
        if bash "$MIGRATION_SCRIPT" "$file" >> "$error_log" 2>&1; then
            # Check if file was changed
            if ! diff -q "$source_dir/${file#$dry_run_copy/}" "$file" > /dev/null 2>&1; then
                changes=$((changes + 1))
            fi
        else
            echo -e "${RED}  ✗ Migration failed: ${file#$dry_run_copy/}${NC}" | tee -a "$error_log"
            issues=$((issues + 1))
        fi
    done

    # Verify migrated code compiles (if build.zig exists)
    if [ -f "${dry_run_copy}/build.zig" ]; then
        echo -e "  🔨 Testing build..."
        cd "$dry_run_copy"
        if zig build 2>&1 | tee -a "$error_log" | tail -1 | grep -q "Build Summary"; then
            echo -e "${GREEN}  ✓ Build succeeded${NC}"
        else
            echo -e "${YELLOW}  ⚠ Build had warnings/errors (see ${error_log})${NC}"
            issues=$((issues + 1))
        fi
        cd - > /dev/null
    fi

    # Summary for this project
    if [ $issues -eq 0 ]; then
        echo -e "${GREEN}✓ ${project_name}: Migration succeeded${NC}"
        echo -e "  Changes: ${changes} files modified"
        echo "${project_name}: SUCCESS (${changes} files changed)" >> "$RESULTS_FILE"
        SUCCESSFUL_PROJECTS=$((SUCCESSFUL_PROJECTS + 1))
    else
        echo -e "${RED}✗ ${project_name}: Migration had ${issues} issue(s)${NC}"
        echo -e "  See: ${error_log}"
        echo "${project_name}: FAILED (${changes} files changed, ${issues} issues)" >> "$RESULTS_FILE"
        FAILED_PROJECTS=$((FAILED_PROJECTS + 1))
    fi

    echo ""
}

# Run dry-run for each consumer project
for project in "${CONSUMER_PROJECTS[@]}"; do
    run_dry_run "$project"
done

# Overall summary
echo -e "${BLUE}=== Overall Summary ===${NC}"
echo -e "Total projects tested: ${TOTAL_PROJECTS}"
echo -e "${GREEN}Successful: ${SUCCESSFUL_PROJECTS}${NC}"
echo -e "${RED}Failed: ${FAILED_PROJECTS}${NC}"
echo -e ""

# Show results
echo -e "${BLUE}=== Detailed Results ===${NC}"
cat "$RESULTS_FILE"

echo -e "\n${BLUE}Dry-run artifacts: ${DRY_RUN_DIR}${NC}"
echo -e "  - Migrated code copies"
echo -e "  - Error logs for failed projects"
echo -e "  - No changes to original consumer project files"

# Exit code
if [ $FAILED_PROJECTS -gt 0 ]; then
    echo -e "\n${YELLOW}⚠ Some projects had issues. Review error logs before proceeding with v2.0.0 release.${NC}"
    exit 1
else
    echo -e "\n${GREEN}✓ All tested projects migrated successfully! Ready for v2.0.0 release.${NC}"
    exit 0
fi
