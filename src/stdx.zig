//! Tiger Style helpers shared across sailor modules.
//!
//! Holds only zero-cost markers; nothing here allocates or owns state.

/// A no-op marker for a condition that is legitimately sometimes true and
/// sometimes false — as opposed to `assert`, which documents *always*.
pub fn maybe(ok: bool) void {
    _ = ok;
}
