//! Helper to discover and connect to the btleplug test peripheral.

use btleplug::api::{Central, Manager as _, Peripheral as _, ScanFilter, WriteType};
use btleplug::platform::{Adapter, Manager, Peripheral};
use std::time::Duration;
use tokio::sync::OnceCell;
use tokio::time;

use super::gatt_uuids;

/// Default scan timeout — how long to wait for the test peripheral to appear.
const DEFAULT_SCAN_TIMEOUT: Duration = Duration::from_secs(10);

/// Process-global adapter. Reusing a single CBCentralManager on macOS is critical —
/// creating a second one in the same process causes CoreBluetooth to stop reporting
/// peripherals that were discovered by the first.
static ADAPTER: OnceCell<Adapter> = OnceCell::const_new();

pub async fn get_adapter() -> &'static Adapter {
    ADAPTER
        .get_or_init(|| async {
            let manager = Manager::new()
                .await
                .expect("failed to create BLE manager");
            let adapters = manager.adapters().await.expect("failed to get adapters");
            // Leak the manager so it (and the underlying CBCentralManager) lives forever.
            // OnceCell keeps the Adapter alive; we need the Manager alive too since
            // the Adapter borrows from it internally on some platforms.
            std::mem::forget(manager);
            adapters.into_iter().next().expect("no BLE adapters found")
        })
        .await
}

/// Discover the test peripheral by name, connect to it, and discover its services.
///
/// Returns the connected `Peripheral` with services already discovered.
///
/// # Panics
/// Panics if the peripheral is not found within the timeout, or if connection/service
/// discovery fails.
pub async fn find_and_connect() -> Peripheral {
    let peripheral_name = std::env::var("BTLEPLUG_TEST_PERIPHERAL")
        .unwrap_or_else(|_| gatt_uuids::TEST_PERIPHERAL_NAME.to_string());

    let adapter = get_adapter().await;

    // Always scan — even if the peripheral is cached from a prior test, scanning
    // ensures CoreBluetooth refreshes its state after a disconnect.
    adapter
        .start_scan(ScanFilter::default())
        .await
        .expect("failed to start scan");

    let peripheral = tokio::time::timeout(DEFAULT_SCAN_TIMEOUT, async {
        loop {
            let peripherals = adapter
                .peripherals()
                .await
                .expect("failed to list peripherals");
            for p in peripherals {
                if let Ok(Some(props)) = p.properties().await {
                    println!("{:?}", props.local_name);
                    if props.local_name.as_deref() == Some(&peripheral_name) {
                        println!("Returning!");
                        return p;
                    }
                }
            }
            time::sleep(Duration::from_millis(200)).await;
        }
    })
    .await
    .unwrap_or_else(|_| {
        panic!(
            "timed out after {:?} waiting for peripheral '{}'",
            DEFAULT_SCAN_TIMEOUT, peripheral_name
        )
    });

    adapter.stop_scan().await.expect("failed to stop scan");
    println!("Connecting");
    tokio::time::timeout(Duration::from_secs(10), peripheral.connect())
        .await
        .expect("timed out connecting to peripheral")
        .expect("failed to connect to test peripheral");
println!("Connected");
    tokio::time::timeout(Duration::from_secs(10), peripheral.discover_services())
        .await
        .expect("timed out discovering services")
        .expect("failed to discover services");
println!("Discovered");
    peripheral
}

/// Send a control command to the test peripheral's Control Point characteristic.
pub async fn send_control_command(peripheral: &Peripheral, opcode: u8) {
    let chars = peripheral.characteristics();
    let control_point = chars
        .iter()
        .find(|c| c.uuid == gatt_uuids::CONTROL_POINT)
        .expect("Control Point characteristic not found");

    peripheral
        .write(control_point, &[opcode], WriteType::WithResponse)
        .await
        .expect("failed to write control command");
}

/// Reset the test peripheral to its default state.
pub async fn reset_peripheral(peripheral: &Peripheral) {
    send_control_command(peripheral, gatt_uuids::CMD_RESET_STATE).await;
    // Brief pause to let the peripheral process the reset
    time::sleep(Duration::from_millis(100)).await;
}

/// Find a characteristic by UUID from the peripheral's discovered characteristics.
pub fn find_characteristic(
    peripheral: &Peripheral,
    uuid: uuid::Uuid,
) -> btleplug::api::Characteristic {
    peripheral
        .characteristics()
        .into_iter()
        .find(|c| c.uuid == uuid)
        .unwrap_or_else(|| panic!("characteristic {} not found", uuid))
}
