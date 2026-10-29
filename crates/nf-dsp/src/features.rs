//! Band features, ported from `aggregate_band_feature` in
//! `rust/src/api/features.rs`: ratios of relative band powers.

/// Feature ids, as in the legacy registry.
pub const FEATURE_IDS: [&str; 7] = ["band.atr", "band.tar", "band.btr", "band.alpha", "band.theta", "band.beta", "band.delta"];

/// Value of feature `id` from linear band powers (δ θ α β γ, µV²);
/// `None` for unknown ids, zero totals or non-finite results.
pub fn band_feature(id: &str, linear: &[f64; 5]) -> Option<f64> {
    let total: f64 = linear.iter().sum();
    if !(total > 0.0) {
        return None;
    }
    let [d, t, a, b, _] = linear.map(|v| v / total);
    let v = match id {
        "band.atr" if t > 0.0 => a / t,
        "band.tar" if a > 0.0 => t / a,
        "band.btr" if t > 0.0 => b / t,
        "band.alpha" => a,
        "band.theta" => t,
        "band.beta" => b,
        "band.delta" => d,
        _ => return None,
    };
    v.is_finite().then_some(v)
}
