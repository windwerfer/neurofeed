mod common;

use btleplug::api::Peripheral as _;

#[tokio::test]
#[ignore = "requires BLE test peripheral"]
async fn test_subscribe_notifications() {
    let peripheral = common::peripheral_finder::find_and_connect().await;
    common::peripheral_finder::reset_peripheral(&peripheral).await;
    let char = common::peripheral_finder::find_characteristic(
        &peripheral,
        common::gatt_uuids::NOTIFY_CHAR,
    );
    peripheral.subscribe(&char).await.unwrap();
    peripheral.unsubscribe(&char).await.unwrap();
}
