//! Civil local time → Unix ms (proleptic Gregorian, no tz database).

/// `(year, month, day, hour, minute, second)`.
pub type Civil = (i64, i64, i64, i64, i64, i64);

/// Days since 1970-01-01 (Howard Hinnant's algorithm).
fn days_from_civil(y: i64, m: i64, d: i64) -> i64 {
    let y = if m <= 2 { y - 1 } else { y };
    let era = y.div_euclid(400);
    let yoe = y - era * 400;
    let mp = (m + 9) % 12;
    let doy = (153 * mp + 2) / 5 + d - 1;
    let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy;
    era * 146_097 + doe - 719_468
}

/// `(y, mo, d, h, mi, s)` local + `ms` → Unix ms, given the local UTC offset.
pub fn unix_ms(c: Civil, ms: f64, utc_offset_minutes: i32) -> f64 {
    let (y, mo, d, h, mi, s) = c;
    let secs = days_from_civil(y, mo, d) * 86_400 + h * 3600 + mi * 60 + s - i64::from(utc_offset_minutes) * 60;
    secs as f64 * 1000.0 + ms
}

/// `YYYY-MM-DD[ T]HH:MM:SS[.fff]` → (civil, ms).
pub fn parse_stamp(raw: &str) -> Option<(Civil, f64)> {
    let s = raw.trim();
    let (date, time) = s.split_once([' ', 'T'])?;
    let mut d = date.split('-').map(|p| p.parse::<i64>().ok());
    let (y, mo, da) = (d.next()??, d.next()??, d.next()??);
    let (hms, frac) = time.split_once('.').unwrap_or((time, ""));
    let mut t = hms.split(':').map(|p| p.parse::<i64>().ok());
    let (h, mi, se) = (t.next()??, t.next()??, t.next()??);
    let ms = if frac.is_empty() { 0.0 } else { format!("0.{frac}").parse::<f64>().ok()? * 1000.0 };
    Some(((y, mo, da, h, mi, se), ms))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn known_answers() {
        assert_eq!(unix_ms((1970, 1, 1, 0, 0, 0), 0.0, 0), 0.0);
        assert_eq!(unix_ms((2024, 3, 1, 12, 0, 0), 250.0, 60), 1_709_290_800_250.0);
        let (c, ms) = parse_stamp("2024-03-01 12:00:00.25").unwrap_or(((0, 0, 0, 0, 0, 0), 0.0));
        assert_eq!((c, ms), ((2024, 3, 1, 12, 0, 0), 250.0));
        assert!(parse_stamp("garbage").is_none());
    }
}
