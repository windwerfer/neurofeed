//! Capture writer (PR 4) and max-rate soak (PR 2).
//!
//! PR 2 only lands the harness against **current** assemble. Do not "fix"
//! O(n) RAM here.

#[cfg(test)]
mod soak;
