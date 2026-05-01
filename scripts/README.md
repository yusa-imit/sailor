# sailor Scripts

## check_benchmarks.zig

Benchmark regression detection tool for CI integration.

### Usage

```bash
# Compare current benchmarks against baseline
zig run scripts/check_benchmarks.zig -- <current_results.txt> [baseline_results.txt]

# Example
zig run scripts/check_benchmarks.zig -- benchmark-current.txt benchmark-baseline.txt
```

### Exit Codes

- `0` - No regression detected
- `1` - Regression detected (>10% slower)
- `2` - Error (missing files, parse error, etc.)

### Features

- Parses benchmark output format from `examples/benchmark.zig`
- Compares per-operation time across benchmarks
- Detects new/removed benchmarks
- Configurable regression threshold (default: 10%)
- Color-coded output:
  - ✅ No regression or improvement
  - ⚠️ Minor slowdown (within threshold)
  - ❌ Regression (exceeds threshold)

### CI Integration

The GitHub Actions workflow (`.github/workflows/ci.yml`) uses this tool to:

1. Run benchmarks on current PR code
2. Fetch baseline results from main branch
3. Compare and detect regressions
4. Report results in PR summary
5. Fail CI if regression exceeds threshold

### Regression Threshold

Default threshold: **10%** slower than baseline.

To adjust, modify `REGRESSION_THRESHOLD_PERCENT` in `scripts/check_benchmarks.zig`.

### Tests

```bash
zig test scripts/check_benchmarks.zig
```

Tests cover:
- Benchmark line parsing
- Regression calculation (slower/faster)
- Edge cases
