mod common;

use btleplug::api::Peripheral as _;

/// Helper: find a descriptor by UUID on a specific characteristic
fn find_descriptor(
    peripheral: &btleplug::platform::Peripheral,
    char_uuid: uuid::Uuid,
    descriptor_uuid: uuid::Uuid,
) -> btleplug::api::Descriptor {
    use btleplug::api::Peripheral as _;
    let services = peripheral.services();
    for service in &services {
        for char in &service.characteristics {
            if char.uuid == char_uuid {
                for desc in &char.descriptors {
                    if desc.uuid == descriptor_uuid {
                        return desc.clone();
                    }
                }
            }
        }
    }
    panic!(
        "descriptor {} not found on characteristic {}",
        descriptor_uuid, char_uuid
    );
}

#[tokio::test]
#[ignore = "requires BLE test peripheral"]
async fn test_read_only_descriptor() {
    let peripheral = common::peripheral_finder::find_and_connect().await;
    common::peripheral_finder::reset_peripheral(&peripheral).await;

    let descriptor = find_descriptor(
        &peripheral,
        common::gatt_uuids::DESCRIPTOR_TEST_CHAR,
        common::gatt_uuids::READ_ONLY_DESCRIPTOR,
    );

    let value = peripheral.read_descriptor(&descriptor).await.unwrap();
    assert_eq!(
        value,
        vec![0xDE, 0xAD, 0xBE, 0xEF],
        "Read-only descriptor should return fixed value"
    );

    peripheral.disconnect().await.unwrap();
}

#[tokio::test]
#[ignore = "requires BLE test peripheral"]
async fn test_read_write_descriptor_roundtrip() {
    let peripheral = common::peripheral_finder::find_and_connect().await;
    common::peripheral_finder::reset_peripheral(&peripheral).await;

    let descriptor = find_descriptor(
        &peripheral,
        common::gatt_uuids::DESCRIPTOR_TEST_CHAR,
        common::gatt_uuids::READ_WRITE_DESCRIPTOR,
    );

    let data = vec![0x42, 0x43, 0x44];
    peripheral
        .write_descriptor(&descriptor, &data)
        .await
        .unwrap();

    let read_back = peripheral.read_descriptor(&descriptor).await.unwrap();
    assert_eq!(
        read_back, data,
        "Descriptor read-back should match written data"
    );

    peripheral.disconnect().await.unwrap();
}

#[tokio::test]
#[ignore = "requires BLE test peripheral"]
async fn test_descriptor_discovery() {
    let peripheral = common::peripheral_finder::find_and_connect().await;

    // Find the Descriptor Test Char and verify it has our custom descriptors
    let char = common::peripheral_finder::find_characteristic(
        &peripheral,
        common::gatt_uuids::DESCRIPTOR_TEST_CHAR,
    );

    let descriptor_uuids: Vec<_> = char.descriptors.iter().map(|d| d.uuid).collect();

    // Should contain our custom descriptors (may also contain CCCD etc.)
    assert!(
        descriptor_uuids.contains(&common::gatt_uuids::READ_ONLY_DESCRIPTOR),
        "Read-only descriptor not found. Found: {:?}",
        descriptor_uuids
    );
    assert!(
        descriptor_uuids.contains(&common::gatt_uuids::READ_WRITE_DESCRIPTOR),
        "Read/write descriptor not found. Found: {:?}",
        descriptor_uuids
    );

    peripheral.disconnect().await.unwrap();
}
