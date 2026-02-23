mod common;

use btleplug::api::Peripheral as _;
use std::time::Duration;
use tokio::time;

#[tokio::test]
#[ignore = "requires BLE test peripheral"]
async fn test_connect_and_disconnect() {
    let peripheral = common::peripheral_finder::find_and_connect().await;
    assert!(peripheral.is_connected().await.unwrap());

    peripheral.disconnect().await.unwrap();
    // Brief pause for disconnection to propagate
    time::sleep(Duration::from_millis(500)).await;
    assert!(!peripheral.is_connected().await.unwrap());
}

#[tokio::test]
#[ignore = "requires BLE test peripheral"]
async fn test_reconnect_after_disconnect() {
    let peripheral = common::peripheral_finder::find_and_connect().await;
    assert!(peripheral.is_connected().await.unwrap());

    peripheral.disconnect().await.unwrap();
    time::sleep(Duration::from_millis(500)).await;
    assert!(!peripheral.is_connected().await.unwrap());

    // Reconnect
    peripheral.connect().await.unwrap();
    assert!(peripheral.is_connected().await.unwrap());

    // Services should be rediscoverable
    peripheral.discover_services().await.unwrap();
    assert!(!peripheral.services().is_empty());

    peripheral.disconnect().await.unwrap();
}

#[tokio::test]
#[ignore = "requires BLE test peripheral"]
async fn test_peripheral_triggered_disconnect() {
    let peripheral = common::peripheral_finder::find_and_connect().await;
    assert!(peripheral.is_connected().await.unwrap());

    // Tell the peripheral to disconnect us after 500ms
    common::peripheral_finder::send_control_command(
        &peripheral,
        common::gatt_uuids::CMD_TRIGGER_DISCONNECT,
    )
    .await;

    // Wait for the disconnect to happen
    time::sleep(Duration::from_secs(2)).await;
    assert!(
        !peripheral.is_connected().await.unwrap(),
        "Peripheral should have disconnected us"
    );
}
