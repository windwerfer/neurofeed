mod common;

use btleplug::api::Peripheral as _;

#[tokio::test]
#[ignore = "requires BLE test peripheral"]
async fn test_connect_and_disconnect() {
    let peripheral = common::peripheral_finder::find_and_connect().await;
    assert!(peripheral.is_connected().await.unwrap());
    peripheral.disconnect().await.unwrap();
    assert!(!peripheral.is_connected().await.unwrap());
}
