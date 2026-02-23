# tests/ -- Integration Test Suite

Freshness: 2026-02-22

## Purpose

Integration tests that exercise btleplug against a real or virtual BLE peripheral running the btleplug test GATT profile. All tests are marked `#[ignore]` so they only run when explicitly requested (`cargo test --test '*' -- --ignored`).

## Structure

- `common/` -- shared test helpers (imported via `mod common;`)
  - `gatt_uuids.rs` -- canonical UUID constants for the test GATT profile (base UUID: `XXXXXXXX-b5a3-f393-e0a9-e50e24dcca9e`)
  - `peripheral_finder.rs` -- discover, connect, and control the test peripheral
- `test_discovery.rs` -- scanning and advertisement parsing
- `test_connection.rs` -- connect/disconnect lifecycle
- `test_read_write.rs` -- characteristic read/write operations
- `test_notifications.rs` -- notify/indicate subscriptions
- `test_descriptors.rs` -- descriptor read/write
- `test_device_info.rs` -- MTU, RSSI, connection parameters

## Contracts

- Every test file uses `find_and_connect()` from `peripheral_finder.rs` to get a connected peripheral with services discovered.
- Tests that mutate peripheral state must call `reset_peripheral()` in setup to ensure clean state.
- Control commands are sent via the Control Point characteristic (UUID `00000101-...`) using `send_control_command()`.
- The env var `BTLEPLUG_TEST_PERIPHERAL` overrides the default peripheral name (`btleplug-test`).

## Dependencies

- Requires a running test peripheral (Bumble virtual or Zephyr hardware) -- see `test-peripheral/`.
- UUID constants in `gatt_uuids.rs` must stay in sync with the peripheral implementations in `test-peripheral/zephyr/src/gatt_profile.h` and `test-peripheral/bumble/test_peripheral.py`.

## Invariants

- All test functions are `#[ignore]` and `#[tokio::test]`.
- Tests must not depend on execution order; each test connects independently.
- The scan timeout is 10 seconds (hardcoded in `peripheral_finder.rs`).
