mod common;

use btleplug::api::Peripheral as _;

#[tokio::test]
#[ignore = "requires BLE test peripheral"]
async fn test_read_static_value() {
    let peripheral = common::peripheral_finder::find_and_connect().await;
    common::peripheral_finder::reset_peripheral(&peripheral).await;
    let char = common::peripheral_finder::find_characteristic(
        &peripheral,
        common::gatt_uuids::STATIC_READ,
    );
    let value = peripheral.read(&char).await.unwrap();
    assert_eq!(value, common::gatt_uuids::STATIC_READ_VALUE);
}
