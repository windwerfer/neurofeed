mod common;

use btleplug::api::Peripheral as _;

#[tokio::test]
#[ignore = "requires BLE test peripheral"]
async fn test_read_rssi() {
    let peripheral = common::peripheral_finder::find_and_connect().await;
    let rssi = peripheral.read_rssi().await.unwrap();
    // RSSI should be a negative dBm value (typically -30 to -100)
    assert!(rssi < 0, "RSSI should be negative, got {}", rssi);
}
