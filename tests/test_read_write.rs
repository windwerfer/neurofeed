mod common;

use btleplug::api::{Peripheral as _, WriteType};

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
    assert_eq!(
        value,
        common::gatt_uuids::STATIC_READ_VALUE,
        "Static read should return [0x01, 0x02, 0x03, 0x04]"
    );

    peripheral.disconnect().await.unwrap();
}

#[tokio::test]
#[ignore = "requires BLE test peripheral"]
async fn test_read_counter_increments() {
    let peripheral = common::peripheral_finder::find_and_connect().await;
    common::peripheral_finder::reset_peripheral(&peripheral).await;

    let char = common::peripheral_finder::find_characteristic(
        &peripheral,
        common::gatt_uuids::COUNTER_READ,
    );

    let first = peripheral.read(&char).await.unwrap();
    let second = peripheral.read(&char).await.unwrap();

    // Counter is a little-endian u32, second read should be > first
    let first_val = u32::from_le_bytes(first[..4].try_into().unwrap());
    let second_val = u32::from_le_bytes(second[..4].try_into().unwrap());
    assert!(
        second_val > first_val,
        "Counter should increment: first={}, second={}",
        first_val,
        second_val
    );

    peripheral.disconnect().await.unwrap();
}

#[tokio::test]
#[ignore = "requires BLE test peripheral"]
async fn test_write_with_response() {
    let peripheral = common::peripheral_finder::find_and_connect().await;
    common::peripheral_finder::reset_peripheral(&peripheral).await;

    let char = common::peripheral_finder::find_characteristic(
        &peripheral,
        common::gatt_uuids::WRITE_WITH_RESPONSE,
    );

    let data = vec![0xAA, 0xBB, 0xCC];
    // Should succeed without error (write-with-response gets acknowledgement)
    peripheral
        .write(&char, &data, WriteType::WithResponse)
        .await
        .unwrap();

    peripheral.disconnect().await.unwrap();
}

#[tokio::test]
#[ignore = "requires BLE test peripheral"]
async fn test_write_without_response() {
    let peripheral = common::peripheral_finder::find_and_connect().await;
    common::peripheral_finder::reset_peripheral(&peripheral).await;

    let char = common::peripheral_finder::find_characteristic(
        &peripheral,
        common::gatt_uuids::WRITE_WITHOUT_RESPONSE,
    );

    let data = vec![0x11, 0x22, 0x33];
    peripheral
        .write(&char, &data, WriteType::WithoutResponse)
        .await
        .unwrap();

    peripheral.disconnect().await.unwrap();
}

#[tokio::test]
#[ignore = "requires BLE test peripheral"]
async fn test_read_write_roundtrip() {
    let peripheral = common::peripheral_finder::find_and_connect().await;
    common::peripheral_finder::reset_peripheral(&peripheral).await;

    let char = common::peripheral_finder::find_characteristic(
        &peripheral,
        common::gatt_uuids::READ_WRITE,
    );

    let data = vec![0xDE, 0xAD, 0xBE, 0xEF];
    peripheral
        .write(&char, &data, WriteType::WithResponse)
        .await
        .unwrap();

    let read_back = peripheral.read(&char).await.unwrap();
    assert_eq!(read_back, data, "Read-back should match written data");

    peripheral.disconnect().await.unwrap();
}

#[tokio::test]
#[ignore = "requires BLE test peripheral"]
async fn test_long_value_read_write() {
    let peripheral = common::peripheral_finder::find_and_connect().await;
    common::peripheral_finder::reset_peripheral(&peripheral).await;

    let char = common::peripheral_finder::find_characteristic(
        &peripheral,
        common::gatt_uuids::LONG_VALUE,
    );

    // Write a value larger than the default MTU (23 bytes)
    let data: Vec<u8> = (0..200).map(|i| (i % 256) as u8).collect();
    peripheral
        .write(&char, &data, WriteType::WithResponse)
        .await
        .unwrap();

    let read_back = peripheral.read(&char).await.unwrap();
    assert_eq!(
        read_back, data,
        "Long value read-back should match written data"
    );

    peripheral.disconnect().await.unwrap();
}

#[tokio::test]
#[ignore = "requires BLE test peripheral"]
async fn test_characteristic_properties() {
    let peripheral = common::peripheral_finder::find_and_connect().await;
    use btleplug::api::CharPropFlags;

    let static_read = common::peripheral_finder::find_characteristic(
        &peripheral,
        common::gatt_uuids::STATIC_READ,
    );
    assert!(
        static_read.properties.contains(CharPropFlags::READ),
        "Static Read should have READ property"
    );

    let write_char = common::peripheral_finder::find_characteristic(
        &peripheral,
        common::gatt_uuids::WRITE_WITH_RESPONSE,
    );
    assert!(
        write_char.properties.contains(CharPropFlags::WRITE),
        "Write With Response should have WRITE property"
    );

    let write_no_resp = common::peripheral_finder::find_characteristic(
        &peripheral,
        common::gatt_uuids::WRITE_WITHOUT_RESPONSE,
    );
    assert!(
        write_no_resp
            .properties
            .contains(CharPropFlags::WRITE_WITHOUT_RESPONSE),
        "Write Without Response should have WRITE_WITHOUT_RESPONSE property"
    );

    peripheral.disconnect().await.unwrap();
}
