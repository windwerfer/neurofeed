mod common;

use btleplug::api::Peripheral as _;

#[tokio::test]
#[ignore = "requires BLE test peripheral"]
async fn test_discover_peripheral_by_name() {
    let peripheral = common::peripheral_finder::find_and_connect().await;
    let props = peripheral.properties().await.unwrap().unwrap();
    let name = props.local_name.unwrap_or_default();
    let expected = std::env::var("BTLEPLUG_TEST_PERIPHERAL")
        .unwrap_or_else(|_| common::gatt_uuids::TEST_PERIPHERAL_NAME.to_string());
    assert_eq!(name, expected);
}
